import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kayıt sırasında çukurlar nasıl ele alınır. Her durumda uygulamanın otomatik tespiti CSV'nin Cukur sütununa
// sessizce yazılır; mod yalnızca sürücünün gördüğünü / yaptığını belirler.
enum CukurModu {
  // Doğrulama sürüşü: sürücü çukurları kendisi işaretler (buton, ses tuşu, kumanda, kulaklık). Otomatik uyarı
  // gösterilmez: uyarıyı gören sürücünün işaretleri ölçümden bağımsız olmazdı.
  isaret('isaret', 'Çukurları ben işaretlerim (doğrulama)'),
  // Sürücü sert darbede ekranda kırmızı ışık ve sesle uyarılır; işaret butonu yok
  uyari('uyari', 'Otomatik çukur uyarısı'),
  // Yalnızca ölçüm: ne işaret ne uyarı
  kapali('kapali', 'Yalnızca ölçüm (işaret ve uyarı yok)');

  const CukurModu(this.kod, this.ad);
  final String kod;
  final String ad;
}

// Kalıcı ayarlar: telefonda saklanır, her kaydın _bilgi.txt dosyasına otomatik yazılır
class Ayarlar {
  static const String _scooterAnahtar = 'scooter';
  static const String _cukurModuAnahtar = 'cukur_modu';

  static Future<CukurModu> cukurModu() async {
    final kod = (await SharedPreferences.getInstance()).getString(_cukurModuAnahtar);
    return CukurModu.values.firstWhere((m) => m.kod == kod, orElse: () => CukurModu.isaret);
  }

  static Future<void> cukurModuKaydet(CukurModu mod) async =>
      (await SharedPreferences.getInstance()).setString(_cukurModuAnahtar, mod.kod);

  static Future<String> scooter() async => (await SharedPreferences.getInstance()).getString(_scooterAnahtar) ?? '';

  static Future<void> scooterKaydet(String deger) async =>
      (await SharedPreferences.getInstance()).setString(_scooterAnahtar, deger.trim());

  // Test sürüşü: gerçek GPS yerine YTÜ Davutpaşa Yerleşkesi'nde sanal konum ve hız üretilir (ivmeölçer gerçektir).
  // GPS'i olmayan cihazda (ör. yalnızca Wi-Fi tablet) veya kapalı alanda arayüzü denemek içindir.
  static const String _testSurusuAnahtar = 'test_surusu';

  static Future<bool> testSurusu() async => (await SharedPreferences.getInstance()).getBool(_testSurusuAnahtar) ?? false;

  static Future<void> testSurusuKaydet(bool deger) async =>
      (await SharedPreferences.getInstance()).setBool(_testSurusuAnahtar, deger);
}

class AyarlarPage extends StatefulWidget {
  const AyarlarPage({super.key});

  @override
  State<AyarlarPage> createState() => _AyarlarPageState();
}

class _AyarlarPageState extends State<AyarlarPage> {
  final TextEditingController _scooter = TextEditingController();
  bool _yuklendi = false;
  CukurModu _cukurModu = CukurModu.isaret;
  bool _testSurusu = false;

  @override
  void initState() {
    super.initState();
    Future.wait([Ayarlar.scooter(), Ayarlar.cukurModu(), Ayarlar.testSurusu()]).then((d) {
      if (!mounted) return;
      setState(() {
        _scooter.text = d[0] as String;
        _cukurModu = d[1] as CukurModu;
        _testSurusu = d[2] as bool;
        _yuklendi = true;
      });
    });
  }

  static const Map<CukurModu, String> _modAciklama = {
    CukurModu.isaret: 'Çukurdan geçince ÇUKUR butonuna, ses tuşuna, Bluetooth kumandaya veya kulaklık tuşuna basarsınız. '
        'Otomatik uyarı gösterilmez: uyarıyı görmeyen sürücünün işaretleri ölçümden bağımsız bir referans olur. '
        'Doğrulama sürüşleri için önerilir.',
    CukurModu.uyari: 'Sert darbede sarsıntı kartı kırmızı yanar ve sesli uyarı verilir. İşaret butonu çıkmaz, '
        'ses tuşları normal çalışır.',
    CukurModu.kapali: 'Ekrana dokunmadan yalnızca ölçüm yapılır.',
  };

  @override
  void dispose() {
    _scooter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        title: const Text('Ayarlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SCOOTER', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _scooter,
                    enabled: _yuklendi,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Kullanılan scooter (marka / model)',
                      hintText: 'Örnek: Xiaomi Electric Scooter 4 Pro',
                      helperText: 'Her kayda otomatik eklenir. Değişirse buradan güncelleyin.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    // Her değişiklik hemen kaydedilir
                    onChanged: Ayarlar.scooterKaydet,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text('KAYIT SIRASINDA ÇUKUR', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                  ),
                  RadioGroup<CukurModu>(
                    groupValue: _cukurModu,
                    onChanged: (mod) {
                      if (mod == null || !_yuklendi) return;
                      setState(() => _cukurModu = mod);
                      Ayarlar.cukurModuKaydet(mod);
                    },
                    child: Column(
                      children: [
                        for (final mod in CukurModu.values)
                          RadioListTile<CukurModu>(
                            value: mod,
                            contentPadding: EdgeInsets.zero,
                            title: Text(mod.ad, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: Text(_modAciklama[mod]!, style: const TextStyle(fontSize: 12.5, height: 1.3)),
                          ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 12, top: 4),
                    child: Text(
                      'Her modda uygulamanın otomatik tespiti kayda sessizce yazılır; analiz betiği işaretlerle karşılaştırır. '
                      'Değişiklik bir sonraki kayıtta geçerli olur.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6C757D), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TEST SÜRÜŞÜ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sanal GPS kullan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Konum YTÜ Davutpaşa Yerleşkesi\'nde 150 m yarıçaplı bir tur üzerinde, hız 4-20 km/h arasında üretilir '
                      '(dakikada bir 6 sn duruş). Sarsıntı gerçek ivmeölçerden ölçülür. GPS\'i olmayan cihazda veya kapalı '
                      'alanda uygulamayı denemek içindir. Kayıtlar "test_" ile başlar, bilgi dosyasında TEST SÜRÜŞÜ yazar, '
                      'analiz betikleri klasör taramasında bunları atlar. Puanlamada parçalar 50 m yerine 5 m\'den başlar. '
                      'Tez verisi için kapalı tutun.',
                      style: TextStyle(fontSize: 12.5, height: 1.3),
                    ),
                    value: _testSurusu,
                    onChanged: _yuklendi
                        ? (v) {
                            setState(() => _testSurusu = v);
                            Ayarlar.testSurusuKaydet(v);
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HAVA DURUMU', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                  SizedBox(height: 8),
                  Text(
                    'Kayıt başında internet ve GPS konumu varsa hava durumu (durum, sıcaklık, yağış, rüzgâr, nem) '
                    'Open-Meteo servisinden otomatik alınır ve kayda eklenir. Alınamazsa kayda hava durumu yazılmaz.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF212529), height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
