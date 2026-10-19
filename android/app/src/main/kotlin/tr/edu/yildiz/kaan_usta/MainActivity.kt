package tr.edu.yildiz.kaan_usta

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Ham GPS: Fused / birleşik konum servisini atlayıp doğrudan GPS donanımını (GPS_PROVIDER) dinler.
// Hız, GNSS yongasının Doppler ölçümünden gelir; yumuşatma yapılmaz.
class MainActivity : FlutterActivity() {
    private var listener: LocationListener? = null

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
                }

                override fun onCancel(arguments: Any?) {
                    stopRawGps()
                }
            })

        // Cihaz ve sensör bilgisi: her kaydın _bilgi.txt dosyasına ve Teknik Bilgi sayfasına yazılır
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaan_usta/cihaz")
            .setMethodCallHandler { call, result ->
                if (call.method == "bilgi") result.success(deviceInfo()) else result.notImplemented()
            }
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
            "gyroscope" to sensorInfo(sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)),
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

    private fun locationManager() = getSystemService(Context.LOCATION_SERVICE) as LocationManager

    private fun stopRawGps() {
        listener?.let { locationManager().removeUpdates(it) }
        listener = null
    }

    override fun onDestroy() {
        stopRawGps()
        super.onDestroy()
    }
}
