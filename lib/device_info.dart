import 'package:flutter/services.dart';

// Cihaz ve sensör bilgisi (Android tarafı: MainActivity.kt, "kaan_usta/cihaz" kanalı)
class DeviceInfo {
  static const MethodChannel _channel = MethodChannel('kaan_usta/cihaz');
  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> load() async {
    if (_cache != null) return _cache!;
    try {
      final result = await _channel.invokeMethod<Map>('bilgi');
      _cache = Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      _cache = {'hata': '$e'};
    }
    return _cache!;
  }

  // Okunabilir satırlar: Teknik Bilgi sayfası ve _bilgi.txt dosyası aynı metni kullanır
  static List<String> describe(Map<String, dynamic> info) {
    if (info.containsKey('hata')) return ['Cihaz bilgisi okunamadı: ${info['hata']}'];
    return [
      'Uygulama sürümü: ${info['appVersion']} (yapı ${info['appBuild']})',
      'Cihaz: ${info['manufacturer']} ${info['model']}',
      'Android: ${info['android']} (API ${info['sdk']})',
      ..._sensorLines('İvmeölçer', info['accelerometer'], 'm/s²'),
    ];
  }

  static List<String> _sensorLines(String label, dynamic sensor, String unit) {
    if (sensor == null) return ['$label: bu cihazda yok'];
    final s = Map<String, dynamic>.from(sensor as Map);
    final int minDelayUs = (s['minDelayUs'] as num).toInt();
    final String maxRate = minDelayUs > 0 ? '${(1e6 / minDelayUs).toStringAsFixed(0)} Hz' : 'olay tabanlı';
    return [
      '$label: ${s['name']} (${s['vendor']})',
      '  Çözünürlük: ${(s['resolution'] as num).toStringAsPrecision(3)} $unit, ölçüm aralığı: ±${(s['maxRange'] as num).toStringAsFixed(1)} $unit, en yüksek örnekleme: $maxRate',
    ];
  }
}
