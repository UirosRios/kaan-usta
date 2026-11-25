import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaan_usta/kesitler.dart';

// Kesit defteri: referans uçlar kayıtların uçlarının ortancasıdır; silinen kayıt referanstan çıkar.

const a = (41.027878, 28.889648), b = (41.026281, 28.888188); // YTÜ Davutpaşa, ~215 m

// Noktayı kuzeye / doğuya metre cinsinden kaydırır
(double, double) kaydir((double, double) p, {double kuzey = 0, double dogu = 0}) =>
    (p.$1 + kuzey / 111195, p.$2 + dogu / (111195 * cos(p.$1 * pi / 180)));

double uzaklik((double, double) p, double enlem, double boylam) => mesafeM(p.$1, p.$2, enlem, boylam);

void main() {
  late Directory klasor;
  setUp(() => klasor = Directory.systemTemp.createTempSync('kaan_usta_kesit'));
  tearDown(() => klasor.deleteSync(recursive: true));

  KesitDefteri yeni() => KesitDefteri.yukle(klasor.path, test: false);

  test('yanlış noktadan başlayan ilk geçiş silinince kesit kalan geçişlere göre eşleşir', () {
    final d = yeni();
    expect(d.ata('k1', kaydir(a, kuzey: 25), b)!.kesit.kod, 'K01'); // 25 m erken başlamış ilk geçiş
    expect(d.ata('k2', a, b)!.kesit.kod, 'K01');
    d.kayitSil('k1');
    final k = d.kod('K01')!;
    expect(uzaklik(a, k.basEnlem, k.basBoylam), lessThan(0.01));
    // Eski referanstan (ilk geçiş) 53 m, yeni referanstan 28 m uzakta başlayan geçiş aynı kesittir
    final s = d.ata('k3', kaydir(a, kuzey: -28), b)!;
    expect((s.kesit.kod, s.yon, s.gecis), ('K01', 'gidis', 2));
  });

  test('dönüş kaydının uçları kesitin yönüne çevrilir', () {
    final d = yeni();
    d.ata('k1', a, b);
    final b2 = kaydir(b, dogu: 10);
    final s = d.ata('k2', b2, a)!; // ters yön, başlangıcı 10 m doğuda
    expect((s.kesit.kod, s.yon), ('K01', 'donus'));
    final k = s.kesit;
    expect(k.uclar['k2'], [a.$1, a.$2, b2.$1, b2.$2]);
    expect(uzaklik(a, k.basEnlem, k.basBoylam), lessThan(0.01));
    expect(uzaklik(kaydir(b, dogu: 5), k.bitEnlem, k.bitBoylam), lessThan(0.01)); // iki geçişin ortası
  });

  test('3+ geçişli kesitte sapan tek geçiş referansı kaydırmaz', () {
    final d = yeni();
    for (final no in ['k1', 'k2', 'k3']) {
      d.ata(no, a, b);
    }
    expect(d.ata('k4', kaydir(a, kuzey: 29), b)!.kesit.kod, 'K01');
    final k = d.kod('K01')!;
    expect(uzaklik(a, k.basEnlem, k.basBoylam), lessThan(0.01));
  });

  test('adı verilmiş kesit boşalınca kalır; yeniden sürülünce kodunu ve adını korur', () {
    final d = yeni();
    d.ata('k1', a, b);
    d.ata('u1', (41.0245, 28.8877), (41.0225, 28.8911)); // K02, adsız
    d.kod('K01')!.ad = 'Kuzey yolu';
    d.kayitSil('k1');
    d.kayitSil('u1');
    expect(d.kesitler.map((k) => k.kod), ['K01']); // adsız boş kesit silinir
    expect(d.kod('K01')!.uclar, isEmpty);
    final s = d.ata('k2', kaydir(a, kuzey: 20), b)!;
    expect((s.kesit.kod, s.kesit.ad, s.gecis), ('K01', 'Kuzey yolu', 1));
  });

  test('defter kaydedilip yüklenince uçlar ve referans aynı kalır', () {
    final d = yeni();
    d.ata('k1', a, b);
    d.ata('k2', b, kaydir(a, dogu: 6));
    d.kaydet();
    final y = yeni();
    final k = y.kod('K01')!, e = d.kod('K01')!;
    expect(k.uclar, e.uclar);
    expect([k.basEnlem, k.basBoylam, k.bitEnlem, k.bitBoylam], [e.basEnlem, e.basBoylam, e.bitEnlem, e.bitBoylam]);
    expect(k.kayitlar, {'k1': 'gidis', 'k2': 'donus'});
  });

  test('2.1 öncesi defter (uçlar yok): bilinmeyenler listelenir, eski referans korunur', () {
    File('${klasor.path}/kesitler.json').writeAsStringSync('{"kesitler": [{"kod": "K01", "ad": null, '
        '"bas": [${a.$1}, ${a.$2}], "bit": [${b.$1}, ${b.$2}], "kayitlar": {"k1": "gidis", "k2": "donus"}}]}');
    final d = yeni();
    final k = d.kod('K01')!;
    expect([for (final (kesit, no) in d.ucuBilinmeyenler()) '${kesit.kod}/$no'], ['K01/k1', 'K01/k2']);
    // Bilinmeyen kaydın silinmesi referansı değiştirmez
    d.kayitSil('k1');
    expect([k.basEnlem, k.bitEnlem], [a.$1, b.$1]);
    // Yeniden çevrilen kayıt (zaten atanmış) uçlarını ekler
    final s = d.ata('k2', kaydir(b, dogu: 4), a)!;
    expect((s.kesit.kod, s.yon), ('K01', 'donus'));
    expect(d.ucuBilinmeyenler(), isEmpty);
    expect(uzaklik(kaydir(b, dogu: 4), k.bitEnlem, k.bitBoylam), lessThan(0.01));
  });
}
