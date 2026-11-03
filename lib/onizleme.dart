import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'puanlama.dart';
import 'recordings_page.dart';

// KAYIT ÖNİZLEMESİ (gösterim amaçlı): bir kaydın haritası, grafikleri, konfor puanları ve özeti telefonda.
// Test sürüşleri dahil her kayıtta çalışır. Analizin yalnızca basit bir kısmıdır: hız düzeltmesi, darbe tespiti
// (çevreye göre), haritaya oturtma ve istatistik testleri bilgisayardaki analiz betiğindedir.

const Color _lacivert = Color(0xFF003366);
const Color _gri = Color(0xFF6C757D);
// Sarsıntı ve puan renkleri: yeşil = düzgün / rahat ... kırmızı = sarsıntılı
const List<Color> _renkler = [Color(0xFF1A9850), Color(0xFF91CF60), Color(0xFFFEE08B), Color(0xFFFC8D59), Color(0xFFD73027)];
const List<double> _rmsSinirlari = [3, 5, 7, 9]; // m/s²: bu sınırlarla 5 renk
Color _rmsRengi(double rms) {
  var k = 0;
  while (k < _rmsSinirlari.length && rms >= _rmsSinirlari[k]) {
    k++;
  }
  return _renkler[k];
}

Color _puanRengi(int puan) => _renkler[5 - puan.clamp(1, 5)];

// GPS konumu sensörden ~1 sn geç gelir (analiz betiğindeki gecikme düzeltmesi): sensör satırının konumu 2 satır sonrakidir
const int _gecikmeSatir = 2;
const Duration _gecikme = Duration(seconds: 1);

class _Satir {
  _Satir(this.t, this.konum, this.hiz, this.rms, this.tepe, this.uyari, this.isaret, this.kaynak);
  final DateTime t;
  final LatLng? konum;
  final double? hiz;
  final double rms, tepe; // tepe: |Dikey_Min| ve Dikey_Max'ın büyüğü
  final bool uyari; // uygulamanın anlık çukur uyarısı (Cukur = 1)
  final int isaret; // sürücünün çukur işareti basışı
  final String kaynak;
}

class _PuanParca {
  _PuanParca(this.no, this.bas, this.bit, this.uzunluk, this.puan);
  final int no;
  final DateTime bas, bit;
  final double uzunluk;
  final int? puan;
  List<LatLng> noktalar = [];
  double? rms; // parçadaki hareket satırlarının medyan Dikey_RMS'i (hız düzeltmesiz)
}

class _Isaret {
  _Isaret(this.basis, this.cukur, this.konum, this.tepe);
  final _Satir basis;
  final _Satir? cukur; // basıştan önceki 5 sn'deki en büyük tepe (yoksa null)
  final LatLng? konum;
  final double? tepe;
}

DateTime? _zaman(String s) => DateTime.tryParse(s.trim().replaceAll(',', '.'));
double? _sayi(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));
String _ondalik(double v, int b) => v.toStringAsFixed(b).replaceAll('.', ',');

class _Veri {
  final List<_Satir> satirlar = [];
  final List<_PuanParca> parcalar = [];
  final List<_Isaret> isaretler = [];
  final Map<String, String> bilgi = {};
  bool test = false;

  // Sensör satırı i'nin gecikme düzeltmeli konumu
  LatLng? konum(int i) {
    final j = min(i + _gecikmeSatir, satirlar.length - 1);
    return satirlar[j].konum ?? satirlar[i].konum;
  }

