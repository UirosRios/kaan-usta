import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SensorDashboard(),
    );
  }
}

class SensorDashboard extends StatefulWidget {
  const SensorDashboard({super.key});

  @override
  State<SensorDashboard> createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard> {
  // Sensör ve Veri Değişkenleri
  double zAxis = 0.0;
  double currentLat = 0.0;
  double currentLon = 0.0;
  double currentSpeed = 0.0; // Mantıksal (Ölü Bölge Filtreli) Hız
  double currentRawSpeed = 0.0; // Ham (Seken) GPS Hızı
  double currentAccuracy = 0.0; // GPS yatay konum doğruluğu (m)
  DateTime? lastFixTime; // Son geçerli GPS konumunun zamanı
  bool isRecording = false;
  String _gpsStatus = "GPS bekleniyor...";

  // Kayıt penceresi (500 ms) içindeki tüm Z örnekleri.
  // İvmeölçer ~50 Hz okunur; pencere başına istatistik çıkarılır ki
  // 2 Hz kayıtta tek anlık değer alınmasından doğan örtüşme (aliasing) olmasın.
  final List<double> _zWindow = [];

  // Zamanlayıcı ve Veri Kayıt Değişkenleri
  String _liveDate = "Tarih Yükleniyor...";
  String _liveTime = "Saat Yükleniyor...";
  Timer? _clockTimer;
  Timer? _uiTimer;
  Timer? _recordTimer;
  List<String> recordedData = [];

  // Abonelikler
  StreamSubscription<Position>? geoSubscription;
  StreamSubscription<AccelerometerEvent>? accelSubscription;

  @override
  void initState() {
    super.initState();
    _startClock();
    _initSensors();
  }

  // 1. Canlı Saat ve Tarih Fonksiyonu
  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final now = DateTime.now();
      final List<String> aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
      final List<String> gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

      setState(() {
        _liveDate = "${now.day} ${aylar[now.month - 1]} ${now.year} ${gunler[now.weekday - 1]}";
        _liveTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      });
    });

    // Ekrandaki Z değerini saniyede 5 kez yenile (her sensör olayında setState yapmamak için)
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (mounted) setState(() {});
    });
  }

  // 2. Sensörleri (GPS ve Z-Ekseni) Başlatma Fonksiyonu
  Future<void> _initSensors() async {
    // Z-Ekseni (İvmeölçer) Sensörünü Başlat
    // gameInterval = 20 ms (~50 Hz). Varsayılan (normalInterval) 200 ms olup sarsıntı için çok yavaştır.
    accelSubscription = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((AccelerometerEvent event) {
      zAxis = event.z;
      if (isRecording) _zWindow.add(event.z);
    });

    // Konum servisi (GPS) açık mı?
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _gpsStatus = "Konum servisi kapalı! Lütfen GPS'i açın.");
      return;
    }

    // İzin Kontrolü
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      if (mounted) setState(() => _gpsStatus = "GPS sinyali aranıyor...");
      // Yüksek Hassasiyetli GPS'i Başlat
      geoSubscription = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation, // Tez için en yüksek hassasiyet
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: 500),
          forceLocationManager: true, // Ham GNSS hızını doğrudan almak için (Fused yerine)
        ),
      ).listen((Position position) {
        if (mounted) {
          // 50 metreden büyük çok ekstrem sapmaları yoksay (hassasiyet korunur)
          if (position.accuracy > 50.0) return;

          setState(() {
            _gpsStatus = "";
            currentLat = position.latitude;
            currentLon = position.longitude;
            currentAccuracy = position.accuracy;
            lastFixTime = DateTime.now();

            // Uydudan gelen gerçek (sekme payı olan) ham hız
            currentRawSpeed = position.speed < 0 ? 0.0 : position.speed * 3.6;

            // MANTIKSAL ÖLÜ BÖLGE FİLTRESİ: Kapalı alandaki 2 km/h altı mikro sekmeleri sıfırla
            currentSpeed = currentRawSpeed < 2.0 ? 0.0 : currentRawSpeed;
          });
        }
      });
    } else {
      if (mounted) setState(() => _gpsStatus = "Konum izni verilmedi! Ayarlardan izin verin.");
    }
  }

  // 3. KAYIT BAŞLATMA MOTORU
  void startRecording() {
    setState(() {
      isRecording = true;
    });
    // Kayıt sırasında ekranın kapanıp sensörlerin durmasını engelle
    WakelockPlus.enable();

    // Her yeni kayıtta listeyi temizle ve teze uygun CSV Başlıklarını ekle
    recordedData.clear();
    _zWindow.clear();
    recordedData.add("Tarih_Saat,Enlem,Boylam,Mantiksal_Hiz_kmh,Ham_Hiz_kmh,Z_Ekseni,"
        "Z_Ort,Z_RMS_Dinamik,Z_Min,Z_Max,Z_Ornek_Sayisi,GPS_Dogruluk_m,GPS_Yasi_s");

    // Saniyede 2 kez (500 milisaniye) veri örnekleme
    _recordTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!isRecording) {
        timer.cancel();
        return;
      }

      // Pencere içindeki Z örneklerinin istatistikleri
      // Z_RMS_Dinamik: ortalama (yerçekimi + eğim) çıkarıldıktan sonraki RMS = sarsıntı şiddeti
      final samples = List<double>.from(_zWindow);
      _zWindow.clear();
      double zMean = 0, zRms = 0, zMin = 0, zMax = 0;
      if (samples.isNotEmpty) {
        zMean = samples.reduce((a, b) => a + b) / samples.length;
        zRms = sqrt(samples.map((z) => (z - zMean) * (z - zMean)).reduce((a, b) => a + b) / samples.length);
        zMin = samples.reduce(min);
        zMax = samples.reduce(max);
      }

      // Son GPS konumundan bu yana geçen süre (GPS kesilirse eski konum tekrarlanır, bu sütunla ayıklanabilir)
      final String gpsAge = lastFixTime == null ? "" : (DateTime.now().difference(lastFixTime!).inMilliseconds / 1000).toStringAsFixed(1);

      // O anki sensör verilerini CSV formatında virgülle ayırarak kaydet
      String timestamp = DateTime.now().toString();
      String row = "$timestamp,${currentLat.toStringAsFixed(6)},${currentLon.toStringAsFixed(6)},${currentSpeed.toStringAsFixed(2)},${currentRawSpeed.toStringAsFixed(2)},${zAxis.toStringAsFixed(4)},"
          "${zMean.toStringAsFixed(4)},${zRms.toStringAsFixed(4)},${zMin.toStringAsFixed(4)},${zMax.toStringAsFixed(4)},${samples.length},${currentAccuracy.toStringAsFixed(1)},$gpsAge";
      recordedData.add(row);
    });
  }

  // 4. KAYIT BİTİRME VE PAYLAŞMA MOTORU
  Future<void> stopRecording() async {
    setState(() {
      isRecording = false;
    });
    _recordTimer?.cancel();
    WakelockPlus.disable();

    if (recordedData.length <= 1) return;

    try {
      // Cihazın güvenli klasörünü bul ve dosyayı oluştur
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/mikromobilite_tez_verisi_${DateTime.now().millisecondsSinceEpoch}.csv';
      final File file = File(filePath);

      // Verileri alt alta (.csv formatında) dosyaya yaz
      await file.writeAsString(recordedData.join('\n'));

      // Dosyayı paylaşım ekranına (WhatsApp, Mail, Drive vb.) gönder
      await SharePlus.instance.share(ShareParams(files: [XFile(filePath)], text: 'Tez Sensör Verisi (CSV) - KAAN USTA'));
    } catch (e) {
      debugPrint("Dosya kaydedilirken hata oluştu: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Dosya kaydedilemedi: $e")));
      }
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _uiTimer?.cancel();
    _recordTimer?.cancel();
    geoSubscription?.cancel();
    accelSubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEF),
      body: SafeArea(
        child: Column(
          children: [
            // YTÜ Özel Başlık Alanı (Genişletilmiş Logolu ve Boşluklu Tasarım)
            Container(
              color: const Color(0xFF003366),
              padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8, right: 10),
              height: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "KAAN USTA",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(_liveDate, style: const TextStyle(color: Color(0xFFCED4DA), fontSize: 12)),
                      Text(_liveTime, style: const TextStyle(color: Color(0xFFCED4DA), fontSize: 12)),
                    ],
                  ),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(-2, 0))],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: Image.network(
                        "https://upload.wikimedia.org/wikipedia/commons/3/37/Y%C4%B1ld%C4%B1z_Technical_University_Logo.png",
                        fit: BoxFit.contain,
                        // İnternet yoksa (sahada) uygulama çökmesin, boş daire göster
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // İçerik Alanı ve Kartlar
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Z-Ekseni Kartı
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            const Text('Z-EKSENİ SARSINTI', style: TextStyle(fontSize: 14, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 10),
                            Text(
                              zAxis.toStringAsFixed(3),
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF003366))
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Alt Alta Hız ve Koordinat Kartı
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            // Mantıksal (Filtrelenmiş) Hız
                            const Text('MANTIKSAL HIZ (km/h)', style: TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(
                              currentSpeed.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF198754))
                            ),

                            const SizedBox(height: 12),

                            // Ham (Seken) GPS Hızı
                            const Text('HAM GPS HIZI (km/h)', style: TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(
                              currentRawSpeed.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFFD7E14))
                            ),

                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Divider(color: Color(0xFFDEE2E6), thickness: 1),
                            ),

                            // Koordinatlar
                            const Text('KOORDİNATLAR (Enlem / Boylam)', style: TextStyle(fontSize: 14, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 10),
                            Text(
                              '${currentLat.toStringAsFixed(5)} / ${currentLon.toStringAsFixed(5)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF212529))
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _gpsStatus.isNotEmpty ? _gpsStatus : 'Doğruluk: ±${currentAccuracy.toStringAsFixed(1)} m',
                              style: TextStyle(fontSize: 12, color: _gpsStatus.isNotEmpty ? Colors.redAccent : const Color(0xFF6C757D)),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // BAŞLAT / DURDUR Butonu
                    ElevatedButton(
                      onPressed: isRecording ? stopRecording : startRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRecording ? Colors.redAccent : const Color(0xFF198754),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 4,
                      ),
                      child: Text(
                        isRecording ? 'DURDUR (${recordedData.length - 1} satır)' : 'BAŞLAT',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
