package com.tangotech.mindfull

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity is required by local_auth's BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blank the Recents thumbnail and block screenshots/screen recording of
        // journal content.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mindfull/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "profile" -> {
                    val memory = ActivityManager.MemoryInfo()
                    (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
                    val stat = StatFs(filesDir.absolutePath)
                    result.success(
                        mapOf(
                            "totalRamBytes" to memory.totalMem,
                            "freeDiskBytes" to stat.availableBytes,
                            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                            "osVersion" to Build.VERSION.RELEASE,
                        ),
                    )
                }
                // Android app-data backup is already disabled in the manifest.
                "excludeFromBackup" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }
}
