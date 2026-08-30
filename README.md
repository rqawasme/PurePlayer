# PurePlayer

A simple, ad-free local MP3 player for Android. No ads, no analytics, no
network calls of any kind — the app does not even declare `INTERNET`
permission, so the OS enforces that rather than us merely promising it.

## Features

- Scans the device for MP3s straight from `MediaStore`
- Card-based library with album-art thumbnails, title, artist and duration
- Search across title / artist / album, and sort by title, artist, date added
  or duration
- Playback screen with play/pause, next/previous, and a scrub bar showing
  position and duration
- Shuffle and repeat (off / all / one), toggled from the player screen and
  reflected in the media session
- Play a playlist in its listed order or shuffled, and shuffle the whole
  library from the library screen
- Background playback with notification and lock-screen controls
- Create, rename and delete playlists; add and remove tracks
- Drag-and-drop reordering within a playlist
- Playlists, sort choice, shuffle/repeat, and the last queue + position
  persist locally

## Requirements

- Flutter **3.47.1** (stable) or newer — Dart **3.13.1**
- Android SDK **36** installed (`compileSdk` / `targetSdk` = 36)
- JDK **17**
- A device or emulator running Android 7.0 (API 24) or newer

## Running it

```bash
flutter pub get
flutter run
```

On first launch the app asks for audio access. Grant it and the library
populates; the launch screen explains the denied and "don't ask again" cases and
links to app settings.

## Toolchain

The Android scaffold uses the triple that Flutter 3.47.1 ships and tests
together, rather than a hand-picked mix:

| Component | Version | Where |
|---|---|---|
| Android Gradle Plugin | 9.1.0 | `android/settings.gradle.kts` |
| Kotlin | 2.4.10 | `android/settings.gradle.kts` |
| Gradle | 9.3.1 | `android/gradle/wrapper/gradle-wrapper.properties` |
| compileSdk / targetSdk | 36 | via `flutter.compileSdkVersion` |
| minSdk | 24 | via `flutter.minSdkVersion` |

Kotlin is the one deliberate bump — Flutter's template pins 2.4.0 and 2.4.10 is
the current stable patch. SDK levels reference the `flutter.*` properties rather
than literal integers, so they follow the SDK on `flutter upgrade` instead of
going stale.

## Permissions

| Permission | Why |
|---|---|
| `READ_MEDIA_AUDIO` | Read audio files on Android 13+ (API 33+) |
| `READ_EXTERNAL_STORAGE` | Same, on API 32 and below — capped with `maxSdkVersion="32"` |
| `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Keep playback alive in the background |

## Project layout

```
lib/
  models/      Track, Playlist, SortOption, PlaybackSource, PlaybackMode +
               the pure search/sort functions
  services/    MediaStoreService (platform channel), AppDatabase (sqflite),
               PurePlayerAudioHandler (just_audio + audio_service)
  providers/   Riverpod 3 providers: library, playlists, playback
  screens/     launch, home, library, playlist list/detail, player
  widgets/     TrackCard, AlbumArt, MiniPlayer, SeekBar, shuffle/repeat
               buttons, sheets
android/app/src/main/kotlin/com/pureplayer/app/
  MediaStorePlugin.kt   MediaStore query + album-art thumbnails
  MainActivity.kt       extends AudioServiceActivity
```

### Why no `permission_handler`

`permission_handler_android` 14 declares `compileSdk = 37`. Since AGP requires the
app's `compileSdk` to be at least as high as every dependency's, that one package
forced the whole project off Flutter's pinned 36 and onto an SDK platform that does
not resolve cleanly (`android-37.0` gets installed; AGP looks for `android-37`).
Every other Android module here sits at 36 or below.

The permission flow it provided — check status, request one permission, open app
settings — now lives in `MediaStorePlugin.kt` alongside the MediaStore query.
It uses only framework APIs available since API 23, well under this app's `minSdk`
of 24, so no dependency can pin the project's SDK level again.

### Why a hand-rolled MediaStore channel

The obvious choice, `on_audio_query`, has been unmaintained since 2023: its
Android module ships no `namespace` and pins AGP 4.1.3, which does not build
against the Android Gradle Plugin this project uses. Rather than depend on a
community fork of an abandoned package, the ~180 lines of `MediaStorePlugin.kt`
query `MediaStore.Audio` directly and pull album art via `loadThumbnail` on API
29+, with the legacy `albumart` content path as a fallback.

## Tests

```bash
flutter analyze
flutter test
```

54 tests cover the search/sort logic, the shuffle/repeat model and its
persistence format, the sqflite DAO (run against real SQLite through
`sqflite_common_ffi`, including playlist reordering and cascade deletes), the
`MediaStore` channel mapping, permission-status decoding, artwork caching, and
the `TrackCard` and shuffle/repeat button rendering.

CI (`.github/workflows/ci.yml`) runs those on every pull request and also builds a
debug APK against Android SDK 36, uploading it as a build artifact.
