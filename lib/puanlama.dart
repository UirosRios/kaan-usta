import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// SÜRÜŞ SONRASI KONFOR PUANLAMASI (doğrulama için)
// Güzergâh dönüş noktalarından parçalara bölünür (kabaca her sokak bir parça; uzun düz yollar en fazla ~200 m).
// Sürücü her parçayı 1 (çok sarsıntılı) - 5 (çok rahat) arası puanlar. Haritada ölçülen sarsıntı GÖSTERİLMEZ:
// puan ölçümden bağımsız bir referans olsun. Puanlar kaydın yanına <kayıt>_puan.csv olarak yazılır; analiz betiği
// her parçanın hız düzeltmeli sarsıntı indeksini puanla karşılaştırır.

// Kayda ait puan dosyası (aynı ad + _puan.csv)
File puanFileFor(File csv) => File(csv.path.replaceAll(RegExp(r'\.csv$'), '_puan.csv'));

class Parca {
  Parca(this.noktalar, this.zamanlar, this.adim);
  final List<LatLng> noktalar; // adim aralıklı (gerçek sürüşte 10 m)
  final List<DateTime> zamanlar;
  final double adim;
  int? puan;
  bool hatirlamiyorum = false;

  DateTime get bas => zamanlar.first;
  DateTime get bit => zamanlar.last;
  double get uzunluk => (noktalar.length - 1) * adim;
  bool get yanitlandi => puan != null || hatirlamiyorum;
}

class Parcalama {
  const Parcalama({required this.adim, required this.enKisa});
  final double adim; // m: güzergâh bu aralıkla yeniden örneklenir
  final double enKisa; // m: daha kısa parça olmaz
  static const double donusAcisi = 45; // derece: bu kadar yön değişimi parça sınırı olur
  static const double enUzun = 200; // m: uzun düz yollar bölünür
  static const double minHiz = 3; // km/h: duruşta GPS'in titremesi sahte dönüş üretmesin

  static const Distance _mesafe = Distance(roundResult: false);

  // Gerçek sürüş: 10 m örnekleme, en kısa parça 50 m.
  // Test sürüşü (Ayarlar, sanal GPS; dosya adı test_ ile başlar): kısa denemeler de puanlanabilsin diye 1 m / 5 m.
  static const Parcalama gercek = Parcalama(adim: 10, enKisa: 50);
  static const Parcalama test = Parcalama(adim: 1, enKisa: 5);
  static Parcalama kayitIcin(File csv) => csv.uri.pathSegments.last.startsWith('test_') ? test : gercek;

  // Kayıt CSV'sinden hareket hâlindeki tekil GPS konumları
  static Future<(List<LatLng>, List<DateTime>)> izOku(File csv) async {
    final satirlar = await csv.readAsLines();
    if (satirlar.isEmpty) return (<LatLng>[], <DateTime>[]);
    final baslik = satirlar.first.replaceFirst('﻿', '').split(';');
    final iZaman = baslik.indexOf('Tarih_Saat'), iEnlem = baslik.indexOf('Enlem'), iBoylam = baslik.indexOf('Boylam');
    final iHiz = baslik.indexOf('GPS_Doppler_Hiz_kmh');
    if (iZaman < 0 || iEnlem < 0 || iBoylam < 0) return (<LatLng>[], <DateTime>[]);
    double? sayi(String m) => m.trim().isEmpty ? null : double.tryParse(m.trim().replaceAll(',', '.'));
    final noktalar = <LatLng>[];
    final zamanlar = <DateTime>[];
    String? onceki;
    for (final satir in satirlar.skip(1)) {
      final h = satir.split(';');
      if (h.length <= max(iZaman, max(iEnlem, iBoylam))) continue;
      final enlem = sayi(h[iEnlem]), boylam = sayi(h[iBoylam]);
      if (enlem == null || boylam == null) continue;
      final anahtar = '${h[iEnlem]};${h[iBoylam]}';
      if (anahtar == onceki) continue; // GPS saniyede bir; satırlar 0,5 sn: aynı konum tekrar eder
      onceki = anahtar;
      final hiz = iHiz >= 0 && iHiz < h.length ? sayi(h[iHiz]) : null;
      if (hiz != null && hiz < minHiz) continue;
      final t = DateTime.tryParse(h[iZaman].trim().replaceAll(',', '.'));
      if (t == null) continue;
      noktalar.add(LatLng(enlem, boylam));
      zamanlar.add(t);
    }
    return (noktalar, zamanlar);
  }

