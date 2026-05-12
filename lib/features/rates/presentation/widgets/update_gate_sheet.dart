import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/services/update_service.dart';

Future<void> showUpdateGateSheet(
  BuildContext context,
  UpdateInfo updateInfo,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
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
  String? _errorMessage;
  bool _isInstalled = false;

  Future<void> _startDownload() async {
    setState(() {
      _errorMessage = null;
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
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo descargar o instalar la actualización. Verifica tu conexión e intenta de nuevo.';
        _isDownloading = false;
      });
    }
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
              '¡Tenemos mejoras para ti! Ahora DollApp es más rápido.',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Instala la última versión para ver mejoras, correcciones y una experiencia más fluida.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 160,
              child: Center(
                child: Lottie.network(
                  'https://assets7.lottiefiles.com/packages/lf20_op6zjz8f.json',
                  fit: BoxFit.contain,
                  repeat: true,
                  frameRate: FrameRate.composition,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.rocket_launch_rounded,
                      size: 82,
                      color: colorScheme.primary,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoTile(context, 'Versión', widget.updateInfo.versionName),
            const SizedBox(height: 12),
            Text(
              'Novedades',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              widget.updateInfo.changelog,
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
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: _startDownload,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Actualizar ahora'),
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

  Widget _buildInfoTile(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}
