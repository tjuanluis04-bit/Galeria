import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/thumbnail_cache.dart';
import '../utils/file_utils.dart';

/// Genera una imagen tipo "contact sheet": una grilla con fotogramas
/// tomados a lo largo de todo el video, con la cantidad de imágenes y el
/// rango de tiempo (inicio/fin) ajustables por el usuario.
class MosaicScreen extends StatefulWidget {
  final String videoPath;
  const MosaicScreen({super.key, required this.videoPath});

  @override
  State<MosaicScreen> createState() => _MosaicScreenState();
}

class _MosaicScreenState extends State<MosaicScreen> {
  Duration? _duration;
  bool _loadingDuration = true;

  int _tileCount = 9;
  double _startPct = 0;
  double _endPct = 100;

  bool _generating = false;
  double _progress = 0;
  Uint8List? _resultBytes;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _loadDuration();
  }

  Future<void> _loadDuration() async {
    final d = await ThumbnailCache.instance.durationFor(widget.videoPath);
    if (!mounted) return;
    setState(() {
      _duration = d;
      _loadingDuration = false;
    });
  }

  List<int> _computeTimestamps() {
    final totalMs = _duration?.inMilliseconds ?? 0;
    if (totalMs <= 0) return List.filled(_tileCount, 0);
    final startMs = (totalMs * (_startPct / 100)).round();
    final endMs = (totalMs * (_endPct / 100)).round();
    final span = (endMs - startMs).clamp(0, totalMs);
    final times = <int>[];
    for (var i = 0; i < _tileCount; i++) {
      final t = _tileCount == 1 ? startMs + span ~/ 2 : startMs + (span * i / (_tileCount - 1)).round();
      times.add(t.clamp(0, totalMs));
    }
    return times;
  }

  int _columnsFor(int count) {
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    if (count <= 16) return 4;
    return 5;
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _progress = 0;
      _resultBytes = null;
      _savedPath = null;
    });

    final times = _computeTimestamps();
    final cols = _columnsFor(_tileCount);
    final rows = (_tileCount / cols).ceil();
    const cellW = 240.0;
    const cellH = 240.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, cellW * cols, cellH * rows));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cellW * cols, cellH * rows),
      Paint()..color = Colors.black,
    );

    for (var i = 0; i < times.length; i++) {
      final bytes = await ThumbnailCache.instance.frameBytesAt(widget.videoPath, times[i], maxWidth: 480);
      if (bytes != null) {
        try {
          final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
          final frame = await codec.getNextFrame();
          final img = frame.image;
          final col = i % cols;
          final row = i ~/ cols;
          final dstRect = Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);

          final srcAspect = img.width / img.height;
          const dstAspect = cellW / cellH;
          Rect srcRect;
          if (srcAspect > dstAspect) {
            final srcW = img.height * dstAspect;
            final offsetX = (img.width - srcW) / 2;
            srcRect = Rect.fromLTWH(offsetX, 0, srcW, img.height.toDouble());
          } else {
            final srcH = img.width / dstAspect;
            final offsetY = (img.height - srcH) / 2;
            srcRect = Rect.fromLTWH(0, offsetY, img.width.toDouble(), srcH);
          }
          canvas.drawImageRect(img, srcRect, dstRect, Paint());
          canvas.drawRect(
            dstRect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.black,
          );
        } catch (_) {
          // Si un fotograma puntual falla, se deja esa celda en negro y se sigue.
        }
      }
      if (mounted) setState(() => _progress = (i + 1) / times.length);
    }

    final picture = recorder.endRecording();
    final fullImage = await picture.toImage((cellW * cols).round(), (cellH * rows).round());
    final byteData = await fullImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    if (!mounted) return;
    setState(() {
      _resultBytes = pngBytes;
      _generating = false;
    });
  }

  Future<void> _save() async {
    final bytes = _resultBytes;
    if (bytes == null) return;
    try {
      final dir = Directory(parentPath(widget.videoPath));
      final base = folderName(widget.videoPath).replaceAll(RegExp(r'\.[^.]+$'), '');
      var target = File('${dir.path}/${base}_mosaico.jpg');
      var counter = 1;
      while (await target.exists()) {
        target = File('${dir.path}/${base}_mosaico_$counter.jpg');
        counter++;
      }
      await target.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _savedPath = target.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardado junto al video: ${folderName(target.path)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mosaico del video')),
      body: _loadingDuration
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folderName(widget.videoPath), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    _duration == null
                        ? 'No se pudo leer la duración del video'
                        : 'Duración: ${_duration!.toString().split('.').first}',
                  ),
                  const SizedBox(height: 20),
                  Text('Cantidad de imágenes en el mosaico: $_tileCount'),
                  Slider(
                    value: _tileCount.toDouble(),
                    min: 4,
                    max: 25,
                    divisions: 21,
                    label: '$_tileCount',
                    onChanged: (v) => setState(() => _tileCount = v.round()),
                  ),
                  const SizedBox(height: 8),
                  Text('Rango del video a capturar: ${_startPct.round()}% - ${_endPct.round()}%'),
                  const Text(
                    'Útil para saltarte la intro o el final si no aportan nada.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  RangeSlider(
                    values: RangeValues(_startPct, _endPct),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    labels: RangeLabels('${_startPct.round()}%', '${_endPct.round()}%'),
                    onChanged: (v) => setState(() {
                      _startPct = v.start;
                      _endPct = v.end;
                    }),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _generating ? null : _generate,
                    icon: const Icon(Icons.auto_awesome_mosaic),
                    label: Text(_generating ? 'Generando…' : 'Generar mosaico'),
                  ),
                  if (_generating) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _progress),
                  ],
                  if (_resultBytes != null) ...[
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_resultBytes!),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Guardar junto al video'),
                    ),
                    if (_savedPath != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Guardado en: $_savedPath',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
