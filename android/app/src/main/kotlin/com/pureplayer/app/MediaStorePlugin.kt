package com.pureplayer.app

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Reads the device's audio library straight from `MediaStore`, and owns the
 * runtime permission that gates it.
 *
 * Both halves are deliberately hand-rolled rather than taken from packages:
 * `on_audio_query`'s Android module has been unmaintained since 2023 and does
 * not build against this project's Android Gradle Plugin, and
 * `permission_handler_android` 14 forces `compileSdk = 37` on the whole app for
 * what amounts to three calls. Everything used here is framework API available
 * since API 23, well below this app's `minSdk` of 24, so no dependency can pin
 * an SDK level again.
 *
 * Content-resolver work runs on a background executor; results are posted back
 * on the main looper because Flutter's [MethodChannel.Result] is not
 * thread-safe. The permission calls stay on the main thread — they touch the
 * [Activity].
 */
class MediaStorePlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private val context: Context get() = activity.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Held between [requestPermission] and the system dialog's callback. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val preferences: SharedPreferences
        get() = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    /** Releases the worker thread; called when the hosting activity is destroyed. */
    fun destroy() {
        pendingPermissionResult = null
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            "permissionStatus" -> result.success(permissionStatus())
            "requestPermission" -> requestPermission(result)
            "openAppSettings" -> result.success(openAppSettings())
            "queryTracks" -> runAsync(result) { queryTracks() }
            "queryArtwork" -> {
                val songId = (call.argument<Number>("songId"))?.toLong()
                val albumId = (call.argument<Number>("albumId"))?.toLong()
                val size = call.argument<Number>("size")?.toInt() ?: DEFAULT_ART_SIZE
                if (songId == null) {
                    result.error("bad_args", "songId is required", null)
                } else {
                    runAsync(result) { loadArtwork(songId, albumId, size) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [work] off the main thread and delivers the outcome back on it. */
    private fun <T> runAsync(result: MethodChannel.Result, work: () -> T) {
        executor.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("media_store_error", error.message, null)
                }
            }
        }
    }

    // ------------------------------------------------------------ permission

    /**
     * Android 13+ replaced blanket storage access with a scoped audio
     * permission; older releases only understand the legacy one.
     */
    private val audioPermission: String
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun isGranted(): Boolean =
        context.checkSelfPermission(audioPermission) == PackageManager.PERMISSION_GRANTED

    /**
     * One of `granted`, `denied` or `permanentlyDenied`.
     *
     * `shouldShowRequestPermissionRationale` also returns false *before* the
     * first ever request, so it cannot identify a permanent denial on its own —
     * hence the persisted "we have asked at least once" flag.
     */
    private fun permissionStatus(): String {
        if (isGranted()) return GRANTED
        val hasAsked = preferences.getBoolean(KEY_HAS_REQUESTED, false)
        val canAskAgain = activity.shouldShowRequestPermissionRationale(audioPermission)
        return if (hasAsked && !canAskAgain) PERMANENTLY_DENIED else DENIED
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (isGranted()) {
            result.success(GRANTED)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "A permission request is already in progress", null)
            return
        }

        pendingPermissionResult = result
        preferences.edit().putBoolean(KEY_HAS_REQUESTED, true).apply()
        activity.requestPermissions(arrayOf(audioPermission), PERMISSION_REQUEST_CODE)
    }

    /** Called by `MainActivity` once the system dialog has been answered. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        result.success(permissionStatus())
        return true
    }

    /** Opens this app's system settings page, for a permanently denied grant. */
    private fun openAppSettings(): Boolean = try {
        activity.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", activity.packageName, null),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (_: Throwable) {
        false
    }

    // ---------------------------------------------------------------- library

    private fun queryTracks(): List<Map<String, Any?>> {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.SIZE,
        )

        // MP3 only, per the app's remit. The MIME check is authoritative; the
        // extension check catches files the indexer typed loosely.
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND " +
            "(${MediaStore.Audio.Media.MIME_TYPE} = ? OR ${MediaStore.Audio.Media.DATA} LIKE ?)"
        val selectionArgs = arrayOf("audio/mpeg", "%.mp3")

        val tracks = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            collection,
            projection,
            selection,
            selectionArgs,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)

            while (cursor.moveToNext()) {
                val path = cursor.getString(dataColumn) ?: continue
                tracks += mapOf(
                    "id" to cursor.getLong(idColumn),
                    "title" to cursor.getString(titleColumn),
                    "artist" to cursor.getString(artistColumn),
                    "album" to cursor.getString(albumColumn),
                    "albumId" to cursor.getLong(albumIdColumn),
                    "durationMs" to cursor.getLong(durationColumn),
                    "path" to path,
                    "dateAdded" to cursor.getLong(dateColumn),
                    "size" to cursor.getLong(sizeColumn),
                )
            }
        }
        return tracks
    }

    /**
     * Returns JPEG bytes for a track's album art, or `null` when it has none.
     *
     * A missing thumbnail is an ordinary outcome, not an error, so every failure
     * path here collapses to `null` and lets the UI show its placeholder.
     */
    private fun loadArtwork(songId: Long, albumId: Long?, size: Int): ByteArray? {
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val songUri = ContentUris.withAppendedId(
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL),
                songId,
            )
            try {
                context.contentResolver.loadThumbnail(songUri, Size(size, size), null)
            } catch (_: Throwable) {
                null
            }
        } else {
            legacyAlbumArt(albumId)
        }
        return bitmap?.let { encodeJpeg(it) }
    }

    /** Pre-API-29 devices expose album art through a dedicated content path. */
    private fun legacyAlbumArt(albumId: Long?): Bitmap? {
        if (albumId == null) return null
        val artUri = ContentUris.withAppendedId(LEGACY_ALBUM_ART, albumId)
        return try {
            context.contentResolver.openInputStream(artUri)?.use(BitmapFactory::decodeStream)
        } catch (_: Throwable) {
            null
        }
    }

    private fun encodeJpeg(bitmap: Bitmap): ByteArray =
        ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
            stream.toByteArray()
        }

    private companion object {
        const val CHANNEL = "com.pureplayer.app/media_store"
        const val DEFAULT_ART_SIZE = 256
        const val JPEG_QUALITY = 85

        const val PREFERENCES = "pureplayer_permissions"
        const val KEY_HAS_REQUESTED = "has_requested_audio_permission"
        const val PERMISSION_REQUEST_CODE = 4711

        const val GRANTED = "granted"
        const val DENIED = "denied"
        const val PERMANENTLY_DENIED = "permanentlyDenied"
        val LEGACY_ALBUM_ART: Uri = Uri.parse("content://media/external/audio/albumart")
    }
}
