package com.example.tab2notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "tab2notify/native_notifications"
    private var methodChannel: MethodChannel? = null
    private var pendingRequestId: String? = null
    private var mediaPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "showNotification" -> {
                        val title = call.argument<String>("title") ?: "Table Request"
                        val body = call.argument<String>("body") ?: "A table is requesting assistance"
                        val requestId = call.argument<String>("requestId") ?: ""
                        val tableNumber = call.argument<Int>("tableNumber") ?: 1
                        val notificationId = call.argument<Int>("notificationId") ?: tableNumber
                        val channelId = call.argument<String>("channelId") ?: "waiter_requests_channel"
                        val sound = call.argument<String>("sound") ?: ""
                        showNativeNotification(title, body, requestId, tableNumber, notificationId, channelId, sound)
                        result.success(true)
                    }
                    "clearNotification" -> {
                        val notificationId = call.argument<Int>("notificationId") ?: 1
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancel(notificationId)
                        result.success(true)
                    }
                    "getInitialNotificationPayload" -> {
                        result.success(pendingRequestId)
                        pendingRequestId = null
                    }
                    "playAudioPrompt" -> {
                        playNativeAudioPrompt(R.raw.incoming_prompt)
                        result.success(true)
                    }
                    "playManagerAudioPrompt" -> {
                        playNativeAudioPrompt(R.raw.please_hold)
                        result.success(true)
                    }
                    "stopAudioPrompt" -> {
                        stopNativeAudioPrompt()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        stopNativeAudioPrompt()
        super.onDestroy()
    }

    private fun playNativeAudioPrompt(rawResourceId: Int = R.raw.incoming_prompt) {
        try {
            stopNativeAudioPrompt()
            mediaPlayer = MediaPlayer.create(this, rawResourceId)?.apply {
                setOnCompletionListener { mp ->
                    mp.release()
                    if (mediaPlayer == mp) {
                        mediaPlayer = null
                    }
                }
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopNativeAudioPrompt() {
        try {
            mediaPlayer?.let { mp ->
                if (mp.isPlaying) {
                    mp.stop()
                }
                mp.release()
            }
            mediaPlayer = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val reqId = intent?.getStringExtra("requestId")
        if (!reqId.isNullOrEmpty()) {
            pendingRequestId = reqId
            methodChannel?.invokeMethod("onNotificationTapped", mapOf("requestId" to reqId))
        }
    }

    private fun showNativeNotification(
        title: String,
        body: String,
        requestId: String,
        tableNumber: Int,
        notificationId: Int,
        channelId: String = "waiter_requests_channel",
        sound: String = ""
    ) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val intent = (packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("requestId", requestId)
            putExtra("tableNumber", tableNumber)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(this, notificationId, intent, flags)

        val targetChannelId = if (channelId == "manager_escalation_channel" || sound == "please_hold") {
            "manager_escalation_channel"
        } else {
            "waiter_requests_channel"
        }

        val soundRes = if (targetChannelId == "manager_escalation_channel") {
            R.raw.please_hold
        } else {
            R.raw.incoming_prompt
        }

        val builder = NotificationCompat.Builder(this, targetChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setSilent(true)
            .setVibrate(longArrayOf(0, 500, 250, 500))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        notificationManager.notify(notificationId, builder.build())
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            // 1. Waiter Request Channel (Incoming_Prompt)
            val waiterSoundUri = Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/" + R.raw.incoming_prompt)
            val waiterChannel = NotificationChannel("waiter_requests_channel", "Waiter Service Requests", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "High-priority alerts when customers at assigned tables request service"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500)
                setSound(waiterSoundUri, audioAttributes)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(waiterChannel)

            // 2. Manager Escalation Channel (Please_Hold)
            val managerSoundUri = Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/" + R.raw.please_hold)
            val managerChannel = NotificationChannel("manager_escalation_channel", "Manager Escalation Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "High-priority alerts when table requests remain pending for more than 20 seconds"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500)
                setSound(managerSoundUri, audioAttributes)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(managerChannel)
        }
    }
}
