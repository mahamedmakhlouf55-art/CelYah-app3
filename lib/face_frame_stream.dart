import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Displays ESP32 /frame as raw little-endian RGB565, 240x240.
/// TEST creates a local image without Wi-Fi, to distinguish rendering from networking.
class CelyahLiveFace extends StatefulWidget {
  final String baseUrl;
  const CelyahLiveFace({super.key, required this.baseUrl});
  @override
  State<CelyahLiveFace> createState() => _CelyahLiveFaceState();
}

class _CelyahLiveFaceState extends State<CelyahLiveFace> {
  final http.Client _client = http.Client();
  ui.Image? _frame;
  Timer? _timer;
  bool _busy = false;
  bool _test = false;
  int _generation = 0;
  String _status = 'جاري الاتصال...';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant CelyahLiveFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) _start();
  }

  void _start() {
    _timer?.cancel();
    ++_generation;
    _busy = false;
    if (_test) return;
    _fetch();
    _timer = Timer.periodic(const Duration(milliseconds: 350), (_) => _fetch());
  }

  Future<ui.Image> _decode(Uint8List raw) async {
    if (raw.length != 115200) {
      throw FormatException('حجم الإطار ${raw.length} بدل 115200 بايت');
    }
    final rgba = Uint8List(240 * 240 * 4);
    for (int i = 0; i < 57600; i++) {
      final pixel = raw[i * 2] | (raw[i * 2 + 1] << 8);
      final j = i * 4;
      final r = (pixel >> 11) & 31;
      final g = (pixel >> 5) & 63;
      final b = pixel & 31;
      rgba[j] = (r << 3) | (r >> 2);
      rgba[j + 1] = (g << 2) | (g >> 4);
      rgba[j + 2] = (b << 3) | (b >> 2);
      rgba[j + 3] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, 240, 240, ui.PixelFormat.rgba8888,
        (image) => completer.complete(image));
    return completer.future;
  }

  void _show(ui.Image image, int generation, String status) {
    if (!mounted || generation != _generation) {
      image.dispose();
      return;
    }
    final old = _frame;
    setState(() {
      _frame = image;
      _status = status;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  Future<void> _fetch() async {
    if (_busy || !mounted || _test) return;
    final generation = _generation;
    _busy = true;
    try {
      final base = widget.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$base/frame');
      final response = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode} من $uri');
      }
      final image = await _decode(response.bodyBytes);
      _show(image, generation, 'متصل · بث الوش مباشر');
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _status = 'خطأ البث: $e');
      }
      debugPrint('CelYah face: $e');
    } finally {
      if (generation == _generation) _busy = false;
    }
  }

  Future<void> _toggleTest() async {
    _timer?.cancel();
    final generation = ++_generation;
    _busy = false;
    setState(() {
      _test = !_test;
      _status = _test ? 'TEST محلي: لا يعتمد على Wi-Fi' : 'جاري إعادة الاتصال...';
    });
    if (!_test) {
      _start();
      return;
    }
    // Distinct magenta/lavender eyes, generated locally in RGB565.
    final bytes = Uint8List(115200);
    for (int y = 0; y < 240; y++) {
      for (int x = 0; x < 240; x++) {
        final eye1 = (x - 70) * (x - 70) / 1600 + (y - 115) * (y - 115) / 2600 < 1;
        final eye2 = (x - 170) * (x - 170) / 1600 + (y - 115) * (y - 115) / 2600 < 1;
        final color = (eye1 || eye2) ? 0xD39F : 0x0000;
        final i = (y * 240 + x) * 2;
        bytes[i] = color & 0xFF;
        bytes[i + 1] = color >> 8;
      }
    }
    try {
      final image = await _decode(bytes);
      _show(image, generation, 'TEST ناجح: عرض RGB565 يعمل');
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _status = 'TEST فشل: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.close();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Stack(children: [
      Positioned.fill(child: _frame == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE17BFF)))
          : RawImage(image: _frame, fit: BoxFit.contain, filterQuality: FilterQuality.none)),
      Positioned(left: 8, right: 8, top: 6, child: Text(_status,
          maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE17BFF), fontSize: 11,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)]))),
      Positioned(bottom: 8, right: 8, child: TextButton(
        onPressed: _toggleTest,
        style: TextButton.styleFrom(backgroundColor: const Color(0xFF251633)),
        child: Text(_test ? 'LIVE' : 'TEST',
            style: const TextStyle(color: Color(0xFFE17BFF))))),
    ]),
  );
}
