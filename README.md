# Galería

App Flutter para Android que permite ver fotos y videos organizados por carpetas
y subcarpetas del celular, con gestión de archivos y edición avanzada incluida.

## Funciones incluidas

- Navegar por las carpetas reales del almacenamiento (`/storage/emulated/0`),
  con subcarpetas dentro de carpetas, ilimitado.
- **Acceso a carpetas protegidas** (`Android/data`, `Android/obb`, etc.) usando
  **Shizuku** como respaldo automático cuando el sistema deniega una operación
  normal, aunque tengas el permiso "Administrar almacenamiento" concedido.
  Ver la sección [Shizuku](#shizuku-carpetas-protegidas) más abajo.
- Ver fotos a pantalla completa (con zoom) y reproducir videos, **deslizando
  hacia los lados para pasar al siguiente/anterior** sin volver a la grilla.
- **Miniaturas reales de video** (un fotograma real, no un ícono), cacheadas en
  memoria para que la grilla no las regenere al hacer scroll.
- **Duración visible** sobre la miniatura de cada video.
- Control de **velocidad de reproducción** ampliado: 0.25x, 0.5x, 0.75x, 1x,
  1.25x, 1.5x, 1.75x, 2x, 2.5x, 3x y 4x.
- Ver el **tamaño** de fotos y videos (botón de info en cada miniatura, en el
  visor y en el reproductor).
- **Mover archivos a otra carpeta directamente desde el visor** (mientras estás
  viendo la foto/video, sin volver a la grilla), además de mover varios a la
  vez desde la selección múltiple en la grilla.
- **Borrar rápido** (selección múltiple + un toque, o un botón dentro del
  visor).
- **Crear carpetas y subcarpetas** (botón flotante "+", disponible también al
  elegir carpeta destino para mover).
- **Renombrar y borrar carpetas** (menú de 3 puntos en cada carpeta o en la
  barra superior).
- **Generar un mosaico ("contact sheet") de cualquier video**: una sola imagen
  con varios fotogramas tomados a lo largo del video, de inicio a fin. Podés
  ajustar cuántas imágenes tiene el mosaico (4 a 25) y qué rango del video se
  captura (por ejemplo, saltar la intro o el final). Se abre con el ícono de
  mosaico dentro del visor de video, y el resultado se guarda como .jpg junto
  al video original.

## Shizuku (carpetas protegidas)

Algunas carpetas del sistema (como `Android/data` de otras apps) están
bloqueadas por Android incluso con el permiso "Administrar almacenamiento".
Para esos casos la app usa **Shizuku** automáticamente como respaldo: primero
intenta la operación normal, y si el sistema la deniega, reintenta el mismo
mover/crear/renombrar/borrar como comando con privilegios de Shizuku.

Para que esto funcione:

1. Instalá la app **Shizuku** desde Google Play o desde
   https://shizuku.rikka.app/download/.
2. Activá Shizuku en tu celular:
   - Android 11+: se puede iniciar directamente desde la propia app Shizuku
     usando "depuración inalámbrica" (wireless debugging), sin PC.
   - Versiones más viejas o si preferís: se activa una vez por PC con ADB
     (la app de Shizuku te guía paso a paso).
3. Abrí la Galería y tocá el ícono de escudo (🛡️) en la pantalla principal.
   Te va a pedir el permiso de Shizuku la primera vez.
4. Ya podés entrar a los accesos rápidos "Android/data" y "Android/obb" que
   aparecen arriba de todo en la pantalla principal, o navegar a cualquier
   carpeta protegida.

Si no instalás ni activás Shizuku, la app funciona igual con normalidad en
todo el resto del almacenamiento; simplemente no vas a poder tocar esas
carpetas específicas del sistema.

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
el álbum de fotos del sistema. El permiso de Shizuku (opcional) se pide aparte,
solo si tocás el ícono de escudo o intentás acceder a una carpeta protegida.

## Estructura del proyecto

```
lib/
  main.dart                          -> punto de entrada, pide permisos
  utils/file_utils.dart              -> helpers (tamaños, extensiones, rutas)
  services/file_ops.dart             -> crear/mover/renombrar/borrar, con
                                         respaldo automático de Shizuku
  services/shizuku_service.dart      -> wrapper del plugin shizuku_api
  services/thumbnail_cache.dart      -> miniaturas reales de video + duración,
                                         cacheadas en memoria
  widgets/video_tile_thumbnail.dart  -> miniatura de video con duración
  screens/gallery_screen.dart        -> navegador de carpetas + grilla
  screens/media_viewer_screen.dart   -> visor deslizable (fotos y videos),
                                         con mover/borrar/mosaico sin salir
  screens/mosaic_screen.dart         -> generador de mosaico de fotogramas
  screens/folder_picker_screen.dart  -> selector de carpeta destino al mover
android_overrides/AndroidManifest.xml -> permisos + proveedor de Shizuku,
                                          se copia sobre el generado
.github/workflows/build.yml         -> compila el APK en GitHub Actions
```

## Notas

- El proyecto no incluye la carpeta `android/` completa: GitHub Actions la
  genera automáticamente en cada build con `flutter create`, y luego le aplica
  los permisos personalizados. Así el repositorio se mantiene liviano y sin
  archivos de Gradle que puedan quedar desactualizados.
- El mosaico se genera enteramente en el celular (sin depender de un servidor),
  componiendo los fotogramas con Flutter. En videos muy largos o con muchas
  imágenes en el mosaico, la generación puede tardar unos segundos; se muestra
  una barra de progreso.
- El respaldo de Shizuku para archivos solo cubre operaciones de escritura
  (crear, mover, renombrar, borrar). La lectura/listado de carpetas usa
  siempre el almacenamiento normal, que ya cubre la gran mayoría de rutas
  gracias al permiso "Administrar almacenamiento".
