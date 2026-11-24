import 'dart:convert';
import 'dart:io';
import 'dart:math';

// KESİT DEFTERİ: bir kayıt = bir kesitin bir geçişi. Kesit kodu (K01, K02, ...) otomatik verilir: başlangıç ve bitiş
// noktası daha önceki bir kesitle ~30 m içinde örtüşen kayıt aynı kesittir; ters yönde örtüşüyorsa aynı kesitin
// dönüşüdür. Kesit adını kullanıcı Kayıtlar sayfasında verir. Defter, kayıt klasöründe JSON dosyasıdır
// (kesitler.json; test sürüşleri için test_kesitler.json).

const double kesitEsigiM = 30;

double mesafeM(double enlem1, double boylam1, double enlem2, double boylam2) {
  const r = 6371000.0;
  final p1 = enlem1 * pi / 180, p2 = enlem2 * pi / 180;
  final dp = p2 - p1, dl = (boylam2 - boylam1) * pi / 180;
  final a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
  return 2 * r * asin(min(1, sqrt(a)));
}

class Kesit {
  Kesit(this.kod, this.ad, this.basEnlem, this.basBoylam, this.bitEnlem, this.bitBoylam, this.kayitlar);
  final String kod;
  String? ad;
  final double basEnlem, basBoylam, bitEnlem, bitBoylam; // ilk kaydın yönünde
  final Map<String, String> kayitlar; // kayit_no -> yon (gidis / donus)

  Map<String, Object?> toJson() => {
        'kod': kod,
        'ad': ad,
        'bas': [basEnlem, basBoylam],
        'bit': [bitEnlem, bitBoylam],
        'kayitlar': kayitlar,
      };

  static Kesit fromJson(Map<String, dynamic> j) => Kesit(
        j['kod'] as String,
        j['ad'] as String?,
        (j['bas'][0] as num).toDouble(),
        (j['bas'][1] as num).toDouble(),
        (j['bit'][0] as num).toDouble(),
        (j['bit'][1] as num).toDouble(),
        Map<String, String>.from(j['kayitlar'] as Map),
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

  // Kaydı bir kesite atar (zaten atanmışsa aynısını döner). Başlangıç / bitiş noktası yoksa (GPS yok) null.
  KesitAtamasi? ata(String kayitNo, (double, double)? bas, (double, double)? bit) {
    for (final k in kesitler) {
      final y = k.kayitlar[kayitNo];
      if (y != null) return KesitAtamasi(k, y, k.kayitlar.keys.toList().indexOf(kayitNo) + 1);
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
    return KesitAtamasi(enIyi, yon, enIyi.kayitlar.length);
  }

  void kayitSil(String kayitNo) {
    for (final k in kesitler) {
      k.kayitlar.remove(kayitNo);
    }
    kesitler.removeWhere((k) => k.kayitlar.isEmpty && (k.ad == null || k.ad!.isEmpty));
  }
}
