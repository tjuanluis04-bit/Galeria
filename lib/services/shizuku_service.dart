import 'package:shizuku_api/shizuku_api.dart';

/// Envuelve Shizuku para usarlo como respaldo cuando el sistema deniega una
/// operación de archivos incluso con el permiso "Administrar almacenamiento"
/// concedido (por ejemplo, algunas subcarpetas protegidas dentro de
/// Android/data o Android/obb en ciertos dispositivos).
///
/// IMPORTANTE / limitación conocida: el plugin `shizuku_api` ejecuta el
/// comando y devuelve únicamente si tuvo éxito o no (no la salida de texto
/// del comando). Por eso Shizuku se usa aquí solo para operaciones de
/// escritura (crear, mover, renombrar, borrar), donde éxito/fracaso es
/// suficiente. La LECTURA/listado de carpetas sigue haciéndose con dart:io,
/// que ya funciona en la enorme mayoría de rutas gracias al permiso
/// "Administrar almacenamiento".
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
}
