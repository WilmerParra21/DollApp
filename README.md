# DollApp

DollApp es una aplicación móvil construida con Flutter para consultar tasas de cambio y realizar conversiones, orientada al consumo del público venezolano con referencias del BCV y otras tasas utilizadas en el país.

## ¿Qué hace?

- Muestra tasas de cambio actualizadas y datos financieros en una interfaz clara y moderna.
- Permite consultar históricos de tasas y comparar su evolución.
- Incluye una calculadora de conversiones con soporte para precisión ampliada.
- Gestiona actualizaciones internas de la app mediante un modal de actualización con estado de descarga e instalación.
- Incluye animaciones Lottie para dar una experiencia más inmersiva al momento de actualizar.
- Ofrece información de versión, fuentes de datos, política de privacidad y términos de uso.

## ¿Cómo funciona?

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
- `lib/features/rates/presentation/pages/app_version_screen.dart`: información de versión y modales legales.
- `lib/features/rates/presentation/widgets/update_gate_sheet.dart`: modal de actualización con animación Lottie.

## Tasas y datos

- Las tasas se obtienen de fuentes públicas y reconocidas, como el Banco Central de Venezuela, TRM Colombia y servicios de referencia internacional.
- La aplicación conserva tasas y preferencias en caché local para poder mostrar los últimos datos disponibles sin conexión.
- Las tasas se manejan con hasta cuatro decimales. La interfaz puede mostrar una versión resumida o la precisión ampliada según el contexto.
- Los valores son informativos y deben verificarse con la fuente correspondiente antes de realizar una operación.

## Privacidad

- DollApp no solicita cuentas ni recopila datos personales, contactos, ubicación o el contenido de las conversiones.
- Si ocurre un fallo, puede enviarse información relacionada con el error únicamente para diagnosticarlo, corregirlo y mejorar la estabilidad de la aplicación.
- La política de privacidad y los términos y condiciones están disponibles desde la pantalla `Versión de la aplicación`.

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

La app está diseñada para ser adaptable a temas claros y oscuros. Las tasas son informativas y la disponibilidad de datos puede depender de la conexión y de las fuentes externas.
