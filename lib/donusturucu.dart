import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'gpkg.dart';
import 'ham_kayit.dart';
import 'katmanlar.dart';
import 'kesitler.dart';

// Kayıt bitince ham dosyayı (.kuham) o sürüş gününün GeoPackage dosyalarına ekler:
//   <gün>_ham.gpkg   : güzergâh, GPS noktaları + sarsıntı özeti, ham ivme ve jiroskop (Claude'a gider)
//   <gün>_insan.gpkg : sürücünün çukur işaretleri ve konfor puanı (sürücüde kalır)
// Her adım tekrarlanabilir: uygulama yarıda çökerse aynı ham dosya yeniden çevrilir, çift kayıt oluşmaz.
// Bu dosya Flutter'a bağlı değildir: bilgisayarda test edilir (test/donusturucu_test.dart).

class KayitBilgisi {
  const KayitBilgisi({
    this.cihaz = '',
    this.ivmeSensoru = '',
    this.jiroSensoru = '',
    this.scooter = '',
    this.uygulamaSurumu = '',
    this.hava,
    this.sicaklik,
    this.yagis,
  });
  final String cihaz, ivmeSensoru, jiroSensoru, scooter, uygulamaSurumu;
  final String? hava;
  final double? sicaklik, yagis;

  // Boş (null / '') alanları eski bilgiden doldurur. Kayıt sürerken ekran yeniden kurulursa bellekteki scooter ve hava
  // durumu kaybolur; DURDUR'da yazılan bilgi, BAŞLAT'ta yazılmış olanı boşaltmasın.
  KayitBilgisi eksikleriDoldur(KayitBilgisi eski) {
    String m(String yeni, String e) => yeni.isEmpty ? e : yeni;
    return KayitBilgisi(
      cihaz: m(cihaz, eski.cihaz),
      ivmeSensoru: m(ivmeSensoru, eski.ivmeSensoru),
      jiroSensoru: m(jiroSensoru, eski.jiroSensoru),
      scooter: m(scooter, eski.scooter),
      uygulamaSurumu: m(uygulamaSurumu, eski.uygulamaSurumu),
      hava: (hava == null || hava!.isEmpty) ? eski.hava : hava,
      sicaklik: sicaklik ?? eski.sicaklik,
      yagis: yagis ?? eski.yagis,
    );
  }

  Map<String, Object?> toMap() => {
        'cihaz': cihaz,
        'ivmeSensoru': ivmeSensoru,
        'jiroSensoru': jiroSensoru,
        'scooter': scooter,
        'uygulamaSurumu': uygulamaSurumu,
        'hava': hava,
        'sicaklik': sicaklik,
        'yagis': yagis,
      };

  static KayitBilgisi fromMap(Map<String, Object?> m) => KayitBilgisi(
        cihaz: m['cihaz'] as String? ?? '',
        ivmeSensoru: m['ivmeSensoru'] as String? ?? '',
        jiroSensoru: m['jiroSensoru'] as String? ?? '',
        scooter: m['scooter'] as String? ?? '',
        uygulamaSurumu: m['uygulamaSurumu'] as String? ?? '',
        hava: m['hava'] as String?,
        sicaklik: (m['sicaklik'] as num?)?.toDouble(),
        yagis: (m['yagis'] as num?)?.toDouble(),
      );
}

class DonusumSonucu {
  DonusumSonucu(this.kayitNo, this.kesit, this.kesitAdi, this.yon, this.gecis, this.isaretSayisi, this.sure, this.uzunluk,
      this.gpsNokta, this.ivmeHz, this.guzergah, this.hamYol, this.insanYol, this.yarimKaldi);
  final String kayitNo;
  final String? kesit, kesitAdi;
  final String yon;
  final int gecis, isaretSayisi, gpsNokta;
  final double sure, uzunluk;
  final double? ivmeHz;
  final List<(double, double)> guzergah; // (enlem, boylam)
  final String hamYol, insanYol;
  final bool yarimKaldi;

  Map<String, Object?> toMap() => {
        'kayitNo': kayitNo,
        'kesit': kesit,
        'kesitAdi': kesitAdi,
        'yon': yon,
        'gecis': gecis,
        'isaretSayisi': isaretSayisi,
        'sure': sure,
        'uzunluk': uzunluk,
        'gpsNokta': gpsNokta,
        'ivmeHz': ivmeHz,
        'guzergah': [for (final (a, b) in guzergah) [a, b]],
        'hamYol': hamYol,
        'insanYol': insanYol,
        'yarimKaldi': yarimKaldi,
      };

