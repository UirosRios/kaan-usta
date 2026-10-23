import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// İnternetten yüklenen logoyu, resmin kendi saydam / beyaz kenar boşluklarını kırparak
// verilen alanı tam dolduracak şekilde çizer. İnternet yoksa (sahada) boş kalır.
class TrimmedLogo extends StatefulWidget {
  const TrimmedLogo({super.key, required this.url});
  final String url;

  @override
  State<TrimmedLogo> createState() => _TrimmedLogoState();
}

class _TrimmedLogoState extends State<TrimmedLogo> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage, onError: (_, _) {});
  ImageInfo? _info;
  Rect? _content;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream?.removeListener(_listener);
    _stream = NetworkImage(widget.url).resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener);
  }

  Future<void> _onImage(ImageInfo info, bool _) async {
    final content = await logoContentBounds(info.image);
    if (!mounted) {
      info.dispose();
      return;
    }
    setState(() {
      _info?.dispose();
      _info = info;
      _content = content;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info, content = _content;
    if (info == null || content == null) return const SizedBox.expand();
    return CustomPaint(size: Size.infinite, painter: _LogoPainter(info.image, content));
  }
}

// Logonun dolu kısmını kapsayan dikdörtgen: saydam ve beyaza yakın pikseller kenar boşluğu sayılır
Future<Rect> logoContentBounds(ui.Image image) async {
  final full = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return full;
  final Uint8List px = data.buffer.asUint8List();
  final w = image.width, h = image.height;
  int left = w, right = -1, top = h, bottom = -1;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      if (px[i + 3] < 32 || (px[i] > 235 && px[i + 1] > 235 && px[i + 2] > 235)) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  if (right < left || bottom < top) return full;
  return Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.image, this.src);
  final ui.Image image;
  final Rect src;

  @override
  void paint(Canvas canvas, Size size) {
    // Dolu kısım alanın içine sığdırılır ve ortalanır (daire biçimli logo daireyi tam doldurur)
    final double scale = (size.width / src.width) < (size.height / src.height) ? size.width / src.width : size.height / src.height;
    final dst = Rect.fromCenter(center: size.center(Offset.zero), width: src.width * scale, height: src.height * scale);
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.image != image || old.src != src;
}
