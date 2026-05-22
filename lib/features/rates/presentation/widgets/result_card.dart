import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/trend_indicator.dart';
import '../../models/exchange_rate.dart';

class ResultCard extends StatelessWidget {
  const ResultCard({required this.result, required this.rate, super.key});

  final double result;
  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: .56),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultado',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                CurrencyFormatter.bolivar(result),
                key: ValueKey(result.toStringAsFixed(2)),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tasa usada: ${rate.name} = ${CurrencyFormatter.money(rate.displayValue ?? rate.value, rate.displayCurrencyCode ?? 'VES')}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Última consulta: ${_timeLabel(rate.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.payments_outlined,
                  text: 'Moneda: ${rate.displayCurrencyCode ?? rate.moneyType ?? rate.code}',
                ),
                if (rate.conversionCode != null)
                  _InfoChip(
                    icon: Icons.sync_alt_rounded,
                    text: 'Convierte: ${rate.conversionCode}',
                  ),
                if (rate.sourceUpdatedAtLabel != null)
                  _InfoChip(
                    icon: Icons.event_available_outlined,
                    text: 'Actualizada el ${rate.sourceUpdatedAtLabel}',
                  ),
              ],
            ),
            if (rate.keptPreviousValue) ...[
              const SizedBox(height: 10),
              Text(
                'No se pudo actualizar el monto por problemas con el servidor.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: .55)),
            const SizedBox(height: 14),
            if (rate.hasTrend) _HistoryTrend(rate: rate),
            if (!rate.hasTrend) const _NoTrendNotice(),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime date) {
    final hour = date.hour == 0
        ? 12
        : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _HistoryTrend extends StatelessWidget {
  const _HistoryTrend({required this.rate});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
  
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historial de variación',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
       
            TrendIndicator(
              changePercent: rate.changePercent,
              isUp: rate.isUp,
              compact: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: rate.historyPoints.map((point) {
            return _InfoChip(
              icon: Icons.history_rounded,
              text:
                  '${_dateLabel(point.date)}: ${CurrencyFormatter.money(point.value, point.currencyCode)}',
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'Desde la tasa anterior hasta la actualización actual.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }
}

class _NoTrendNotice extends StatelessWidget {
  const _NoTrendNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.onSurfaceVariant.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: colorScheme.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Se mostrará cuando la API entregue al menos una tasa anterior.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