  static Future<_Veri> oku(File csv) async {
    final v = _Veri()..test = csv.uri.pathSegments.last.startsWith('test_');
    final satirlar = await csv.readAsLines();
    if (satirlar.isEmpty) return v;
    final b = satirlar.first.replaceFirst('﻿', '').split(';');
    int s(String ad) => b.indexOf(ad);
    final iT = s('Tarih_Saat'), iE = s('Enlem'), iB = s('Boylam'), iH = s('GPS_Doppler_Hiz_kmh'), iR = s('Dikey_RMS');
    final iMin = s('Dikey_Min'), iMax = s('Dikey_Max'), iC = s('Cukur'), iI = s('Isaret'), iK = s('Isaret_Kaynak');
    String h(List<String> c, int i) => i >= 0 && i < c.length ? c[i] : '';
    for (final satir in satirlar.skip(1)) {
      final c = satir.split(';');
      final t = _zaman(h(c, iT));
      final rms = _sayi(h(c, iR));
      if (t == null || rms == null) continue;
      final e = _sayi(h(c, iE)), bo = _sayi(h(c, iB));
      final tepe = max((_sayi(h(c, iMin)) ?? 0).abs(), _sayi(h(c, iMax)) ?? 0);
      v.satirlar.add(_Satir(t, e == null || bo == null ? null : LatLng(e, bo), _sayi(h(c, iH)), rms, tepe, h(c, iC).trim() == '1',
          int.tryParse(h(c, iI).trim()) ?? 0, h(c, iK).trim()));
    }
    v._isaretleriBul();
    await v._puanOku(puanFileFor(csv));
    await v._bilgiOku(infoFileFor(csv));
    return v;
  }

  // Basit eşleştirme: basıştan önceki 5 sn içindeki en büyük ivme tepesi çukur sayılır (tepki süresi 1-3 sn)
  void _isaretleriBul() {
    for (var i = 0; i < satirlar.length; i++) {
      final p = satirlar[i];
      if (p.isaret <= 0) continue;
      int? enIyi;
      for (var j = i - 1; j >= 0 && p.t.difference(satirlar[j].t) <= const Duration(seconds: 5); j--) {
        if (enIyi == null || satirlar[j].tepe > satirlar[enIyi].tepe) enIyi = j;
      }
      isaretler.add(enIyi == null
          ? _Isaret(p, null, konum(i), null)
          : _Isaret(p, satirlar[enIyi], konum(enIyi), satirlar[enIyi].tepe));
    }
  }

  Future<void> _puanOku(File dosya) async {
    if (!await dosya.exists()) return;
    final s = await dosya.readAsLines();
    if (s.isEmpty) return;
    final b = s.first.replaceFirst('﻿', '').split(';');
    final iN = b.indexOf('Parca'), iBas = b.indexOf('Baslangic'), iBit = b.indexOf('Bitis'), iU = b.indexOf('Uzunluk_m'), iP = b.indexOf('Puan');
    if ([iN, iBas, iBit, iP].any((x) => x < 0)) return;
    for (final satir in s.skip(1)) {
      final c = satir.split(';');
      if (c.length <= [iN, iBas, iBit, iP].reduce(max)) continue;
      final bas = _zaman(c[iBas]), bit = _zaman(c[iBit]);
      if (bas == null || bit == null) continue;
      parcalar.add(_PuanParca(int.tryParse(c[iN]) ?? parcalar.length + 1, bas, bit, iU >= 0 && iU < c.length ? _sayi(c[iU]) ?? 0 : 0,
          int.tryParse(c[iP].trim())));
    }
    // Parçanın satırları: konumu (gecikme düzeltmeli) parçanın zaman aralığında kalan sensör satırları
    for (final p in parcalar) {
      final rmsler = <double>[];
      for (var i = 0; i < satirlar.length; i++) {
        final t = satirlar[i].t.add(_gecikme);
        if (t.isBefore(p.bas) || t.isAfter(p.bit)) continue;
        final k = konum(i);
        if (k != null) p.noktalar.add(k);
        if ((satirlar[i].hiz ?? 0) >= 3) rmsler.add(satirlar[i].rms);
      }
      if (rmsler.isNotEmpty) {
        rmsler.sort();
        p.rms = rmsler[rmsler.length ~/ 2];
      }
    }
  }

  Future<void> _bilgiOku(File dosya) async {
    if (!await dosya.exists()) return;
    for (final satir in await dosya.readAsLines()) {
      for (final a in ['Scooter', 'Hava durumu', 'Çukur modu', 'Cihaz']) {
        if (satir.startsWith('$a:')) bilgi[a] = satir.substring(a.length + 1).trim();
      }
    }
  }

  List<LatLng> get iz => [for (final s in satirlar) if (s.konum != null) s.konum!];

  double get mesafe {
    final d = const Distance(roundResult: false);
    var top = 0.0;
    LatLng? onceki;
    for (final k in iz) {
      if (onceki != null && k != onceki) {
        final m = d.as(LengthUnit.Meter, onceki, k);
        if (m < 200) top += m; // GPS sıçraması sayılmaz
      }
      onceki = k;
    }
    return top;
  }
}

