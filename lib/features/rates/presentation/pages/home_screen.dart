import 'package:flutter/material.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/quick_action_chip.dart';
import '../../data/http_exchange_rate_repository.dart';
import '../../models/exchange_rate_snapshot.dart';
import '../../utils/exchange_pair_quote.dart';
import '../widgets/rate_card.dart';
import '../widgets/update_gate_sheet.dart';
import '../widgets/update_status_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.themeMode,
    required this.onToggleTheme,
    super.key,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ValueNotifier<ExchangeRateSnapshot?> _snapshotNotifier;
  var _isRefreshing = false;
  var _bottomRefreshDrag = 0.0;

  var _updateSheetShown = false;
  var _loadFailed = false; // Track if initial load failed

  @override
  void initState() {
    super.initState();
    _snapshotNotifier = HttpExchangeRateRepository.instance.snapshotNotifier;
    _loadCachedSnapshot();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdateGate();
    });
    // Load initial data with error handling
    _loadInitialData().catchError((e) {});
  }

  Future<void> _loadInitialData() async {
    try {
      await HttpExchangeRateRepository.instance.getRates(forceRefresh: true);
      if (mounted) setState(() => _loadFailed = false);
    } catch (e) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _checkForUpdateGate() async {
    if (_updateSheetShown || !mounted) return;

    try {
      final updateInfo = await UpdateService.instance.checkForUpdate();
      if (updateInfo == null || !mounted) {
        return;
      }
      _updateSheetShown = true;
      await showUpdateGateSheet(context, updateInfo);
    } catch (_) {
      // Error al verificar actualización
    }
  }

  Future<void> _loadCachedSnapshot() async {
    try {
      await HttpExchangeRateRepository.instance.loadSavedSnapshot();
    } catch (_) {
      // Error is handled in repository
    }
  }

  Future<void> _refreshRates() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      await HttpExchangeRateRepository.instance.getRates(forceRefresh: true);
    } catch (error) {
      // Error handled in repository
    }

    if (!mounted) return;

    setState(() => _isRefreshing = false);

    _showSnackBar(context, 'Tasas actualizadas correctamente.');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: AppBackground(
          child: RefreshIndicator(
            onRefresh: _refreshRates,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'DollApp',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tus tasas al día',
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            _ThemeToggleButton(
                              isDark: isDark,
                              onTap: widget.onToggleTheme,
                            ),
                            const SizedBox(width: 10),
                            _HeaderIconButton(
                              tooltip: 'Acerca de',
                              icon: Icons.info_outline_rounded,
                              onTap: () =>
                                  Navigator.pushNamed(context, AppRoutes.about),
                            ),
                          ],
                        ),
                         ValueListenableBuilder<ExchangeRateSnapshot?>(
                           valueListenable: _snapshotNotifier,
                           builder: (context, snapshot, child) {
                             if (snapshot == null) {
                               if (_loadFailed) {
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
                                         ElevatedButton.icon(
                                           onPressed: _loadInitialData,
                                           icon: const Icon(Icons.refresh_rounded),
                                           label: const Text('Reintentar'),
                                         ),
                                       ],
                                     ),
                                   ),
                                 );
                               }
                               return const _HomeSkeleton();
                             }

                             return _HomeContent(
                               ratesSnapshot: snapshot,
                               isRefreshing: _isRefreshing,
                             );
                           },
                         ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.metrics.extentAfter == 0 &&
        notification.overscroll > 0) {
      _bottomRefreshDrag += notification.overscroll;
    }

    if (notification is ScrollEndNotification) {
      if (_bottomRefreshDrag >= 72) {
        _refreshRates();
      }
      _bottomRefreshDrag = 0;
    }

    return false;
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.ratesSnapshot, required this.isRefreshing});

  final ExchangeRateSnapshot ratesSnapshot;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        UpdateStatusCard(
          isOffline: ratesSnapshot.usedFallback,
          updatedAt: ratesSnapshot.updatedAt,
        ),
        const SizedBox(height: 24),
        Text(
          'Tasas de hoy',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        ...ratesSnapshot.rates.map(
          (rate) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RateCard(
              rate: rate,
              isFavorite: rate.isFavorite,
              onFavoriteTap: () async {
                final nextIsFavorite = !rate.isFavorite;
                final messenger = ScaffoldMessenger.of(context);
                await HttpExchangeRateRepository.instance.setFavorite(
                  rate.id,
                  nextIsFavorite,
                );

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      nextIsFavorite
                          ? 'Conversión guardada como favorita.'
                          : 'Conversión removida de favoritos.',
                    ),
                  ),
                );
              },
              onTap: () {
                final parsed = tryParseQuote(rate);

                Navigator.pushNamed(
                  context,
                  AppRoutes.calculator,
                  arguments: CalculatorRouteArgs(
                    fixedRateId: rate.id,
                    fromCode: parsed?.anchor,
                    toCode: parsed?.counter,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        AppPrimaryButton(
          label: 'Calcular',
          icon: Icons.calculate_rounded,
          onPressed: () => Navigator.pushNamed(context, AppRoutes.calculator),
        ),
        const SizedBox(height: 28),
        Text(
          'Conversion rapida',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: _quickActionChips(context)),
        ),
        const SizedBox(height: 14),
        _BottomRefreshHint(isRefreshing: isRefreshing),
      ],
    );
  }

  List<Widget> _quickActionChips(BuildContext context) {
    final chips = <Widget>[];
    for (final rate in ratesSnapshot.rates) {
      final parsed = tryParseQuote(rate);
      if (parsed == null) {
        continue;
      }

      if (chips.isNotEmpty) {
        chips.add(const SizedBox(width: 10));
      }

      chips.add(
        QuickActionChip(
          label: '${parsed.anchor} a ${parsed.counter}',
          icon: _quickActionIcon(parsed.counter),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.calculator,
            arguments: CalculatorRouteArgs(
              fixedRateId: rate.id,
              fromCode: parsed.anchor,
              toCode: parsed.counter,
            ),
          ),
        ),
      );
    }
    return chips;
  }

  IconData _quickActionIcon(String code) {
    return Icons.currency_exchange_rounded;
  }
}

