import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart' show rootStoragePath;
import '../utils/file_utils.dart';
import '../services/file_ops.dart';
import '../services/shizuku_service.dart';
import '../services/settings_service.dart';
import '../services/category_service.dart';
import '../services/folder_stats.dart';
import '../services/storage_roots.dart';
import '../services/thumbnail_cache.dart';
import '../widgets/video_tile_thumbnail.dart';
import '../widgets/move_picker_sheet.dart';
import 'media_viewer_screen.dart';
import 'protected_folder_screen.dart';

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
  final Set<String> _selectedFiles = {};
  final Set<String> _selectedFolders = {};
  List<StorageRoot> _extraRoots = [];

  bool get _selectionMode => _selectedFiles.isNotEmpty || _selectedFolders.isNotEmpty;
  bool get _isRoot => widget.path == rootStoragePath;

  static const _quickAccess = [
    '$rootStoragePath/Android/data',
    '$rootStoragePath/Android/obb',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await SettingsService.instance.load();
    await CategoryService.instance.load();
    if (_isRoot) {
      final roots = await StorageRoots.detect();
      if (mounted) setState(() => _extraRoots = roots.where((r) => r.path != rootStoragePath).toList());
    }
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
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _mediaFiles = media;
        _loading = false;
      });
      await _applySort();
    } catch (e) {
      if (!mounted) return;
      final isProtected = widget.path.contains('/Android/data') || widget.path.contains('/Android/obb');
      setState(() {
        _error = isProtected
            ? 'No se pudo abrir esta carpeta (protegida por el sistema).\n'
                'Probá con "Carpetas protegidas (Shizuku)" desde la pantalla principal.\n$e'
            : 'No se pudo abrir esta carpeta.\n$e';
        _loading = false;
      });
    }
  }

  // ---------- Orden y filtro ----------

  int _sizeOf(File f) {
    try {
      return f.statSync().size;
    } catch (_) {
      return 0;
    }
  }

  DateTime _modifiedOf(File f) {
    try {
      return f.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  int _compareMedia(File a, File b) {
    final s = SettingsService.instance;
    int cmp;
    switch (s.sortField) {
      case SortField.name:
        cmp = folderName(a.path).toLowerCase().compareTo(folderName(b.path).toLowerCase());
        break;
      case SortField.size:
        cmp = _sizeOf(a).compareTo(_sizeOf(b));
        break;
      case SortField.duration:
        final da = isVideoFile(a.path)
            ? (ThumbnailCache.instance.cachedDuration(a.path)?.inMilliseconds ?? -1)
            : -1;
        final db = isVideoFile(b.path)
            ? (ThumbnailCache.instance.cachedDuration(b.path)?.inMilliseconds ?? -1)
            : -1;
        cmp = da.compareTo(db);
        break;
      case SortField.dateDefault:
        cmp = _modifiedOf(a).compareTo(_modifiedOf(b));
        break;
    }
    return s.sortDescending ? -cmp : cmp;
  }

  final Map<String, FolderStats> _folderStatsCache = {};

  int _compareFolder(Directory a, Directory b) {
    final s = SettingsService.instance;
    int cmp;
    switch (s.folderSortField) {
      case FolderSortField.name:
        cmp = folderName(a.path).toLowerCase().compareTo(folderName(b.path).toLowerCase());
        break;
      case FolderSortField.size:
        cmp = (_folderStatsCache[a.path]?.totalBytes ?? 0)
            .compareTo(_folderStatsCache[b.path]?.totalBytes ?? 0);
        break;
      case FolderSortField.fileCount:
        cmp = (_folderStatsCache[a.path]?.total ?? 0)
            .compareTo(_folderStatsCache[b.path]?.total ?? 0);
        break;
    }
    return s.folderSortDescending ? -cmp : cmp;
  }

  Future<void> _applySort() async {
    final s = SettingsService.instance;
    if (s.sortField == SortField.duration) {
      final videos = _mediaFiles.where((f) => isVideoFile(f.path));
      await Future.wait(videos.map((f) => ThumbnailCache.instance.durationFor(f.path)));
    }
    if (s.folderSortField != FolderSortField.name) {
      final results = await Future.wait(_folders.map((d) => FolderStatsService.instance.directStats(d.path)));
      for (var i = 0; i < _folders.length; i++) {
        _folderStatsCache[_folders[i].path] = results[i];
      }
    }
    if (!mounted) return;
    setState(() {
      _mediaFiles.sort(_compareMedia);
      _folders.sort(_compareFolder);
    });
  }

  List<File> get _filteredMedia {
    switch (SettingsService.instance.contentFilter) {
      case ContentFilter.images:
        return _mediaFiles.where((f) => isImageFile(f.path)).toList();
      case ContentFilter.videos:
        return _mediaFiles.where((f) => isVideoFile(f.path)).toList();
      case ContentFilter.all:
        return _mediaFiles;
    }
  }

  // ---------- Selección ----------

  void _toggleSelectFile(String path) {
    setState(() {
      if (_selectedFiles.contains(path)) {
        _selectedFiles.remove(path);
      } else {
        _selectedFiles.add(path);
      }
    });
  }

  void _toggleSelectFolder(String path) {
    setState(() {
      if (_selectedFolders.contains(path)) {
        _selectedFolders.remove(path);
      } else {
        _selectedFolders.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedFiles
        ..clear()
        ..addAll(_filteredMedia.map((f) => f.path));
      _selectedFolders
        ..clear()
        ..addAll(_folders.map((d) => d.path));
    });
  }

  void _clearSelection() => setState(() {
        _selectedFiles.clear();
        _selectedFolders.clear();
      });

  Future<void> _checkShizuku() async {
    final ok = await ShizukuService.instance.ensureReady(forcePrompt: true);
    if (!mounted) return;
    _showSnack(ok
        ? 'Shizuku activo: se usará como respaldo si el sistema deniega alguna operación.'
        : 'Shizuku no disponible (no está instalado/corriendo o se negó el permiso).');
  }

  // ---------- Crear / renombrar / borrar carpetas ----------

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
      await CategoryService.instance.renameFolder(dir.path, newPath);
      FolderStatsService.instance.invalidate(dir.path);
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
      await CategoryService.instance.forgetFolder(dir.path);
      FolderStatsService.instance.invalidate(dir.path);
      if (result.usedShizuku) _showSnack('Carpeta eliminada con Shizuku');
      _load();
    } else {
      _showSnack('Error al eliminar: ${result.error}');
    }
  }

  Future<void> _deleteSelected() async {
    final total = _selectedFiles.length + _selectedFolders.length;
    final confirm = await _confirm(
      '¿Eliminar $total elemento(s)'
      '${_selectedFolders.isNotEmpty ? " (incluye carpetas completas con su contenido)" : ""}? '
      'Esta acción no se puede deshacer.',
    );
    if (confirm != true) return;
    var shizukuUsed = false;
    for (final p in _selectedFiles.toList()) {
      final result = await FileOps.deleteFile(p);
      if (result.usedShizuku) shizukuUsed = true;
    }
    for (final p in _selectedFolders.toList()) {
      final result = await FileOps.deleteDir(p);
      if (result.usedShizuku) shizukuUsed = true;
      await CategoryService.instance.forgetFolder(p);
    }
    _clearSelection();
    _load();
    if (shizukuUsed) _showSnack('Algunos elementos se eliminaron con Shizuku');
  }

  Future<void> _moveSelected() async {
    final dest = await showMovePickerSheet(context, startPath: rootStoragePath);
    if (dest == null) return;
    var errors = 0;
    var shizukuUsed = false;
    for (final p in _selectedFiles.toList()) {
      final result = await FileOps.moveFile(p, '$dest/${folderName(p)}');
      if (!result.success) errors++;
      if (result.usedShizuku) shizukuUsed = true;
    }
    for (final p in _selectedFolders.toList()) {
      final result = await FileOps.moveDir(p, '$dest/${folderName(p)}');
      if (!result.success) errors++;
      if (result.usedShizuku) shizukuUsed = true;
      await CategoryService.instance.forgetFolder(p);
    }
    _clearSelection();
    _load();
    if (errors > 0) _showSnack('$errors elemento(s) no se pudieron mover');
    if (shizukuUsed) _showSnack('Algunos elementos se movieron con Shizuku');
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

  // ---------- Menú de carpeta (⋮): renombrar, categorizar, info, borrar ----------

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
              leading: const Icon(Icons.label_outline),
              title: const Text('Categorizar'),
              subtitle: const Text('Para acceder más rápido al mover contenido'),
              onTap: () {
                Navigator.pop(ctx);
                _showCategorizeDialog(dir);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Información'),
              onTap: () {
                Navigator.pop(ctx);
                _showFolderInfo(dir);
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

  Future<void> _showFolderInfo(Directory dir) async {
    final stats = await FolderStatsService.instance.directStats(dir.path);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(folderName(dir.path)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Imágenes: ${stats.images}'),
            Text('Videos: ${stats.videos}'),
            Text('Tamaño total: ${formatBytes(stats.totalBytes)}'),
            const SizedBox(height: 8),
            const Text(
              'Nota: solo cuenta lo que está directamente en esta carpeta, no '
              'lo que haya dentro de sus subcarpetas.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

  void _showCategorizeDialog(Directory dir) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final current = CategoryService.instance.categoriesOf(dir.path);
          final all = CategoryService.instance.categoryNames;
          return AlertDialog(
            title: Text('Categorizar "${folderName(dir.path)}"'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (all.isEmpty) const Text('Todavía no creaste ninguna categoría.'),
                  for (final cat in all)
                    CheckboxListTile(
                      title: Text(cat),
                      value: current.contains(cat),
                      onChanged: (checked) async {
                        if (checked == true) {
                          await CategoryService.instance.addFolderToCategory(dir.path, cat);
                        } else {
                          await CategoryService.instance.removeFolderFromCategory(dir.path, cat);
                        }
                        setDialogState(() {});
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva categoría'),
                      onPressed: () async {
                        final controller = TextEditingController();
                        final name = await showDialog<String>(
                          context: ctx,
                          builder: (ctx2) => AlertDialog(
                            title: const Text('Nueva categoría'),
                            content: TextField(controller: controller, autofocus: true),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx2), child: const Text('Cancelar')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx2, controller.text),
                                  child: const Text('Crear')),
                            ],
                          ),
                        );
                        if (name != null && name.trim().isNotEmpty) {
                          await CategoryService.instance.createCategory(name.trim());
                          await CategoryService.instance.addFolderToCategory(dir.path, name.trim());
                          setDialogState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
            ],
          );
        },
      ),
    );
  }

  // ---------- Menú de vista (⚙): filtro, orden, columnas, indicador ----------

  void _showViewOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final s = SettingsService.instance;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Contenido', style: Theme.of(context).textTheme.titleSmall),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in ContentFilter.values)
                        ChoiceChip(
                          label: Text(_filterLabel(f)),
                          selected: s.contentFilter == f,
                          onSelected: (_) async {
                            await s.setContentFilter(f);
                            setSheetState(() {});
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Orden de fotos/videos', style: Theme.of(context).textTheme.titleSmall),
                      ),
                      IconButton(
                        icon: Icon(s.sortDescending ? Icons.arrow_downward : Icons.arrow_upward),
                        tooltip: 'Invertir dirección',
                        onPressed: () async {
                          await s.toggleSortDirection();
                          setSheetState(() {});
                          await _applySort();
                        },
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in SortField.values)
                        ChoiceChip(
                          label: Text(_sortLabel(f)),
                          selected: s.sortField == f,
                          onSelected: (_) async {
                            await s.setSort(f);
                            setSheetState(() {});
                            await _applySort();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Orden de carpetas', style: Theme.of(context).textTheme.titleSmall),
                      ),
                      IconButton(
                        icon: Icon(s.folderSortDescending ? Icons.arrow_downward : Icons.arrow_upward),
                        tooltip: 'Invertir dirección',
                        onPressed: () async {
                          await s.toggleFolderSortDirection();
                          setSheetState(() {});
                          await _applySort();
                        },
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in FolderSortField.values)
                        ChoiceChip(
                          label: Text(_folderSortLabel(f)),
                          selected: s.folderSortField == f,
                          onSelected: (_) async {
                            await s.setFolderSort(f);
                            setSheetState(() {});
                            await _applySort();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Columnas de la grilla: ${s.gridColumns}', style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: s.gridColumns.toDouble(),
                    min: 2,
                    max: 6,
                    divisions: 4,
                    label: '${s.gridColumns}',
                    onChanged: (v) async {
                      await s.setGridColumns(v.round());
                      setSheetState(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Indicador sobre videos', style: Theme.of(context).textTheme.titleSmall),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final v in VideoIndicator.values)
                        ChoiceChip(
                          label: Text(_indicatorLabel(v)),
                          selected: s.videoIndicator == v,
                          onSelected: (_) async {
                            await s.setVideoIndicator(v);
                            setSheetState(() {});
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _filterLabel(ContentFilter f) => switch (f) {
        ContentFilter.all => 'Todo',
        ContentFilter.images => 'Solo imágenes',
        ContentFilter.videos => 'Solo videos',
      };

  String _sortLabel(SortField f) => switch (f) {
        SortField.dateDefault => 'Por defecto (fecha)',
        SortField.name => 'Nombre',
        SortField.size => 'Tamaño',
        SortField.duration => 'Duración',
      };

  String _folderSortLabel(FolderSortField f) => switch (f) {
        FolderSortField.name => 'Nombre',
        FolderSortField.size => 'Tamaño',
        FolderSortField.fileCount => 'Cantidad de archivos',
      };

  String _indicatorLabel(VideoIndicator v) => switch (v) {
        VideoIndicator.duration => 'Duración',
        VideoIndicator.size => 'Tamaño',
        VideoIndicator.off => 'Desactivado',
      };

  void _openViewer(int index) async {
    final files = _filteredMedia;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(files: files, initialIndex: index),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedFiles.length + _selectedFolders.length} seleccionado(s)')
            : Text(_isRoot ? 'Galería' : folderName(widget.path)),
        leading: _selectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection)
            : null,
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Seleccionar todo',
                  onPressed: _selectAll,
                ),
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
                  icon: const Icon(Icons.tune),
                  tooltip: 'Orden, filtro y vista',
                  onPressed: _showViewOptions,
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
      final isProtected =
          widget.path.contains('/Android/data') || widget.path.contains('/Android/obb');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              if (isProtected) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.security),
                  label: const Text('Abrir esta carpeta con Shizuku'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProtectedFolderScreen(path: widget.path)),
                  ).then((_) => _load()),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final media = _filteredMedia;
    if (_folders.isEmpty && media.isEmpty && !_isRoot) {
      return const Center(child: Text('Carpeta vacía'));
    }
    final columns = SettingsService.instance.gridColumns;
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
                for (final root in _extraRoots)
                  ListTile(
                    leading: const Icon(Icons.sd_card, color: Colors.lightBlueAccent),
                    title: Text(root.label),
                    subtitle: Text(root.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GalleryScreen(path: root.path)),
                    ).then((_) => _load()),
                  ),
                for (final p in _quickAccess)
                  ListTile(
                    leading: const Icon(Icons.folder_special, color: Colors.deepPurpleAccent),
                    title: Text(folderName(p)),
                    subtitle: const Text('Carpeta protegida — se abre con Shizuku'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProtectedFolderScreen(path: p)),
                    ),
                  ),
                const Divider(height: 1),
              ]),
            ),
          if (_folders.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final dir = _folders[i];
                  final selected = _selectedFolders.contains(dir.path);
                  return ListTile(
                    selected: selected,
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.folder, color: Colors.amber),
                        Positioned(
                          right: -2,
                          top: -2,
                          child: FutureBuilder<bool>(
                            future: FolderStatsService.instance.hasMediaRecursive(dir.path),
                            builder: (ctx, snap) {
                              if (snap.data != true) return const SizedBox.shrink();
                              return Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    title: Text(folderName(dir.path)),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showFolderMenu(dir),
                    ),
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSelectFolder(dir.path);
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => GalleryScreen(path: dir.path)),
                      ).then((_) => _load());
                    },
                    onLongPress: () => _toggleSelectFolder(dir.path),
                  );
                },
                childCount: _folders.length,
              ),
            ),
          if (_folders.isNotEmpty && media.isNotEmpty)
            const SliverToBoxAdapter(child: Divider(height: 1)),
          if (media.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(4),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildMediaTile(media, i),
                  childCount: media.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaTile(List<File> media, int index) {
    final file = media[index];
    final selected = _selectedFiles.contains(file.path);
    final isVideo = isVideoFile(file.path);
    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleSelectFile(file.path);
          return;
        }
        _openViewer(index);
      },
      onLongPress: () => _toggleSelectFile(file.path),
      child: Stack(
        fit: StackFit.expand,
        children: [
          isVideo
              ? VideoTileThumbnail(path: file.path)
              : Image.file(file, fit: BoxFit.cover, cacheWidth: 300),
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
