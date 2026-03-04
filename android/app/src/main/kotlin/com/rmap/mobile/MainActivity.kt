package com.rmap.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.rmap.mobile/deeplink"
    private var channel: MethodChannel? = null
    private var initialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(initialLink)
                    initialLink = null // consume it
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Stash the deep-link URI BEFORE super.onCreate, which triggers
        // configureFlutterEngine.  If we wait, handleIntent sees channel!=null
        // and tries invokeMethod("onNewLink") before Dart is ready → lost.
        initialLink = intent?.data?.toString()
        super.onCreate(savedInstanceState)

        // Create the notification channel for property alerts (Android 8+).
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "property_alerts",
                "Property Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications about new properties near you"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data?.toString() ?: return
        if (channel != null) {
            // Engine is already running – push to Dart immediately.
            channel?.invokeMethod("onNewLink", uri)
        } else {
            // Cold start – stash for when Dart asks via getInitialLink.
            initialLink = uri
        }
    }
}