  static DonusumSonucu fromMap(Map<String, Object?> m) => DonusumSonucu(
        m['kayitNo'] as String,
        m['kesit'] as String?,
        m['kesitAdi'] as String?,
        m['yon'] as String,
        m['gecis'] as int,
        m['isaretSayisi'] as int,
        (m['sure'] as num).toDouble(),
        (m['uzunluk'] as num).toDouble(),
        m['gpsNokta'] as int,
        (m['ivmeHz'] as num?)?.toDouble(),
        [for (final p in m['guzergah'] as List) ((p[0] as num).toDouble(), (p[1] as num).toDouble())],
        m['hamYol'] as String,
        m['insanYol'] as String,
        m['yarimKaldi'] as bool,
      );
}

String _iki(int v) => v.toString().padLeft(2, '0');
String kayitNoFor(DateTime yerel) =>
    '${yerel.year}${_iki(yerel.month)}${_iki(yerel.day)}_${_iki(yerel.hour)}${_iki(yerel.minute)}${_iki(yerel.second)}';
String _gun(DateTime yerel) => '${yerel.year}${_iki(yerel.month)}${_iki(yerel.day)}';
String yerelYazim(DateTime t, {bool ms = true}) {
  final y = t.toLocal();
  final s = '${y.year}-${_iki(y.month)}-${_iki(y.day)} ${_iki(y.hour)}:${_iki(y.minute)}:${_iki(y.second)}';
  return ms ? '$s.${y.millisecond.toString().padLeft(3, '0')}' : s;
}

// Sürüş gününün dosyaları: (mikromobilite | test_mikromobilite)_YYYYMMDD_(ham | insan).gpkg
String gunDosyasi(String klasor, DateTime yerel, String tur, {required bool test}) =>
    gunDosyasiYolu(klasor, _gun(yerel), tur, test: test);
String gunDosyasiYolu(String klasor, String gun, String tur, {required bool test}) =>
    '$klasor/${test ? 'test_' : ''}mikromobilite_${gun}_$tur.gpkg';

double? _r(double? v, int basamak) {
  if (v == null || v.isNaN || v.isInfinite) return null;
  final p = pow(10, basamak);
  return (v * p).round() / p;
}

// Doğrulukları 50 m'den kötü olmayan konumlar (kesit ve uzunluk hesabında)
bool _iyi(GpsKonumu k) => k.dogruluk.isNaN || k.dogruluk <= 50;

// GPS noktası, uç hesabı için: (t_s, enlem, boylam, doğruluk m; bilinmiyorsa NaN)
typedef UcNoktasi = (double, double, double, double);

(double, double)? _ortanca(List<UcNoktasi> l) {
  if (l.isEmpty) return null;
  final e = [for (final k in l) k.$2]..sort();
  final b = [for (final k in l) k.$3]..sort();
  return (e[e.length ~/ 2], b[b.length ~/ 2]);
}

// Kaydın başlangıç ve bitiş noktası: ilk / son GPS konumundan sonraki / önceki 5 sn'deki konumların ortancası
// (sürücü kesitin başında ve sonunda ~5 sn bekler). noktalar zamana göre sıralı.
((double, double)?, (double, double)?) uclarNoktalardan(List<UcNoktasi> noktalar) {
  final iyi = noktalar.where((k) => k.$4.isNaN || k.$4 <= 50).toList();
  if (iyi.isEmpty) return (null, null);
  final t0 = iyi.first.$1, t1 = iyi.last.$1;
  return (_ortanca(iyi.where((k) => k.$1 <= t0 + 5).toList()), _ortanca(iyi.where((k) => k.$1 >= t1 - 5).toList()));
}

((double, double)?, (double, double)?) uclar(List<GpsKonumu> konumlar) =>
    uclarNoktalardan([for (final g in konumlar) (g.t, g.enlem, g.boylam, g.dogruluk)]);

// GeoPackage nokta geometrisinden (enlem, boylam)
(double, double)? _noktaOku(Object? blob) {
  if (blob is! Uint8List || blob.length < 29) return null;
  final b = ByteData.sublistView(blob);
  final zarf = (b.getUint8(3) >> 1) & 7;
  final o = 8 + (zarf == 1 ? 32 : 0) + 5;
  return (b.getFloat64(o + 8, Endian.little), b.getFloat64(o, Endian.little));
}

