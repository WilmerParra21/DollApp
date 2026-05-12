import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppBackground extends StatefulWidget {
  const AppBackground({required this.child, super.key});

  final Widget child;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
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
        return CustomPaint(
          painter: _AppBackgroundPainter(
            progress: _controller.value,
            isDark: Theme.of(context).brightness == Brightness.dark,
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _AppBackgroundPainter extends CustomPainter {
  const _AppBackgroundPainter({
    required this.progress,
    required this.isDark,
    required this.colorScheme,
  });

  final double progress;
  final bool isDark;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF061611), Color(0xFF0B221A), Color(0xFF101B25)]
          : const [Color(0xFFF5FAF7), Color(0xFFEAF5EF), Color(0xFFF8FBF9)],
    );
    canvas.drawRect(rect, Paint()..shader = baseGradient.createShader(rect));

    _paintSoftBands(canvas, size);
    _paintFineGrid(canvas, size);
    _paintLightSweep(canvas, size);
  }

  void _paintSoftBands(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = colorScheme.primary.withValues(alpha: isDark ? .10 : .08);
    final secondaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = const Color(0xFF1D4ED8).withValues(alpha: isDark ? .08 : .05);

    for (var i = -2; i < 5; i++) {
      final y = size.height * (.18 + i * .19);
      final path = Path()
        ..moveTo(-40, y)
        ..cubicTo(
          size.width * .25,
          y - 34,
          size.width * .66,
          y + 42,
          size.width + 40,
          y - 12,
        );
      canvas.drawPath(path, i.isEven ? paint : secondaryPaint);
    }
  }

  void _paintFineGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = .6
      ..color = (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? .035 : .03,
      );
    const spacing = 34.0;
    final offset = progress * spacing;

    for (var x = -spacing + offset; x < size.width + spacing; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * .22, size.height),
        paint,
      );
    }
  }

  void _paintLightSweep(Canvas canvas, Size size) {
    final sweepWidth = math.max(size.width, size.height) * .65;
    final x = -sweepWidth + (size.width + sweepWidth * 2) * progress;
    final rect = Rect.fromLTWH(x, 0, sweepWidth, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: isDark ? .035 : .18),
          Colors.transparent,
        ],
      ).createShader(rect);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 12);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.colorScheme != colorScheme;
  }
}
