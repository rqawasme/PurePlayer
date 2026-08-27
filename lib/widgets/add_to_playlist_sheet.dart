import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers/playlist_providers.dart';

/// Bottom sheet listing every playlist, plus an inline "new playlist" row.
class AddToPlaylistSheet extends ConsumerWidget {
  const AddToPlaylistSheet({required this.tracks, super.key});

  final List<Track> tracks;

  static Future<void> show(BuildContext context, List<Track> tracks) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => AddToPlaylistSheet(tracks: tracks),
      );

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    int playlistId,
    String name,
  ) async {
    final added = await ref
        .read(playlistControllerProvider)
        .addTracks(playlistId, tracks);
    if (!context.mounted) return;
    Navigator.of(context).pop();

    final skipped = tracks.length - added;
    final message = added == 0
        ? 'Already in $name'
        : skipped > 0
        ? 'Added $added to $name · $skipped already there'
        : 'Added $added to $name';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final name = await promptForPlaylistName(context, title: 'New playlist');
    if (name == null || !context.mounted) return;

    final controller = ref.read(playlistControllerProvider);
    final id = await controller.create(name);
    if (!context.mounted) return;
    await _add(context, ref, id, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlists = ref.watch(playlistsProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              tracks.length == 1
                  ? 'Add "${tracks.single.title}" to'
                  : 'Add ${tracks.length} tracks to',
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New playlist'),
            onTap: () => _createAndAdd(context, ref),
          ),
          const Divider(),
          Flexible(
            child: switch (playlists) {
              AsyncData(:final value) when value.isEmpty => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No playlists yet.', textAlign: TextAlign.center),
              ),
              AsyncData(:final value) => ListView.builder(
                shrinkWrap: true,
                itemCount: value.length,
                itemBuilder: (context, index) {
                  final playlist = value[index];
                  return ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.trackCount} tracks'),
                    onTap: () => _add(context, ref, playlist.id, playlist.name),
                  );
                },
              ),
              AsyncError(:final error) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load playlists: $error'),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// Shared name prompt used for both creating and renaming playlists.
Future<String?> promptForPlaylistName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) {
          final name = value.trim();
          if (name.isNotEmpty) Navigator.of(context).pop(name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
