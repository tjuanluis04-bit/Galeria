import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/file_utils.dart';

class FolderPickerScreen extends StatefulWidget {
  final String startPath;
  const FolderPickerScreen({super.key, required this.startPath});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  late String _current;
  List<Directory> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _current = widget.startPath;
    _load();
  }

  Future<void> _load() async {
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
    setState(() => _current = path);
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
    try {
      await Directory('$_current/${name.trim()}').create(recursive: true);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isRoot = _current == widget.startPath;
    return Scaffold(
      appBar: AppBar(
        title: Text('Mover a: ${folderName(_current)}'),
        leading: isRoot
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_upward),
                onPressed: () => _open(parentPath(_current)),
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? const Center(child: Text('Sin subcarpetas aquí'))
              : ListView.builder(
                  itemCount: _folders.length,
                  itemBuilder: (ctx, i) {
                    final dir = _folders[i];
                    return ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Text(folderName(dir.path)),
                      onTap: () => _open(dir.path),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFolderHere,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Nueva'),
      ),
      persistentFooterButtons: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _current),
          child: const Text('Seleccionar esta carpeta'),
        ),
      ],
    );
  }
}
