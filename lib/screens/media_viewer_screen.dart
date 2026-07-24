import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../main.dart' show rootStoragePath;
import '../utils/file_utils.dart';
import '../services/file_ops.dart';
import '../widgets/move_picker_sheet.dart';
import 'mosaic_screen.dart';

/// Visor a pantalla completa para fotos y videos, con deslizamiento para
/// pasar al siguiente/anterior sin volver a la grilla, y acciones rápidas
/// (mover, eliminar, mosaico) directamente desde aquí.
class MediaViewerScreen extends StatefulWidget {
  final List<File> files;
  final int initialIndex;
  const MediaViewerScreen({super.key, required this.files, required this.initialIndex});

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageController;
  late List<File> _files;
  late int _index;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _files = List.of(widget.files);
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _moveCurrent() async {
    if (_files.isEmpty) return;
    final current = _files[_index];
    final dest = await showMovePickerSheet(context, startPath: rootStoragePath);
    if (dest == null) return;
    final newPath = '$dest/${folderName(current.path)}';
    final result = await FileOps.moveFile(current.path, newPath);
    if (!mounted) return;
    if (result.success) {
      _changed = true;
      final removedLast = _index == _files.length - 1;
      setState(() {
        _files.removeAt(_index);
        if (removedLast) _index = _files.length - 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Movido a ${folderName(dest)}')),
      );
      if (_files.isEmpty) Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo mover: ${result.error ?? "error desconocido"}')),
      );
    }
  }

  Future<void> _deleteCurrent() async {
    if (_files.isEmpty) return;
    final current = _files[_index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text('¿Eliminar "${folderName(current.path)}"? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true) return;
    final result = await FileOps.deleteFile(current.path);
    if (!mounted) return;
    if (result.success) {
      _changed = true;
      final removedLast = _index == _files.length - 1;
      setState(() {
        _files.removeAt(_index);
        if (removedLast) _index = _files.length - 1;
      });
      if (_files.isEmpty) Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: ${result.error ?? ""}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Sin archivos', style: TextStyle(color: Colors.white))),
      );
    }
    final current = _files[_index.clamp(0, _files.length - 1)];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text('${_index + 1} / ${_files.length}', style: const TextStyle(fontSize: 14)),
          actions: [
            if (isVideoFile(current.path))
              IconButton(
                icon: const Icon(Icons.auto_awesome_mosaic),
                tooltip: 'Crear mosaico del video',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MosaicScreen(videoPath: current.path)),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.drive_file_move_outline),
              tooltip: 'Mover a otra carpeta',
              onPressed: _moveCurrent,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: _deleteCurrent,
            ),
          ],
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: _files.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (ctx, i) {
            final file = _files[i];
            if (isVideoFile(file.path)) {
              return _InlineVideoPage(file: file, active: i == _index);
            }
            return InteractiveViewer(
              child: Center(child: Image.file(file)),
            );
          },
        ),
      ),
    );
  }
}

class _InlineVideoPage extends StatefulWidget {
  final File file;
  final bool active;
  const _InlineVideoPage({required this.file, required this.active});

  @override
  State<_InlineVideoPage> createState() => _InlineVideoPageState();
}

class _InlineVideoPageState extends State<_InlineVideoPage> {
  VideoPlayerController? _controller;
  bool _ready = false;
  double _speed = 1.0;
  BoxFit _fit = BoxFit.contain;
  bool _looping = false;
  bool _autoNext = false;
  double? _seekBubbleSeconds; // si no es null, muestra el "+10s"/"-10s" a un lado
  bool _seekBubbleLeft = false;
  Timer? _seekBubbleTimer;

  static const List<double> _speeds = [
    0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0
  ];

