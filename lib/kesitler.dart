import 'dart:convert';
import 'dart:io';
import 'dart:math';

// KESİT DEFTERİ: bir kayıt = bir kesitin bir geçişi. Kesit kodu (K01, K02, ...) otomatik verilir: başlangıç ve bitiş
// noktası daha önceki bir kesitle ~30 m içinde örtüşen kayıt aynı kesittir; ters yönde örtüşüyorsa aynı kesitin
// dönüşüdür. Kesit adını kullanıcı Kayıtlar sayfasında verir. Defter, kayıt klasöründe JSON dosyasıdır
// (kesitler.json; test sürüşleri için test_kesitler.json).
//
// Kesitin referans uçları, kayıtlarının uçlarının ortancasıdır (her kaydın uçları kesitin kendi yönüne çevrilerek
// saklanır; sürüm 2.1'den önce yalnızca ilk kaydın uçları kullanılıyordu). Böylece ilk geçiş yanlış noktadan
// başlayıp silinse de kesit doğru geçişlere göre eşleşir ve tek bir geçişin GPS sapması referansı kaydırmaz.
// Bütün kayıtları silinen kesit defterde kalır (görünmez; son referansıyla): aynı yer yeniden sürülünce kodu ve adı geri
// gelir, başka bir sokak yeni kod alır (silinen kodun başka sokağa verilmesi, daha önce gönderilmiş dosyalarla karışırdı).
// Kesitin yönü ilk kaydınkidir, sonradan değişmez.

const double kesitEsigiM = 30;

double mesafeM(double enlem1, double boylam1, double enlem2, double boylam2) {
  const r = 6371000.0;
  final p1 = enlem1 * pi / 180, p2 = enlem2 * pi / 180;
  final dp = p2 - p1, dl = (boylam2 - boylam1) * pi / 180;
  final a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
  return 2 * r * asin(min(1, sqrt(a)));
}

class Kesit {
  Kesit(this.kod, this.ad, this.basEnlem, this.basBoylam, this.bitEnlem, this.bitBoylam, this.kayitlar,
      [Map<String, List<double>>? uclar])
      : uclar = uclar ?? {};
  final String kod;
  String? ad;
  double basEnlem, basBoylam, bitEnlem, bitBoylam; // referans uçlar, kesitin (ilk kaydının) yönünde
  final Map<String, String> kayitlar; // kayit_no -> yon (gidis / donus)
  final Map<String, List<double>> uclar; // kayit_no -> [baş enlem, baş boylam, bitiş enlem, bitiş boylam], kesitin yönünde

  // Kaydın uçlarını kesitin yönüne çevirip saklar (dönüş kaydının başı kesitin bitişidir) ve referansı yeniler
  void ucEkle(String kayitNo, (double, double) bas, (double, double) bit) {
    uclar[kayitNo] = kayitlar[kayitNo] == 'donus' ? [bit.$1, bit.$2, bas.$1, bas.$2] : [bas.$1, bas.$2, bit.$1, bit.$2];
    referansiYenile();
  }

  // Referans = uçların ortancası (enlem ve boylam ayrı ayrı; çift sayıda kayıtta ortadaki ikisinin ortalaması)
  void referansiYenile() {
    if (uclar.isEmpty) return;
    double ortanca(int i) {
      final d = [for (final u in uclar.values) u[i]]..sort();
      final n = d.length;
      return n.isOdd ? d[n ~/ 2] : (d[n ~/ 2 - 1] + d[n ~/ 2]) / 2;
    }

    basEnlem = ortanca(0);
    basBoylam = ortanca(1);
    bitEnlem = ortanca(2);
    bitBoylam = ortanca(3);
  }

  Map<String, Object?> toJson() => {
        'kod': kod,
        'ad': ad,
        'bas': [basEnlem, basBoylam],
        'bit': [bitEnlem, bitBoylam],
        'kayitlar': kayitlar,
        'uclar': uclar,
      };

  static Kesit fromJson(Map<String, dynamic> j) => Kesit(
        j['kod'] as String,
        j['ad'] as String?,
        (j['bas'][0] as num).toDouble(),
        (j['bas'][1] as num).toDouble(),
        (j['bit'][0] as num).toDouble(),
        (j['bit'][1] as num).toDouble(),
        Map<String, String>.from(j['kayitlar'] as Map),
        {
          for (final e in ((j['uclar'] as Map?) ?? const {}).entries)
            e.key as String: [for (final v in e.value as List) (v as num).toDouble()],
        },
      );
}

