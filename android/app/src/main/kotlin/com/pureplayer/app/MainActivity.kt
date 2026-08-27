package com.pureplayer.app

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Extends [AudioServiceActivity] rather than the usual `FlutterActivity`, which
 * audio_service requires so a single Flutter engine is shared between the UI and
 * the background playback service.
 */
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaStorePlugin(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
