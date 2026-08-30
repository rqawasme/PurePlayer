import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/playlist.dart';
import '../models/track.dart';

/// All local persistence: custom playlists, their ordering, and the small
/// key/value blobs used to restore app state on relaunch.
///
/// No network, no analytics — this database is the app's only storage.
class AppDatabase {
  AppDatabase({this.factoryOverride, this.pathOverride});

  static const fileName = 'pureplayer.db';
  static const _schemaVersion = 1;

  /// Key under which the library sort choice is stored in `app_state`.
  static const sortStateKey = 'library_sort';

  /// Key under which the resume queue/position is stored in `app_state`.
  static const resumeStateKey = 'resume';

  /// Injected by tests so the schema can be exercised against desktop SQLite.
  final DatabaseFactory? factoryOverride;
  final String? pathOverride;

  Database? _database;
  Completer<Database>? _opening;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    // Guard against two callers racing to open the database on first use.
    final inFlight = _opening;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<Database>();
    _opening = completer;
    try {
      final database = await _open();
      _database = database;
      completer.complete(database);
      return database;
    } catch (error, stackTrace) {
      _opening = null;
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  Future<Database> _open() async {
    final factory = factoryOverride ?? databaseFactory;
    final path =
        pathOverride ?? p.join(await factory.getDatabasesPath(), fileName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          final batch = db.batch();
          batch.execute('''
            CREATE TABLE playlists (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          batch.execute('''
            CREATE TABLE playlist_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              playlist_id INTEGER NOT NULL
                REFERENCES playlists (id) ON DELETE CASCADE,
              track_id INTEGER NOT NULL,
              path TEXT NOT NULL,
              title TEXT,
              artist TEXT,
              album TEXT,
              album_id INTEGER,
              duration_ms INTEGER,
              date_added INTEGER,
              position INTEGER NOT NULL
            )
          ''');
          // A track appears at most once per playlist...
          batch.execute(
            'CREATE UNIQUE INDEX idx_items_unique '
            'ON playlist_items (playlist_id, track_id)',
          );
          // ...and playlists are almost always read in position order.
          batch.execute(
            'CREATE INDEX idx_items_order '
            'ON playlist_items (playlist_id, position)',
          );
          batch.execute('''
            CREATE TABLE app_state (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await batch.commit(noResult: true);
        },
      ),
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _opening = null;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- playlists

  Future<List<Playlist>> playlists() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.created_at, p.updated_at,
             COUNT(i.id) AS track_count,
             COALESCE(SUM(i.duration_ms), 0) AS total_duration_ms
      FROM playlists p
      LEFT JOIN playlist_items i ON i.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.updated_at DESC
    ''');
    return rows.map(Playlist.fromDbMap).toList();
  }

  Future<int> createPlaylist(String name) async {
    final db = await database;
    final now = _now();
    return db.insert('playlists', {
      'name': name.trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> renamePlaylist(int playlistId, String name) async {
    final db = await database;
    await db.update(
      'playlists',
      {'name': name.trim(), 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  /// Items go too, via `ON DELETE CASCADE` (see `PRAGMA foreign_keys` above).
  Future<void> deletePlaylist(int playlistId) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  Future<void> _touch(DatabaseExecutor db, int playlistId) => db.update(
    'playlists',
    {'updated_at': _now()},
    where: 'id = ?',
    whereArgs: [playlistId],
  );

  // ------------------------------------------------------------------- items

  Future<List<PlaylistEntry>> entries(int playlistId) async {
    final db = await database;
    final rows = await db.query(
      'playlist_items',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return rows.map(PlaylistEntry.fromDbMap).toList();
  }

  /// Appends [tracks], skipping any already present.
  ///
  /// Returns the number actually added, so the UI can say "3 added, 1 already
  /// in playlist" rather than silently dropping duplicates.
  Future<int> addTracks(int playlistId, List<Track> tracks) async {
    if (tracks.isEmpty) return 0;
    final db = await database;
    var added = 0;
    await db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) AS max_position '
        'FROM playlist_items WHERE playlist_id = ?',
        [playlistId],
      );
      var position =
          ((result.first['max_position'] as num?)?.toInt() ?? -1) + 1;

      for (final track in tracks) {
        final rowId = await txn.insert('playlist_items', {
          'playlist_id': playlistId,
          'position': position,
          ...track.toDbMap(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        // insert() returns 0 when the unique index rejected a duplicate.
        if (rowId != 0) {
          position++;
          added++;
        }
      }
      await _touch(txn, playlistId);
    });
    return added;
  }

  Future<void> removeTrack(int playlistId, int trackId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'playlist_items',
        where: 'playlist_id = ? AND track_id = ?',
        whereArgs: [playlistId, trackId],
      );
      await _renumber(txn, playlistId);
      await _touch(txn, playlistId);
    });
  }

  /// Moves the item at [oldIndex] to [newIndex], both zero-based positions in
  /// the playlist's current order.
  Future<void> reorder(int playlistId, int oldIndex, int newIndex) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'playlist_items',
        columns: ['id'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC',
      );
      final ids = rows.map((row) => (row['id'] as num).toInt()).toList();
      if (oldIndex < 0 || oldIndex >= ids.length) return;

      final target = newIndex.clamp(0, ids.length - 1);
      if (target == oldIndex) return;

      ids.insert(target, ids.removeAt(oldIndex));
      for (var index = 0; index < ids.length; index++) {
        await txn.update(
          'playlist_items',
          {'position': index},
          where: 'id = ?',
          whereArgs: [ids[index]],
        );
      }
      await _touch(txn, playlistId);
    });
  }

  /// Rewrites positions to a dense 0..n-1 range after a removal.
  Future<void> _renumber(DatabaseExecutor db, int playlistId) async {
    final rows = await db.query(
      'playlist_items',
      columns: ['id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    for (var index = 0; index < rows.length; index++) {
      await db.update(
        'playlist_items',
        {'position': index},
        where: 'id = ?',
        whereArgs: [(rows[index]['id'] as num).toInt()],
      );
    }
  }

  // --------------------------------------------------------------- app state

  Future<String?> readState(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeState(String key, String value) async {
    final db = await database;
    await db.insert('app_state', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
