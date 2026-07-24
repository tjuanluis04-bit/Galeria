import 'package:flutter/material.dart';
import '../services/shizuku_service.dart';
import '../services/file_ops.dart';
import '../utils/file_utils.dart';
import '../widgets/move_picker_sheet.dart';

/// Navegador para carpetas que Android bloquea a cualquier app común
/// (Android/data y Android/obb de OTRAS apps, desde Android 11). El listado
/// normal (dart:io) siempre falla ahí por política del sistema operativo,
/// con o sin el permiso "Administrar almacenamiento" concedido — Shizuku es
/// la única forma de esquivarlo, ejecutando los comandos como si fuera
/// `adb shell`.
///
/// Limitación real de este modo: al venir de un comando de shell y no de
/// dart:io, no hay miniaturas ni reproducción directa. Para ver/reproducir
/// un archivo de acá, primero hay que copiarlo a una carpeta normal
/// (por ejemplo Download) con el botón correspondiente.
class ProtectedFolderScreen extends StatefulWidget {
  final String path;
  const ProtectedFolderScreen({super.key, required this.path});

  @override
  State<ProtectedFolderScreen> createState() => _ProtectedFolderScreenState();
}

class _ProtectedFolderScreenState extends State<ProtectedFolderScreen> {
  List<ShellEntry> _entries = [];
  bool _loading = true;
  String? _error;
  final Set<String> _selected = {};

  bool get _selectionMode => _selected.isNotEmpty;

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
    final ready = await ShizukuService.instance.ensureReady();
    if (!ready) {
      setState(() {
        _loading = false;
        _error = 'Shizuku no está disponible. Instalalo, activalo, y concedé el '
            'permiso desde el ícono de escudo en la pantalla principal.';
      });
      return;
    }
    final entries = await ShizukuService.instance.listDir(widget.path);
    if (!mounted) return;
    if (entries == null) {
      setState(() {
        _loading = false;
        _error = 'No se pudo listar esta carpeta con Shizuku. Puede que esté '
            'vacía, que no exista, o que el comando haya fallado.';
      });
      return;
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    setState(() {
      _entries = entries;
      _loading = false;
    });
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
    final result = await FileOps.createDir('${widget.path}/${name.trim()}');
    if (result.success) {
      _load();
    } else {
      _showSnack('Error al crear: ${result.error}');
    }
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text('¿Eliminar ${_selected.length} elemento(s)? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true) return;
    for (final path in _selected.toList()) {
      await ShizukuService.instance.run('rm -rf ${_q(path)}');
    }
    setState(() => _selected.clear());
    _load();
  }

  Future<void> _moveSelected() async {
    final dest = await showMovePickerSheet(context, startPath: '/storage/emulated/0');
    if (dest == null) return;
    for (final src in _selected.toList()) {
      final name = src.split('/').last;
      await ShizukuService.instance.run('mv ${_q(src)} ${_q('$dest/$name')}');
    }
    setState(() => _selected.clear());
    _load();
    _showSnack('Movido con Shizuku a ${folderName(dest)}');
  }

  Future<void> _copyToDownloads(String path) async {
    const target = '/storage/emulated/0/Download';
    final name = path.split('/').last;
    final ok = await ShizukuService.instance.run('cp -r ${_q(path)} ${_q('$target/$name')}');
    _showSnack(ok
        ? 'Copiado a Download/$name. Ya podés verlo desde la carpeta normal.'
        : 'No se pudo copiar.');
  }

  String _q(String path) => "'${path.replaceAll("'", "'\\''")}'";

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selected.length} seleccionado(s)')
            : Text(folderName(widget.path)),
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
            : [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
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
    if (_entries.isEmpty) return const Center(child: Text('Carpeta vacía'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (ctx, i) {
          final entry = _entries[i];
          final fullPath = '${widget.path}/${entry.name}';
          final selected = _selected.contains(fullPath);
          return ListTile(
            selected: selected,
            leading: Icon(
              entry.isDir ? Icons.folder : Icons.insert_drive_file,
              color: entry.isDir ? Colors.amber : Colors.blueGrey,
            ),
            title: Text(entry.name),
            subtitle: entry.isDir ? null : Text(formatBytes(entry.size)),
            trailing: !entry.isDir
                ? IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Copiar a Download para poder verlo',
                    onPressed: () => _copyToDownloads(fullPath),
                  )
                : null,
            onTap: () {
              if (_selectionMode) {
                _toggleSelect(fullPath);
                return;
              }
              if (entry.isDir) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProtectedFolderScreen(path: fullPath)),
                ).then((_) => _load());
              }
            },
            onLongPress: () => _toggleSelect(fullPath),
          );
        },
      ),
    );
  }
}
