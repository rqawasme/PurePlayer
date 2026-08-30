import 'package:flutter/foundation.dart';

/// A single audio track discovered on the device.
///
/// Instances come either from a `MediaStore` scan (see
/// `MediaStoreService.queryTracks`) or from the denormalised copy of the
/// metadata kept in the `playlist_items` table, which lets playlists render
/// before — or without — a fresh library scan.
@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.duration,
    required this.path,
    required this.dateAdded,
    this.size = 0,
  });

  /// `MediaStore.Audio.Media._ID`. Stable for as long as the file is indexed.
  final int id;
  final String title;
  final String artist;
  final String album;

  /// `MediaStore.Audio.Media.ALBUM_ID`, used for the pre-API-29 artwork path.
  final int? albumId;
  final Duration duration;
  final String path;

  /// `MediaStore.Audio.Media.DATE_ADDED`, in seconds since the epoch.
  final int dateAdded;

  /// File size in bytes. Zero when unknown (e.g. restored from a playlist row).
  final int size;

  DateTime get dateAddedTime =>
      DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000);

  /// MediaStore reports missing tags as the literal string `<unknown>`.
  static String _clean(Object? value, String fallback) {
    final text = (value as String?)?.trim();
    if (text == null || text.isEmpty || text == '<unknown>') return fallback;
    return text;
  }

  /// Builds a track from the map returned by the `queryTracks` platform call.
  factory Track.fromPlatform(Map<Object?, Object?> map) {
    final path = (map['path'] as String?) ?? '';
    return Track(
      id: (map['id'] as num).toInt(),
      title: _clean(map['title'], _titleFromPath(path)),
      artist: _clean(map['artist'], 'Unknown artist'),
      album: _clean(map['album'], 'Unknown album'),
      albumId: (map['albumId'] as num?)?.toInt(),
      duration: Duration(
        milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0,
      ),
      path: path,
      dateAdded: (map['dateAdded'] as num?)?.toInt() ?? 0,
      size: (map['size'] as num?)?.toInt() ?? 0,
    );
  }

  static String _titleFromPath(String path) {
    if (path.isEmpty) return 'Unknown title';
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Map<String, Object?> toDbMap() => {
    'track_id': id,
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'album_id': albumId,
    'duration_ms': duration.inMilliseconds,
    'date_added': dateAdded,
  };

  factory Track.fromDbMap(Map<String, Object?> map) => Track(
    id: (map['track_id'] as num).toInt(),
    title: _clean(map['title'], 'Unknown title'),
    artist: _clean(map['artist'], 'Unknown artist'),
    album: _clean(map['album'], 'Unknown album'),
    albumId: (map['album_id'] as num?)?.toInt(),
    duration: Duration(
      milliseconds: (map['duration_ms'] as num?)?.toInt() ?? 0,
    ),
    path: (map['path'] as String?) ?? '',
    dateAdded: (map['date_added'] as num?)?.toInt() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track && other.id == id && other.path == path);

  @override
  int get hashCode => Object.hash(id, path);

  @override
  String toString() => 'Track($id, $title)';
}

/// `mm:ss`, or `h:mm:ss` once past an hour.
String formatDuration(Duration duration) {
  final total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  return '$minutes:$ss';
}