// Spearman sıra korelasyonu (eşit değerlere ortalama sıra)
double? _spearman(List<double> x, List<double> y) {
  if (x.length < 3) return null;
  List<double> sira(List<double> v) {
    final idx = List.generate(v.length, (i) => i)..sort((a, b) => v[a].compareTo(v[b]));
    final r = List<double>.filled(v.length, 0);
    var i = 0;
    while (i < idx.length) {
      var j = i;
      while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
        j++;
      }
      for (var k = i; k <= j; k++) {
        r[idx[k]] = (i + j) / 2 + 1;
      }
      i = j + 1;
    }
    return r;
  }

  final rx = sira(x), ry = sira(y);
  final mx = rx.reduce((a, b) => a + b) / rx.length, my = ry.reduce((a, b) => a + b) / ry.length;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < rx.length; i++) {
    sxy += (rx[i] - mx) * (ry[i] - my);
    sxx += (rx[i] - mx) * (rx[i] - mx);
    syy += (ry[i] - my) * (ry[i] - my);
  }
  return sxx == 0 || syy == 0 ? null : sxy / sqrt(sxx * syy);
}

class OnizlemeSayfasi extends StatefulWidget {
  const OnizlemeSayfasi({super.key, required this.csv});
  final File csv;

  @override
  State<OnizlemeSayfasi> createState() => _OnizlemeSayfasiState();
}

class _OnizlemeSayfasiState extends State<OnizlemeSayfasi> {
  _Veri? _veri;
  String? _hata;
  final PageController _sayfa = PageController();
  int _sayfaNo = 0;
  static const List<(IconData, String)> _sekmeler = [
    (Icons.map_outlined, 'Harita'),
    (Icons.show_chart, 'Grafikler'),
    (Icons.star_outline, 'Puanlar'),
    (Icons.list_alt, 'Özet'),
  ];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = await _Veri.oku(widget.csv);
      if (mounted) setState(() => _veri = v);
    } catch (e) {
      if (mounted) setState(() => _hata = '$e');
    }
  }

  @override
  void dispose() {
    _sayfa.dispose();
    super.dispose();
  }

  Future<void> _puanla() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PuanlamaSayfasi(csv: widget.csv)));
    await telefonaKopyala(await kayitDosyalari(widget.csv));
    if (!mounted) return;
    setState(() => _veri = null);
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    final ad = widget.csv.uri.pathSegments.last;
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEF),
      appBar: AppBar(
        backgroundColor: _lacivert,
        foregroundColor: Colors.white,
        title: Text(ad.startsWith('test_') ? 'Önizleme (TEST)' : 'Önizleme'),
        actions: [
          IconButton(icon: const Icon(Icons.table_view), tooltip: 'CSV\'yi aç', onPressed: () => kaydiAc(context, widget.csv)),
          IconButton(icon: const Icon(Icons.share), tooltip: 'Paylaş', onPressed: () => shareRecording(widget.csv)),
        ],
      ),
      body: _hata != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Kayıt okunamadı: $_hata')))
          : v == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _sekmeCubugu(),
                    Expanded(
                      child: PageView(
                        controller: _sayfa,
                        onPageChanged: (i) => setState(() => _sayfaNo = i),
                        children: [_HaritaSayfasi(v), _GrafikSayfasi(v), _PuanSayfasi(v, _puanla), _OzetSayfasi(v, ad)],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _sekmeCubugu() => Material(
        color: Colors.white,
        elevation: 1,
        child: Row(
          children: [
            for (var i = 0; i < _sekmeler.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => _sayfa.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: i == _sayfaNo ? _lacivert : Colors.transparent, width: 3)),
                    ),
                    child: Column(
                      children: [
                        Icon(_sekmeler[i].$1, size: 20, color: i == _sayfaNo ? _lacivert : _gri),
                        Text(_sekmeler[i].$2,
                            style: TextStyle(fontSize: 12, color: i == _sayfaNo ? _lacivert : _gri, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

// Altlık harita ve ortak katmanlar
class _Harita extends StatelessWidget {
  const _Harita({required this.noktalar, required this.katmanlar});
  final List<LatLng> noktalar;
  final List<Widget> katmanlar;

  @override
  Widget build(BuildContext context) {
    if (noktalar.isEmpty) {
      return const Center(child: Text('Kayıtta GPS konumu yok', style: TextStyle(color: _gri)));
    }
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: noktalar.length > 1
            ? CameraFit.coordinates(coordinates: noktalar, padding: const EdgeInsets.all(32), maxZoom: 18)
            : null,
        initialCenter: noktalar.first,
        initialZoom: 17,
        maxZoom: 19,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'tr.edu.yildiz.kaan_usta',
          maxNativeZoom: 19,
        ),
        ...katmanlar,
        const RichAttributionWidget(attributions: [TextSourceAttribution('Esri, HERE, Garmin, © OpenStreetMap katkıcıları')]),
      ],
    );
  }
}

Widget _lejant(List<(Color, String)> ogeler, {Widget? ek}) => Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final (renk, yazi) in ogeler)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 14, height: 14, decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 4),
                  Text(yazi, style: const TextStyle(fontSize: 12)),
                ]),
            ],
          ),
          ?ek,
        ],
      ),
    );

