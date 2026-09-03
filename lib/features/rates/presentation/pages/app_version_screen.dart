import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_background.dart';
import '../widgets/version_info_card.dart';

class AppVersionScreen extends StatelessWidget {
  const AppVersionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        foregroundColor: isDark ? AppColors.white : AppColors.forestGreen,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'VERSIÓN DE LA APLICACIÓN',
          style: TextStyle(fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: AppBackground(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  children: [
                    VersionInfoCard(
                      padding: const EdgeInsets.all(22),
                      children: [
                        Center(
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  'assets/images/icon.jpg',
                                  width: 84,
                                  height: 84,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'DollApp',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tus tasas al día',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    VersionInfoCard(
                      children: const [
                        _DynamicVersionRow(),
                        _InfoRow(label: 'Estado', value: 'v1.0'),
                        _InfoRow(
                          label: 'Última actualización',
                          value: '02/09/2026',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    VersionInfoCard(
                      children: [
                        Text(
                          'Descripción',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'DollApp te permite consultar tasas de cambio, comparar referencias y calcular conversiones de forma rápida, clara y sencilla.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    VersionInfoCard(
                        children: [
                          Text(
                            'Información legal',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Consulta cómo funciona DollApp y cómo manejamos la información.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                          ),
                          const SizedBox(height: 10),
                          _LegalAction(
                            icon: Icons.privacy_tip_outlined,
                            label: 'Política de privacidad',
                            onTap: () => _showPolicyDialog(
                              context,
                              title: 'Política de privacidad',
                              sections: _privacySections,
                            ),
                          ),
                          const Divider(height: 1),
                          _LegalAction(
                            icon: Icons.gavel_rounded,
                            label: 'Términos y condiciones',
                            onTap: () => _showPolicyDialog(
                              context,
                              title: 'Términos y condiciones',
                              sections: _termsSections,
                            ),
                          ),
                        ],
                      ),
             
                    const SizedBox(height: 14),
                    VersionInfoCard(
                      children: [
                        Text(
                          'Fuentes de datos',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 12),
                        const _FeatureTile(
                          icon: Icons.account_balance_rounded,
                          text: 'Banco Central de Venezuela',
                        ),

                        const _FeatureTile(
                          icon: Icons.account_balance_rounded,
                          text: 'Tasa de Cambio Internacional',
                        ),

                        const _FeatureTile(
                          icon: Icons.currency_exchange_rounded,
                          text: 'TRM Colombia',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    VersionInfoCard(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Las tasas mostradas son informativas. DollApp no realiza operaciones cambiarias ni financieras.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.45,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    VersionInfoCard(
                      children: [
                        Text(
                          'Características',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 12),
                        const _FeatureTile(
                          icon: Icons.trending_up_rounded,
                          text: 'Consulta de tasas BCV, EUR, CNY, COP y más.',
                        ),

                        const _FeatureTile(
                          icon: Icons.calculate_rounded,
                          text: 'Calculadora rápida',
                        ),
                        const _FeatureTile(
                          icon: Icons.dark_mode_rounded,
                          text: 'Modo oscuro',
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '© 2026 Devsparra. Todos los derechos reservados.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showPolicyDialog(
  BuildContext context, {
  required String title,
  required List<_PolicySectionData> sections,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Última actualización: septiembre de 2026',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              ...sections.map(
                (section) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _PolicySection(section: section),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

class _LegalAction extends StatelessWidget {
  const _LegalAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _PolicySectionData {
  const _PolicySectionData(this.title, this.body);

  final String title;
  final String body;
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.section});

  final _PolicySectionData section;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          section.body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

const _privacySections = <_PolicySectionData>[
  _PolicySectionData(
    'Qué información manejamos',
    'DollApp no solicita cuentas ni recopila nombres, correos, teléfonos, contactos, ubicación, fotos o información financiera personal. La aplicación guarda localmente algunas preferencias y tasas en caché para funcionar sin conexión.',
  ),
  _PolicySectionData(
    'Diagnóstico y mejora',
    'Si la aplicación presenta un problema, podemos enviar información relacionada con ese fallo únicamente para diagnosticarlo, corregirlo y mejorar su estabilidad. No se envía el contenido de tus conversiones ni tus datos personales.',
  ),
  _PolicySectionData(
    'Fuentes y conexiones',
    'Las tasas se consultan desde fuentes públicas y servicios externos de datos. Las conexiones se realizan mediante HTTPS. No usamos publicidad personalizada ni servicios de analítica de terceros.',
  ),
  _PolicySectionData(
    'Contacto',
    'Responsable: devsparra. Para consultas sobre privacidad, escribe a wilmerparragomez@gmail.com.',
  ),
];

const _termsSections = <_PolicySectionData>[
  _PolicySectionData(
    'Aceptación y uso',
    'Al instalar o utilizar DollApp aceptas estos términos. La aplicación está destinada a la consulta personal de tasas, conversiones y tendencias; no es un servicio de intermediación financiera.',
  ),
  _PolicySectionData(
    'Carácter informativo',
    'Las tasas provienen de fuentes públicas y reconocidas. Pueden presentar retrasos, variaciones, redondeos o interrupciones. Verifica el valor con la fuente correspondiente antes de realizar una operación.',
  ),
  _PolicySectionData(
    'Responsabilidad',
    'DollApp no garantiza que los valores coincidan con los aplicados por bancos, comercios u otras instituciones y no se responsabiliza por decisiones tomadas únicamente con base en la información mostrada.',
  ),
  _PolicySectionData(
    'Disponibilidad y cambios',
    'Podemos actualizar, modificar o retirar funciones, fuentes o contenidos de la aplicación. La disponibilidad puede verse afectada por conectividad, mantenimiento o cambios en servicios externos.',
  ),
  _PolicySectionData(
    'Uso prohibido',
    'No está permitido utilizar DollApp para actividades ilegales, interferir con su funcionamiento, intentar acceder sin autorización a sus servicios o modificar, descompilar y redistribuir la aplicación.',
  ),
  _PolicySectionData(
    'Contacto',
    'Responsable: devsparra. Para consultas sobre estos términos, escribe a wilmerparragomez@gmail.com.',
  ),
];

class _DynamicVersionRow extends StatelessWidget {
  const _DynamicVersionRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final version = info?.version ?? 'Cargando...';

        return _InfoRow(label: 'Versión', value: version);
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: .11),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