  List<Parca> bol(List<LatLng> noktalar, List<DateTime> zamanlar) {
    // 1. Güzergâhı adim (gerçek sürüşte 10 m) aralıkla yeniden örnekle (konum ve zaman doğrusal enterpolasyon)
    final r = <LatLng>[], rt = <DateTime>[];
    if (noktalar.length < 2) return [];
    r.add(noktalar.first);
    rt.add(zamanlar.first);
    double kalan = adim;
    for (var i = 0; i + 1 < noktalar.length; i++) {
      final a = noktalar[i], b = noktalar[i + 1];
      final d = _mesafe.as(LengthUnit.Meter, a, b);
      if (d > 200) continue; // GPS sıçraması veya uzun kesinti: bu aralık güzergâha katılmaz
      var gidilen = 0.0;
      while (d - gidilen >= kalan) {
        gidilen += kalan;
        final k = gidilen / d;
        r.add(LatLng(a.latitude + k * (b.latitude - a.latitude), a.longitude + k * (b.longitude - a.longitude)));
        final ta = zamanlar[i].microsecondsSinceEpoch, tb = zamanlar[i + 1].microsecondsSinceEpoch;
        rt.add(DateTime.fromMicrosecondsSinceEpoch((ta + k * (tb - ta)).round()));
        kalan = adim;
      }
      kalan -= d - gidilen;
    }
    final n = r.length;
    if ((n - 1) * adim < enKisa) return [];

    // 2. Dönüşler: 2 adım geri ile 2 adım ileri arasındaki yön farkı; yerel en büyük ve en az enKisa arayla
    double yon(LatLng a, LatLng b) => _mesafe.bearing(a, b);
    double fark(double x, double y) => ((y - x + 540) % 360 - 180).abs();
    final donus = List<double>.filled(n, 0);
    for (var i = 2; i + 2 < n; i++) {
      donus[i] = fark(yon(r[i - 2], r[i]), yon(r[i], r[i + 2]));
    }
    final enAzAdim = (enKisa / adim).round();
    final sinirlar = <int>[0];
    for (var i = enAzAdim; i + enAzAdim < n; i++) {
      if (donus[i] < donusAcisi || i - sinirlar.last < enAzAdim) continue;
      var yerelEnBuyuk = true;
      for (var j = max(0, i - 3); j <= min(n - 1, i + 3); j++) {
        if (donus[j] > donus[i]) yerelEnBuyuk = false;
      }
      if (yerelEnBuyuk) sinirlar.add(i);
    }
    // Son parça çok kısaysa bir öncekine katılır
    if (n - 1 - sinirlar.last < enAzAdim && sinirlar.length > 1) sinirlar.removeLast();
    sinirlar.add(n - 1);

    // 3. Uzun parçaları eşit bölümlere ayır
    final parcalar = <Parca>[];
    for (var s = 0; s + 1 < sinirlar.length; s++) {
      final i0 = sinirlar[s], i1 = sinirlar[s + 1];
      final bolum = max(1, ((i1 - i0) * adim / enUzun).ceil());
      for (var k = 0; k < bolum; k++) {
        final a = i0 + ((i1 - i0) * k / bolum).round(), b = i0 + ((i1 - i0) * (k + 1) / bolum).round();
        parcalar.add(Parca(r.sublist(a, b + 1), rt.sublist(a, b + 1), adim));
      }
    }
    return parcalar;
  }
}

