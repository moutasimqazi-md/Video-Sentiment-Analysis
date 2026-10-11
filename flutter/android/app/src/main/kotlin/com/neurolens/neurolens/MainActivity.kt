package com.neurolens.neurolens

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Receives links shared to NeuroLens from other apps (Instagram, YouTube, a browser...) and hands them to the Flutter side. */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initial: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initial = sharedText(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "neurolens/share").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(initial)
                    initial = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("shared", it) }
    }

    private fun sharedText(i: Intent?): String? {
        if (i == null || i.action != Intent.ACTION_SEND || i.type?.startsWith("text/") != true) return null
        return i.getStringExtra(Intent.EXTRA_TEXT)
    }
}
