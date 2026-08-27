import 'package:flutter/foundation.dart';

/// Where the current queue came from.
///
/// Persisted with the resume state, and used to decide whether reordering a
/// playlist should also reorder the live playback queue.
@immutable
sealed class PlaybackSource {
  const PlaybackSource();

  String encode();

  static PlaybackSource? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value == 'library') return const LibrarySource();
    if (value.startsWith('playlist:')) {
      final id = int.tryParse(value.substring('playlist:'.length));
      return id == null ? null : PlaylistSource(id);
    }
    return null;
  }
}

class LibrarySource extends PlaybackSource {
  const LibrarySource();

  @override
  String encode() => 'library';

  @override
  bool operator ==(Object other) => other is LibrarySource;

  @override
  int get hashCode => 'library'.hashCode;
}

class PlaylistSource extends PlaybackSource {
  const PlaylistSource(this.playlistId);

  final int playlistId;

  @override
  String encode() => 'playlist:$playlistId';

  @override
  bool operator ==(Object other) =>
      other is PlaylistSource && other.playlistId == playlistId;

  @override
  int get hashCode => Object.hash('playlist', playlistId);
}
