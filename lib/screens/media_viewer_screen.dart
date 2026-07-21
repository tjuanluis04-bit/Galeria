import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../main.dart' show rootStoragePath;
import '../utils/file_utils.dart';
import '../services/file_ops.dart';
import 'folder_picker_screen.dart';
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
    final dest = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const FolderPickerScreen(startPath: rootStoragePath),
      ),
    );
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

  static const List<double> _speeds = [
    0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0
  ];

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
    setState(() => _ready = true);
    if (widget.active) controller.play();
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

  String get _sizeLabel {
    try {
      return formatBytes(widget.file.lengthSync());
    } catch (_) {
      return '—';
    }
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
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: _togglePlay,
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(playedColor: Colors.deepPurple),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${_speed}x', style: const TextStyle(color: Colors.white)),
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
