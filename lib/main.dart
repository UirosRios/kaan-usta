import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'about_page.dart';
import 'device_info.dart';
import 'recordings_page.dart';

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

class _SensorDashboardState extends State<SensorDashboard> with WidgetsBindingObserver {
  // Sensör ve Veri Değişkenleri
  double zAxis = 0.0; // Ham Z ivmesi (yerçekimi dahil)
  double zNet = 0.0; // Yerçekimi çıkarılmış Z ivmesi (telefonun kendi ekseni)
  double verticalNet = 0.0; // Dikey sarsıntı: titreşimin gerçek düşey (yerçekimi) yönündeki bileşeni
  double totalNet = 0.0; // Toplam sarsıntı: üç eksendeki titreşimin büyüklüğü (yönden bağımsız)
  double tiltDeg = 0.0; // Telefonun yataydan eğimi (derece); ekran yukarı ve yatayken 0
  double gyroX = 0.0, gyroY = 0.0, gyroZ = 0.0; // Jiroskop açısal hızı (rad/s)
  bool gyroAvailable = true;
  double currentLat = 0.0;
  double currentLon = 0.0;
  double currentRawSpeed = 0.0; // Ham (Seken) GPS Hızı - doğrudan GPS donanımı
  double currentFusedSpeed = 0.0; // Düzeltilmiş GPS Hızı - Fused (birleşik) konum servisi
  double currentAccuracy = 0.0; // Ham GPS yatay konum doğruluğu (m)
  DateTime? lastFixTime; // Son geçerli ham GPS konumunun zamanı
  DateTime? lastFusedFixTime; // Son geçerli düzeltilmiş GPS konumunun zamanı
  bool isRecording = false;
  String _gpsStatus = "GPS bekleniyor...";
  // GPS tanı bilgisi: uydu sayısı, 50 m filtresine takılan son doğruluk, durum yazısına dokununca açılacak ayar
  int? _satVisible, _satUsed;
  double? _rejectedAccuracy;
  VoidCallback? _gpsStatusAction;
  bool _initializingLocation = false;

  // Harita (OpenStreetMap / flutter_map): o anki ham GPS konumunu takip eder
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // Kayıt penceresi (500 ms) içindeki tüm Z örnekleri.
  // İvmeölçer ~50 Hz okunur; pencere başına istatistik çıkarılır ki
  // 2 Hz kayıtta tek anlık değer alınmasından doğan örtüşme (aliasing) olmasın.
  final List<double> _zWindow = [];
  final List<double> _zNetWindow = [];
  final List<double> _verticalWindow = [];
  final List<double> _totalWindow = [];
  final List<double> _tiltWindow = [];

  // YERÇEKİMİ GİDERME: ivmenin üç ekseni de 0,4 Hz kesim frekanslı birinci dereceden yüksek geçiren filtreden
  // geçirilir (bilineer / Tustin dönüşümü). Filtre çıkışı titreşimdir; ham ivme − titreşim = yerçekimi vektörü,
  // yani telefonun o anki "aşağı" yönü. 0,4 Hz, ISO 2631-1 titreşim değerlendirmesinin alt bant sınırıdır.
  static const double gravityCutoffHz = 0.4;
  static const double _gravityTau = 1 / (2 * pi * gravityCutoffHz);
  List<double>? _prevAcc; // önceki ham ivme [x, y, z]
  final List<double> _dynAcc = [0.0, 0.0, 0.0]; // titreşim bileşeni [x, y, z]
  DateTime? _lastAccelTime;
  // Aynı pencere içindeki jiroskop örnekleri [x, y, z]
  final List<List<double>> _gyroWindow = [];

  // Zamanlayıcı ve Veri Kayıt Değişkenleri
  String _liveDate = "Tarih Yükleniyor...";
  String _liveTime = "Saat Yükleniyor...";
  Timer? _clockTimer;
  Timer? _uiTimer;
  Timer? _recordTimer;

