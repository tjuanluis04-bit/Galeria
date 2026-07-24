import 'package:shared_preferences/shared_preferences.dart';

enum VideoIndicator { duration, size, off }

enum SortField { dateDefault, name, size, duration }

enum FolderSortField { name, size, fileCount }

enum ContentFilter { all, images, videos }

/// Ajustes de visualización, guardados en el dispositivo (se recuerdan entre
/// aperturas de la app). Todo se mantiene también en memoria para no tener
/// que leer SharedPreferences constantemente.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;

  VideoIndicator videoIndicator = VideoIndicator.duration;
  SortField sortField = SortField.dateDefault;
  bool sortDescending = true; // true = más reciente/grande/largo arriba
  ContentFilter contentFilter = ContentFilter.all;
  int gridColumns = 3;
  FolderSortField folderSortField = FolderSortField.name;
  bool folderSortDescending = false;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    videoIndicator = VideoIndicator.values[p.getInt('videoIndicator') ?? 0];
    sortField = SortField.values[p.getInt('sortField') ?? 0];
    sortDescending = p.getBool('sortDescending') ?? true;
    contentFilter = ContentFilter.values[p.getInt('contentFilter') ?? 0];
    gridColumns = p.getInt('gridColumns') ?? 3;
    folderSortField = FolderSortField.values[p.getInt('folderSortField') ?? 0];
    folderSortDescending = p.getBool('folderSortDescending') ?? false;
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt('videoIndicator', videoIndicator.index);
    await p.setInt('sortField', sortField.index);
    await p.setBool('sortDescending', sortDescending);
    await p.setInt('contentFilter', contentFilter.index);
    await p.setInt('gridColumns', gridColumns);
    await p.setInt('folderSortField', folderSortField.index);
    await p.setBool('folderSortDescending', folderSortDescending);
  }

  Future<void> setVideoIndicator(VideoIndicator v) async {
    videoIndicator = v;
    await _save();
  }

  Future<void> setSort(SortField field, {bool? descending}) async {
    sortField = field;
    if (descending != null) sortDescending = descending;
    await _save();
  }

  Future<void> toggleSortDirection() async {
    sortDescending = !sortDescending;
    await _save();
  }

  Future<void> setContentFilter(ContentFilter f) async {
    contentFilter = f;
    await _save();
  }

  Future<void> setGridColumns(int columns) async {
    gridColumns = columns;
    await _save();
  }

  Future<void> setFolderSort(FolderSortField field, {bool? descending}) async {
    folderSortField = field;
    if (descending != null) folderSortDescending = descending;
    await _save();
  }

  Future<void> toggleFolderSortDirection() async {
    folderSortDescending = !folderSortDescending;
    await _save();
  }
}
