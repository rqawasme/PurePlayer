package com.pureplayer.app

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Reads the device's audio library straight from `MediaStore`.
 *
 * This is deliberately hand-rolled instead of pulling in `on_audio_query`: that
 * package's Android module has been unmaintained since 2023 and does not build
 * against the Android Gradle Plugin this project uses.
 *
 * All content-resolver work runs on a background executor; results are posted
 * back on the main looper because Flutter's [MethodChannel.Result] is not
 * thread-safe.
 */
class MediaStorePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
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
        val LEGACY_ALBUM_ART: Uri = Uri.parse("content://media/external/audio/albumart")
    }
}
