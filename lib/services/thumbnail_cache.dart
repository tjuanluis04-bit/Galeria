import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter_video_info/flutter_video_info.dart';

/// Genera miniaturas de video reales (fotograma real, no un ícono) y las
/// guarda en la carpeta temporal de la app, y cachea la duración de cada
/// video en memoria. Cada ruta se procesa una sola vez por sesión: los
/// Future ya resueltos (o en curso) se reutilizan, así la grilla no vuelve
/// a generar nada al hacer scroll hacia atrás y adelante.
class ThumbnailCache {
  ThumbnailCache._();
  static final ThumbnailCache instance = ThumbnailCache._();

  final Map<String, Future<String?>> _thumbFutures = {};
  final Map<String, Future<Duration?>> _durationFutures = {};
  final _videoInfo = FlutterVideoInfo();
  Directory? _cacheDir;

  Future<Directory> _dir() async {
    _cacheDir ??= await getTemporaryDirectory();
    return _cacheDir!;
  }

  /// Devuelve (generando y cacheando si hace falta) la ruta a un archivo de
  /// imagen con el primer fotograma representativo del video.
  Future<String?> thumbnailFor(String videoPath) {
    return _thumbFutures.putIfAbsent(videoPath, () => _generateThumb(videoPath));
  }

  Future<String?> _generateThumb(String videoPath) async {
    try {
      int modMillis = 0;
      try {
        modMillis = File(videoPath).statSync().modified.millisecondsSinceEpoch;
      } catch (_) {}
      final dir = await _dir();
      final cacheName = 'thumb_${videoPath.hashCode}_$modMillis.jpg';
      final targetPath = '${dir.path}/$cacheName';
      final targetFile = File(targetPath);
      if (await targetFile.exists()) return targetPath;

      final generated = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        quality: 60,
      );
      if (generated == null) return null;
      if (generated != targetPath) {
        try {
          final renamed = await File(generated).rename(targetPath);
          return renamed.path;
        } catch (_) {
          return generated;
        }
      }
      return generated;
    } catch (_) {
      return null;
    }
  }

  /// Devuelve (y cachea en memoria) la duración del video.
  Future<Duration?> durationFor(String videoPath) {
    return _durationFutures.putIfAbsent(videoPath, () => _fetchDuration(videoPath));
  }

  Future<Duration?> _fetchDuration(String videoPath) async {
    try {
      final info = await _videoInfo.getVideoInfo(videoPath);
      final raw = info?.duration;
      if (raw == null) return null;
      final ms = num.tryParse(raw.toString());
      if (ms == null) return null;
      return Duration(milliseconds: ms.round());
    } catch (_) {
      return null;
    }
  }

  /// Genera los bytes de un fotograma en un instante puntual del video, para
  /// usar en el mosaico. No se cachea (cada instante es distinto).
  Future<List<int>?> frameBytesAt(String videoPath, int timeMs, {int maxWidth = 480}) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        quality: 70,
        timeMs: timeMs,
      );
    } catch (_) {
      return null;
    }
  }

  void clearMemoryCache() {
    _thumbFutures.clear();
    _durationFutures.clear();
  }
}
