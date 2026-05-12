import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/mini_sparkline.dart';
import '../../../../core/widgets/trend_indicator.dart';
import '../../models/exchange_rate.dart';

class RateTrendCard extends StatelessWidget {
  const RateTrendCard({required this.rate, super.key});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    final color = rate.isUp ? AppColors.positiveGreen : AppColors.negativeRed;
    final colorScheme = Theme.of(context).colorScheme;

    if (!rate.hasTrend) {
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

    return Row(
      children: [
        Expanded(
          child: MiniSparkline(
            values: rate.sparklineValues,
            color: color,
            height: 36,
          ),
        ),
        const SizedBox(width: 12),
        TrendIndicator(changePercent: rate.changePercent, isUp: rate.isUp),
      ],
    );
  }
}
