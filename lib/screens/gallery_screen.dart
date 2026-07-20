import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart' show rootStoragePath;
import '../utils/file_utils.dart';
import 'video_player_screen.dart';
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
      setState(() {
        _error = 'No se pudo abrir esta carpeta.\n$e';
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

  Future<void> _createFolder() async {
    final name = await _promptText(title: 'Nueva carpeta', hint: 'Nombre de la carpeta');
    if (name == null || name.trim().isEmpty) return;
    try {
      final newDir = Directory('${widget.path}/${name.trim()}');
      if (await newDir.exists()) {
        _showSnack('Ya existe una carpeta con ese nombre');
        return;
      }
      await newDir.create(recursive: true);
      _load();
    } catch (e) {
      _showSnack('Error al crear la carpeta: $e');
    }
  }

  Future<void> _renameFolder(Directory dir) async {
    final currentName = folderName(dir.path);
    final name = await _promptText(
      title: 'Renombrar carpeta',
      hint: 'Nuevo nombre',
      initial: currentName,
    );
    if (name == null || name.trim().isEmpty || name.trim() == currentName) return;
    try {
      final newPath = '${parentPath(dir.path)}/${name.trim()}';
      await dir.rename(newPath);
      _load();
    } catch (e) {
      _showSnack('Error al renombrar: $e');
    }
  }

  Future<void> _deleteFolder(Directory dir) async {
    final confirm =
        await _confirm('¿Eliminar la carpeta "${folderName(dir.path)}" y todo su contenido?');
    if (confirm != true) return;
    try {
      await dir.delete(recursive: true);
      _load();
    } catch (e) {
      _showSnack('Error al eliminar: $e');
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm =
        await _confirm('¿Eliminar $count elemento(s)? Esta acción no se puede deshacer.');
    if (confirm != true) return;
    for (final p in _selected.toList()) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    setState(() => _selected.clear());
    _load();
  }

  Future<void> _moveSelected() async {
    final dest = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const FolderPickerScreen(startPath: rootStoragePath),
      ),
    );
    if (dest == null) return;
    var errors = 0;
    for (final p in _selected.toList()) {
      try {
        final newPath = '$dest/${folderName(p)}';
        final f = File(p);
        try {
          await f.rename(newPath);
        } catch (_) {
          await f.copy(newPath);
          await f.delete();
        }
      } catch (_) {
        errors++;
      }
    }
    setState(() => _selected.clear());
    _load();
    if (errors > 0) _showSnack('$errors elemento(s) no se pudieron mover');
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
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Aceptar')),
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
    if (_folders.isEmpty && _mediaFiles.isEmpty) {
      return const Center(child: Text('Carpeta vacía'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
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
                  (ctx, i) => _buildMediaTile(_mediaFiles[i]),
                  childCount: _mediaFiles.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaTile(File file) {
    final selected = _selected.contains(file.path);
    final isVideo = isVideoFile(file.path);
    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(file.path);
          return;
        }
        if (isVideo) {
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(path: file.path)));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => _ImageViewer(file: file)));
        }
      },
      onLongPress: () => _toggleSelect(file.path),
      child: Stack(
        fit: StackFit.expand,
        children: [
          isVideo
              ? Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const Icon(Icons.movie, size: 32),
                )
              : Image.file(file, fit: BoxFit.cover, cacheWidth: 300),
          if (isVideo)
            const Positioned(
              bottom: 4,
              right: 4,
              child: Icon(Icons.play_circle_fill, color: Colors.white70),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _showFileInfo(file),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration:
                    BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
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

class _ImageViewer extends StatelessWidget {
  final File file;
  const _ImageViewer({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(folderName(file.path)),
      ),
      body: Center(child: InteractiveViewer(child: Image.file(file))),
    );
  }
}
