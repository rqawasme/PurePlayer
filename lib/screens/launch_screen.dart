import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import 'home_screen.dart';

/// Shown while permissions are checked and the first scan runs.
///
/// Deliberately static — app name and a play mark, no animation.
class LaunchScreen extends ConsumerStatefulWidget {
  const LaunchScreen({super.key});

  @override
  ConsumerState<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends ConsumerState<LaunchScreen>
    with WidgetsBindingObserver {
  bool _resumeAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system settings page is the usual way a
    // permanently-denied permission gets granted, so re-check on resume.
    if (state == AppLifecycleState.resumed) {
      ref.read(permissionProvider.notifier).recheck();
    }
  }

  /// Restores the previous queue once, as soon as a library is available.
  ///
  /// Deferred to after the frame: this is triggered from `build`, and loading a
  /// queue mid-build would mutate state the tree is still being built from.
  void _maybeRestore() {
    if (_resumeAttempted) return;
    final tracks = ref.read(libraryProvider).value;
    if (tracks == null || tracks.isEmpty) return;
    _resumeAttempted = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(playbackControllerProvider).restoreResumeState(tracks);
    });
  }

  @override
  Widget build(BuildContext context) {
    final permission = ref.watch(permissionProvider);
    final library = ref.watch(libraryProvider);

    if (permission.value == LibraryPermission.granted && library.hasValue) {
      _maybeRestore();
      return const HomeScreen();
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Wordmark(),
                const SizedBox(height: 40),
                switch (permission) {
                  AsyncData(value: LibraryPermission.denied) => _PermissionGate(
                    detail:
                        'PurePlayer needs access to the audio on this device '
                        'to build your library. Nothing leaves your phone.',
                    actionLabel: 'Grant access',
                    onPressed: () =>
                        ref.read(permissionProvider.notifier).request(),
                  ),
                  AsyncData(value: LibraryPermission.permanentlyDenied) =>
                    _PermissionGate(
                      detail:
                          'Audio access is turned off for PurePlayer. Enable '
                          'it in app settings to see your music.',
                      actionLabel: 'Open settings',
                      onPressed: () =>
                          ref.read(permissionProvider.notifier).openSettings(),
                    ),
                  AsyncError(:final error) => _PermissionGate(
                    detail: 'Something went wrong: $error',
                    actionLabel: 'Try again',
                    onPressed: () =>
                        ref.read(permissionProvider.notifier).request(),
                  ),
                  _ => const CircularProgressIndicator(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: 56,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'PurePlayer',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _PermissionGate extends StatelessWidget {
  const _PermissionGate({
    required this.detail,
    required this.actionLabel,
    required this.onPressed,
  });

  final String detail;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          detail,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: onPressed, child: Text(actionLabel)),
      ],
    );
  }
}
