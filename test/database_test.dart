import 'package:flutter_test/flutter_test.dart';
import 'package:pureplayer/models/track.dart';
import 'package:pureplayer/services/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track track(int id, {String title = 'Track', int seconds = 60}) => Track(
  id: id,
  title: '$title $id',
  artist: 'Artist $id',
  album: 'Album',
  albumId: id,
  duration: Duration(seconds: seconds),
  path: '/music/$id.mp3',
  dateAdded: id,
);

void main() {
  sqfliteFfiInit();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: inMemoryDatabasePath,
    );
  });

  tearDown(() => db.close());

  Future<List<int>> trackIds(int playlistId) async =>
      (await db.entries(playlistId)).map((entry) => entry.track.id).toList();

  group('playlists', () {
    test('create, rename and delete', () async {
      final id = await db.createPlaylist('  Morning  ');
      expect((await db.playlists()).single.name, 'Morning');

      await db.renamePlaylist(id, 'Evening');
      expect((await db.playlists()).single.name, 'Evening');

      await db.deletePlaylist(id);
      expect(await db.playlists(), isEmpty);
    });

    test('reports track count and total duration', () async {
      final id = await db.createPlaylist('Mix');
      await db.addTracks(id, [track(1, seconds: 60), track(2, seconds: 90)]);

      final playlist = (await db.playlists()).single;
      expect(playlist.trackCount, 2);
      expect(playlist.totalDuration, const Duration(seconds: 150));
    });

    test('deleting a playlist cascades to its items', () async {
      final id = await db.createPlaylist('Mix');
      await db.addTracks(id, [track(1)]);
      await db.deletePlaylist(id);
      expect(await db.entries(id), isEmpty);
    });
  });

  group('items', () {
    test('appends in order and reports how many were added', () async {
      final id = await db.createPlaylist('Mix');
      expect(await db.addTracks(id, [track(1), track(2)]), 2);
      expect(await trackIds(id), [1, 2]);
    });

    test('ignores duplicates without disturbing the order', () async {
      final id = await db.createPlaylist('Mix');
      await db.addTracks(id, [track(1), track(2)]);

      expect(await db.addTracks(id, [track(2), track(3)]), 1);
      expect(await trackIds(id), [1, 2, 3]);
    });

    test('removing an item renumbers the rest densely', () async {
      final id = await db.createPlaylist('Mix');
      await db.addTracks(id, [track(1), track(2), track(3)]);

      await db.removeTrack(id, 2);

      final entries = await db.entries(id);
      expect(entries.map((entry) => entry.track.id), [1, 3]);
      expect(entries.map((entry) => entry.position), [0, 1]);
    });

    test(
      'keeps denormalised metadata so playlists render without a scan',
      () async {
        final id = await db.createPlaylist('Mix');
        await db.addTracks(id, [track(7, title: 'Ripple', seconds: 123)]);

        final entry = (await db.entries(id)).single;
        expect(entry.track.title, 'Ripple 7');
        expect(entry.track.duration, const Duration(seconds: 123));
        expect(entry.track.path, '/music/7.mp3');
      },
    );
  });

  group('reorder', () {
    late int id;

    setUp(() async {
      id = await db.createPlaylist('Mix');
      await db.addTracks(id, [track(1), track(2), track(3), track(4)]);
    });

    test('moves an item downwards', () async {
      await db.reorder(id, 0, 2);
      expect(await trackIds(id), [2, 3, 1, 4]);
    });

    test('moves an item upwards', () async {
      await db.reorder(id, 3, 0);
      expect(await trackIds(id), [4, 1, 2, 3]);
    });

    test('leaves positions dense after a move', () async {
      await db.reorder(id, 1, 3);
      final entries = await db.entries(id);
      expect(entries.map((entry) => entry.position), [0, 1, 2, 3]);
    });

    test('is a no-op for the same index or an out-of-range one', () async {
      await db.reorder(id, 1, 1);
      expect(await trackIds(id), [1, 2, 3, 4]);

      await db.reorder(id, 9, 0);
      expect(await trackIds(id), [1, 2, 3, 4]);
    });

    test('clamps a target index past the end', () async {
      await db.reorder(id, 0, 99);
      expect(await trackIds(id), [2, 3, 4, 1]);
    });
  });

  group('app_state', () {
    test('returns null for a key that was never written', () async {
      expect(await db.readState('missing'), isNull);
    });

    test('writes and overwrites a value', () async {
      await db.writeState(AppDatabase.resumeStateKey, '{"index":1}');
      expect(await db.readState(AppDatabase.resumeStateKey), '{"index":1}');

      await db.writeState(AppDatabase.resumeStateKey, '{"index":2}');
      expect(await db.readState(AppDatabase.resumeStateKey), '{"index":2}');
    });
  });
}
