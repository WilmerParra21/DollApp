import 'package:dollapp/core/models/audit_log.dart';
import 'package:dollapp/core/services/audit_service.dart';
import 'package:dollapp/core/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/no_consecutive_decimal_separator_formatter.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/trend_indicator.dart';
import '../../data/http_exchange_rate_repository.dart';
import '../../data/pinned_conversion_store.dart';
import '../../models/exchange_rate.dart';
import '../../models/exchange_rate_snapshot.dart';
import '../../utils/exchange_pair_quote.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({
    this.fixedRateId,
    this.fixedRateCode,
    this.initialFromCode,
    this.initialToCode,
    this.closeAppOnBack = false,
    this.onToggleTheme,
    super.key,
  });

  final String? fixedRateId;
  final String? fixedRateCode;
  final String? initialFromCode;
  final String? initialToCode;
  final bool closeAppOnBack;
  final VoidCallback? onToggleTheme;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final TextEditingController _amountController = TextEditingController(
    text: '',
  );
  static const List<int> _quickAmounts = [5, 10, 20, 50, 100];
  late final ValueNotifier<ExchangeRateSnapshot?> _snapshotNotifier;

  ExchangeRateSnapshot? _bootSnapshot;
  ExchangeRateSnapshot? _currentSnapshot;
  bool _appliedRouteDirection = false;
  bool _fixedQuoteInvalid = false;
  ParsedQuote? _activeQuote;
  bool _missingQuoteBinding = false;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isPinned = false;
  bool _offlineNoData = false;
  bool _isFetchingHistoricalRate = false;
  final Map<String, DateTime> _selectedHistoricalDateByRate = {};
  final Map<String, double> _historicalRateValuesByRate = {};
  final Map<String, ExchangeRate> _historicalTrendRatesByRate = {};

  String _fromCode = '';
  String _toCode = '';
  int _selectedQuickAmount = -1;

  @override
  void initState() {
    super.initState();
    _snapshotNotifier = HttpExchangeRateRepository.instance.snapshotNotifier;
    _snapshotNotifier.addListener(_onSnapshotUpdated);
    _loadPinnedStatus();
    _loadCachedSnapshot();
    _startBackgroundRefresh();
  }

  Future<void> _loadCachedSnapshot() async {
    final cached = await HttpExchangeRateRepository.instance
        .loadSavedSnapshot();
    if (!mounted) return;

    if (cached != null) {
      setState(() {
        _bootSnapshot ??= cached;
        _currentSnapshot ??= cached;
        _applyRouteDirectionOnce(cached);
        _rebindActiveQuote(cached);
        _maybeClearInvalidPinnedConversion(cached);
        _isLoading = false;
        _offlineNoData = false;
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _offlineNoData = true;
    });
  }

  Future<void> _loadPinnedStatus() async {
    final pinned = await PinnedConversionStore.loadPinnedConversion();
    if (!mounted) return;

    setState(() {
      _isPinned = _isCurrentConversionPinned(pinned);
    });
  }

  bool _isCurrentConversionPinned(PinnedConversion pinned) {
    final fixedId = widget.fixedRateId?.trim();
    final fixedCode = widget.fixedRateCode?.trim();
    final fromCode = widget.initialFromCode?.trim();
    final toCode = widget.initialToCode?.trim();

    if (pinned.rateId != null &&
        pinned.rateId!.isNotEmpty &&
        fixedId != null &&
        fixedId.isNotEmpty &&
        pinned.rateId == fixedId) {
      return true;
    }

    if (pinned.rateCode != null &&
        pinned.rateCode!.isNotEmpty &&
        fixedCode != null &&
        fixedCode.isNotEmpty &&
        pinned.rateCode == fixedCode) {
      return true;
    }

    if (pinned.fromCode != null &&
        pinned.toCode != null &&
        pinned.fromCode!.isNotEmpty &&
        pinned.toCode!.isNotEmpty &&
        fromCode != null &&
        fromCode.isNotEmpty &&
        toCode != null &&
        toCode.isNotEmpty &&
        pinned.fromCode!.trim() == fromCode &&
        pinned.toCode!.trim() == toCode) {
      return true;
    }

    return false;
  }

  Future<void> _startBackgroundRefresh() async {
    try {
      final latest = await HttpExchangeRateRepository.instance.getRates(
        forceRefresh: false,
      );
      if (!mounted) return;

      if (latest.usedFallback) {
        setState(() {
          _isLoading = false;
          _offlineNoData = false;
        });
        _showSnackBar(
          'Sin conexión a internet.',
        );
        return;
      }

      if (_bootSnapshot != null && !_canBindSnapshot(latest)) {
        _showSnackBar(
          'No se pudo actualizar la tasa fijada. Se mantiene la tasa anterior.',
        );
        return;
      }

      setState(() {
        _bootSnapshot = latest;
        _currentSnapshot = latest;
        _applyRouteDirectionOnce(latest);
        _rebindActiveQuote(latest);
        _maybeClearInvalidPinnedConversion(latest);
        _isLoading = false;
        _offlineNoData = false;
      });
    } catch (error) {
      if (error is RateRefreshLimitException ||
          error is RatesAlreadyUpdatedException) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _offlineNoData = false;
        });
        _showRatesAlreadyUpdatedNotice();
        return;
      }

      if (error is NetworkUnavailableException) {
        if (!mounted) return;
        _showSnackBar(
          'No se pudieron actualizar las tasas porque no hay conexión.',
        );
        if (_bootSnapshot == null) {
          setState(() {
            _isLoading = false;
            _offlineNoData = true;
          });
        }
        return;
      }

      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'CALCULATOR_BACKGROUND_REFRESH_FAILED',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {'stage': 'background_refresh'},
            ),
          );
        } catch (_) {}
      });
      if (!mounted) return;
      if (_bootSnapshot == null) {
        setState(() {
          _isLoading = false;
          _offlineNoData = true;
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
    _snapshotNotifier.removeListener(_onSnapshotUpdated);
    _amountController.dispose();
    super.dispose();
  }

  double get _amount {
    final text = _normalizedAmountText(_amountController.text);
    if (text.isEmpty) {
      // Sin monto escrito, la calculadora muestra la tasa del día tomando
      // como referencia una unidad de la moneda de origen.
      return 1;
    }
    return double.tryParse(text) ?? 0;
  }

  double? get _enteredAmount {
    final text = _normalizedAmountText(_amountController.text);
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String _normalizedAmountText(String value) {
    final cleaned = value.trim().replaceAll(' ', '');
    if (cleaned.isEmpty) {
      return '';
    }

    final hasComma = cleaned.contains(',');
    final hasDot = cleaned.contains('.');

    if (hasComma && hasDot) {
      return cleaned.replaceAll('.', '').replaceAll(',', '.');
    }

    if (hasComma && !hasDot) {
      return cleaned.replaceAll(',', '.');
    }

    if (hasDot && !hasComma) {
      final dotCount = '.'.allMatches(cleaned).length;
      if (dotCount > 1) {
        return cleaned.replaceAll('.', '');
      }

      final lastDotIndex = cleaned.lastIndexOf('.');
      if (cleaned.length - lastDotIndex - 1 == 3) {
        return cleaned.replaceAll('.', '');
      }
    }

    return cleaned;
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

  double _computedNumericResultForAmount(
    double enteredAmount, {
    double? historicalValue,
  }) {
    if (_missingQuoteBinding || _activeQuote == null) {
      return double.nan;
    }
    try {
      final selectedHistoricalValue = historicalValue ??
          _historicalRateValuesByRate[_activeQuote!.row.id];
      final unitsPerAnchor =
          (selectedHistoricalValue != null && selectedHistoricalValue > 0)
              ? selectedHistoricalValue
              : _activeQuote!.unitsPerAnchor;
      final quote = ParsedQuote(
        row: _activeQuote!.row,
        anchor: _activeQuote!.anchor,
        counter: _activeQuote!.counter,
        unitsPerAnchor: unitsPerAnchor,
      );
      return quote.convert(enteredAmount, _fromCode, _toCode);
    } on ArgumentError {
      return double.nan;
    }
  }

  double _computedNumericResult() {
    return _computedNumericResultForAmount(_amount);
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

    final historicalValue = _historicalRateValuesByRate[rate.id];
    final selectedDate = _selectedHistoricalDateByRate[rate.id];
    final usingHistorical = historicalValue != null &&
        historicalValue > 0 &&
        selectedDate != null;

    final n = usingHistorical ? historicalValue : quote.unitsPerAnchor;
    if (!n.isFinite || n <= 0) {
      return 'No hay tasa cargada para este par.';
    }

    final reciprocal = 1.0 / n;
    final conversionLabel = ' (${quote.anchor}/${quote.counter})';

    final direct =
        '1 ${quote.anchor} = ${CurrencyFormatter.moneyRate(n, quote.counter)}';
    final reciprocalLine =
        '1 ${quote.counter} = ${CurrencyFormatter.moneyRate(reciprocal, quote.anchor)}';

    if (usingHistorical) {
      return 'Tasa histórica · ${rate.name}$conversionLabel\n'
          '$direct\n'
          '$reciprocalLine';
    }

    return 'Tasa usada · ${rate.name}\n'
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

    final keyboardIsVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      // Permitir el back del sistema únicamente cuando la calculadora
      // anclada debe cerrar la app y no hay teclado visible. En los
      // demás casos onPopInvokedWithResult procesa el retroceso manualmente.
      canPop: widget.closeAppOnBack && !keyboardIsVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        // El primer retroceso con el monto enfocado debe cerrar únicamente el
        // teclado. Esto evita que la calculadora anclada cierre la app cuando
        // el usuario escribió y luego dejó el campo vacío.
        if (keyboardIsVisible) {
          FocusManager.instance.primaryFocus?.unfocus();
          return;
        }

        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: appBarBackground,
        appBar: AppBar(
          backgroundColor: appBarBackground,
          foregroundColor: appBarForeground,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: widget.closeAppOnBack ? 'Menú' : 'Volver',
            style: IconButton.styleFrom(
              foregroundColor: appBarForeground,
              backgroundColor: appBarForeground.withValues(alpha: .08),
            ),
            icon: Icon(
              widget.closeAppOnBack
                  ? Icons.menu_rounded
                  : Icons.arrow_back_rounded,
                  size: 28,
            ),
            onPressed: () {
              if (widget.closeAppOnBack) {
                Navigator.pushReplacementNamed(
                  context,
                  AppRoutes.home,
                  arguments: const HomeRouteArgs(skipPinnedRedirect: true),
                );
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: const Text('Calculadora'),
          actions: [
            IconButton(
              tooltip: _resolvedRowForTrend() == null
                  ? 'Fijar tasas de conversión al iniciar'
                  : (_resolvedRowForTrend()!.isFavorite
                      ? (_isPinned
                          ? 'Desfijar conversión al iniciar'
                          : 'Fijar conversión al iniciar')
                      : 'Solo favoritas se pueden fijar'),
              icon: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              ),
              onPressed: _showPinnedConversionSheet,
            ),
            if (widget.onToggleTheme != null)
              IconButton(
                tooltip: 'Cambiar tema',
                icon: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                ),
                onPressed: widget.onToggleTheme,
              ),
          ],
        ),
        body: SafeArea(
          child: AppBackground(
            child: RefreshIndicator(
              onRefresh: _refreshRates,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ValueListenableBuilder<ExchangeRateSnapshot?>(
                  valueListenable: _snapshotNotifier,
                  builder: (context, snapshot, child) {
                    final ratesSnapshot =
                        snapshot ?? _currentSnapshot ?? _bootSnapshot;
                    final isLoading = _isLoading && ratesSnapshot == null;

                    if (isLoading) {
                      return const _CalculatorSkeleton();
                    }

                    if (ratesSnapshot == null) {
                      return _QuoteLoadProblem(
                        onRetry: _refreshRates,
                        message: _offlineNoData
                            ? 'No hay conexión y no hay datos guardados. Conecta a internet para descargar las tasas reales.'
                            : 'No se pudo cargar la tasa para cotizar. Revisa tu conexión e intenta de nuevo.',
                      );
                    }

                    if (_fixedQuoteInvalid) {
                      return _InvalidFixedRateProblem(onRetry: _refreshRates);
                    }

                    final rowForUi = _resolvedRowForTrend();
                    if (_missingQuoteBinding ||
                        rowForUi == null ||
                        _activeQuote == null) {
                      return _QuoteLoadProblem(
                        onRetry: _refreshRates,
                        message:
                            'No se pudo cargar la tasa para cotizar. Revisa tu conexión e intenta de nuevo.',
                      );
                    }

                    final trendRateForUi =
                        _historicalTrendRatesByRate[rowForUi.id] ?? rowForUi;

                    final currencyNames = _namesForCalculatorPair(ratesSnapshot);
                    final currencyBadges = _badgesForCalculatorPair();

                    final favoriteRates = ratesSnapshot.rates
                        .where((rate) => rate.isFavorite)
                        .toList();
                    final canPin = rowForUi.isFavorite;
                    final hasFavoriteSelector =
                        favoriteRates.length > 1 && rowForUi.isFavorite;
                    final selectedHistoricalDate =
                        _selectedHistoricalDateByRate[rowForUi.id];

                    return _CalculatorContent(
                      amountController: _amountController,
                      quickAmounts: _quickAmounts,
                      selectedQuickAmount: _selectedQuickAmount,
                      fromCode: _fromCode,
                      toCode: _toCode,
                      currencyNames: currencyNames,
                      currencyBadges: currencyBadges,
                      selectedRate: trendRateForUi,
                      amount: _amount,
                      formattedResult: _formattedResult(),
                      rateLabel: _formattedRateLabel(),
                      selectedHistoricalDate: selectedHistoricalDate,
                      isPinned: _isPinned,
                      canPin: canPin,
                      otherFavoriteLabel: null,
                      onSwitchFavorite: hasFavoriteSelector
                          ? () => _showFavoriteSelector(
                              ratesSnapshot,
                              rowForUi,
                              favoriteRates,
                            )
                          : null,
                      onAmountChanged: () =>
                          setState(() => _selectedQuickAmount = -1),
                      onClear: _clear,
                      onCopy: _copyResult,
                      onPickFrom: _noopPickHandler,
                      onPickTo: _noopPickHandler,
                      onSwap: () => _swapCurrencies(ratesSnapshot),
                      onPinChanged: _togglePinnedConversion,
                      onQuickAmount: _setQuickAmount,
                      onRequestHistoricalDate: _requestHistoricalDate,
                      isFetchingHistoricalRate: _isFetchingHistoricalRate,
                      onOpenExpandedCalculator: _showExpandedCalculator,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _noopPickHandler() {}

  Future<void> _refreshRates() async {
    if (_isRefreshing ||
        HttpExchangeRateRepository.isRatesNoticeVisible) {
      return;
    }

    setState(() {
      _isRefreshing = true;
      _fixedQuoteInvalid = false;
    });

    try {
      final latest = await HttpExchangeRateRepository.instance.getRates(
        forceRefresh: true,
      );
      if (!mounted) return;

      if (latest.usedFallback) {
        _showSnackBar(
          'Sin conexión a internet.',
        );
        return;
      }

      if (_bootSnapshot != null && !_canBindSnapshot(latest)) {
        _showSnackBar(
          'No se pudo actualizar la tasa fijada. Se mantiene la tasa anterior.',
        );
        return;
      }

      setState(() {
        _bootSnapshot = latest;
        _currentSnapshot = latest;
        _applyRouteDirectionOnce(latest);
        _rebindActiveQuote(latest);
        _maybeClearInvalidPinnedConversion(latest);
        _offlineNoData = false;
      });
    } catch (error) {
      if (error is NetworkUnavailableException) {
        if (!mounted) return;
        _showSnackBar(
          'Sin conexión. Conecta a internet para actualizar las tasas.',
        );
        return;
      }

      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'CALCULATOR_REFRESH_RATES_FAILED',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {'stage': 'refresh_rates'},
            ),
          );
        } catch (_) {}
      });
      if (!mounted) return;
      _showSnackBar('No se pudo cargar la tasa para cotizar.');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _onSnapshotUpdated() {
    final snapshot = _snapshotNotifier.value;
    if (snapshot == null || !mounted) return;

    if (_bootSnapshot != null && !_canBindSnapshot(snapshot)) {
      // Mantener la snapshot anterior si la nueva no puede satisfacer la tasa actual.
      return;
    }

    setState(() {
      _currentSnapshot = snapshot;
      _bootSnapshot ??= snapshot;
      _applyRouteDirectionOnce(snapshot);
      _rebindActiveQuote(snapshot);
      _maybeClearInvalidPinnedConversion(snapshot);
      _offlineNoData = false;
    });
  }

  bool _canBindSnapshot(ExchangeRateSnapshot snapshot) {
    final fixedId = widget.fixedRateId?.trim();
    if (fixedId != null && fixedId.isNotEmpty) {
      return snapshot.tryById(fixedId) != null;
    }

    final fixedCode = widget.fixedRateCode?.trim();
    if (fixedCode != null && fixedCode.isNotEmpty) {
      return snapshot.tryByCode(fixedCode) != null;
    }

    final fromCode = widget.initialFromCode?.trim();
    final toCode = widget.initialToCode?.trim();
    if (fromCode != null &&
        fromCode.isNotEmpty &&
        toCode != null &&
        toCode.isNotEmpty) {
      return findQuoteForCurrencyPair(snapshot, fromCode, toCode) != null;
    }

    return true;
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
      for (final entry in {
        _fromCode,
        _toCode,
      }.map((c) => canonicalCurrencyCode(c)))
        entry: entry,
    };
  }

  Map<String, String> _badgesForCalculatorPair() {
    final badges = <String, String>{};
    final quote = _activeQuote;

    if (quote != null) {
      final anchor = canonicalCurrencyCode(quote.anchor);
      final counter = canonicalCurrencyCode(quote.counter);
      final anchorSymbol = quote.row.conversionSymbol?.trim();
      final counterSymbol = (quote.row.moneyTypeSymbol ?? quote.row.symbol)
          .trim();

      if (anchorSymbol != null && anchorSymbol.isNotEmpty) {
        badges[anchor] = anchorSymbol;
      }
      if (counterSymbol.isNotEmpty) {
        badges[counter] = counterSymbol;
      }
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

  Future<void> _togglePinnedConversion(bool value) async {
    final rate = _resolvedRowForTrend();
    if (value) {
      if (rate?.isFavorite != true) {
        _showSnackBar('Solo puedes fijar una conversión favorita.');
        return;
      }

      await PinnedConversionStore.savePinnedConversion(
        rateId: rate?.id,
        rateCode: rate?.code,
        fromCode: _fromCode,
        toCode: _toCode,
      );
      if (!mounted) return;
      setState(() {
        _isPinned = true;
      });
      _showSnackBar('Conversión fijada para mostrarla al iniciar.');
      return;
    }

    await PinnedConversionStore.clearPinnedConversion();
    if (!mounted) return;
    setState(() {
      _isPinned = false;
    });
    _showSnackBar('Fijado eliminado. Verás la lista de tasas al iniciar.');
  }

  Future<void> _switchToOtherFavorite(
    ExchangeRateSnapshot snapshot,
    ExchangeRate otherFavorite,
  ) async {
    final parsed = tryParseQuote(otherFavorite);
    if (parsed == null) {
      _showSnackBar('No se pudo cambiar a la otra favorita.');
      return;
    }

    setState(() {
      _fromCode = parsed.anchor;
      _toCode = parsed.counter;
      _rebindActiveQuote(snapshot);
      _isPinned = false;
    });
    await _loadPinnedStatus();
    _showSnackBar('Mostrando la otra conversión favorita.');
  }

  Future<void> _showPinnedConversionSheet() async {
    final rate = _resolvedRowForTrend();
    final canPin = rate?.isFavorite == true;
    bool localPinned = _isPinned;

    final selected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PinnedConversionToggle(
                      isPinned: localPinned,
                      canPin: canPin,
                      onChanged: (value) async {
                        await _togglePinnedConversion(value);
                        if (!mounted) return;
                        localPinned = _isPinned;
                        setModalState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      await _togglePinnedConversion(selected);
    }
  }

  Future<void> _showFavoriteSelector(
    ExchangeRateSnapshot snapshot,
    ExchangeRate currentRate,
    List<ExchangeRate> favoriteRates,
  ) async {
    final selected = await showModalBottomSheet<ExchangeRate>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Selecciona una favorita',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Elige otra conversión favorita para usarla en la calculadora.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: favoriteRates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final rate = favoriteRates[index];
                    final parsed = tryParseQuote(rate);
                    final label = parsed == null
                        ? rate.code
                        : '${canonicalCurrencyCode(parsed.anchor)} / ${canonicalCurrencyCode(parsed.counter)}';
                    final isCurrent = rate.id == currentRate.id;
                    return ListTile(
                      title: Text(label),
                      subtitle: Text(rate.name),
                      leading: Icon(
                        isCurrent
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      enabled: !isCurrent,
                      onTap: isCurrent ? null : () => Navigator.pop(context, rate),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await _switchToOtherFavorite(snapshot, selected);
    }
  }

  void _maybeClearInvalidPinnedConversion(ExchangeRateSnapshot snapshot) {
    final current = _resolvedRowForTrend();
    if (_isPinned && current != null && !current.isFavorite) {
      PinnedConversionStore.clearPinnedConversion();
      _isPinned = false;
    }
  }

  void _clear() {
    setState(() {
      _selectedQuickAmount = -1;
      _amountController.clear();
      _amountController.selection = const TextSelection.collapsed(offset: 0);
      _selectedHistoricalDateByRate.clear();
      _historicalRateValuesByRate.clear();
      _historicalTrendRatesByRate.clear();
      _isFetchingHistoricalRate = false;
    });
  }

  Future<void> _copyResult() async {
    if (_enteredAmount == null || _amount == 0) {
      _showSnackBar('Ingresa un monto mayor a 0 para copiar.');
      return;
    }
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

  Future<void> _showExpandedCalculator() async {
    final quote = _activeQuote;
    if (quote == null) return;

    final rate = quote.row;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ExpandedCalculatorSheet(
          initialAmount: _amount,
          fromCode: _fromCode,
          toCode: _toCode,
          rate: rate,
          initialHistoricalDate: _selectedHistoricalDateByRate[rate.id],
          initialHistoricalValue: _historicalRateValuesByRate[rate.id],
          calculate: (amount, historicalValue) =>
              _computedNumericResultForAmount(
                amount,
                historicalValue: historicalValue,
              ),
          onRequestHistoricalDate: (selectedRate) =>
              _requestHistoricalDate(selectedRate),
        );
      },
    );
  }

  String _historyDateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<HistoricalRateResult?> _requestHistoricalDate(
    ExchangeRate rate,
  ) async {
    final now = DateTime.now();
    final initialDate = _selectedHistoricalDateByRate[rate.id] ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      locale: const Locale('es'),
      initialDate: initialDate,
      firstDate: DateTime(now.year, 1, 1),
      lastDate: now,
      // La fecha histórica debe seleccionarse únicamente desde el calendario.
      // Evita que el usuario cambie al modo de entrada manual y envíe formatos
      // que la API no pueda interpretar.
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Selecciona la fecha de la tasa',
    );

    if (pickedDate == null) {
      return null;
    }

    return _selectHistoricalDate(rate, pickedDate);
  }

  Future<HistoricalRateResult?> _selectHistoricalDate(
    ExchangeRate rate,
    DateTime pickedDate,
  ) async {
    setState(() {
      _selectedHistoricalDateByRate[rate.id] = pickedDate;
      _historicalRateValuesByRate.remove(rate.id);
      _historicalTrendRatesByRate.remove(rate.id);
      _isFetchingHistoricalRate = true;
    });

    _showSnackBar('Consultando tasa histórica...');

    try {
      final historicalResult = await HttpExchangeRateRepository.instance
          .fetchHistoricalRateDetails(
        nombre: rate.name,
        fecha: pickedDate,
      );

      HistoricalRateResult? previousResult;
      for (var offset = 1; offset <= 10; offset++) {
        final previousDate = historicalResult.usedDate.subtract(
          Duration(days: offset),
        );
        if (previousDate.year != historicalResult.usedDate.year) {
          break;
        }
        try {
          final candidate = await HttpExchangeRateRepository.instance
              .fetchHistoricalRateDetails(
                nombre: rate.name,
                fecha: previousDate,
              );
          final changePercent =
              ((historicalResult.value - candidate.value) / candidate.value)
                  .abs() *
              100;
          if (candidate.usedDate.isBefore(historicalResult.usedDate) &&
              changePercent > 0.01) {
            previousResult = candidate;
            break;
          }
        } on FormatException {
          // Continue looking for the previous published rate.
        }
      }

      final historicalChangePercent = previousResult == null
          ? 0.0
          : ((historicalResult.value - previousResult.value) /
                    previousResult.value) *
              100;
      final historicalTrendRate = rate.copyWith(
        changePercent: historicalChangePercent,
        sparklineValues: previousResult == null
            ? [historicalResult.value]
            : [previousResult.value, historicalResult.value],
      );

      if (!mounted) return historicalResult;
      setState(() {
        _selectedHistoricalDateByRate[rate.id] = historicalResult.usedDate;
        _historicalRateValuesByRate[rate.id] = historicalResult.value;
        _historicalTrendRatesByRate[rate.id] = historicalTrendRate;
        _isFetchingHistoricalRate = false;
      });

      _showSnackBar(
        'Tasa histórica del ${_historyDateLabel(pickedDate)}: '
        '${CurrencyFormatter.moneyRate(historicalResult.value, _toCode)}',
      );
      return historicalResult;
    } catch (error, stackTrace) {
      if (!HttpExchangeRateRepository.isNetworkError(error)) {
        Future.microtask(() async {
        await AuditService.instance.logError(
          AuditLog(
            accion: 'CALCULATOR_HISTORICAL_RATE_FAILED',
            mensaje: error.toString(),
            codigo: error.runtimeType.toString(),
            metadatos: {
              'rateId': rate.id,
              'rateName': rate.name,
              'selectedDate': pickedDate.toIso8601String(),
              'stackTrace': stackTrace.toString(),
            },
          ),
        );
        });
      }

      if (!mounted) return null;
      setState(() {
        _historicalRateValuesByRate.remove(rate.id);
        _historicalTrendRatesByRate.remove(rate.id);
        _isFetchingHistoricalRate = false;
      });

      final message = error is FormatException
          ? 'No pudimos consultar la tasa histórica. Seguimos usando la tasa actual.'
          : 'No se pudo obtener la tasa histórica. Se usa la tasa actual.';
      _showSnackBar(message);
      return null;
    }
  }

  void _showSnackBar(String message) {
    showAppNotice(context, message);
  }

  void _showRatesAlreadyUpdatedNotice() {
    if (!mounted) return;
    _showSnackBar('Las tasas ya están actualizadas.');
  }
}

class _QuoteLoadProblem extends StatelessWidget {
  const _QuoteLoadProblem({required this.onRetry, required this.message});

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
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
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
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
    required this.selectedHistoricalDate,
    required this.isPinned,
    required this.canPin,
    this.otherFavoriteLabel,
    this.onSwitchFavorite,
    required this.onAmountChanged,
    required this.onClear,
    required this.onCopy,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSwap,
    required this.onPinChanged,
    required this.onQuickAmount,
    required this.onRequestHistoricalDate,
    required this.isFetchingHistoricalRate,
    required this.onOpenExpandedCalculator,
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
  final DateTime? selectedHistoricalDate;
  final bool isPinned;
  final bool canPin;
  final String? otherFavoriteLabel;
  final VoidCallback? onSwitchFavorite;
  final VoidCallback onAmountChanged;
  final VoidCallback onClear;
  final VoidCallback onCopy;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSwap;
  final ValueChanged<bool> onPinChanged;
  final ValueChanged<int> onQuickAmount;
  final Future<HistoricalRateResult?> Function(ExchangeRate)
      onRequestHistoricalDate;
  final bool isFetchingHistoricalRate;
  final VoidCallback onOpenExpandedCalculator;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPadding = 36.0;
        final minHeight = constraints.hasBoundedHeight &&
                constraints.maxHeight > verticalPadding
            ? constraints.maxHeight - verticalPadding
            : 0.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, minHeight: minHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onSwitchFavorite != null) ...[
                  const SizedBox(height: 5),
                  OutlinedButton.icon(
                    onPressed: onSwitchFavorite,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(
                      otherFavoriteLabel == null
                          ? 'Cambiar tasa favorita'
                          : 'Cambiar tasa favorita ($otherFavoriteLabel)',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                _AmountField(
                  controller: amountController,
                  onChanged: onAmountChanged,
                  onClear: onClear,
                  currency: currencyNames[fromCode]!,
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
                  selectedHistoricalDate: selectedHistoricalDate,
                  rate: selectedRate,
                  onCopy: onCopy,
                  onRequestHistoricalDate: onRequestHistoricalDate,
                  isFetchingHistoricalRate: isFetchingHistoricalRate,
                  onOpenExpandedCalculator: onOpenExpandedCalculator,
                ),
                const SizedBox(height: 12),
                _ActionButtons(onCopy: onCopy, onClear: onClear),
                const SizedBox(height: 16),
                Text(
                  'Montos rápidos',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                _QuickAmounts(
                  amounts: quickAmounts,
                  selectedAmount: selectedQuickAmount,
                  onAmountSelected: onQuickAmount,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PinnedConversionToggle extends StatelessWidget {
  const _PinnedConversionToggle({
    required this.isPinned,
    required this.canPin,
    required this.onChanged,
  });

  final bool isPinned;
  final bool canPin;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fijar tasas de conversión al iniciar.',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canPin
                        ? 'Al activar se fija la conversión con tus favoritas.'
                        : 'Solo las conversiones favoritas pueden fijarse.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(value: isPinned, onChanged: onChanged),
          ],
        ),
      ],
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
            const NoConsecutiveDecimalSeparatorFormatter(),
            const _MaxAmountDigitsFormatter(12),
          ],
          onChanged: (_) => onChanged(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
          decoration: InputDecoration(
            hintText: '0',
            contentPadding: const EdgeInsets.only(
              right: 12,
            ), // Quitamos el padding izquierdo para que el prefijo pegue
            // USAMOS prefix PARA CONTROL TOTAL
            prefixIcon: Container(
              margin: const EdgeInsets.only(
                right: 12,
              ), // Espacio entre el fondo del símbolo y el número
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
                      fontSize: 14,
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
        ),
      ],
    );
  }
}

class _MaxAmountDigitsFormatter extends TextInputFormatter {
  const _MaxAmountDigitsFormatter(this.maxDigits);

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length <= maxDigits ? newValue : oldValue;
  }
}

class _ExpandedCalculatorSheet extends StatefulWidget {
  const _ExpandedCalculatorSheet({
    required this.initialAmount,
    required this.fromCode,
    required this.toCode,
    required this.rate,
    required this.initialHistoricalDate,
    required this.initialHistoricalValue,
    required this.calculate,
    required this.onRequestHistoricalDate,
  });

  final double initialAmount;
  final String fromCode;
  final String toCode;
  final ExchangeRate rate;
  final DateTime? initialHistoricalDate;
  final double? initialHistoricalValue;
  final double Function(double amount, double? historicalValue) calculate;
  final Future<HistoricalRateResult?> Function(ExchangeRate)
      onRequestHistoricalDate;

  @override
  State<_ExpandedCalculatorSheet> createState() =>
      _ExpandedCalculatorSheetState();
}

class _ExpandedCalculatorSheetState extends State<_ExpandedCalculatorSheet> {
  late final TextEditingController _controller;
  late DateTime? _selectedDate = widget.initialHistoricalDate;
  late double? _historicalValue = widget.initialHistoricalValue;
  bool _isFetchingDate = false;

  @override
  void initState() {
    super.initState();
    final initialText = widget.initialAmount > 0
        ? widget.initialAmount.toStringAsFixed(
            widget.initialAmount.truncateToDouble() == widget.initialAmount
                ? 0
                : 2,
          )
        : '';
    _controller = TextEditingController(text: initialText);
    _controller.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onAmountChanged)
      ..dispose();
    super.dispose();
  }

  double? get _amount {
    final normalized = _controller.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    final value = double.tryParse(normalized);
    return value != null && value.isFinite && value >= 0 ? value : null;
  }

  double get _result {
    final amount = _amount;
    if (amount == null) return double.nan;
    return widget.calculate(amount, _historicalValue);
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _changeDate() async {
    setState(() => _isFetchingDate = true);
    final result = await widget.onRequestHistoricalDate(widget.rate);
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _selectedDate = result.usedDate;
        _historicalValue = result.value;
      });
    }
    setState(() => _isFetchingDate = false);
  }

  Future<void> _copy() async {
    final result = _result;
    if (result.isNaN || result.isInfinite) return;
    await Clipboard.setData(ClipboardData(text: result.toString()));
    if (mounted) {
      showAppNotice(context, 'Resultado copiado');
    }
  }

  String _dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final result = _result;
    final resultLabel = result.isNaN || result.isInfinite
        ? '—'
        : CurrencyFormatter.moneyRate(result, widget.toCode);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Calculadora ampliada',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Puedes usar montos grandes sin afectar la calculadora principal.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                const NoConsecutiveDecimalSeparatorFormatter(),
                const _MaxAmountDigitsFormatter(30),
              ],
              decoration: InputDecoration(
                labelText: 'Monto en ${widget.fromCode}',
                prefixText: '${widget.fromCode}  ',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Resultado',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  resultLabel,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: AppColors.positiveGreen,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedDate == null
                  ? 'Tasa actual: ${widget.rate.name}'
                  : 'Tasa del ${_dateLabel(_selectedDate!)}: ${widget.rate.name}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: result.isNaN || result.isInfinite ? null : _copy,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isFetchingDate ? null : _changeDate,
                    icon: _isFetchingDate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.calendar_month_rounded),
                    label: const Text('Cambiar fecha'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
          child: Container(
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
    required this.selectedHistoricalDate,
    required this.rate,
     required this.onRequestHistoricalDate,
     required this.isFetchingHistoricalRate,
     required this.onCopy,
     required this.onOpenExpandedCalculator,
   });

  String _dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  final double amount;
  final String fromCode;
  final String toCode;
  final String formattedResult;
  final String rateLabel;
  final DateTime? selectedHistoricalDate;
  final ExchangeRate rate;
  final Future<HistoricalRateResult?> Function(ExchangeRate)
      onRequestHistoricalDate;
  final bool isFetchingHistoricalRate;
  final VoidCallback onCopy;
  final VoidCallback onOpenExpandedCalculator;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Resultado',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
           
               Flexible(
                 child: Text(
                   selectedHistoricalDate != null
                       ? 'Tasa del ${_dateLabel(selectedHistoricalDate!)}'
                       : 'Actualización de ${_dateLabel(rate.updatedAt)}',
                   textAlign: TextAlign.right,
                   maxLines: 2,
                   overflow: TextOverflow.ellipsis,
                   style: Theme.of(context).textTheme.labelMedium?.copyWith(
                     color: colorScheme.onSurfaceVariant,
                     fontWeight: FontWeight.w700,
                   ),
                 ),
               ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '$fromCode a ${CurrencyFormatter.moneyWithCode(amount, toCode)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
           ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onOpenExpandedCalculator,
                  child: SizedBox(
                    height: 42,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formattedResult,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: AppColors.positiveGreen,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: Icon(
                  Icons.copy_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 24,
                ),
                tooltip: 'Copiar resultado',
              ),
              IconButton(
                onPressed: () => onRequestHistoricalDate(rate),
                icon: isFetchingHistoricalRate
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        Icons.calendar_month_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                tooltip: selectedHistoricalDate != null
                    ? 'Cambiar fecha histórica'
                    : 'Seleccionar fecha histórica',
              ),
            ],
          ),
          if (formattedResult.length > 18) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenExpandedCalculator,
                icon: const Icon(Icons.open_in_full_rounded, size: 16),
                label: const Text('Ver resultado completo'),
              ),
            ),
          ],
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