// 2.1'den önceki kesit defterinde kayıtların kendi uçları yoktu: gün dosyasındaki GPS noktalarından, kaydın
// çevrildiği kuralla (uclar) bulunur. Gün dosyası veya noktaları yoksa kayıt bilinmeyen kalır (referansa katılmaz).
void _ucBilgisiniTamamla(KesitDefteri defter, String klasor, {required bool test}) {
  final eksik = defter.ucuBilinmeyenler();
  if (eksik.isEmpty) return;
  final acik = <String, GeoPackage?>{};
  try {
    for (final (kesit, kayitNo) in eksik) {
      if (kayitNo.length < 8) continue;
      final yol = gunDosyasiYolu(klasor, kayitNo.substring(0, 8), 'ham', test: test);
      final gp = acik.putIfAbsent(yol, () => File(yol).existsSync() ? GeoPackage.ac(yol) : null);
      if (gp == null || !gp.katmanVar('gps_noktalari')) continue;
      final noktalar = <UcNoktasi>[];
      for (final r in gp.db.select('SELECT t_s, dogruluk_m, geom FROM gps_noktalari WHERE kayit_no = ? ORDER BY t_s', [kayitNo])) {
        final p = _noktaOku(r['geom']);
        if (p == null) continue;
        noktalar.add(((r['t_s'] as num?)?.toDouble() ?? 0, p.$1, p.$2, (r['dogruluk_m'] as num?)?.toDouble() ?? double.nan));
      }
      final (b0, b1) = uclarNoktalardan(noktalar);
      if (b0 != null && b1 != null) kesit.ucEkle(kayitNo, b0, b1);
    }
  } finally {
    for (final gp in acik.values) {
      gp?.kapat();
    }
  }
}

// GPS konumunu t anına doğrusal ara değerle bulur (enlem, boylam, hız km/h)
(double, double, double?)? konumAt(List<GpsKonumu> l, double t) {
  if (l.isEmpty) return null;
  if (t <= l.first.t) return (l.first.enlem, l.first.boylam, l.first.hizKmh);
  for (var i = 1; i < l.length; i++) {
    if (t <= l[i].t) {
      final a = l[i - 1], b = l[i];
      final f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0.0;
      final ha = a.hizKmh, hb = b.hizKmh;
      return (
        a.enlem + f * (b.enlem - a.enlem),
        a.boylam + f * (b.boylam - a.boylam),
        ha == null || hb == null ? (ha ?? hb) : ha + f * (hb - ha),
      );
    }
  }
  return (l.last.enlem, l.last.boylam, l.last.hizKmh);
}

bool _kayitVar(GeoPackage gp, String katman, String kayitNo) =>
    gp.katmanVar(katman) && gp.db.select('SELECT 1 FROM "$katman" WHERE kayit_no = ? LIMIT 1', [kayitNo]).isNotEmpty;

void _aciklamalar(GeoPackage gp, List<List<String>> satirlar, DateTime simdi) {
  if (gp.katman(aciklamaKatmani, simdi)) gp.ekle(aciklamaKatmani, satirlar, simdi);
}

