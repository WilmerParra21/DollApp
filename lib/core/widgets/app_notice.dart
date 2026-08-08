import 'dart:async';

import 'package:flutter/material.dart';

void showAppNotice(
  BuildContext context,
  String message, {
  IconData? icon,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AppNoticeEntry(
      message: message,
      icon: icon,
      duration: duration,
      onDismiss: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _AppNoticeEntry extends StatefulWidget {
  const _AppNoticeEntry({
    required this.message,
    required this.duration,
    required this.onDismiss,
    this.icon,
  });

  final String message;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_AppNoticeEntry> createState() => _AppNoticeEntryState();
}

class _AppNoticeEntryState extends State<_AppNoticeEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    )..forward();
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isConnectionNotice = widget.message.toLowerCase().contains('conex');

    return Positioned(
      left: 16,
      right: 16,
      bottom: 22,
      child: SafeArea(
        top: false,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .35),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
            ),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.inverseSurface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .2),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon ??
                            (isConnectionNotice
                                ? Icons.wifi_off_rounded
                                : Icons.info_outline_rounded),
                        color: colors.onInverseSurface,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: colors.onInverseSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _dismiss,
                        tooltip: 'Cerrar aviso',
                        icon: Icon(
                          Icons.close_rounded,
                          color: colors.onInverseSurface.withValues(alpha: .75),
                          size: 19,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
