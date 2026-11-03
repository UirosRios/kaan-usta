import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'puanlama.dart';
import 'recordings_page.dart';

// KAYIT ÖNİZLEMESİ (gösterim amaçlı, sade): bir kaydın haritası, grafikleri, konfor puanları ve özeti telefonda.
// Test sürüşleri dahil her kayıtta çalışır. Güzergâh 25 m'lik parçalara bölünür; her parça medyan Dikey_RMS'ine göre
// üç renkten birini alır (tek tek sarsıntı tepeleri gösterilmez). Asıl analiz (haritaya oturtma, hız düzeltmesi, darbe
// tespiti, istatistik) bilgisayardaki betiktedir.

const Color _lacivert = Color(0xFF003366);
const Color _gri = Color(0xFF6C757D);

// Üç sarsıntı sınıfı (hareket hâlindeki medyan Dikey_RMS, m/s²). Sınırlar Kadıköy sürüşlerindeki 25 m'lik parçaların
// dağılımından: düzgün asfalt ~3-5, bozuk asfalt / parke ~5-8, Arnavut kaldırımı ve çok bozuk yol ≥ 8.
enum _Sinif {
  duzgun('Düzgün', Color(0xFF1A9850)),
  orta('Orta', Color(0xFFF4A72B)),
  sarsintili('Sarsıntılı', Color(0xFFD73027));

  const _Sinif(this.ad, this.renk);
  final String ad;
  final Color renk;

  static _Sinif rms(double r) => r < 5 ? duzgun : (r < 8 ? orta : sarsintili);
}

const List<Color> _puanRenkleri = [Color(0xFFD73027), Color(0xFFFC8D59), Color(0xFFF4C542), Color(0xFF91CF60), Color(0xFF1A9850)];
const List<String> _puanAdlari = ['çok sarsıntılı', 'sarsıntılı', 'orta', 'rahat', 'çok rahat'];
Color _puanRengi(int puan) => _puanRenkleri[puan.clamp(1, 5) - 1];

// GPS konumu sensörden ~1 sn geç gelir (analiz betiğindeki gecikme düzeltmesi): sensör satırının konumu 2 satır sonrakidir
const int _gecikmeSatir = 2;
const Duration _gecikme = Duration(seconds: 1);
const double _minHiz = 3; // km/h: altı duruş
const double _haritaParcasi = 25; // m

class _Satir {
  _Satir(this.t, this.konum, this.hiz, this.rms, this.tepe, this.isaret);
  final DateTime t;
  final LatLng? konum;
  final double? hiz;
  final double rms, tepe; // tepe: |Dikey_Min| ve Dikey_Max'ın büyüğü
  final int isaret; // sürücünün çukur işareti basışı
  bool get hareket => (hiz ?? 0) >= _minHiz;
}

class _Bolum {
  _Bolum(this.noktalar, this.rms);
  final List<LatLng> noktalar;
  final double? rms; // hareket satırlarının medyan Dikey_RMS'i
  double uzunluk = 0;
}

class _PuanParca {
  _PuanParca(this.no, this.bas, this.bit, this.uzunluk, this.puan);
  final int no;
  final DateTime bas, bit;
  final double uzunluk;
  final int? puan;
  List<LatLng> noktalar = [];
  double? rms;
}

class _Isaret {
  _Isaret(this.t, this.konum);
  final DateTime t; // çukur anı: basıştan önceki 5 sn'deki en büyük ivme tepesi (yoksa basış anı)
  final LatLng? konum;
}

DateTime? _zaman(String s) => DateTime.tryParse(s.trim().replaceAll(',', '.'));
double? _sayi(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));
String _ondalik(double v, int b) => v.toStringAsFixed(b).replaceAll('.', ',');
double? _medyan(List<double> l) {
  if (l.isEmpty) return null;
  final k = [...l]..sort();
  return k[k.length ~/ 2];
}

class _Veri {
  final List<_Satir> satirlar = [];
  final List<_Bolum> bolumler = [];
  final List<_PuanParca> parcalar = [];
  final List<_Isaret> isaretler = [];
  final Map<String, String> bilgi = {};
  bool test = false;
  double mesafe = 0;

  static const Distance _d = Distance(roundResult: false);

