import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playback_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/playback_mode_buttons.dart';
import '../widgets/seek_bar.dart';

/// Full-screen now-playing view: art, metadata, scrub bar and transport.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final track = ref.watch(currentTrackProvider);
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final position = ref.watch(positionProvider).value ?? PositionData.zero;
    final handler = ref.watch(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Now playing'),
      ),
      body: track == null
          ? const Center(child: Text('Nothing is playing.'))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Keep the art square and inside the viewport on short
                        // screens as well as wide ones.
                        final side = constraints.maxWidth.clamp(0.0, 340.0);
                        return AlbumArt(track: track, size: side, radius: 28);
                      },
                    ),
                    const SizedBox(height: 36),
                    Text(
                      track.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.artist,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SeekBar(
                      position: position.position,
                      duration: position.duration == Duration.zero
                          ? track.duration
                          : position.duration,
                      onSeek: handler.seek,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const ShuffleButton(iconSize: 28),
                        IconButton(
                          iconSize: 44,
                          tooltip: 'Previous',
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: handler.skipToPrevious,
                        ),
                        FilledButton(
                          onPressed: () => ref
                              .read(playbackControllerProvider)
                              .togglePlayPause(),
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(20),
                          ),
                          child: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 40,
                          ),
                        ),
                        IconButton(
                          iconSize: 44,
                          tooltip: 'Next',
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: handler.skipToNext,
                        ),
                        const RepeatButton(iconSize: 28),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
    );
  }
}
