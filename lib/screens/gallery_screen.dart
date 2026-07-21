import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart' show rootStoragePath;
import '../utils/file_utils.dart';
import '../services/file_ops.dart';
import '../services/shizuku_service.dart';
import '../widgets/video_tile_thumbnail.dart';
import 'media_viewer_screen.dart';
import 'folder_picker_screen.dart';

class GalleryScreen extends StatefulWidget {
  final String path;
  const GalleryScreen({super.key, required this.path});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Directory> _folders = [];
  List<File> _mediaFiles = [];
  bool _loading = true;
  String? _error;
  final Set<String> _selected = {};

  bool get _selectionMode => _selected.isNotEmpty;
  bool get _isRoot => widget.path == rootStoragePath;

  // Accesos rápidos a carpetas protegidas del sistema (solo se muestran en
  // la raíz). Si el listado normal falla ahí, se sugiere activar Shizuku.
  static const _quickAccess = [
    '$rootStoragePath/Android/data',
    '$rootStoragePath/Android/obb',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(widget.path);
      final entities = dir.listSync();
      final folders = <Directory>[];
      final media = <File>[];
      for (final e in entities) {
        final name = folderName(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          folders.add(e);
        } else if (e is File && isMediaFile(e.path)) {
          media.add(e);
        }
      }
      folders.sort((a, b) =>
          folderName(a.path).toLowerCase().compareTo(folderName(b.path).toLowerCase()));
      media.sort((a, b) {
        try {
          return b.statSync().modified.compareTo(a.statSync().modified);
        } catch (_) {
          return 0;
        }
      });
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _mediaFiles = media;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final isProtected = widget.path.contains('/Android/data') || widget.path.contains('/Android/obb');
      setState(() {
        _error = isProtected
            ? 'No se pudo abrir esta carpeta (protegida por el sistema).\n'
                'Probá activar Shizuku desde el botón de arriba y reintentar.\n$e'
            : 'No se pudo abrir esta carpeta.\n$e';
        _loading = false;
      });
    }
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  Future<void> _checkShizuku() async {
    final ok = await ShizukuService.instance.ensureReady(forcePrompt: true);
    if (!mounted) return;
    _showSnack(ok
        ? 'Shizuku activo: se usará como respaldo si el sistema deniega alguna operación.'
        : 'Shizuku no disponible (no está instalado/corriendo o se negó el permiso).');
  }

  Future<void> _createFolder() async {
    final name = await _promptText(title: 'Nueva carpeta', hint: 'Nombre de la carpeta');
    if (name == null || name.trim().isEmpty) return;
    final newPath = '${widget.path}/${name.trim()}';
    if (await Directory(newPath).exists()) {
      _showSnack('Ya existe una carpeta con ese nombre');
      return;
    }
    final result = await FileOps.createDir(newPath);
    if (result.success) {
      if (result.usedShizuku) _showSnack('Carpeta creada con Shizuku');
      _load();
    } else {
      _showSnack('Error al crear la carpeta: ${result.error}');
    }
  }

  Future<void> _renameFolder(Directory dir) async {
    final currentName = folderName(dir.path);
    final name = await _promptText(title: 'Renombrar carpeta', hint: 'Nuevo nombre', initial: currentName);
    if (name == null || name.trim().isEmpty || name.trim() == currentName) return;
    final newPath = '${parentPath(dir.path)}/${name.trim()}';
    final result = await FileOps.renameDir(dir.path, newPath);
    if (result.success) {
      if (result.usedShizuku) _showSnack('Renombrado con Shizuku');
      _load();
    } else {
      _showSnack('Error al renombrar: ${result.error}');
    }
  }