// Ham dosyayı çevirir. klasor: kayıt klasörü (gün dosyaları ve kesit defteri burada). stiller: katman adı -> QML.
DonusumSonucu donustur({
  required String hamDosya,
  required String klasor,
  required KayitBilgisi bilgi,
  Map<String, String> stiller = const {},
  DateTime? simdi,
}) {
  final now = simdi ?? DateTime.now();
  final k = HamKayit.oku(File(hamDosya).readAsBytesSync());
  final test = k.sanal;
  final bas = k.baslangic;
  final kayitNo = kayitNoFor(bas);
  final hamYol = gunDosyasi(klasor, bas, 'ham', test: test);
  final insanYol = gunDosyasi(klasor, bas, 'insan', test: test);
  DateTime an(double t) => bas.add(Duration(microseconds: (t * 1e6).round()));

  // 1) Kesit ataması (defter önce kaydedilir; tekrar çevirmede aynı atama döner)
  final defter = KesitDefteri.yukle(klasor, test: test);
  _ucBilgisiniTamamla(defter, klasor, test: test);
  final (b0, b1) = uclar(k.konumlar);
  final atama = defter.ata(kayitNo, b0, b1);
  defter.kaydet();
  final kesit = atama?.kesit.kod;
  final kesitAdi = atama?.kesit.ad;
  final yon = atama?.yon ?? 'gidis';

  // Güzergâh ve özetler
  final konumlar = k.konumlar;
  final guzergah = [for (final g in konumlar) (g.boylam, g.enlem)];
  final cizgiGeo = guzergah.length >= 2 ? cizgi(guzergah) : null;
  var uzunluk = 0.0;
  final hizlar = <double>[];
  for (var i = 0; i < konumlar.length; i++) {
    final h = konumlar[i].hizKmh;
    if (h != null && h >= 3) hizlar.add(h);
    if (i > 0) {
      final a = konumlar[i - 1], b = konumlar[i];
      if ((a.hizKmh ?? 0) >= 3 && (b.hizKmh ?? 0) >= 3 && _iyi(a) && _iyi(b)) {
        uzunluk += mesafeM(a.enlem, a.boylam, b.enlem, b.boylam);
      }
    }
  }
  final ortHiz = hizlar.isEmpty ? null : hizlar.reduce((a, b) => a + b) / hizlar.length;
  final isaretSayisi = k.isaretler.length;

  // 2) Ham dosya
  final ham = GeoPackage.ac(hamYol);
  try {
    if (!_kayitVar(ham, 'kayitlar', kayitNo)) {
      ham.islem(() {
        for (final kt in [kayitlarKatmani, gpsKatmani, ivmeKatmani, jiroKatmani]) {
          ham.katman(kt, now);
        }
        _aciklamalar(ham, hamAciklamalari(test: test), now);
        ham.ekle(kayitlarKatmani, [
          [
            cizgiGeo, kayitNo, kesit, kesitAdi, yon, yerelYazim(bas, ms: false),
            _r(k.sure, 1), _r(uzunluk, 1), _r(ortHiz, 1), konumlar.length, _r(k.ivme.hiz, 1), _r(k.jiro.hiz, 1),
            bilgi.cihaz, bilgi.ivmeSensoru, bilgi.jiroSensoru, bilgi.scooter, bilgi.hava, bilgi.sicaklik, bilgi.yagis,
            test ? 'test_surusu' : 'telefon', bilgi.uygulamaSurumu,
          ]
        ], now);

        // Sarsıntı özeti: önceki GPS konumundan bu konuma kadarki ivme örnekleri
        final dikey = dikeySarsinti(k.ivme);
        final satirlar = <List<Object?>>[];
        var j = 0;
        var onceki = double.negativeInfinity;
        for (final g in konumlar) {
          var kare = 0.0, tepe = 0.0, n = 0;
          while (j < dikey.length && k.ivme.t[j] <= g.t) {
            if (k.ivme.t[j] > onceki) {
              final v = dikey[j];
              kare += v * v;
              tepe = max(tepe, v.abs());
              n++;
            }
            j++;
          }
          onceki = g.t;
          satirlar.add([
            nokta(g.boylam, g.enlem), kayitNo, kesit, _r(g.t, 4), yerelYazim(an(g.t)), _r(g.hizKmh, 2),
            _r(g.yon, 1), _r(g.dogruluk, 1), g.uydu < 0 ? null : g.uydu, n > 0 ? _r(sqrt(kare / n), 3) : null,
            n > 0 ? _r(tepe, 2) : null, n,
          ]);
        }
        ham.ekle(gpsKatmani, satirlar, now);
        for (final (kt, s) in [(ivmeKatmani, k.ivme), (jiroKatmani, k.jiro)]) {
          ham.ekle(kt, [for (var i = 0; i < s.sayi; i++) [kayitNo, _r(s.t[i], 4), _r(s.x[i], 4), _r(s.y[i], 4), _r(s.z[i], 4)]],
              now);
        }
        ham.stiller(stiller, stilNotu, now);
      });
    }
  } finally {
    ham.kapat();
  }

  // 3) İnsan dosyası: işaretler ve (henüz verilmemiş) puan satırı
  final insan = GeoPackage.ac(insanYol);
  try {
    if (!_kayitVar(insan, 'insan_puanlar', kayitNo)) {
      insan.islem(() {
        insan.katman(insanCukurKatmani, now);
        insan.katman(insanPuanKatmani, now);
        _aciklamalar(insan, insanAciklamalari(test: test), now);
        insan.ekle(insanCukurKatmani, [
          for (final m in k.isaretler)
            [
              switch (konumAt(konumlar, m.t)) { final p? => nokta(p.$2, p.$1), null => null },
              kayitNo, kesit, _r(m.t, 4), yerelYazim(an(m.t)), _r(konumAt(konumlar, m.t)?.$3, 2), m.kaynak,
            ]
        ], now);
        insan.ekle(insanPuanKatmani, [
          [cizgiGeo, kayitNo, kesit, kesitAdi, null, 'puanlanmadi', null, isaretSayisi]
        ], now);
        insan.stiller(stiller, stilNotu, now);
      });
    }
  } finally {
    insan.kapat();
  }

  return DonusumSonucu(kayitNo, kesit, kesitAdi, yon, atama?.gecis ?? 1, isaretSayisi, k.sure, uzunluk, konumlar.length,
      k.ivme.hiz, [for (final g in konumlar) (g.enlem, g.boylam)], hamYol, insanYol, k.yarimKaldi || !k.tamamlandi);
}

