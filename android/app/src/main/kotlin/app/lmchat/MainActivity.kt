package app.lmchat

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingStartText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lm_chat/keepalive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val text = call.argument<String>("text") ?: "Готовится ответ…"
                    if (needsNotificationPermission()) {
                        pendingStartText = text
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQUEST_NOTIFICATIONS,
                        )
                    } else {
                        KeepAliveService.start(this, text)
                    }
                    result.success(true)
                }
                "stop" -> {
                    KeepAliveService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun needsNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            // Start the service even if the permission was denied: it keeps the
            // process alive, only the notification stays hidden.
            val text = pendingStartText ?: "Готовится ответ…"
            pendingStartText = null
            KeepAliveService.start(this, text)
        }
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 41
    }
}
