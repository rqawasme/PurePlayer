import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playback_providers.dart';

/// Toggles shuffle for the current queue.
///
/// Lit in the accent colour when on, so the state is readable at a glance
/// without a label next to it.
class ShuffleButton extends ConsumerWidget {
  const ShuffleButton({this.iconSize = 24, super.key});

  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(playbackModeProvider);
    final shuffle = mode.shuffle;

    return IconButton(
      iconSize: iconSize,
      tooltip: mode.shuffleLabel,
      isSelected: shuffle,
      color: shuffle ? scheme.primary : scheme.onSurfaceVariant,
      icon: const Icon(Icons.shuffle_rounded),
      onPressed: () => ref.read(playbackControllerProvider).toggleShuffle(),
    );
  }
}

/// Steps through the repeat settings: off → all → one → off.
class RepeatButton extends ConsumerWidget {
  const RepeatButton({this.iconSize = 24, super.key});

  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final repeat = ref.watch(playbackModeProvider).repeat;
    final active = repeat != RepeatSetting.off;

    return IconButton(
      iconSize: iconSize,
      tooltip: repeat.label,
      isSelected: active,
      color: active ? scheme.primary : scheme.onSurfaceVariant,
      icon: Icon(
        // Repeat-one gets its own glyph; off and all share one and are told
        // apart by the colour.
        repeat == RepeatSetting.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
      ),
      onPressed: () => ref.read(playbackControllerProvider).cycleRepeat(),
    );
  }
}
