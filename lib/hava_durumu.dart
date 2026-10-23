import 'dart:convert';
import 'dart:io';

// Kayıt başındaki hava durumu: Open-Meteo (anahtarsız, ücretsiz; https://open-meteo.com, CC BY 4.0).
// Konum ~1 km'ye yuvarlanarak gönderilir (hava durumu için yeterli).
class HavaDurumu {
  HavaDurumu(this.durum, this.sicaklik, this.nem, this.yagis, this.ruzgar, this.zaman);

  final String durum;
  final double sicaklik; // °C
  final double nem; // %
  final double yagis; // mm (son saat)
  final double ruzgar; // km/h
  final String zaman; // servisin ölçüm zamanı (yerel)

  static String _s(double v, [int basamak = 1]) => v.toStringAsFixed(basamak).replaceAll('.', ',');

  String satir() =>
      '$durum, ${_s(sicaklik)} °C, yağış ${_s(yagis)} mm, rüzgâr ${_s(ruzgar, 0)} km/h, nem %${_s(nem, 0)} (Open-Meteo, $zaman)';

  // Alınamazsa (internet yok, zaman aşımı, hata) null döner
  static Future<HavaDurumu?> al(double enlem, double boylam) async {
    final istemci = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': enlem.toStringAsFixed(2),
        'longitude': boylam.toStringAsFixed(2),
        'current': 'temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
        'timezone': 'auto',
      });
      final yanit = await (await istemci.getUrl(uri)).close().timeout(const Duration(seconds: 8));
      if (yanit.statusCode != 200) return null;
      final govde = await yanit.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
      final c = (jsonDecode(govde) as Map<String, dynamic>)['current'] as Map<String, dynamic>;
      double sayi(String k) => (c[k] as num).toDouble();
      return HavaDurumu(
        _durum((c['weather_code'] as num).toInt()),
        sayi('temperature_2m'),
        sayi('relative_humidity_2m'),
        sayi('precipitation'),
        sayi('wind_speed_10m'),
        (c['time'] as String).replaceAll('T', ' '),
      );
    } catch (_) {
      return null;
    } finally {
      istemci.close(force: true);
    }
  }

  // WMO hava durumu kodları
  static String _durum(int kod) {
    if (kod == 0) return 'Açık';
    if (kod == 1) return 'Çoğunlukla açık';
    if (kod == 2) return 'Parçalı bulutlu';
    if (kod == 3) return 'Kapalı';
    if (kod == 45 || kod == 48) return 'Sisli';
    if (kod >= 51 && kod <= 57) return 'Çisenti';
    if (kod >= 61 && kod <= 67) return 'Yağmurlu';
    if (kod >= 71 && kod <= 77) return 'Karlı';
    if (kod >= 80 && kod <= 82) return 'Sağanak';
    if (kod == 85 || kod == 86) return 'Kar sağanağı';
    if (kod >= 95) return 'Gök gürültülü fırtına';
    return 'Bilinmiyor ($kod)';
  }
}
