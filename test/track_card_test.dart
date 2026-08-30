import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureplayer/models/track.dart';
import 'package:pureplayer/services/media_store_service.dart';
import 'package:pureplayer/theme/app_theme.dart';
import 'package:pureplayer/widgets/track_card.dart';

const _track = Track(
  id: 1,
  title: 'Still Water',
  artist: 'Ana Reef',
  album: 'Tide',
  albumId: 9,
  duration: Duration(minutes: 3, seconds: 25),
  path: '/music/still-water.mp3',
  dateAdded: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MediaStoreService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    // No artwork on the platform side, so AlbumArt renders its placeholder.
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );

  testWidgets('shows title, artist and formatted duration', (tester) async {
    await pump(tester, const TrackCard(track: _track));
    await tester.pumpAndSettle();

    expect(find.text('Still Water'), findsOneWidget);
    expect(find.text('Ana Reef'), findsOneWidget);
    expect(find.text('3:25'), findsOneWidget);
  });

  testWidgets('falls back to the placeholder when a track has no art', (
    tester,
  ) async {
    await pump(tester, const TrackCard(track: _track));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('calls onTap when the row is tapped', (tester) async {
    var taps = 0;
    await pump(tester, TrackCard(track: _track, onTap: () => taps++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Still Water'));
    expect(taps, 1);
  });

  testWidgets('a missing file is shown greyed out and is not tappable', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      TrackCard(track: _track, missing: true, onTap: () => taps++),
    );
    await tester.pumpAndSettle();

    expect(find.text('File missing'), findsOneWidget);
    expect(find.text('Ana Reef'), findsNothing);

    await tester.tap(find.text('Still Water'));
    expect(taps, 0);
  });
}
