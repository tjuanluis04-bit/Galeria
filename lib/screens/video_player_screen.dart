import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/file_utils.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String path;
  const VideoPlayerScreen({super.key, required this.path});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _ready = false;
  double _speed = 1.0;
  final List<double> _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _controller.setPlaybackSpeed(speed);
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  String get _sizeLabel {
    try {
      return formatBytes(File(widget.path).lengthSync());
    } catch (_) {
      return '—';
    }
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Información del video'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nombre: ${folderName(widget.path)}'),
            const SizedBox(height: 8),
            Text('Tamaño: $_sizeLabel'),
            if (_ready) ...[
              const SizedBox(height: 8),
              Text('Duración: ${_controller.value.duration}'),
              const SizedBox(height: 8),
              Text(
                  'Resolución: ${_controller.value.size.width.toInt()}x${_controller.value.size.height.toInt()}'),
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(folderName(widget.path), overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed),
            tooltip: 'Velocidad de reproducción',
            initialValue: _speed,
            onSelected: _setSpeed,
            itemBuilder: (ctx) =>
                _speeds.map((s) => PopupMenuItem(value: s, child: Text('${s}x'))).toList(),
          ),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showInfo),
        ],
      ),
      body: _ready
          ? Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: _ready
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: _togglePlay,
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        _controller,
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
            )
          : null,
    );
  }
}
