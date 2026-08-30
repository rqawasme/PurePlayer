/// Whether the app may read the device's audio files.
///
/// Resolved on the Android side (see `MediaStorePlugin.kt`), which picks
/// `READ_MEDIA_AUDIO` on API 33+ and the legacy storage permission below that.
enum LibraryPermission {
  granted,
  denied,

  /// The user selected "don't ask again", so only app settings can fix it.
  permanentlyDenied;

  /// Decodes the string returned by the platform channel.
  ///
  /// Anything unrecognised is treated as [denied]: the launch screen then offers
  /// to ask again, which is the recoverable outcome.
  static LibraryPermission fromPlatform(String? value) => switch (value) {
    'granted' => LibraryPermission.granted,
    'permanentlyDenied' => LibraryPermission.permanentlyDenied,
    _ => LibraryPermission.denied,
  };
}
