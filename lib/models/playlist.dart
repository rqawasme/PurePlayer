import 'package:flutter/foundation.dart';

import 'track.dart';

/// A user-created playlist. [trackCount] and [totalDuration] are computed by
/// the query that loads it rather than stored, so they cannot drift.
@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.trackCount = 0,
    this.totalDuration = Duration.zero,
  });

  final int id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int trackCount;
  final Duration totalDuration;

  factory Playlist.fromDbMap(Map<String, Object?> map) => Playlist(
    id: (map['id'] as num).toInt(),
    name: (map['name'] as String?) ?? 'Untitled',
    createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
    updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    trackCount: (map['track_count'] as num?)?.toInt() ?? 0,
    totalDuration: Duration(
      milliseconds: (map['total_duration_ms'] as num?)?.toInt() ?? 0,
    ),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.id == id &&
          other.name == name &&
          other.updatedAt == updatedAt &&
          other.trackCount == trackCount);

  @override
  int get hashCode => Object.hash(id, name, updatedAt, trackCount);
}

/// One row of `playlist_items`: a [Track] plus its place in a playlist.
///
/// The track metadata is denormalised into the row, so a playlist renders
/// immediately on launch without waiting for a library scan — and a track whose
/// file has since been deleted still appears, flagged via [missing], instead of
/// silently disappearing.
@immutable
class PlaylistEntry {
  const PlaylistEntry({
    required this.rowId,
    required this.playlistId,
    required this.position,
    required this.track,
  });

  final int rowId;
  final int playlistId;
  final int position;
  final Track track;

  factory PlaylistEntry.fromDbMap(Map<String, Object?> map) => PlaylistEntry(
    rowId: (map['id'] as num).toInt(),
    playlistId: (map['playlist_id'] as num).toInt(),
    position: (map['position'] as num).toInt(),
    track: Track.fromDbMap(map),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistEntry &&
          other.rowId == rowId &&
          other.position == position &&
          other.track == track);

  @override
  int get hashCode => Object.hash(rowId, position, track);
}
