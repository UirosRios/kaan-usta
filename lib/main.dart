import 'dart:async';
import 'dart:convert';
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
import 'arka_plan.dart';
import 'ayarlar.dart';
import 'device_info.dart';
import 'donusturucu.dart';
import 'hava_durumu.dart';
import 'kayitlar_sayfasi.dart';
import 'puan_sayfasi.dart';
import 'recordings_page.dart';
import 'test_surusu.dart';

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
  double currentAccuracy = 0.0; // Ham GPS yatay konum doğruluğu (m)
  DateTime? lastFixTime; // Son geçerli ham GPS konumunun zamanı
  bool isRecording = false;
  String _gpsStatus = "GPS bekleniyor...";
  // GPS tanı bilgisi: uydu sayısı, 50 m filtresine takılan son doğruluk, durum yazısına dokununca açılacak ayar
  int? _satVisible, _satUsed;
  double? _rejectedAccuracy;
  VoidCallback? _gpsStatusAction;
  bool _initializingLocation = false;

  // TEST SÜRÜŞÜ (Ayarlar): gerçek GPS yerine sanal konum ve hız üretilir; ivmeölçer gerçektir.
  // Güzergâh YTÜ Davutpaşa Yerleşkesi iç yollarında kapalı bir turdur (test_surusu.dart).
  bool _testSurusu = false;
  Timer? _simTimer;

  // Harita (Esri Light Gray Canvas / flutter_map): o anki ham GPS konumunu takip eder
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // YERÇEKİMİ GİDERME: ivmenin üç ekseni de 0,4 Hz kesim frekanslı birinci dereceden yüksek geçiren filtreden
  // geçirilir (bilineer / Tustin dönüşümü). Filtre çıkışı titreşimdir; ham ivme − titreşim = yerçekimi vektörü,
  // yani telefonun o anki "aşağı" yönü. 0,4 Hz, ISO 2631-1 titreşim değerlendirmesinin alt bant sınırıdır.
  static const double gravityCutoffHz = 0.4;
  static const Duration sensorSamplingPeriod = Duration(milliseconds: 5); // ~200 Hz
  static const double _gravityTau = 1 / (2 * pi * gravityCutoffHz);
  List<double>? _prevAcc; // önceki ham ivme [x, y, z]
  final List<double> _dynAcc = [0.0, 0.0, 0.0]; // titreşim bileşeni [x, y, z]
  DateTime? _lastAccelTime;

  // Zamanlayıcılar
  String _liveDate = "Tarih Yükleniyor...";
  String _liveTime = "Saat Yükleniyor...";
  Timer? _clockTimer;
  Timer? _uiTimer;
  bool _busy = false; // başlatma/durdurma sürerken düğmeye ikinci kez basılmasını engeller

  // HAM VERİ KAYDI (2.0): ivmeölçer, jiroskop, GPS ve basışlar Android tarafında (KayitMotoru.kt) aynı saatle ikili bir
  // dosyaya yazılır. DURDUR'dan sonra dosya o günün GeoPackage dosyalarına çevrilir (donusturucu.dart). Ekrandaki
  // sarsıntı, hız ve harita yalnızca gösterim içindir.
  String? _hamYol; // süren kaydın ham dosyası
  DateTime? _recordStart;

  // ÇUKUR İŞARETİ: sürücü çukurdan (ani sarsıntı veren her şeyden) geçince kulaklık / Bluetooth kumanda tuşuna,
  // telefonun ses tuşuna veya ekrandaki ÇUKUR butonuna basar. Basış Android tarafında kayda yazılır (1 sn içindeki
  // ikinci basış sayılmaz) ve buraya bildirilir. Geri bildirim yalnızca sesle: titreşim ivmeölçere karışırdı.
  static const MethodChannel _isaretKanali = MethodChannel('kaan_usta/isaret');
  final AudioPlayer _isaretSesi = AudioPlayer();
  int _isaretSayisi = 0; // bu kayıttaki toplam işaret
  bool _isaretParlama = false;

  // QGIS görünümü (kullanıcının QGIS projesinden; qgis/stiller): GeoPackage dosyalarına gömülür
  Map<String, String> _stiller = {};

  // Kayıt etiketleri: ayarlardaki scooter ve kayıt başındaki hava durumu (alınamazsa yazılmaz)
  String _kayitScooter = '';
  HavaDurumu? _hava;
  bool _havaBekleniyor = false; // kayıt başında GPS konumu yoksa ilk konumda bir kez denenir

  // Ham veri kaydı ve ön plan hizmeti (MainActivity.kt / KayitMotoru.kt / KayitServisi.kt)
  static const MethodChannel _kayitServisi = MethodChannel('kaan_usta/kayit_servisi');

  // Abonelikler
  // Ham GPS, Android tarafında (MainActivity.kt) GPS_PROVIDER'dan okunur
  static const EventChannel _rawGpsChannel = EventChannel('kaan_usta/ham_gps');
  StreamSubscription<dynamic>? rawGpsSubscription;
  StreamSubscription<AccelerometerEvent>? accelSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceInfo.load();
    _startClock();
    _initSensors();
    _initIsaretSesi();
    _isaretKanali.setMethodCallHandler((call) async {
      if (call.method == 'isaret') _isaretSayildi();
    });
    _acilistaDenetle();
  }

  // Açılışta: ekran yeniden kurulduysa süren kaydı geri al; yarım kalan (çevrilmemiş) ham dosyaları çevir;
  // Belgeler/Mikromobilite klasörüne kopyalanmamış dosyaları kopyala (Android 9 ve öncesinde izin istenir)
  Future<void> _acilistaDenetle() async {
    await _stilleriYukle();
    String? aktif;
    try {
      final d = await _kayitServisi.invokeMapMethod<String, dynamic>('durum');
      if (d?['kayitta'] == true) aktif = d?['yol'] as String?;
    } catch (e) {
      debugPrint('Kayıt durumu okunamadı: $e');
    }
    if (aktif != null && mounted) {
      setState(() {
        isRecording = true;
        _hamYol = aktif;
        _recordStart = DateTime.now();
      });
      WakelockPlus.enable();
    }
    await _yarimKalanlariCevir(haric: aktif);
    final sorun = await tumKayitlariKopyala();
    if (sorun != null) _showMessage(sorun);
  }

  Future<void> _stilleriYukle() async {
    final stiller = <String, String>{};
    for (final ad in ['kayitlar', 'gps_noktalari', 'insan_cukurlar', 'insan_puanlar']) {
      try {
        stiller[ad] = await rootBundle.loadString('qgis/stiller/$ad.qml');
      } catch (e) {
        debugPrint('QGIS stili yüklenemedi ($ad): $e');
      }
    }
    _stiller = stiller;
  }

  // Düşük gecikmeli çalma; başka uygulamanın sesini (müzik, navigasyon) durdurmaz
  Future<void> _initIsaretSesi() async {
    try {
      await _isaretSesi.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
      await _isaretSesi.setPlayerMode(PlayerMode.lowLatency);
      await _isaretSesi.setReleaseMode(ReleaseMode.stop);
      await _isaretSesi.setSource(AssetSource('sesler/isaret.mp3'));
    } catch (e) {
      debugPrint('İşaret sesi yüklenemedi: $e');
    }
  }

  // Ekrandaki ÇUKUR butonu: basış Android tarafında kayda yazılır, sayılırsa _isaretSayildi çağrılır
  void _ekrandanIsaretle() {
    if (!isRecording) return;
    _kayitServisi.invokeMethod('isaret', 'ekran').catchError((Object e) => debugPrint('İşaret gönderilemedi: $e'));
  }

  // Basış kayda yazıldı (kaynağı ne olursa olsun): sayaç, kısa parlama ve çift bip
  void _isaretSayildi() {
    if (!mounted) return;
    setState(() {
      _isaretSayisi++;
      _isaretParlama = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isaretParlama = false);
    });
    _isaretSesi.stop().then((_) => _isaretSesi.resume()).catchError((Object e) => debugPrint('İşaret sesi çalınamadı: $e'));
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

  // 2. Ekrandaki canlı değerler için sensörler (kayıt bunlardan bağımsız, Android tarafında yapılır)
  Future<void> _initSensors() async {
    // İvmeölçer (~200 Hz): ekrandaki dikey sarsıntı, toplam ve eğim
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
    rawGpsSubscription = null;
    _satVisible = null;
    _satUsed = null;
    _rejectedAccuracy = null;
    _gpsStatusAction = null;
    if (_simTimer != null) {
      // Sanal konumdan gerçek GPS'e geçiliyor: son sanal konum ve hız ekranda kalmasın
      lastFixTime = null;
      currentLat = 0.0;
      currentLon = 0.0;
      currentAccuracy = 0.0;
      currentRawSpeed = 0.0;
    }
    _simTimer?.cancel();
    _simTimer = null;

    // Test sürüşü açıksa gerçek GPS yerine sanal konum üretilir
    _testSurusu = await Ayarlar.testSurusu();
    if (_testSurusu) {
      // Arka plan kayıt hizmeti konum izni ister: test sürüşünde de bir kez sorulur (reddedilirse kayıt ekran açıkken sürer)
      try {
        if (await Geolocator.checkPermission() == LocationPermission.denied) await Geolocator.requestPermission();
      } catch (e) {
        debugPrint('Konum izni sorulamadı: $e');
      }
      _startSimulation();
      return;
    }

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

    } else {
      if (mounted) {
        setState(() {
          _gpsStatus = "Konum izni verilmedi! İzin vermek için dokunun.";
          _gpsStatusAction = Geolocator.openAppSettings;
        });
      }
    }
  }

  // Sanal GPS: 0,5 sn'de bir, kampüs turunda ilerleyen konum ve değişken hız (SanalTur)
  void _startSimulation() {
    final tur = SanalTur();
    if (mounted) {
      setState(() {
        _gpsStatus = 'TEST SÜRÜŞÜ: sanal GPS başlatılıyor...';
        _gpsStatusAction = null;
      });
    }
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      tur.ilerle(0.5);
      final now = DateTime.now();
      setState(() {
        _gpsStatus = '';
        _rejectedAccuracy = null;
        currentLat = tur.konum.latitude;
        currentLon = tur.konum.longitude;
        currentAccuracy = 5.0;
        currentRawSpeed = tur.hizKmh;
        lastFixTime = now;
      });
      // Kayıt sürüyorsa sanal konum ham kayda yazılır (gerçek GPS'in yerine)
      if (isRecording) {
        _kayitServisi.invokeMethod('sanalKonum', {
          'enlem': tur.konum.latitude,
          'boylam': tur.konum.longitude,
          'hiz': tur.hizKmh / 3.6,
          'dogruluk': 5.0,
        }).catchError((Object e) => debugPrint('Sanal konum yazılamadı: $e'));
      }
      if (_mapReady) _mapController.move(LatLng(currentLat, currentLon), _mapController.camera.zoom);
    });
  }

  // Durum yazısı: GPS bulunana kadar neden beklendiğini gösterir
  String get _gpsStatusText {
    if (_testSurusu && _gpsStatus.isEmpty) return 'TEST SÜRÜŞÜ (sanal GPS, konum ve hız gerçek değil)';
    if (_gpsStatus.isEmpty) return 'Doğruluk: ±${currentAccuracy.toStringAsFixed(1)} m';
    final parts = [_gpsStatus];
    if (_satVisible != null) parts.add('Uydu: $_satVisible görünen, $_satUsed kullanılan');
    if (_rejectedAccuracy != null) parts.add('Gelen konumun doğruluğu ±${_rejectedAccuracy!.toStringAsFixed(0)} m (50 m altı bekleniyor)');
    return parts.join('\n');
  }

  // 3. KAYIT BAŞLATMA
  Future<void> startRecording() async {
    if (isRecording || _busy) return;
    _busy = true;
    final now = DateTime.now();
    final String yol;
    try {
      final dir = await recordingsDirectory();
      yol = '${dir.path}/ham_gecici/${_testSurusu ? "test_" : ""}${kayitNoFor(now)}.kuham';
      _kayitScooter = await Ayarlar.scooter();
      _hava = null;
      _hamYol = yol;
      await _bilgiDosyasiYaz(); // çökme olursa kurtarılan kayıt da cihaz / scooter bilgisini alsın
      final yanit = await _kayitServisi.invokeMapMethod<String, dynamic>('baslat', {'yol': yol, 'sanal': _testSurusu});
      if (yanit?['servis'] != true) {
        _showMessage('Arka planda kayıt yapılamıyor (konum izni yok): ekranı açık tutun.');
      }
    } catch (e) {
      _busy = false;
      _hamYol = null;
      _showMessage("Kayıt başlatılamadı: $e");
      return;
    }

    setState(() {
      isRecording = true;
      _recordStart = now;
      _isaretSayisi = 0;
    });
    _busy = false;
    // Kayıt sırasında ekran kapanmasın (kapanırsa da kayıt arka planda sürer)
    WakelockPlus.enable();
    // Hava durumu: GPS konumu varsa hemen, yoksa ilk konum gelince (kayıt başından en fazla 60 sn sonra)
    _havaBekleniyor = !_testSurusu; // sanal konumun hava durumu anlamsız
    if (!_testSurusu && lastFixTime != null && DateTime.now().difference(lastFixTime!) <= const Duration(seconds: 60)) _havaDurumuAl();
  }

  // Kayda ait bilgiler (cihaz, sensörler, scooter, hava durumu) ham dosyanın yanına yazılır; çeviride kullanılır
  static File _bilgiDosyasi(String hamYol) => File('$hamYol.json');

  Future<KayitBilgisi> _kayitBilgisi() async {
    final info = await DeviceInfo.load();
    String sensor(String anahtar) {
      final s = info[anahtar];
      if (s is! Map) return '';
      return '${s['name']} (${s['vendor']})';
    }

    final hava = _hava;
    return KayitBilgisi(
      cihaz: info.containsKey('hata') ? '' : '${info['manufacturer']} ${info['model']} (Android ${info['android']})',
      ivmeSensoru: sensor('accelerometer'),
      jiroSensoru: sensor('gyroscope'),
      scooter: _kayitScooter,
      uygulamaSurumu: info.containsKey('hata') ? '' : '${info['appVersion']} (yapı ${info['appBuild']})',
      hava: hava?.durum,
      sicaklik: hava?.sicaklik,
      yagis: hava?.yagis,
    );
  }

  Future<void> _bilgiDosyasiYaz() async {
    final yol = _hamYol;
    if (yol == null) return;
    try {
      final f = _bilgiDosyasi(yol);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode((await _kayitBilgisi()).toMap()), flush: true);
    } catch (e) {
      debugPrint('Kayıt bilgisi yazılamadı: $e');
    }
  }

  void _showMessage(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Kayıt başındaki hava durumunu bir kez almayı dene; alınırsa kayda eklenir
  Future<void> _havaDurumuAl() async {
    final baslangic = _recordStart;
    _havaBekleniyor = false;
    if (!isRecording || baslangic == null || DateTime.now().difference(baslangic) > const Duration(seconds: 60)) return;
    final hava = await HavaDurumu.al(currentLat, currentLon).timeout(const Duration(seconds: 15), onTimeout: () => null);
    // Bu arada kayıt bittiyse veya yeni kayıt başladıysa yazma
    if (hava == null || !isRecording || _recordStart != baslangic) return;
    _hava = hava;
    await _bilgiDosyasiYaz();
  }

  // Ham dosyayı o günün GeoPackage dosyalarına çevirir (arka planda), sonra ham dosyayı siler
  Future<DonusumSonucu> _cevir(String hamYol) async {
    final dir = (await recordingsDirectory()).path;
    var bilgi = const KayitBilgisi();
    try {
      final f = _bilgiDosyasi(hamYol);
      if (await f.exists()) bilgi = KayitBilgisi.fromMap(Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map));
    } catch (e) {
      debugPrint('Kayıt bilgisi okunamadı: $e');
    }
    final sonuc = await donusturArkaPlanda(hamYol, dir, bilgi, _stiller);
    for (final f in [File(hamYol), _bilgiDosyasi(hamYol)]) {
      if (await f.exists()) await f.delete();
    }
    return sonuc;
  }

  // Uygulama kayıt sürerken kapandıysa ham dosya çevrilmeden kalır: açılışta çevrilir
  Future<void> _yarimKalanlariCevir({String? haric}) async {
    final klasor = Directory('${(await recordingsDirectory()).path}/ham_gecici');
    if (!await klasor.exists()) return;
    var n = 0;
    for (final f in klasor.listSync().whereType<File>().where((f) => f.path.endsWith('.kuham') && f.path != haric)) {
      try {
        final s = await _cevir(f.path);
        await telefonaKopyala([File(s.hamYol), File(s.insanYol)]);
        n++;
      } catch (e) {
        debugPrint('Yarım kalan kayıt çevrilemedi (${f.path}): $e');
      }
    }
    if (n > 0) _showMessage('Yarım kalan $n kayıt kurtarıldı. Kayıtlar sayfasından puanlayabilirsiniz.');
  }

  // 4. KAYIT BİTİRME: ham dosya kapatılır, GeoPackage'a çevrilir, puan ekranı açılır
  Future<void> stopRecording() async {
    if (!isRecording || _busy) return;
    _busy = true;
    setState(() => isRecording = false);
    WakelockPlus.disable();
    _havaBekleniyor = false;
    final hamYol = _hamYol;
    _hamYol = null;
    try {
      final sonuc = await _kayitServisi.invokeMapMethod<String, dynamic>('durdur');
      if (sonuc?['hata'] != null) _showMessage('Uyarı: ham dosya düzgün kapanmadı (${sonuc!['hata']}).');
      if (hamYol == null || !await File(hamYol).exists()) {
        _showMessage('Kayıt dosyası bulunamadı.');
        return;
      }
      await _bilgiDosyasiYaz();
      if (!mounted) return;
      // Çeviri birkaç saniye sürebilir
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Expanded(child: Text('Kayıt kaydediliyor...'))])),
        ),
      );
      DonusumSonucu? s;
      try {
        s = await _cevir(hamYol);
      } finally {
        if (mounted) Navigator.of(context).pop();
      }
      if (!mounted) return;
      // Sürüş akılda tazeyken konfor puanı (geçilemez: 1-5 veya Hatırlamıyorum)
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PuanSayfasi(sonuc: s!)));
      // Telefonun Belgeler/Mikromobilite klasörüne kopyala
      final sorun = await telefonaKopyala([File(s.hamYol), File(s.insanYol)]);
      if (sorun != null) _showMessage(sorun);
    } catch (e) {
      debugPrint("Kayıt kaydedilemedi: $e");
      _showMessage("Kayıt kaydedilemedi: $e. Ham dosya korunuyor; uygulama yeniden açılınca tekrar denenir.");
    } finally {
      _busy = false;
    }
  }

  String _sureYazisi() {
    final t = _recordStart;
    if (t == null) return '';
    final s = DateTime.now().difference(t).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _gpsStatusAction != null && !isRecording) {
      // Kullanıcı ayarlara yönlendirilmişti (izin / konum servisi): dönünce GPS'i yeniden başlat
      _initLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _uiTimer?.cancel();
    _simTimer?.cancel();
    rawGpsSubscription?.cancel();
    accelSubscription?.cancel();
    _isaretSesi.dispose();
    _isaretKanali.setMethodCallHandler(null);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bildirim çubuğu başlıkla aynı lacivert, simgeleri beyaz
    // Kayıt sürerken geri tuşu uygulamayı kapatmasın
    return PopScope(
      canPop: !isRecording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showMessage('Kayıt sürüyor: önce DURDUR\'a basılı tutun.');
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
            // Telefonda büyük yazı tipi seçiliyse başlık yazıları en fazla %15 büyür, başlık gerekirse uzar
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Container(
              color: const Color(0xFF003366),
              padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8, right: 10),
              constraints: const BoxConstraints(minHeight: 100),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Büyük yazı tipi ayarında taşmasın: sığmazsa kısaltılır
                  Flexible(
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "KAAN USTA",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(_liveDate, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFCED4DA), fontSize: 12)),
                      Text(_liveTime, style: const TextStyle(color: Color(0xFFCED4DA), fontSize: 12)),
                    ],
                  ),
                  ),
                  Row(
                    children: [
                      // Kayıtlar, Ayarlar, Hakkında / Teknik Bilgi sayfaları (yan yana)
                      for (final (ikon, ipucu, sayfa) in <(IconData, String, Widget)>[
                        (Icons.folder_outlined, 'Kayıtlar', const KayitlarSayfasi()),
                        (Icons.settings_outlined, 'Ayarlar', const AyarlarPage()),
                        (Icons.info_outline, 'Hakkında / Teknik Bilgi', const AboutPage()),
                      ])
                        IconButton(
                          icon: Icon(ikon, color: Colors.white, size: 26),
                          tooltip: ipucu,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 38, height: 48),
                          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          onPressed: () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => sayfa));
                            // Ayarlarda test sürüşü değiştiyse (kayıt sürmüyorsa) konum kaynağını yeniden başlat
                            if (!mounted || isRecording) return;
                            if (await Ayarlar.testSurusu() != _testSurusu) _initLocation();
                          },
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
                    // Sarsıntı Kartı: büyük sayı dikey sarsıntı, altında küçük toplam ve eğim (yalnızca gösterim)
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            const Text(
                              'DİKEY SARSINTI (m/s²)',
                              style: TextStyle(fontSize: 14, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
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

                    // Alt Alta Hız ve Koordinat Kartı
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            // GPS Doppler hızı (ham GPS donanımı, yumuşatma yok)
                            const Text('GPS HIZI (km/h)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, letterSpacing: 1)),
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
                                  // Harita kaynağı (kısa ve küçük: dar ekranda sığsın)
                                  const Align(
                                    alignment: Alignment.bottomRight,
                                    child: ColoredBox(
                                      color: Color(0xB3FFFFFF),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Text('© Esri, HERE, Garmin, OpenStreetMap', style: TextStyle(fontSize: 10, color: Color(0xFF495057))),
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
                    ),
                    const SizedBox(height: 15),

                    // ÇUKUR İŞARET Butonu (yalnızca kayıt sırasında): büyük, bakmadan basılabilir.
                    // Dokunulduğu an (parmak kalkmadan) sayılır; sistem tık sesi / titreşimi kapalı.
                    // Ses tuşu, Bluetooth kumanda ve kulaklık tuşu da aynı işi görür (MainActivity.kt / KayitServisi.kt).
                    if (isRecording) ...[
                      Material(
                        color: _isaretParlama ? const Color(0xFFFFC107) : const Color(0xFFFD7E14),
                        borderRadius: BorderRadius.circular(15),
                        elevation: 4,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          enableFeedback: false,
                          onTapDown: (_) => _ekrandanIsaretle(),
                          child: SizedBox(
                            height: 110,
                            child: Center(
                              child: Text(
                                'ÇUKUR\n($_isaretSayisi işaret)',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Kulaklık / Bluetooth kumanda tuşu önerilir (ekrana ve ses tuşuna basmak telefonu sarsar)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Color(0xFF6C757D)),
                      ),
                      const SizedBox(height: 15),
                    ],

                    // BAŞLAT / DURDUR Butonu. DURDUR basılı tutularak çalışır:
                    // hemen üstündeki ÇUKUR butonuna basarken kayıt yanlışlıkla durmasın.
                    ElevatedButton(
                      onPressed: !isRecording ? startRecording : () => _showMessage('Durdurmak için basılı tutun'),
                      onLongPress: isRecording ? stopRecording : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRecording ? Colors.redAccent : const Color(0xFF198754),
                        enableFeedback: false, // basılı tutunca titreşmesin (son satıra karışmasın)
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 4,
                      ),
                      child: Text(
                        isRecording ? 'DURDUR - basılı tutun (${_sureYazisi()})' : 'BAŞLAT',
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
      ),
    );
  }
}
