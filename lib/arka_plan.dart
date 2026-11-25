import 'dart:isolate';

import 'donusturucu.dart';

// Dosya işlemleri ekranı dondurmasın diye ayrı bir işlem biriminde (isolate) çalışır. Bu işlevler bilerek sayfa
// sınıflarının dışında: bir sayfanın içinde yazılan kapanış (closure) sayfanın kendisini de yakalayabilir ve
// isolate'e gönderilemez ("object is unsendable"). Burada yalnızca düz değerler (metin, sayı, harita) gider.
//
// Gün dosyalarına ve kesit defterine dokunan bütün işlemler TEK SIRADA çalışır (sirayla): aynı anda iki işlem aynı
// GeoPackage'ı yazarsa "database is locked" hatası, aynı anda kesitler.json'ı okuyup yazarsa biri öbürünün değişikliğini
// siler (ör. açılışta yarım kalan kayıt çevrilirken Kayıtlar'da kesit adı verilmesi). Sıradaki bir işlem hata verse de
// sıra sürer. Sıradaki bir işlemin içinden sirayla çağrılmamalı (kendini bekler).

Future<Object?> _son = Future<Object?>.value();

Future<T> sirayla<T>(Future<T> Function() islem) {
  final sonuc = _son.then((_) => islem());
  _son = sonuc.then<Object?>((_) => null, onError: (Object _) => null);
  return sonuc;
}

Future<DonusumSonucu> donusturArkaPlanda(String hamDosya, String klasor, KayitBilgisi bilgi, Map<String, String> stiller) =>
    sirayla(() => Isolate.run(() => donustur(hamDosya: hamDosya, klasor: klasor, bilgi: bilgi, stiller: stiller).toMap()))
        .then(DonusumSonucu.fromMap);

Future<void> puanYazArkaPlanda(String insanYol, String kayitNo, int? puan) =>
    sirayla(() => Isolate.run(() => puanYaz(insanYol, kayitNo, puan)));

Future<void> kesitAdiVerArkaPlanda(String klasor, String kod, String? ad, bool test) =>
    sirayla(() => Isolate.run(() => kesitAdiVer(klasor, kod, ad, test: test)));

Future<void> kayitSilArkaPlanda(String hamYol, String insanYol, String kayitNo, String klasor, bool test) =>
    sirayla(() => Isolate.run(() => kayitSil(hamYol, insanYol, kayitNo, klasor, test: test)));

Future<List<KayitOzeti>> kayitlariListeleArkaPlanda(String klasor) => sirayla(() => Isolate.run(() => kayitlariListele(klasor)));

Future<(List<(double, double)>, List<(double, double)>)> haritaVerisiArkaPlanda(String hamYol, String insanYol, String kayitNo) =>
    sirayla(() => Isolate.run(() => haritaVerisi(hamYol, insanYol, kayitNo)));
