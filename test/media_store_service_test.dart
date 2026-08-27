import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureplayer/models/track.dart';
import 'package:pureplayer/services/media_store_service.dart';

const _track = Track(
  id: 12,
  title: 'Ripple',
  artist: 'Ocean',
  album: 'Tide',
  albumId: 4,
  duration: Duration(seconds: 60),
  path: '/music/ripple.mp3',
  dateAdded: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MediaStoreService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  /// Installs [handler] as the platform side and records every call made.
  void stub(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('maps MediaStore rows onto tracks', () async {
    stub(
      (_) async => [
        {
          'id': 12,
          'title': 'Ripple',
          'artist': 'Ocean',
          'album': 'Tide',
          'albumId': 4,
          'durationMs': 185000,
          'path': '/music/ripple.mp3',
          'dateAdded': 1700000000,
          'size': 4096,
        },
      ],
    );

    final track = (await MediaStoreService().queryTracks()).single;

    expect(track.id, 12);
    expect(track.title, 'Ripple');
    expect(track.artist, 'Ocean');
    expect(track.albumId, 4);
    expect(track.duration, const Duration(milliseconds: 185000));
    expect(track.path, '/music/ripple.mp3');
    expect(track.size, 4096);
  });

  test(
    'replaces MediaStore\'s "<unknown>" tags with readable fallbacks',
    () async {
      stub(
        (_) async => [
          {
            'id': 1,
            'title': null,
            'artist': '<unknown>',
            'album': '   ',
            'albumId': null,
            'durationMs': 1000,
            'path': '/music/no-tags.mp3',
            'dateAdded': 0,
          },
        ],
      );

      final track = (await MediaStoreService().queryTracks()).single;

      // A missing title falls back to the filename, not a generic placeholder.
      expect(track.title, 'no-tags');
      expect(track.artist, 'Unknown artist');
      expect(track.album, 'Unknown album');
    },
  );

  test('returns an empty library when the scan finds nothing', () async {
    stub((_) async => <Object?>[]);
    expect(await MediaStoreService().queryTracks(), isEmpty);
  });

  test('reports the device API level', () async {
    stub((_) async => 34);
    expect(await MediaStoreService().sdkInt(), 34);
  });

  group('artwork', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    test('memoises hits so scrolling does not re-query', () async {
      stub((_) async => bytes);
      final service = MediaStoreService();

      expect(await service.artwork(_track), bytes);
      expect(await service.artwork(_track), bytes);
      expect(calls, hasLength(1));
    });

    test(
      'memoises misses too — otherwise the worst case re-queries forever',
      () async {
        stub((_) async => null);
        final service = MediaStoreService();

        expect(await service.artwork(_track), isNull);
        expect(await service.artwork(_track), isNull);
        expect(calls, hasLength(1));
      },
    );

    test('passes the song and album ids through to the platform', () async {
      stub((_) async => bytes);
      await MediaStoreService().artwork(_track);

      expect(calls.single.method, 'queryArtwork');
      expect(calls.single.arguments, {
        'songId': 12,
        'albumId': 4,
        'size': MediaStoreService.artworkSize,
      });
    });

    test(
      'treats a platform failure as "no artwork" rather than throwing',
      () async {
        stub((_) => throw PlatformException(code: 'media_store_error'));
        expect(await MediaStoreService().artwork(_track), isNull);
      },
    );
  });
}
