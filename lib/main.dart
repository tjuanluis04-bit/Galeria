import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/gallery_screen.dart';

const String rootStoragePath = '/storage/emulated/0';

void main() {
  runApp(const GaleriaApp());
}

class GaleriaApp extends StatelessWidget {
  const GaleriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Galería',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const PermissionGate(),
    );
  }
}

class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _checking = true;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    setState(() => _checking = true);

    var manageStatus = await Permission.manageExternalStorage.status;
    if (!manageStatus.isGranted) {
      manageStatus = await Permission.manageExternalStorage.request();
    }

    if (!manageStatus.isGranted) {
      // Alternativa para versiones/dispositivos donde manageExternalStorage no aplica.
      await Permission.storage.request();
      await Permission.photos.request();
      await Permission.videos.request();
    }

    final finalManage = await Permission.manageExternalStorage.status;
    final finalStorage = await Permission.storage.status;
    final granted = finalManage.isGranted || finalStorage.isGranted;

    if (!mounted) return;
    setState(() {
      _granted = granted;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_granted) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Se necesita permiso de almacenamiento para ver y organizar '
                  'tus fotos y videos.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await openAppSettings();
                    _checkPermission();
                  },
                  child: const Text('Abrir ajustes'),
                ),
                TextButton(
                  onPressed: _checkPermission,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const GalleryScreen(path: rootStoragePath);
  }
}
