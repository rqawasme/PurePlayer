import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player_source.dart';
import '../models/track.dart';
import '../providers/library_providers.dart';
import '../providers/playback_providers.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/sort_sheet.dart';
import '../widgets/track_card.dart';

/// The device's MP3s, searchable and sortable.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(searchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Tapping a row keeps whatever shuffle/repeat setting is in force — the
  /// user picked a starting track, not an order.
  Future<void> _play(List<Track> tracks, int index) => ref
      .read(playbackControllerProvider)
      .playAll(tracks, source: const LibrarySource(), index: index);

  /// Plays everything currently listed in a fresh random order.
  Future<void> _shuffleAll(List<Track> tracks) => ref
      .read(playbackControllerProvider)
      .shufflePlay(tracks, source: const LibrarySource());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.watch(libraryProvider);
    final visible = ref.watch(visibleTracksProvider);
    final sort = ref.watch(sortOptionProvider);
    final query = ref.watch(searchQueryProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Shuffle all',
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: visible.isEmpty ? null : () => _shuffleAll(visible),
          ),
          IconButton(
            tooltip: 'Sort (${sort.field.label})',
            icon: const Icon(Icons.sort_rounded),
            onPressed: () => SortSheet.show(
              context,
              current: sort,
              onChanged: ref.read(sortOptionProvider.notifier).update,
            ),
          ),
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(libraryProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: ref.read(searchQueryProvider.notifier).update,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search title, artist or album',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).clear();
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: switch (library) {
              AsyncLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
              AsyncError(:final error) => _Message(
                icon: Icons.error_outline_rounded,
                title: 'Could not read your music',
                detail: '$error',
              ),
              _ when visible.isEmpty => _Message(
                icon: query.isEmpty
                    ? Icons.library_music_outlined
                    : Icons.search_off_rounded,
                title: query.isEmpty
                    ? 'No MP3s found'
                    : 'No matches for "$query"',
                detail: query.isEmpty
                    ? 'Add some music to your device, then tap Rescan.'
                    : 'Try a different search.',
              ),
              _ => RefreshIndicator(
                onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final track = visible[index];
                    return TrackCard(
                      track: track,
                      isPlaying: currentTrack?.id == track.id,
                      onTap: () => _play(visible, index),
                      trailing: IconButton(
                        tooltip: 'More',
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () =>
                            AddToPlaylistSheet.show(context, [track]),
                      ),
                    );
                  },
                ),
              ),
            },
          ),
          if (visible.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${visible.length} of ${library.value?.length ?? 0} tracks',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Centred empty / error state.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
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
