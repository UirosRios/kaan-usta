package tr.edu.yildiz.kaan_usta

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Ham GPS: Fused / birleşik konum servisini atlayıp doğrudan GPS donanımını (GPS_PROVIDER) dinler.
// Hız, GNSS yongasının Doppler ölçümünden gelir; yumuşatma yapılmaz.
class MainActivity : FlutterActivity() {
    private var listener: LocationListener? = null
    private var gnssCallback: Any? = null // GnssStatus.Callback (Android 7+)
    private var kayitta = false // kayıt sürerken tuşlar çukur işareti olur
    private var isaretKanali: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "kaan_usta/ham_gps")
            .setStreamHandler(object : EventChannel.StreamHandler {
                @SuppressLint("MissingPermission")
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopRawGps()
                    // Eski Android sürümlerinde tüm metotlar zorunlu olduğu için hepsi tanımlı
                    val l = object : LocationListener {
                        override fun onLocationChanged(loc: Location) {
                            events.success(
                                mapOf(
                                    "type" to "fix",
                                    "lat" to loc.latitude,
                                    "lon" to loc.longitude,
                                    "speed" to if (loc.hasSpeed()) loc.speed.toDouble() else -1.0,
                                    "accuracy" to if (loc.hasAccuracy()) loc.accuracy.toDouble() else -1.0,
                                )
                            )
                        }

                        override fun onProviderEnabled(provider: String) {}
                        override fun onProviderDisabled(provider: String) {}

                        @Deprecated("Android 10 ve öncesi için gerekli")
                        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    }
                    try {
                        locationManager().requestLocationUpdates(
                            LocationManager.GPS_PROVIDER, 500L, 0f, l, Looper.getMainLooper()
                        )
                        listener = l
                    } catch (e: Exception) {
                        events.error("HAM_GPS", e.message, null)
                    }

                    // Uydu durumu (tanı için): kaç uydu görülüyor, kaçı konum çözümünde kullanılıyor
                    if (Build.VERSION.SDK_INT >= 24) {
                        try {
                            val cb = object : GnssStatus.Callback() {
                                override fun onSatelliteStatusChanged(status: GnssStatus) {
                                    var used = 0
                                    for (i in 0 until status.satelliteCount) if (status.usedInFix(i)) used++
                                    events.success(mapOf("type" to "sat", "visible" to status.satelliteCount, "used" to used))
                                }
                            }
                            locationManager().registerGnssStatusCallback(cb, Handler(Looper.getMainLooper()))
                            gnssCallback = cb
                        } catch (e: Exception) {
                            // Yalnızca yaklaşık konum izni varsa uydu durumu okunamaz; konum yine de dinlenir
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    stopRawGps()
                }
            })

        // Çukur işareti: tuşlardan gelen basışlar Dart'a iletilir (kaynak: tus / kumanda / kulaklik)
        val kanal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaan_usta/isaret")
        isaretKanali = kanal
        val anaIs = Handler(Looper.getMainLooper())
        KayitServisi.isaretDinleyici = { kaynak -> anaIs.post { isaretKanali?.invokeMethod("isaret", kaynak) } }

        // Kayıt sırasında ön plan hizmeti (KayitServisi.kt): ekran kapalıyken de ölçüm sürer
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaan_usta/kayit_servisi")
            .setMethodCallHandler { call, result ->
                val intent = Intent(this, KayitServisi::class.java)
                when (call.method) {
                    "baslat" -> {
                        kayitta = true
                        // Android 13+: bildirim izni (verilmezse hizmet yine çalışır, yalnızca bildirim görünmez)
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 1)
                        }
                        // Konum izni yoksa konum türü ön plan hizmeti başlatılamaz (Android 14+); hizmetsiz devam edilir
                        val konumIzni = listOf("android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION")
                            .any { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
                        if (!konumIzni) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("KAYIT_SERVISI", e.message, null)
                        }
                    }
                    "durdur" -> {
                        kayitta = false
                        stopService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Cihaz ve sensör bilgisi: her kaydın _bilgi.txt dosyasına ve Teknik Bilgi sayfasına yazılır
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaan_usta/cihaz")
            .setMethodCallHandler { call, result ->
                if (call.method == "bilgi") result.success(deviceInfo()) else result.notImplemented()
            }
    }

    companion object {
        private val MEDYA_TUSLARI = setOf(
            KeyEvent.KEYCODE_HEADSETHOOK, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_MEDIA_NEXT, KeyEvent.KEYCODE_MEDIA_PREVIOUS,
        )
        private val ISARET_TUSLARI = MEDYA_TUSLARI + setOf(
            KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_CAMERA,
        )
    }

    @Suppress("DEPRECATION")
    private fun deviceInfo(): Map<String, Any?> {
        val pi = packageManager.getPackageInfo(packageName, 0)
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "appVersion" to pi.versionName,
            "appBuild" to (if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()),
            "accelerometer" to sensorInfo(sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)),
        )
    }

    private fun sensorInfo(s: Sensor?): Map<String, Any?>? = s?.let {
        mapOf(
            "name" to it.name,
            "vendor" to it.vendor,
            "resolution" to it.resolution.toDouble(),
            "maxRange" to it.maximumRange.toDouble(),
            "minDelayUs" to it.minDelay, // en kısa örnekleme aralığı (µs); 0 = olay tabanlı
        )
    }

    // Ekran açıkken: telefonun ses tuşları, Bluetooth kumanda (çoğu ses açma veya Enter gönderir) ve kulaklık tuşu.
    // Kayıt sırasında bu tuşlar çukur işareti olur ve başka işe yaramaz; kayıt yokken normal çalışır.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (kayitta && event.keyCode in ISARET_TUSLARI) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) KayitServisi.isaretBildir(kaynak(event))
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun kaynak(event: KeyEvent): String = when {
        event.keyCode in MEDYA_TUSLARI -> KayitServisi.KAYNAK_KULAKLIK
        // Telefonun kendi tuşları dahili aygıttır; Bluetooth / USB kumanda harici (Android 10+ ayırt edilebilir)
        Build.VERSION.SDK_INT >= 29 && event.device?.isExternal == true -> KayitServisi.KAYNAK_KUMANDA
        else -> KayitServisi.KAYNAK_TUS
    }

    private fun locationManager() = getSystemService(Context.LOCATION_SERVICE) as LocationManager

    private fun stopRawGps() {
        listener?.let { locationManager().removeUpdates(it) }
        listener = null
        if (Build.VERSION.SDK_INT >= 24) {
            (gnssCallback as? GnssStatus.Callback)?.let { locationManager().unregisterGnssStatusCallback(it) }
        }
        gnssCallback = null
    }

    override fun onDestroy() {
        stopRawGps()
        KayitServisi.isaretDinleyici = null
        isaretKanali = null
        // Ekran yok edilince ölçüm (Dart tarafı) da biter; kayıt hizmeti ve bildirimi asılı kalmasın
        stopService(Intent(this, KayitServisi::class.java))
        super.onDestroy()
    }
}
