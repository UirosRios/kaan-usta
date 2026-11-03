package tr.edu.yildiz.kaan_usta

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.view.KeyEvent

// Kayıt sırasında çalışan ön plan hizmeti. Ekran kilitlenince veya başka uygulamaya geçilince Android
// arka plandaki uygulamanın sensör ve konum güncellemelerini keser; bu hizmet uygulamayı "ön planda"
// tutar (bildirim çubuğunda simge) ve işlemcinin uyumasını engeller. Ölçümün kendisi Dart tarafında sürer.
//
// Çukur işareti, ekran kapalıyken: kulaklık / Bluetooth kumandanın medya tuşları ve ses tuşları bu hizmetteki
// medya oturumuna gelir (ekran açıkken MainActivity.dispatchKeyEvent yakalar).
class KayitServisi : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var oturum: MediaSession? = null
    private var sessizSes: AudioTrack? = null

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
        if (intent?.getBooleanExtra(TUSLAR, false) == true) tuslariDinle()
        return START_NOT_STICKY
    }

    // Medya oturumu: kulaklık ve medya tuşları onMediaButtonEvent'e, ses tuşları (uzak ses denetimi olarak)
    // onAdjustVolume'a gelir. Kayıt boyunca telefonun medya ses düzeyi bu tuşlarla değişmez.
    private fun tuslariDinle() {
        if (oturum != null) return
        try {
            val o = MediaSession(this, "kaan_usta_cukur_isareti")
            o.setCallback(object : MediaSession.Callback() {
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    val tus: KeyEvent? = if (Build.VERSION.SDK_INT >= 33) {
                        mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                    }
                    if (tus != null && tus.action == KeyEvent.ACTION_DOWN && tus.repeatCount == 0) isaretBildir(KAYNAK_KULAKLIK)
                    return true
                }
            })
            o.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS
                    )
                    .setState(PlaybackState.STATE_PLAYING, 0L, 1f)
                    .build()
            )
            // Ses tuşu kumandadan mı telefondan mı bilinmez: "tus" sayılır (analiz betiği o anı sarsıntı analizinden dışlar)
            o.setPlaybackToRemote(object : VolumeProvider(VolumeProvider.VOLUME_CONTROL_RELATIVE, 100, 50) {
                override fun onAdjustVolume(direction: Int) {
                    if (direction != 0) isaretBildir(KAYNAK_TUS)
                }
            })
            o.isActive = true
            oturum = o
        } catch (e: Exception) {
            // Medya oturumu açılamazsa işaret yalnızca ekrandan ve ekran açıkken tuşlardan verilir
        }
        sessizSesBaslat()
    }

    // Android 8+ medya tuşlarını en son ses çalan uygulamaya gönderir: kayıt boyunca sessiz bir ses çalınır.
    // Ses odağı istenmez; başka uygulamanın müziği durmaz (ama o sırada müzik çalan uygulama tuşları alabilir).
    private fun sessizSesBaslat() {
        if (Build.VERSION.SDK_INT < 26 || sessizSes != null) return
        try {
            val oran = 8000
            val t = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(oran)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(oran * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
            t.write(ShortArray(oran), 0, oran)
            t.setLoopPoints(0, oran, -1)
            t.play()
            sessizSes = t
        } catch (e: Exception) {
            // Sessiz ses çalınamazsa ekran kapalıyken medya tuşları başka uygulamaya gidebilir
        }
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
        oturum?.let {
            it.isActive = false
            it.release()
        }
        oturum = null
        sessizSes?.let {
            try {
                it.stop()
            } catch (e: IllegalStateException) {
                // zaten durmuş
            }
            it.release()
        }
        sessizSes = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    companion object {
        private const val KANAL = "kayit"
        private const val BILDIRIM_NO = 1

        const val TUSLAR = "tuslar" // Intent ekstrası: tuşlar çukur işareti olsun mu

        // İşaretin kaynağı (CSV'de Isaret_Kaynak): ekran ve tus telefonu sarsar, kumanda ve kulaklik sarsmaz
        const val KAYNAK_TUS = "tus"
        const val KAYNAK_KUMANDA = "kumanda"
        const val KAYNAK_KULAKLIK = "kulaklik"

        // MainActivity bunu Dart'a ileten işlevle doldurur (aynı süreç)
        @Volatile
        var isaretDinleyici: ((String) -> Unit)? = null

        fun isaretBildir(kaynak: String) {
            isaretDinleyici?.invoke(kaynak)
        }
    }
}
