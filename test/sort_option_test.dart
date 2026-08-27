import 'package:flutter_test/flutter_test.dart';
import 'package:pureplayer/models/sort_option.dart';
import 'package:pureplayer/models/track.dart';

Track track({
  required int id,
  String title = 'Title',
  String artist = 'Artist',
  String album = 'Album',
  int seconds = 60,
  int dateAdded = 0,
}) => Track(
  id: id,
  title: title,
  artist: artist,
  album: album,
  albumId: null,
  duration: Duration(seconds: seconds),
  path: '/music/$id.mp3',
  dateAdded: dateAdded,
);

void main() {
  final tracks = [
    track(id: 1, title: 'Delta', artist: 'Zoe', seconds: 300, dateAdded: 30),
    track(id: 2, title: 'alpha', artist: 'Ana', seconds: 100, dateAdded: 10),
    track(id: 3, title: 'Charlie', artist: 'ana', seconds: 200, dateAdded: 20),
  ];

  group('searchTracks', () {
    test('returns everything for an empty or blank query', () {
      expect(searchTracks(tracks, ''), hasLength(3));
      expect(searchTracks(tracks, '   '), hasLength(3));
    });

    test('matches title, artist and album case-insensitively', () {
      expect(searchTracks(tracks, 'ALPHA').single.id, 2);
      expect(searchTracks(tracks, 'ana').map((t) => t.id), containsAll([2, 3]));
      expect(searchTracks(tracks, 'album'), hasLength(3));
    });

    test('returns an empty list when nothing matches', () {
      expect(searchTracks(tracks, 'nonexistent'), isEmpty);
    });
  });

  group('sortTracks', () {
    test('sorts by title case-insensitively', () {
      expect(sortTracks(tracks, const SortOption()).map((t) => t.title), [
        'alpha',
        'Charlie',
        'Delta',
      ]);
    });

    test('reverses when ascending is false', () {
      expect(
        sortTracks(
          tracks,
          const SortOption(ascending: false),
        ).map((t) => t.title),
        ['Delta', 'Charlie', 'alpha'],
      );
    });

    test('sorts by duration and by date added', () {
      expect(
        sortTracks(
          tracks,
          const SortOption(field: SortField.duration),
        ).map((t) => t.id),
        [2, 3, 1],
      );
      expect(
        sortTracks(
          tracks,
          const SortOption(field: SortField.dateAdded, ascending: false),
        ).map((t) => t.id),
        [1, 3, 2],
      );
    });

    test('breaks ties by title, ascending, even when reversed', () {
      final tied = [
        track(id: 1, title: 'Beta', artist: 'Same', seconds: 90),
        track(id: 2, title: 'Alpha', artist: 'Same', seconds: 90),
      ];
      expect(
        sortTracks(
          tied,
          const SortOption(field: SortField.artist, ascending: false),
        ).map((t) => t.title),
        ['Alpha', 'Beta'],
      );
    });

    test('leaves the input list untouched', () {
      final input = [...tracks];
      sortTracks(input, const SortOption(field: SortField.duration));
      expect(input.map((t) => t.id), [1, 2, 3]);
    });
  });

  test('queryTracks searches before sorting', () {
    final result = queryTracks(
      tracks,
      'ana',
      const SortOption(field: SortField.duration),
    );
    expect(result.map((t) => t.id), [2, 3]);
  });

  group('SortOption serialisation', () {
    test('round-trips through JSON', () {
      const option = SortOption(field: SortField.dateAdded, ascending: false);
      expect(SortOption.fromJson(option.toJson()), option);
    });

    test('falls back to title for an unknown field', () {
      expect(
        SortOption.fromJson({'field': 'bogus', 'ascending': true}).field,
        SortField.title,
      );
    });
  });

  group('formatDuration', () {
    test('formats minutes and hours', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('clamps negative durations to zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });
}