  // Sensör satırı i'nin gecikme düzeltmeli konumu
  LatLng? konum(int i) {
    final j = min(i + _gecikmeSatir, satirlar.length - 1);
    return satirlar[j].konum ?? satirlar[i].konum;
  }

  List<LatLng> get iz => [for (var i = 0; i < satirlar.length; i++) if (konum(i) != null) konum(i)!];

  static Future<_Veri> oku(File csv) async {
    final v = _Veri()..test = csv.uri.pathSegments.last.startsWith('test_');
    final satirlar = await csv.readAsLines();
    if (satirlar.isEmpty) return v;
    final b = satirlar.first.replaceFirst('﻿', '').split(';');
    int s(String ad) => b.indexOf(ad);
    final iT = s('Tarih_Saat'), iE = s('Enlem'), iB = s('Boylam'), iH = s('GPS_Doppler_Hiz_kmh'), iR = s('Dikey_RMS');
    final iMin = s('Dikey_Min'), iMax = s('Dikey_Max'), iI = s('Isaret');
    String h(List<String> c, int i) => i >= 0 && i < c.length ? c[i] : '';
    for (final satir in satirlar.skip(1)) {
      final c = satir.split(';');
      final t = _zaman(h(c, iT));
      final rms = _sayi(h(c, iR));
      if (t == null || rms == null) continue;
      final e = _sayi(h(c, iE)), bo = _sayi(h(c, iB));
      final tepe = max((_sayi(h(c, iMin)) ?? 0).abs(), _sayi(h(c, iMax)) ?? 0);
      v.satirlar.add(_Satir(t, e == null || bo == null ? null : LatLng(e, bo), _sayi(h(c, iH)), rms, tepe, int.tryParse(h(c, iI).trim()) ?? 0));
    }
    v._bolumle();
    v._isaretleriBul();
    await v._puanOku(puanFileFor(csv));
    await v._bilgiOku(infoFileFor(csv));
    return v;
  }

  // Güzergâhı ~25 m'lik bölümlere ayır; her bölüm medyan sarsıntısıyla tek renk
  void _bolumle() {
    var noktalar = <LatLng>[];
    var rmsler = <double>[];
    var uzunluk = 0.0;
    LatLng? onceki;
    void kapat() {
      if (noktalar.length > 1) bolumler.add(_Bolum(noktalar, _medyan(rmsler))..uzunluk = uzunluk);
    }

    for (var i = 0; i < satirlar.length; i++) {
      final k = konum(i);
      if (k == null) continue;
      if (onceki != null) {
        final m = _d.as(LengthUnit.Meter, onceki, k);
        if (m > 200) {
          // GPS sıçraması / kesinti: çizgi burada kesilir
          kapat();
          noktalar = [];
          rmsler = [];
          uzunluk = 0;
        } else {
          uzunluk += m;
          mesafe += m;
        }
      }
      noktalar.add(k);
      if (satirlar[i].hareket) rmsler.add(satirlar[i].rms);
      onceki = k;
      if (uzunluk >= _haritaParcasi) {
        kapat();
        noktalar = [k];
        rmsler = [];
        uzunluk = 0;
      }
    }
    kapat();
  }

  // Basit eşleştirme: basıştan önceki 5 sn içindeki en büyük ivme tepesi çukur sayılır (tepki süresi 1-3 sn)
  void _isaretleriBul() {
    for (var i = 0; i < satirlar.length; i++) {
      if (satirlar[i].isaret <= 0) continue;
      int? enIyi;
      for (var j = i - 1; j >= 0 && satirlar[i].t.difference(satirlar[j].t) <= const Duration(seconds: 5); j--) {
        if (enIyi == null || satirlar[j].tepe > satirlar[enIyi].tepe) enIyi = j;
      }
      final k = enIyi ?? i;
      isaretler.add(_Isaret(satirlar[k].t, konum(k)));
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
        if (satirlar[i].hareket) rmsler.add(satirlar[i].rms);
      }
      p.rms = _medyan(rmsler);
    }
  }

  Future<void> _bilgiOku(File dosya) async {
    if (!await dosya.exists()) return;
    for (final satir in await dosya.readAsLines()) {
      for (final a in ['Scooter', 'Hava durumu']) {
        if (satir.startsWith('$a:')) bilgi[a] = satir.substring(a.length + 1).trim();
      }
    }
  }
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
                        children: [_HaritaSayfasi(v), _GrafikSayfasi(v), _PuanSayfasi(v, _puanla), _OzetSayfasi(v)],
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

