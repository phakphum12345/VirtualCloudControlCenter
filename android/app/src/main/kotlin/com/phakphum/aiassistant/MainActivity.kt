package com.phakphum.aiassistant

import android.app.ActivityManager
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.phakphum.aiassistant/android"
    private val captureRequestCode = 4107
    private var pendingCaptureResult: MethodChannel.Result? = null
    private var pendingCaptureParameters: Map<String, Any?> = emptyMap()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSystemStatus" -> result.success(systemStatus())
            "openSettings" -> result.success(openSettings(call.argument<String>("page")))
            "startRecording" -> startRecording(call, result)
            "pauseRecording" -> controlRecording(ScreenRecordingService.ACTION_PAUSE, result)
            "resumeRecording" -> controlRecording(ScreenRecordingService.ACTION_RESUME, result)
            "stopRecording" -> controlRecording(ScreenRecordingService.ACTION_STOP, result)
            "recordingStatus" -> result.success(ScreenRecordingService.currentStatus())
            else -> result.notImplemented()
        }
    }

    private fun startRecording(call: MethodCall, result: MethodChannel.Result) {
        if (pendingCaptureResult != null) {
            result.success(failure("Android is already waiting for screen-capture permission."))
            return
        }
        if (ScreenRecordingService.isRecording) {
            result.success(failure("Android screen recording is already active."))
            return
        }
        if (call.argument<Boolean>("microphone") == true) {
            result.success(failure("Microphone recording is not supported by the Android adapter yet."))
            return
        }
        if (call.argument<Boolean>("systemAudio") == true) {
            result.success(failure("System-audio recording is not supported by the Android adapter yet."))
            return
        }
        pendingCaptureResult = result
        pendingCaptureParameters = call.arguments as? Map<String, Any?> ?: emptyMap()
        val projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(projectionManager.createScreenCaptureIntent(), captureRequestCode)
    }

    @Deprecated("The Flutter activity result bridge still uses this callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != captureRequestCode) return
        val result = pendingCaptureResult ?: return
        pendingCaptureResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(
                failure("Screen recording was not started because capture permission was denied."),
            )
            return
        }
        val quality = pendingCaptureParameters["quality"]?.toString() ?: "1080p"
        val fps = (pendingCaptureParameters["fps"] as? Number)?.toInt() ?: 30
        val serviceIntent = Intent(this, ScreenRecordingService::class.java).apply {
            action = ScreenRecordingService.ACTION_START
            putExtra(ScreenRecordingService.EXTRA_RESULT_CODE, resultCode)
            putExtra(ScreenRecordingService.EXTRA_RESULT_DATA, data)
            putExtra(ScreenRecordingService.EXTRA_QUALITY, quality)
            putExtra(ScreenRecordingService.EXTRA_FPS, fps)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            awaitRecorderStart(result)
        } catch (error: Exception) {
            result.success(failure("Android could not start screen recording: ${error.message}"))
        }
    }

    private fun awaitRecorderStart(result: MethodChannel.Result) {
        val handler = Handler(Looper.getMainLooper())
        val deadline = System.currentTimeMillis() + 5_000
        lateinit var check: Runnable
        check = Runnable {
            val error = ScreenRecordingService.lastError
            when {
                ScreenRecordingService.isRecording -> result.success(
                    ScreenRecordingService.currentStatus() +
                        success("Android screen recording started.") +
                        mapOf("microphone" to false, "systemAudio" to false),
                )
                error != null -> result.success(failure(error))
                System.currentTimeMillis() >= deadline -> result.success(
                    failure("Android recorder did not become ready within five seconds."),
                )
                else -> handler.postDelayed(check, 50)
            }
        }
        handler.post(check)
    }

    private fun controlRecording(action: String, result: MethodChannel.Result) {
        if (!ScreenRecordingService.isRecording && action != ScreenRecordingService.ACTION_STOP) {
            result.success(failure("No Android screen recording is active."))
            return
        }
        if (!ScreenRecordingService.isRecording && action == ScreenRecordingService.ACTION_STOP) {
            result.success(failure("No Android screen recording is active."))
            return
        }
        val before = ScreenRecordingService.currentStatus()
        try {
            startService(Intent(this, ScreenRecordingService::class.java).setAction(action))
            awaitRecorderControl(action, before["outputFile"]?.toString().orEmpty(), result)
        } catch (error: Exception) {
            result.success(failure("Android could not control screen recording: ${error.message}"))
        }
    }

    private fun awaitRecorderControl(
        action: String,
        outputFile: String,
        result: MethodChannel.Result,
    ) {
        val handler = Handler(Looper.getMainLooper())
        val deadline = System.currentTimeMillis() + 2_000
        lateinit var check: Runnable
        check = Runnable {
            val completed = when (action) {
                ScreenRecordingService.ACTION_PAUSE ->
                    ScreenRecordingService.isRecording && ScreenRecordingService.isPaused
                ScreenRecordingService.ACTION_RESUME ->
                    ScreenRecordingService.isRecording && !ScreenRecordingService.isPaused
                else -> !ScreenRecordingService.isRecording
            }
            if (completed) {
                val state = when (action) {
                    ScreenRecordingService.ACTION_PAUSE -> "paused"
                    ScreenRecordingService.ACTION_RESUME -> "recording"
                    else -> "stopped"
                }
                result.success(
                    success("Android screen recording $state.") +
                        mapOf("state" to state, "outputFile" to outputFile),
                )
            } else if (System.currentTimeMillis() >= deadline) {
                result.success(failure("Android recorder did not complete the requested control action."))
            } else {
                handler.postDelayed(check, 50)
            }
        }
        handler.post(check)
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
