import 'dart:math';
import 'dart:typed_data';

// Telefonun kayıt sırasında yazdığı ikili ham veri dosyasını (.kuham) okur. Biçim: KayitMotoru.kt.
// Bütün zamanlar kayıt başından (BAŞLAT) itibaren saniye olarak verilir; sensörler, GPS ve basışlar aynı saatledir.
// Dosya yarıda kesilmişse (uygulama çöktüyse) okunabilen kısım alınır.

class SensorOrnekleri {
  final List<double> t = [];
  final List<double> x = [];
  final List<double> y = [];
  final List<double> z = [];
  int get sayi => t.length;

  // Gerçek örnekleme hızı (Hz)
  double? get hiz => sayi < 2 || t.last <= t.first ? null : (sayi - 1) / (t.last - t.first);
}

class GpsKonumu {
  GpsKonumu(this.t, this.enlem, this.boylam, this.yukseklik, this.hiz, this.yon, this.dogruluk, this.hizDogrulugu,
      this.dikeyDogruluk, this.uydu, this.gpsSaatiMs, this.sanal);
  final double t;
  final double enlem, boylam;
  final double yukseklik; // m, bilinmiyorsa NaN
  final double hiz; // m/s (GPS Doppler), bilinmiyorsa NaN
  final double yon; // derece, bilinmiyorsa NaN
  final double dogruluk; // m
  final double hizDogrulugu; // m/s
  final double dikeyDogruluk; // m
  final int uydu; // konumda kullanılan uydu; bilinmiyorsa -1
  final int gpsSaatiMs;
  final bool sanal;

  double? get hizKmh => hiz.isNaN ? null : hiz * 3.6;
}

class CukurIsareti {
  CukurIsareti(this.t, this.kaynak);
  final double t;
  final String kaynak;
}

class HamKayit {
  int t0Ns = 0;
  DateTime baslangic = DateTime.fromMillisecondsSinceEpoch(0); // duvar saati (BAŞLAT anı)
  bool sanal = false;
  final SensorOrnekleri ivme = SensorOrnekleri();
  final SensorOrnekleri jiro = SensorOrnekleri();
  final List<GpsKonumu> konumlar = [];
  final List<CukurIsareti> isaretler = [];
  double? bitis; // DURDUR anı (dosya düzgün kapandıysa)
  bool tamamlandi = false; // 'E' kaydı okundu
  bool yarimKaldi = false; // dosya bir kaydın ortasında bitti veya bozuk
  double sensorSaatDuzeltmesi = 0; // s; sensör zaman damgası başka saate göreyse uygulanan fark

  // Kaydın süresi: DURDUR anı, yoksa son veri
  double get sure {
    if (bitis != null) return bitis!;
    var son = 0.0;
    if (ivme.sayi > 0) son = max(son, ivme.t.last);
    if (jiro.sayi > 0) son = max(son, jiro.t.last);
    if (konumlar.isNotEmpty) son = max(son, konumlar.last.t);
    if (isaretler.isNotEmpty) son = max(son, isaretler.last.t);
    return son;
  }

  static const List<String> kaynaklar = ['?', 'ekran', 'tus', 'kumanda', 'kulaklik'];

