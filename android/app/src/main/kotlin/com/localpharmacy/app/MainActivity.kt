package com.localpharmacy.app

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger, "com.localpharmacy.app/secure-storage",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            val bytes = call.arguments as? ByteArray
            if (bytes == null) {
                result.error("invalid_data", "Invalid storage input", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "seal" -> result.success(SecureData.seal(bytes, "pharmacy/database"))
                    "open" -> result.success(SecureData.open(bytes, "pharmacy/database"))
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("secure_storage", "Unable to access encrypted storage", null)
            }
        }
        MethodChannel(messenger, "com.localpharmacy.app/sharing").setMethodCallHandler { call, result ->
            if (call.method == "keepScreenOn") {
                val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                if (call.arguments == true) window.addFlags(flag) else window.clearFlags(flag)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        Reminders.ensureChannel(this)
        MethodChannel(messenger, "com.localpharmacy.app/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "replace" -> {
                        try {
                            Reminders.replace(this, call.argument<Boolean>("enabled") == true, call.argument<String>("events") ?: "[]")
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("reminder_storage", "Unable to update encrypted reminders", null)
                        }
                    }
                    "requestPermission" -> {
                        if (notificationsAllowed() || Build.VERSION.SDK_INT < 33) {
                            result.success(notificationsAllowed())
                        } else if (permissionResult == null) {
                            permissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                        } else {
                            result.success(false)
                        }
                    }
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun notificationsAllowed() =
        getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 41) {
            permissionResult?.success(notificationsAllowed())
            permissionResult = null
        }
    }
}