class _HaritaSayfasi extends StatelessWidget {
  const _HaritaSayfasi(this.v);
  final _Veri v;

  @override
  Widget build(BuildContext context) {
    // Güzergâh sarsıntıya göre renkli: ardışık aynı renkli satırlar tek çizgi
    final cizgiler = <Polyline>[];
    List<LatLng> parca = [];
    Color? renk;
    for (var i = 0; i < v.satirlar.length; i++) {
      final k = v.konum(i);
      if (k == null) continue;
      final r = _rmsRengi(v.satirlar[i].rms);
      if (r != renk && parca.isNotEmpty) {
        parca.add(k);
        cizgiler.add(Polyline(points: parca, strokeWidth: 6, color: renk!));
        parca = [];
      }
      renk = r;
      parca.add(k);
    }
    if (parca.length > 1) cizgiler.add(Polyline(points: parca, strokeWidth: 6, color: renk!));
    final uyarilar = [
      for (var i = 0; i < v.satirlar.length; i++)
        if (v.satirlar[i].uyari && v.konum(i) != null) v.konum(i)!,
    ];
    final iz = v.iz;
    return Column(
      children: [
        Expanded(
          child: _Harita(noktalar: iz, katmanlar: [
            PolylineLayer(polylines: [Polyline(points: iz, strokeWidth: 9, color: Colors.white), ...cizgiler]),
            CircleLayer(circles: [
              for (final k in uyarilar) CircleMarker(point: k, radius: 5, color: Colors.white, borderColor: const Color(0xFFDC3545), borderStrokeWidth: 2.5),
              if (iz.isNotEmpty) CircleMarker(point: iz.first, radius: 7, color: const Color(0xFF198754), borderColor: Colors.white, borderStrokeWidth: 2),
              if (iz.isNotEmpty) CircleMarker(point: iz.last, radius: 7, color: Colors.black87, borderColor: Colors.white, borderStrokeWidth: 2),
            ]),
            MarkerLayer(markers: [
              for (var n = 0; n < v.isaretler.length; n++)
                if (v.isaretler[n].konum != null)
                  Marker(
                    point: v.isaretler[n].konum!,
                    width: 26,
                    height: 26,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _lacivert, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white, width: 2)),
                      child: Text('${n + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
            ]),
          ]),
        ),
        _lejant([
          for (var k = 0; k < 5; k++)
            (_renkler[k], k == 0 ? '<${_rmsSinirlari[0].toStringAsFixed(0)}' : k == 4 ? '≥${_rmsSinirlari[3].toStringAsFixed(0)}' : '${_rmsSinirlari[k - 1].toStringAsFixed(0)}-${_rmsSinirlari[k].toStringAsFixed(0)}'),
          (_lacivert, 'çukur işareti (${v.isaretler.length})'),
          (const Color(0xFFDC3545), 'uygulama uyarısı (${uyarilar.length})'),
        ],
            ek: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Renk: Dikey_RMS (m/s²), hız düzeltmesiz. Yeşil nokta başlangıç, siyah bitiş. '
                  'Diğer sayfalar için sekmelere dokunun veya bu alanda kaydırın.',
                  style: TextStyle(fontSize: 11, color: _gri)),
            )),
      ],
    );
  }
}

