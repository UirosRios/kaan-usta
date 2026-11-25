import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaan_usta/donusturucu.dart';
import 'package:kaan_usta/gpkg.dart';
import 'package:kaan_usta/ham_kayit.dart';
import 'package:kaan_usta/kesitler.dart';

// Telefonun yazdığı ham dosyayı (KayitMotoru.kt biçiminde) yapay olarak üretip GeoPackage'a çevirir.
// KAAN_TEST_CIKTI ortam değişkeni verilirse üretilen dosyalar o klasöre kopyalanır (qgis/sema_karsilastir.py ile denetim).

class _Yazici {
  final BytesBuilder b = BytesBuilder();
  void bayt(int v) => b.addByte(v);
  void long(int v) => b.add((ByteData(8)..setInt64(0, v)).buffer.asUint8List());
  void f32(double v) => b.add((ByteData(4)..setFloat32(0, v)).buffer.asUint8List());
  void f64(double v) => b.add((ByteData(8)..setFloat64(0, v)).buffer.asUint8List());
  void i16(int v) => b.add((ByteData(2)..setInt16(0, v)).buffer.asUint8List());
  void tur(String c) => bayt(c.codeUnitAt(0));
}

// Düz bir yolda kayıt: başta ve sonda 5 sn duruş, arada sabit hızla A'dan B'ye. Çukur 12. saniyede, basış 13,3'te.
Uint8List yapayKayit({
  required DateTime baslangic,
  required (double, double) a,
  required (double, double) b,
  double hareket = 20,
  bool sanal = false,
  int sensorSaatFarkiNs = 0,
  bool bitir = true,
}) {
  final y = _Yazici();
  final t0 = 5000000000000; // elapsedRealtimeNanos
  y.b.add('KUHAM1'.codeUnits);
  y.tur('S');
  y.long(t0);
  y.long(baslangic.millisecondsSinceEpoch);
  y.bayt(sanal ? 1 : 0);
  final sure = hareket + 10;
  final rnd = Random(1);
  int ns(double t) => t0 + (t * 1e9).round();
  var sonT = -1.0;
  for (var i = 0; i * 0.005 < sure; i++) {
    final t = i * 0.005;
    final hareketli = t > 5 && t < 5 + hareket;
    var dikey = hareketli ? rnd.nextDouble() * 4 - 2 : 0.0;
    if ((t - 12).abs() < 0.04) dikey += 30 * sin((t - 12) * 2 * pi * 11);
    y.tur('A');
    y.long(ns(t) - sensorSaatFarkiNs);
    y.f32(0.1);
    y.f32(5.6 + dikey * 0.57);
    y.f32(8.0 + dikey * 0.82);
    y.tur('G');
    y.long(ns(t + 0.001) - sensorSaatFarkiNs);
    y.f32(0.01);
    y.f32(0.0);
    y.f32(0.002);
    if (t.floor() > sonT) {
      sonT = t.floor().toDouble();
      // saat eşi ve GPS (saniyede bir)
      y.tur('T');
      y.long(ns(t) + 2000000);
      y.long(ns(t) - sensorSaatFarkiNs);
      y.long(ns(t) + 1000000);
      final f = ((t - 5) / hareket).clamp(0.0, 1.0);
      y.tur('L');
      y.long(ns(t + 0.3));
      y.f64(a.$1 + f * (b.$1 - a.$1));
      y.f64(a.$2 + f * (b.$2 - a.$2));
      y.f64(70);
      y.f32(hareketli ? 4.5 : 0.1);
      y.f32(hareketli ? 135 : double.nan);
      y.f32(4);
      y.f32(0.3);
      y.f32(6);
      y.i16(hareketli ? 12 : -1);
      y.long(baslangic.millisecondsSinceEpoch + (t * 1000).round());
      y.bayt(sanal ? 1 : 0);
    }
    if ((t - 13.3).abs() < 0.0025) {
      y.tur('M');
      y.long(ns(t));
      y.bayt(4);
    }
  }
  if (bitir) {
    y.tur('E');
    y.long(ns(sure));
  }
  return y.b.toBytes();
}

