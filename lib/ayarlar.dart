import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kalıcı ayarlar: telefonda saklanır, her kayda otomatik yazılır
class Ayarlar {
  static const String _scooterAnahtar = 'scooter';

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
  bool _testSurusu = false;

  @override
  void initState() {
    super.initState();
    Future.wait([Ayarlar.scooter(), Ayarlar.testSurusu()]).then((d) {
      if (!mounted) return;
      setState(() {
        _scooter.text = d[0] as String;
        _testSurusu = d[1] as bool;
        _yuklendi = true;
      });
    });
  }

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
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ÇUKUR İŞARETİ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                  SizedBox(height: 8),
                  Text(
                    'Kayıt sırasında ani sarsıntı veren her şeyde (çukur, kasis, ray, rögar, kot farkı) kulaklık veya Bluetooth '
                    'kumanda tuşuna basın; ekran kapalıyken de çalışır. Arnavut kaldırımı gibi sürekli pürüzlü zeminde yalnızca '
                    'zeminden belirgin ayrılan sarsıntılara basın. Ekrandaki ÇUKUR butonu ve telefonun ses tuşu yedektir: '
                    'telefonu sarsarlar. 1 sn içindeki ikinci basış sayılmaz.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF212529), height: 1.35),
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
                      'Konum YTÜ Davutpaşa Yerleşkesi\'nin iç yollarında ~1,85 km\'lik bir tur üzerinde üretilir: başladığı '
                      'yere dönünce 6 sn durup yeni tura başlar, hız 4-20 km/h. Sarsıntı gerçek ivmeölçerden ölçülür. GPS\'i olmayan cihazda, kapalı '
                      'alanda veya evde kayıt akışını prova etmek içindir. Test kayıtları ayrı dosyalara (test_mikromobilite_...) '
                      'yazılır, Kayıtlar\'da TEST diye ayrı görünür. Tez verisi için kapalı tutun.',
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
                    'Kayıt başında internet ve GPS konumu varsa hava durumu (durum, sıcaklık, yağış) '
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
