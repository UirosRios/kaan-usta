package tr.edu.yildiz.kaan_usta

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

// Kayıt sırasında çalışan ön plan hizmeti. Ekran kilitlenince veya başka uygulamaya geçilince Android
// arka plandaki uygulamanın sensör ve konum güncellemelerini keser; bu hizmet uygulamayı "ön planda"
// tutar (bildirim çubuğunda simge) ve işlemcinin uyumasını engeller. Ölçümün kendisi Dart tarafında sürer.
class KayitServisi : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val ac = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val bildirim = bildirimOlusturucu()
            .setContentTitle("Mikromobilite Veri Aracı")
            .setContentText("Sürüş kaydı sürüyor")
            .setSmallIcon(R.drawable.ic_kayit)
            .setContentIntent(ac)
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(BILDIRIM_NO, bildirim, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(BILDIRIM_NO, bildirim)
            }
        } catch (e: Exception) {
            // Konum izni yoksa (Android 14+) ön plan hizmeti başlatılamaz; kayıt yalnızca ekran açıkken sürer
            stopSelf()
            return START_NOT_STICKY
        }
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kaan_usta:kayit").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L) // en fazla 6 saat
            }
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun bildirimOlusturucu(): Notification.Builder {
        if (Build.VERSION.SDK_INT < 26) return Notification.Builder(this)
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(KANAL, "Sürüş kaydı", NotificationManager.IMPORTANCE_LOW))
        return Notification.Builder(this, KANAL)
    }

    // Uygulama son uygulamalar listesinden kaydırılınca ölçüm de biter: hizmet asılı kalmasın
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    companion object {
        private const val KANAL = "kayit"
        private const val BILDIRIM_NO = 1
    }
}
