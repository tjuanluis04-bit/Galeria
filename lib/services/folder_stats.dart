import 'dart:io';
import '../utils/file_utils.dart';

class FolderStats {
  final int images;
  final int videos;
  final int totalBytes;
  const FolderStats({required this.images, required this.videos, required this.totalBytes});
  int get total => images + videos;
}

/// Chequeos sobre el contenido de una carpeta. Todo pensado para ser
/// razonablemente rápido incluso con árboles grandes de subcarpetas.
class FolderStatsService {
  FolderStatsService._();
  static final FolderStatsService instance = FolderStatsService._();

  final Map<String, bool> _hasContentCache = {};

  /// true si la carpeta (o alguna subcarpeta, sin límite de profundidad)
  /// contiene al menos una foto o video. Se corta apenas encuentra la
  /// primera coincidencia, así que en la práctica es muy rápido salvo en
  /// árboles enormes sin ningún archivo multimedia.
  Future<bool> hasMediaRecursive(String path) async {
    final cached = _hasContentCache[path];
    if (cached != null) return cached;
    var found = false;
    try {
      final stream = Directory(path).list(recursive: true, followLinks: false);
      await for (final entity in stream) {
        if (entity is File && isMediaFile(entity.path)) {
          found = true;
          break;
        }
      }
    } catch (_) {
      found = false;
    }
    _hasContentCache[path] = found;
    return found;
  }

  void invalidate(String path) => _hasContentCache.remove(path);
  void clearCache() => _hasContentCache.clear();

  /// Cuenta solo los archivos DIRECTOS de una carpeta (no cuenta lo que haya
  /// dentro de subcarpetas), junto con el tamaño total en bytes.
  Future<FolderStats> directStats(String path) async {
    var images = 0;
    var videos = 0;
    var bytes = 0;
    try {
      final entities = Directory(path).listSync();
      for (final e in entities) {
        if (e is File) {
          if (isImageFile(e.path)) {
            images++;
          } else if (isVideoFile(e.path)) {
            videos++;
          } else {
            continue;
          }
          try {
            bytes += e.statSync().size;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return FolderStats(images: images, videos: videos, totalBytes: bytes);
  }
}
