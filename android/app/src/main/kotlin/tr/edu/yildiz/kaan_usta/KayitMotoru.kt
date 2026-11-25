package tr.edu.yildiz.kaan_usta

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream

// HAM VERİ KAYDI (uygulama 2.0). İvmeölçer ve jiroskop (~200 Hz), GPS alıcısının her konumu ve çukur basışları
// aynı saatle, SystemClock.elapsedRealtimeNanos ile, ikili bir dosyaya yazılır. Telefonda süzgeç uygulanmaz.
// Dart tarafı kayıt bitince bu dosyayı okuyup GeoPackage'a çevirir (lib/ham_kayit.dart).
//
// Kayıt uygulamanın sürecinde yaşar; KayitServisi yalnızca süreci ön planda ve işlemciyi uyanık tutar. Hizmet
// başlatılamasa da (ör. Android 14'te izin) kayıt ekran açıkken sürer.
//
// Dosya biçimi (büyük sonlu, java.io.DataOutputStream): başlık "KUHAM1", ardından kayıtlar. Her kayıt bir tür baytıyla başlar:
//   'S' başlangıç: t0_ns (long), duvar_saati_ms (long), sanal (byte)
//   'A' ivme:      t_ns (long), x, y, z (float, m/s², yerçekimi dahil)
//   'G' jiroskop:  t_ns (long), x, y, z (float, rad/s)
//   'L' konum:     t_ns (long), enlem, boylam, yükseklik (double), hız, yön, doğruluk, hız doğruluğu, dikey doğruluk
//                  (float; bilinmiyorsa NaN), uydu (short; bilinmiyorsa -1), gps_saati_ms (long), sanal (byte)
//   'M' işaret:    t_ns (long), kaynak (byte: 1 ekran, 2 tus, 3 kumanda, 4 kulaklik)
//   'T' saat eşi:  şimdi_ns (long), son ivme olayının zaman damgası (long), o olayın geldiği an (long)
//                  (sensör zaman damgası başka bir saate göre verilirse Dart tarafı farkı buradan düzeltir)
//   'E' bitiş:     t_ns (long)
// Dosya saniyede bir diske yazılır: uygulama çökerse en fazla son ~1 sn kaybolur, önceki veri sağlam kalır.
// Yazma hatasında (ör. telefonun hafızası doldu) o andan sonra hiçbir şey yazılmaz: yarım kalan bir kaydın ardına yeni
// kayıt eklenirse dosyanın geri kalanı okunamaz hâle gelir. Hata DURDUR'da "hata" olarak döner, kullanıcı uyarılır;
// hatadan sonra çukur basışı sayılmaz (bip gelmez).
object KayitMotoru {
    private const val BASLIK = "KUHAM1"
    private const val ORNEKLEME_US = 5000 // ~200 Hz; Android 12+'da özel izinsiz en yüksek hız
    private const val GPS_ARALIK_MS = 500L
    private const val ISARET_ARASI_NS = 1_000_000_000L // 1 sn içindeki ikinci basış sayılmaz

    private val kilit = Any()
    private var cikis: DataOutputStream? = null
    private var dosya: FileOutputStream? = null
    private var yazmaHatasi: String? = null // kilit altında; ilk yazma hatası
    private var baslangicMs = 0L // BAŞLAT anı (duvar saati, 'S' kaydındakiyle aynı)
    private var yol: String? = null
    private var is_: HandlerThread? = null
    private var isleyici: Handler? = null
    private var sm: SensorManager? = null
    private var lm: LocationManager? = null
    private var sensorDinleyici: SensorEventListener? = null
    private var konumDinleyici: LocationListener? = null
    private var gnssGeriCagri: Any? = null // GnssStatus.Callback (Android 7+)

    @Volatile private var uyduKullanilan = -1
    private var sonIsaretNs = 0L
    private var sonIvmeOlayNs = 0L
    private var sonIvmeGelisNs = 0L
    private var ivmeSayisi = 0L
    private var jiroSayisi = 0L
    private var konumSayisi = 0L
    private var isaretSayisi = 0L

    val kayitta: Boolean get() = synchronized(kilit) { cikis != null }
    val aktifYol: String? get() = synchronized(kilit) { yol }

    // Ekran yeniden kurulunca Dart süren kaydı buradan öğrenir: başlangıç anı (süre göstergesi) ve sayılan basışlar
    val durum: Map<String, Any?>
        get() = synchronized(kilit) {
            mapOf(
                "kayitta" to (cikis != null),
                "yol" to yol,
                "baslangicMs" to (if (cikis != null) baslangicMs else null),
                "isaret" to isaretSayisi,
            )
        }

    fun kaynakKodu(kaynak: String): Int = when (kaynak) {
        "ekran" -> 1
        "tus" -> 2
        "kumanda" -> 3
        "kulaklik" -> 4
        else -> 0
    }

