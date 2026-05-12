import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/currency_formatter.dart';

class TrendIndicator extends StatelessWidget {
  const TrendIndicator({
    required this.changePercent,
    required this.isUp,
    this.compact = false,
    super.key,
  });

  final double changePercent;
  final bool isUp;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = isUp ? AppColors.positiveGreen : AppColors.negativeRed;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: color,
            size: compact ? 15 : 17,
          ),
          const SizedBox(width: 4),
          Text(
            CurrencyFormatter.percent(changePercent),
            style: TextStyle(
              color: color,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
