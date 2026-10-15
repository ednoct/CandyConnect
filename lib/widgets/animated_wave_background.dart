import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class AnimatedWaveBackground extends ConsumerStatefulWidget {
  const AnimatedWaveBackground({super.key});

  @override
  ConsumerState<AnimatedWaveBackground> createState() =>
      _AnimatedWaveBackgroundState();
}

class _AnimatedWaveBackgroundState extends ConsumerState<AnimatedWaveBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // توقف رندر انیمیشن هنگام مخفی بودن پنجره در System Tray یا پس‌زمینه موبایل
    // جهت رساندن مصرف CPU/GPU در حالت بیکار به صفر درصد
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(isConnectedProvider);

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: isConnected ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
        builder: (context, connectionEnergy, _) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: WavePainter(
                  animationValue: _controller.value,
                  connectionEnergy: connectionEnergy,
                ),
                size: Size.infinite,
                isComplex: true,
                willChange: true,
              );
            },
          );
        },
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final double animationValue;
  final double connectionEnergy;

  const WavePainter({
    required this.animationValue,
    this.connectionEnergy = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // ── ۱. بوم پایه عمیق فضایی (Deep Space OLED Gradient) ─────────────────
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF070A12),
          AppTheme.oledDark,
          Color(0xFF0D1324),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // ── ۲. سحابی نوری واکنش‌گرا در نیمه بالایی (پشت دکمه اتصال) ─────────────
    final nebulaRadius = size.shortestSide * (0.55 + 0.15 * connectionEnergy);
    final nebulaCenter = Offset(size.width * 0.5, size.height * 0.34);
    final nebulaColor = Color.lerp(
      AppTheme.neonPurple.withValues(alpha: 0.07),
      AppTheme.neonCyan.withValues(alpha: 0.14),
      connectionEnergy,
    )!;

    final nebulaPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          nebulaColor,
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: nebulaCenter, radius: nebulaRadius),
      );
    canvas.drawCircle(nebulaCenter, nebulaRadius, nebulaPaint);

    // ── ۳. لایه‌های موج چندهارمونیک با گرادینت عمودی و خط تاج نوری ─────────
    final ampScale = lerpDouble(1.0, 1.32, connectionEnergy) ?? 1.0;

    // موج اول: بنفش نئونی (لایه عمیق پس‌زمینه)
    _drawBioWave(
      canvas: canvas,
      size: size,
      heightFactor: 0.42,
      amplitude: 26.0 * ampScale,
      secondaryAmplitude: 10.0 * ampScale,
      speedMultiplier: 1.0,
      phaseShift: 0.0,
      topColor: AppTheme.neonPurple.withValues(
        alpha: lerpDouble(0.16, 0.24, connectionEnergy)!,
      ),
      crestColor: AppTheme.neonPurple.withValues(
        alpha: lerpDouble(0.28, 0.48, connectionEnergy)!,
      ),
    );

    // موج دوم: سیان نئونی (لایه میانی انرژی)
    _drawBioWave(
      canvas: canvas,
      size: size,
      heightFactor: 0.52,
      amplitude: 30.0 * ampScale,
      secondaryAmplitude: 12.0 * ampScale,
      speedMultiplier: 1.5,
      phaseShift: math.pi / 3,
      topColor: AppTheme.neonCyan.withValues(
        alpha: lerpDouble(0.11, 0.22, connectionEnergy)!,
      ),
      crestColor: AppTheme.neonCyan.withValues(
        alpha: lerpDouble(0.32, 0.65, connectionEnergy)!,
      ),
    );

    // موج سوم: آبی الکتریک (لایه پیش‌زمینه)
    _drawBioWave(
      canvas: canvas,
      size: size,
      heightFactor: 0.62,
      amplitude: 24.0 * ampScale,
      secondaryAmplitude: 9.0 * ampScale,
      speedMultiplier: 2.0,
      phaseShift: math.pi / 1.5,
      topColor: const Color(0xFF0052D4).withValues(
        alpha: lerpDouble(0.14, 0.22, connectionEnergy)!,
      ),
      crestColor: AppTheme.neonCyan.withValues(
        alpha: lerpDouble(0.18, 0.40, connectionEnergy)!,
      ),
    );
  }

  void _drawBioWave({
    required Canvas canvas,
    required Size size,
    required double heightFactor,
    required double amplitude,
    required double secondaryAmplitude,
    required double speedMultiplier,
    required double phaseShift,
    required Color topColor,
    required Color crestColor,
  }) {
    final yBase = size.height * heightFactor;
    final fillPath = Path();
    final crestPath = Path();

    final double phase =
        (animationValue * 2 * math.pi * speedMultiplier) + phaseShift;
    const double step = 4.0; // بهینه‌سازی ۷۵ درصدی محاسبات بدون افت کیفیت بصری

    fillPath.moveTo(0, size.height);

    bool isFirst = true;
    for (double x = 0; x <= size.width + step; x += step) {
      final double clampedX = x > size.width ? size.width : x;
      final double normX = clampedX / size.width;

      // ترکیب دو هارمونیک موج برای حرکت طبیعی و سیال
      final double primaryWave =
          math.sin((normX * 2 * math.pi) + phase) * amplitude;
      final double harmonicWave =
          math.cos((normX * 4 * math.pi) - (phase * 0.5)) * secondaryAmplitude;
      final double y = yBase + primaryWave + harmonicWave;

      fillPath.lineTo(clampedX, y);
      if (isFirst) {
        crestPath.moveTo(clampedX, y);
        isFirst = false;
      } else {
        crestPath.lineTo(clampedX, y);
      }

      if (clampedX == size.width) break;
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // رنگ‌آمیزی گرادینت عمودی موج
    final waveRect = Rect.fromLTWH(
      0,
      yBase - amplitude - secondaryAmplitude,
      size.width,
      size.height - (yBase - amplitude - secondaryAmplitude),
    );
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          topColor,
          topColor.withValues(alpha: topColor.a * 0.35),
          AppTheme.oledDark.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(waveRect);

    canvas.drawPath(fillPath, fillPaint);

    // رسم خط نوری درخشان روی لبه تاج موج
    final crestPaint = Paint()
      ..color = crestColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);

    canvas.drawPath(crestPath, crestPaint);
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.connectionEnergy != connectionEnergy;
  }
}