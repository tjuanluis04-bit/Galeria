import 'package:path_provider/path_provider.dart';
import '../main.dart' show rootStoragePath;

class StorageRoot {
  final String label;
  final String path;
  const StorageRoot({required this.label, required this.path});
}

/// Detecta las "raíces" de almacenamiento del celular: la memoria interna
/// (siempre) y, si existe, la tarjeta SD. Usa una carpeta que Android reserva
/// para cada app dentro de cada unidad de almacenamiento
/// (Android/data/<paquete>/files) y le recorta ese sufijo para llegar a la
/// raíz real de esa unidad — es la forma estándar de detectar la SD sin
/// pedir permisos adicionales.
class StorageRoots {
  static Future<List<StorageRoot>> detect() async {
    final roots = <StorageRoot>[
      const StorageRoot(label: 'Almacenamiento interno', path: rootStoragePath),
    ];
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs == null) return roots;
      var sdCount = 0;
      for (final dir in dirs) {
        final marker = RegExp(r'^(.*)/Android/data/.*$');
        final match = marker.firstMatch(dir.path);
        final root = match?.group(1);
        if (root == null || root == rootStoragePath) continue;
        if (roots.any((r) => r.path == root)) continue;
        sdCount++;
        roots.add(StorageRoot(
          label: sdCount == 1 ? 'Tarjeta SD' : 'Tarjeta SD $sdCount',
          path: root,
        ));
      }
    } catch (_) {
      // Si falla la detección, seguimos solo con el almacenamiento interno.
    }
    return roots;
  }
}
