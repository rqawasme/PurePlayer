import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// Dart side of the app's own `MediaStore` platform channel.
///
/// See `android/app/src/main/kotlin/com/pureplayer/app/MediaStorePlugin.kt` for
/// the implementation.
class MediaStoreService {
  MediaStoreService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.pureplayer.app/media_store';
  static const artworkSize = 256;

  /// Number of decoded thumbnails held in memory. Bounded so that scrolling a
  /// large library cannot grow the heap without limit.
  static const _artCacheLimit = 150;

  final MethodChannel _channel;

  /// Insertion-ordered, so the first key is always the least recently used.
  final LinkedHashMap<int, Uint8List?> _artCache = LinkedHashMap();
  Directory? _artDirectory;

  /// The device's API level, used to pick the right runtime permission.
  Future<int> sdkInt() async => await _channel.invokeMethod<int>('sdkInt') ?? 0;

  Future<List<Track>> queryTracks() async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('queryTracks') ??
        const [];
    return rows.map(Track.fromPlatform).toList();
  }

  /// Album art for [track], or `null` when it has none.
  ///
  /// Results are memoised — including the `null` misses, which are otherwise
  /// the most expensive case, since a track without art would be re-queried on
  /// every rebuild.
  Future<Uint8List?> artwork(Track track) async {
    if (_artCache.containsKey(track.id)) {
      // Re-insert to mark this entry as most recently used.
      final cached = _artCache.remove(track.id);
      _artCache[track.id] = cached;
      return cached;
    }

    Uint8List? bytes;
    try {
      bytes = await _channel.invokeMethod<Uint8List>('queryArtwork', {
        'songId': track.id,
        'albumId': track.albumId,
        'size': artworkSize,
      });
    } on PlatformException {
      // Treat an unreadable thumbnail as "no artwork" — the UI shows its
      // placeholder either way, and this must not break the list.
      bytes = null;
    }

    _artCache[track.id] = bytes;
    if (_artCache.length > _artCacheLimit) {
      _artCache.remove(_artCache.keys.first);
    }
    return bytes;
  }

  /// Writes [track]'s artwork to the cache directory and returns a `file://`
  /// URI for it.
  ///
  /// audio_service addresses notification artwork by URI rather than by bytes,
  /// so the thumbnail has to exist as a file on disk.
  Future<Uri?> artworkUri(Track track) async {
    final bytes = await artwork(track);
    if (bytes == null || bytes.isEmpty) return null;

    final directory = _artDirectory ??= await _createArtDirectory();
    final file = File(p.join(directory.path, '${track.id}.jpg'));
    try {
      if (!file.existsSync() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.uri;
    } on FileSystemException {
      return null;
    }
  }

  Future<Directory> _createArtDirectory() async {
    final cache = await getTemporaryDirectory();
    final directory = Directory(p.join(cache.path, 'artwork'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @visibleForTesting
  void clearCache() => _artCache.clear();
}