class _HomeSkeleton extends StatefulWidget {
  const _HomeSkeleton();

  @override
  State<_HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<_HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat();
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
        return _SkeletonTheme(progress: _controller.value, child: child!);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 22),
          const _StatusSkeletonCard(),
          const SizedBox(height: 24),
          const _SkeletonBlock(width: 138, height: 24, borderRadius: 12),
          const SizedBox(height: 12),
          ...List.generate(
            3,
            (index) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _RateSkeletonCard(),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumns = constraints.maxWidth < 420;
              const primary = _SkeletonBlock(height: 54, borderRadius: 16);
              const secondary = _SkeletonBlock(height: 54, borderRadius: 16);

              return useColumns
                  ? const Column(
                      children: [primary, SizedBox(height: 12), secondary],
                    )
                  : const Row(
                      children: [
                        Expanded(child: primary),
                        SizedBox(width: 12),
                        Expanded(child: secondary),
                      ],
                    );
            },
          ),
          const SizedBox(height: 28),
          const _SkeletonBlock(width: 168, height: 20, borderRadius: 10),
          const SizedBox(height: 10),
          const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SkeletonBlock(width: 108, height: 44, borderRadius: 999),
                SizedBox(width: 10),
                _SkeletonBlock(width: 104, height: 44, borderRadius: 999),
                SizedBox(width: 10),
                _SkeletonBlock(width: 108, height: 44, borderRadius: 999),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonTheme extends InheritedWidget {
  const _SkeletonTheme({required this.progress, required super.child});

  final double progress;

  static double progressOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SkeletonTheme>()
            ?.progress ??
        0;
  }

  @override
  bool updateShouldNotify(covariant _SkeletonTheme oldWidget) {
    return oldWidget.progress != progress;
  }
}

class _StatusSkeletonCard extends StatelessWidget {
  const _StatusSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: const Row(
          children: [
            _SkeletonBlock(width: 44, height: 44, borderRadius: 999),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBlock(width: 172, height: 16, borderRadius: 8),
                  SizedBox(height: 8),
                  _SkeletonBlock(width: 218, height: 13, borderRadius: 7),
                  SizedBox(height: 12),
                  _SkeletonBlock(width: 156, height: 12, borderRadius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateSkeletonCard extends StatelessWidget {
  const _RateSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
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
            const header = Row(
              children: [
                _SkeletonBlock(width: 48, height: 48, borderRadius: 999),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBlock(width: 144, height: 17, borderRadius: 9),
                      SizedBox(height: 8),
                      _SkeletonBlock(width: 190, height: 12, borderRadius: 6),
                      SizedBox(height: 8),
                      _SkeletonBlock(width: 132, height: 12, borderRadius: 6),
                    ],
                  ),
                ),
              ],
            );
            const value = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SkeletonBlock(width: 92, height: 18, borderRadius: 9),
                SizedBox(height: 9),
                _SkeletonBlock(width: 76, height: 24, borderRadius: 999),
              ],
            );

            if (compact) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  SizedBox(height: 14),
                  Align(alignment: Alignment.centerRight, child: value),
                ],
              );
            }

            return const Row(
              children: [
                Expanded(child: header),
                SizedBox(width: 10),
                value,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    required this.borderRadius,
    this.width,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = _SkeletonTheme.progressOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = colorScheme.onSurface.withValues(
      alpha: isDark ? .10 : .08,
    );
    final highlightColor = colorScheme.onSurface.withValues(
      alpha: isDark ? .22 : .16,
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(-1.4 + progress * 2.8, 0),
          end: Alignment(-.4 + progress * 2.8, 0),
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0, .5, 1],
        ),
      ),
    );
  }
}

class _BottomRefreshHint extends StatelessWidget {
  const _BottomRefreshHint({required this.isRefreshing});

  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: isRefreshing
            ? SizedBox(
                key: const ValueKey('refreshing'),
                height: 28,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Consultando tasas',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            : Text(
                key: const ValueKey('idle'),
                'Desliza hacia arriba al final para actualizar',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Cambiar tema',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 74,
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: .26),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: colorScheme.onPrimary,
                size: 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 21),
        ),
      ),
    );
  }
}
