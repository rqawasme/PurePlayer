import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/library_permission.dart';
import '../models/sort_option.dart';
import '../models/track.dart';
import '../services/database.dart';
import '../services/media_store_service.dart';

// Re-exported so screens can switch on the permission state without reaching
// past the providers into models/.
export '../models/library_permission.dart';

/// Overridden in `main()` so the app and the audio handler share one instance.
final mediaStoreProvider = Provider<MediaStoreService>(
  (ref) => MediaStoreService(),
);

/// Overridden in `main()` for the same reason.
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final permissionProvider =
    AsyncNotifierProvider<PermissionNotifier, LibraryPermission>(
      PermissionNotifier.new,
    );

class PermissionNotifier extends AsyncNotifier<LibraryPermission> {
  @override
  Future<LibraryPermission> build() =>
      ref.read(mediaStoreProvider).permissionStatus();

  /// Shows the system dialog. No-op if access has already been granted.
  Future<void> request() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(mediaStoreProvider).requestPermission(),
    );
  }

  /// Re-reads the status, for when the user returns from app settings.
  Future<void> recheck() async {
    state = await AsyncValue.guard(
      () => ref.read(mediaStoreProvider).permissionStatus(),
    );
  }

  Future<void> openSettings() => ref.read(mediaStoreProvider).openAppSettings();
}

/// Every MP3 the device has indexed, newest scan wins.
///
/// Resolves to an empty list rather than an error when permission is missing —
/// the launch screen already surfaces that case, and an error here would only
/// duplicate it.
final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<Track>>(
  LibraryNotifier.new,
);

class LibraryNotifier extends AsyncNotifier<List<Track>> {
  @override
  Future<List<Track>> build() async {
    final permission = await ref.watch(permissionProvider.future);
    if (permission != LibraryPermission.granted) return const [];
    return ref.read(mediaStoreProvider).queryTracks();
  }

  /// Re-scans MediaStore, e.g. after pull-to-refresh.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(mediaStoreProvider).queryTracks(),
    );
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

/// The library sort choice, restored from and written back to `app_state`.
final sortOptionProvider = NotifierProvider<SortOptionNotifier, SortOption>(
  SortOptionNotifier.new,
);

class SortOptionNotifier extends Notifier<SortOption> {
  @override
  SortOption build() {
    // Start from the default and swap in the stored choice when it arrives;
    // the alternative is blocking the whole library screen on a disk read.
    unawaited(_restore());
    return const SortOption();
  }

  Future<void> _restore() async {
    final raw = await ref
        .read(databaseProvider)
        .readState(AppDatabase.sortStateKey);
    if (raw == null || !ref.mounted) return;
    try {
      state = SortOption.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on FormatException {
      // A corrupt value just means the default sticks.
    }
  }

  void update(SortOption option) {
    state = option;
    unawaited(
      ref
          .read(databaseProvider)
          .writeState(AppDatabase.sortStateKey, jsonEncode(option.toJson())),
    );
  }
}

/// The library as the list actually renders it: searched, then sorted.
final visibleTracksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(libraryProvider).value ?? const <Track>[];
  return queryTracks(
    tracks,
    ref.watch(searchQueryProvider),
    ref.watch(sortOptionProvider),
  );
});