// Altlık harita: sade gri sokak haritası (puanlama.dart, sadeAltlik)
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
        sadeAltlik(),
        ...katmanlar,
        const RichAttributionWidget(attributions: [TextSourceAttribution('Esri, HERE, Garmin, © OpenStreetMap katkıcıları')]),
      ],
    );
  }
}

Widget _lejant(List<(Color, String)> ogeler, {String? not}) => Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (renk, yazi) in ogeler)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 22, height: 8, decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 5),
                  Text(yazi, style: const TextStyle(fontSize: 13)),
                ]),
            ],
          ),
          if (not != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(not, style: const TextStyle(fontSize: 11.5, color: _gri))),
        ],
      ),
    );

// Çukur işareti: haritada küçük lacivert kare
Marker _isaretIsareti(LatLng k) => Marker(
      point: k,
      width: 16,
      height: 16,
      child: Container(decoration: BoxDecoration(color: _lacivert, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white, width: 2))),
    );

class _HaritaSayfasi extends StatelessWidget {
  const _HaritaSayfasi(this.v);
  final _Veri v;

  @override
  Widget build(BuildContext context) {
    final iz = v.iz;
    return Column(
      children: [
        Expanded(
          child: _Harita(noktalar: iz, katmanlar: [
            PolylineLayer(polylines: [
              for (final b in v.bolumler)
                Polyline(
                  points: b.noktalar,
                  strokeWidth: 8,
                  color: b.rms == null ? const Color(0xFFADB5BD) : _Sinif.rms(b.rms!).renk,
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.white,
                ),
            ]),
            CircleLayer(circles: [
              if (iz.isNotEmpty) CircleMarker(point: iz.first, radius: 7, color: Colors.white, borderColor: Colors.black87, borderStrokeWidth: 3),
            ]),
            MarkerLayer(markers: [for (final i in v.isaretler) if (i.konum != null) _isaretIsareti(i.konum!)]),
          ]),
        ),
        _lejant([
          for (final s in _Sinif.values) (s.renk, s.ad),
          if (v.isaretler.isNotEmpty) (_lacivert, 'çukur işaretim'),
        ], not: 'Her 25 m\'lik parçanın ortalama sarsıntısı. Beyaz halka başlangıç. Sayfa değiştirmek için sekmelere dokunun.'),
      ],
    );
  }
}

// ---------------------------------------------------------------- grafikler (CustomPainter, ek paket yok)

class _Cizim extends CustomPainter {
  _Cizim({required this.noktalar, required this.renk, required this.yEtiket, this.isaretler = const [], this.bantlar = false});
  final List<Offset> noktalar; // x: dakika; y NaN ise çizgi kesilir
  final Color renk;
  final String yEtiket;
  final List<double> isaretler; // çukur işareti anları (dakika)
  final bool bantlar; // sarsıntı sınıfı arka plan bantları

  static double _adim(double aralik, int hedef) {
    final ham = aralik / hedef;
    final us = pow(10, (log(ham) / ln10).floor()).toDouble();
    for (final c in [1, 2, 5, 10]) {
      if (c * us >= ham) return c * us;
    }
    return 10 * us;
  }

