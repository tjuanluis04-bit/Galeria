import 'dart:io';
import 'package:shizuku_api/shizuku_api.dart';

class ShellEntry {
  final String name;
  final bool isDir;
  final int size;
  const ShellEntry({required this.name, required this.isDir, required this.size});
}

/// Envuelve Shizuku para usarlo como respaldo cuando el sistema deniega una
/// operación de archivos incluso con el permiso "Administrar almacenamiento"
/// concedido (por ejemplo, algunas subcarpetas protegidas dentro de
/// Android/data o Android/obb en ciertos dispositivos).
///
/// IMPORTANTE / limitación conocida: el plugin `shizuku_api` ejecuta el
/// comando y devuelve únicamente si tuvo éxito o no (no la salida de texto
/// del comando). Por eso, para poder LISTAR una carpeta protegida (algo que
/// de otra forma sería imposible con este plugin), usamos un truco: le
/// pedimos al comando que redirija su salida a un archivo de texto ubicado
/// en una carpeta normal (accesible sin Shizuku, como Download), y después
/// leemos ese archivo con dart:io de forma común. Así sí conseguimos el
/// contenido real del listado.
class ShizukuService {
  ShizukuService._();
  static final ShizukuService instance = ShizukuService._();

  final ShizukuApi _api = ShizukuApi();
  bool _permissionGranted = false;
  bool _checkedOnce = false;

  bool get isAvailable => _permissionGranted;

  /// Verifica que Shizuku esté corriendo y con permiso concedido. Si hace
  /// falta, dispara el diálogo de permiso de Shizuku (solo la primera vez
  /// que se necesite, o cuando se llama explícitamente).
  Future<bool> ensureReady({bool forcePrompt = false}) async {
    try {
      final running = await _api.pingBinder() ?? false;
      if (!running) {
        _permissionGranted = false;
        _checkedOnce = true;
        return false;
      }
      var granted = await _api.checkPermission() ?? false;
      if (!granted || forcePrompt) {
        granted = await _api.requestPermission() ?? false;
      }
      _permissionGranted = granted;
      _checkedOnce = true;
      return granted;
    } catch (_) {
      _permissionGranted = false;
      _checkedOnce = true;
      return false;
    }
  }

  bool get checkedOnce => _checkedOnce;

  static String _q(String path) => "'${path.replaceAll("'", "'\\''")}'";

  /// Ejecuta un comando de shell con privilegios de Shizuku (equivalentes a
  /// `adb shell`). Devuelve true si el comando terminó con éxito.
  Future<bool> run(String command) async {
    try {
      final result = await _api.runCommand(command);
      final text = result?.toString().toLowerCase() ?? '';
      if (text.isEmpty) return true;
      if (text.contains('fail') || text.contains('error') || text.contains('denied')) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Lista el contenido de una carpeta protegida usando Shizuku, aunque el
  /// plugin no exponga la salida del comando directamente.
  Future<List<ShellEntry>?> listDir(String path) async {
    final ready = await ensureReady();
    if (!ready) return null;
    Directory? tmpDir;
    File? tmpFile;
    try {
      tmpDir = await Directory('${Directory.systemTemp.path}/galeria_shizuku').create(recursive: true);
    } catch (_) {
      try {
        tmpDir = await Directory('/storage/emulated/0/Download/.galeria_tmp').create(recursive: true);
      } catch (_) {
        return null;
      }
    }
    final tmpPath = '${tmpDir.path}/listing_${DateTime.now().microsecondsSinceEpoch}.txt';
    tmpFile = File(tmpPath);
    try {
      final ok = await run('ls -la ${_q(path)} > ${_q(tmpPath)} 2>&1');
      if (!ok && !await tmpFile.exists()) return null;
      if (!await tmpFile.exists()) return null;
      final lines = await tmpFile.readAsLines();
      final entries = <ShellEntry>[];
      for (final line in lines) {
        final entry = _parseLsLine(line);
        if (entry != null) entries.add(entry);
      }
      return entries;
    } catch (_) {
      return null;
    } finally {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
  }

  ShellEntry? _parseLsLine(String line) {
    if (line.trim().isEmpty) return null;
    if (!line.startsWith('d') && !line.startsWith('-') && !line.startsWith('l')) return null;
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 8) return null;
    final name = parts.sublist(8).join(' ');
    if (name.isEmpty || name == '.' || name == '..') return null;
    if (name.startsWith('.')) return null;
    final isDir = line.startsWith('d');
    final size = int.tryParse(parts[4]) ?? 0;
    // Los symlinks (ej: "nombre -> destino") se muestran, pero se recorta la flecha.
    final cleanName = name.contains(' -> ') ? name.split(' -> ').first : name;
    return ShellEntry(name: cleanName, isDir: isDir, size: size);
  }
}
