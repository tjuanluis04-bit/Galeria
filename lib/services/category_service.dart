import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda a qué "categorías" (etiquetas no reales, solo de acceso rápido)
/// pertenece cada carpeta. Se usa únicamente para filtrar la lista de
/// carpetas al momento de mover algo, no cambia nada del sistema de archivos.
class CategoryService {
  CategoryService._();
  static final CategoryService instance = CategoryService._();

  SharedPreferences? _prefs;

  /// categoría -> lista de rutas de carpetas
  Map<String, List<String>> _data = {};

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString('folderCategories');
    if (raw == null) {
      _data = {};
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _data = decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (_) {
      _data = {};
    }
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString('folderCategories', jsonEncode(_data));
  }

  List<String> get categoryNames => _data.keys.toList()..sort();

  List<String> foldersIn(String category) => List.unmodifiable(_data[category] ?? const []);

  List<String> categoriesOf(String folderPath) {
    return _data.entries.where((e) => e.value.contains(folderPath)).map((e) => e.key).toList();
  }

  Future<void> createCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _data.putIfAbsent(trimmed, () => []);
    await _save();
  }

  Future<void> addFolderToCategory(String folderPath, String category) async {
    final list = _data.putIfAbsent(category, () => []);
    if (!list.contains(folderPath)) list.add(folderPath);
    await _save();
  }

  Future<void> removeFolderFromCategory(String folderPath, String category) async {
    _data[category]?.remove(folderPath);
    await _save();
  }

  Future<void> deleteCategory(String category) async {
    _data.remove(category);
    await _save();
  }

  /// Quita todas las referencias a una carpeta (por ejemplo, si se borra o
  /// se renombra) de todas las categorías.
  Future<void> forgetFolder(String folderPath) async {
    for (final list in _data.values) {
      list.remove(folderPath);
    }
    await _save();
  }

  Future<void> renameFolder(String oldPath, String newPath) async {
    for (final list in _data.values) {
      final idx = list.indexOf(oldPath);
      if (idx != -1) list[idx] = newPath;
    }
    await _save();
  }
}