  static const List<BoxFit> _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.file(widget.file);
    _controller = controller;
    await controller.initialize();
    if (!mounted) return;
    controller.addListener(_onTick);
    setState(() => _ready = true);
    if (widget.active) controller.play();
  }

  bool _autoNextTriggered = false;

  void _onTick() {
    final c = _controller;
    if (c == null || !_ready) return;
    if (_autoNext &&
        !_looping &&
        !_autoNextTriggered &&
        c.value.position >= c.value.duration &&
        c.value.duration > Duration.zero) {
      _autoNextTriggered = true;
      final page = context.findAncestorStateOfType<_MediaViewerScreenState>();
      page?._pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _InlineVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final c = _controller;
    if (c == null || !_ready) return;
    if (widget.active) {
      c.play();
    } else {
      c.pause();
    }
  }

  @override
  void dispose() {
    _seekBubbleTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _controller?.setPlaybackSpeed(speed);
  }

  void _cycleFit() {
    final idx = _fits.indexOf(_fit);
    setState(() => _fit = _fits[(idx + 1) % _fits.length]);
  }

  String get _fitLabel => switch (_fit) {
        BoxFit.contain => 'Ajustar',
        BoxFit.cover => 'Rellenar',
        BoxFit.fill => 'Estirar',
        _ => 'Ajustar',
      };

  void _toggleLoop() {
    setState(() => _looping = !_looping);
    _controller?.setLooping(_looping);
    if (_looping) _autoNext = false;
  }

  void _toggleAutoNext() {
    setState(() => _autoNext = !_autoNext);
    if (_autoNext) {
      _looping = false;
      _controller?.setLooping(false);
    }
  }

  void _seekBy(Duration delta, {required bool fromLeft}) {
    final c = _controller;
    if (c == null) return;
    final target = c.value.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target);
    c.seekTo(clamped);
    _seekBubbleTimer?.cancel();
    setState(() {
      _seekBubbleSeconds = delta.inSeconds.toDouble();
      _seekBubbleLeft = fromLeft;
    });
    _seekBubbleTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _seekBubbleSeconds = null);
    });
  }

  String get _sizeLabel {
    try {
      return formatBytes(widget.file.lengthSync());
    } catch (_) {
      return '—';
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _showInfo() {
    final controller = _controller;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Información del video'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nombre: ${folderName(widget.file.path)}'),
            const SizedBox(height: 8),
            Text('Tamaño: $_sizeLabel'),
            if (_ready && controller != null) ...[
              const SizedBox(height: 8),
              Text('Duración: ${controller.value.duration}'),
              const SizedBox(height: 8),
              Text(
                  'Resolución: ${controller.value.size.width.toInt()}x${controller.value.size.height.toInt()}'),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Center(
          child: GestureDetector(
            onTap: _togglePlay,
            child: SizedBox.expand(
              child: FittedBox(
                fit: _fit,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ),
        ),
        // Zonas invisibles a los lados para doble-toque: retroceder (izquierda)
        // y adelantar (derecha) 10 segundos, sin interferir con el tap central
        // de pausar/reproducir.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.3,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () => _seekBy(const Duration(seconds: -10), fromLeft: true),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.3,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () => _seekBy(const Duration(seconds: 10), fromLeft: false),
          ),
        ),
        if (_seekBubbleSeconds != null)
          Positioned(
            left: _seekBubbleLeft ? 24 : null,
            right: _seekBubbleLeft ? null : 24,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_seekBubbleLeft ? Icons.fast_rewind : Icons.fast_forward, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('${_seekBubbleSeconds!.abs().round()}s', style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(_looping ? Icons.repeat_on : Icons.repeat, color: Colors.white),
                tooltip: 'Repetir este video',
                onPressed: _toggleLoop,
              ),
              IconButton(
                icon: Icon(
                  _autoNext ? Icons.skip_next : Icons.playlist_play,
                  color: _autoNext ? Colors.deepPurpleAccent : Colors.white,
                ),
                tooltip: 'Reproducir el siguiente al terminar',
                onPressed: _toggleAutoNext,
              ),
              IconButton(
                icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                tooltip: 'Ajuste de imagen: $_fitLabel',
                onPressed: _cycleFit,
              ),
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, color: Colors.white),
                tooltip: 'Velocidad de reproducción',
                initialValue: _speed,
                onSelected: _setSpeed,
                itemBuilder: (ctx) =>
                    _speeds.map((s) => PopupMenuItem(value: s, child: Text('${s}x'))).toList(),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white),
                onPressed: _showInfo,
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final pos = value.position;
                      final dur = value.duration;
                      final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                      return Row(
                        children: [
                          Text(_fmtDuration(pos), style: const TextStyle(color: Colors.white, fontSize: 11)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: pos.inMilliseconds.clamp(0, maxMs.round()).toDouble(),
                                min: 0,
                                max: maxMs,
                                activeColor: Colors.deepPurple,
                                inactiveColor: Colors.white24,
                                onChanged: (v) => controller.seekTo(Duration(milliseconds: v.round())),
                              ),
                            ),
                          ),
                          Text(_fmtDuration(dur), style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      );
                    },
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: _togglePlay,
                      ),
                      const Spacer(),
                      Text('${_speed}x', style: const TextStyle(color: Colors.white)),
                      const SizedBox(width: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
