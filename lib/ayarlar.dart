import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kalıcı ayarlar: telefonda saklanır, her kaydın _bilgi.txt dosyasına otomatik yazılır
class Ayarlar {
  static const String _scooterAnahtar = 'scooter';

  static Future<String> scooter() async => (await SharedPreferences.getInstance()).getString(_scooterAnahtar) ?? '';

  static Future<void> scooterKaydet(String deger) async =>
      (await SharedPreferences.getInstance()).setString(_scooterAnahtar, deger.trim());
}

class AyarlarPage extends StatefulWidget {
  const AyarlarPage({super.key});

  @override
  State<AyarlarPage> createState() => _AyarlarPageState();
}

class _AyarlarPageState extends State<AyarlarPage> {
  final TextEditingController _scooter = TextEditingController();
  bool _yuklendi = false;

  @override
  void initState() {
    super.initState();
    Ayarlar.scooter().then((deger) {
      if (!mounted) return;
      setState(() {
        _scooter.text = deger;
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