  void _yazi(Canvas c, String s, Offset o, {double boy = 10.5, bool ortala = false, bool sag = false}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontFamily: 'Roboto', fontSize: boy, color: _gri)), textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, o - Offset(ortala ? tp.width / 2 : (sag ? tp.width : 0), tp.height / 2));
  }

  @override
  void paint(Canvas c, Size size) {
    final gecerli = noktalar.where((p) => p.dy.isFinite).toList();
    if (gecerli.isEmpty) return;
    const sol = 30.0, alt = 32.0, ust = 8.0, sagB = 8.0;
    final x1 = max(gecerli.last.dx, 0.1);
    final yUst = max(bantlar ? 10.0 : 5.0, gecerli.map((p) => p.dy).reduce(max) * 1.1);
    final w = size.width - sol - sagB, h = size.height - alt - ust;
    Offset ekran(double x, double y) => Offset(sol + x / x1 * w, ust + h - (y / yUst).clamp(0, 1) * h);
    if (bantlar) {
      for (final (y0, y1, s) in [(0.0, 5.0, _Sinif.duzgun), (5.0, 8.0, _Sinif.orta), (8.0, yUst, _Sinif.sarsintili)]) {
        c.drawRect(Rect.fromPoints(ekran(0, y0), ekran(x1, y1)), Paint()..color = s.renk.withValues(alpha: 0.10));
      }
    }
    final izgara = Paint()
      ..color = const Color(0xFFDEE2E6)
      ..strokeWidth = 1;
    final ya = _adim(yUst, 4);
    for (var y = 0.0; y <= yUst; y += ya) {
      final p = ekran(0, y);
      c.drawLine(Offset(sol, p.dy), Offset(sol + w, p.dy), izgara);
      _yazi(c, _ondalik(y, 0), Offset(sol - 4, p.dy), sag: true);
    }
    final xa = _adim(x1, 5);
    for (var x = 0.0; x <= x1 + 1e-9; x += xa) {
      final p = ekran(x, 0);
      _yazi(c, _ondalik(x, xa < 1 ? 1 : 0), Offset(p.dx, ust + h + 9), ortala: true);
    }
    _yazi(c, 'süre (dakika)', Offset(sol + w / 2, size.height - 7), ortala: true);
    final kesik = Paint()
      ..color = _lacivert
      ..strokeWidth = 1.5;
    for (final x in isaretler) {
      final px = ekran(x, 0).dx;
      c.drawLine(Offset(px, ust), Offset(px, ust + h), kesik..color = _lacivert.withValues(alpha: 0.35));
      c.drawRect(Rect.fromCenter(center: Offset(px, ust + 4), width: 8, height: 8), Paint()..color = _lacivert);
    }
    final yol = Path();
    var basla = true;
    for (final p in noktalar) {
      if (!p.dy.isFinite) {
        basla = true;
        continue;
      }
      final e = ekran(p.dx, p.dy);
      basla ? yol.moveTo(e.dx, e.dy) : yol.lineTo(e.dx, e.dy);
      basla = false;
    }
    c.drawPath(
        yol,
        Paint()
          ..color = renk
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
    _yazi(c, yEtiket, Offset(sol + 4, ust + 6));
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
          if (not != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(not, style: const TextStyle(fontSize: 11.5, color: _gri))),
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
    double dk(DateTime t) => t.difference(t0).inMilliseconds / 60000;
    // 5 sn'lik (10 satır) kayan ortalama: tek tek tepeler değil, yolun genel sarsıntısı görünsün
    final s = v.satirlar;
    final hiz = [for (final x in s) Offset(dk(x.t), x.hiz ?? double.nan)];
    final sarsinti = <Offset>[];
    for (var i = 0; i < s.length; i++) {
      final pencere = [for (var j = max(0, i - 5); j < min(s.length, i + 5); j++) if (s[j].hareket) s[j].rms];
      sarsinti.add(Offset(dk(s[i].t), pencere.length < 3 ? double.nan : pencere.reduce((a, b) => a + b) / pencere.length));
    }
    final isaretler = [for (final i in v.isaretler) dk(i.t)];
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _kart(
          'Sarsıntı',
          SizedBox(
            height: 190,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Cizim(noktalar: sarsinti, renk: const Color(0xFF343A40), yEtiket: 'm/s²', isaretler: isaretler, bantlar: true),
            ),
          ),
          not: 'Dikey sarsıntının 5 sn\'lik ortalaması (duruşlar hariç). Arka plan: yeşil düzgün, turuncu orta, kırmızı sarsıntılı.'
              '${isaretler.isEmpty ? '' : ' Lacivert çizgi: çukur işaretiniz.'}',
        ),
        _kart(
          'Hız',
          SizedBox(
            height: 150,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Cizim(noktalar: hiz, renk: const Color(0xFF2F7ED8), yEtiket: 'km/h', isaretler: isaretler),
            ),
          ),
          not: v.test ? 'TEST SÜRÜŞÜ: hız sanaldır.' : null,
        ),
      ],
    );
  }
}

class _PuanSayfasi extends StatelessWidget {
  const _PuanSayfasi(this.v, this.puanla);
  final _Veri v;
  final VoidCallback puanla;

