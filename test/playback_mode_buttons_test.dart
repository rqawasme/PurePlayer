import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureplayer/providers/playback_providers.dart';
import 'package:pureplayer/theme/app_theme.dart';
import 'package:pureplayer/widgets/playback_mode_buttons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Renders the two buttons against a fixed media-session state, which is
  /// what they read their own state from.
  Future<void> pump(WidgetTester tester, PlaybackState state) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackStateProvider.overrideWith((ref) => Stream.value(state)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Row(children: [ShuffleButton(), RepeatButton()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an untouched session reads as shuffle off, repeat off', (
    tester,
  ) async {
    await pump(tester, PlaybackState());

    expect(find.byTooltip('Shuffle off'), findsOneWidget);
    expect(find.byTooltip('Repeat off'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
  });

  testWidgets('shuffle and repeat-all are picked up from the session', (
    tester,
  ) async {
    await pump(
      tester,
      PlaybackState(
        shuffleMode: AudioServiceShuffleMode.all,
        repeatMode: AudioServiceRepeatMode.all,
      ),
    );

    expect(find.byTooltip('Shuffle on'), findsOneWidget);
    expect(find.byTooltip('Repeat all'), findsOneWidget);
    // Repeat-all shares the plain glyph with off; the tooltip and colour are
    // what tell them apart.
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
  });

  testWidgets('repeat-one gets its own glyph', (tester) async {
    await pump(tester, PlaybackState(repeatMode: AudioServiceRepeatMode.one));

    expect(find.byTooltip('Repeat one'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsNothing);
  });
}
