import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/library_providers.dart';
import 'providers/playback_providers.dart';
import 'screens/launch_screen.dart';
import 'services/audio_handler.dart';
import 'services/database.dart';
import 'services/media_store_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both are shared with the audio handler, which is built before the widget
  // tree exists — hence the provider overrides below rather than plain
  // provider defaults.
  final mediaStore = MediaStoreService();
  final database = AppDatabase();

  // Binds the handler to the platform media session, which is what keeps
  // playback running in the background and puts controls on the lock screen.
  final handler = await AudioService.init(
    builder: () => PurePlayerAudioHandler(mediaStore),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.pureplayer.app.channel.audio',
      androidNotificationChannelName: 'PurePlayer playback',
      androidNotificationChannelDescription: 'Controls for the current track',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  await handler.init();

  runApp(
    ProviderScope(
      overrides: [
        mediaStoreProvider.overrideWithValue(mediaStore),
        databaseProvider.overrideWithValue(database),
        audioHandlerProvider.overrideWithValue(handler),
      ],
      child: const PurePlayerApp(),
    ),
  );
}

class PurePlayerApp extends StatelessWidget {
  const PurePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PurePlayer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Light mode only, by design — no darkTheme is supplied.
      themeMode: ThemeMode.light,
      home: const LaunchScreen(),
    );
  }
}
