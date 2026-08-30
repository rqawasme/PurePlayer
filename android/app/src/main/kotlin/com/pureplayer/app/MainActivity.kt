package com.pureplayer.app

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Extends [AudioServiceActivity] rather than the usual `FlutterActivity`, which
 * audio_service requires so a single Flutter engine is shared between the UI and
 * the background playback service.
 */
class MainActivity : AudioServiceActivity() {

    private var mediaStorePlugin: MediaStorePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaStorePlugin = MediaStorePlugin(this).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    /**
     * [MediaStorePlugin] is registered by this activity rather than as an
     * `ActivityAware` Flutter plugin, so the permission result lands here and has
     * to be handed on explicitly.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        mediaStorePlugin?.onRequestPermissionsResult(requestCode)
    }

    override fun onDestroy() {
        mediaStorePlugin?.destroy()
        mediaStorePlugin = null
        super.onDestroy()
    }
}
