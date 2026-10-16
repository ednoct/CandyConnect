import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../core/desktop_manager.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class CustomDesktopTitleBar extends ConsumerWidget {
  const CustomDesktopTitleBar({super.key});

  Future<void> _handleMinimize() async {
    await windowManager.minimize();
  }

  Future<void> _handleExit(WidgetRef ref) async {
    final currentLicense = ref.read(currentLicenseProvider);

    if (currentLicense != null && currentLicense.isNotEmpty) {
      // کاربر لاگین است: انتقال آنی و نرم به System Tray
      await windowManager.hide();
    } else {
      // کاربر لاگین نیست: خروج ایمن با پاکسازی کامل پروکسی سیستم و هسته Xray
      await DesktopManager().hardExit();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(isConnectedProvider);
    final isVpnMode = ref.watch(isVpnModeProvider);
    final currentLicense = ref.watch(currentLicenseProvider);
    final isLoggedIn = currentLicense != null && currentLicense.isNotEmpty;

    final Color accentColor =
        isConnected ? AppTheme.neonCyan : AppTheme.neonPurple;
    final String modeLabel = isVpnMode ? 'TUN' : 'PROXY';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF060911),
                AppTheme.oledDark.withValues(alpha: 0.96),
              ],
            ),
          ),
          child: Stack(
            children: [
              // ── خط افق لیزری در لبه پایینی (Laser Horizon Beam) ─────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  height: 1.2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withValues(alpha: isConnected ? 0.55 : 0.20),
                        accentColor.withValues(alpha: isConnected ? 0.20 : 0.06),
                        Colors.white.withValues(alpha: 0.04),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),

              // ── محتوای اصلی نوار عنوان ───────────────────────────────────
              Row(
                children: [
                  // ۱. ناحیه قابل کشیدن (کاملاً جدا از دکمه‌ها برای حذف باگ گیر کردن)
                  Expanded(
                    child: DragToMoveArea(
                      child: Container(
                        height: 42,
                        color: Colors.transparent,
                        padding: const EdgeInsets.only(left: 14),
                        child: Row(
                          children: [
                            // گوی نوری دوحلقه‌ای وضعیت (Dual-Ring Status Orb)
                            _StatusOrb(
                              color: accentColor,
                              isConnected: isConnected,
                            ),
                            const SizedBox(width: 10),

                            // نام برند با تایپوگرافی آینده‌نگر
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  Colors.white,
                                  Colors.white.withValues(alpha: 0.78),
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'CandyConnect',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // کپسول تله‌متری بدون پرش (Smooth Telemetry Pill)
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(
                                  opacity: anim,
                                  child: ScaleTransition(
                                    scale: Tween<double>(begin: 0.92, end: 1.0)
                                        .animate(anim),
                                    child: child,
                                  ),
                                ),
                                child: isConnected
                                    ? _TelemetryBadge(
                                        key: ValueKey('connected-$modeLabel'),
                                        text: 'PROTECTED • $modeLabel',
                                        color: AppTheme.neonCyan,
                                      )
                                    : isLoggedIn
                                        ? _TelemetryBadge(
                                            key: ValueKey('standby-$modeLabel'),
                                            text: 'STANDBY • $modeLabel',
                                            color: Colors.white38,
                                            isSubtle: true,
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('logged-out'),
                                          ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ۲. دکمه‌های کنترلی کپسولی (خارج از DragToMoveArea برای کلیک آنی)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FuturisticWindowButton(
                          icon: Icons.remove_rounded,
                          hoverColor: Colors.white.withValues(alpha: 0.10),
                          hoverBorderColor: Colors.white.withValues(alpha: 0.22),
                          iconColor: Colors.white70,
                          hoverIconColor: AppTheme.neonCyan,
                          onTap: _handleMinimize,
                        ),
                        const SizedBox(width: 4),
                        _FuturisticWindowButton(
                          icon: Icons.close_rounded,
                          hoverColor: AppTheme.errorRed.withValues(alpha: 0.85),
                          hoverBorderColor: AppTheme.errorRed,
                          iconColor: Colors.white70,
                          hoverIconColor: Colors.white,
                          glowOnHover: true,
                          onTap: () => _handleExit(ref),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Dual-Ring Glowing Status Orb
// ════════════════════════════════════════════════════════════════════════════

class _StatusOrb extends StatelessWidget {
  final Color color;
  final bool isConnected;

  const _StatusOrb({
    required this.color,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: isConnected ? 0.18 : 0.10),
        border: Border.all(
          color: color.withValues(alpha: isConnected ? 0.55 : 0.30),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isConnected ? 0.55 : 0.20),
            blurRadius: isConnected ? 10 : 4,
            spreadRadius: isConnected ? 1 : 0,
          ),
        ],
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Smooth Telemetry Badge
// ════════════════════════════════════════════════════════════════════════════

class _TelemetryBadge extends StatelessWidget {
  final String text;
  final Color color;
  final bool isSubtle;

  const _TelemetryBadge({
    super.key,
    required this.text,
    required this.color,
    this.isSubtle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isSubtle
            ? Colors.white.withValues(alpha: 0.04)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSubtle
              ? Colors.white.withValues(alpha: 0.10)
              : color.withValues(alpha: 0.38),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Isolated Tactile Window Control Button (Zero Stuck State)
// ════════════════════════════════════════════════════════════════════════════

class _FuturisticWindowButton extends StatefulWidget {
  final IconData icon;
  final Color hoverColor;
  final Color hoverBorderColor;
  final Color iconColor;
  final Color hoverIconColor;
  final bool glowOnHover;
  final Future<void> Function() onTap;

  const _FuturisticWindowButton({
    required this.icon,
    required this.hoverColor,
    required this.hoverBorderColor,
    required this.iconColor,
    required this.hoverIconColor,
    this.glowOnHover = false,
    required this.onTap,
  });

  @override
  State<_FuturisticWindowButton> createState() =>
      _FuturisticWindowButtonState();
}

class _FuturisticWindowButtonState extends State<_FuturisticWindowButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  Future<void> _triggerTap() async {
    // ریست فوری وضعیت هاور و فشردگی قبل از مخفی/مینیمایز شدن پنجره
    // تا وقتی پنجره از Tray یا Taskbar برمی‌گردد، دکمه در حالت قرمز/هاور قفل نماند
    if (mounted) {
      setState(() {
        _isHovered = false;
        _isPressed = false;
      });
    }
    await widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered || _isPressed) {
          setState(() {
            _isHovered = false;
            _isPressed = false;
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => _triggerTap(),
        child: SizedBox(
          width: 38,
          height: 32,
          child: Center(
            child: AnimatedScale(
              scale: _isPressed ? 0.88 : 1.0,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOutQuad,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isHovered ? widget.hoverColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isHovered
                        ? widget.hoverBorderColor
                        : Colors.transparent,
                    width: 0.9,
                  ),
                  boxShadow: (_isHovered && widget.glowOnHover)
                      ? [
                          BoxShadow(
                            color: widget.hoverBorderColor
                                .withValues(alpha: 0.45),
                            blurRadius: 10,
                            spreadRadius: 0.5,
                          ),
                        ]
                      : const [],
                ),
                child: Icon(
                  widget.icon,
                  size: 16.5,
                  color: _isHovered ? widget.hoverIconColor : widget.iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}