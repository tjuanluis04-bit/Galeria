import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/thumbnail_cache.dart';
import '../utils/file_utils.dart';

/// Genera una imagen tipo "contact sheet": una grilla con fotogramas
/// tomados a lo largo de todo el video. Cantidad de imágenes, rango de
/// tiempo, filas/columnas, margen interno y marcas de tiempo son ajustables.
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

  // Filas/columnas: por defecto se calculan solas a partir de _tileCount;
  // si el usuario activa el modo manual, se respeta lo que elija.
  bool _manualGrid = false;
  int _manualCols = 3;
  int _manualRows = 3;

  // Margen interno (gutter) entre celdas.
  double _gutter = 4;
  Color _gutterColor = Colors.black;
  static const _gutterColors = [Colors.black, Colors.white, Color(0xFF424242), Colors.deepPurple];

  bool _sceneDetection = false;
  bool _showTimestamps = false;

  bool _generating = false;
  String _statusText = '';
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

  int get _effectiveCols => _manualGrid ? _manualCols : _columnsFor(_tileCount);
  int get _effectiveRows =>
      _manualGrid ? _manualRows : (_tileCount / _columnsFor(_tileCount)).ceil();
  int get _effectiveCount => _manualGrid ? _manualCols * _manualRows : _tileCount;

  int _columnsFor(int count) {
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    if (count <= 16) return 4;
    return 5;
  }

  List<int> _evenTimestamps(int count) {
    final totalMs = _duration?.inMilliseconds ?? 0;
    if (totalMs <= 0 || count <= 0) return List.filled(count, 0);
    final startMs = (totalMs * (_startPct / 100)).round();
    final endMs = (totalMs * (_endPct / 100)).round();
    final span = (endMs - startMs).clamp(0, totalMs);
    final times = <int>[];
    for (var i = 0; i < count; i++) {
      final t = count == 1 ? startMs + span ~/ 2 : startMs + (span * i / (count - 1)).round();
      times.add(t.clamp(0, totalMs));
    }
    return times;
  }

  /// Fingerprint barato de una imagen (bytes JPEG chiquitos) para comparar
  /// cuánto cambia una escena respecto a otra: brillo promedio en una
  /// cuadrícula de 8x8 celdas.
  Future<List<double>?> _fingerprint(Uint8List jpegBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(jpegBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;
      final bytes = byteData.buffer.asUint8List();
      const grid = 8;
      final cellW = (img.width / grid).ceil().clamp(1, img.width);
      final cellH = (img.height / grid).ceil().clamp(1, img.height);
      final result = <double>[];
      for (var gy = 0; gy < grid; gy++) {
        for (var gx = 0; gx < grid; gx++) {
          var sum = 0;
          var samples = 0;
          for (var y = gy * cellH; y < (gy + 1) * cellH && y < img.height; y += 2) {
            for (var x = gx * cellW; x < (gx + 1) * cellW && x < img.width; x += 2) {
              final i = (y * img.width + x) * 4;
              if (i + 2 >= bytes.length) continue;
              sum += bytes[i] + bytes[i + 1] + bytes[i + 2];
              samples++;
            }
          }
          result.add(samples == 0 ? 0 : sum / samples);
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  double _diff(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sum;
  }

  /// Modo "detección de escenas": analiza más candidatos de los necesarios y
  /// se queda con los que representan cambios reales de plano, en vez de
  /// cortar por tiempo estricto. Es una heurística simple (diferencia de
  /// brillo por bloques), no un análisis de video profesional, pero evita
  /// bastante bien los fotogramas casi idénticos.
  Future<List<int>> _sceneTimestamps(int count) async {
    final totalMs = _duration?.inMilliseconds ?? 0;
    if (totalMs <= 0 || count <= 0) return List.filled(count, 0);
    final oversample = (count * 3).clamp(count, 60);
    final candidates = _evenTimestamps(oversample);

    final fingerprints = <List<double>?>[];
    for (var i = 0; i < candidates.length; i++) {
      final bytes =
          await ThumbnailCache.instance.frameBytesAt(widget.videoPath, candidates[i], maxWidth: 64);
      fingerprints.add(bytes == null ? null : await _fingerprint(Uint8List.fromList(bytes)));
      if (mounted) {
        setState(() => _progress = (i + 1) / (candidates.length * 2));
      }
    }

    // Puntaje de cada candidato = cuánto cambia respecto al anterior válido.
    final scores = List<double>.filled(candidates.length, 0);
    List<double>? prev;
    for (var i = 0; i < candidates.length; i++) {
      final fp = fingerprints[i];
      if (fp != null && prev != null) scores[i] = _diff(fp, prev);
      if (fp != null) prev = fp;
    }
    scores[0] = scores.isEmpty ? 0 : (scores.reduce((a, b) => a > b ? a : b) * 0.5 + 1);

    final order = List<int>.generate(candidates.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final chosenIdx = (order.take(count).toList()..sort());
    return chosenIdx.map((i) => candidates[i]).toList();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _progress = 0;
      _statusText = _sceneDetection ? 'Analizando escenas…' : 'Extrayendo fotogramas…';
      _resultBytes = null;
      _savedPath = null;
    });

    final count = _effectiveCount;
    final cols = _effectiveCols;
    final rows = _effectiveRows;

    final times =
        _sceneDetection ? await _sceneTimestamps(count) : _evenTimestamps(count);

    if (mounted) setState(() => _statusText = 'Componiendo mosaico…');

    const cellW = 240.0;
    const cellH = 240.0;
    final g = _gutter;
    final totalW = cols * cellW + (cols + 1) * g;
    final totalH = rows * cellH + (rows + 1) * g;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, totalW, totalH));
    canvas.drawRect(Rect.fromLTWH(0, 0, totalW, totalH), Paint()..color = _gutterColor);

    for (var i = 0; i < times.length && i < cols * rows; i++) {
      final bytes = await ThumbnailCache.instance.frameBytesAt(widget.videoPath, times[i], maxWidth: 480);
      final col = i % cols;
      final row = i ~/ cols;
      final dstRect = Rect.fromLTWH(
        g + col * (cellW + g),
        g + row * (cellH + g),
        cellW,
        cellH,
      );
      if (bytes != null) {
        try {
          final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
          final frame = await codec.getNextFrame();
          final img = frame.image;

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
        } catch (_) {
          // Si un fotograma puntual falla, se deja esa celda vacía y se sigue.
        }
      }

      if (_showTimestamps) {
        _drawTimestamp(canvas, dstRect, times[i]);
      }

      if (mounted) setState(() => _progress = 0.5 + (i + 1) / times.length * 0.5);
    }

    final picture = recorder.endRecording();
    final fullImage = await picture.toImage(totalW.round(), totalH.round());
    final byteData = await fullImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    if (!mounted) return;
    setState(() {
      _resultBytes = pngBytes;
      _generating = false;
    });
  }

  void _drawTimestamp(Canvas canvas, Rect cell, int timeMs) {
    final label = _fmtDuration(Duration(milliseconds: timeMs));
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 6.0;
    final bgRect = Rect.fromLTWH(
      cell.left + 6,
      cell.bottom - textPainter.height - pad * 2 - 6,
      textPainter.width + pad * 2,
      textPainter.height + pad * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      Paint()..color = Colors.black54,
    );
    textPainter.paint(canvas, Offset(bgRect.left + pad, bgRect.top + pad));
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Elegir filas y columnas manualmente'),
                    subtitle: Text(_manualGrid
                        ? '$_manualCols columnas × $_manualRows filas = $_effectiveCount imágenes'
                        : 'Automático según la cantidad de imágenes'),
                    value: _manualGrid,
                    onChanged: (v) => setState(() => _manualGrid = v),
                  ),
                  if (!_manualGrid) ...[
                    Text('Cantidad de imágenes en el mosaico: $_tileCount'),
                    Slider(
                      value: _tileCount.toDouble(),
                      min: 4,
                      max: 25,
                      divisions: 21,
                      label: '$_tileCount',
                      onChanged: (v) => setState(() => _tileCount = v.round()),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Columnas: $_manualCols'),
                              Slider(
                                value: _manualCols.toDouble(),
                                min: 1,
                                max: 8,
                                divisions: 7,
                                label: '$_manualCols',
                                onChanged: (v) => setState(() => _manualCols = v.round()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Filas: $_manualRows'),
                              Slider(
                                value: _manualRows.toDouble(),
                                min: 1,
                                max: 8,
                                divisions: 7,
                                label: '$_manualRows',
                                onChanged: (v) => setState(() => _manualRows = v.round()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],

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

                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Detección de escenas (opcional)'),
                    subtitle: const Text(
                      'En vez de cortar por tiempo exacto, prioriza fotogramas donde '
                      'la escena realmente cambia. Tarda un poco más.',
                    ),
                    value: _sceneDetection,
                    onChanged: (v) => setState(() => _sceneDetection = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar marca de tiempo en cada imagen'),
                    value: _showTimestamps,
                    onChanged: (v) => setState(() => _showTimestamps = v),
                  ),

                  const SizedBox(height: 16),
                  Text('Margen interno entre imágenes: ${_gutter.round()}px',
                      style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: _gutter,
                    min: 0,
                    max: 16,
                    divisions: 16,
                    label: _gutter == 0 ? 'Sin margen' : '${_gutter.round()}px',
                    onChanged: (v) => setState(() => _gutter = v),
                  ),
                  if (_gutter > 0) ...[
                    const SizedBox(height: 8),
                    Text('Color del margen', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final c in _gutterColors)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: () => setState(() => _gutterColor = c),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _gutterColor == c ? Colors.deepPurpleAccent : Colors.grey,
                                    width: _gutterColor == c ? 3 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _generating ? null : _generate,
                    icon: const Icon(Icons.auto_awesome_mosaic),
                    label: Text(_generating ? 'Generando…' : 'Generar mosaico'),
                  ),
                  if (_generating) ...[
                    const SizedBox(height: 12),
                    Text(_statusText, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
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