// Konfor puanını yazar. puan null = "Hatırlamıyorum".
void puanYaz(String insanYol, String kayitNo, int? puan, {DateTime? simdi}) {
  final gp = GeoPackage.ac(insanYol);
  try {
    gp.alanlariTamamla(insanPuanKatmani); // 2.0'ın yazdığı dosyada puanlama_yerel alanı yoktur
    gp.db.execute('UPDATE insan_puanlar SET puan = ?, durum = ?, puanlama_yerel = ? WHERE kayit_no = ?',
        [puan, puan == null ? 'hatirlamiyorum' : 'puanlandi', yerelYazim(simdi ?? DateTime.now(), ms: false), kayitNo]);
  } finally {
    gp.kapat();
  }
}

// Kesit adını defterde ve klasördeki bütün gün dosyalarında değiştirir.
void kesitAdiVer(String klasor, String kod, String? ad, {required bool test}) {
  final temiz = (ad == null || ad.trim().isEmpty) ? null : ad.trim();
  final defter = KesitDefteri.yukle(klasor, test: test);
  final k = defter.kod(kod);
  if (k == null) return;
  k.ad = temiz;
  defter.kaydet();
  for (final f in gunDosyalari(klasor, test: test)) {
    final gp = GeoPackage.ac(f.path);
    try {
      for (final katman in ['kayitlar', 'insan_puanlar']) {
        if (gp.katmanVar(katman)) gp.db.execute('UPDATE "$katman" SET kesit_adi = ? WHERE kesit = ?', [temiz, kod]);
      }
    } finally {
      gp.kapat();
    }
  }
}

// Kaydı gün dosyalarından ve kesit defterinden siler. Gün dosyasında kayıt kalmazsa dosyalar silinir.
void kayitSil(String hamYol, String insanYol, String kayitNo, String klasor, {required bool test}) {
  // Kesitin referansı kalan kayıtlardan yeniden hesaplanacak: eski defterdeki uçlar, satırlar silinmeden tamamlanır
  final defter = KesitDefteri.yukle(klasor, test: test);
  _ucBilgisiniTamamla(defter, klasor, test: test);
  for (final (yol, katmanlar) in [
    (hamYol, ['kayitlar', 'gps_noktalari', 'ivme', 'jiroskop']),
    (insanYol, ['insan_cukurlar', 'insan_puanlar']),
  ]) {
    if (!File(yol).existsSync()) continue;
    final gp = GeoPackage.ac(yol);
    try {
      gp.islem(() {
        for (final katman in katmanlar) {
          if (gp.katmanVar(katman)) gp.db.execute('DELETE FROM "$katman" WHERE kayit_no = ?', [kayitNo]);
        }
      });
    } finally {
      gp.kapat();
    }
  }
  defter.kayitSil(kayitNo);
  defter.kaydet();
  // Gün boşaldıysa dosyaları sil
  if (File(hamYol).existsSync()) {
    final gp = GeoPackage.ac(hamYol);
    final bos = !gp.katmanVar('kayitlar') || gp.db.select('SELECT 1 FROM kayitlar LIMIT 1').isEmpty;
    gp.kapat();
    if (bos) {
      for (final y in [hamYol, insanYol]) {
        if (File(y).existsSync()) File(y).deleteSync();
      }
    }
  }
}

