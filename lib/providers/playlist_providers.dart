import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player_source.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/database.dart';
import 'library_providers.dart';
import 'playback_providers.dart';

/// All playlists, most recently touched first.
final playlistsProvider = FutureProvider<List<Playlist>>(
  (ref) => ref.watch(databaseProvider).playlists(),
);

/// The ordered contents of one playlist.
final playlistEntriesProvider = FutureProvider.family<List<PlaylistEntry>, int>(
  (ref, playlistId) => ref.watch(databaseProvider).entries(playlistId),
);

final playlistControllerProvider = Provider<PlaylistController>(
  PlaylistController.new,
);

/// Every playlist mutation goes through here so that persistence, provider
/// invalidation, and the live playback queue stay in step.
class PlaylistController {
  PlaylistController(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  void _invalidate(int playlistId) {
    _ref.invalidate(playlistEntriesProvider(playlistId));
    _ref.invalidate(playlistsProvider);
  }

  Future<int> create(String name) async {
    final id = await _db.createPlaylist(name);
    _ref.invalidate(playlistsProvider);
    return id;
  }

  Future<void> rename(int playlistId, String name) async {
    await _db.renamePlaylist(playlistId, name);
    _invalidate(playlistId);
  }

  Future<void> delete(int playlistId) async {
    await _db.deletePlaylist(playlistId);
    _invalidate(playlistId);
  }

  /// Returns how many tracks were actually added — the rest were already there.
  Future<int> addTracks(int playlistId, List<Track> tracks) async {
    final added = await _db.addTracks(playlistId, tracks);
    _invalidate(playlistId);
    return added;
  }

  Future<void> removeTrack(int playlistId, int trackId) async {
    await _db.removeTrack(playlistId, trackId);
    _invalidate(playlistId);

    // Keep the queue honest if this playlist is the one currently playing.
    final handler = _ref.read(audioHandlerProvider);
    if (handler.source == PlaylistSource(playlistId)) {
      final index = handler.tracks.indexWhere((track) => track.id == trackId);
      if (index >= 0) await handler.removeTrackAt(index);
    }
  }

  /// Applies a drag-and-drop reorder.
  ///
  /// Both indices are final positions in the playlist's order — the caller uses
  /// `ReorderableListView.onReorderItem`, which has already accounted for the
  /// dragged row leaving its old slot.
  Future<void> reorder(int playlistId, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;

    await _db.reorder(playlistId, oldIndex, newIndex);
    _invalidate(playlistId);

    final handler = _ref.read(audioHandlerProvider);
    if (handler.source == PlaylistSource(playlistId)) {
      await handler.moveTrack(oldIndex, newIndex);
    }
  }
}
