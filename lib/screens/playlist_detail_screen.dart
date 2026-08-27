import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player_source.dart';
import '../models/playlist.dart';
import '../providers/playback_providers.dart';
import '../providers/playlist_providers.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/track_card.dart';

/// One playlist's contents, reorderable by drag and drop.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({required this.playlistId, super.key});

  final int playlistId;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final name = await promptForPlaylistName(
      context,
      title: 'Rename playlist',
      initial: current,
    );
    if (name == null) return;
    await ref.read(playlistControllerProvider).rename(playlistId, name);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'The playlist is removed. The audio files stay on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(playlistControllerProvider).delete(playlistId);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(playlistEntriesProvider(playlistId));
    final currentTrack = ref.watch(currentTrackProvider);

    // The list screen already holds every playlist, so the name comes from
    // there rather than costing a second query.
    final playlist = ref
        .watch(playlistsProvider)
        .value
        ?.where((item) => item.id == playlistId)
        .firstOrNull;
    final name = playlist?.name ?? 'Playlist';

    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'rename' => _rename(context, ref, name),
              'delete' => _delete(context, ref, name),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: switch (entries) {
        AsyncData(:final value) when value.isEmpty => const _EmptyPlaylist(),
        AsyncData(:final value) => _EntryList(
          playlistId: playlistId,
          entries: value,
          currentTrackId: currentTrack?.id,
        ),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Could not load this playlist: $error'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({
    required this.playlistId,
    required this.entries,
    required this.currentTrackId,
  });

  final int playlistId;
  final List<PlaylistEntry> entries;
  final int? currentTrackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playable = [
      for (final entry in entries)
        if (File(entry.track.path).existsSync()) entry.track,
    ];

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: entries.length,
      // onReorderItem (unlike the deprecated onReorder) already accounts for
      // the dragged row leaving its old slot, so newIndex needs no adjusting.
      onReorderItem: (oldIndex, newIndex) => ref
          .read(playlistControllerProvider)
          .reorder(playlistId, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final missing = !File(entry.track.path).existsSync();

        return Padding(
          key: ValueKey(entry.rowId),
          padding: const EdgeInsets.only(bottom: 8),
          child: TrackCard(
            track: entry.track,
            missing: missing,
            isPlaying: currentTrackId == entry.track.id,
            leading: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            onTap: () {
              // Play the playlist from this track, skipping entries whose
              // files have disappeared.
              final target = playable.indexWhere(
                (track) => track.id == entry.track.id,
              );
              if (target < 0) return;
              ref
                  .read(playbackControllerProvider)
                  .playAll(
                    playable,
                    source: PlaylistSource(playlistId),
                    index: target,
                  );
            },
            trailing: IconButton(
              tooltip: 'Remove from playlist',
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: () => ref
                  .read(playlistControllerProvider)
                  .removeTrack(playlistId, entry.track.id),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Nothing here yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Open your library and use the ⋮ menu on a track to add it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
