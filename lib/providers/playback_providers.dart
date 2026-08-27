import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../models/player_source.dart';
import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/database.dart';
import 'library_providers.dart';

/// Always overridden in `main()`; the handler must be created before the
/// widget tree so audio_service can bind it to the platform media session.
final audioHandlerProvider = Provider<PurePlayerAudioHandler>(
  (ref) => throw UnimplementedError(
    'audioHandlerProvider must be overridden with the instance from '
    'AudioService.init()',
  ),
);

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final currentMediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);

final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);

/// The currently playing track, or `null` when the queue is empty.
final currentTrackProvider = Provider<Track?>((ref) {
  // Depend on the media item so this recomputes on every track change.
  ref.watch(currentMediaItemProvider);
  return ref.watch(audioHandlerProvider).currentTrack;
});

/// Position, buffer and duration in one value, so the seek bar rebuilds once
/// per tick instead of three times.
@immutable
class PositionData {
  const PositionData({
    required this.position,
    required this.bufferedPosition,
    required this.duration,
  });

  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  static const zero = PositionData(
    position: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: Duration.zero,
  );
}

final positionProvider = StreamProvider<PositionData>((ref) {
  final player = ref.watch(audioHandlerProvider).player;
  return Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
    player.positionStream,
    player.bufferedPositionStream,
    player.durationStream,
    (position, buffered, duration) => PositionData(
      position: position,
      bufferedPosition: buffered,
      duration: duration ?? Duration.zero,
    ),
  );
});

final playbackControllerProvider = Provider<PlaybackController>(
  PlaybackController.new,
);

/// Starts playback and keeps the resume snapshot up to date.
class PlaybackController {
  PlaybackController(this._ref) {
    // Registered once here rather than per playback start, which would stack up
    // a new dispose callback every time the user pressed play.
    _ref.onDispose(() => _saveTimer?.cancel());
  }

  /// How often the resume snapshot is rewritten while playing. Frequent enough
  /// to lose at most a few seconds, rare enough not to hammer the database.
  static const _saveInterval = Duration(seconds: 5);

  final Ref _ref;
  Timer? _saveTimer;

  PurePlayerAudioHandler get _handler => _ref.read(audioHandlerProvider);
  AppDatabase get _db => _ref.read(databaseProvider);

  /// Plays [tracks] starting at [index], replacing whatever was queued.
  Future<void> playAll(
    List<Track> tracks, {
    required PlaybackSource source,
    int index = 0,
  }) async {
    if (tracks.isEmpty) return;
    await _handler.loadQueue(tracks, source: source, initialIndex: index);
    _startAutosave();
    unawaited(saveResumeState());
  }

  Future<void> togglePlayPause() async {
    if (_handler.player.playing) {
      await _handler.pause();
      // Pausing is the natural moment to checkpoint — and there is nothing to
      // track until playback resumes, so the periodic save stops here.
      _saveTimer?.cancel();
      _saveTimer = null;
      await saveResumeState();
    } else {
      await _handler.play();
      _startAutosave();
    }
  }

  Future<void> skipToIndex(int index) async {
    await _handler.skipToQueueItem(index);
    unawaited(saveResumeState());
  }

  void _startAutosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(
      _saveInterval,
      (_) => unawaited(saveResumeState()),
    );
  }

  /// Persists the queue as track ids plus the current index and position.
  ///
  /// Ids rather than full metadata: the queue can be the whole library, and the
  /// ids are re-resolved against the next scan anyway, which also drops tracks
  /// whose files have since disappeared.
  Future<void> saveResumeState() async {
    final tracks = _handler.tracks;
    final source = _handler.source;
    if (tracks.isEmpty || source == null) return;

    final snapshot = <String, Object?>{
      'source': source.encode(),
      'trackIds': [for (final track in tracks) track.id],
      'index': _handler.player.currentIndex ?? 0,
      'positionMs': _handler.player.position.inMilliseconds,
    };
    await _db.writeState(AppDatabase.resumeStateKey, jsonEncode(snapshot));
  }

  /// Rebuilds the last session's queue, cued and paused.
  ///
  /// Returns `false` when there is nothing to restore, or when none of the
  /// saved tracks still exist in the library.
  Future<bool> restoreResumeState(List<Track> library) async {
    if (library.isEmpty) return false;

    final raw = await _db.readState(AppDatabase.resumeStateKey);
    if (raw == null) return false;

    final Map<String, Object?> snapshot;
    try {
      snapshot = jsonDecode(raw) as Map<String, Object?>;
    } on FormatException {
      return false;
    }

    final source = PlaybackSource.decode(snapshot['source'] as String?);
    if (source == null) return false;

    final byId = {for (final track in library) track.id: track};
    final savedIndex = (snapshot['index'] as num?)?.toInt() ?? 0;
    final ids = (snapshot['trackIds'] as List?)?.cast<Object?>() ?? const [];

    final tracks = <Track>[];
    var index = 0;
    for (var position = 0; position < ids.length; position++) {
      final track = byId[(ids[position] as num?)?.toInt()];
      if (track == null) continue;
      // Track the saved item's new position after any drop-outs.
      if (position == savedIndex) index = tracks.length;
      tracks.add(track);
    }
    if (tracks.isEmpty) return false;

    await _handler.loadQueue(
      tracks,
      source: source,
      initialIndex: index.clamp(0, tracks.length - 1),
      initialPosition: Duration(
        milliseconds: (snapshot['positionMs'] as num?)?.toInt() ?? 0,
      ),
      autoPlay: false,
    );
    return true;
  }
}
