import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Kayıt klasörü: Android/data/<uygulama>/files/kayitlar
// Telefon USB ile bilgisayara bağlanınca da bu klasörden dosyalar kopyalanabilir.
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

// CSV ve varsa bilgi dosyasını birlikte paylaş
Future<void> shareRecording(File csv) async {
  final info = infoFileFor(csv);
  final files = [XFile(csv.path), if (await info.exists()) XFile(info.path)];
  await SharePlus.instance.share(ShareParams(files: files, text: 'Tez Sensör Verisi (CSV) - KAAN USTA'));
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
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv')).toList()
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
    await csv.delete();
    final info = infoFileFor(csv);
    if (await info.exists()) await info.delete();
    _load();
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

  // mikromobilite_20261024_011502.csv -> 24 Ekim 2026, 01:15:02 (ad farklıysa dosya adı)
  static const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  String _baslik(String ad) {
    final m = RegExp(r'_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.csv$').firstMatch(ad);
    final ay = m == null ? 0 : int.parse(m[2]!);
    if (m == null || ay < 1 || ay > 12) return ad;
    return '${int.parse(m[3]!)} ${_aylar[ay - 1]} ${m[1]}, ${m[4]}:${m[5]}:${m[6]}';
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('Henüz kayıt yok', style: TextStyle(color: Color(0xFF6C757D))))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _files.length,
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    final stat = f.statSync();
                    return Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(_baslik(f.uri.pathSegments.last), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            Text(f.path == aktifKayitYolu ? 'Kayıt sürüyor' : '${_size(stat.size)} · açmak için dokunun'),
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () => _open(f),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.share, color: Color(0xFF003366)), tooltip: 'Paylaş', onPressed: () => shareRecording(f)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: 'Sil',
                              onPressed: f.path == aktifKayitYolu ? null : () => _delete(f),
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
