# Galería

App Flutter para Android que permite ver fotos y videos organizados por carpetas
y subcarpetas del celular, con gestión de archivos incluida.

## Funciones incluidas

- Navegar por las carpetas reales del almacenamiento (`/storage/emulated/0`),
  con subcarpetas dentro de carpetas, ilimitado.
- Ver fotos a pantalla completa (con zoom).
- Reproducir videos, con control de **velocidad de reproducción** (0.25x a 2x).
- Ver el **tamaño** de fotos y videos (botón de info en cada miniatura y en el reproductor).
- **Mover** archivos a otra carpeta (selección múltiple, mantén presionado para seleccionar).
- **Borrar rápido** (selección múltiple + un toque).
- **Crear carpetas y subcarpetas** (botón flotante "+").
- **Renombrar y borrar carpetas** (menú de 3 puntos en cada carpeta o en la barra superior).

## Cómo compilar el APK con GitHub Actions

1. Crea un repositorio nuevo en GitHub (puede ser privado).
2. Sube TODO el contenido de esta carpeta (`galeria_app/`) a la raíz de ese
   repositorio (respeta la estructura de carpetas, incluida `.github/workflows/`).
3. Entra a la pestaña **Actions** del repositorio en GitHub. Si Actions está
   desactivado, actívalo.
4. El workflow **"Build APK"** se ejecuta automáticamente al hacer push a la
   rama `main`. También puedes lanzarlo manualmente desde Actions → Build APK
   → "Run workflow".
5. Cuando termine (en verde ✅), entra a esa ejecución y baja hasta
   **Artifacts**: ahí aparece `galeria-apk` para descargar. Es un .zip que
   contiene `app-release.apk`.
6. Pasa el APK a tu celular e instálalo (Android te pedirá permitir
   "instalar apps de fuentes desconocidas" la primera vez).

### Comandos equivalentes en tu propia PC (opcional)

Si en algún momento tienes Flutter instalado localmente, también puedes hacer:

```bash
flutter create --platforms=android --org com.galeria.app .
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

## Permisos

La primera vez que abras la app te pedirá el permiso "Acceso a todos los
archivos" (Administrar almacenamiento). Es necesario para poder leer, mover,
crear y borrar carpetas en cualquier ubicación del almacenamiento, no solo en
el álbum de fotos del sistema.

## Estructura del proyecto

```
lib/
  main.dart                     -> punto de entrada, pide permisos
  utils/file_utils.dart         -> helpers (tamaños, extensiones, rutas)
  screens/gallery_screen.dart   -> navegador de carpetas + grilla de fotos/videos
  screens/video_player_screen.dart -> reproductor con control de velocidad
  screens/folder_picker_screen.dart -> selector de carpeta destino al mover
android_overrides/AndroidManifest.xml -> permisos, se copia sobre el generado
.github/workflows/build.yml    -> compila el APK en GitHub Actions
```

## Notas

- Las miniaturas de video muestran un ícono en vez de un fotograma real, para
  mantener el proyecto simple y confiable en la compilación. Si más adelante
  quieres miniaturas reales de video, se puede agregar el paquete
  `video_thumbnail` a `pubspec.yaml`.
- El proyecto no incluye la carpeta `android/` completa: GitHub Actions la
  genera automáticamente en cada build con `flutter create`, y luego le aplica
  los permisos personalizados. Así el repositorio se mantiene liviano y sin
  archivos de Gradle que puedan quedar desactualizados.
