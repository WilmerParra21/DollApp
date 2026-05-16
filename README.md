# DollApp

DollApp es una aplicación móvil construida con Flutter para consultar tasas de cambio y mantener a los usuarios informados sobre sus actualizaciones, está orientada al consummo del público venezolano con tasas de conversión del BCV y otras utilizadas en el país.

## ¿Qué hace?

- Muestra tasas de cambio actualizadas y datos financieros en una interfaz clara y moderna.
- Gestiona actualizaciones internas de la app mediante un modal de actualización con estado de descarga e instalación.
- Incluye animaciones Lottie para dar una experiencia más inmersiva al momento de actualizar.
- Ofrece mensajes de novedades, control de versión y manejo de permisos de instalación si es necesario.

## Cómo funciona

1. Al abrir la app, el usuario ve las tasas del día y la última actualización disponible.
2. Si hay una versión nueva, se muestra un panel de actualización que explica la mejora y guía al usuario.
3. El botón `Actualizar ahora` inicia la descarga del APK a través del servicio `UpdateService`.
4. Durante la descarga se muestra el progreso con una barra y una animación de cohete.
5. Si la instalación requiere permisos adicionales, la app redirige al usuario a los ajustes necesarios.

## Arquitectura y organización

- `lib/main.dart`: punto de entrada de la app.
- `lib/app/`: configuración de temas y rutas.
- `lib/core/`: servicios, constantes, modelos y widgets reutilizables.
- `lib/features/rates/`: pantalla y widgets específicos de tasas y actualización.
- `lib/features/rates/presentation/widgets/update_gate_sheet.dart`: modal de actualización con animación Lottie.

## Paleta de colores

DollApp utiliza una paleta inspirada en tonos verdes y neutros para transmitir confianza y claridad:

- `AppColors.forestGreen`: color principal de botones y acentos.
- `AppColors.accentGreen`: color secundario para estados positivos y destacables.
- `AppColors.lightBackground`: fondo claro principal en modo día.
- `AppColors.darkBackground`: fondo oscuro principal en modo noche.
- `AppColors.white`: superficie de tarjetas y contenedores claros.
- `AppColors.darkCard`: superficie de tarjetas en modo oscuro.
- `AppColors.lightGray`: separadores y bordes suaves.
- `AppColors.darkBorder`: contornos discretos en modo oscuro.
- `AppColors.negativeRed`: color de error y advertencias.

## Recursos y animaciones

- `assets/animation/Rocket.lottie`: animación del cohete usada en el modal de actualización.
- `assets/images/`: imágenes adicionales de la interfaz.

## Tecnologías principales

- Flutter 3.x
- Dart
- Lottie (`package:lottie`) para animaciones vectoriales.
- Arquitectura modular por características.

## Instrucciones rápidas

- Instalar dependencias:
  ```bash
  flutter pub get
  ```
- Ejecutar la app:
  ```bash
  flutter run
  ```
- Limpiar el proyecto si hay problemas de cache:
  ```bash
  flutter clean
  flutter pub get
  ```

## Notas

La app está diseñada para ser adaptable a temas claros y oscuros, con un modal de actualización que debe integrarse visualmente con el fondo de la pantalla para evitar la sensación de un cuadro separado.
