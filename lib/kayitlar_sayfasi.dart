import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import 'arka_plan.dart';
import 'donusturucu.dart';
import 'puan_sayfasi.dart';
import 'puanlama.dart' show sadeAltlik;
import 'recordings_page.dart';

// KAYITLAR (2.0): kayıtlar sürüş günlerine göre listelenir. Her gün iki dosyadır:
//   ..._ham.gpkg   : Claude'a gönderilen ham veri (sürücünün işaret ve puanları içinde yok)
//   ..._insan.gpkg : sürücünün çukur işaretleri ve konfor puanları (sürücüde kalır)
// Kesite ad verilebilir (aynı kesitin bütün kayıtlarına uygulanır), puan değiştirilebilir, kayıt silinebilir.

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

String gunBasligi(String kayitNo) {
  final y = int.parse(kayitNo.substring(0, 4)), a = int.parse(kayitNo.substring(4, 6)), g = int.parse(kayitNo.substring(6, 8));
  return '$g ${_aylar[a - 1]} $y';
}

String puanYazisi(KayitOzeti o) => switch (o.durum) {
      'puanlandi' => 'puan ${o.puan} (${puanAdlari[o.puan ?? 0]})',
      'hatirlamiyorum' => 'hatırlamıyorum',
      _ => 'PUAN VERİLMEDİ',
    };

class KayitlarSayfasi extends StatefulWidget {
  const KayitlarSayfasi({super.key});

  @override
  State<KayitlarSayfasi> createState() => _KayitlarSayfasiState();
}

class _KayitlarSayfasiState extends State<KayitlarSayfasi> {
  List<KayitOzeti> _kayitlar = [];
  bool _yukleniyor = true;
  String _klasor = '';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final klasor = (await recordingsDirectory()).path;
      final liste = await kayitlariListeleArkaPlanda(klasor);
      if (mounted) {
        setState(() {
          _klasor = klasor;
          _kayitlar = liste;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
      _mesaj('Kayıtlar okunamadı: $e');
    }
  }

  void _mesaj(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // Değişen gün dosyalarını Belgeler/Mikromobilite klasörüne yeniden kopyala
  Future<void> _kopyala(List<String> yollar) async {
    final sorun = await telefonaKopyala([for (final y in yollar) if (File(y).existsSync()) File(y)]);
    if (sorun != null) _mesaj(sorun);
  }

  Future<void> _paylas(String yol, String metin) async {
    if (!File(yol).existsSync()) {
      _mesaj('Dosya bulunamadı');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(yol, mimeType: 'application/geopackage+sqlite3')], text: metin));
  }

  // Ad verme, puanlama, silme: hata olursa söylenir; liste her durumda dosyadan yeniden okunur
  Future<void> _islem(String hataMetni, Future<void> Function() islem) async {
    try {
      await islem();
    } catch (e) {
      _mesaj('$hataMetni: $e');
    } finally {
      if (mounted) _yukle();
    }
  }

  Future<void> _adVer(KayitOzeti o) async {
    final ad = await showDialog<String>(context: context, builder: (_) => _KesitAdiPenceresi(kesit: o.kesit!, ad: o.kesitAdi));
    if (ad == null) return;
    await _islem('Kesit adı kaydedilemedi', () async {
      await kesitAdiVerArkaPlanda(_klasor, o.kesit!, ad, o.test);
      await _kopyala([for (final f in gunDosyalari(_klasor, test: o.test)) f.path]);
    });
  }