  @override
  Widget build(BuildContext context) {
    if (!v.parcalar.any((p) => p.puan != null)) {
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
    Widget hucre(String s, {bool kalin = false}) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(s, style: TextStyle(fontSize: 13, fontWeight: kalin ? FontWeight.bold : null)));
    Widget etiket(Color renk, String s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Flexible(child: Text(s, style: const TextStyle(fontSize: 13))),
          ]),
        );
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
                      strokeWidth: 8,
                      color: p.puan == null ? const Color(0xFFADB5BD) : _puanRengi(p.puan!),
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.white),
            ]),
          ]),
        ),
        _lejant([for (var p = 1; p <= 5; p++) (_puanRengi(p), '$p ${_puanAdlari[p - 1]}')], not: 'Haritada parçalar verdiğiniz puanın renginde.'),
        _kart(
          'Puanınız ve ölçülen sarsıntı',
          Table(
            columnWidths: const {0: FixedColumnWidth(48), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [hucre('Parça', kalin: true), hucre('Puanınız', kalin: true), hucre('Ölçülen', kalin: true)]),
              for (final p in v.parcalar)
                TableRow(children: [
                  hucre('${p.no}'),
                  p.puan == null ? hucre('-') : etiket(_puanRengi(p.puan!), '${p.puan} ${_puanAdlari[p.puan! - 1]}'),
                  p.rms == null ? hucre('-') : etiket(_Sinif.rms(p.rms!).renk, _Sinif.rms(p.rms!).ad),
                ]),
            ],
          ),
          not: 'Ölçülen: parçadaki ortalama sarsıntı (hız düzeltmesiz). Ayrıntılı karşılaştırma bilgisayardaki analizde.',
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
  const _OzetSayfasi(this.v);
  final _Veri v;

  @override
  Widget build(BuildContext context) {
    final s = v.satirlar;
    if (s.isEmpty) return const Center(child: Text('Kayıtta veri yok'));
    final sure = s.last.t.difference(s.first.t).inSeconds;
    final hareket = s.where((x) => x.hareket).toList();
    final hiz = _medyan([for (final x in hareket) x.hiz!]);
    // Yolun sarsıntı sınıflarına dağılımı (25 m'lik parçalar, uzunlukla ağırlıklı)
    final pay = {for (final k in _Sinif.values) k: 0.0};
    for (final b in v.bolumler) {
      if (b.rms != null) pay[_Sinif.rms(b.rms!)] = pay[_Sinif.rms(b.rms!)]! + b.uzunluk;
    }
    final toplam = pay.values.fold(0.0, (a, b) => a + b);
    final puanli = v.parcalar.where((p) => p.puan != null).length;
    final satirlar = <(String, String)>[
      ('Süre', '${sure ~/ 60} dk ${sure % 60} sn'),
      ('Yol', '~${v.mesafe.round()} m'),
      ('Ortalama hız', hiz == null ? '-' : '${_ondalik(hiz, 0)} km/h'),
      ('Çukur işaretim', '${v.isaretler.length}'),
      ('Puanlanan parça', v.parcalar.isEmpty ? 'puanlanmadı' : '$puanli / ${v.parcalar.length}'),
      for (final a in ['Scooter', 'Hava durumu'])
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
            child: const Text('TEST SÜRÜŞÜ: konum ve hız sanaldır (YTÜ Davutpaşa); sarsıntı gerçek ivmeölçerden.', style: TextStyle(fontSize: 12.5)),
          ),
        if (toplam > 0)
          _kart(
            'Yolun durumu',
            Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Row(children: [
                  for (final k in _Sinif.values)
                    if (pay[k]! > 0) Expanded(flex: (pay[k]! / toplam * 1000).round(), child: Container(height: 18, color: k.renk)),
                ]),
              ),
              const SizedBox(height: 8),
              for (final k in _Sinif.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: k.renk, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(k.ad, style: const TextStyle(fontSize: 13))),
                    Text('%${(pay[k]! / toplam * 100).round()}  (~${pay[k]!.round()} m)', style: const TextStyle(fontSize: 13)),
                  ]),
                ),
            ]),
          ),
        _kart(
          'Özet',
          Table(
            columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.5)},
            children: [
              for (final (a, b) in satirlar)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(a, style: const TextStyle(fontSize: 13, color: _gri))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(b, style: const TextStyle(fontSize: 13))),
                ]),
            ],
          ),
          not: 'Telefondaki önizleme gösterim içindir; asıl analiz bilgisayardaki betiktedir.',
        ),
      ],
    );
  }
}