// ---------------------------------------------------------------- grafikler (CustomPainter, ek paket yok)

class _Seri {
  const _Seri(this.noktalar, this.renk, {this.dagilim = false, this.yaricap = 2.6});
  final List<Offset> noktalar; // y NaN ise çizgi kesilir
  final Color renk;
  final bool dagilim; // nokta bulutu
  final double yaricap;
}

class _Cizim extends CustomPainter {
  _Cizim({required this.seriler, required this.xEtiket, required this.yEtiket, this.dikeyler = const [], this.isaretNoktalari = const [],
      this.uyariNoktalari = const [], this.xMin, this.xMax, this.xTamsayi = false});
  final List<_Seri> seriler;
  final String xEtiket, yEtiket;
  final List<double> dikeyler; // basış anları (kesikli lacivert çizgi)
  final List<Offset> isaretNoktalari; // işaretli çukur (lacivert kare)
  final List<Offset> uyariNoktalari; // uygulama uyarısı (kırmızı halka)
  final double? xMin, xMax;
  final bool xTamsayi;

  static double _adim(double aralik, int hedef) {
    final ham = aralik / hedef;
    final us = pow(10, (log(ham) / ln10).floor()).toDouble();
    for (final c in [1, 2, 5, 10]) {
      if (c * us >= ham) return c * us;
    }
    return 10 * us;
  }

  void _yazi(Canvas c, String s, Offset o, {double boy = 10, Color renk = _gri, bool ortala = false, bool sag = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontFamily: 'Roboto', fontSize: boy, color: renk)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o - Offset(ortala ? tp.width / 2 : (sag ? tp.width : 0), tp.height / 2));
  }

  @override
  void paint(Canvas c, Size size) {
    final tum = [for (final s in seriler) ...s.noktalar.where((p) => p.dy.isFinite)];
    if (tum.isEmpty) return;
    const sol = 34.0, alt = 30.0, ust = 16.0, sagB = 8.0;
    final x0 = xMin ?? tum.map((p) => p.dx).reduce(min), x1 = xMax ?? tum.map((p) => p.dx).reduce(max);
    final yUst = max(1.0, [...tum.map((p) => p.dy), ...isaretNoktalari.map((p) => p.dy), ...uyariNoktalari.map((p) => p.dy)].reduce(max) * 1.08);
    final w = size.width - sol - sagB, h = size.height - alt - ust;
    Offset ekran(double x, double y) => Offset(sol + (x1 == x0 ? 0.5 : (x - x0) / (x1 - x0)) * w, ust + h - (y / yUst).clamp(0, 1) * h);
    final izgara = Paint()
      ..color = const Color(0xFFDEE2E6)
      ..strokeWidth = 1;
    final ya = _adim(yUst, 4);
    for (var y = 0.0; y <= yUst; y += ya) {
      final p = ekran(x0, y);
      c.drawLine(Offset(sol, p.dy), Offset(sol + w, p.dy), izgara);
      _yazi(c, _ondalik(y, ya < 1 ? 1 : 0), Offset(sol - 4, p.dy), sag: true);
    }
    final xa = xTamsayi ? 1.0 : _adim(x1 - x0, 5);
    for (var x = (x0 / xa).ceil() * xa; x <= x1 + 1e-9; x += xa) {
      final p = ekran(x, 0);
      c.drawLine(Offset(p.dx, ust + h), Offset(p.dx, ust + h + 3), izgara..color = _gri);
      _yazi(c, _ondalik(x, 0), Offset(p.dx, ust + h + 10), ortala: true);
    }
    izgara.color = const Color(0xFFDEE2E6);
    _yazi(c, xEtiket, Offset(sol + w / 2, size.height - 6), ortala: true, boy: 10.5);
    _yazi(c, yEtiket, Offset(sol, 6), boy: 10.5, renk: Colors.black87);
    // Basış anları
    final kesik = Paint()
      ..color = _lacivert.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final x in dikeyler) {
      final px = ekran(x, 0).dx;
      for (var y = ust; y < ust + h; y += 6) {
        c.drawLine(Offset(px, y), Offset(px, min(y + 3, ust + h)), kesik);
      }
    }
    for (final s in seriler) {
      final boya = Paint()
        ..color = s.renk
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      if (s.dagilim) {
        boya.style = PaintingStyle.fill;
        boya.color = s.renk.withValues(alpha: 0.45);
        for (final p in s.noktalar) {
          if (p.dy.isFinite) c.drawCircle(ekran(p.dx, p.dy), s.yaricap, boya);
        }
        continue;
      }
      final yol = Path();
      var basla = true;
      for (final p in s.noktalar) {
        if (!p.dy.isFinite) {
          basla = true;
          continue;
        }
        final e = ekran(p.dx, p.dy);
        basla ? yol.moveTo(e.dx, e.dy) : yol.lineTo(e.dx, e.dy);
        basla = false;
      }
      c.drawPath(yol, boya);
    }
    final halka = Paint()
      ..color = const Color(0xFFDC3545)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    for (final p in uyariNoktalari) {
      c.drawCircle(ekran(p.dx, p.dy), 5, halka);
    }
    final kare = Paint()
      ..color = _lacivert
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in isaretNoktalari) {
      c.drawRect(Rect.fromCenter(center: ekran(p.dx, p.dy), width: 10, height: 10), kare);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Widget _kart(String baslik, Widget icerik, {String? not}) => Card(
      color: Colors.white,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(baslik, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _lacivert)),
          const SizedBox(height: 6),
          icerik,
          if (not != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(not, style: const TextStyle(fontSize: 11, color: _gri))),
        ]),
      ),
    );

