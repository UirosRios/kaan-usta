import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'about_page.dart';
import 'ayarlar.dart';
import 'device_info.dart';
import 'hava_durumu.dart';
import 'recordings_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Mikromobilite Veri Aracı',
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
  double verticalNet = 0.0; // Dikey sarsıntı: titreşimin gerçek düşey (yerçekimi) yönündeki bileşeni
  double totalNet = 0.0; // Toplam sarsıntı: üç eksendeki titreşimin büyüklüğü (yönden bağımsız)
  double tiltDeg = 0.0; // Telefonun yataydan eğimi (derece); ekran yukarı ve yatayken 0
  double currentLat = 0.0;
  double currentLon = 0.0;
  double currentRawSpeed = 0.0; // GPS Doppler Hızı - doğrudan GPS donanımı (yumuşatma yok)
  double currentFusedSpeed = 0.0; // Düzeltilmiş GPS Hızı - Fused (birleşik) konum servisi
  double currentAccuracy = 0.0; // Ham GPS yatay konum doğruluğu (m)
  DateTime? lastFixTime; // Son geçerli ham GPS konumunun zamanı
  DateTime? lastFusedFixTime; // Son geçerli düzeltilmiş GPS konumunun zamanı
  // Son konum bundan eskiyse (GPS kesildiyse) CSV'de konum / hız hücreleri boş bırakılır
  static const Duration gpsMaxAge = Duration(seconds: 3);
  bool isRecording = false;
  String _gpsStatus = "GPS bekleniyor...";
  // GPS tanı bilgisi: uydu sayısı, 50 m filtresine takılan son doğruluk, durum yazısına dokununca açılacak ayar
  int? _satVisible, _satUsed;
  double? _rejectedAccuracy;
  VoidCallback? _gpsStatusAction;
  bool _initializingLocation = false;

  // Harita (Esri Light Gray Canvas / flutter_map): o anki ham GPS konumunu takip eder
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // Kayıt penceresi (500 ms) içindeki tüm dikey sarsıntı örnekleri.
  // İvmeölçer ~200 Hz okunur; pencere başına istatistik çıkarılır ki
  // 2 Hz kayıtta tek anlık değer alınmasından doğan örtüşme (aliasing) olmasın.
  final List<double> _verticalWindow = [];

  // YERÇEKİMİ GİDERME: ivmenin üç ekseni de 0,4 Hz kesim frekanslı birinci dereceden yüksek geçiren filtreden
  // geçirilir (bilineer / Tustin dönüşümü). Filtre çıkışı titreşimdir; ham ivme − titreşim = yerçekimi vektörü,
  // yani telefonun o anki "aşağı" yönü. 0,4 Hz, ISO 2631-1 titreşim değerlendirmesinin alt bant sınırıdır.
  static const double gravityCutoffHz = 0.4;
  static const Duration sensorSamplingPeriod = Duration(milliseconds: 5); // ~200 Hz
  static const double _gravityTau = 1 / (2 * pi * gravityCutoffHz);
  List<double>? _prevAcc; // önceki ham ivme [x, y, z]
  final List<double> _dynAcc = [0.0, 0.0, 0.0]; // titreşim bileşeni [x, y, z]
  DateTime? _lastAccelTime;

  // Zamanlayıcı ve Veri Kayıt Değişkenleri
  String _liveDate = "Tarih Yükleniyor...";
  String _liveTime = "Saat Yükleniyor...";
  Timer? _clockTimer;
  Timer? _uiTimer;
  Timer? _recordTimer;

  // Kayıt dosyası: satırlar 5 saniyede bir dosyaya eklenir (uygulama kapanırsa en fazla son 5 sn kaybolur)
  // Türkçe Excel biçimi: sütun ayırıcı noktalı virgül, ondalık ayırıcı virgül
  // (Python: pd.read_csv(dosya, sep=';', decimal=','))
  static const String _csvHeader = "Tarih_Saat;Enlem;Boylam;GPS_Doppler_Hiz_kmh;Duzeltilmis_GPS_Hiz_kmh;"
      "Dikey_RMS;Dikey_Min;Dikey_Max;Ivme_Ornek_Sayisi;GPS_Dogruluk_m;Cukur";

  // Sayıyı CSV için ondalık virgülle yaz
  static String _num(double v, int digits) => v.toStringAsFixed(digits).replaceAll('.', ',');
  File? _csvFile;
  DateTime? _recordStart;
  int _rowCount = 0;
  final List<String> _pendingRows = [];
  Future<void> _writeChain = Future.value();
  bool _writeError = false;
  bool _busy = false; // başlatma/durdurma sürerken düğmeye ikinci kez basılmasını engeller

  // ANLIK ÇUKUR UYARISI: 0,5 sn'lik penceredeki en büyük dikey ivme (|Dikey_Min| veya Dikey_Max) eşiği aşarsa
  // sarsıntı kartı kırmızı yanar, sesli uyarı verilir ve CSV'de o satırın Cukur sütununa 1 yazılır. Sabit eşik seçildi: kayıt sırasında
  // yalnızca geçmiş bilinir; geçmişe göre (göreli) eşik gerçek sürüşlerde sabit eşikten daha iyi sonuç vermedi.
  // Hız eşiği: duruşta scooter'ı elle çevirmek / itmek uyarı vermesin. Ayrıntılı tespit analiz betiğindedir.
  static const double cukurEsik = 35.0; // m/s²
  static const double cukurMinHiz = 3.0; // km/h
  static const Duration cukurIsikSuresi = Duration(milliseconds: 1500);
  int _cukurCount = 0; // bu kayıttaki uyarı sayısı
  DateTime? _cukurIsikBitis;
  bool get _cukurIsigi => _cukurIsikBitis != null && DateTime.now().isBefore(_cukurIsikBitis!);
  // Uyarı sesi: art arda gelen uyarılarda ses en fazla saniyede bir çalar
  final AudioPlayer _uyariSesi = AudioPlayer();
  DateTime? _sonSes;

  // Kayıt etiketleri: ayarlardaki scooter ve kayıt başındaki hava durumu (alınamazsa yazılmaz)
  String _kayitScooter = '';
  HavaDurumu? _hava;
  bool _havaBekleniyor = false; // kayıt başında GPS konumu yoksa ilk konumda bir kez denenir

  // Ekran kapalıyken / uygulama arka plandayken kayıt sürsün diye Android ön plan hizmeti (MainActivity.kt)
  static const MethodChannel _kayitServisi = MethodChannel('kaan_usta/kayit_servisi');

  // Abonelikler
  // Ham GPS, Android tarafında (MainActivity.kt) GPS_PROVIDER'dan okunur
  static const EventChannel _rawGpsChannel = EventChannel('kaan_usta/ham_gps');
  StreamSubscription<dynamic>? rawGpsSubscription;
  StreamSubscription<Position>? geoSubscription;
  StreamSubscription<AccelerometerEvent>? accelSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceInfo.load();
    _startClock();
    _initSensors();
    _initUyariSesi();
  }

  // Düşük gecikmeli çalma; başka uygulamanın sesini (müzik, navigasyon) durdurmaz
  Future<void> _initUyariSesi() async {
    try {
      await _uyariSesi.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
      await _uyariSesi.setPlayerMode(PlayerMode.lowLatency);
      await _uyariSesi.setReleaseMode(ReleaseMode.stop);
      await _uyariSesi.setSource(AssetSource('sesler/uyari.mp3'));
    } catch (e) {
      debugPrint('Uyarı sesi yüklenemedi: $e');
    }
  }

  void _uyariSesiCal(DateTime now) {
    if (_sonSes != null && now.difference(_sonSes!) < const Duration(seconds: 1)) return;
    _sonSes = now;
    _uyariSesi.stop().then((_) => _uyariSesi.resume()).catchError((Object e) => debugPrint('Uyarı sesi çalınamadı: $e'));
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
    // 5 ms (~200 Hz): kısa çukur darbelerinin (~30 ms) tepesi kaçmasın. Android 12+'da özel izin
    // olmadan izin verilen en yüksek hız budur. Telefon daha yavaş verirse Ivme_Ornek_Sayisi'nda görülür.
    accelSubscription = accelerometerEventStream(samplingPeriod: sensorSamplingPeriod).listen((AccelerometerEvent event) {
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

      if (isRecording) _verticalWindow.add(verticalNet);
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

          // GPS Doppler hızı: uydu sinyalinin Doppler kaymasından, yumuşatmasız (sekme payı olabilir)
          currentRawSpeed = speed < 0 ? 0.0 : speed * 3.6;
        });
        if (_havaBekleniyor) _havaDurumuAl();
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
      aktifKayitYolu = file.path;
      _recordStart = now;
      _rowCount = 0;
      _pendingRows.clear();
      _writeError = false;
      _kayitScooter = await Ayarlar.scooter();
      _hava = null;
      await _writeInfoFile(null);
    } catch (e) {
      _busy = false;
      aktifKayitYolu = null;
      _showMessage("Kayıt başlatılamadı: $e");
      return;
    }

    setState(() {
      isRecording = true;
    });
    _busy = false;
    // Kayıt sırasında ekranın kapanıp sensörlerin durmasını engelle
    WakelockPlus.enable();
    // Ekran kilitlenir veya başka uygulamaya geçilirse kayıt arka planda sürsün
    _kayitServisi.invokeMethod<bool>('baslat').then((basladi) {
      if (basladi != true) _showMessage('Konum izni olmadığı için arka planda kayıt yapılamıyor: ekranı açık tutun.');
    }).catchError((Object e) => _showMessage('Arka planda kayıt başlatılamadı: ekranı açık tutun. ($e)'));
    // Hava durumu: GPS konumu varsa hemen, yoksa ilk konum gelince (kayıt başından en fazla 60 sn sonra)
    _havaBekleniyor = true;
    if (lastFixTime != null && DateTime.now().difference(lastFixTime!) <= const Duration(seconds: 60)) _havaDurumuAl();

    _verticalWindow.clear();
    _cukurCount = 0;
    _cukurIsikBitis = null;

    // Saniyede 2 kez (500 milisaniye) veri örnekleme
    _recordTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!isRecording) {
        timer.cancel();
        return;
      }

      // Pencere içindeki dikey sarsıntı istatistikleri (telefonun açısından bağımsız)
      // Dikey_RMS: ana sarsıntı ölçüsü; Dikey_Min / Dikey_Max: darbe tepe değerleri
      final vSamples = List<double>.from(_verticalWindow);
      _verticalWindow.clear();
      double vRms = 0, vMin = 0, vMax = 0;
      if (vSamples.isNotEmpty) {
        vRms = sqrt(vSamples.map((v) => v * v).reduce((a, b) => a + b) / vSamples.length);
        vMin = vSamples.reduce(min);
        vMax = vSamples.reduce(max);
      }

      // GPS 3 sn'den uzun süredir konum vermiyorsa eski konum / hız tekrarlanmasın: hücreler boş kalır
      final now = DateTime.now();
      bool fresh(DateTime? t) => t != null && now.difference(t) <= gpsMaxAge;
      final bool gpsOk = fresh(lastFixTime);
      final bool fusedOk = fresh(lastFusedFixTime);

      // Anlık çukur uyarısı (GPS hızı yoksa hareket bilinmediği için uyarı verilmez)
      final bool cukur = gpsOk && currentRawSpeed >= cukurMinHiz && max(vMin.abs(), vMax) >= cukurEsik;
      if (cukur) {
        setState(() {
          _cukurCount++;
          _cukurIsikBitis = now.add(cukurIsikSuresi);
        });
        _uyariSesiCal(now);
      }

      // O anki sensör verilerini CSV formatında noktalı virgülle ayırarak kaydet
      // Tarih_Saat: 2026-10-23 14:05:31,512 (milisaniye de ondalık virgülle)
      String row = [
        now.toString().replaceAll('.', ','),
        gpsOk ? _num(currentLat, 6) : '',
        gpsOk ? _num(currentLon, 6) : '',
        gpsOk ? _num(currentRawSpeed, 2) : '',
        fusedOk ? _num(currentFusedSpeed, 2) : '',
        _num(vRms, 4),
        _num(vMin, 4),
        _num(vMax, 4),
        '${vSamples.length}',
        gpsOk ? _num(currentAccuracy, 1) : '',
        cukur ? '1' : '',
      ].join(';');
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
  // Bilgi dosyası yazımları sırayla yapılır: kayıt başında, hava durumu gelince ve durdurunca yazılır;
  // sonuncusu (durdurma) her zaman en son biter
  Future<void> _infoChain = Future.value();
  Future<void> _writeInfoFile(DateTime? end) {
    _infoChain = _infoChain.then((_) => _writeInfoFileNow(end)).catchError((Object e) => debugPrint('Bilgi dosyası yazılamadı: $e'));
    return _infoChain;
  }

  Future<void> _writeInfoFileNow(DateTime? end) async {
    final file = _csvFile;
    if (file == null) return;
    final info = await DeviceInfo.load();
    final lines = [
      'Mikromobilite Veri Aracı - kayıt bilgisi',
      'Veri dosyası: ${file.uri.pathSegments.last}',
      'Kayıt başlangıcı: $_recordStart',
      'Kayıt bitişi: ${end ?? "(kayıt sürüyor veya düzgün kapatılmadı)"}',
      'Satır sayısı: ${end == null ? "(kayıt bitince yazılır; CSV'deki satırları sayın)" : _rowCount}',
      'Çukur uyarısı sayısı: ${end == null ? "(kayıt bitince yazılır)" : _cukurCount}',
      'Scooter: ${_kayitScooter.isEmpty ? "belirtilmedi (Ayarlar)" : _kayitScooter}',
      if (_hava != null) 'Hava durumu: ${_hava!.satir()}',
      '',
      ...DeviceInfo.describe(info),
      '',
      'CSV biçimi: sütun ayırıcı noktalı virgül (;), ondalık ayırıcı virgül (,) - Türkçe Excel ile doğrudan açılır',
      '',
      'Ölçüm ayarları:',
      '  İstenen ivmeölçer örnekleme aralığı: 5 ms (~200 Hz)',
      '  Kayıt penceresi: 0,5 s (saniyede 2 satır)',
      '  Yerçekimi giderme: ivmenin üç eksenine birinci dereceden yüksek geçiren filtre (bilineer dönüşüm), kesim frekansı $gravityCutoffHz Hz',
      '  Yerçekimi yönü = ham ivme − filtre çıkışı; Dikey_* = titreşimin bu yöne izdüşümü (telefonun montaj açısından bağımsız)',
      '  GPS Doppler hızı ve konum: doğrudan GPS donanımı (Android GPS_PROVIDER), yumuşatma yok, istenen aralık 500 ms',
      '  Düzeltilmiş GPS: Fused konum servisi, istenen aralık 500 ms',
      '  GPS konum filtresi: doğruluğu 50 m\'den kötü konumlar atılır',
      '  GPS kesintisi: son konum ${gpsMaxAge.inSeconds} sn\'den eskiyse Enlem, Boylam, GPS_Doppler_Hiz_kmh ve GPS_Dogruluk_m boş bırakılır;',
      '  düzeltilmiş GPS ${gpsMaxAge.inSeconds} sn\'den eskiyse Duzeltilmis_GPS_Hiz_kmh boş bırakılır',
      '  Cukur: anlık çukur uyarısı; ekranda kırmızı yanar ve sesli uyarı verilir (1 = o 0,5 sn içinde |Dikey_Min| veya Dikey_Max ≥ ${cukurEsik.toStringAsFixed(0)} m/s² ve GPS hızı ≥ ${cukurMinHiz.toStringAsFixed(0)} km/h).',
      '  Ayrıntılı darbe tespiti (çevredeki sarsıntıya göre, GPS gecikmesi düzeltilmiş) analiz betiğiyle yapılır.',
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
  // Kayıt başındaki hava durumunu bir kez almayı dene; alınırsa bilgi dosyasına eklenir
  Future<void> _havaDurumuAl() async {
    final baslangic = _recordStart;
    _havaBekleniyor = false;
    if (!isRecording || baslangic == null || DateTime.now().difference(baslangic) > const Duration(seconds: 60)) return;
    final hava = await HavaDurumu.al(currentLat, currentLon).timeout(const Duration(seconds: 15), onTimeout: () => null);
    // Bu arada kayıt bittiyse veya yeni kayıt başladıysa yazma
    if (hava == null || !isRecording || _recordStart != baslangic) return;
    _hava = hava;
    await _writeInfoFile(null);
  }

  Future<void> stopRecording() async {
    if (!isRecording || _busy) return;
    _busy = true;
    _recordTimer?.cancel();
    setState(() {
      isRecording = false;
    });
    WakelockPlus.disable();
    _havaBekleniyor = false;
    _kayitServisi.invokeMethod('durdur').catchError((Object e) => debugPrint('Kayıt hizmeti durdurulamadı: $e'));
    aktifKayitYolu = null;

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
    _uyariSesi.dispose();
    if (isRecording) _kayitServisi.invokeMethod('durdur').catchError((Object e) => null);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bildirim çubuğu başlıkla aynı lacivert, simgeleri beyaz
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
      backgroundColor: const Color(0xFFE9ECEF),
      body: Column(
        children: [
          Container(color: const Color(0xFF003366), height: MediaQuery.paddingOf(context).top),
          Expanded(
            child: SafeArea(
        top: false,
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
                          // Kayıtlar, Ayarlar, Hakkında / Teknik Bilgi sayfaları
                          for (final (ikon, ipucu, sayfa) in <(IconData, String, Widget)>[
                            (Icons.folder_outlined, 'Kayıtlar', const RecordingsPage()),
                            (Icons.settings_outlined, 'Ayarlar', const AyarlarPage()),
                            (Icons.info_outline, 'Hakkında / Teknik Bilgi', const AboutPage()),
                          ])
                            IconButton(
                              icon: Icon(ikon, color: Colors.white, size: 24),
                              tooltip: ipucu,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(width: 40, height: 28),
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => sayfa)),
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
                    // YTÜ logosu uygulamaya gömülü (internet olmadan da görünür)
                    child: ClipOval(child: Image.asset('assets/logo/ytu.png', fit: BoxFit.contain)),
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
                    // Sarsıntı Kartı: büyük sayı dikey sarsıntı, altında küçük toplam ve eğim.
                    // Kayıt sırasında çukur uyarısı gelince 1,5 sn kırmızı yanar.
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: _cukurIsigi ? const Color(0xFFDC3545) : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Text(
                              _cukurIsigi ? 'ÇUKUR!' : 'DİKEY SARSINTI (m/s²)',
                              style: TextStyle(fontSize: 14, color: _cukurIsigi ? Colors.white : const Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            const SizedBox(height: 10),
                            // Yerçekimi çıkarılmış, gerçek düşey yöndeki titreşim: hareketsizken ≈ 0, telefonun açısından bağımsız
                            Text(
                              verticalNet.toStringAsFixed(3),
                              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: _cukurIsigi ? Colors.white : const Color(0xFF003366))
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                for (final (label, value) in [
                                  ('TOPLAM', totalNet.toStringAsFixed(3)),
                                  ('EĞİM', '${tiltDeg.toStringAsFixed(0)}°'),
                                  if (isRecording) ('ÇUKUR', '$_cukurCount'), // bu kayıttaki uyarı sayısı
                                ])
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(label, style: TextStyle(fontSize: 10, color: _cukurIsigi ? Colors.white70 : const Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
                                        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _cukurIsigi ? Colors.white : const Color(0xFF495057))),
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

                    // Alt Alta Hız ve Koordinat Kartı
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            // GPS Doppler Hızı ve Düzeltilmiş (Fused) GPS Hızı yan yana
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Text('GPS DOPPLER\nHIZI (km/h)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
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

                    // Harita Kartı: o anki ham GPS konumu ve doğruluk dairesi (Esri Light Gray Canvas)
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
                                  initialZoom: 16,
                                  maxZoom: 19,
                                  onMapReady: () => _mapReady = true,
                                  // Sürükleme kapalı (sayfa kaydırmasıyla çakışmasın); harita konumu kendisi takip eder, yakınlaştırılabilir
                                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
                                ),
                                children: [
                                  // Esri Light Gray Canvas: sade gri altlık + ayrı katman olarak sokak adları.
                                  // Esri karo adresinde sıra {z}/{y}/{x}'tir. Altlık en fazla 16. seviyeye kadar
                                  // karo verir; daha yakın seviyelerde 16. seviye karoları büyütülür.
                                  TileLayer(
                                    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
                                    userAgentPackageName: 'tr.edu.yildiz.kaan_usta',
                                    maxNativeZoom: 16,
                                  ),
                                  TileLayer(
                                    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
                                    userAgentPackageName: 'tr.edu.yildiz.kaan_usta',
                                    maxNativeZoom: 16,
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
                                  const SimpleAttributionWidget(source: Text('Esri, HERE, Garmin, © OpenStreetMap katkıcıları')),
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
          ),
        ],
      ),
      ),
    );
  }
}
