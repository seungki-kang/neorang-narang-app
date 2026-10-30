package com.example.neorang_narang_app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var ready = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Cold starts have no in-memory PKCE transaction; discard return intents.
        intent?.data = null
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jesuslife/mobile_browser")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> { ready = true; result.success(null) }
                "open" -> {
                    val uri = (call.arguments as? String)?.let { Uri.parse(it) }
                    if (uri == null || uri.scheme != "http" || uri.host != "127.0.0.1" ||
                        uri.port != 8000 || uri.path != "/api/v1/mobile/authorize") {
                        result.error("invalid_uri", "Unable to open login", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(null)
                        } catch (_: Exception) { result.error("browser_unavailable", "Unable to open login", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        val uri = intent.data
        intent.data = null
        super.onNewIntent(intent)
        if (ready && uri?.scheme == "jesuslife-poc" && uri.host == "auth" && uri.path == "/complete/android") {
            channel?.invokeMethod("returnUri", uri.toString())
        }
    }
}
