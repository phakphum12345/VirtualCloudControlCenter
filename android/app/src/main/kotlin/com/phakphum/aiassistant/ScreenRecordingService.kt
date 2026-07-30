package com.phakphum.aiassistant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenRecordingService : Service() {
    private var mediaProjection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startCapture(intent)
            ACTION_PAUSE -> pauseCapture()
            ACTION_RESUME -> resumeCapture()
            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    private fun startCapture(intent: Intent) {
        if (isRecording) return
        lastError = null
        createNotificationChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("Phakphum AI System Assistant")
            .setContentText("กำลังบันทึกหน้าจอ — แตะเพื่อกลับไปยังแอป")
            .setOngoing(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    packageManager.getLaunchIntentForPackage(packageName),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }
        if (resultData == null) {
            lastError = "Android did not provide screen-capture permission data."
            stopSelf()
            return
        }

        val metrics = resources.displayMetrics
        val requested = dimensionsFor(intent.getStringExtra(EXTRA_QUALITY), metrics.widthPixels, metrics.heightPixels)
        val width = requested.first.ensureEven()
        val height = requested.second.ensureEven()
        val fps = intent.getIntExtra(EXTRA_FPS, 30).coerceIn(15, 60)
        val outputDirectory = getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: filesDir
        outputDirectory.mkdirs()
        outputFile = File(
            outputDirectory,
            "recording_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.mp4",
        ).absolutePath

        try {
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setOutputFile(outputFile)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recorder.setVideoSize(width, height)
            recorder.setVideoFrameRate(fps)
            recorder.setVideoEncodingBitRate((width * height * fps * 0.12).toInt().coerceAtLeast(4_000_000))
            recorder.prepare()

            val manager =
                getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = manager.getMediaProjection(resultCode, resultData)
                ?: error("MediaProjection permission token was rejected.")
            projection.registerCallback(
                object : MediaProjection.Callback() {
                    override fun onStop() {
                        stopCapture()
                    }
                },
                null,
            )
            val display = projection.createVirtualDisplay(
                "PhakphumScreenRecording",
                width,
                height,
                metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                recorder.surface,
                null,
                null,
            )
            mediaRecorder = recorder
            mediaProjection = projection
            virtualDisplay = display
            recorder.start()
            isRecording = true
            isPaused = false
        } catch (error: Exception) {
            lastError = "Android could not initialize the screen recorder: ${error.message}"
            releaseResources(deleteIncompleteFile = true)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun pauseCapture() {
        if (!isRecording || isPaused || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        mediaRecorder?.pause()
        isPaused = true
    }

    private fun resumeCapture() {
        if (!isRecording || !isPaused || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        mediaRecorder?.resume()
        isPaused = false
    }

    private fun stopCapture() {
        if (isRecording) {
            try {
                mediaRecorder?.stop()
            } catch (_: RuntimeException) {
                outputFile?.let(::File)?.delete()
            }
        }
        releaseResources(deleteIncompleteFile = false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun releaseResources(deleteIncompleteFile: Boolean) {
        virtualDisplay?.release()
        virtualDisplay = null
        try {
            mediaRecorder?.reset()
            mediaRecorder?.release()
        } catch (_: Exception) {
            // The recorder may already have been released by the platform.
        }
        mediaRecorder = null
        mediaProjection?.stop()
        mediaProjection = null
        isRecording = false
        isPaused = false
        if (deleteIncompleteFile) {
            outputFile?.let(::File)?.delete()
            outputFile = null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Screen recording",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun dimensionsFor(quality: String?, screenWidth: Int, screenHeight: Int): Pair<Int, Int> {
        val longEdge = when (quality) {
            "720p" -> 1280
            "1440p" -> 2560
            else -> 1920
        }
        val screenLong = maxOf(screenWidth, screenHeight)
        if (screenLong <= longEdge) return screenWidth to screenHeight
        val scale = longEdge.toDouble() / screenLong
        return (screenWidth * scale).toInt() to (screenHeight * scale).toInt()
    }

    private fun Int.ensureEven(): Int = if (this % 2 == 0) this else this - 1

    companion object {
        const val ACTION_START = "com.phakphum.aiassistant.recording.START"
        const val ACTION_PAUSE = "com.phakphum.aiassistant.recording.PAUSE"
        const val ACTION_RESUME = "com.phakphum.aiassistant.recording.RESUME"
        const val ACTION_STOP = "com.phakphum.aiassistant.recording.STOP"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_QUALITY = "quality"
        const val EXTRA_FPS = "fps"
        private const val CHANNEL_ID = "screen_recording"
        private const val NOTIFICATION_ID = 4107

        @Volatile var isRecording = false
            private set
        @Volatile var isPaused = false
            private set
        @Volatile var outputFile: String? = null
            private set
        @Volatile var lastError: String? = null
            private set

        fun currentStatus(): Map<String, Any> = mapOf(
            "success" to true,
            "message" to "Android recording status read.",
            "recording" to isRecording,
            "paused" to isPaused,
            "outputFile" to (outputFile ?: ""),
            "visibleIndicator" to isRecording,
        )
    }
}
