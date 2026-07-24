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

## Novedades de esta versión

- Indicador de video configurable: duración, tamaño o desactivado.
- Orden de fotos/videos por nombre, tamaño o duración, ascendente/descendente
  con una flecha para invertir (por defecto: más reciente arriba).
- Orden de carpetas por nombre, tamaño o cantidad de archivos.
- Filtro de contenido: todo, solo imágenes o solo videos.
- Columnas de la grilla ajustables (2 a 6).
- "Seleccionar todo" en una carpeta (fotos/videos y carpetas), con
  confirmación antes de borrar.
- Selección múltiple de carpetas para mover o eliminar juntas.
- Detección de la tarjeta SD como acceso rápido adicional.
- Distintivo visual (punto verde) en las carpetas que sí tienen contenido.
- Categorías de acceso rápido para mover archivos ("Todas", "Amor", etc.),
  asignables desde el menú ⋮ de cada carpeta ("Categorizar").
- Info de carpeta con cantidad de imágenes/videos (sin contar subcarpetas).
- Doble toque a los lados del video para retroceder/adelantar 10s.
- El selector de "Mover a" ahora aparece como una hoja flotante encima del
  visor, sin salir de la foto/video.
- Visor de video: ajuste de aspecto (ajustar/rellenar/estirar), repetir,
  reproducir el siguiente al terminar, barra de progreso arrastrable.
- Mosaico de video: sin margen o con margen de color elegible, filas/columnas
  manuales, detección de escenas (heurística simple que prioriza cambios de
  plano reales en vez de cortar por tiempo fijo), marca de tiempo por imagen.
- Botón directo "Abrir con Shizuku" cuando una carpeta protegida no se puede
  listar de forma normal (antes solo se sugería por texto).

## Lo que NO se pudo hacer todavía (y por qué)

- **Highlight reel / resumen en video**: generar un video nuevo recortando y
  uniendo varias escenas del original requiere una librería de codificación
  de video de verdad (no solo extraer fotogramas sueltos, como hace el
  mosaico). La opción estándar para esto en Flutter, `ffmpeg_kit_flutter`,
  fue retirada oficialmente por su autor en 2025 y sus binarios ya no están
  disponibles — agregarla haría fallar la compilación, igual que pasó con
  otros paquetes viejos en este proyecto. Las alternativas actuales están
  incompletas o sin mantenimiento para Android. Si querés igual avanzar con
  esto, se puede intentar con una integración nativa a medida (mucho más
  trabajo y menos estable), o dejarlo para cuando exista un reemplazo
  confiable.
- **Videos .m3u8 que no permiten adelantar**: algunas transmisiones HLS se
  publican sin un índice completo de "seek" (les falta información que le
  diga al reproductor dónde puede saltar), o están armadas para reproducirse
  solo de corrido. Es una limitación del archivo/códec en sí, no algo que la
  app pueda forzar. Si querés poder adelantar esos videos, la única forma
  confiable es convertirlos antes a .mp4 con una herramienta externa en tu PC.

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
