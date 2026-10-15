import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../core/desktop_manager.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class CustomDesktopTitleBar extends ConsumerStatefulWidget {
  const CustomDesktopTitleBar({super.key});

  @override
  ConsumerState<CustomDesktopTitleBar> createState() =>
      _CustomDesktopTitleBarState();
}

class _CustomDesktopTitleBarState
    extends ConsumerState<CustomDesktopTitleBar> {
  bool _isMinimizeHovered = false;
  bool _isExitHovered = false;

  Future<void> _onMinimizePressed() async {
    await windowManager.minimize();
  }

  Future<void> _onExitPressed() async {
    final currentLicense = ref.read(currentLicenseProvider);

    if (currentLicense != null && currentLicense.isNotEmpty) {
      // کاربر لاگین است: مخفی‌سازی نرم در System Tray
      await windowManager.hide();
    } else {
      // کاربر لاگین نیست: خروج ایمن با پاکسازی کامل پروکسی سیستم و هسته Xray
      await DesktopManager().hardExit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(isConnectedProvider);
    final currentLicense = ref.watch(currentLicenseProvider);
    final isLoggedIn = currentLicense != null && currentLicense.isNotEmpty;

    final Color statusColor =
        isConnected ? AppTheme.neonCyan : AppTheme.neonPurple;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DragToMoveArea(
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.oledDark.withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(
                color: isConnected
                    ? AppTheme.neonCyan.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              // ── نشانگر نوری وضعیت زنده ──────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.8),
                      blurRadius: isConnected ? 10 : 6,
                      spreadRadius: isConnected ? 1.5 : 0.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'CANDY CONNECT',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
              if (isConnected) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.neonCyan.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'PROTECTED',
                    style: TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // ── دکمه کوچک‌سازی (Minimize) ───────────────────────────────
              Tooltip(
                message: 'کوچک‌سازی پنجره',
                waitDuration: const Duration(milliseconds: 500),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isMinimizeHovered = true),
                  onExit: (_) => setState(() => _isMinimizeHovered = false),
                  child: GestureDetector(
                    onTap: _onMinimizePressed,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 46,
                      height: 40,
                      alignment: Alignment.center,
                      color: _isMinimizeHovered
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.transparent,
                      child: Icon(
                        Icons.horizontal_rule_rounded,
                        color:
                            _isMinimizeHovered ? Colors.white : Colors.white60,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),

              // ── دکمه بستن / انتقال به System Tray ───────────────────────
              Tooltip(
                message: isLoggedIn ? 'انتقال به کنار ساعت' : 'بستن برنامه',
                waitDuration: const Duration(milliseconds: 500),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isExitHovered = true),
                  onExit: (_) => setState(() => _isExitHovered = false),
                  child: GestureDetector(
                    onTap: _onExitPressed,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 46,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _isExitHovered
                            ? AppTheme.errorRed
                            : Colors.transparent,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: _isExitHovered ? Colors.white : Colors.white70,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}