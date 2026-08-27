import 'package:flutter/material.dart';

import '../models/track.dart';
import 'album_art.dart';

/// One row of the library / playlist lists: thumbnail, title, artist, duration.
class TrackCard extends StatelessWidget {
  const TrackCard({
    required this.track,
    this.onTap,
    this.isPlaying = false,
    this.missing = false,
    this.trailing,
    this.leading,
    super.key,
  });

  final Track track;
  final VoidCallback? onTap;

  /// Highlights the row that is currently playing.
  final bool isPlaying;

  /// The file behind this entry is gone — shown greyed rather than hidden, so
  /// a stale playlist entry is visible instead of silently vanishing.
  final bool missing;

  final Widget? trailing;

  /// Used by the playlist screen to host the drag handle.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dimmed = missing;

    return Card(
      color: isPlaying ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
      child: InkWell(
        onTap: missing ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ?leading,
              Opacity(
                opacity: dimmed ? 0.4 : 1,
                child: AlbumArt(track: track),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: isPlaying
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: dimmed
                            ? scheme.onSurfaceVariant
                            : isPlaying
                            ? scheme.primary
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      missing ? 'File missing' : track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: missing ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatDuration(track.duration),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
