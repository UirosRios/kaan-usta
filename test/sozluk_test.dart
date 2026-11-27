import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaan_usta/katmanlar.dart';

// Uygulamanın dosyalara yazdığı veri sözlüğü, örnek dosyaların ve Claude dosyasının sözlüğüyle (qgis/sozluk.py) aynı
// olmalı. qgis/sozluk.json, `python3 qgis/sozluk.py` ile qgis/sozluk.py'den üretilir; Python testi de onun güncel
// olduğunu denetler. Biri değişip öbürü unutulursa iki testten biri düşer.
void main() {
  final beklenen = jsonDecode(File('qgis/sozluk.json').readAsStringSync()) as Map<String, dynamic>;
  List<List<String>> liste(String ad) => [for (final r in beklenen[ad] as List) [for (final h in r as List) h as String]];

  test('ham dosya sözlüğü qgis/sozluk.py ile aynı', () {
    expect(hamAciklamalari(test: false), liste('ham'));
  });

  test('insan dosyası sözlüğü qgis/sozluk.py ile aynı', () {
    expect(insanAciklamalari(test: false), liste('insan'));
  });
}
