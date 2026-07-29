package com.phakphum.aiassistant

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.phakphum.aiassistant/android"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSystemStatus" -> result.success(systemStatus())
            "openSettings" -> result.success(openSettings(call.argument<String>("page")))
            else -> result.notImplemented()
        }
    }

    private fun systemStatus(): Map<String, Any> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
        val storage = StatFs(Environment.getDataDirectory().absolutePath)
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return mapOf(
            "success" to true,
            "message" to "Android system status read successfully.",
            "memoryTotalBytes" to memory.totalMem,
            "memoryAvailableBytes" to memory.availMem,
            "memoryLow" to memory.lowMemory,
            "diskTotalBytes" to storage.totalBytes,
            "diskFreeBytes" to storage.availableBytes,
            "batteryPercent" to batteryManager.getIntProperty(
                BatteryManager.BATTERY_PROPERTY_CAPACITY,
            ),
            "logicalProcessors" to Runtime.getRuntime().availableProcessors(),
        )
    }

    private fun openSettings(page: String?): Map<String, Any> {
        val action = when (page) {
            "wifi" -> Settings.ACTION_WIFI_SETTINGS
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "display" -> Settings.ACTION_DISPLAY_SETTINGS
            "storage" -> Settings.ACTION_INTERNAL_STORAGE_SETTINGS
            "battery" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
            "notifications" -> Settings.ACTION_APP_NOTIFICATION_SETTINGS
            "sound" -> Settings.ACTION_SOUND_SETTINGS
            else -> null
        } ?: return failure("The requested Android settings page is not allowlisted.")

        val intent = Intent(action).apply {
            if (action == Settings.ACTION_APP_NOTIFICATION_SETTINGS) {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        }
        return try {
            startActivity(intent)
            success("Android settings opened.")
        } catch (_: Exception) {
            failure("Android could not open this settings page.")
        }
    }

    private fun success(message: String) = mapOf(
        "success" to true,
        "message" to message,
    )

    private fun failure(message: String) = mapOf(
        "success" to false,
        "message" to message,
    )
}