  // Kayıt dosyası: satırlar 5 saniyede bir dosyaya eklenir (uygulama kapanırsa en fazla son 5 sn kaybolur)
  static const String _csvHeader = "Tarih_Saat,Enlem,Boylam,Ham_Hiz_kmh,Duzeltilmis_GPS_Hiz_kmh,"
      "Dikey_Net,Dikey_RMS,Dikey_Min,Dikey_Max,Toplam_RMS,Egim_derece,"
      "Z_Net,Z_Ham,Z_Ham_Ort,Z_Net_RMS,Z_Net_Min,Z_Net_Max,Ivme_Ornek_Sayisi,"
      "Jiro_X_Ort,Jiro_Y_Ort,Jiro_Z_Ort,Jiro_Max_Bileske,"
      "GPS_Dogruluk_m,GPS_Yasi_s,Duzeltilmis_GPS_Yasi_s";
  File? _csvFile;
  DateTime? _recordStart;
  int _rowCount = 0;
  final List<String> _pendingRows = [];
  Future<void> _writeChain = Future.value();
  bool _writeError = false;
  bool _busy = false; // başlatma/durdurma sürerken düğmeye ikinci kez basılmasını engeller

  // Abonelikler
  // Ham GPS, Android tarafında (MainActivity.kt) GPS_PROVIDER'dan okunur
  static const EventChannel _rawGpsChannel = EventChannel('kaan_usta/ham_gps');
  StreamSubscription<dynamic>? rawGpsSubscription;
  StreamSubscription<Position>? geoSubscription;
  StreamSubscription<AccelerometerEvent>? accelSubscription;
  StreamSubscription<GyroscopeEvent>? gyroSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceInfo.load();
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
      final acc = [event.x, event.y, event.z];

      // Her eksene yüksek geçiren filtre: y = k/(k+1)·(a − a_önceki) + (k−1)/(k+1)·y_önceki, k = 2τ/dt
      // İlk örnekte veya 1 sn'den uzun boşlukta sıfırlanır.
      final last = _lastAccelTime;
      _lastAccelTime = event.timestamp;
      final double dt = last == null ? 0 : event.timestamp.difference(last).inMicroseconds / 1e6;
      if (_prevAcc == null || dt <= 0 || dt > 1) {
        _dynAcc.fillRange(0, 3, 0.0);
      } else {
        final double k = 2 * _gravityTau / dt;
        for (int i = 0; i < 3; i++) {
          _dynAcc[i] = k / (k + 1) * (acc[i] - _prevAcc![i]) + (k - 1) / (k + 1) * _dynAcc[i];
        }
      }
      _prevAcc = acc;

      // Yerçekimi vektörü = ham ivme − titreşim. Telefon hangi açıda durursa dursun gerçek düşeyi gösterir.
      final double gx = acc[0] - _dynAcc[0], gy = acc[1] - _dynAcc[1], gz = acc[2] - _dynAcc[2];
      final double gNorm = sqrt(gx * gx + gy * gy + gz * gz);
      // Dikey sarsıntı: titreşimin yerçekimi yönüne izdüşümü (yukarı +)
      verticalNet = gNorm > 0 ? (_dynAcc[0] * gx + _dynAcc[1] * gy + _dynAcc[2] * gz) / gNorm : 0.0;
      // Toplam sarsıntı: titreşim vektörünün büyüklüğü
      totalNet = sqrt(_dynAcc[0] * _dynAcc[0] + _dynAcc[1] * _dynAcc[1] + _dynAcc[2] * _dynAcc[2]);
      // Eğim: telefonun Z ekseni (ekrana dik) ile gerçek düşey arasındaki açı
      tiltDeg = gNorm > 0 ? acos((gz / gNorm).clamp(-1.0, 1.0)) * 180 / pi : 0.0;
      // Z sarsıntısı (telefonun kendi ekseni): Z ekseninin titreşim bileşeni
      zNet = _dynAcc[2];

