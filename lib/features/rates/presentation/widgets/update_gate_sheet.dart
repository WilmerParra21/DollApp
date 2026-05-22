import 'package:dollapp/core/models/audit_log.dart';
import 'package:dollapp/core/services/audit_service.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/services/update_service.dart';

Future<void> showUpdateGateSheet(BuildContext context, UpdateInfo updateInfo) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _UpdateGateContent(updateInfo: updateInfo),
      );
    },
  );
}

class _UpdateGateContent extends StatefulWidget {
  const _UpdateGateContent({required this.updateInfo});

  final UpdateInfo updateInfo;

  @override
  State<_UpdateGateContent> createState() => _UpdateGateContentState();
}

class _UpdateGateContentState extends State<_UpdateGateContent> {
  double _progress = 0;
  bool _isDownloading = false;
  bool _installPermissionDenied = false;
  String? _errorMessage;
  bool _isInstalled = false;
  bool _playStoreAvailable = false;
  bool _playStoreChecked = false;

  @override
  void initState() {
    super.initState();
    _resolvePlayStoreAvailability();
  }

  Future<void> _resolvePlayStoreAvailability() async {
    if (!UpdateService.instance.hasPlayStoreLink) {
      setState(() {
        _playStoreChecked = true;
        _playStoreAvailable = false;
      });
      return;
    }

    final available = await UpdateService.instance.isPlayStoreAvailable();
    if (!mounted) return;

    setState(() {
      _playStoreChecked = true;
      _playStoreAvailable = available;
    });
  }

  Future<void> _startDownload() async {
    setState(() {
      _errorMessage = null;
      _installPermissionDenied = false;
      _isDownloading = true;
      _progress = 0;
    });

    try {
      final apkFile = await UpdateService.instance.downloadApk(
        widget.updateInfo.downloadUrl,
        (progress) {
          setState(() {
            _progress = progress.clamp(0, 1);
          });
        },
      );

      await UpdateService.instance.installApk(apkFile);
      if (!mounted) return;

      setState(() {
        _isInstalled = true;
      });
    } catch (error) {
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'UPDATE_GATE_DOWNLOAD_FAILED',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {
                'stage': 'start_download',
                'downloadUrl': widget.updateInfo.downloadUrl,
              },
            ),
          );
        } catch (_) {}
      });
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        if (error is InstallPermissionDeniedException ||
            error.toString().contains('REQUEST_INSTALL_PACKAGES') ||
            error.toString().contains('Permission denied')) {
          _installPermissionDenied = true;
          _errorMessage =
              'DollApp necesita permiso para instalar apps desconocidas. Abre ajustes y activa el permiso para continuar.';
        } else {
          _errorMessage =
              'No se pudo descargar o instalar la actualización. Verifica tu conexión e intenta de nuevo.';
        }
      });
    }
  }

  Future<void> _openPlayStore() async {
    try {
      await UpdateService.instance.openPlayStore();
    } catch (error) {
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'UPDATE_GATE_OPEN_PLAY_STORE_FAILED',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {'stage': 'open_play_store'},
            ),
          );
        } catch (_) {}
      });
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No se pudo abrir Play Store. Intenta nuevamente más tarde.';
      });
    }
  }

  Future<void> _startUpdate() async {
    if (UpdateService.instance.hasPlayStoreLink && !_playStoreChecked) {
      await _resolvePlayStoreAvailability();
    }

    if (_playStoreAvailable) {
      await _openPlayStore();
      return;
    }

    final canInstall = await UpdateService.instance
        .canInstallFromUnknownSources();
    if (!canInstall) {
      if (!mounted) return;
      setState(() {
        _installPermissionDenied = true;
        _errorMessage =
            'DollApp necesita permiso para instalar apps desconocidas antes de descargar la actualización.';
      });
      return;
    }

    await _startDownload();
  }

  Future<void> _openInstallUnknownAppsSettings() async {
    try {
      await UpdateService.instance.openInstallUnknownAppsSettings();
    } catch (error) {
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'UPDATE_GATE_OPEN_SETTINGS_FAILED',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {'stage': 'open_install_unknown_apps_settings'},
            ),
          );
        } catch (_) {}
      });
      // Error al abrir ajustes de instalación
    }
  }

  Future<LottieComposition?> _dotLottieDecoder(List<int> bytes) {
    return LottieComposition.decodeZip(
      bytes,
      filePicker: (files) {
        return files.firstWhere(
          (file) =>
              file.name.startsWith('animations/') &&
              file.name.endsWith('.json'),
          orElse: () => files.first,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '¡Tenemos una nueva versión de DollApp para tí!',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Instala la versión (${widget.updateInfo.versionName}) para ver mejoras, correcciones y una mejor experiencia.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            colorScheme.primary.withValues(alpha: 0.14),
                            Colors.transparent,
                          ],
                          center: Alignment(0, -0.5),
                          radius: 0.75,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Lottie.asset(
                      'assets/animation/Rocket.lottie',
                      decoder: _dotLottieDecoder,
                      fit: BoxFit.contain,
                      repeat: true,
                      frameRate: FrameRate.composition,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.rocket_launch_rounded,
                          size: 100,
                          color: colorScheme.primary,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Novedades',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.updateInfo.news,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
              Text(
                '${(_progress * 100).toStringAsFixed(0)} % descargado',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ] else ...[
              ElevatedButton(
                onPressed:
                    (_playStoreChecked ||
                        !UpdateService.instance.hasPlayStoreLink)
                    ? _startUpdate
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    !_playStoreChecked &&
                            UpdateService.instance.hasPlayStoreLink
                        ? 'Verificando Play Store...'
                        : _playStoreAvailable
                        ? 'Abrir Play Store'
                        : 'Actualizar ahora',
                  ),
                ),
              ),
              if (!widget.updateInfo.isMandatory) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Recordar más tarde'),
                  ),
                ),
              ],
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_installPermissionDenied) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _openInstallUnknownAppsSettings,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Abrir ajustes de instalación'),
                ),
              ),
            ],
            if (_isInstalled) ...[
              const SizedBox(height: 14),
              Text(
                'La descarga terminó. Sigue las instrucciones del instalador para actualizar DollApp.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (widget.updateInfo.isMandatory)
              Text(
                'Esta actualización es obligatoria. Debes instalarla para seguir usando DollApp.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