class _GrafikSayfasi extends StatelessWidget {
  const _GrafikSayfasi(this.v);
  final _Veri v;

  @override
  Widget build(BuildContext context) {
    if (v.satirlar.isEmpty) return const Center(child: Text('Kayıtta veri yok'));
    final t0 = v.satirlar.first.t;
    double sn(DateTime t) => t.difference(t0).inMilliseconds / 1000;
    final hiz = [for (final s in v.satirlar) Offset(sn(s.t), s.hiz ?? double.nan)];
    final rms = [for (final s in v.satirlar) Offset(sn(s.t), s.rms)];
    final basislar = [for (final i in v.isaretler) sn(i.basis.t)];
    final cukurlar = [for (final i in v.isaretler) if (i.cukur != null) Offset(sn(i.cukur!.t), i.cukur!.rms)];
    final uyarilar = [for (final s in v.satirlar) if (s.uyari) Offset(sn(s.t), s.rms)];
    final dagilim = [for (final s in v.satirlar) if ((s.hiz ?? 0) >= 3) Offset(s.hiz!, s.rms)];
    final xMax = sn(v.satirlar.last.t);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _kart(
          'Hız (km/h)',
          SizedBox(
            height: 150,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Cizim(seriler: [_Seri(hiz, const Color(0xFF2F7ED8))], xEtiket: 'kayıt başından süre (s)', yEtiket: 'km/h',
                  dikeyler: basislar, xMin: 0, xMax: xMax),
            ),
          ),
          not: v.test ? 'TEST SÜRÜŞÜ: hız sanaldır.' : 'Kesikli çizgi: çukur butonuna basış.',
        ),
        _kart(
          'Dikey sarsıntı (Dikey_RMS, m/s²)',
          SizedBox(
            height: 170,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Cizim(seriler: [_Seri(rms, const Color(0xFFE8590C))], xEtiket: 'kayıt başından süre (s)', yEtiket: 'm/s²',
                  dikeyler: basislar, isaretNoktalari: cukurlar, uyariNoktalari: uyarilar, xMin: 0, xMax: xMax),
            ),
          ),
          not: 'Lacivert kare: işaretli çukur (basıştan önceki 5 sn\'deki en büyük tepe). Kırmızı halka: uygulamanın anlık uyarısı.',
        ),
        _kart(
          'Hıza göre sarsıntı',
          SizedBox(
            height: 170,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Cizim(seriler: [_Seri(dagilim, const Color(0xFFE8590C), dagilim: true)], xEtiket: 'hız (km/h)', yEtiket: 'Dikey_RMS (m/s²)', xMin: 0),
            ),
          ),
          not: 'Her nokta 0,5 sn\'lik bir satır (3 km/h altı hariç). Sarsıntı hem yüzeye hem hıza bağlıdır; hız düzeltmesi bilgisayardaki analizdedir.',
        ),
        _kart(
          'Çukur işaretleri (${v.isaretler.length})',
          v.isaretler.isEmpty
              ? const Text('Bu kayıtta çukur işareti yok.', style: TextStyle(fontSize: 13))
              : Column(children: [
                  for (var n = 0; n < v.isaretler.length; n++) _isaretSatiri(n, v.isaretler[n], sn),
                ]),
        ),
      ],
    );
  }

  Widget _isaretSatiri(int n, _Isaret i, double Function(DateTime) sn) {
    final c = i.cukur;
    final tepki = c == null ? null : i.basis.t.difference(c.t).inMilliseconds / 1000;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _lacivert, borderRadius: BorderRadius.circular(4)),
          child: Text('${n + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_ondalik(sn(i.basis.t), 1)} s · ${i.basis.kaynak.isEmpty ? 'basış' : i.basis.kaynak}'
            '${c == null ? '' : ' · tepe ${_ondalik(i.tepe!, 1)} m/s², ${_ondalik(tepki!, 1)} sn önce'}'
            '${c != null && c.uyari ? ' · uygulama da uyardı' : ''}',
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}