class KesitAtamasi {
  KesitAtamasi(this.kesit, this.yon, this.gecis);
  final Kesit kesit;
  final String yon;
  final int gecis; // bu kesitin kaçıncı geçişi
}

class KesitDefteri {
  KesitDefteri(this.dosya, this.kesitler);
  final File dosya;
  final List<Kesit> kesitler;

  static File dosyaFor(String klasor, {required bool test}) => File('$klasor/${test ? 'test_' : ''}kesitler.json');

  static KesitDefteri yukle(String klasor, {required bool test}) {
    final f = dosyaFor(klasor, test: test);
    if (!f.existsSync()) return KesitDefteri(f, []);
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return KesitDefteri(f, [for (final k in j['kesitler'] as List) Kesit.fromJson(k as Map<String, dynamic>)]);
  }

  // Önce geçici dosyaya yazılıp yeniden adlandırılır: yazarken çökme defteri bozmasın
  void kaydet() {
    final gecici = File('${dosya.path}.yeni');
    gecici.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'kesitler': [for (final k in kesitler) k.toJson()]}),
        flush: true);
    gecici.renameSync(dosya.path);
  }

  Kesit? kod(String kod) {
    for (final k in kesitler) {
      if (k.kod == kod) return k;
    }
    return null;
  }

  // Uçları bilinmeyen kayıtlar (2.1'den önceki defter): çağıran gün dosyasından bulup ucEkle ile ekler
  List<(Kesit, String)> ucuBilinmeyenler() => [
        for (final k in kesitler)
          for (final no in k.kayitlar.keys)
            if (!k.uclar.containsKey(no)) (k, no),
      ];

  // Kaydı bir kesite atar (zaten atanmışsa aynısını döner). Başlangıç / bitiş noktası yoksa (GPS yok) null.
  KesitAtamasi? ata(String kayitNo, (double, double)? bas, (double, double)? bit) {
    for (final k in kesitler) {
      final y = k.kayitlar[kayitNo];
      if (y != null) {
        if (!k.uclar.containsKey(kayitNo) && bas != null && bit != null) k.ucEkle(kayitNo, bas, bit);
        return KesitAtamasi(k, y, k.kayitlar.keys.toList().indexOf(kayitNo) + 1);
      }
    }
    if (bas == null || bit == null) return null;
    Kesit? enIyi;
    String yon = 'gidis';
    var enKucuk = double.infinity;
    for (final k in kesitler) {
      final ileri = max(mesafeM(bas.$1, bas.$2, k.basEnlem, k.basBoylam), mesafeM(bit.$1, bit.$2, k.bitEnlem, k.bitBoylam));
      final geri = max(mesafeM(bas.$1, bas.$2, k.bitEnlem, k.bitBoylam), mesafeM(bit.$1, bit.$2, k.basEnlem, k.basBoylam));
      if (ileri <= kesitEsigiM && ileri < enKucuk) {
        enIyi = k;
        yon = 'gidis';
        enKucuk = ileri;
      }
      if (geri <= kesitEsigiM && geri < enKucuk) {
        enIyi = k;
        yon = 'donus';
        enKucuk = geri;
      }
    }
    if (enIyi == null) {
      var n = kesitler.length + 1;
      String yeniKod() => 'K${n.toString().padLeft(2, '0')}';
      while (kod(yeniKod()) != null) {
        n++;
      }
      enIyi = Kesit(yeniKod(), null, bas.$1, bas.$2, bit.$1, bit.$2, {});
      kesitler.add(enIyi);
      yon = 'gidis';
    }
    enIyi.kayitlar[kayitNo] = yon;
    enIyi.ucEkle(kayitNo, bas, bit);
    return KesitAtamasi(enIyi, yon, enIyi.kayitlar.length);
  }

  // Kaydı kesitinden çıkarır; kesit boşalsa da silinmez (kodu bir daha başka kesite verilmez)
  void kayitSil(String kayitNo) {
    for (final k in kesitler) {
      k.kayitlar.remove(kayitNo);
      if (k.uclar.remove(kayitNo) != null) k.referansiYenile();
    }
  }
}
