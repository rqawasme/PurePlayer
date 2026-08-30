import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers/library_providers.dart';

/// Album art for one track, loaded lazily through the MediaStore channel.
///
/// Auto-disposing and keyed by track id, so scrolling a large library keeps at
/// most a screenful of decode work alive at a time; the service behind it
/// memoises both hits and misses.
final artworkProvider = FutureProvider.autoDispose.family<Uint8List?, Track>(
  (ref, track) => ref.watch(mediaStoreProvider).artwork(track),
);

class AlbumArt extends ConsumerWidget {
  const AlbumArt({
    required this.track,
    this.size = 56,
    this.radius = 12,
    super.key,
  });

  final Track? track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = track;
    final borderRadius = BorderRadius.circular(radius);

    Widget frame(Widget child) => ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: size, height: size, child: child),
    );

    if (current == null) return frame(_Placeholder(size: size));

    final artwork = ref.watch(artworkProvider(current));
    final bytes = artwork.value;

    return frame(
      bytes == null || bytes.isEmpty
          ? _Placeholder(size: size)
          : Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // A corrupt thumbnail should degrade to the placeholder, not
              // throw inside a list item.
              errorBuilder: (context, _, _) => _Placeholder(size: size),
            ),
    );
  }
}

/// Shown whenever a track has no embedded art — an aqua wash with a note.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.45,
          color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
