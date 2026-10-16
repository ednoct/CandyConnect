import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_config.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_wave_background.dart';
import '../utils/url_launcher_utils.dart';
import '../core/xray_bridge.dart';
import '../core/desktop_manager.dart';
import '../services/subscription_service.dart';
import '../services/latency_tester.dart';
import '../services/dns_manager.dart';
import '../services/connection_optimizer.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import '../windows/wintun_ffi.dart';
import '../windows/windivert_ffi.dart';
import '../windows/elevation_utils.dart';

// بارگذاری تنبل (Lazy Initialization) فقط در سیستم‌عامل ویندوز جهت جلوگیری از کرش در اندروید/iOS
WintunFFI? _wintunInstance;
WinDivertFFI? _winDivertInstance;

WintunFFI get _wintunFFI => _wintunInstance ??= WintunFFI();
WinDivertFFI get _winDivertFFI => _winDivertInstance ??= WinDivertFFI();

/// تابع کمکی سراسری برای توقف ایمن و کامل تمام لایه‌های تونل و هسته در همه پلتفرم‌ها
Future<void> _safeStopAllTunnels() async {
  if (Platform.isWindows) {
    try {
      _winDivertFFI.close();
      _wintunFFI.close();
    } catch (_) {}
  } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    const vpnChannel = MethodChannel('candyconnect/vpn');
    try {
      await vpnChannel.invokeMethod('stopVpn');
    } catch (_) {}
  }
  try {
    await XrayBridge.stopXray();
  } catch (_) {}
}

// ════════════════════════════════════════════════════════════════════════════
// Main Screen
// ════════════════════════════════════════════════════════════════════════════

