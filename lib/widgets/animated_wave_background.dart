import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AnimatedWaveBackground extends StatefulWidget {
  const AnimatedWaveBackground({super.key});

  @override
  State<AnimatedWaveBackground> createState() => _AnimatedWaveBackgroundState();
}

class _AnimatedWaveBackgroundState extends State<AnimatedWaveBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
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
          painter: WavePainter(_controller.value),
          child: Container(),
        );
      },
    );
  }
}

class WavePainter extends CustomPainter {
  final double animationValue;

  WavePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = AppTheme.oledDark,
    );

    _drawWave(canvas, size, 0.4, AppTheme.neonPurple.withOpacity(0.15), 1.0);
    _drawWave(canvas, size, 0.5, AppTheme.neonCyan.withOpacity(0.1), 1.5);
    _drawWave(canvas, size, 0.6, const Color(0xFF0052D4).withOpacity(0.12), 2.0);
  }

  void _drawWave(Canvas canvas, Size size, double heightFactor, Color color, double speedMultiplier) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final yBase = size.height * heightFactor;

    path.moveTo(0, size.height);
    path.lineTo(0, yBase);

    for (double i = 0; i <= size.width; i++) {
      final y = yBase + math.sin((i / size.width * 2 * math.pi) + (animationValue * 2 * math.pi * speedMultiplier)) * 30;
      path.lineTo(i, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
