import 'dart:io';

const List<String> imageExtensions = [
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'
];

const List<String> videoExtensions = [
  '.mp4', '.mov', '.mkv', '.avi', '.3gp', '.webm', '.m4v'
];

bool isImageFile(String path) {
  final p = path.toLowerCase();
  return imageExtensions.any((e) => p.endsWith(e));
}

bool isVideoFile(String path) {
  final p = path.toLowerCase();
  return videoExtensions.any((e) => p.endsWith(e));
}

bool isMediaFile(String path) => isImageFile(path) || isVideoFile(path);

/// Formatea bytes a una unidad legible (B, KB, MB, GB, TB).
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var i = 0;
  while (value >= 1024 && i < suffixes.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(i == 0 ? 0 : decimals)} ${suffixes[i]}';
}

/// Devuelve el nombre de la última carpeta o archivo de una ruta.
String folderName(String path) {
  final sep = Platform.pathSeparator;
  final trimmed = path.endsWith(sep) ? path.substring(0, path.length - 1) : path;
  final parts = trimmed.split(sep).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? trimmed : parts.last;
}

/// Devuelve la ruta de la carpeta padre.
String parentPath(String path) {
  final sep = Platform.pathSeparator;
  final trimmed = path.endsWith(sep) ? path.substring(0, path.length - 1) : path;
  final idx = trimmed.lastIndexOf(sep);
  if (idx <= 0) return sep;
  return trimmed.substring(0, idx);
}
