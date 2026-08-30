import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/player_source.dart';
import '../models/track.dart';
import 'media_store_service.dart';

/// Owns the single [AudioPlayer] and bridges it to the platform's media
/// session, which is what gives PurePlayer notification and lock-screen
/// controls and keeps playback alive in the background.
class PurePlayerAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  PurePlayerAudioHandler(this._mediaStore);

  final MediaStoreService _mediaStore;
  final AudioPlayer _player = AudioPlayer();

  /// The queue as [Track]s, kept parallel to [queue] so the UI does not have to
  /// round-trip through [MediaItem] to get at the original metadata.
  List<Track> _tracks = const [];

  PlaybackSource? _source;

  AudioPlayer get player => _player;

  List<Track> get tracks => _tracks;

  /// Where the current queue came from, or `null` if nothing is loaded.
  PlaybackSource? get source => _source;

  Track? get currentTrack {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) return null;
    return _tracks[index];
  }

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playbackEventStream
        .map(_toPlaybackState)
        .listen(playbackState.add, onError: (Object _) {});

    // just_audio 0.10 moved player errors off playbackEventStream. Swallowing
    // them here keeps a single unreadable file from tearing down the stream and
    // freezing the notification.
    _player.errorStream.listen((_) {});

    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index >= 0 && index < items.length) {
        mediaItem.add(items[index]);
        unawaited(_attachArtwork(index));
      }
    });

    // MediaStore's duration can be missing or wrong; once the decoder reports
    // the real one, correct the item the notification is showing.
    _player.durationStream.listen((duration) {
      final current = mediaItem.value;
      if (duration != null && current != null && current.duration != duration) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
  }

  /// Replaces the queue with [tracks] and cues [initialIndex].
  ///
  /// Pass `autoPlay: false` when restoring saved state on launch, so the app
  /// comes back ready to resume rather than playing on its own.
  Future<void> loadQueue(
    List<Track> tracks, {
    required PlaybackSource source,
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) {
      await clearQueue();
      return;
    }

    _tracks = List.unmodifiable(tracks);
    _source = source;

    // Built without artwork: resolving art for every entry up front would fire
    // one platform call per track before playback could even start. The
    // notification only ever shows the current item, so art is fetched for that
    // one alone, as the index changes.
    final items = [for (final track in tracks) _toMediaItem(track)];
    queue.add(items);

    final index = initialIndex.clamp(0, tracks.length - 1);
    mediaItem.add(items[index]);
    unawaited(_attachArtwork(index));

    await _player.setAudioSources(
      [for (final track in tracks) AudioSource.file(track.path)],
      initialIndex: index,
      initialPosition: initialPosition,
    );

    if (autoPlay) await _player.play();
  }

  Future<void> clearQueue() async {
    _tracks = const [];
    _source = null;
    queue.add(const []);
    mediaItem.add(null);
    await _player.stop();
    await _player.clearAudioSources();
  }

  /// Moves a queue entry, mirroring a drag-and-drop reorder in a playlist.
  Future<void> moveTrack(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _tracks.length) return;
    final target = newIndex.clamp(0, _tracks.length - 1);
    if (target == oldIndex) return;

    final tracks = [..._tracks];
    tracks.insert(target, tracks.removeAt(oldIndex));
    _tracks = List.unmodifiable(tracks);

    final items = [...queue.value];
    items.insert(target, items.removeAt(oldIndex));
    queue.add(items);

    await _player.moveAudioSource(oldIndex, target);
  }

  /// Removes the entry at [index], mirroring a removal from a playlist.
  Future<void> removeTrackAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;

    final tracks = [..._tracks]..removeAt(index);
    _tracks = List.unmodifiable(tracks);

    final items = [...queue.value]..removeAt(index);
    queue.add(items);

    await _player.removeAudioSourceAt(index);
    if (tracks.isEmpty) {
      _source = null;
      mediaItem.add(null);
      await _player.stop();
    }
  }

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.path,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration,
    extras: {'trackId': track.id},
  );

  /// Fills in the artwork URI for the queue entry at [index] and re-emits it.
  ///
  /// audio_service addresses notification artwork by URI, so the thumbnail has
  /// to be spilled to a cache file first. Silently does nothing when the track
  /// has no art, or when the user has already moved on to another one.
  Future<void> _attachArtwork(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final track = _tracks[index];

    final artUri = await _mediaStore.artworkUri(track);
    if (artUri == null) return;

    final items = queue.value;
    if (index >= items.length || items[index].id != track.path) return;

    final updated = items[index].copyWith(artUri: artUri);
    queue.add([...items]..[index] = updated);

    // Only refresh what the notification is showing if it is still this track.
    if (_player.currentIndex == index) mediaItem.add(updated);
  }

  PlaybackState _toPlaybackState(PlaybackEvent event) => PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      if (_player.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ],
    systemActions: const {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
    },
    androidCompactActionIndices: const [0, 1, 2],
    processingState: switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    },
    playing: _player.playing,
    updatePosition: _player.position,
    bufferedPosition: _player.bufferedPosition,
    speed: _player.speed,
    queueIndex: event.currentIndex,
  );

  // ------------------------------------------------- audio_service overrides

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  Future<void> dispose() => _player.dispose();
}
