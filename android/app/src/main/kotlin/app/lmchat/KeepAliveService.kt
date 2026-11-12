package app.lmchat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app process alive while an answer is being generated.
 *
 * Android freezes background processes, which stalls the streaming HTTP
 * connection. A foreground service with a partial wake lock keeps the process
 * out of the freezer and the network alive. The actual generation may also run
 * on the GPU bridge, in which case this service only keeps the UI attached.
 */
class KeepAliveService : Service() {
    companion object {
        const val CHANNEL_ID = "lm_chat_generation"
        const val NOTIFICATION_ID = 41
        const val EXTRA_TEXT = "text"
        const val ACTION_START = "app.lmchat.KEEP_ALIVE_START"

        fun start(context: Context, text: String) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KeepAliveService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "lm_chat:generation")
            .apply {
                setReferenceCounted(false)
                acquire(60 * 60 * 1000L)
            }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Готовится ответ…"
        startInForeground(text)
        return START_NOT_STICKY
    }

    private fun startInForeground(text: String) {
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("LM Chat")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_lm_chat)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Генерация ответа",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Показывает, что LM Chat готовит ответ в фоне"
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