class _PuanSayfasi extends StatelessWidget {
  const _PuanSayfasi(this.v, this.puanla);
  final _Veri v;
  final VoidCallback puanla;

  @override
  Widget build(BuildContext context) {
    final puanli = v.parcalar.where((p) => p.puan != null).toList();
    if (puanli.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Bu kayıt henüz puanlanmadı.', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: puanla, icon: const Icon(Icons.star), label: const Text('Şimdi puanla')),
          ]),
        ),
      );
    }
    final giren = puanli.where((p) => p.rms != null).toList();
    final r = _spearman([for (final p in giren) p.puan!.toDouble()], [for (final p in giren) p.rms!]);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SizedBox(
          height: 300,
          child: _Harita(noktalar: v.iz, katmanlar: [
            PolylineLayer(polylines: [
              Polyline(points: v.iz, strokeWidth: 3, color: const Color(0x99495057)),
              for (final p in v.parcalar)
                if (p.noktalar.length > 1)
                  Polyline(
                      points: p.noktalar,
                      strokeWidth: 7,
                      color: p.puan == null ? const Color(0xFFADB5BD) : _puanRengi(p.puan!),
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.white),
            ]),
          ]),
        ),
        _lejant([for (var p = 1; p <= 5; p++) (_puanRengi(p), '$p ${['', 'çok sarsıntılı', 'sarsıntılı', 'orta', 'rahat', 'çok rahat'][p]}')]),
        _kart(
          'Puan ve ölçülen sarsıntı',
          SizedBox(
            height: 170,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Cizim(
                  seriler: [_Seri([for (final p in giren) Offset(p.puan!.toDouble(), p.rms!)], _lacivert, dagilim: true, yaricap: 6)],
                  xEtiket: 'puan (1 çok sarsıntılı - 5 çok rahat)',
                  yEtiket: 'medyan Dikey_RMS (m/s²)',
                  xMin: 0.5,
                  xMax: 5.5,
                  xTamsayi: true),
            ),
          ),
          not: r == null
              ? 'Karşılaştırma için en az 3 puanlı parça gerekir.'
              : 'Spearman r = ${_ondalik(r, 2)} (n = ${giren.length}; beklenen yön negatif). Basit gösterim: hız düzeltmesiz; '
                  'hız düzeltmeli indeks ve anlamlılık testi bilgisayardaki analizde.',
        ),
        _kart(
          'Parçalar',
          Table(
            columnWidths: const {0: FixedColumnWidth(44), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth(1.3)},
            children: [
              const TableRow(children: [
                Text('Parça', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text('Uzunluk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text('Puan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text('Dikey_RMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
              for (final p in v.parcalar)
                TableRow(children: [
                  Text('${p.no}', style: const TextStyle(fontSize: 12.5)),
                  Text('${p.uzunluk.round()} m', style: const TextStyle(fontSize: 12.5)),
                  Row(children: [
                    Container(width: 10, height: 10, color: p.puan == null ? const Color(0xFFADB5BD) : _puanRengi(p.puan!)),
                    const SizedBox(width: 4),
                    Text(p.puan?.toString() ?? '-', style: const TextStyle(fontSize: 12.5)),
                  ]),
                  Text(p.rms == null ? '-' : '${_ondalik(p.rms!, 2)} m/s²', style: const TextStyle(fontSize: 12.5)),
                ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: OutlinedButton.icon(onPressed: puanla, icon: const Icon(Icons.edit), label: const Text('Puanları değiştir')),
        ),
      ],
    );
  }
}

class _OzetSayfasi extends StatelessWidget {
  const _OzetSayfasi(this.v, this.ad);
  final _Veri v;
  final String ad;

  @override
  Widget build(BuildContext context) {
    final s = v.satirlar;
    if (s.isEmpty) return const Center(child: Text('Kayıtta veri yok'));
    final sure = s.last.t.difference(s.first.t).inSeconds;
    final hareket = s.where((x) => (x.hiz ?? 0) >= 3).toList();
    final hizlar = [for (final x in s) if (x.hiz != null) x.hiz!];
    double medyan(List<double> l) {
      if (l.isEmpty) return double.nan;
      final k = [...l]..sort();
      return k[k.length ~/ 2];
    }

    final kaynaklar = <String, int>{};
    for (final i in v.isaretler) {
      final k = i.basis.kaynak.isEmpty ? 'bilinmiyor' : i.basis.kaynak;
      kaynaklar[k] = (kaynaklar[k] ?? 0) + 1;
    }
    final uyari = s.where((x) => x.uyari).length;
    final isaretUyari = v.isaretler.where((i) => i.cukur?.uyari ?? false).length;
    final satirlar = <(String, String)>[
      ('Süre', '${sure ~/ 60} dk ${sure % 60} sn'),
      ('GPS ile yol', '~${v.mesafe.round()} m'),
      ('En yüksek hız', hizlar.isEmpty ? '-' : '${_ondalik(hizlar.reduce(max), 1)} km/h'),
      ('Hareket hâlinde medyan hız', hareket.isEmpty ? '-' : '${_ondalik(medyan([for (final x in hareket) x.hiz!]), 1)} km/h'),
      ('Medyan Dikey_RMS (hareket)', hareket.isEmpty ? '-' : '${_ondalik(medyan([for (final x in hareket) x.rms]), 2)} m/s²'),
      ('En büyük ivme tepesi', '${_ondalik(s.map((x) => x.tepe).reduce(max), 1)} m/s²'),
      ('Çukur işareti', v.isaretler.isEmpty ? 'yok' : '${v.isaretler.length} (${kaynaklar.entries.map((e) => '${e.key} ${e.value}').join(', ')})'),
      ('Uygulamanın anlık uyarısı', '$uyari satır${v.isaretler.isEmpty ? '' : '; işaretli çukurların $isaretUyari tanesinde'}'),
      ('Puanlanan parça', v.parcalar.isEmpty ? 'puanlanmadı' : '${v.parcalar.where((p) => p.puan != null).length} / ${v.parcalar.length}'),
      for (final a in ['Çukur modu', 'Scooter', 'Hava durumu', 'Cihaz'])
        if (v.bilgi[a] != null) (a, v.bilgi[a]!),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (v.test)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(10)),
            child: const Text('TEST SÜRÜŞÜ: konum ve hız sanaldır (YTÜ Davutpaşa); sarsıntı gerçek ivmeölçerden.',
                style: TextStyle(fontSize: 12.5)),
          ),
        _kart(
          'Özet',
          Table(
            columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4)},
            children: [
              for (final (a, b) in satirlar)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(a, style: const TextStyle(fontSize: 12.5, color: _gri))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(b, style: const TextStyle(fontSize: 12.5))),
                ]),
            ],
          ),
          not: ad,
        ),
        _kart(
          'Bu önizleme hakkında',
          const Text(
            'Telefonda gösterim içindir; ham ölçümleri olduğu gibi gösterir. Bilgisayardaki analiz bunlara ek olarak GPS\'i '
            'OpenStreetMap yollarına oturtur, sarsıntıyı hıza göre düzeltir (sokak indeksi), darbeleri çevredeki sarsıntıya göre bulur, '
            'işaretleri darbelerle eşleştirir ve puan-indeks ilişkisini test eder.',
            style: TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ],
    );
  }
}
