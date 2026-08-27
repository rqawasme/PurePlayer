import 'package:flutter/material.dart';

import '../models/track.dart';

/// Scrub bar with position and duration labels.
///
/// Holds a local value while the thumb is being dragged so the bar tracks the
/// finger instead of fighting the stream of real playback positions.
class SeekBar extends StatefulWidget {
  const SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final positionMs = widget.position.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs <= 0 ? 0.0 : maxMs,
    );
    final value = _dragValue ?? positionMs;

    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      children: [
        Slider(
          value: value.clamp(0.0, maxMs <= 0 ? 1.0 : maxMs),
          max: maxMs <= 0 ? 1.0 : maxMs,
          // A zero duration means nothing is loaded yet; seeking would be a
          // no-op at best, so the bar stays inert.
          onChanged: maxMs <= 0
              ? null
              : (next) => setState(() => _dragValue = next),
          onChangeEnd: maxMs <= 0
              ? null
              : (next) {
                  widget.onSeek(Duration(milliseconds: next.round()));
                  setState(() => _dragValue = null);
                },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(Duration(milliseconds: value.round())),
                style: labelStyle,
              ),
              Text(formatDuration(widget.duration), style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}
