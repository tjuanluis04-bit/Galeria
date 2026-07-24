import 'dart:io';
import 'package:flutter/material.dart';
import '../services/file_ops.dart';
import '../services/category_service.dart';
import '../utils/file_utils.dart';

/// Abre el panel de "mover a" como una hoja que se desliza encima del
/// contenido actual (foto/video o grilla), en vez de navegar a otra pantalla
/// completa. Devuelve la ruta elegida, o null si se canceló.
Future<String?> showMovePickerSheet(BuildContext context, {required String startPath}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx2, scrollController) => _MovePickerContent(
        startPath: startPath,
        scrollController: scrollController,
      ),
    ),
  );
}

class _MovePickerContent extends StatefulWidget {
  final String startPath;
  final ScrollController scrollController;
  const _MovePickerContent({required this.startPath, required this.scrollController});

  @override
  State<_MovePickerContent> createState() => _MovePickerContentState();
}

class _MovePickerContentState extends State<_MovePickerContent> {
  late String _current;
  List<Directory> _folders = [];
  bool _loading = true;
  String _selectedCategory = 'Todas';

  @override
  void initState() {
    super.initState();
    _current = widget.startPath;
    CategoryService.instance.load().then((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final entities = Directory(_current)
          .listSync()
          .whereType<Directory>()
          .where((d) => !folderName(d.path).startsWith('.'))
          .toList();
      entities.sort((a, b) =>
          folderName(a.path).toLowerCase().compareTo(folderName(b.path).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _folders = entities;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _folders = [];
        _loading = false;
      });
    }
  }

  void _open(String path) {
    setState(() {
      _current = path;
      _selectedCategory = 'Todas';
    });
    _load();
  }

  Future<void> _createFolderHere() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva carpeta'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Crear')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final result = await FileOps.createDir('$_current/${name.trim()}');
    if (result.success) {
      _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al crear: ${result.error}')));
    }
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej: Amor, Trabajo, Verde…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Crear')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await CategoryService.instance.createCategory(name.trim());
    if (!mounted) return;
    setState(() => _selectedCategory = name.trim());
  }

  Widget _buildCategoryPills() {
    final categories = CategoryService.instance.categoryNames;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _pill('Todas', _selectedCategory == 'Todas', () {
            setState(() => _selectedCategory = 'Todas');
          }),
          for (final c in categories)
            _pill(c, _selectedCategory == c, () {
              setState(() => _selectedCategory = c);
            }),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('+'),
            onPressed: _createCategory,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildCategoryFolderList() {
    final paths = CategoryService.instance.foldersIn(_selectedCategory);
    if (paths.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay carpetas en esta categoría.\n'
            'Andá a los "⋮" de una carpeta y elegí "Categorizar" para agregarla acá.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: paths.length,
      itemBuilder: (ctx, i) {
        final path = paths[i];
        final exists = Directory(path).existsSync();
        return ListTile(
          leading: Icon(Icons.folder, color: exists ? Colors.amber : Colors.grey),
          title: Text(folderName(path)),
          subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
          enabled: exists,
          onTap: exists ? () => Navigator.pop(context, path) : null,
        );
      },
    );
  }

  Widget _buildNestedBrowser() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_folders.isEmpty) {
      return const Center(child: Text('Sin subcarpetas aquí'));
    }
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: _folders.length,
      itemBuilder: (ctx, i) {
        final dir = _folders[i];
        return ListTile(
          leading: const Icon(Icons.folder, color: Colors.amber),
          title: Text(folderName(dir.path)),
          onTap: () => _open(dir.path),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRoot = _current == widget.startPath;
    final showingCategory = _selectedCategory != 'Todas';
    return SafeArea(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (!showingCategory && !isRoot)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: () => _open(parentPath(_current)),
                  ),
                Expanded(
                  child: Text(
                    showingCategory ? 'Categoría: $_selectedCategory' : 'Mover a: ${folderName(_current)}',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildCategoryPills(),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(
            child: showingCategory ? _buildCategoryFolderList() : _buildNestedBrowser(),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (!showingCategory)
                  OutlinedButton.icon(
                    onPressed: _createFolderHere,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Nueva'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                if (!showingCategory)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _current),
                    child: const Text('Seleccionar esta carpeta'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
