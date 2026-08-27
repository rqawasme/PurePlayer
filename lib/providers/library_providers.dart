import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sort_option.dart';
import '../models/track.dart';
import '../services/database.dart';
import '../services/media_store_service.dart';

/// Overridden in `main()` so the app and the audio handler share one instance.
final mediaStoreProvider = Provider<MediaStoreService>(
  (ref) => MediaStoreService(),
);

/// Overridden in `main()` for the same reason.
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

/// First Android API level that replaced blanket storage access with the
/// scoped `READ_MEDIA_AUDIO` permission.
const _androidTiramisu = 33;

enum LibraryPermission {
  granted,
  denied,

  /// The user selected "don't ask again", so only app settings can fix it.
  permanentlyDenied,
}

final permissionProvider =
    AsyncNotifierProvider<PermissionNotifier, LibraryPermission>(
      PermissionNotifier.new,
    );

class PermissionNotifier extends AsyncNotifier<LibraryPermission> {
  @override
  Future<LibraryPermission> build() async =>
      _map(await (await _target()).status);

  /// Android 13+ wants `READ_MEDIA_AUDIO`; older releases only understand the
  /// legacy storage permission.
  Future<Permission> _target() async {
    final sdkInt = await ref.read(mediaStoreProvider).sdkInt();
    return sdkInt >= _androidTiramisu ? Permission.audio : Permission.storage;
  }

  static LibraryPermission _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return LibraryPermission.granted;
    if (status.isPermanentlyDenied) return LibraryPermission.permanentlyDenied;
    return LibraryPermission.denied;
  }

  Future<void> request() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final permission = await _target();
      return _map(await permission.request());
    });
  }

  /// Re-reads the status, for when the user returns from app settings.
  Future<void> recheck() async {
    state = await AsyncValue.guard(
      () async => _map(await (await _target()).status),
    );
  }

  Future<void> openSettings() => openAppSettings();
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
