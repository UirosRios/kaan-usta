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
                        title: Text(f.uri.pathSegments.last, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text('${_size(stat.size)} · açmak için dokunun'),
                        onTap: () => _open(f),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.share, color: Color(0xFF003366)), tooltip: 'Paylaş', onPressed: () => shareRecording(f)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), tooltip: 'Sil', onPressed: () => _delete(f)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
