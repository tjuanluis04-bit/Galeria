import 'dart:io';
import 'shizuku_service.dart';

class FileOpResult {
  final bool success;
  final String? error;
  final bool usedShizuku;
  const FileOpResult({required this.success, this.error, this.usedShizuku = false});
}

/// Capa única para crear, renombrar, mover y borrar carpetas/archivos.
///
/// Primero intenta la operación normal con dart:io (funciona en casi todo el
/// almacenamiento gracias al permiso "Administrar almacenamiento"). Si el
/// sistema la deniega (carpetas protegidas tipo Android/data en algunos
/// dispositivos), y Shizuku está disponible, reintenta la misma operación
/// como comando de shell con privilegios de Shizuku.
class FileOps {
  static String _q(String path) => "'${path.replaceAll("'", "'\\''")}'";

  static Future<FileOpResult> createDir(String path) async {
    try {
      await Directory(path).create(recursive: true);
      return const FileOpResult(success: true);
    } catch (e) {
      final ok = await _shizukuFallback('mkdir -p ${_q(path)}');
      if (ok) return const FileOpResult(success: true, usedShizuku: true);
      return FileOpResult(success: false, error: e.toString());
    }
  }

  static Future<FileOpResult> renameDir(String oldPath, String newPath) async {
    try {
      await Directory(oldPath).rename(newPath);
      return const FileOpResult(success: true);
    } catch (e) {
      final ok = await _shizukuFallback('mv ${_q(oldPath)} ${_q(newPath)}');
      if (ok) return const FileOpResult(success: true, usedShizuku: true);
      return FileOpResult(success: false, error: e.toString());
    }
  }

  static Future<FileOpResult> deleteDir(String path) async {
    try {
      await Directory(path).delete(recursive: true);
      return const FileOpResult(success: true);
    } catch (e) {
      final ok = await _shizukuFallback('rm -rf ${_q(path)}');
      if (ok) return const FileOpResult(success: true, usedShizuku: true);
      return FileOpResult(success: false, error: e.toString());
    }
  }

  static Future<FileOpResult> deleteFile(String path) async {
    try {
      await File(path).delete();
      return const FileOpResult(success: true);
    } catch (e) {
      final ok = await _shizukuFallback('rm -f ${_q(path)}');
      if (ok) return const FileOpResult(success: true, usedShizuku: true);
      return FileOpResult(success: false, error: e.toString());
    }
  }

  static Future<FileOpResult> moveFile(String srcPath, String destPath) async {
    try {
      try {
        await File(srcPath).rename(destPath);
      } catch (_) {
        await File(srcPath).copy(destPath);
        await File(srcPath).delete();
      }
      return const FileOpResult(success: true);
    } catch (e) {
      final ok = await _shizukuFallback('mv ${_q(srcPath)} ${_q(destPath)}');
      if (ok) return const FileOpResult(success: true, usedShizuku: true);
      return FileOpResult(success: false, error: e.toString());
    }
  }

  /// Mueve una carpeta entera (con todo su contenido) a otra ubicación.
  static Future<FileOpResult> moveDir(String srcPath, String destPath) async {
    try {
      try {
        await Directory(srcPath).rename(destPath);
      } catch (_) {
        await _copyDirRecursive(Directory(srcPath), Directory(destPath));
        await Directory(srcPath).delete(recursive: true);
      }
      return const FileOpResult(success: true);
    } catch (e) {
      final ok = await _shizukuFallback('mv ${_q(srcPath)} ${_q(destPath)}');
      if (ok) return const FileOpResult(success: true, usedShizuku: true);
      return FileOpResult(success: false, error: e.toString());
    }
  }

  static Future<void> _copyDirRecursive(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final newPath = '${dest.path}/$name';
      if (entity is Directory) {
        await _copyDirRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  static Future<bool> _shizukuFallback(String command) async {
    final ready = await ShizukuService.instance.ensureReady();
    if (!ready) return false;
    return ShizukuService.instance.run(command);
  }
}
