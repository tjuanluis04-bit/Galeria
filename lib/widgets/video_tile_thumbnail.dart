import 'dart:io';
import 'package:flutter/material.dart';
import '../services/thumbnail_cache.dart';

class VideoTileThumbnail extends StatelessWidget {
  final String path;
  const VideoTileThumbnail({super.key, required this.path});

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) {
      final mm = m.toString().padLeft(2, '0');
      return '$h:$mm:$ss';
    }
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<String?>(
          future: ThumbnailCache.instance.thumbnailFor(path),
          builder: (context, snapshot) {
            final thumbPath = snapshot.data;
            if (thumbPath == null) {
              return Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.movie, size: 32),
              );
            }
            return Image.file(File(thumbPath), fit: BoxFit.cover, cacheWidth: 300);
          },
        ),
        const Positioned(
          bottom: 4,
          right: 4,
          child: Icon(Icons.play_circle_fill, color: Colors.white70),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: FutureBuilder<Duration?>(
            future: ThumbnailCache.instance.durationFor(path),
            builder: (context, durSnap) {
              final d = durSnap.data;
              if (d == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(d),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