String _zamanMetin(DateTime t) => t.toString().replaceAll('.', ',');
String _sayi(double v, int basamak) => v.toStringAsFixed(basamak).replaceAll('.', ',');

class PuanlamaSayfasi extends StatefulWidget {
  const PuanlamaSayfasi({super.key, required this.csv});
  final File csv;

  @override
  State<PuanlamaSayfasi> createState() => _PuanlamaSayfasiState();
}

class _PuanlamaSayfasiState extends State<PuanlamaSayfasi> {
  List<Parca>? _parcalar;
  List<LatLng> _iz = [];
  int _i = 0;
  final MapController _harita = MapController();
  bool _haritaHazir = false;

  static const List<(int, String)> _olcek = [
    (1, 'Çok\nsarsıntılı'),
    (2, 'Sarsıntılı'),
    (3, 'Orta'),
    (4, 'Rahat'),
    (5, 'Çok\nrahat'),
  ];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final (noktalar, zamanlar) = await Parcalama.izOku(widget.csv);
    final parcalar = Parcalama.kayitIcin(widget.csv).bol(noktalar, zamanlar);
    await _eskiPuanlariOku(parcalar);
    if (!mounted) return;
    setState(() {
      _iz = noktalar;
      _parcalar = parcalar;
      final ilk = parcalar.indexWhere((p) => !p.yanitlandi);
      _i = ilk < 0 ? 0 : ilk;
    });
    _parcayaOdaklan();
  }

  // Daha önce puanlanmışsa puanlar geri yüklenir (parçalama aynı kayıtta hep aynı sonucu verir)
  Future<void> _eskiPuanlariOku(List<Parca> parcalar) async {
    final dosya = puanFileFor(widget.csv);
    if (!await dosya.exists()) return;
    final satirlar = await dosya.readAsLines();
    if (satirlar.length - 1 != parcalar.length) return;
    final baslik = satirlar.first.replaceFirst('﻿', '').split(';');
    final iPuan = baslik.indexOf('Puan'), iDurum = baslik.indexOf('Durum');
    if (iPuan < 0 || iDurum < 0) return;
    for (var k = 0; k < parcalar.length; k++) {
      final h = satirlar[k + 1].split(';');
      if (h.length <= max(iPuan, iDurum)) continue;
      parcalar[k].puan = int.tryParse(h[iPuan]);
      parcalar[k].hatirlamiyorum = h[iDurum] == 'hatirlamiyorum';
    }
  }

  Future<void> _kaydet() async {
    final parcalar = _parcalar;
    if (parcalar == null || parcalar.isEmpty || !parcalar.any((p) => p.yanitlandi)) return;
    final simdi = _zamanMetin(DateTime.now());
    final satirlar = [
      'Parca;Baslangic;Bitis;Uzunluk_m;Baslangic_Enlem;Baslangic_Boylam;Bitis_Enlem;Bitis_Boylam;Puan;Durum;Puanlama_Zamani',
      for (var k = 0; k < parcalar.length; k++)
        [
          '${k + 1}',
          _zamanMetin(parcalar[k].bas),
          _zamanMetin(parcalar[k].bit),
          _sayi(parcalar[k].uzunluk, 0),
          _sayi(parcalar[k].noktalar.first.latitude, 6),
          _sayi(parcalar[k].noktalar.first.longitude, 6),
          _sayi(parcalar[k].noktalar.last.latitude, 6),
          _sayi(parcalar[k].noktalar.last.longitude, 6),
          parcalar[k].puan?.toString() ?? '',
          parcalar[k].puan != null ? 'puanlandi' : (parcalar[k].hatirlamiyorum ? 'hatirlamiyorum' : 'puanlanmadi'),
          simdi,
        ].join(';'),
    ];
    await puanFileFor(widget.csv).writeAsString('${satirlar.join('\n')}\n', flush: true);
  }

  void _parcayaOdaklan() {
    final parcalar = _parcalar;
    if (!_haritaHazir || parcalar == null || parcalar.isEmpty) return;
    _harita.fitCamera(CameraFit.coordinates(
      coordinates: parcalar[_i].noktalar,
      padding: const EdgeInsets.all(48),
      maxZoom: 18,
    ));
  }

  Future<void> _yanitla({int? puan}) async {
    final parcalar = _parcalar!;
    setState(() {
      parcalar[_i].puan = puan;
      parcalar[_i].hatirlamiyorum = puan == null;
    });
    if (_i + 1 < parcalar.length) {
      setState(() => _i++);
      _parcayaOdaklan();
      return;
    }
    await _kaydet();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _sonra() async {
    await _kaydet();
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final parcalar = _parcalar;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bitti, _) {
        if (!bitti) _sonra();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE9ECEF),
        appBar: AppBar(
          backgroundColor: const Color(0xFF003366),
          foregroundColor: Colors.white,
          title: const Text('Sürüşü puanla'),
          actions: [
            TextButton(onPressed: _sonra, child: const Text('Sonra', style: TextStyle(color: Colors.white, fontSize: 16))),
          ],
        ),
        body: parcalar == null
            ? const Center(child: CircularProgressIndicator())
            : parcalar.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Puanlanacak kadar uzun bir sürüş yok (en az 50 m hareket gerekir).',
                          textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6C757D))),
                    ),
                  )
                : Column(children: [Expanded(child: _haritaGorunumu(parcalar)), _panel(parcalar)]),
      ),
    );
  }

  Widget _haritaGorunumu(List<Parca> parcalar) {
    final p = parcalar[_i];
    return FlutterMap(
      mapController: _harita,
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(coordinates: _iz.isEmpty ? p.noktalar : _iz, padding: const EdgeInsets.all(32)),
        maxZoom: 19,
        onMapReady: () {
          _haritaHazir = true;
          _parcayaOdaklan();
        },
      ),
      children: [
        // Sokak adları görünsün diye renkli sokak haritası. Ölçülen sarsıntı haritada yoktur (kör puanlama).
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'tr.edu.yildiz.kaan_usta',
          maxNativeZoom: 19,
        ),
        PolylineLayer(polylines: [
          Polyline(points: _iz, strokeWidth: 3, color: const Color(0x99495057)),
          Polyline(points: p.noktalar, strokeWidth: 8, color: const Color(0xFF0D6EFD), borderStrokeWidth: 2, borderColor: Colors.white),
        ]),
        CircleLayer(circles: [
          CircleMarker(point: p.noktalar.first, radius: 8, color: const Color(0xFF198754), borderColor: Colors.white, borderStrokeWidth: 2),
          CircleMarker(point: p.noktalar.last, radius: 8, color: const Color(0xFFDC3545), borderColor: Colors.white, borderStrokeWidth: 2),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('Esri, HERE, Garmin, © OpenStreetMap katkıcıları')]),
      ],
    );
  }

  Widget _panel(List<Parca> parcalar) {
    final p = parcalar[_i];
    String saat(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final secili = p.puan;
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Parça ${_i + 1} / ${parcalar.length}  ·  ~${p.uzunluk.round()} m  ·  ${saat(p.bas)}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D))),
              const SizedBox(height: 4),
              const Text('Mavi parçadan (yeşil → kırmızı) geçiş ne kadar rahattı?',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (deger, ad) in _olcek)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ElevatedButton(
                          onPressed: () => _yanitla(puan: deger),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: secili == deger ? const Color(0xFF003366) : const Color(0xFFF1F3F5),
                            foregroundColor: secili == deger ? Colors.white : const Color(0xFF212529),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$deger', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              Text(ad, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, height: 1.1)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _i == 0
                        ? null
                        : () {
                            setState(() => _i--);
                            _parcayaOdaklan();
                          },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Geri'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _yanitla(),
                    child: Text('Hatırlamıyorum', style: TextStyle(fontWeight: p.hatirlamiyorum ? FontWeight.bold : FontWeight.normal)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