    // Kaydı başlatır. sanal = test sürüşü: konumlar Dart'tan sanalKonum ile gelir, gerçek GPS dinlenmez.
    @SuppressLint("MissingPermission")
    fun baslat(ctx: Context, dosyaYolu: String, sanal: Boolean): Boolean {
        synchronized(kilit) {
            if (cikis != null) return false
            val f = File(dosyaYolu)
            f.parentFile?.mkdirs()
            val fos = FileOutputStream(f)
            val c = DataOutputStream(BufferedOutputStream(fos, 64 * 1024))
            val duvarMs = System.currentTimeMillis()
            try {
                c.writeBytes(BASLIK)
                c.writeByte('S'.code)
                c.writeLong(SystemClock.elapsedRealtimeNanos())
                c.writeLong(duvarMs)
                c.writeByte(if (sanal) 1 else 0)
                c.flush()
            } catch (e: Exception) {
                try {
                    fos.close()
                } catch (kapatma: Exception) {
                    // asıl hata (e) bildirilir
                }
                throw e
            }
            cikis = c
            dosya = fos
            yazmaHatasi = null
            baslangicMs = duvarMs
            yol = dosyaYolu
            sonIsaretNs = 0L
            sonIvmeOlayNs = 0L
            sonIvmeGelisNs = 0L
            ivmeSayisi = 0L
            jiroSayisi = 0L
            konumSayisi = 0L
            isaretSayisi = 0L
        }

        val t = HandlerThread("kaan_usta_kayit").apply { start() }
        val h = Handler(t.looper)
        is_ = t
        isleyici = h

        val s = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sm = s
        val d = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                when (e.sensor.type) {
                    Sensor.TYPE_ACCELEROMETER -> {
                        sonIvmeOlayNs = e.timestamp
                        sonIvmeGelisNs = SystemClock.elapsedRealtimeNanos()
                        yaz3('A', e.timestamp, e.values)
                    }
                    Sensor.TYPE_GYROSCOPE -> yaz3('G', e.timestamp, e.values)
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorDinleyici = d
        s.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { s.registerListener(d, it, ORNEKLEME_US, h) }
        s.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let { s.registerListener(d, it, ORNEKLEME_US, h) }

        if (!sanal) gpsBaslat(ctx, h)

        // Saniyede bir: saat eşi kaydı ve diske yazma
        h.postDelayed(object : Runnable {
            override fun run() {
                synchronized(kilit) {
                    val c = cikis ?: return
                    if (yazmaHatasi == null) {
                        try {
                            c.writeByte('T'.code)
                            c.writeLong(SystemClock.elapsedRealtimeNanos())
                            c.writeLong(sonIvmeOlayNs)
                            c.writeLong(sonIvmeGelisNs)
                            c.flush()
                        } catch (e: Exception) {
                            hataOldu(e)
                        }
                    }
                }
                h.postDelayed(this, 1000L)
            }
        }, 1000L)
        return true
    }

    @SuppressLint("MissingPermission")
    private fun gpsBaslat(ctx: Context, h: Handler) {
        val l = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        lm = l
        // Eski Android sürümlerinde tüm metotlar zorunlu olduğu için hepsi tanımlı
        val kd = object : LocationListener {
            override fun onLocationChanged(loc: Location) = konumYaz(loc)
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}

            @Deprecated("Android 10 ve öncesi için gerekli")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        try {
            l.requestLocationUpdates(LocationManager.GPS_PROVIDER, GPS_ARALIK_MS, 0f, kd, h.looper)
            konumDinleyici = kd
        } catch (e: Exception) {
            // Konum izni yok: sensörler yine kaydedilir, kayıtta GPS noktası olmaz
        }
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                val cb = object : GnssStatus.Callback() {
                    override fun onSatelliteStatusChanged(status: GnssStatus) {
                        var n = 0
                        for (i in 0 until status.satelliteCount) if (status.usedInFix(i)) n++
                        uyduKullanilan = n
                    }
                }
                @Suppress("DEPRECATION")
                l.registerGnssStatusCallback(cb, h)
                gnssGeriCagri = cb
            } catch (e: Exception) {
                // Uydu sayısı okunamazsa -1 yazılır
            }
        }
    }

    // Kilit altında çağrılır: ilk hata saklanır, sonrası yazılmaz
    private fun hataOldu(e: Exception) {
        if (yazmaHatasi == null) yazmaHatasi = e.message ?: e.javaClass.simpleName
    }

    private fun yaz3(tur: Char, tNs: Long, v: FloatArray) {
        synchronized(kilit) {
            val c = cikis ?: return
            if (yazmaHatasi != null) return
            try {
                c.writeByte(tur.code)
                c.writeLong(tNs)
                c.writeFloat(v[0])
                c.writeFloat(v[1])
                c.writeFloat(v[2])
                if (tur == 'A') ivmeSayisi++ else jiroSayisi++
            } catch (e: Exception) {
                hataOldu(e)
            }
        }
    }

    private fun konumYaz(loc: Location) {
        val hizDog = if (Build.VERSION.SDK_INT >= 26 && loc.hasSpeedAccuracy()) loc.speedAccuracyMetersPerSecond else Float.NaN
        val dikeyDog = if (Build.VERSION.SDK_INT >= 26 && loc.hasVerticalAccuracy()) loc.verticalAccuracyMeters else Float.NaN
        konumKaydi(
            loc.elapsedRealtimeNanos, loc.latitude, loc.longitude,
            if (loc.hasAltitude()) loc.altitude else Double.NaN,
            if (loc.hasSpeed()) loc.speed else Float.NaN,
            if (loc.hasBearing()) loc.bearing else Float.NaN,
            if (loc.hasAccuracy()) loc.accuracy else Float.NaN,
            hizDog, dikeyDog, uyduKullanilan, loc.time, false,
        )
    }

    // Test sürüşü: Dart'taki sanal turdan gelen konum (zaman damgası geldiği an)
    fun sanalKonum(enlem: Double, boylam: Double, hizMs: Double, dogrulukM: Double) {
        konumKaydi(
            SystemClock.elapsedRealtimeNanos(), enlem, boylam, Double.NaN, hizMs.toFloat(), Float.NaN,
            dogrulukM.toFloat(), Float.NaN, Float.NaN, -1, System.currentTimeMillis(), true,
        )
    }

    private fun konumKaydi(
        tNs: Long, enlem: Double, boylam: Double, yukseklik: Double, hiz: Float, yon: Float, dogruluk: Float,
        hizDog: Float, dikeyDog: Float, uydu: Int, gpsSaatiMs: Long, sanal: Boolean,
    ) {
        synchronized(kilit) {
            val c = cikis ?: return
            if (yazmaHatasi != null) return
            try {
                c.writeByte('L'.code)
                c.writeLong(tNs)
                c.writeDouble(enlem)
                c.writeDouble(boylam)
                c.writeDouble(yukseklik)
                c.writeFloat(hiz)
                c.writeFloat(yon)
                c.writeFloat(dogruluk)
                c.writeFloat(hizDog)
                c.writeFloat(dikeyDog)
                c.writeShort(uydu)
                c.writeLong(gpsSaatiMs)
                c.writeByte(if (sanal) 1 else 0)
                konumSayisi++
            } catch (e: Exception) {
                hataOldu(e)
            }
        }
    }

    // Çukur basışı. 1 sn içindeki ikinci basış sayılmaz (çift basma, kumandanın tuş sekmesi). Sayıldıysa true.
    fun isaret(kaynak: String): Boolean {
        val simdi = SystemClock.elapsedRealtimeNanos()
        synchronized(kilit) {
            val c = cikis ?: return false
            if (yazmaHatasi != null) return false
            if (sonIsaretNs != 0L && simdi - sonIsaretNs < ISARET_ARASI_NS) return false
            try {
                c.writeByte('M'.code)
                c.writeLong(simdi)
                c.writeByte(kaynakKodu(kaynak))
                c.flush() // işaret hemen diske
            } catch (e: Exception) {
                hataOldu(e)
                return false
            }
            sonIsaretNs = simdi
            isaretSayisi++
            return true
        }
    }

    // Kaydı bitirir; dosya kapanınca döner. Kayıt yoksa null.
    fun durdur(): Map<String, Any?>? {
        sensorDinleyici?.let { d -> sm?.unregisterListener(d) }
        sensorDinleyici = null
        konumDinleyici?.let { k -> lm?.removeUpdates(k) }
        konumDinleyici = null
        if (Build.VERSION.SDK_INT >= 24) {
            (gnssGeriCagri as? GnssStatus.Callback)?.let { lm?.unregisterGnssStatusCallback(it) }
        }
        gnssGeriCagri = null
        isleyici?.removeCallbacksAndMessages(null)
        is_?.quitSafely()
        is_ = null
        isleyici = null
        uyduKullanilan = -1

        synchronized(kilit) {
            val c = cikis ?: return null
            var hata: String? = yazmaHatasi?.let { "kayıt sırasında yazılamadı: $it" }
            if (hata == null) {
                try {
                    c.writeByte('E'.code)
                    c.writeLong(SystemClock.elapsedRealtimeNanos())
                    c.flush()
                } catch (e: Exception) {
                    hata = "kapanırken yazılamadı: ${e.message ?: e.javaClass.simpleName}"
                }
            }
            // Dosya doğrudan kapatılır: yazma hatasından sonra tampondaki yarım kayıt yeniden yazılmasın
            try {
                dosya?.close()
            } catch (e: Exception) {
                if (hata == null) hata = "kapanırken: ${e.message ?: e.javaClass.simpleName}"
            }
            val sonuc = mapOf(
                "yol" to yol,
                "ivme" to ivmeSayisi,
                "jiro" to jiroSayisi,
                "konum" to konumSayisi,
                "isaret" to isaretSayisi,
                "hata" to hata,
            )
            cikis = null
            dosya = null
            yazmaHatasi = null
            yol = null
            return sonuc
        }
    }
}