  Future<void> _puanVer(KayitOzeti o) async {
    final secim = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('${kesitBasligi(o.kesit, o.kesitAdi)}: konfor puanı'),
        children: [
          for (var p = 5; p >= 1; p--)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, p), child: Text('$p  ${puanAdlari[p]}', style: const TextStyle(fontSize: 16))),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 0), child: const Text('Hatırlamıyorum', style: TextStyle(fontSize: 16))),
        ],
      ),
    );
    if (secim == null) return;
    await _islem('Puan kaydedilemedi', () async {
      await puanYazArkaPlanda(o.insanYol, o.kayitNo, secim == 0 ? null : secim);
      await _kopyala([o.insanYol]);
    });
  }

  Future<void> _sil(KayitOzeti o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kayıt silinsin mi?'),
        content: Text('${kesitBasligi(o.kesit, o.kesitAdi)}, ${o.baslangicYerel}\n\n'
            'Kayıt bu günün ham ve işaret/puan dosyalarından silinir. Belgeler klasöründeki eski kopya kendiliğinden silinmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    await _islem('Kayıt silinemedi', () async {
      await kayitSilArkaPlanda(o.hamYol, o.insanYol, o.kayitNo, _klasor, o.test);
      await _kopyala([o.hamYol, o.insanYol]);
    });
  }

  Future<void> _hepsiniKopyala() async {
    final sorun = await tumKayitlariKopyala(uzerineYaz: true);
    _mesaj(sorun ?? 'Kayıtlar $telefonKlasoru klasörüne kopyalandı');
  }

  @override
  Widget build(BuildContext context) {
    // Günlere göre grupla (en yeni üstte); test kayıtları ayrı gün grubu
    final gruplar = <(String, bool), List<KayitOzeti>>{};
    for (final o in _kayitlar) {
      gruplar.putIfAbsent((o.kayitNo.substring(0, 8), o.test), () => []).add(o);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        title: const Text('Kayıtlar'),
        actions: [
          IconButton(icon: const Icon(Icons.drive_folder_upload), tooltip: '$telefonKlasoru klasörüne kopyala', onPressed: _hepsiniKopyala),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Eski kayıtlar (v1, CSV)',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordingsPage())),
          ),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Her sürüş günü iki dosyadır: "Ham dosya" Claude\'a gönderilir; "İşaret/puan dosyası" sizde kalır. '
                      'Dosyalar $telefonKlasoru klasörüne de kopyalanır. Kayda dokunun: harita. Üç nokta: kesit adı, puan, silme. '
                      'Eski (v1) CSV kayıtları sağ üstteki saat simgesinde.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF6C757D)),
                    ),
                  ),
                  if (_kayitlar.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('Henüz kayıt yok', style: TextStyle(color: Color(0xFF6C757D)))),
                    ),
                  for (final MapEntry(key: (gun, test), value: liste) in gruplar.entries) ...[
                    _gunKarti(gun, test, liste),
                    for (final o in liste) _kayitKarti(o),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _gunKarti(String gun, bool test, List<KayitOzeti> liste) {
    final puansiz = liste.where((o) => o.durum == 'puanlanmadi').length;
    return Card(
      color: test ? const Color(0xFFFFF3CD) : const Color(0xFFDDE7F3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${test ? 'TEST · ' : ''}${gunBasligi(gun)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
            Text('${liste.length} kayıt${puansiz > 0 ? ' · $puansiz kayıt puanlanmadı' : ''}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF003366)),
                  onPressed: () => _paylas(liste.first.hamYol, 'Ham veri (${gunBasligi(gun)}) - KAAN USTA'),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Ham dosyayı gönder'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF003366)),
                  onPressed: () => _paylas(liste.first.insanYol, 'İşaret ve puanlar (${gunBasligi(gun)}) - KAAN USTA'),
                  icon: const Icon(Icons.star_outline, size: 18),
                  label: const Text('İşaret/puan dosyası'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kayitKarti(KayitOzeti o) {
    final saat = o.baslangicYerel.length >= 16 ? o.baslangicYerel.substring(11, 16) : o.baslangicYerel;
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(kesitBasligi(o.kesit, o.kesitAdi), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        subtitle: Text(
          '$saat · ${yonYazisi(o.yon)} · ${o.sure.toStringAsFixed(0)} sn · ${o.uzunluk.toStringAsFixed(0)} m · '
          '${o.isaretSayisi} işaret · ${puanYazisi(o)}',
          style: TextStyle(fontSize: 12.5, color: o.durum == 'puanlanmadi' ? Colors.redAccent : null),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => KayitHaritasi(ozet: o))),
        trailing: PopupMenuButton<String>(
          onSelected: (s) => switch (s) {
            'ad' => _adVer(o),
            'puan' => _puanVer(o),
            _ => _sil(o),
          },
          itemBuilder: (_) => [
            if (o.kesit != null) const PopupMenuItem(value: 'ad', child: Text('Kesit adını değiştir')),
            const PopupMenuItem(value: 'puan', child: Text('Puan ver / değiştir')),
            const PopupMenuItem(value: 'sil', child: Text('Sil', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      ),
    );
  }
}

// Bir kaydın güzergâhı ve çukur işaretleri (kırmızı üçgen). Ölçülen sarsıntı gösterilmez.
class KayitHaritasi extends StatelessWidget {
  const KayitHaritasi({super.key, required this.ozet});
  final KayitOzeti ozet;

  @override
  Widget build(BuildContext context) {
    final o = ozet;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        title: Text(kesitBasligi(o.kesit, o.kesitAdi)),
      ),
      body: FutureBuilder<(List<(double, double)>, List<(double, double)>)>(
        future: haritaVerisiArkaPlanda(o.hamYol, o.insanYol, o.kayitNo),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Padding(padding: const EdgeInsets.all(24), child: Text('Harita verisi okunamadı: ${snap.error}', textAlign: TextAlign.center)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rota = [for (final (a, b) in snap.data!.$1) LatLng(a, b)];
          final isaretler = [for (final (a, b) in snap.data!.$2) LatLng(a, b)];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${o.baslangicYerel} · ${yonYazisi(o.yon)} · ${o.sure.toStringAsFixed(0)} sn · ${o.uzunluk.toStringAsFixed(0)} m\n'
                  '${o.isaretSayisi} çukur işareti (kırmızı üçgen) · ${puanYazisi(o)}',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: rota.length < 2
                    ? const Center(child: Text('Güzergâh yok (GPS konumu alınamadı)'))
                    : FlutterMap(
                        options: MapOptions(
                          initialCameraFit: CameraFit.coordinates(coordinates: rota, padding: const EdgeInsets.all(30), maxZoom: 18),
                        ),
                        children: [
                          sadeAltlik(),
                          PolylineLayer(polylines: [Polyline(points: rota, strokeWidth: 5, color: const Color(0xFF003366))]),
                          MarkerLayer(markers: [
                            for (final p in isaretler)
                              Marker(point: p, width: 26, height: 26, child: const Icon(Icons.change_history, color: Color(0xFFDB1E2A), size: 26)),
                          ]),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Kesit adı penceresi: yazı alanının denetleyicisini pencere kendisi tutar ve pencere tamamen kapanınca bırakır
// (pencere kapanma animasyonu sürerken bırakılırsa Flutter "used after being disposed" hatası verir)
class _KesitAdiPenceresi extends StatefulWidget {
  const _KesitAdiPenceresi({required this.kesit, required this.ad});
  final String kesit;
  final String? ad;

  @override
  State<_KesitAdiPenceresi> createState() => _KesitAdiPenceresiState();
}

class _KesitAdiPenceresiState extends State<_KesitAdiPenceresi> {
  late final TextEditingController _denetleyici = TextEditingController(text: widget.ad ?? '');

  @override
  void dispose() {
    _denetleyici.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.kesit} kesitinin adı'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _denetleyici,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Örnek: Mühürdar Caddesi', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Text('Ad, ${widget.kesit} kesitinin bütün kayıtlarına ve sonraki geçişlerine uygulanır. Boş bırakılırsa ad silinir.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF6C757D))),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        TextButton(onPressed: () => Navigator.pop(context, _denetleyici.text), child: const Text('Kaydet')),
      ],
    );
  }
}
