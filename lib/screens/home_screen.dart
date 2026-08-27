import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import 'library_screen.dart';
import 'playlist_list_screen.dart';

/// Library and Playlists, with the now-playing strip pinned above the bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps each tab's scroll position and search text alive
      // across switches.
      body: IndexedStack(
        index: _index,
        children: const [LibraryScreen(), PlaylistListScreen()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          const Divider(height: 1),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music_rounded),
                label: 'Playlists',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