  Future<void> _deleteFolder(Directory dir) async {
    final confirm = await _confirm('¿Eliminar la carpeta "${folderName(dir.path)}" y todo su contenido?');
    if (confirm != true) return;
    final result = await FileOps.deleteDir(dir.path);
    if (result.success) {
      if (result.usedShizuku) _showSnack('Carpeta eliminada con Shizuku');
      _load();
    } else {
      _showSnack('Error al eliminar: ${result.error}');
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await _confirm('¿Eliminar $count elemento(s)? Esta acción no se puede deshacer.');
    if (confirm != true) return;
    var shizukuUsed = false;
    for (final p in _selected.toList()) {
      final result = await FileOps.deleteFile(p);
      if (result.usedShizuku) shizukuUsed = true;
    }
    setState(() => _selected.clear());
    _load();
    if (shizukuUsed) _showSnack('Algunos archivos se eliminaron con Shizuku');
  }

  Future<void> _moveSelected() async {
    final dest = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const FolderPickerScreen(startPath: rootStoragePath)),
    );
    if (dest == null) return;
    var errors = 0;
    var shizukuUsed = false;
    for (final p in _selected.toList()) {
      final newPath = '$dest/${folderName(p)}';
      final result = await FileOps.moveFile(p, newPath);
      if (!result.success) errors++;
      if (result.usedShizuku) shizukuUsed = true;
    }
    setState(() => _selected.clear());
    _load();
    if (errors > 0) _showSnack('$errors elemento(s) no se pudieron mover');
    if (shizukuUsed) _showSnack('Algunos archivos se movieron con Shizuku');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool?> _confirm(String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
  }

  Future<String?> _promptText({required String title, String? hint, String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Aceptar')),
        ],
      ),
    );
  }

  void _showFolderMenu(Directory dir) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Renombrar'),
              onTap: () {
                Navigator.pop(ctx);
                _renameFolder(dir);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Eliminar carpeta'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteFolder(dir);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFileInfo(File file) {
    int size = 0;
    DateTime? modified;
    try {
      final stat = file.statSync();
      size = stat.size;
      modified = stat.modified;
    } catch (_) {}
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(folderName(file.path)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tamaño: ${formatBytes(size)}'),
            if (modified != null) ...[
              const SizedBox(height: 8),
              Text('Modificado: $modified'),
            ],
            const SizedBox(height: 8),
            Text('Ruta: ${file.path}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _openViewer(int index) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(files: _mediaFiles, initialIndex: index),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selected.length} seleccionado(s)')
            : Text(_isRoot ? 'Galería' : folderName(widget.path)),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selected.clear()),
              )
            : null,
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outline),
                  tooltip: 'Mover',
                  onPressed: _moveSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Eliminar',
                  onPressed: _deleteSelected,
                ),
              ]
            : [
                if (!_isRoot)
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showFolderMenu(Directory(widget.path)),
                  ),
                IconButton(
                  icon: const Icon(Icons.security),
                  tooltip: 'Activar Shizuku (acceso a carpetas protegidas)',
                  onPressed: _checkShizuku,
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
              ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: _createFolder,
              tooltip: 'Nueva carpeta',
              child: const Icon(Icons.create_new_folder_outlined),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    if (_folders.isEmpty && _mediaFiles.isEmpty && !_isRoot) {
      return const Center(child: Text('Carpeta vacía'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          if (_isRoot)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Accesos rápidos', style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
          if (_isRoot)
            SliverList(
              delegate: SliverChildListDelegate([
                for (final p in _quickAccess)
                  ListTile(
                    leading: const Icon(Icons.folder_special, color: Colors.deepPurpleAccent),
                    title: Text(folderName(p)),
                    subtitle: const Text('Carpeta protegida del sistema'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GalleryScreen(path: p)),
                    ).then((_) => _load()),
                  ),
                const Divider(height: 1),
              ]),
            ),
          if (_folders.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final dir = _folders[i];
                  return ListTile(
                    leading: const Icon(Icons.folder, color: Colors.amber),
                    title: Text(folderName(dir.path)),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showFolderMenu(dir),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GalleryScreen(path: dir.path)),
                    ).then((_) => _load()),
                  );
                },
                childCount: _folders.length,
              ),
            ),
          if (_folders.isNotEmpty && _mediaFiles.isNotEmpty)
            const SliverToBoxAdapter(child: Divider(height: 1)),
          if (_mediaFiles.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(4),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildMediaTile(i),
                  childCount: _mediaFiles.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaTile(int index) {
    final file = _mediaFiles[index];
    final selected = _selected.contains(file.path);
    final isVideo = isVideoFile(file.path);
    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(file.path);
          return;
        }
        _openViewer(index);
      },
      onLongPress: () => _toggleSelect(file.path),
      child: Stack(
        fit: StackFit.expand,
        children: [
          isVideo
              ? VideoTileThumbnail(path: file.path)
              : Image.file(file, fit: BoxFit.cover, cacheWidth: 300),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _showFileInfo(file),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.info_outline, size: 15, color: Colors.white),
              ),
            ),
          ),
          if (selected)
            Container(
              color: Colors.deepPurple.withOpacity(0.5),
              alignment: Alignment.center,
              child: const Icon(Icons.check_circle, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
