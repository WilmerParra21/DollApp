import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/mini_sparkline.dart';
import '../../../../core/widgets/trend_indicator.dart';
import '../../data/http_exchange_rate_repository.dart';
import '../../models/exchange_rate.dart';
import '../../models/exchange_rate_snapshot.dart';
import '../../utils/exchange_pair_quote.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({
    this.fixedRateId,
    this.fixedRateCode,
    this.initialFromCode,
    this.initialToCode,
    super.key,
  });

  final String? fixedRateId;
  final String? fixedRateCode;
  final String? initialFromCode;
  final String? initialToCode;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final TextEditingController _amountController = TextEditingController(
    text: '1',
  );
  static const List<int> _quickAmounts = [1, 5, 10, 20, 50, 100];
  late final ValueNotifier<ExchangeRateSnapshot?> _snapshotNotifier;

  ExchangeRateSnapshot? _bootSnapshot;
  bool _appliedRouteDirection = false;
  bool _fixedQuoteInvalid = false;
  ParsedQuote? _activeQuote;
  bool _missingQuoteBinding = false;
  bool _isLoading = true;
  bool _isRefreshing = false;

  String _fromCode = '';
  String _toCode = '';
  int _selectedQuickAmount = 1;

  @override
  void initState() {
    super.initState();
    _snapshotNotifier = HttpExchangeRateRepository.instance.snapshotNotifier;
    _loadCachedSnapshot();
    _startBackgroundRefresh();

  }

  Future<void> _loadCachedSnapshot() async {
    final cached = await HttpExchangeRateRepository.instance.loadSavedSnapshot();
    if (!mounted) return;

    if (cached != null) {
      setState(() {
        _bootSnapshot ??= cached;
        _applyRouteDirectionOnce(cached);
        _rebindActiveQuote(cached);
        _isLoading = false;
      });
    }
  }

  Future<void> _startBackgroundRefresh() async {
    try {
      final latest = await HttpExchangeRateRepository.instance.getRates(
        forceRefresh: true,
      );
      if (!mounted) return;

      setState(() {
        _bootSnapshot ??= latest;
        _applyRouteDirectionOnce(latest);
        _rebindActiveQuote(latest);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (_bootSnapshot == null) {
        setState(() {
          _isLoading = false;
        });
      } else {
        _showSnackBar(
          'No se pudo actualizar la tasa. Se muestran datos locales.',
        );
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _amount {
    return double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;
  }

  void _applyRouteDirectionOnce(ExchangeRateSnapshot snapshot) {
    if (_appliedRouteDirection) return;

    final rawFrom = widget.initialFromCode?.trim();
    final rawTo = widget.initialToCode?.trim();
    if (rawFrom != null &&
        rawFrom.isNotEmpty &&
        rawTo != null &&
        rawTo.isNotEmpty) {
      _fromCode = canonicalCurrencyCode(rawFrom);
      _toCode = canonicalCurrencyCode(rawTo);
      _appliedRouteDirection = true;
      return;
    }

    final fixedId = widget.fixedRateId?.trim();
    if (fixedId != null && fixedId.isNotEmpty) {
      final rate = snapshot.tryById(fixedId);
      if (rate == null) {
        return;
      }
      final parsed = tryParseQuote(rate);
      if (parsed == null) {
        _fixedQuoteInvalid = true;
        return;
      }
      _fromCode = parsed.anchor;
      _toCode = parsed.counter;
      _appliedRouteDirection = true;
      return;
    }

    final fixed = widget.fixedRateCode?.trim();
    if (fixed != null && fixed.isNotEmpty) {
      final rate = snapshot.tryByCode(fixed);
      if (rate == null) {
        return;
      }
      final parsed = tryParseQuote(rate);
      if (parsed == null) {
        _fixedQuoteInvalid = true;
        return;
      }
      _fromCode = parsed.anchor;
      _toCode = parsed.counter;
      _appliedRouteDirection = true;
      return;
    }

    ParsedQuote? firstParsed;
    for (final rate in snapshot.rates) {
      final parsed = tryParseQuote(rate);
      if (parsed != null) {
        firstParsed = parsed;
        break;
      }
    }

    if (firstParsed != null) {
      _fromCode = firstParsed.anchor;
      _toCode = firstParsed.counter;
    }
    _appliedRouteDirection = true;
  }

  void _rebindActiveQuote(ExchangeRateSnapshot snapshot) {
    if (!_appliedRouteDirection) {
      _activeQuote = null;
      _missingQuoteBinding = false;
      return;
    }

    ParsedQuote? q;
    final fixedId = widget.fixedRateId?.trim();
    if (fixedId != null && fixedId.isNotEmpty) {
      final fixedRate = snapshot.tryById(fixedId);
      if (fixedRate != null) {
        final parsed = tryParseQuote(fixedRate);
        if (parsed != null) {
          final from = canonicalCurrencyCode(_fromCode);
          final to = canonicalCurrencyCode(_toCode);
          if ((parsed.anchor == from && parsed.counter == to) ||
              (parsed.anchor == to && parsed.counter == from)) {
            q = parsed;
          }
        }
      }
    }

    q ??= findQuoteForCurrencyPair(snapshot, _fromCode, _toCode);
    if (q == null) {
      _activeQuote = null;
      _missingQuoteBinding = true;
    } else {
      _activeQuote = q;
      _missingQuoteBinding = false;
    }
  }

  double _computedNumericResult() {
    if (_missingQuoteBinding || _activeQuote == null) {
      return double.nan;
    }
    try {
      return _activeQuote!.convert(_amount, _fromCode, _toCode);
    } on ArgumentError {
      return double.nan;
    }
  }

  ExchangeRate? _resolvedRowForTrend() => _activeQuote?.row;

  String _formattedResult() {
    final value = _computedNumericResult();
    if (value.isNaN || value.isInfinite) {
      return '—';
    }
    return CurrencyFormatter.moneyRate(value, _toCode);
  }

  String _formattedRateLabel() {
    final quote = _activeQuote;
    final rate = quote?.row;
    if (quote == null || rate == null) {
      return 'No hay tasa cargada para este par.';
    }

    final n = quote.unitsPerAnchor;
    if (!n.isFinite || n <= 0) {
      return 'No hay tasa cargada para este par.';
    }

    final reciprocal = 1.0 / n;
    final conversionLabel = ' (${quote.anchor}/${quote.counter})';

    // Misma formula que usa el resultado: identica al boton invertir (x o / por N).
    final direct =
        '1 ${quote.anchor} = ${CurrencyFormatter.moneyRate(n, quote.counter)}';
    final reciprocalLine =
        '1 ${quote.counter} = ${CurrencyFormatter.moneyRate(reciprocal, quote.anchor)}';

    return 'Tasa usada · ${rate.name}$conversionLabel\n'
        '$direct\n'
        '$reciprocalLine';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBackground = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;
    final appBarForeground = isDark ? AppColors.white : AppColors.forestGreen;

    return Scaffold(
      backgroundColor: appBarBackground,
      appBar: AppBar(
        backgroundColor: appBarBackground,
        foregroundColor: appBarForeground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Volver',
          style: IconButton.styleFrom(
            foregroundColor: appBarForeground,
            backgroundColor: appBarForeground.withValues(alpha: .08),
          ),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Calculadora"),
      ),
      body: SafeArea(
        child: AppBackground(
          child: SizedBox.expand(
            child: ValueListenableBuilder<ExchangeRateSnapshot?>(
              valueListenable: _snapshotNotifier,
              builder: (context, snapshot, child) {
                final ratesSnapshot = snapshot ?? _bootSnapshot;
                final isLoading = _isLoading && ratesSnapshot == null;

                if (isLoading) {
                  return const _CalculatorSkeleton();
                }

                if (ratesSnapshot == null) {
                  return _QuoteLoadProblem(onRetry: _refreshRates);
                }

                if (_fixedQuoteInvalid) {
                  return _InvalidFixedRateProblem(onRetry: _refreshRates);
                }

                final rowForUi = _resolvedRowForTrend();
                if (_missingQuoteBinding || rowForUi == null || _activeQuote == null) {
                  return _QuoteLoadProblem(onRetry: _refreshRates);
                }

                final currencyNames = _namesForCalculatorPair(ratesSnapshot);
                final currencyBadges = _badgesForCalculatorPair(ratesSnapshot);

                return _CalculatorContent(
                  amountController: _amountController,
                  quickAmounts: _quickAmounts,
                  selectedQuickAmount: _selectedQuickAmount,
                  fromCode: _fromCode,
                  toCode: _toCode,
                  currencyNames: currencyNames,
                  currencyBadges: currencyBadges,
                  selectedRate: rowForUi,
                  amount: _amount,
                  formattedResult: _formattedResult(),
                  rateLabel: _formattedRateLabel(),
                  onAmountChanged: () => setState(() => _selectedQuickAmount = -1),
                  onClear: _clear,
                  onCopy: _copyResult,
                  onPickFrom: _noopPickHandler,
                  onPickTo: _noopPickHandler,
                  onSwap: () => _swapCurrencies(ratesSnapshot),
                  onQuickAmount: _setQuickAmount,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _noopPickHandler() {}

  Future<void> _refreshRates() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _fixedQuoteInvalid = false;
    });

    try {
      final latest = await HttpExchangeRateRepository.instance.getRates(
        forceRefresh: true,
      );
      if (!mounted) return;

      setState(() {
        _bootSnapshot ??= latest;
        _applyRouteDirectionOnce(latest);
        _rebindActiveQuote(latest);
      });
    } catch (_) {
      if (mounted) {
        _showSnackBar('No se pudo cargar la tasa para cotizar.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _swapCurrencies(ExchangeRateSnapshot snapshot) {
    setState(() {
      final previousFrom = _fromCode;
      _fromCode = _toCode;
      _toCode = previousFrom;
      _rebindActiveQuote(snapshot);
    });
  }

Map<String, String> _namesForCalculatorPair(ExchangeRateSnapshot snapshot) {
    return {
      for (final entry in {_fromCode, _toCode}.map((c) => canonicalCurrencyCode(c)))
        entry: entry,
    };
  }

  Map<String, String> _badgesForCalculatorPair(ExchangeRateSnapshot snapshot) {
    final badges = <String, String>{};
    for (final code in {_fromCode, _toCode}.map((c) => canonicalCurrencyCode(c)).toSet()) {
      final matchingRate = snapshot.rates.firstWhere(
        (r) => r.displayCurrencyCode?.toUpperCase() == code.toUpperCase() ||
                 r.code.toUpperCase() == code.toUpperCase(),
        orElse: () => snapshot.rates.firstWhere(
          (r) => r.conversionCode?.toUpperCase() == code.toUpperCase(),
          orElse: () => snapshot.rates.first,
        ),
      );
      badges[code] = matchingRate.symbol;
    }
    return badges;
  }

  void _setQuickAmount(int amount) {
    setState(() {
      _selectedQuickAmount = amount;
      _amountController.text = amount.toString();
      _amountController.selection = TextSelection.fromPosition(
        TextPosition(offset: _amountController.text.length),
      );
    });
  }

  void _clear() {
    setState(() {
      _selectedQuickAmount = -1;
      _amountController.text = '';
      _amountController.selection = TextSelection.fromPosition(
        TextPosition(offset: _amountController.text.length),
      );
    });
  }

  Future<void> _copyResult() async {
    final numeric = _computedNumericResult();
    if (numeric.isNaN || numeric.isInfinite) {
      _showSnackBar('No hay tasa disponible para copiar el resultado.');
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: CurrencyFormatter.decimal(numeric)),
    );
    _showSnackBar('Resultado copiado');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _QuoteLoadProblem extends StatelessWidget {
  const _QuoteLoadProblem({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No se pudo cargar la tasa para cotizar. '
              'Revisa tu conexion e intenta de nuevo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvalidFixedRateProblem extends StatelessWidget {
  const _InvalidFixedRateProblem({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'La tasa seleccionada no tiene datos válidos para cotizar '
              '(monto igual o menor a cero).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalculatorContent extends StatelessWidget {
  const _CalculatorContent({
    required this.amountController,
    required this.quickAmounts,
    required this.selectedQuickAmount,
    required this.fromCode,
    required this.toCode,
    required this.currencyNames,
    required this.currencyBadges,
    required this.selectedRate,
    required this.amount,
    required this.formattedResult,
    required this.rateLabel,
    required this.onAmountChanged,
    required this.onClear,
    required this.onCopy,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSwap,
    required this.onQuickAmount,
  });

  final TextEditingController amountController;
  final List<int> quickAmounts;
  final int selectedQuickAmount;
  final String fromCode;
  final String toCode;
  final Map<String, String> currencyNames;
  final Map<String, String> currencyBadges;
  final ExchangeRate selectedRate;
  final double amount;
  final String formattedResult;
  final String rateLabel;
  final VoidCallback onAmountChanged;
  final VoidCallback onClear;
  final VoidCallback onCopy;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSwap;
  final ValueChanged<int> onQuickAmount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPadding = 36.0;
        final minHeight = constraints.maxHeight > verticalPadding
            ? constraints.maxHeight - verticalPadding
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520, minHeight: minHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AmountField(
                    controller: amountController,
                    onChanged: onAmountChanged,
                    onClear: onClear,
                    currency: currencyNames[fromCode]!
                  ),
                  const SizedBox(height: 18),
                  _CurrencyFlow(
                    fromCode: fromCode,
                    toCode: toCode,
                    currencyNames: currencyNames,
                    currencyBadges: currencyBadges,
                    onPickFrom: onPickFrom,
                    onPickTo: onPickTo,
                    onSwap: onSwap,
                  ),
                  const SizedBox(height: 18),
                  _ResultPanel(
                    amount: amount,
                    fromCode: fromCode,
                    toCode: toCode,
                    formattedResult: formattedResult,
                    rateLabel: rateLabel,
                    rate: selectedRate,
                    onCopy: onCopy,
                  ),
                  const SizedBox(height: 12),
                  _ActionButtons(onCopy: onCopy, onClear: onClear),
                  const SizedBox(height: 16),
                  Text(
                    'Montos rapidos',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _QuickAmounts(
                    amounts: quickAmounts,
                    selectedAmount: selectedQuickAmount,
                    onAmountSelected: onQuickAmount,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.currency, 
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClear;
  final String currency;
  
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
  
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monto',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
  controller: controller,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
  ],
  onChanged: (_) => onChanged(),
  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.1, // Ajuste ligero para alineación vertical
      ),
  decoration: InputDecoration(
    hintText: '0',
    contentPadding: const EdgeInsets.only(right: 12), // Quitamos el padding izquierdo para que el prefijo pegue
    
    // USAMOS prefix PARA CONTROL TOTAL
    prefixIcon: Container(
      margin: const EdgeInsets.only(right: 12), // Espacio entre el fondo del símbolo y el número
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        // Color de fondo que ocupa toda la sección izquierda
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.04),
        // Redondeamos solo las esquinas de la izquierda para que encaje con el borde del TextField
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
      ),
      // Usamos Center con heightFactor para que el fondo se estire
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currency,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
    
    // ESTO ES CLAVE: Quitar las restricciones por defecto
    prefixIconConstraints: const BoxConstraints(
      minHeight: 64, // Ajusta esto al alto de tu TextField
      minWidth: 60,
    ),
    
    suffixIcon: IconButton(
      tooltip: 'Limpiar monto',
      icon: const Icon(Icons.cancel_rounded),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: onClear,
    ),
    
    // BORDES: Asegúrate de que el radio coincida con el del Container del prefijo
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    filled: true,
    fillColor: Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.02),
  ),
), ],
    );
  }
}

class _CurrencyFlow extends StatelessWidget {
  const _CurrencyFlow({
    required this.fromCode,
    required this.toCode,
    required this.currencyNames,
    required this.currencyBadges,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSwap,
  });

  final String fromCode;
  final String toCode;
  final Map<String, String> currencyNames;
  final Map<String, String> currencyBadges;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final from = _CurrencyPickerCard(
      label: 'Desde',
      code: fromCode,
      name: currencyNames[fromCode] ?? fromCode,
      badge: currencyBadges[fromCode] ?? fromCode,
    );
    final to = _CurrencyPickerCard(
      label: 'Hacia',
      code: toCode,
      name: currencyNames[toCode] ?? toCode,
      badge: currencyBadges[toCode] ?? toCode,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: from),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
          child: IconButton.filled(
            tooltip: 'Invertir',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
              foregroundColor: AppColors.white,
              fixedSize: const Size(44, 44),
            ),
            onPressed: onSwap,
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ),
        Expanded(child: to),
      ],
    );
  }
}

class _CurrencyPickerCard extends StatelessWidget {
  const _CurrencyPickerCard({
    required this.label,
    required this.code,
    required this.name,
    required this.badge,
  });

  final String label;
  final String code;
  final String name;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showName = name.trim().isNotEmpty && name.trim() != code.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: colorScheme.surface.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(12),
          child:  Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: .7),
                ),
              ),
              child: Row(
                children: [
                  _CurrencyMark(code: code, badge: badge),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (showName)
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
         
        ),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.amount,
    required this.fromCode,
    required this.toCode,
    required this.formattedResult,
    required this.rateLabel,
    required this.rate,
    required this.onCopy,
  });

  final double amount;
  final String fromCode;
  final String toCode;
  final String formattedResult;
  final String rateLabel;
  final ExchangeRate rate;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: .72),
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
          const SizedBox(height: 6),
          Text(
            '${CurrencyFormatter.moneyWithCode(amount, toCode)} a $fromCode',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formattedResult,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: AppColors.positiveGreen,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.copy_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: .65)),
          const SizedBox(height: 8),
          _DetailLine(icon: Icons.sell_outlined, text: rateLabel),
          if (rate.keptPreviousValue) ...[
            const SizedBox(height: 8),
            _DetailLine(
              icon: Icons.wifi_off_rounded,
              text: 'Usando la ultima tasa disponible.',
            ),
          ],
          const SizedBox(height: 12),
          _TrendPanel(rate: rate),
        ],
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.rate});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasTrend = rate.hasTrend;
    final color = rate.isUp ? AppColors.positiveGreen : AppColors.negativeRed;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.onSurfaceVariant.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: .58),
        ),
      ),
      child: hasTrend
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tendencia de la tasa',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      MiniSparkline(
                        values: rate.sparklineValues,
                        color: color,
                        height: 28,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                TrendIndicator(
                  changePercent: rate.changePercent,
                  isUp: rate.isUp,
                  compact: true,
                ),
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 17,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sin tasa anterior en el histórico.',
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

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.onCopy, required this.onClear});

  final VoidCallback onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar monto'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.positiveGreen,
              side: const BorderSide(color: AppColors.positiveGreen),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Limpiar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickAmounts extends StatelessWidget {
  const _QuickAmounts({
    required this.amounts,
    required this.selectedAmount,
    required this.onAmountSelected,
  });

  final List<int> amounts;
  final int selectedAmount;
  final ValueChanged<int> onAmountSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final itemWidth = (constraints.maxWidth - gap * 5) / 6;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: amounts.map((amount) {
            final isSelected = selectedAmount == amount;
            return SizedBox(
              width: itemWidth.clamp(44, 76),
              child: _QuickAmountButton(
                amount: amount,
                isSelected: isSelected,
                onTap: () => onAmountSelected(amount),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _QuickAmountButton extends StatelessWidget {
  const _QuickAmountButton({
    required this.amount,
    required this.isSelected,
    required this.onTap,
  });

  final int amount;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? AppColors.accentGreen
          : colorScheme.surface.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppColors.accentGreen
                  : colorScheme.outlineVariant.withValues(alpha: .7),
            ),
          ),
          child: Text(
            '$amount',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: isSelected ? AppColors.white : colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrencyMark extends StatelessWidget {
  const _CurrencyMark({required this.code, required this.badge});

  final String code;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final color = switch (code) {
      'USD' => AppColors.positiveGreen,
      'EUR' => const Color(0xFF2563EB),
      'COP' => const Color(0xFFFACC15),
      'VES' => const Color(0xFFDC2626),
      _ => Theme.of(context).colorScheme.primary,
    };

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Center(
        child: Text(
          badge,
          style: TextStyle(
            color: color,
            fontSize: badge.length > 2 ? 9 : 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

}

class _CalculatorSkeleton extends StatefulWidget {
  const _CalculatorSkeleton();

  @override
  State<_CalculatorSkeleton> createState() => _CalculatorSkeletonState();
}

class _CalculatorSkeletonState extends State<_CalculatorSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(opacity: 0.3 + 0.7 * _controller.value, child: child);
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(height: 72),
                SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _SkeletonBlock(height: 100)),
                    SizedBox(width: 8),
                    _SkeletonSwapButton(),
                    SizedBox(width: 8),
                    Expanded(child: _SkeletonBlock(height: 100)),
                  ],
                ),
                SizedBox(height: 18),
                _SkeletonBlock(height: 240),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _SkeletonBlock(height: 46)),
                    SizedBox(width: 10),
                    Expanded(child: _SkeletonBlock(height: 46)),
                  ],
                ),
                SizedBox(height: 16),
                _SkeletonBlock(height: 20, width: 120),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SkeletonBlock(height: 42, width: 50),
                    _SkeletonBlock(height: 42, width: 50),
                    _SkeletonBlock(height: 42, width: 50),
                    _SkeletonBlock(height: 42, width: 50),
                    _SkeletonBlock(height: 42, width: 50),
                    _SkeletonBlock(height: 42, width: 50),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height, this.width = double.infinity});

  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _SkeletonSwapButton extends StatelessWidget {
  const _SkeletonSwapButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
    );
  }
}
