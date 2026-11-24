import 'dart:isolate';

import 'donusturucu.dart';

// Dosya işlemleri ekranı dondurmasın diye ayrı bir işlem biriminde (isolate) çalışır. Bu işlevler bilerek sayfa
// sınıflarının dışında: bir sayfanın içinde yazılan kapanış (closure) sayfanın kendisini de yakalayabilir ve
// isolate'e gönderilemez ("object is unsendable"). Burada yalnızca düz değerler (metin, sayı, harita) gider.

Future<DonusumSonucu> donusturArkaPlanda(String hamDosya, String klasor, KayitBilgisi bilgi, Map<String, String> stiller) async =>
    DonusumSonucu.fromMap(
        await Isolate.run(() => donustur(hamDosya: hamDosya, klasor: klasor, bilgi: bilgi, stiller: stiller).toMap()));

Future<void> puanYazArkaPlanda(String insanYol, String kayitNo, int? puan) => Isolate.run(() => puanYaz(insanYol, kayitNo, puan));

Future<void> kesitAdiVerArkaPlanda(String klasor, String kod, String? ad, bool test) =>
    Isolate.run(() => kesitAdiVer(klasor, kod, ad, test: test));

Future<void> kayitSilArkaPlanda(String hamYol, String insanYol, String kayitNo, String klasor, bool test) =>
    Isolate.run(() => kayitSil(hamYol, insanYol, kayitNo, klasor, test: test));

Future<List<KayitOzeti>> kayitlariListeleArkaPlanda(String klasor) => Isolate.run(() => kayitlariListele(klasor));

Future<(List<(double, double)>, List<(double, double)>)> haritaVerisiArkaPlanda(String hamYol, String insanYol, String kayitNo) =>
    Isolate.run(() => haritaVerisi(hamYol, insanYol, kayitNo));
