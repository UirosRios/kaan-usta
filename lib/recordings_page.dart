import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'puanlama.dart';

// Kayıt klasörü: Android/data/<uygulama>/files/kayitlar. Kayıt bitince dosyalar telefonun
// Belgeler/Mikromobilite klasörüne de kopyalanır (telefonToKopyala): dosya yöneticisinden ve USB ile görünür.
Future<Directory> recordingsDirectory() async {
  final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/kayitlar');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

// Şu an kaydı süren dosya (ana ekran ayarlar): Kayıtlar sayfasında silinemez
String? aktifKayitYolu;

// Kayda ait cihaz/sensör bilgi dosyası (aynı ad + _bilgi.txt)
File infoFileFor(File csv) => File(csv.path.replaceAll(RegExp(r'\.csv$'), '_bilgi.txt'));

// Bir kaydın var olan dosyaları: CSV, _bilgi.txt, _puan.csv
Future<List<File>> kayitDosyalari(File csv) async =>
    [for (final f in [csv, infoFileFor(csv), puanFileFor(csv)]) if (await f.exists()) f];

// CSV, bilgi ve varsa puan dosyasını birlikte paylaş
Future<void> shareRecording(File csv) async {
  final files = [for (final f in await kayitDosyalari(csv)) XFile(f.path)];
  await SharePlus.instance.share(ShareParams(files: files, text: 'Tez Sensör Verisi (CSV) - KAAN USTA'));
}

// Telefonun Belgeler/Mikromobilite klasörü (MainActivity.kt)
const String telefonKlasoru = 'Belgeler/Mikromobilite';
const MethodChannel _dosyaKanali = MethodChannel('kaan_usta/dosya');

// Dosyaları Belgeler/Mikromobilite klasörüne kopyala. uzerineYaz = false: önceden kopyalananlar atlanır.
// Sorun varsa kullanıcıya gösterilecek açıklama, yoksa null döner.
Future<String?> telefonaKopyala(List<File> dosyalar, {bool uzerineYaz = true}) async {
  if (dosyalar.isEmpty) return null;
  try {
    final yanit = await _dosyaKanali.invokeMapMethod<String, dynamic>(
        'disaAktar', {'yollar': [for (final f in dosyalar) f.path], 'uzerineYaz': uzerineYaz});
    if (yanit == null) return null;
    if (yanit['izin'] == false) return 'Kayıtları $telefonKlasoru klasörüne kopyalamak için dosya izni verin, sonra tekrar deneyin.';
    if (yanit['hata'] != null) return '$telefonKlasoru klasörüne kopyalanamadı: ${yanit['hata']}';
    return null;
  } catch (e) {
    return '$telefonKlasoru klasörüne kopyalanamadı: $e';
  }
}

// Bütün kayıtları (süren kayıt hariç) kopyala
Future<String?> tumKayitlariKopyala({bool uzerineYaz = false}) async {
  final dir = await recordingsDirectory();
  final csvler = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv') && !f.path.endsWith('_puan.csv'));
  final dosyalar = <File>[
    for (final csv in csvler)
      if (csv.path != aktifKayitYolu) ...await kayitDosyalari(csv),
  ];
  return telefonaKopyala(dosyalar, uzerineYaz: uzerineYaz);
}

// Geçmiş kayıtlar: listele, yeniden paylaş, sil
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await recordingsDirectory();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv') && !f.path.endsWith('_puan.csv')).toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // dosya adı tarih içerdiği için en yeni üstte
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
    }
  }

  Future<void> _delete(File csv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kayıt silinsin mi?'),
        content: Text(csv.uri.pathSegments.last),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    for (final f in await kayitDosyalari(csv)) {
      await f.delete();
    }
    _load();
  }

  Future<void> _puanla(File csv) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PuanlamaSayfasi(csv: csv)));
    final sorun = await telefonaKopyala(await kayitDosyalari(csv));
    if (sorun != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sorun)));
    _load();
  }

  Future<void> _hepsiniKopyala() async {
    final sorun = await tumKayitlariKopyala(uzerineYaz: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sorun ?? 'Kayıtlar $telefonKlasoru klasörüne kopyalandı')));
    }
  }

  // CSV'yi telefondaki bir uygulamayla aç (Excel, Google E-Tablolar vb.)
  Future<void> _open(File csv) async {
    var result = await OpenFilex.open(csv.path, type: 'text/csv');
    // Bazı uygulamalar CSV'yi yalnızca Excel türüyle tanır
    if (result.type == ResultType.noAppToOpen) result = await OpenFilex.open(csv.path, type: 'application/vnd.ms-excel');
    if (result.type != ResultType.done && mounted) {
      final text = result.type == ResultType.noAppToOpen
          ? 'CSV açabilecek uygulama bulunamadı (Excel veya Google E-Tablolar yükleyin ya da Paylaş ile gönderin)'
          : 'Dosya açılamadı: ${result.message}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  // mikromobilite_20261024_011502.csv -> 24 Ekim 2026, 01:15:02; test_ önekli -> TEST · ... (ad farklıysa dosya adı)
  static const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  String _baslik(String ad) {
    final m = RegExp(r'_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.csv$').firstMatch(ad);
    final ay = m == null ? 0 : int.parse(m[2]!);
    if (m == null || ay < 1 || ay > 12) return ad;
    // Test sürüşü (Ayarlar, sanal GPS): test_mikromobilite_....csv
    final test = ad.startsWith('test_') ? 'TEST · ' : '';
    return '$test${int.parse(m[3]!)} ${_aylar[ay - 1]} ${m[1]}, ${m[4]}:${m[5]}:${m[6]}';
  }

  String _size(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(0)} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        title: const Text('Kayıtlar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_folder_upload),
            tooltip: '$telefonKlasoru klasörüne kopyala',
            onPressed: _hepsiniKopyala,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('Henüz kayıt yok', style: TextStyle(color: Color(0xFF6C757D))))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _files.length + 1,
                  itemBuilder: (context, sira) {
                    if (sira == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Text(
                          'Kayıtlar telefonun $telefonKlasoru klasörüne de kopyalanır (dosya yöneticisi veya USB). '
                          'Yıldız: sürüşü konfor açısından puanla.',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF6C757D)),
                        ),
                      );
                    }
                    final f = _files[sira - 1];
                    final stat = f.statSync();
                    final puanli = puanFileFor(f).existsSync();
                    final suruyor = f.path == aktifKayitYolu;
                    return Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(_baslik(f.uri.pathSegments.last), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            Text(suruyor ? 'Kayıt sürüyor' : '${_size(stat.size)} · ${puanli ? 'puanlandı' : 'puanlanmadı'} · açmak için dokunun'),
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () => _open(f),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(puanli ? Icons.star : Icons.star_border, color: const Color(0xFFFD7E14)),
                              tooltip: 'Konfor puanla',
                              onPressed: suruyor ? null : () => _puanla(f),
                            ),
                            IconButton(icon: const Icon(Icons.share, color: Color(0xFF003366)), tooltip: 'Paylaş', onPressed: () => shareRecording(f)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: 'Sil',
                              onPressed: suruyor ? null : () => _delete(f),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
