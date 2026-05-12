import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/mini_sparkline.dart';
import '../../../../core/widgets/trend_indicator.dart';
import '../../models/exchange_rate.dart';

class RateCard extends StatelessWidget {
  const RateCard({required this.rate, required this.onTap, super.key});

  final ExchangeRate rate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currencyColor = _currencyColor(rate.code, colorScheme.primary);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              final header = _RateHeader(
                rate: rate,
                currencyColor: currencyColor,
              );
              final value = _RateValue(rate: rate);

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _RateMetaInfo(rate: rate)),
                        const SizedBox(width: 8),
                        value,
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        const SizedBox(height: 10),
                        _RateMetaInfo(rate: rate),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  value,
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Color _currencyColor(String code, Color fallback) {
    return switch (code) {
      'USD' => AppColors.accentGreen,
      'EUR' => const Color(0xFF1D4ED8),
      'COP' => const Color(0xFF003893),
      _ => fallback,
    };
  }
}

class _RateHeader extends StatelessWidget {
  const _RateHeader({required this.rate, required this.currencyColor});

  final ExchangeRate rate;
  final Color currencyColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: currencyColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              rate.symbol,
              style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rate.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                rate.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (rate.keptPreviousValue) ...[
                const SizedBox(height: 8),
                Text(
                  'La API devolvió 0,00. Se muestra la última actualización conocida.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RateValue extends StatelessWidget {
  const _RateValue({required this.rate});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    final trendColor = rate.isUp
        ? AppColors.positiveGreen
        : AppColors.negativeRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          CurrencyFormatter.money(
            rate.displayValue ?? rate.value,
            rate.displayCurrencyCode ?? rate.code,
          ),
          textAlign: TextAlign.end,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (rate.hasTrend) ...[
          const SizedBox(height: 4),
          MiniSparkline(values: rate.sparklineValues, color: trendColor),
          const SizedBox(height: 8),
          TrendIndicator(
            changePercent: rate.changePercent,
            isUp: rate.isUp,
            compact: true,
          ),
        ] else ...[
          const SizedBox(height: 8),
          const _TrendUnavailableBadge(),
        ],
      ],
    );
  }
}

class _RateMetaInfo extends StatelessWidget {
  const _RateMetaInfo({required this.rate});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RateMetaLine(
          icon: Icons.payments_outlined,
          text: 'Moneda: ${rate.displayCurrencyCode ?? rate.moneyType ?? rate.code}',
        ),
        if (rate.conversionCode != null) ...[
          const SizedBox(height: 5),
          _RateMetaLine(
            icon: Icons.sync_alt_rounded,
            text: 'Convierte: ${rate.conversionCode}',
          ),
        ],
        if (rate.sourceUpdatedAtLabel != null) ...[
          const SizedBox(height: 5),
          _RateMetaLine(
            icon: Icons.event_available_outlined,
            text: rate.sourceUpdatedAtLabel!,
          ),
        ],
      ],
    );
  }
}

class _RateMetaLine extends StatelessWidget {
  const _RateMetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 40) {
          return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          );
        }

        return Row(
          children: [
            Icon(icon, size: 14, color: colorScheme.primary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrendUnavailableBadge extends StatelessWidget {
  const _TrendUnavailableBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.onSurfaceVariant.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Gráfica no disponible',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
