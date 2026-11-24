import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'arka_plan.dart';
import 'donusturucu.dart';
import 'puanlama.dart' show sadeAltlik;

// KONFOR PUANI: DURDUR'dan hemen sonra, sürüş akılda tazeyken. Bir kayıt = bir kesit = bir puan.
// Ekran geçilemez: 1 (çok sarsıntılı) - 5 (çok rahat) veya "Hatırlamıyorum". Ölçülen sarsıntı gösterilmez.
// Puan sonradan Kayıtlar sayfasından değiştirilebilir.

const List<String> puanAdlari = ['', 'Çok sarsıntılı', 'Sarsıntılı', 'Orta', 'Rahat', 'Çok rahat'];

String kesitBasligi(String? kesit, String? kesitAdi) {
  if (kesit == null) return 'Kesit yok (GPS konumu alınamadı)';
  return kesitAdi == null || kesitAdi.isEmpty ? kesit : '$kesit · $kesitAdi';
}

String yonYazisi(String yon) => yon == 'donus' ? 'dönüş' : 'gidiş';

class PuanSayfasi extends StatefulWidget {
  const PuanSayfasi({super.key, required this.sonuc});
  final DonusumSonucu sonuc;

  @override
  State<PuanSayfasi> createState() => _PuanSayfasiState();
}

class _PuanSayfasiState extends State<PuanSayfasi> {
  bool _yaziliyor = false;

  Future<void> _sec(int? puan) async {
    if (_yaziliyor) return;
    setState(() => _yaziliyor = true);
    final s = widget.sonuc;
    try {
      await puanYazArkaPlanda(s.insanYol, s.kayitNo, puan);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _yaziliyor = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Puan kaydedilemedi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sonuc;
    final rota = [for (final (a, b) in s.guzergah) LatLng(a, b)];
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFE9ECEF),
        appBar: AppBar(
          backgroundColor: const Color(0xFF003366),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: const Text('Bu kesit ne kadar rahattı?'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(kesitBasligi(s.kesit, s.kesitAdi),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                const SizedBox(height: 4),
                Text(
                  '${yonYazisi(s.yon)} · ${s.gecis}. geçiş · ${s.sure.toStringAsFixed(0)} sn · ${s.uzunluk.toStringAsFixed(0)} m · '
                  '${s.isaretSayisi} çukur işareti',
                  style: const TextStyle(fontSize: 13.5, color: Color(0xFF495057)),
                ),
                if (s.yarimKaldi)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Kayıt düzgün kapanmamış; okunabilen kısmı kaydedildi.', style: TextStyle(fontSize: 12.5, color: Colors.redAccent)),
                  ),
                const SizedBox(height: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: rota.length < 2
                        ? const ColoredBox(
                            color: Colors.white,
                            child: Center(child: Text('Güzergâh yok (GPS konumu alınamadı)', style: TextStyle(color: Color(0xFF6C757D)))))
                        : FlutterMap(
                            options: MapOptions(
                              initialCameraFit: CameraFit.coordinates(coordinates: rota, padding: const EdgeInsets.all(30), maxZoom: 18),
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                            ),
                            children: [
                              sadeAltlik(),
                              PolylineLayer(polylines: [Polyline(points: rota, strokeWidth: 5, color: const Color(0xFF003366))]),
                              CircleLayer(circles: [
                                CircleMarker(point: rota.first, radius: 6, color: const Color(0xFF198754), borderColor: Colors.white, borderStrokeWidth: 2),
                              ]),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('1 çok sarsıntılı · 5 çok rahat', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF6C757D))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var p = 1; p <= 5; p++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ElevatedButton(
                            onPressed: _yaziliyor ? null : () => _sec(p),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF003366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Column(
                              children: [
                                Text('$p', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                                Text(puanAdlari[p], textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _yaziliyor ? null : () => _sec(null),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF003366), padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Hatırlamıyorum', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
