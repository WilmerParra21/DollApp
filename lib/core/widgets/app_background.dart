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
      duration: const Duration(seconds: 45),
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

    _paintFineGrid(canvas, size);
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


  @override
  bool shouldRepaint(covariant _AppBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.colorScheme != colorScheme;
  }
}
