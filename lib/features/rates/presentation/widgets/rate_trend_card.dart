import 'package:flutter/material.dart';

import '../../../../core/widgets/trend_indicator.dart';
import '../../models/exchange_rate.dart';

class RateTrendCard extends StatelessWidget {
  const RateTrendCard({required this.rate, super.key});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
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
 
        TrendIndicator(changePercent: rate.changePercent, isUp: rate.isUp),
      ],
    );
  }
}