void main() {
  late Directory klasor;
  setUp(() => klasor = Directory.systemTemp.createTempSync('kaan_usta_test'));
  tearDown(() {
    final hedef = Platform.environment['KAAN_TEST_CIKTI'];
    if (hedef != null) {
      Directory(hedef).createSync(recursive: true);
      for (final f in klasor.listSync().whereType<File>()) {
        f.copySync('$hedef/${f.uri.pathSegments.last}');
      }
    }
    klasor.deleteSync(recursive: true);
  });

  const a = (41.027878, 28.889648), b = (41.026281, 28.888188); // YTÜ Davutpaşa, ~215 m
  // Uygulamanın gömdüğü QGIS stilleri (pubspec assets: qgis/stiller/)
  final stiller = {
    for (final f in Directory('qgis/stiller').listSync().whereType<File>().where((f) => f.path.endsWith('.qml')))
      f.uri.pathSegments.last.replaceAll('.qml', ''): f.readAsStringSync(),
  };
  final gun = DateTime(2026, 11, 25, 10, 15, 2);

  String hamYaz(String ad, Uint8List v) {
    final f = File('${klasor.path}/ham_gecici/$ad.kuham')..createSync(recursive: true);
    f.writeAsBytesSync(v);
    return f.path;
  }

  test('ham dosya okunur, zamanlar kayıt başına göre', () {
    final k = HamKayit.oku(yapayKayit(baslangic: gun, a: a, b: b));
    expect(k.tamamlandi, isTrue);
    expect(k.ivme.sayi, 6000);
    expect(k.ivme.hiz!, closeTo(200, 0.5));
    expect(k.jiro.sayi, 6000);
    expect(k.konumlar.length, 30);
    expect(k.konumlar.first.t, closeTo(0.3, 1e-6));
    expect(k.konumlar[10].uydu, 12);
    expect(k.isaretler.single.kaynak, 'kulaklik');
    expect(k.isaretler.single.t, closeTo(13.3, 0.003));
    expect(k.sure, closeTo(30, 1e-6));
    expect(k.sensorSaatDuzeltmesi, 0);
  });

  test('sensör saati başka saate göreyse düzeltilir', () {
    final k = HamKayit.oku(yapayKayit(baslangic: gun, a: a, b: b, sensorSaatFarkiNs: 3600000000000));
    expect(k.sensorSaatDuzeltmesi, closeTo(3600, 0.01));
    expect(k.ivme.t.first, closeTo(0.001, 0.002));
  });

  test('yarım kalan dosya okunabildiği kadar okunur', () {
    final tam = yapayKayit(baslangic: gun, a: a, b: b, bitir: false);
    final k = HamKayit.oku(Uint8List.sublistView(tam, 0, tam.length - 7));
    expect(k.tamamlandi, isFalse);
    expect(k.yarimKaldi, isTrue);
    expect(k.ivme.sayi, greaterThan(5900));
    expect(k.ivme.x.length, k.ivme.t.length);
  });

  test('çeviri: katmanlar, kesit, işaret, puan, ad, silme', () {
    final y1 = hamYaz('1', yapayKayit(baslangic: gun, a: a, b: b));
    final s1 = donustur(hamDosya: y1, klasor: klasor.path, bilgi: const KayitBilgisi(cihaz: 'Deneme'), stiller: stiller);
    expect(s1.kayitNo, '20261125_101502');
    expect(s1.kesit, 'K01');
    expect(s1.yon, 'gidis');
    expect(s1.isaretSayisi, 1);
    expect(s1.uzunluk, greaterThan(150));
    expect(File(s1.hamYol).uri.pathSegments.last, 'mikromobilite_20261125_ham.gpkg');

    // Aynı dosya yeniden çevrilince çift kayıt olmaz
    donustur(hamDosya: y1, klasor: klasor.path, bilgi: const KayitBilgisi());
    final gp = GeoPackage.ac(s1.hamYol);
    expect(gp.db.select('SELECT count(*) AS n FROM kayitlar').first['n'], 1);
    expect(gp.db.select('SELECT count(*) AS n FROM ivme').first['n'], 6000);
    expect(gp.db.select('SELECT count(*) AS n FROM gps_noktalari').first['n'], 30);
    final r = gp.db.select('SELECT dikey_tepe, ivme_ornek FROM gps_noktalari WHERE t_s > 12 ORDER BY t_s LIMIT 1').first;
    expect((r['dikey_tepe'] as num).toDouble(), greaterThan(15)); // çukur darbesi özette görünür
    expect(r['ivme_ornek'], 200);
    expect(gp.db.select("SELECT count(*) AS n FROM layer_styles").first['n'], 2); // kayitlar, gps_noktalari
    gp.kapat();

    // Ters yönde aynı kesit: dönüş, 2. geçiş
    final y2 = hamYaz('2', yapayKayit(baslangic: gun.add(const Duration(minutes: 3)), a: b, b: a));
    final s2 = donustur(hamDosya: y2, klasor: klasor.path, bilgi: const KayitBilgisi());
    expect((s2.kesit, s2.yon, s2.gecis), ('K01', 'donus', 2));

    // Uzak bir yol: yeni kesit
    final y3 = hamYaz('3', yapayKayit(baslangic: gun.add(const Duration(minutes: 6)), a: (41.0245, 28.8877), b: (41.0225, 28.8911)));
    expect(donustur(hamDosya: y3, klasor: klasor.path, bilgi: const KayitBilgisi()).kesit, 'K02');

    // Puan, kesit adı
    puanYaz(s1.insanYol, s1.kayitNo, 4);
    puanYaz(s1.insanYol, s2.kayitNo, null);
    kesitAdiVer(klasor.path, 'K01', 'Kuzey yolu', test: false);
    final liste = kayitlariListele(klasor.path);
    expect(liste.length, 3);
    final l1 = liste.firstWhere((o) => o.kayitNo == s1.kayitNo);
    expect((l1.puan, l1.durum, l1.kesitAdi, l1.isaretSayisi), (4, 'puanlandi', 'Kuzey yolu', 1));
    expect(liste.firstWhere((o) => o.kayitNo == s2.kayitNo).durum, 'hatirlamiyorum');
    expect(liste.firstWhere((o) => o.kesit == 'K02').durum, 'puanlanmadi');

    // Sonraki kayıt kesit adını alır
    final y4 = hamYaz('4', yapayKayit(baslangic: gun.add(const Duration(minutes: 9)), a: a, b: b));
    expect(donustur(hamDosya: y4, klasor: klasor.path, bilgi: const KayitBilgisi()).kesitAdi, 'Kuzey yolu');

    final (rota, isaretler) = haritaVerisi(s1.hamYol, s1.insanYol, s1.kayitNo);
    expect(rota.length, 30);
    expect(rota.first.$1, closeTo(a.$1, 1e-6)); // (enlem, boylam)
    expect(isaretler.length, 1);

    // Silme
    kayitSil(s1.hamYol, s1.insanYol, s2.kayitNo, klasor.path, test: false);
    expect(kayitlariListele(klasor.path).length, 3);
    expect(KesitDefteri.yukle(klasor.path, test: false).kod('K01')!.kayitlar.containsKey(s2.kayitNo), isFalse);
  });

  test('2.0 biçimindeki gün dosyasına yeni kayıt eklenir, puan yazılır', () {
    // 2.0 insan dosyası: puanlama_zamani (UTC) vardı, puanlama_yerel yoktu
    const eskiPuan = Katman('insan_puanlar', 'LINESTRING', [
      ('kayit_no', 'TEXT'), ('kesit', 'TEXT'), ('kesit_adi', 'TEXT'), ('puan', 'INTEGER'), ('durum', 'TEXT'),
      ('puanlama_zamani', 'DATETIME'), ('isaret_sayisi', 'INTEGER'),
    ], '');
    const eskiCukur = Katman('insan_cukurlar', 'POINT', [
      ('kayit_no', 'TEXT'), ('kesit', 'TEXT'), ('t_s', 'REAL'), ('zaman', 'DATETIME'), ('yerel_saat', 'TEXT'),
      ('hiz_kmh', 'REAL'), ('kaynak', 'TEXT'),
    ], '');
    final yol = gunDosyasi(klasor.path, gun, 'insan', test: false);
    final eski = GeoPackage.ac(yol);
    eski.katman(eskiPuan, gun);
    eski.katman(eskiCukur, gun);
    eski.ekle(eskiPuan, [[null, '20261125_080000', 'K09', null, null, 'puanlanmadi', null, 0]], gun);
    eski.kapat();

    final s = donustur(hamDosya: hamYaz('y', yapayKayit(baslangic: gun, a: a, b: b)), klasor: klasor.path,
        bilgi: const KayitBilgisi(), stiller: stiller);
    expect(s.insanYol, yol);
    puanYaz(yol, s.kayitNo, 4, simdi: DateTime(2026, 11, 25, 10, 16, 0));
    puanYaz(yol, '20261125_080000', 2);
    final gp = GeoPackage.ac(yol);
    final r = gp.db.select('SELECT puan, puanlama_yerel FROM insan_puanlar WHERE kayit_no = ?', [s.kayitNo]).single;
    expect((r['puan'], r['puanlama_yerel']), (4, '2026-11-25 10:16:00'));
    expect(gp.db.select("SELECT puan FROM insan_puanlar WHERE kayit_no = '20261125_080000'").single['puan'], 2);
    expect(gp.db.select('SELECT count(*) AS n FROM insan_cukurlar').single['n'], 1);
    gp.kapat();
  });

  test('2.1 öncesi kesit defteri: uçlar gün dosyasından tamamlanır, silinen ilk kayıt referanstan çıkar', () {
    final kuzey = (a.$1 + 25 / 111195, a.$2); // ilk geçiş 25 m erken başlamış
    final s1 = donustur(hamDosya: hamYaz('1', yapayKayit(baslangic: gun, a: kuzey, b: b)), klasor: klasor.path,
        bilgi: const KayitBilgisi());
    final s2 = donustur(hamDosya: hamYaz('2', yapayKayit(baslangic: gun.add(const Duration(minutes: 3)), a: a, b: b)),
        klasor: klasor.path, bilgi: const KayitBilgisi());
    expect((s1.kesit, s2.kesit), ('K01', 'K01'));

    // 2.0 defteri: uç listesi yok, referans ilk kaydın uçları; gün dosyası olmayan bir kayıt da var
    final defter = KesitDefteri.yukle(klasor.path, test: false);
    final k = defter.kod('K01')!;
    final ilk = k.uclar[s1.kayitNo]!;
    final eski = KesitDefteri(defter.dosya, [
      Kesit('K01', null, ilk[0], ilk[1], ilk[2], ilk[3], {...k.kayitlar, '20261120_090000': 'gidis'}),
    ])..kaydet();
    expect(eski.ucuBilinmeyenler().length, 3);

    kayitSil(s1.hamYol, s1.insanYol, s1.kayitNo, klasor.path, test: false);
    final sonra = KesitDefteri.yukle(klasor.path, test: false).kod('K01')!;
    expect(sonra.uclar.keys, [s2.kayitNo]); // gün dosyası olmayan kayıt bilinmeyen kalır
    expect(sonra.kayitlar.keys, [s2.kayitNo, '20261120_090000']);
    expect(mesafeM(a.$1, a.$2, sonra.basEnlem, sonra.basBoylam), lessThan(1));

    // Eski referanstan 53 m, kalan geçişten 28 m uzakta başlayan geçiş aynı kesit
    final guney = (a.$1 - 28 / 111195, a.$2);
    final s3 = donustur(hamDosya: hamYaz('3', yapayKayit(baslangic: gun.add(const Duration(minutes: 6)), a: guney, b: b)),
        klasor: klasor.path, bilgi: const KayitBilgisi());
    expect(s3.kesit, 'K01');
  });

  test('2.1 öncesi defterde eski günün dosyası bozuksa yeni kayıt yine çevrilir', () {
    // Eski günün kaydı K01'de, uçları yok; o günün ham dosyası bozuk
    KesitDefteri(KesitDefteri.dosyaFor(klasor.path, test: false), [
      Kesit('K01', null, a.$1, a.$2, b.$1, b.$2, {'20261120_090000': 'gidis'}),
    ]).kaydet();
    final bozuk = File(gunDosyasiYolu(klasor.path, '20261120', 'ham', test: false))
      ..writeAsBytesSync(List.filled(4096, 7));
    final s = donustur(hamDosya: hamYaz('1', yapayKayit(baslangic: gun, a: a, b: b)), klasor: klasor.path,
        bilgi: const KayitBilgisi());
    expect((s.kesit, s.gecis), ('K01', 2));
    final d = KesitDefteri.yukle(klasor.path, test: false);
    expect([for (final (_, no) in d.ucuBilinmeyenler()) no], ['20261120_090000']);
    expect(bozuk.readAsBytesSync(), List.filled(4096, 7)); // yalnızca okundu
    kayitSil(s.hamYol, s.insanYol, s.kayitNo, klasor.path, test: false);
    expect(KesitDefteri.yukle(klasor.path, test: false).kod('K01')!.kayitlar.keys, ['20261120_090000']);
  });

  test('test sürüşü ayrı dosyalara', () {
    final y = hamYaz('t', yapayKayit(baslangic: gun, a: a, b: b, sanal: true));
    final s = donustur(hamDosya: y, klasor: klasor.path, bilgi: const KayitBilgisi(), stiller: stiller);
    expect(File(s.hamYol).uri.pathSegments.last, 'test_mikromobilite_20261125_ham.gpkg');
    expect(File('${klasor.path}/test_kesitler.json').existsSync(), isTrue);
    expect(kayitlariListele(klasor.path).single.test, isTrue);
  });
}
