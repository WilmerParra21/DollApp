import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        title: const Text('VERSIÓN DE LA APLICACIÓN', style: TextStyle(fontSize: 16),),
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
                                  'assets/images/logo.png',
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
                        _InfoRow(label: 'Versión', value: '1.0.2'),
                        _InfoRow(label: 'Estado', value: 'Alpha v1'),
                        _InfoRow(
                          label: 'Última actualización',
                          value: '10/05/2026',
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
                          text: 'Binance',
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
                          text: 'Consulta de tasas BCV, EUR, USDT y COP',
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
                      '© 2026 DollApp. Todos los derechos reservados.',
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