class MainScreen extends ConsumerStatefulWidget {
  final bool autoConnectVpn;
  const MainScreen({super.key, this.autoConnectVpn = false});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  Timer? _statsTimer;
  bool _isRefreshingStats = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (int i = 0; i < 10; i++) {
        if (!mounted) return;
        if (ref.read(remoteConfigProvider) != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!mounted) return;
      await _fetchStats();
      _scheduleStatsTimer();
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  // ── Stats fetcher (مجهز به آدرس‌های پشتیبان Failover) ─────────────────────

  Future<void> _fetchStats() async {
    if (_isRefreshingStats) return;
    if (mounted) setState(() => _isRefreshingStats = true);

    try {
      final license = ref.read(currentLicenseProvider);
      final config = ref.read(remoteConfigProvider);

      if (license == null || config == null) return;

      final statsUrl = config.apiEndpoints.baseSubsStatsUrl.isNotEmpty
          ? config.apiEndpoints.baseSubsStatsUrl.first
          : '';

      if (statsUrl.isEmpty) return;

      final subService = SubscriptionService(
        config.apiEndpoints.baseJsonSubUrl,
        statsUrl,
        failoverSubUrls: config.apiEndpoints.failoverApiUrls,
        failoverStatsUrls: config.apiEndpoints.baseSubsStatsUrl.length > 1
            ? config.apiEndpoints.baseSubsStatsUrl.sublist(1)
            : const [],
      );

      final stats = await subService.fetchStats(license);

      if (stats != null && mounted) {
        ref.read(subscriptionStatsProvider.notifier).state = stats;
      }
    } catch (e, st) {
      debugPrint('[MainScreen._fetchStats] unhandled exception: $e\n$st');
    } finally {
      if (mounted) setState(() => _isRefreshingStats = false);
    }
  }

  void _scheduleStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _fetchStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final navIndex = ref.watch(navIndexProvider);
    final config = ref.watch(remoteConfigProvider);
    final isPromoDismissed = ref.watch(isPromoDismissedProvider);
    final dismissedNotifs = ref.watch(dismissedNotificationsProvider);
    final stats = ref.watch(subscriptionStatsProvider);

    ref.listen<bool>(isConnectedProvider, (previous, next) {
      if (previous != next) {
        DesktopManager().updateTrayIcon(next);
      }
    });

    // ── Force Disconnect on Expiration (در تمامی سیستم‌عامل‌ها) ───────────────
    ref.listen(subscriptionStatsProvider, (previous, next) {
      if (next != null) {
        final isNowExpired = next.isExpired ||
            (!next.isUnlimitedTraffic && next.remainingTrafficGB <= 0);

        if (isNowExpired) {
          final isConnected = ref.read(isConnectedProvider);
          if (isConnected) {
            debugPrint('[MainScreen] Subscription expired! Force stopping.');
            ref.read(isConnectedProvider.notifier).state = false;
            _safeStopAllTunnels();
          }
        }
      }
    });

    final bool isExpired = stats != null &&
        (stats.isExpired ||
            (!stats.isUnlimitedTraffic && stats.remainingTrafficGB <= 0));

    final activeNotifs = config != null
        ? config.notifications
            .where((n) => n.isActive && !dismissedNotifs.contains(n.id))
            .toList()
        : <AppNotification>[];

    final showPromo =
        config != null && config.promotions.active && !isPromoDismissed;

    return Scaffold(
      body: Stack(
        children: [
          // ── Background ────────────────────────────────────────────────────
          const AnimatedWaveBackground(),

          // ── Main content (IndexedStack جهت حفظ وضعیت HomeTab) ─────────────
          SafeArea(
            child: isExpired
                ? const SizedBox.shrink()
                : IndexedStack(
                    index: navIndex,
                    children: [
                      HomeTab(
                        autoConnectVpn: widget.autoConnectVpn,
                        onRefreshStats: _fetchStats,
                        isRefreshingStats: _isRefreshingStats,
                      ),
                      const SettingsTab(),
                    ],
                  ),
          ),

          // ── Bottom Nav (Glass) ────────────────────────────────────────────
          if (!isExpired)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: GlassCard(
                height: 70,
                padding: EdgeInsets.zero,
                child: BottomNavigationBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  currentIndex: navIndex,
                  selectedItemColor: AppTheme.neonCyan,
                  unselectedItemColor: Colors.white54,
                  onTap: (index) {
                    if (navIndex != index) {
                      HapticFeedback.selectionClick();
                      ref.read(navIndexProvider.notifier).state = index;
                    }
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_filled),
                      label: 'خانه',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings_rounded),
                      label: 'تنظیمات',
                    ),
                  ],
                ),
              ),
            ),

          // ── Promo Banner (above bottom nav) ───────────────────────────────
          if (showPromo && !isExpired)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: _PromoBanner(
                promo: config.promotions,
                botHandle: config.clientPreferences.telegramBotHandle,
                onDismiss: () =>
                    ref.read(isPromoDismissedProvider.notifier).state = true,
              ),
            ),

          // ── Notification Toasts (top-center) ──────────────────────────────
          if (activeNotifs.isNotEmpty && !isExpired)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: activeNotifs
                        .map((n) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _NotificationToast(
                                notif: n,
                                onDismiss: () => ref
                                    .read(dismissedNotificationsProvider
                                        .notifier)
                                    .dismiss(n.id),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),

          // ── Expiration Overlay ────────────────────────────────────────────
          if (isExpired) _ExpirationOverlay(onRefresh: _fetchStats),

          // ── Maintenance Overlay ───────────────────────────────────────────
          if (config != null && config.appControl.maintenanceMode.active)
            _MaintenanceOverlay(
                message: config.appControl.maintenanceMode.message),

          // ── Force Update Overlay ──────────────────────────────────────────
          if (config != null && config.appControl.forceUpdate)
            _ForceUpdateOverlay(
              updateUrl: config.appControl.updateUrl,
              version: config.appControl.latestVersion,
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Overlay & Toast Widgets
// ════════════════════════════════════════════════════════════════════════════

class _MaintenanceOverlay extends StatelessWidget {
  final String message;
  const _MaintenanceOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [AppTheme.neonPurple, AppTheme.neonCyan],
                  ).createShader(b),
                  child: const Icon(Icons.build_circle_outlined,
                      size: 72, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text(
                  'در حال نگهداری و ارتقا',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neonPurple,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, color: Colors.white70, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ForceUpdateOverlay extends StatelessWidget {
  final String updateUrl;
  final String version;
  const _ForceUpdateOverlay({required this.updateUrl, required this.version});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [AppTheme.neonCyan, AppTheme.neonPurple],
                  ).createShader(b),
                  child: const Icon(Icons.system_update_alt_rounded,
                      size: 72, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  'نسخه $version منتشر شد',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neonCyan,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'برای ادامه استفاده و تجربه بالاترین سرعت، لطفاً برنامه را به‌روز کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.white60),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.neonCyan, AppTheme.neonPurple],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => launchUrl(
                        Uri.parse(updateUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text(
                        'دانلود نسخه جدید',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Expiration Overlay
// ════════════════════════════════════════════════════════════════════════════

class _ExpirationOverlay extends ConsumerStatefulWidget {
  final Future<void> Function() onRefresh;
  const _ExpirationOverlay({required this.onRefresh});

  @override
  ConsumerState<_ExpirationOverlay> createState() => _ExpirationOverlayState();
}

class _ExpirationOverlayState extends ConsumerState<_ExpirationOverlay> {
  bool _isChecking = false;

  Future<void> _handleRefresh() async {
    HapticFeedback.lightImpact();
    setState(() => _isChecking = true);
    await widget.onRefresh();
    if (mounted) setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    final botHandle =
        ref.watch(remoteConfigProvider)?.clientPreferences.telegramBotHandle;

    return Positioned.fill(
      child: Container(
        color: AppTheme.oledDark,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.errorRed.withValues(alpha: 0.08),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.errorRed.withValues(alpha: 0.45),
                        blurRadius: 55,
                        spreadRadius: 12,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF1744), Color(0xFFFF6D00)],
                    ).createShader(b),
                    child: const Icon(
                      Icons.block_rounded,
                      size: 72,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                const Text(
                  'اشتراک شما به پایان رسید',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'برای ادامه استفاده، اشتراک خود را تمدید یا لایسنس جدید تهیه کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white60,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  children: [
                    Expanded(
                      child: _ExpirationOutlineButton(
                        label: 'خروج از اکانت',
                        icon: Icons.logout_rounded,
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('license_key');

                          if (DesktopManager().isDesktop) {
                            await DesktopManager().applySystemProxy(
                              enable: false,
                            );
                            await DesktopManager().updateTrayIcon(false);
                          }

                          final isConnected = ref.read(isConnectedProvider);
                          if (isConnected) {
                            await _safeStopAllTunnels();
                            ref.read(isConnectedProvider.notifier).state =
                                false;
                          }

                          ref.read(currentLicenseProvider.notifier).state =
                              null;
                          ref.read(subscriptionJsonProvider.notifier).state =
                              null;
                          ref.read(subscriptionStatsProvider.notifier).state =
                              null;

                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                              (route) => false,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ExpirationGradientButton(
                        label: 'خرید / تمدید',
                        icon: Icons.shopping_cart_checkout_rounded,
                        onPressed: () =>
                            UrlLauncherUtils.launchTelegramSupport(
                          customHandle: botHandle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: _isChecking ? null : _handleRefresh,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppTheme.neonCyan,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded,
                          color: AppTheme.neonCyan, size: 18),
                  label: Text(
                    _isChecking ? 'در حال بررسی...' : 'بررسی مجدد اشتراک',
                    style: const TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpirationGradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _ExpirationGradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0066FF), Color(0xFF00E5FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: Colors.black),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _ExpirationOutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _ExpirationOutlineButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white24, width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: Colors.white54),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Colors.white70,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Promo Banner
// ════════════════════════════════════════════════════════════════════════════

class _PromoBanner extends StatefulWidget {
  final PromotionConfig promo;
  final String? botHandle;
  final VoidCallback onDismiss;

  const _PromoBanner({
    required this.promo,
    this.botHandle,
    required this.onDismiss,
  });

  @override
  State<_PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends State<_PromoBanner> {
  bool _copied = false;

  void _copyCode() {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: widget.promo.discountCode));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _handleTargetAction() {
    if (widget.promo.targetAction == 'open_telegram') {
      UrlLauncherUtils.launchTelegramSupport(customHandle: widget.botHandle);
    } else if (widget.promo.targetAction.startsWith('http')) {
      launchUrl(
        Uri.parse(widget.promo.targetAction),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.neonPurple.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: _handleTargetAction,
                child: const Icon(Icons.local_offer_rounded,
                    color: AppTheme.neonPurple, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _handleTargetAction,
                      child: Text(
                        widget.promo.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _copyCode,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _copied
                              ? AppTheme.neonCyan.withValues(alpha: 0.2)
                              : AppTheme.neonPurple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _copied
                                ? AppTheme.neonCyan
                                : AppTheme.neonPurple.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _copied ? Icons.check_rounded : Icons.copy,
                              size: 12,
                              color: AppTheme.neonCyan,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _copied
                                  ? 'کپی شد!'
                                  : widget.promo.discountCode,
                              style: const TextStyle(
                                color: AppTheme.neonCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: widget.onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationToast extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onDismiss;
  const _NotificationToast({required this.notif, required this.onDismiss});

  Color get _borderColor {
    switch (notif.type) {
      case 'warning':
        return Colors.amber;
      case 'error':
        return AppTheme.errorRed;
      default:
        return AppTheme.neonCyan;
    }
  }

  IconData get _typeIcon {
    switch (notif.type) {
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'error':
        return Icons.error_outline_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: notif.actionUrl != null
          ? () => launchUrl(Uri.parse(notif.actionUrl!),
              mode: LaunchMode.externalApplication)
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _borderColor.withValues(alpha: 0.55), width: 1),
            ),
            child: Row(
              children: [
                Icon(_typeIcon, color: _borderColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        notif.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white),
                      ),
                      if (notif.message.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          notif.message,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ],
                  ),
                ),
                if (notif.dismissible)
                  GestureDetector(
                    onTap: onDismiss,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.close, size: 16, color: Colors.white38),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Home Tab
// ════════════════════════════════════════════════════════════════════════════

class HomeTab extends ConsumerStatefulWidget {
  final bool autoConnectVpn;
  final Future<void> Function()? onRefreshStats;
  final bool isRefreshingStats;

  const HomeTab({
    super.key,
    this.autoConnectVpn = false,
    this.onRefreshStats,
    this.isRefreshingStats = false,
  });

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  bool _isConnecting = false;
  bool _abortRequested = false;
  bool _isMeasuringLatency = false;
  bool _latencyProbeError = false;

  final LatencyTester _latencyTester = LatencyTester();
  dynamic _currentNode;
  int _currentNodeLatencyMs = -1;
  int _bestNodeLatencyMs = -1;

  final DnsManager _dnsManager = DnsManager();
  final ConnectionOptimizer _connectionOptimizer = ConnectionOptimizer();
  OptimizedResult? _lastOptimizedResult;

  @override
  void dispose() {
    if (DesktopManager().isDesktop) {
      DesktopManager().onToggleConnectionRequested = null;
      DesktopManager().onBeforeExitCleanup = null;
      DesktopManager().onModeChanged = null;
    }
    _latencyTester.stop();
    _connectionOptimizer.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // ── اتصال مستقیم منوی Tray دسکتاپ به کنترل‌های HomeTab و Providers ──────
    if (DesktopManager().isDesktop) {
      DesktopManager().onToggleConnectionRequested = _toggleConnection;
      DesktopManager().onBeforeExitCleanup = _safeStopAllTunnels;
      DesktopManager().onModeChanged = (mode) {
        if (!mounted) return;
        ref.read(desktopSystemProxyProvider.notifier).state =
            (mode == DesktopRoutingMode.proxySystem);
        _handleModeSwitch(mode == DesktopRoutingMode.tunnelVpn);
      };
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final license = ref.read(currentLicenseProvider);

      if (license == null || ref.read(subscriptionJsonProvider) != null) {
        for (int i = 0; i < 10; i++) {
          if (!mounted) return;
          if (ref.read(remoteConfigProvider) != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (!mounted) return;
        _maybeStartLatencyTester();
        return;
      }

      RemoteConfig? config;
      for (int i = 0; i < 10; i++) {
        if (!mounted) return;
        config = ref.read(remoteConfigProvider);
        if (config != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!mounted) return;

      if (config != null) {
        final subService = SubscriptionService(
          config.apiEndpoints.baseJsonSubUrl,
          config.apiEndpoints.baseSubsStatsUrl.isNotEmpty
              ? config.apiEndpoints.baseSubsStatsUrl.first
              : '',
          failoverSubUrls: config.apiEndpoints.failoverApiUrls,
          failoverStatsUrls: config.apiEndpoints.baseSubsStatsUrl.length > 1
              ? config.apiEndpoints.baseSubsStatsUrl.sublist(1)
              : const [],
        );
        final sub = await subService.fetchSubscription(license);
        if (sub != null && mounted) {
          ref.read(subscriptionJsonProvider.notifier).state = sub;
        }
      }
      if (!mounted) return;
      _maybeStartLatencyTester();
      if (widget.autoConnectVpn) {
        _toggleConnection();
      }
    });
  }

  // ── Latency tester ────────────────────────────────────────────────────────

  void _maybeStartLatencyTester() {
    final nodes = ref.read(subscriptionJsonProvider);
    if (nodes == null || nodes.isEmpty) return;
    final config = ref.read(remoteConfigProvider);
    final probeUrl = config?.networkProbes.latencyTargetUrl ?? '';

    _latencyTester.start(
      nodes: nodes,
      probeUrl: probeUrl,
      currentNodeGetter: () => _currentNode,
      onBestNodeFound: (NodeLatencyResult best) {
        if (!mounted) return;
        if (best.latencyMs > 0) {
          setState(() {
            _bestNodeLatencyMs = best.latencyMs;
          });
        }
        final isConnected = ref.read(isConnectedProvider);
        if (!isConnected || _isConnecting) return;
        if (best.node == _currentNode) return;

        final bool shouldSwitch = _currentNodeLatencyMs <= 0 ||
            (best.latencyMs > 0 &&
                (_currentNodeLatencyMs - best.latencyMs) >= 40 &&
                best.latencyMs < (_currentNodeLatencyMs * 0.7));

        if (!shouldSwitch) return;

        debugPrint('[LatencyTester] Switching to significantly better node '
            '(${best.latencyMs}ms vs current ${_currentNodeLatencyMs}ms)');
        _currentNodeLatencyMs = best.latencyMs;
        _connectNode(best.node);
      },
    );
  }

  Future<void> _refreshLatency() async {
    if (_isMeasuringLatency) return;
    HapticFeedback.lightImpact();

    setState(() {
      _isMeasuringLatency = true;
      _latencyProbeError = false;
    });

    try {
      final nodes = ref.read(subscriptionJsonProvider);
      if (nodes == null || nodes.isEmpty) {
        if (mounted) setState(() => _latencyProbeError = true);
        return;
      }

      final oneShot = LatencyTester();
      final results = await oneShot.measureAll(nodes);
      oneShot.stop();

      final best = results?.firstOrNull;
      final isConnected = ref.read(isConnectedProvider);
      final isVpnMode = ref.read(isVpnModeProvider);

      if (mounted) {
        if (best != null && best.latencyMs > 0) {
          if (isConnected && isVpnMode && best.latencyMs <= 5) {
            setState(() => _isMeasuringLatency = false);
            return;
          }

          setState(() {
            _bestNodeLatencyMs = best.latencyMs;
            _currentNodeLatencyMs = best.latencyMs;
            _latencyProbeError = false;
          });
        } else {
          setState(() => _latencyProbeError = true);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _latencyProbeError = true);
    } finally {
      if (mounted) setState(() => _isMeasuringLatency = false);
    }
  }

  // ── Mode Switcher Handler ─────────────────────────────────────────────────

  Future<void> _handleModeSwitch(bool targetVpnMode) async {
    final currentMode = ref.read(isVpnModeProvider);
    if (currentMode == targetVpnMode) return;

    HapticFeedback.selectionClick();
    ref.read(isVpnModeProvider.notifier).state = targetVpnMode;

    if (DesktopManager().isDesktop) {
      final sysProxy = ref.read(desktopSystemProxyProvider);
      await DesktopManager().updateTrayIcon(
        ref.read(isConnectedProvider),
        mode: targetVpnMode
            ? DesktopRoutingMode.tunnelVpn
            : (sysProxy
                ? DesktopRoutingMode.proxySystem
                : DesktopRoutingMode.proxyLocal),
      );
    }

    final isConnected = ref.read(isConnectedProvider);
    if (isConnected && !_isConnecting && _currentNode != null) {
      await _connectNode(_currentNode);
    }
  }

  // ── Connection logic ──────────────────────────────────────────────────────

  Future<void> _toggleConnection() async {
    HapticFeedback.mediumImpact();
    final isConnected = ref.read(isConnectedProvider);
    final isVpnMode = ref.read(isVpnModeProvider);

    // ── ۱. امکان لغو فوری در حین تلاش برای اتصال (Abort In-Flight Connect) ──
    if (_isConnecting) {
      debugPrint('[_toggleConnection] Aborting in-flight connection attempt.');
      _abortRequested = true;
      await _connectionOptimizer.cancel();
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _bestNodeLatencyMs = -1;
        });
      }
      await _safeStopAllTunnels();
      ref.read(isConnectedProvider.notifier).state = false;
      return;
    }

    // ── ۲. منطق قطع اتصال (DISCONNECT LOGIC) ──
    if (isConnected) {
      debugPrint('[_toggleConnection] Disconnect initiated.');
      ref.read(isConnectedProvider.notifier).state = false;
      _currentNode = null;
      _currentNodeLatencyMs = -1;
      _lastOptimizedResult = null;
      if (mounted) {
        setState(() {
          _bestNodeLatencyMs = -1;
          _isConnecting = false;
        });
      }

      await _connectionOptimizer.cancel();
      await _safeStopAllTunnels();
      return;
    }

    // ── ۳. منطق اتصال (CONNECT LOGIC) ──
    if (Platform.isWindows && isVpnMode) {
      if (!ElevationUtils.isElevated()) {
        await ElevationUtils.relaunchElevated(['--auto-connect-vpn']);
        return;
      }
    }

    final subJsonList = ref.read(subscriptionJsonProvider);
    if (subJsonList == null || subJsonList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'در حال دریافت اطلاعات سرورها، لطفاً چند لحظه صبر کنید...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    _abortRequested = false;
    setState(() => _isConnecting = true);

    // ── Phase 1 (TCP): Race all nodes via TCP handshake ───────────────────
    NodeLatencyResult? bestResult;
    List<dynamic> top3Nodes = [];
    try {
      final oneShot = LatencyTester();
      final results = await oneShot.measureAll(subJsonList);
      oneShot.stop();
      bestResult = results?.firstOrNull;
      top3Nodes = results
              ?.where((r) => r.isReachable)
              .take(3)
              .map((r) => r.node)
              .toList() ??
          [];
    } catch (_) {}

    if (_abortRequested || !mounted) return;

    _currentNode = bestResult?.node ?? subJsonList.first;
    _currentNodeLatencyMs = bestResult?.latencyMs ?? -1;
    if (mounted && _currentNodeLatencyMs > 0) {
      setState(() => _bestNodeLatencyMs = _currentNodeLatencyMs);
    }

    // ── Phase 2 & 3 (Silent): Bootstrap DNS race + Real-delay benchmark ───
    _lastOptimizedResult = null;
    final config = ref.read(remoteConfigProvider);
    if (config != null && top3Nodes.isNotEmpty) {
      try {
        _connectionOptimizer.reset();

        final bootstrapDns = await _dnsManager.raceBestBootstrap(
          config.dnsRouting.bootstrapDnsPool,
        );

        if (_abortRequested || !mounted) return;

        final variants = _dnsManager.generateVariants(
          nodes: top3Nodes,
          remoteDnsPool: config.dnsRouting.remoteDnsPool,
        );

        final effectiveProbeUrl =
            config.networkProbes.latencyTargetUrl.isNotEmpty
                ? config.networkProbes.latencyTargetUrl
                : 'http://cp.cloudflare.com/generate_204';

        _lastOptimizedResult = await _connectionOptimizer.findBest(
          variants: variants,
          bootstrapDns: bootstrapDns,
          probeUrl: effectiveProbeUrl,
        );
      } catch (e) {
        debugPrint('[HomeTab] Silent DNS optimization failed: $e');
      }
    }

    if (_abortRequested || !mounted) return;

    // ── Phase 4: Connect with the best available node ─────────────────────
    final nodeToConnect = (_lastOptimizedResult?.node ??
        (bestResult?.node ?? subJsonList.first)) as Map<String, dynamic>;
    _currentNode = nodeToConnect;

    await _connectNode(nodeToConnect);
  }

  /// Stops the current Xray instance (if any) and starts a new one on [rawNode].
  Future<void> _connectNode(dynamic rawNode) async {
    if (rawNode is! Map<String, dynamic>) return;

    if (mounted && !_isConnecting) {
      setState(() => _isConnecting = true);
    }

    final node = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(rawNode)) as Map<String, dynamic>,
    );

    _currentNode = rawNode;

    final isConnected = ref.read(isConnectedProvider);
    final isVpnMode = ref.read(isVpnModeProvider);
    final config = ref.read(remoteConfigProvider);

    if (isConnected) {
      ref.read(isConnectedProvider.notifier).state = false;
      await _safeStopAllTunnels();
    }

    if (_abortRequested || !mounted) {
      if (mounted) setState(() => _isConnecting = false);
      return;
    }

    if (Platform.isAndroid && isVpnMode) {
      const vpnChannel = MethodChannel('candyconnect/vpn');
      try {
        final granted =
            await vpnChannel.invokeMethod<bool>('prepareVpn') ?? false;
        if (!granted) {
          if (mounted) setState(() => _isConnecting = false);
          return;
        }

        final proxyMode = ref.read(perAppProxyModeProvider);
        final selectedApps = ref.read(selectedAppsProvider).toList();

        final fd = await vpnChannel.invokeMethod<int>('startVpn', {
              'proxyMode': proxyMode,
              'selectedApps': selectedApps,
            }) ??
            -1;

        node.putIfAbsent('env', () => <String, dynamic>{});
        (node['env'] as Map)['xray.tun.fd'] = fd;
      } catch (e) {
        debugPrint('[_connectNode] VPN channel error: $e');
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      if (isVpnMode) {
        const vpnChannel = MethodChannel('candyconnect/vpn');
        try {
          await vpnChannel.invokeMethod('startVpn');
        } catch (e) {
          debugPrint('[_connectNode] VPN channel error: $e');
        }
      }
      node.putIfAbsent('env', () => <String, dynamic>{});
      (node['env'] as Map)['xray.tun.fd'] = -1;
    } else {
      (node['env'] as Map?)?.remove('xray.tun.fd');
    }

    if (node['inbounds'] is List) {
      final isLanSharing = ref.read(isLanSharingProvider);
      final listenAddress = isLanSharing ? '0.0.0.0' : '127.0.0.1';
      for (var inbound in node['inbounds'] as List) {
        if (inbound is Map) inbound['listen'] = listenAddress;
      }
    }

    // ── Phase 4: DNS Architecture Injection ───────────────────────────────
    final optimized = _lastOptimizedResult;
    if (optimized != null) {
      if (node['dns'] == null || node['dns'] is! Map) {
        node['dns'] = <String, dynamic>{};
      }
      final dnsMap = node['dns'] as Map<String, dynamic>;

      final preservedServers = <dynamic>[];
      if (dnsMap['servers'] is List) {
        for (final s in dnsMap['servers'] as List) {
          if (s is Map && s.containsKey('domains')) {
            preservedServers.add(s);
          }
        }
      }

      dnsMap['servers'] = [
        optimized.bootstrapDns,
        optimized.remoteDns,
        'localhost',
        ...preservedServers,
      ];

      if (node['routing'] == null || node['routing'] is! Map) {
        node['routing'] = <String, dynamic>{};
      }
      final routingMap = node['routing'] as Map<String, dynamic>;
      final existingDnsRules = List<dynamic>.from(
        routingMap['rules'] as List? ?? [],
      );
      routingMap['rules'] = [
        {
          'type': 'field',
          'ip': ['${optimized.bootstrapDns}/32'],
          'outboundTag': 'direct',
        },
        ...existingDnsRules,
      ];
    }

    if (Platform.isWindows && isVpnMode) {
      node['dns'] ??= {};
      node['dns']['servers'] = [
        "fakedns",
        ...(node['dns']['servers'] as List? ?? [])
      ];
      node['fakedns'] = [
        {"ipPool": "198.18.0.0/15", "poolSize": 65535}
      ];

      final existingInbounds =
          List<dynamic>.from(node['inbounds'] as List? ?? []);
      for (var inbound in existingInbounds) {
        if (inbound is Map && inbound['port'] == 10808) {
          inbound['port'] = 10810;
        }
      }

      // تضمین ارسال صرفاً آدرس‌های IPv4 معتبر به آداپتور TUN ویندوز (در صورت برنده شدن DoH)
      final List<String> tunDnsList =
          (optimized != null && DnsManager.isIpv4Address(optimized.remoteDns))
              ? <String>{optimized.remoteDns, "1.1.1.1", "8.8.8.8"}
                  .take(2)
                  .toList()
              : ["1.1.1.1", "8.8.8.8"];

      node['inbounds'] = [
        {
          "tag": "tun-in",
          "protocol": "tun",
          "settings": {
            "name": "CandyConnectVPN",
            "desc": "CandyConnectVPN",
            "mtu": 1500,
            "gateway": ["10.0.0.1/16", "fc00::1/64"],
            "dns": tunDnsList,
            "autoSystemRoutingTable": ["0.0.0.0/0", "::/0"],
            "autoOutboundsInterface": "auto"
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "fakedns"],
          }
        },
        ...existingInbounds
      ];

      final existingOutbounds =
          List<dynamic>.from(node['outbounds'] as List? ?? []);
      bool hasDnsOut =
          existingOutbounds.any((o) => o is Map && o['tag'] == 'dns-out');
      if (!hasDnsOut) {
        existingOutbounds.insert(0, {"tag": "dns-out", "protocol": "dns"});
        node['outbounds'] = existingOutbounds;
      }

      node['routing'] ??= {};
      final existingRules =
          List<dynamic>.from(node['routing']['rules'] as List? ?? []);
      node['routing']['rules'] = [
        {
          "type": "field",
          "inboundTag": ["tun-in"],
          "port": 53,
          "outboundTag": "dns-out"
        },
        ...existingRules
      ];
    }

    // ── Universal Geo-Routing & Split-Tunneling Injection ──────────────────
    String? geoAssetDir;
    try {
      geoAssetDir = await XrayBridge.ensureRoutingAssets();
    } catch (e) {
      debugPrint('[_connectNode] Failed to extract routing assets: $e');
    }

    if (geoAssetDir != null) {
      node.putIfAbsent('env', () => <String, dynamic>{});
      (node['env'] as Map)['xray.location.asset'] = geoAssetDir;

      node.putIfAbsent('routing', () => <String, dynamic>{});
      final routingMap = node['routing'] as Map<String, dynamic>;
      final existingRules =
          List<dynamic>.from(routingMap['rules'] as List? ?? []);

      final splitConfig = config?.splitTunneling;
      final bypassDomestic = splitConfig?.bypassDomesticTraffic ?? true;
      final blockAds = splitConfig?.blockAdsAndTrackers ?? false;

      final injectedRules = <Map<String, dynamic>>[
        {
          'type': 'field',
          'ip': ['geoip:private'],
          'outboundTag': 'direct',
        },
      ];

      if (blockAds &&
          splitConfig != null &&
          splitConfig.blockedDomains.isNotEmpty) {
        final existingOutbounds =
            List<dynamic>.from(node['outbounds'] as List? ?? []);
        final hasBlockOutbound =
            existingOutbounds.any((o) => o is Map && o['tag'] == 'block');
        if (hasBlockOutbound) {
          injectedRules.add({
            'type': 'field',
            'domain': splitConfig.blockedDomains,
            'outboundTag': 'block',
          });
        }
      }

      if (bypassDomestic) {
        final domesticDomains = <String>{
          'geosite:ir',
          if (splitConfig != null) ...splitConfig.directDomains,
        }.toList();

        injectedRules.addAll([
          {
            'type': 'field',
            'ip': ['geoip:ir'],
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'domain': domesticDomains,
            'outboundTag': 'direct',
          },
        ]);
      }

      routingMap['rules'] = [
        ...injectedRules,
        ...existingRules,
      ];
    }

    final jsonString = jsonEncode(node);

    try {
      bool hasError = false;
      String? errorMessage;

      await XrayBridge.startXray(jsonString, (message) {
        if (message.isNotEmpty) {
          try {
            final jsonMap = jsonDecode(message);
            if (jsonMap['success'] == false) {
              hasError = true;
              errorMessage = jsonMap['error']?.toString() ?? 'Unknown error';
            } else if (jsonMap['success'] != true) {
              hasError = true;
              errorMessage = message;
            }
          } catch (_) {
            hasError = true;
            errorMessage = message;
          }
        }
      });

      await Future.delayed(const Duration(seconds: 1));

      if (_abortRequested || !mounted) {
        await _safeStopAllTunnels();
        return;
      }

      if (hasError) {
        ref.read(isConnectedProvider.notifier).state = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در اجرای هسته: $errorMessage'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ref.read(isConnectedProvider.notifier).state = true;
        if (mounted) setState(() => _isConnecting = false);

        if (Platform.isWindows && isVpnMode) {
          Future.microtask(() async {
            int wintunIfIdx = -1;
            for (int i = 0; i < 10; i++) {
              await Future.delayed(const Duration(milliseconds: 500));
              wintunIfIdx = await _wintunFFI
                  .getInterfaceIndex("CandyConnectVPN Tunnel");
              if (wintunIfIdx == -1) {
                wintunIfIdx =
                    await _wintunFFI.getInterfaceIndex("CandyConnectVPN");
              }
              if (wintunIfIdx != -1) break;
            }
            if (wintunIfIdx != -1) {
              _winDivertFFI.startAntiSmhnr(wintunIfIdx);
            }
          });
        }
      }
    } catch (e) {
      ref.read(isConnectedProvider.notifier).state = false;
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  /// محاسبه هوشمند کسر روزهای باقیمانده متناسب با بسته‌های ۳۰، ۶۰ و ۹۰ روزه
  double _computeDaysFraction(dynamic stats) {
    if (stats == null) return 0.0;
    if (stats.isUnlimitedTime) return 1.0;
    if (stats.isExpired || stats.daysRemaining <= 0) return 0.0;

    final int days = stats.daysRemaining;
    final double cycleMax = days > 60
        ? 90.0
        : (days > 30 ? 60.0 : 30.0);
    return (days / cycleMax).clamp(0.0, 1.0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(isConnectedProvider);
    final isVpnMode = ref.watch(isVpnModeProvider);
    final stats = ref.watch(subscriptionStatsProvider);
    final botHandle =
        ref.watch(remoteConfigProvider)?.clientPreferences.telegramBotHandle;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  // ── Top Navbar toggles ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: GlassCard(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _handleModeSwitch(true),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                decoration: BoxDecoration(
                                  color: isVpnMode
                                      ? AppTheme.neonCyan
                                          .withValues(alpha: 0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'VPN (کل دستگاه)',
                                  style: TextStyle(
                                    color: isVpnMode
                                        ? AppTheme.neonCyan
                                        : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _handleModeSwitch(false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                decoration: BoxDecoration(
                                  color: !isVpnMode
                                      ? AppTheme.neonPurple
                                          .withValues(alpha: 0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'حالت پروکسی',
                                  style: TextStyle(
                                    color: !isVpnMode
                                        ? AppTheme.neonPurple
                                        : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // ── Connection Button (با قابلیت لغو در حین اتصال) ───────
                  GestureDetector(
                    onTap: _toggleConnection,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.oledDark,
                        border: Border.all(
                          color: isConnected
                              ? AppTheme.neonCyan
                              : (_isConnecting
                                  ? AppTheme.neonPurple
                                  : Colors.white24),
                          width: 2.2,
                        ),
                        boxShadow: isConnected
                            ? [
                                BoxShadow(
                                  color: AppTheme.neonCyan
                                      .withValues(alpha: 0.5),
                                  blurRadius: 50,
                                  spreadRadius: 10,
                                )
                              ]
                            : [],
                      ),
                      alignment: Alignment.center,
                      child: _isConnecting
                          ? Stack(
                              alignment: Alignment.center,
                              children: const [
                                SizedBox(
                                  width: 84,
                                  height: 84,
                                  child: CircularProgressIndicator(
                                    color: AppTheme.neonCyan,
                                    strokeWidth: 3,
                                  ),
                                ),
                                Icon(
                                  Icons.close_rounded,
                                  size: 36,
                                  color: Colors.white70,
                                ),
                              ],
                            )
                          : Icon(
                              Icons.power_settings_new_rounded,
                              size: 80,
                              color: isConnected
                                  ? AppTheme.neonCyan
                                  : Colors.white54,
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    isConnected
                        ? 'متصل شد'
                        : (_isConnecting
                            ? 'در حال یافتن بهترین سرور... (برای لغو ضربه بزنید)'
                            : 'برای اتصال ضربه بزنید'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isConnected ? AppTheme.neonCyan : Colors.white70,
                      fontSize: _isConnecting ? 14 : 18,
                      fontWeight:
                          isConnected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),

                  // ── Latency badge ────────────────────────────────────────
                  if (isConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(
                          opacity: animation,
                          child:
                              ScaleTransition(scale: animation, child: child),
                        ),
                        child: _isMeasuringLatency
                            ? _PingPill(
                                key: const ValueKey('ping-measuring'),
                                onTap: null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: AppTheme.neonCyan,
                                      ),
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'در حال سنجش...',
                                      style: TextStyle(
                                        color: AppTheme.neonCyan,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _bestNodeLatencyMs > 0
                                ? _PingPill(
                                    key: ValueKey(
                                        'ping-result-$_bestNodeLatencyMs'),
                                    onTap: _refreshLatency,
                                    glowColor: _bestNodeLatencyMs < 120
                                        ? AppTheme.neonCyan
                                        : _bestNodeLatencyMs < 250
                                            ? Colors.amber
                                            : Colors.orange,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.network_ping_rounded,
                                          size: 13,
                                          color: _bestNodeLatencyMs < 120
                                              ? AppTheme.neonCyan
                                              : _bestNodeLatencyMs < 250
                                                  ? Colors.amber
                                                  : Colors.orange,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          '$_bestNodeLatencyMs میلی‌ثانیه',
                                          style: TextStyle(
                                            color: _bestNodeLatencyMs < 120
                                                ? AppTheme.neonCyan
                                                : _bestNodeLatencyMs < 250
                                                    ? Colors.amber
                                                    : Colors.orange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _latencyProbeError
                                    ? _PingPill(
                                        key: const ValueKey('ping-error'),
                                        onTap: _refreshLatency,
                                        glowColor: Colors.redAccent,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(
                                                Icons
                                                    .signal_wifi_statusbar_null_rounded,
                                                size: 13,
                                                color: Colors.redAccent),
                                            SizedBox(width: 5),
                                            Text(
                                              'اتصال ضعیف — تلاش مجدد',
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : _PingPill(
                                        key: const ValueKey('ping-idle'),
                                        onTap: _refreshLatency,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(Icons.radar_rounded,
                                                size: 13,
                                                color: Colors.white60),
                                            SizedBox(width: 5),
                                            Text(
                                              'گرفتن پینگ',
                                              style: TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                      ),
                    ),

                  const Spacer(),

                  // ── Premium Stats Progress Bars ──────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'وضعیت اشتراک',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (widget.onRefreshStats != null)
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: widget.isRefreshingStats
                                    ? null
                                    : () {
                                        HapticFeedback.lightImpact();
                                        widget.onRefreshStats!();
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.isRefreshingStats)
                                        const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppTheme.neonCyan,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.refresh_rounded,
                                          size: 14,
                                          color: AppTheme.neonCyan,
                                        ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'بروزرسانی',
                                        style: TextStyle(
                                          color: AppTheme.neonCyan,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── Traffic bar ────────────────────────────────────
                        _PremiumStatBar(
                          label: 'ترافیک باقیمانده:',
                          valueText: stats == null
                              ? '—'
                              : stats.isUnlimitedTraffic
                                  ? 'نامحدود'
                                  : '${stats.remainingTrafficGB.toStringAsFixed(2)} گیگابایت',
                          isUnlimited: stats?.isUnlimitedTraffic ?? false,
                          isDanger: stats != null &&
                              !stats.isUnlimitedTraffic &&
                              stats.trafficFraction <= 0.20,
                          fraction: stats?.trafficFraction ?? 0.0,
                        ),

                        const SizedBox(height: 18),

                          // ── Days bar (سازگار با بسته‌های ۳۰، ۶۰ و ۹۰ روزه) ──
                        _PremiumStatBar(
                          label: 'زمان باقیمانده:',
                          valueText: stats == null
                              ? '—'
                              : stats.isUnlimitedTime
                                  ? 'نامحدود'
                                  : stats.isExpired
                                      ? 'منقضی شده'
                                      : '${stats.daysRemaining} روز',
                          isUnlimited: stats?.isUnlimitedTime ?? false,
                          isDanger: stats != null &&
                              !stats.isUnlimitedTime &&
                              (stats.isExpired || stats.daysRemaining <= 5),
                          fraction: _computeDaysFraction(stats),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Support Button ───────────────────────────────────────
                  TextButton.icon(
                    onPressed: () => UrlLauncherUtils.launchTelegramSupport(
                      customHandle: botHandle,
                    ),
                    icon: const Icon(Icons.support_agent_rounded,
                        color: AppTheme.neonCyan),
                    label: const Text(
                      'پشتیبانی تلگرام',
                      style: TextStyle(color: AppTheme.neonCyan),
                    ),
                  ),

                  const SizedBox(height: 110),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Premium Stat Bar Widget
// ════════════════════════════════════════════════════════════════════════════

class _PremiumStatBar extends StatelessWidget {
  final String label;
  final String valueText;
  final bool isUnlimited;
  final double fraction;
  final bool isDanger;

  const _PremiumStatBar({
    required this.label,
    required this.valueText,
    required this.isUnlimited,
    required this.fraction,
    this.isDanger = false,
  });

  static const Color _safeColor = Color(0xFF00E5FF);
  static const Color _safeGlow = Color(0xFF0066FF);
  static const Color _dangerColor = Color(0xFFFF1744);
  static const Color _dangerGlow = Color(0xFFFF6D00);

  bool get _inDanger => isDanger || (!isUnlimited && fraction <= 0.20);

  Color get _barColor =>
      (isUnlimited || !_inDanger) ? _safeColor : _dangerColor;

  Color get _glowColor =>
      (isUnlimited || !_inDanger) ? _safeGlow : _dangerGlow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 500),
              style: TextStyle(
                color: _barColor,
                fontSize: 13,
                fontWeight: isUnlimited ? FontWeight.bold : FontWeight.w600,
                shadows: [
                  Shadow(
                    color: _barColor.withValues(alpha: 0.8),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(valueText),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final fillWidth =
                (trackWidth * fraction).clamp(0.0, trackWidth);
            return Stack(
              children: [
                Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  height: 7,
                  width: fillWidth,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_glowColor, _barColor],
                    ),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: _barColor.withValues(alpha: 0.65),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Ping Pill
// ════════════════════════════════════════════════════════════════════════════

class _PingPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color glowColor;

  const _PingPill({
    super.key,
    required this.child,
    required this.onTap,
    this.glowColor = Colors.white24,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: glowColor.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.20),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}