void _showTradingChart(BuildContext context, ExchangeRate rate) {
  showDialog<void>(
    context: context,
    builder: (_) => _TradingChartDialog(rate: rate),
  );
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({
    required this.rate,
  });

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasTrend = rate.hasTrend;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showTradingChart(context, rate),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.onSurfaceVariant.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: .58),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tendencia de la tasa',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (hasTrend)
                    TrendIndicator(
                      changePercent: rate.changePercent,
                      isUp: rate.isUp,
                      compact: true,
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: hasTrend
                        ? (rate.isUp
                              ? AppColors.positiveGreen
                              : AppColors.negativeRed)
                        : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ],
              ),
          if (!hasTrend) ...[
            const SizedBox(height: 12),
            Row(
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
          ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TradingChartDialog extends StatelessWidget {
  const _TradingChartDialog({required this.rate});

  final ExchangeRate rate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final points = rate.historyPoints.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final visiblePoints = points.length > 7
        ? points.sublist(points.length - 7)
        : points;
    final hasChart = visiblePoints.length >= 2;
    final first = hasChart ? visiblePoints.first.value : 0.0;
    final last = hasChart ? visiblePoints.last.value : 0.0;
    final isUp = last >= first;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Histórico de ${rate.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
              Text(
                'Últimos ${visiblePoints.length} días disponibles',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              if (!hasChart)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 70),
                  child: Center(
                    child: Text(
                      'Aún no hay suficientes datos históricos.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 270,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _TradingChartPainter(
                      points: visiblePoints,
                      lineColor: isUp
                          ? AppColors.positiveGreen
                          : AppColors.negativeRed,
                      labelColor: colorScheme.onSurfaceVariant,
                      gridColor: colorScheme.outlineVariant.withValues(
                        alpha: .45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _chartDateLabel(visiblePoints.first.date),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      _chartDateLabel(visiblePoints.last.date),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _chartDateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

class _TradingChartPainter extends CustomPainter {
  const _TradingChartPainter({
    required this.points,
    required this.lineColor,
    required this.labelColor,
    required this.gridColor,
  });

  final List<ExchangeRateHistoryPoint> points;
  final Color lineColor;
  final Color labelColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 54.0;
    const right = 12.0;
    const top = 14.0;
    const bottom = 12.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    final values = points.map((point) => point.value).toList();
    var minValue = values.reduce((a, b) => a < b ? a : b);
    var maxValue = values.reduce((a, b) => a > b ? a : b);
    if (minValue == maxValue) {
      final padding = minValue.abs() * .01;
      minValue -= padding == 0 ? 1 : padding;
      maxValue += padding == 0 ? 1 : padding;
    }

    double yFor(double value) =>
        chart.bottom - ((value - minValue) / (maxValue - minValue)) * chart.height;
    double xFor(int index) => points.length == 1
        ? chart.center.dx
        : chart.left + (chart.width * index / (points.length - 1));

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: labelColor, fontSize: 10);
    for (var row = 0; row < 4; row++) {
      final fraction = row / 3;
      final y = chart.top + chart.height * fraction;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = maxValue - (maxValue - minValue) * fraction;
      final text = TextPainter(
        text: TextSpan(
          text: CurrencyFormatter.formatNumber(value, 2),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: left - 8);
      text.paint(canvas, Offset(0, y - text.height / 2));
    }

    final linePath = Path();
    for (var index = 0; index < points.length; index++) {
      final point = Offset(xFor(index), yFor(points[index].value));
      if (index == 0) {
        linePath.moveTo(point.dx, point.dy);
      } else {
        linePath.lineTo(point.dx, point.dy);
      }
    }

    final areaPath = Path.from(linePath)
      ..lineTo(xFor(points.length - 1), chart.bottom)
      ..lineTo(xFor(0), chart.bottom)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withValues(alpha: .28), lineColor.withValues(alpha: 0)],
        ).createShader(chart),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final pointPaint = Paint()..color = lineColor;
    final haloPaint = Paint()..color = lineColor.withValues(alpha: .18);
    for (var index = 0; index < points.length; index++) {
      final point = Offset(xFor(index), yFor(points[index].value));
      canvas.drawCircle(point, 7, haloPaint);
      canvas.drawCircle(point, 3.5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TradingChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
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
            label: const Text('Copiar'),
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
        const gap = 6.0;
        final itemWidth = (constraints.maxWidth - gap * 4) / 5;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: amounts.map((amount) {
            final isSelected = selectedAmount == amount;
            return SizedBox(
              width: itemWidth.clamp(40, 72),
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
          height: 38,
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
      child: Padding(
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
