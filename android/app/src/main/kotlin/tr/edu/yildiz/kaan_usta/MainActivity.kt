package tr.edu.yildiz.kaan_usta

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

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
