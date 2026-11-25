import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaan_usta/arka_plan.dart';
import 'package:kaan_usta/donusturucu.dart';
import 'package:kaan_usta/gpkg.dart';

void main() {
  test('dosya işlemleri sırayla çalışır, biri hata verse de sıra sürer', () async {
    final olaylar = <String>[];
    final ilkBitsin = Completer<void>();
    final a = sirayla(() async {
      olaylar.add('a başladı');
      await ilkBitsin.future;
      olaylar.add('a bitti');
      return 1;
    });
    final b = sirayla<int>(() async {
      olaylar.add('b başladı');
      throw StateError('b hatası');
    });
    final c = sirayla(() async {
      olaylar.add('c başladı');
      return 3;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(olaylar, ['a başladı']); // a bitmeden b ve c başlamaz
    ilkBitsin.complete();
    expect(await a, 1);
    await expectLater(b, throwsStateError);
    expect(await c, 3);
    expect(olaylar, ['a başladı', 'a bitti', 'b başladı', 'c başladı']);
  });

  test('arka plan işlevleri isolate ile çalışır (gönderilemeyen nesne yakalamaz)', () async {
    final klasor = Directory.systemTemp.createTempSync('kaan_usta_arka');
    addTearDown(() => klasor.deleteSync(recursive: true));
    expect(await kayitlariListeleArkaPlanda(klasor.path), isEmpty);
  });

  test('GeoPackage kilitliyse beklenir (busy_timeout)', () {
    final klasor = Directory.systemTemp.createTempSync('kaan_usta_kilit');
    addTearDown(() => klasor.deleteSync(recursive: true));
    final gp = GeoPackage.ac('${klasor.path}/x.gpkg');
    expect(gp.db.select('PRAGMA busy_timeout').first.values.first, 5000);
    gp.kapat();
  });

  test('kayıt bilgisi: boş alanlar eskisinden doldurulur', () {
    const eski = KayitBilgisi(cihaz: 'Telefon', scooter: 'Hop', hava: 'Açık', sicaklik: 4.1, yagis: 0);
    const yeni = KayitBilgisi(cihaz: 'Telefon', uygulamaSurumu: '2.1.0 (yapı 38)');
    final b = yeni.eksikleriDoldur(eski);
    expect((b.scooter, b.hava, b.sicaklik, b.yagis, b.uygulamaSurumu), ('Hop', 'Açık', 4.1, 0.0, '2.1.0 (yapı 38)'));
    // Yeni değer varsa o kalır
    const sonra = KayitBilgisi(scooter: 'Martı', hava: 'Yağmurlu', sicaklik: 9);
    expect((sonra.eksikleriDoldur(eski).scooter, sonra.eksikleriDoldur(eski).hava), ('Martı', 'Yağmurlu'));
  });
}