  static HamKayit oku(Uint8List bayt) {
    final k = HamKayit();
    final b = ByteData.sublistView(bayt);
    if (bayt.length < 6 || String.fromCharCodes(bayt.sublist(0, 6)) != 'KUHAM1') {
      throw const FormatException('Ham kayıt dosyası değil (başlık yok)');
    }
    var i = 6;
    final ivmeNs = <int>[], jiroNs = <int>[];
    final saatFarklari = <int>[];
    bool yeter(int n) => i + n <= bayt.length;
    while (i < bayt.length) {
      final tur = String.fromCharCode(bayt[i]);
      i++;
      switch (tur) {
        case 'S':
          if (!yeter(17)) return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: true);
          k.t0Ns = b.getInt64(i);
          k.baslangic = DateTime.fromMillisecondsSinceEpoch(b.getInt64(i + 8));
          k.sanal = bayt[i + 16] == 1;
          i += 17;
        case 'A':
        case 'G':
          if (!yeter(20)) return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: true);
          final s = tur == 'A' ? k.ivme : k.jiro;
          (tur == 'A' ? ivmeNs : jiroNs).add(b.getInt64(i));
          s.x.add(b.getFloat32(i + 8));
          s.y.add(b.getFloat32(i + 12));
          s.z.add(b.getFloat32(i + 16));
          i += 20;
        case 'L':
          if (!yeter(63)) return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: true);
          k.konumlar.add(GpsKonumu(
            (b.getInt64(i) - k.t0Ns) / 1e9,
            b.getFloat64(i + 8),
            b.getFloat64(i + 16),
            b.getFloat64(i + 24),
            b.getFloat32(i + 32),
            b.getFloat32(i + 36),
            b.getFloat32(i + 40),
            b.getFloat32(i + 44),
            b.getFloat32(i + 48),
            b.getInt16(i + 52),
            b.getInt64(i + 54),
            bayt[i + 62] == 1,
          ));
          i += 63;
        case 'M':
          if (!yeter(9)) return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: true);
          final kod = bayt[i + 8];
          k.isaretler.add(CukurIsareti((b.getInt64(i) - k.t0Ns) / 1e9, kod < kaynaklar.length ? kaynaklar[kod] : '?'));
          i += 9;
        case 'T':
          if (!yeter(24)) return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: true);
          final olay = b.getInt64(i + 8), gelis = b.getInt64(i + 16);
          if (olay != 0 && gelis != 0) saatFarklari.add(gelis - olay);
          i += 24;
        case 'E':
          if (!yeter(8)) return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: true);
          k.bitis = (b.getInt64(i) - k.t0Ns) / 1e9;
          k.tamamlandi = true;
          i += 8;
        default:
          return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: true);
      }
    }
    return k.._bitir(ivmeNs, jiroNs, saatFarklari, yarim: false);
  }

  // Sensör zaman damgalarını kayıt saatine çevirir. Android'de sensör zaman damgası çoğu cihazda elapsedRealtimeNanos
  // saatindedir; değilse (ör. eski cihazlarda açılıştan bu yana geçen süre) 'T' kayıtlarındaki geliş − olay farkının
  // ortancası 1 sn'den büyük çıkar ve bu fark eklenir.
  void _bitir(List<int> ivmeNs, List<int> jiroNs, List<int> saatFarklari, {required bool yarim}) {
    yarimKaldi = yarim;
    var duzeltmeNs = 0;
    if (saatFarklari.isNotEmpty) {
      final s = [...saatFarklari]..sort();
      final ortanca = s[s.length ~/ 2];
      if (ortanca.abs() > 1000000000) duzeltmeNs = ortanca;
    }
    sensorSaatDuzeltmesi = duzeltmeNs / 1e9;
    for (final v in ivmeNs) {
      ivme.t.add((v + duzeltmeNs - t0Ns) / 1e9);
    }
    for (final v in jiroNs) {
      jiro.t.add((v + duzeltmeNs - t0Ns) / 1e9);
    }
    // Yarım kalan son kayıtta x/y/z eklenmiş, zaman eklenmemiş olamaz (önce yeterlilik denetlenir); yine de eşitle
    for (final s in [ivme, jiro]) {
      final n = s.t.length;
      if (s.x.length > n) {
        s.x.removeRange(n, s.x.length);
        s.y.removeRange(n, s.y.length);
        s.z.removeRange(n, s.z.length);
      }
    }
    konumlar.sort((a, b) => a.t.compareTo(b.t));
  }
}

// Dikey sarsıntı (v1 uygulamasındaki yöntemin aynısı): ivmenin üç eksenine 0,4 Hz birinci dereceden yüksek geçiren
// süzgeç (bilineer / Tustin), yerçekimi = ham − süzülmüş, dikey sarsıntı = titreşimin yerçekimi yönüne izdüşümü.
// Telefonun takılma açısından bağımsızdır. İlk örnekte veya 1 sn'den uzun boşlukta süzgeç sıfırlanır.
List<double> dikeySarsinti(SensorOrnekleri a) {
  const tau = 1 / (2 * pi * 0.4);
  final out = List<double>.filled(a.sayi, 0);
  var yx = 0.0, yy = 0.0, yz = 0.0;
  for (var i = 0; i < a.sayi; i++) {
    if (i > 0) {
      final dt = a.t[i] - a.t[i - 1];
      if (dt <= 0 || dt > 1) {
        yx = yy = yz = 0;
      } else {
        final k = 2 * tau / dt;
        final c1 = k / (k + 1), c2 = (k - 1) / (k + 1);
        yx = c1 * (a.x[i] - a.x[i - 1]) + c2 * yx;
        yy = c1 * (a.y[i] - a.y[i - 1]) + c2 * yy;
        yz = c1 * (a.z[i] - a.z[i - 1]) + c2 * yz;
      }
    }
    final gx = a.x[i] - yx, gy = a.y[i] - yy, gz = a.z[i] - yz;
    final gn = sqrt(gx * gx + gy * gy + gz * gz);
    out[i] = gn > 0 ? (yx * gx + yy * gy + yz * gz) / gn : 0;
  }
  return out;
}