      if (isRecording) {
        _zWindow.add(event.z);
        _zNetWindow.add(zNet);
        _verticalWindow.add(verticalNet);
        _totalWindow.add(totalNet);
        _tiltWindow.add(tiltDeg);
      }
    });

    // Jiroskop (açısal hız) Sensörünü Başlat - ivmeölçerle aynı hızda (~50 Hz)
    // Telefonun tutucuda eğilmesi / dönmesi bu sensörle izlenir
    gyroSubscription = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((GyroscopeEvent event) {
      gyroX = event.x;
      gyroY = event.y;
      gyroZ = event.z;
      if (isRecording) _gyroWindow.add([event.x, event.y, event.z]);
    }, onError: (Object e) {
      // Bazı ucuz telefonlarda jiroskop bulunmaz
      if (mounted) setState(() => gyroAvailable = false);
    });

    await _initLocation();
  }

  // GPS'i başlat. Ayarlardan dönüldüğünde (izin/konum açıldıysa) tekrar çağrılır.
  Future<void> _initLocation() async {
    // İzin penceresi açılırken uygulama duraklar/devam eder; aynı anda iki kez başlatılmasın
    if (_initializingLocation) return;
    _initializingLocation = true;
    try {
      await _startLocationStreams();
    } finally {
      _initializingLocation = false;
    }
  }

  Future<void> _startLocationStreams() async {
    await rawGpsSubscription?.cancel();
    await geoSubscription?.cancel();
    rawGpsSubscription = null;
    geoSubscription = null;
    _satVisible = null;
    _satUsed = null;
    _rejectedAccuracy = null;
    _gpsStatusAction = null;

    // Konum servisi (GPS) açık mı?
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(() {
          _gpsStatus = "Konum servisi kapalı! Açmak için dokunun.";
          _gpsStatusAction = Geolocator.openLocationSettings;
        });
      }
      return;
    }

    // İzin Kontrolü
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      // Android 12+: kullanıcı "Yaklaşık konum" seçtiyse konum ~2 km hatalı gelir ve 50 m filtresine takılır
      final bool reduced = await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced;
      if (mounted) {
        setState(() {
          if (reduced) {
            _gpsStatus = "Yalnızca YAKLAŞIK konum izni var! Dokunun: İzinler > Konum > 'Kesin konum kullan'ı açın.";
            _gpsStatusAction = Geolocator.openAppSettings;
          } else {
            _gpsStatus = "GPS sinyali aranıyor... (açık alanda ilk konum 1-2 dk sürebilir)";
          }
        });
      }
      // HAM GPS: Doğrudan GPS donanımı (yumuşatma yok). Enlem/Boylam, doğruluk ve harita konumu buradan gelir.
      rawGpsSubscription = _rawGpsChannel.receiveBroadcastStream().listen((dynamic event) {
        if (!mounted) return;
        final m = event as Map;
        // Uydu durumu (tanı bilgisi)
        if (m['type'] == 'sat') {
          setState(() {
            _satVisible = (m['visible'] as num).toInt();
            _satUsed = (m['used'] as num).toInt();
          });
          return;
        }
        final double accuracy = (m['accuracy'] as num).toDouble();
        // 50 metreden büyük çok ekstrem sapmaları yoksay (hassasiyet korunur)
        if (accuracy < 0 || accuracy > 50.0) {
          setState(() => _rejectedAccuracy = accuracy);
          return;
        }
        final double speed = (m['speed'] as num).toDouble();

        setState(() {
          _gpsStatus = "";
          _gpsStatusAction = null;
          _rejectedAccuracy = null;
          currentLat = (m['lat'] as num).toDouble();
          currentLon = (m['lon'] as num).toDouble();
          currentAccuracy = accuracy;
          lastFixTime = DateTime.now();

          // Uydudan gelen gerçek (sekme payı olan) ham hız
          currentRawSpeed = speed < 0 ? 0.0 : speed * 3.6;
        });
        // Haritayı yeni konuma kaydır (yakınlaştırma düzeyi korunur)
        if (_mapReady) _mapController.move(LatLng(currentLat, currentLon), _mapController.camera.zoom);
      }, onError: (Object e) {
        if (mounted) setState(() => _gpsStatus = "Ham GPS başlatılamadı: $e");
      });

      // DÜZELTİLMİŞ GPS: Fused (birleşik) konum servisi. GPS'i Wi-Fi/baz istasyonu/sensörlerle harmanlar ve yumuşatır.
      geoSubscription = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation, // Tez için en yüksek hassasiyet
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: 500),
        ),
      ).listen((Position position) {
        if (mounted) {
          // 50 metreden büyük çok ekstrem sapmaları yoksay (hassasiyet korunur)
          if (position.accuracy > 50.0) return;

          setState(() {
            lastFusedFixTime = DateTime.now();
            currentFusedSpeed = position.speed < 0 ? 0.0 : position.speed * 3.6;
          });
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _gpsStatus = "Konum izni verilmedi! İzin vermek için dokunun.";
          _gpsStatusAction = Geolocator.openAppSettings;
        });
      }
    }
  }

  // Durum yazısı: GPS bulunana kadar neden beklendiğini gösterir
  String get _gpsStatusText {
    if (_gpsStatus.isEmpty) return 'Doğruluk: ±${currentAccuracy.toStringAsFixed(1)} m';
    final parts = [_gpsStatus];
    if (_satVisible != null) parts.add('Uydu: $_satVisible görünen, $_satUsed kullanılan');
    if (_rejectedAccuracy != null) parts.add('Gelen konumun doğruluğu ±${_rejectedAccuracy!.toStringAsFixed(0)} m (50 m altı bekleniyor)');
    return parts.join('\n');
  }

  // 3. KAYIT BAŞLATMA MOTORU
  Future<void> startRecording() async {
    if (isRecording || _busy) return;
    _busy = true;
    try {
      // Dosyayı hemen oluştur ve başlığı yaz
      final now = DateTime.now();
      final dir = await recordingsDirectory();
      final file = File('${dir.path}/mikromobilite_${_fileStamp(now)}.csv');
      await file.writeAsString('$_csvHeader\n', flush: true);
      _csvFile = file;
      _recordStart = now;
      _rowCount = 0;
      _pendingRows.clear();
      _writeError = false;
      await _writeInfoFile(null);
    } catch (e) {
      _busy = false;
      _showMessage("Kayıt başlatılamadı: $e");
      return;
    }

    setState(() {
      isRecording = true;
    });
    _busy = false;
    // Kayıt sırasında ekranın kapanıp sensörlerin durmasını engelle
    WakelockPlus.enable();

    _zWindow.clear();
    _zNetWindow.clear();
    _verticalWindow.clear();
    _totalWindow.clear();
    _tiltWindow.clear();
    _gyroWindow.clear();

    // Saniyede 2 kez (500 milisaniye) veri örnekleme
    _recordTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!isRecording) {
        timer.cancel();
        return;
      }

      // Pencere içindeki Z örneklerinin istatistikleri
      // Z_Ham_Ort: ham Z ortalaması (≈ yerçekiminin Z bileşeni, telefonun eğimini gösterir)
      // Z_Net_RMS: yerçekimi çıkarılmış Z'nin RMS'i = sarsıntı şiddeti
      final samples = List<double>.from(_zWindow);
      final netSamples = List<double>.from(_zNetWindow);
      _zWindow.clear();
      _zNetWindow.clear();
      double zMean = 0, zRms = 0, zMin = 0, zMax = 0;
      if (samples.isNotEmpty) {
        zMean = samples.reduce((a, b) => a + b) / samples.length;
        zRms = sqrt(netSamples.map((z) => z * z).reduce((a, b) => a + b) / netSamples.length);
        zMin = netSamples.reduce(min);
        zMax = netSamples.reduce(max);
      }

      // Dikey sarsıntı (telefonun açısından bağımsız), toplam sarsıntı ve ortalama eğim
      // Dikey_RMS: ana sarsıntı ölçüsü. Toplam_RMS: üç eksenin birlikte RMS'i (dikey + yatay titreşim)
      final vSamples = List<double>.from(_verticalWindow);
      final tSamples = List<double>.from(_totalWindow);
      final tiltSamples = List<double>.from(_tiltWindow);
      _verticalWindow.clear();
      _totalWindow.clear();
      _tiltWindow.clear();
      double vRms = 0, vMin = 0, vMax = 0, tRms = 0, tiltMean = 0;
      if (vSamples.isNotEmpty) {
        vRms = sqrt(vSamples.map((v) => v * v).reduce((a, b) => a + b) / vSamples.length);
        vMin = vSamples.reduce(min);
        vMax = vSamples.reduce(max);
        tRms = sqrt(tSamples.map((v) => v * v).reduce((a, b) => a + b) / tSamples.length);
        tiltMean = tiltSamples.reduce((a, b) => a + b) / tiltSamples.length;
      }

      // Pencere içindeki jiroskop istatistikleri (rad/s): eksen ortalamaları ve en büyük bileşke açısal hız
      // Jiroskop yoksa sütunlar boş bırakılır
      final gyroSamples = List<List<double>>.from(_gyroWindow);
      _gyroWindow.clear();
      String gyroCols = ",,,";
      if (gyroSamples.isNotEmpty) {
        final n = gyroSamples.length;
        final double gxMean = gyroSamples.map((g) => g[0]).reduce((a, b) => a + b) / n;
        final double gyMean = gyroSamples.map((g) => g[1]).reduce((a, b) => a + b) / n;
        final double gzMean = gyroSamples.map((g) => g[2]).reduce((a, b) => a + b) / n;
        final double gMax = gyroSamples.map((g) => sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2])).reduce(max);
        gyroCols = "${gxMean.toStringAsFixed(4)},${gyMean.toStringAsFixed(4)},${gzMean.toStringAsFixed(4)},${gMax.toStringAsFixed(4)}";
      }

      // Son GPS konumundan bu yana geçen süre (GPS kesilirse eski konum tekrarlanır, bu sütunla ayıklanabilir)
      final String gpsAge = lastFixTime == null ? "" : (DateTime.now().difference(lastFixTime!).inMilliseconds / 1000).toStringAsFixed(1);
      final String fusedAge = lastFusedFixTime == null ? "" : (DateTime.now().difference(lastFusedFixTime!).inMilliseconds / 1000).toStringAsFixed(1);

      // O anki sensör verilerini CSV formatında virgülle ayırarak kaydet
      String timestamp = DateTime.now().toString();
      String row = "$timestamp,${currentLat.toStringAsFixed(6)},${currentLon.toStringAsFixed(6)},${currentRawSpeed.toStringAsFixed(2)},${currentFusedSpeed.toStringAsFixed(2)},"
          "${verticalNet.toStringAsFixed(4)},${vRms.toStringAsFixed(4)},${vMin.toStringAsFixed(4)},${vMax.toStringAsFixed(4)},${tRms.toStringAsFixed(4)},${tiltMean.toStringAsFixed(1)},"
          "${zNet.toStringAsFixed(4)},${zAxis.toStringAsFixed(4)},${zMean.toStringAsFixed(4)},${zRms.toStringAsFixed(4)},${zMin.toStringAsFixed(4)},${zMax.toStringAsFixed(4)},${samples.length},$gyroCols,${currentAccuracy.toStringAsFixed(1)},$gpsAge,$fusedAge";
      _pendingRows.add(row);
      _rowCount++;
      // 10 satırda bir (5 sn) dosyaya ekle
      if (_rowCount % 10 == 0) _flushPending();
    });
  }

  // Bekleyen satırları dosyanın sonuna ekle. Yazmalar sırayla yapılır (biri bitmeden diğeri başlamaz).
  void _flushPending() {
    final file = _csvFile;
    if (_pendingRows.isEmpty || file == null) return;
    final text = '${_pendingRows.join('\n')}\n';
    _pendingRows.clear();
    _writeChain = _writeChain.then((_) async {
      try {
        await file.writeAsString(text, mode: FileMode.append, flush: true);
      } catch (e) {
        debugPrint("Dosyaya yazılamadı: $e");
        _writeError = true;
      }
    });
  }

  // Kayda ait _bilgi.txt: cihaz, sensörler ve ölçüm ayarları. Başlangıçta yazılır, durdurunca güncellenir.
  Future<void> _writeInfoFile(DateTime? end) async {
    final file = _csvFile;
    if (file == null) return;
    final info = await DeviceInfo.load();
    final lines = [
      'Mikromobilite Sarsıntı Ölçer - kayıt bilgisi',
      'Veri dosyası: ${file.uri.pathSegments.last}',
      'Kayıt başlangıcı: $_recordStart',
      'Kayıt bitişi: ${end ?? "(kayıt sürüyor veya düzgün kapatılmadı)"}',
      'Satır sayısı: ${end == null ? "(kayıt bitince yazılır; CSV'deki satırları sayın)" : _rowCount}',
      '',
      ...DeviceInfo.describe(info),
      '',
      'Ölçüm ayarları:',
      '  İstenen sensör örnekleme aralığı: 20 ms (~50 Hz), ivmeölçer ve jiroskop',
      '  Kayıt penceresi: 0,5 s (saniyede 2 satır)',
      '  Yerçekimi giderme: ivmenin üç eksenine birinci dereceden yüksek geçiren filtre (bilineer dönüşüm), kesim frekansı $gravityCutoffHz Hz',
      '  Yerçekimi yönü = ham ivme − filtre çıkışı; Dikey_* = titreşimin bu yöne izdüşümü (telefonun montaj açısından bağımsız)',
      '  Toplam_RMS = üç eksen titreşim vektörünün RMS büyüklüğü; Egim_derece = telefon Z ekseni ile düşey arasındaki açı',
      '  Z_* = yalnızca telefonun kendi Z ekseni (telefon yatay değilse düşey sarsıntının bir kısmı)',
      '  Ham GPS: Android GPS_PROVIDER, istenen aralık 500 ms',
      '  Düzeltilmiş GPS: Fused konum servisi, istenen aralık 500 ms',
      '  GPS konum filtresi: doğruluğu 50 m\'den kötü konumlar atılır',
    ];
    await infoFileFor(file).writeAsString('${lines.join('\n')}\n', flush: true);
  }

  String _fileStamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  void _showMessage(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // 4. KAYIT BİTİRME VE PAYLAŞMA MOTORU
  Future<void> stopRecording() async {
    if (!isRecording || _busy) return;
    _busy = true;
    _recordTimer?.cancel();
    setState(() {
      isRecording = false;
    });
    WakelockPlus.disable();

    final file = _csvFile;
    try {
      // Kalan satırları yaz ve tüm yazmaların bitmesini bekle
      _flushPending();
      await _writeChain;
      if (file == null) return;
      await _writeInfoFile(DateTime.now());
      if (_writeError) _showMessage("Uyarı: bazı satırlar dosyaya yazılamadı.");

      // Dosyayı paylaşım ekranına (WhatsApp, Mail, Drive vb.) gönder. Kapatılırsa Kayıtlar sayfasından tekrar paylaşılabilir.
      await shareRecording(file);
    } catch (e) {
      debugPrint("Dosya kaydedilirken hata oluştu: $e");
      _showMessage("Dosya kaydedilemedi: $e");
    } finally {
      _busy = false;
    }
  }

  // Uygulama arka plana geçerse bekleyen satırları hemen dosyaya yaz
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _flushPending();
    } else if (_gpsStatusAction != null && !isRecording) {
      // Kullanıcı ayarlara yönlendirilmişti (izin / konum servisi): dönünce GPS'i yeniden başlat
      _initLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushPending();
    _clockTimer?.cancel();
    _uiTimer?.cancel();
    _recordTimer?.cancel();
    rawGpsSubscription?.cancel();
    geoSubscription?.cancel();
    accelSubscription?.cancel();
    gyroSubscription?.cancel();
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
                  Row(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Kayıtlar sayfası
                          IconButton(
                            icon: const Icon(Icons.folder_outlined, color: Colors.white, size: 28),
                            tooltip: 'Kayıtlar',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordingsPage())),
                          ),
                          // Hakkında / Teknik Bilgi sayfası
                          IconButton(
                            icon: const Icon(Icons.info_outline, color: Colors.white, size: 28),
                            tooltip: 'Hakkında / Teknik Bilgi',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
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
                    // Kartlar küçük ekranlarda kaydırılabilir, düğme her zaman altta görünür
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                    // Sarsıntı Kartı: büyük sayı dikey sarsıntı, altında küçük Z-ekseni, toplam ve eğim
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            const Text('DİKEY SARSINTI (m/s²)', style: TextStyle(fontSize: 14, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 10),
                            // Yerçekimi çıkarılmış, gerçek düşey yöndeki titreşim: hareketsizken ≈ 0, telefonun açısından bağımsız
                            Text(
                              verticalNet.toStringAsFixed(3),
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF003366))
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                for (final (label, value) in [
                                  ('Z-EKSENİ', zNet.toStringAsFixed(3)),
                                  ('TOPLAM', totalNet.toStringAsFixed(3)),
                                  ('EĞİM', '${tiltDeg.toStringAsFixed(0)}°'),
                                ])
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                                        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF495057))),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Jiroskop Kartı (açısal hız, rad/s) - tek satır, küçük
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                        child: Row(
                          children: [
                            const Text('JİROSKOP\n(rad/s)', style: TextStyle(fontSize: 11, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(width: 10),
                            if (!gyroAvailable)
                              const Expanded(child: Text('Bu telefonda jiroskop yok', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.redAccent)))
                            else
                              for (final (label, value) in [('X', gyroX), ('Y', gyroY), ('Z', gyroZ)])
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: '$label ', style: const TextStyle(fontSize: 11, color: Color(0xFF6C757D), fontWeight: FontWeight.bold)),
                                      TextSpan(text: value.toStringAsFixed(3), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6F42C1))),
                                    ]),
                                    textAlign: TextAlign.center,
                                  ),
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
                            // Ham (Seken) GPS Hızı ve Düzeltilmiş (Fused) GPS Hızı yan yana
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Text('HAM GPS HIZI\n(km/h)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentRawSpeed.toStringAsFixed(1),
                                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFFD7E14))
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Text('DÜZELTİLMİŞ GPS\n(km/h)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentFusedSpeed.toStringAsFixed(1),
                                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
                            GestureDetector(
                              onTap: _gpsStatusAction,
                              child: Text(
                                _gpsStatusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _gpsStatus.isNotEmpty ? Colors.redAccent : const Color(0xFF6C757D),
                                  decoration: _gpsStatusAction != null ? TextDecoration.underline : null,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Harita Kartı: o anki ham GPS konumu ve doğruluk dairesi (OpenStreetMap)
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        height: 260,
                        child: lastFixTime == null
                            ? const Center(child: Text('Harita, ilk GPS konumu gelince açılır', style: TextStyle(fontSize: 13, color: Color(0xFF6C757D))))
                            : FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: LatLng(currentLat, currentLon),
                                  initialZoom: 17,
                                  onMapReady: () => _mapReady = true,
                                  // Sürükleme kapalı (sayfa kaydırmasıyla çakışmasın); harita konumu kendisi takip eder, yakınlaştırılabilir
                                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'tr.edu.yildiz.kaan_usta',
                                  ),
                                  CircleLayer(
                                    circles: [
                                      // GPS doğruluk dairesi (yarıçap = doğruluk, metre)
                                      CircleMarker(
                                        point: LatLng(currentLat, currentLon),
                                        radius: currentAccuracy,
                                        useRadiusInMeter: true,
                                        color: const Color(0x330D6EFD),
                                        borderColor: const Color(0xFF0D6EFD),
                                        borderStrokeWidth: 1,
                                      ),
                                      // O anki konum
                                      CircleMarker(
                                        point: LatLng(currentLat, currentLon),
                                        radius: 7,
                                        color: const Color(0xFF0D6EFD),
                                        borderColor: Colors.white,
                                        borderStrokeWidth: 2,
                                      ),
                                    ],
                                  ),
                                  const SimpleAttributionWidget(source: Text('OpenStreetMap katkıcıları')),
                                ],
                              ),
                      ),
                    ),

                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

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
                        isRecording ? 'DURDUR ($_rowCount satır)' : 'BAŞLAT',
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