// Klasördeki gün dosyaları (ham ve insan)
List<File> gunDosyalari(String klasor, {required bool test}) {
  final d = Directory(klasor);
  if (!d.existsSync()) return [];
  final onek = test ? 'test_mikromobilite_' : 'mikromobilite_';
  return d
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith(onek) && f.path.endsWith('.gpkg'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path));
}

// Kayıtlar sayfası için bir kaydın özeti
class KayitOzeti {
  KayitOzeti(this.kayitNo, this.kesit, this.kesitAdi, this.yon, this.baslangicYerel, this.sure, this.uzunluk, this.puan,
      this.durum, this.isaretSayisi, this.hamYol, this.insanYol, this.test);
  final String kayitNo;
  final String? kesit, kesitAdi;
  final String yon, baslangicYerel;
  final double sure, uzunluk;
  final int? puan;
  final String durum;
  final int isaretSayisi;
  final String hamYol, insanYol;
  final bool test;
}

List<KayitOzeti> kayitlariListele(String klasor) {
  final sonuc = <KayitOzeti>[];
  for (final test in [false, true]) {
    for (final f in gunDosyalari(klasor, test: test).where((f) => f.path.endsWith('_ham.gpkg'))) {
      final insanYol = f.path.replaceAll(RegExp(r'_ham\.gpkg$'), '_insan.gpkg');
      final puanlar = <String, (int?, String, int)>{};
      if (File(insanYol).existsSync()) {
        final gi = GeoPackage.ac(insanYol);
        try {
          if (gi.katmanVar('insan_puanlar')) {
            for (final r in gi.db.select('SELECT kayit_no, puan, durum, isaret_sayisi FROM insan_puanlar')) {
              puanlar[r['kayit_no'] as String] = (r['puan'] as int?, r['durum'] as String? ?? '', r['isaret_sayisi'] as int? ?? 0);
            }
          }
        } finally {
          gi.kapat();
        }
      }
      final gh = GeoPackage.ac(f.path);
      try {
        if (!gh.katmanVar('kayitlar')) continue;
        for (final r in gh.db.select('SELECT kayit_no, kesit, kesit_adi, yon, baslangic_yerel, sure_s, uzunluk_m FROM kayitlar')) {
          final no = r['kayit_no'] as String;
          final p = puanlar[no];
          sonuc.add(KayitOzeti(no, r['kesit'] as String?, r['kesit_adi'] as String?, r['yon'] as String? ?? '',
              r['baslangic_yerel'] as String? ?? '', (r['sure_s'] as num?)?.toDouble() ?? 0, (r['uzunluk_m'] as num?)?.toDouble() ?? 0,
              p?.$1, p?.$2 ?? 'puanlanmadi', p?.$3 ?? 0, f.path, insanYol, test));
        }
      } finally {
        gh.kapat();
      }
    }
  }
  sonuc.sort((a, b) => b.kayitNo.compareTo(a.kayitNo));
  return sonuc;
}

// Bir kaydın güzergâhı ve işaretleri (harita için): ham dosyadaki GPS noktaları, insan dosyasındaki işaretler
(List<(double, double)>, List<(double, double)>) haritaVerisi(String hamYol, String insanYol, String kayitNo) {
  const noktaOku = _noktaOku;
  final rota = <(double, double)>[];
  final isaretler = <(double, double)>[];
  final gh = GeoPackage.ac(hamYol);
  try {
    for (final r in gh.db.select('SELECT geom FROM gps_noktalari WHERE kayit_no = ? ORDER BY t_s', [kayitNo])) {
      final p = noktaOku(r['geom']);
      if (p != null) rota.add(p);
    }
  } finally {
    gh.kapat();
  }
  if (File(insanYol).existsSync()) {
    final gi = GeoPackage.ac(insanYol);
    try {
      if (gi.katmanVar('insan_cukurlar')) {
        for (final r in gi.db.select('SELECT geom FROM insan_cukurlar WHERE kayit_no = ?', [kayitNo])) {
          final p = noktaOku(r['geom']);
          if (p != null) isaretler.add(p);
        }
      }
    } finally {
      gi.kapat();
    }
  }
  return (rota, isaretler);
}
