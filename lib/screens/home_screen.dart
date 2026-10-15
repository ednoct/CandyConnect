import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/remote_config.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_wave_background.dart';
import '../utils/url_launcher_utils.dart';
import '../core/xray_bridge.dart';
import '../services/subscription_service.dart';
import '../services/latency_tester.dart';
import '../services/dns_manager.dart';
import '../services/connection_optimizer.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../windows/wintun_ffi.dart';
import '../windows/windivert_ffi.dart';
import '../windows/elevation_utils.dart';

final _wintunFFI = WintunFFI();
final _winDivertFFI = WinDivertFFI();

// ════════════════════════════════════════════════════════════════════════════
// Main Screen
// Owns the stats timer so it keeps ticking whether HomeTab or
// _ExpirationOverlay is shown — the overlay reacts automatically via
// subscriptionStatsProvider.
// ════════════════════════════════════════════════════════════════════════════

class MainScreen extends ConsumerStatefulWidget {
  final bool autoConnectVpn;
  const MainScreen({super.key, this.autoConnectVpn = false});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait up to 5 s for RemoteConfig to populate.
      for (int i = 0; i < 10; i++) {
        if (ref.read(remoteConfigProvider) != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      await _fetchStats();
      _scheduleStatsTimer();
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  // ── Stats fetcher ─────────────────────────────────────────────────────────

  Future<void> _fetchStats() async {
    try {
      final license = ref.read(currentLicenseProvider);
      final config = ref.read(remoteConfigProvider);

      debugPrint('[MainScreen._fetchStats] '
          'license=${license != null ? '***' : 'null'} '
          'config=${config != null} '
          'statsUrl=${config?.apiEndpoints.baseSubsStatsUrl}');

      if (license == null || config == null) {
        debugPrint('[MainScreen._fetchStats] bailing — license or config null');
        return;
      }

      final statsUrl = config.apiEndpoints.baseSubsStatsUrl.isNotEmpty
          ? config.apiEndpoints.baseSubsStatsUrl.first
          : '';

      if (statsUrl.isEmpty) {
        debugPrint('[MainScreen._fetchStats] bailing — statsUrl empty');
        return;
      }

      final subService = SubscriptionService(
        config.apiEndpoints.baseJsonSubUrl,
        statsUrl,
      );

      final stats = await subService.fetchStats(license);

      debugPrint('[MainScreen._fetchStats] result: ${stats == null
          ? 'null (fetch/parse failed)'
          : 'unlimitedTraffic=${stats.isUnlimitedTraffic} '
            'unlimitedTime=${stats.isUnlimitedTime} '
            'expired=${stats.isExpired} '
            'remainingGB=${stats.remainingTrafficGB} '
            'days=${stats.daysRemaining}'}');

      if (stats != null && mounted) {
        ref.read(subscriptionStatsProvider.notifier).state = stats;
      }
    } catch (e, st) {
      debugPrint('[MainScreen._fetchStats] unhandled exception: $e\n$st');
    }
  }

  // ── Stats auto-refresh timer ──────────────────────────────────────────────

  void _scheduleStatsTimer() {
    _statsTimer?.cancel();
    debugPrint('[MainScreen] scheduling stats refresh every 3 min');
    _statsTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      debugPrint('[MainScreen] periodic tick — refreshing stats');
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

    // ── Force Disconnect on Expiration ───────────────────────────────────────
    // Listens to the stats provider out-of-band from the build phase. 
    // If it detects the account is expired, it forces Xray to stop immediately.
    ref.listen(subscriptionStatsProvider, (previous, next) {
      if (next != null) {
        final isNowExpired = next.isExpired ||
            (!next.isUnlimitedTraffic && next.remainingTrafficGB <= 0);

        if (isNowExpired) {
          final isConnected = ref.read(isConnectedProvider);
          if (isConnected) {
            debugPrint('[MainScreen] Subscription expired! Force stopping Xray.');
            ref.read(isConnectedProvider.notifier).state = false;
            if (Platform.isWindows) {
              try {
                _winDivertFFI.close();
                _wintunFFI.close();
              } catch (_) {}
            }
            XrayBridge.stopXray();
          }
        }
      }
    });

    // ── Expiration check ─────────────────────────────────────────────────────
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

          // ── Main content ──────────────────────────────────────────────────
          // If expired, shrink this area completely so HomeTab/Settings don't render behind the overlay
          SafeArea(
            child: isExpired
                ? const SizedBox.shrink()
                : (navIndex == 0 ? HomeTab(autoConnectVpn: widget.autoConnectVpn) : const SettingsTab()),
          ),

          // ── Bottom Nav (Glass) ────────────────────────────────────────────
          // Hide the bottom navigation bar completely if the account is expired
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
                  onTap: (index) =>
                      ref.read(navIndexProvider.notifier).state = index,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_filled),
                      label: 'خانه',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings),
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
                onDismiss: () =>
                    ref.read(isPromoDismissedProvider.notifier).state = true,
              ),
            ),

          // ── Notification Toasts (top-center) ─────────────────────────────
          if (activeNotifs.isNotEmpty && !isExpired)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
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
          if (isExpired)
            _ExpirationOverlay(onRefresh: _fetchStats),

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

/// Full-screen OLED frosted-glass maintenance blocker.
class _MaintenanceOverlay extends StatelessWidget {
  final String message;
  const _MaintenanceOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: Colors.black.withOpacity(0.88),
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
                  'در حال نگهداری',
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

/// Full-screen force-update blocker with download CTA.
class _ForceUpdateOverlay extends StatelessWidget {
  final String updateUrl;
  final String version;
  const _ForceUpdateOverlay(
      {required this.updateUrl, required this.version});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: Colors.black.withOpacity(0.88),
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
                  'برای ادامه استفاده لطفاً برنامه را به روز کنید.',
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
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

/// Full-screen solid-background expiration blocker.
/// [onRefresh] is wired to MainScreen._fetchStats so a manual check
/// always runs against live server data even while this overlay is shown.
class _ExpirationOverlay extends ConsumerStatefulWidget {
  final Future<void> Function() onRefresh;
  const _ExpirationOverlay({required this.onRefresh});

  @override
  ConsumerState<_ExpirationOverlay> createState() =>
      _ExpirationOverlayState();
}

class _ExpirationOverlayState extends ConsumerState<_ExpirationOverlay> {
  bool _isChecking = false;

  Future<void> _handleRefresh() async {
    setState(() => _isChecking = true);
    await widget.onRefresh();
    if (mounted) setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: AppTheme.oledDark,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Icon ──────────────────────────────────────────────────
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.errorRed.withOpacity(0.08),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.errorRed.withOpacity(0.45),
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

                // ── Message ───────────────────────────────────────────────
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
                  'لایسنس جدید خریداری کنید',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white60,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 44),

                // ── Action buttons ────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _ExpirationOutlineButton(
                        label: 'خروج از اکانت',
                        icon: Icons.logout_rounded,
                        onPressed: () async {
                          final prefs =
                              await SharedPreferences.getInstance();
                          await prefs.remove('license_key');

                          final isConnected =
                              ref.read(isConnectedProvider);
                          if (isConnected) {
                            if (Platform.isWindows) {
                              try {
                                _winDivertFFI.close();
                                _wintunFFI.close();
                              } catch (_) {}
                            }
                            XrayBridge.stopXray();
                            ref
                                .read(isConnectedProvider.notifier)
                                .state = false;
                          }

                          ref
                              .read(currentLicenseProvider.notifier)
                              .state = null;
                          ref
                              .read(subscriptionJsonProvider.notifier)
                              .state = null;
                          ref
                              .read(subscriptionStatsProvider.notifier)
                              .state = null;

                          if (context.mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ExpirationGradientButton(
                        label: 'خرید لایسنس',
                        icon: Icons.shopping_cart_checkout_rounded,
                        onPressed: () =>
                            UrlLauncherUtils.launchTelegramSupport(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Manual re-check button ────────────────────────────────
                // Lets the user verify a renewal immediately without waiting
                // for the next 3-minute timer tick.
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

/// Vibrant Blue/Cyan gradient button used inside expiration overlay.
class _ExpirationGradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _ExpirationGradientButton(
      {required this.label, required this.icon, required this.onPressed});

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
            color: const Color(0xFF00E5FF).withOpacity(0.35),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
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

/// Ghost/outline button used inside expiration overlay.
class _ExpirationOutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _ExpirationOutlineButton(
      {required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white24, width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

/// Dismissible promo banner floating above bottom nav.
class _PromoBanner extends StatelessWidget {
  final PromotionConfig promo;
  final VoidCallback onDismiss;
  const _PromoBanner({required this.promo, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.neonPurple.withOpacity(0.4),
              width: 1,
            ),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.local_offer_rounded,
                  color: AppTheme.neonPurple, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      promo.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: promo.discountCode));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.neonPurple.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  AppTheme.neonPurple.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.copy,
                                size: 12, color: AppTheme.neonCyan),
                            const SizedBox(width: 4),
                            Text(
                              promo.discountCode,
                              style: const TextStyle(
                                  color: AppTheme.neonCyan,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.white54, size: 20),
                onPressed: onDismiss,
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

/// Frosted-glass toast for a single in-app notification.
class _NotificationToast extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onDismiss;
  const _NotificationToast(
      {required this.notif, required this.onDismiss});

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
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.09),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _borderColor.withOpacity(0.55), width: 1),
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
                      child: Icon(Icons.close,
                          size: 16, color: Colors.white38),
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
  const HomeTab({super.key, this.autoConnectVpn = false});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  bool _isConnecting = false;
  bool _isMeasuringLatency = false;
  bool _latencyProbeError = false;

  final LatencyTester _latencyTester = LatencyTester();
  dynamic _currentNode;
  int _currentNodeLatencyMs = -1;
  int _bestNodeLatencyMs = -1;

  // ── DNS & Real-Delay Optimizer ────────────────────────────────────────────
  // These run silently on connect. They do NOT alter _bestNodeLatencyMs;
  // the UI badge always displays the fast TCP ping from _latencyTester.
  final DnsManager _dnsManager = DnsManager();
  final ConnectionOptimizer _connectionOptimizer = ConnectionOptimizer();
  OptimizedResult? _lastOptimizedResult;

  @override
  void dispose() {
    _latencyTester.stop();
    // Cancel any in-flight benchmarking to free the Xray isolate + ephemeral ports
    _connectionOptimizer.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final license = ref.read(currentLicenseProvider);

      // ── Early-return path: subscription JSON already cached ──────────────
      if (license == null || ref.read(subscriptionJsonProvider) != null) {
        for (int i = 0; i < 10; i++) {
          if (ref.read(remoteConfigProvider) != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
        _maybeStartLatencyTester();
        return;
      }

      // ── Normal path: fetch subscription JSON first ───────────────────────
      RemoteConfig? config;
      for (int i = 0; i < 10; i++) {
        config = ref.read(remoteConfigProvider);
        if (config != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (config != null) {
        final subService = SubscriptionService(
          config.apiEndpoints.baseJsonSubUrl,
          config.apiEndpoints.baseSubsStatsUrl.isNotEmpty
              ? config.apiEndpoints.baseSubsStatsUrl.first
              : '',
        );
        final sub = await subService.fetchSubscription(license);
        if (sub != null) {
          ref.read(subscriptionJsonProvider.notifier).state = sub;
        }
      }
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
        if (!isConnected) return;
        if (best.node == _currentNode) return;
        debugPrint('[LatencyTester] Switching to better node '
            '(${best.latencyMs}ms vs current ${_currentNodeLatencyMs}ms)');
        _connectNode(best.node);
      },
    );
  }

  /// One-shot latency probe triggered by tapping the latency badge.
  Future<void> _refreshLatency() async {
    if (_isMeasuringLatency) return;

    setState(() {
      _isMeasuringLatency = true;
      _latencyProbeError = false;
    });
    debugPrint('[_refreshLatency] tap received');

    try {
      final nodes = ref.read(subscriptionJsonProvider);
      debugPrint('[_refreshLatency] nodes: ${nodes?.length ?? 'null'}');

      if (nodes == null || nodes.isEmpty) {
        debugPrint('[_refreshLatency] no nodes available');
        if (mounted) setState(() => _latencyProbeError = true);
        return;
      }

      final oneShot = LatencyTester();
      final results = await oneShot.measureAll(nodes);
      oneShot.stop();

      debugPrint('[_refreshLatency] results: '
          '${results?.map((r) => '${r.latencyMs}ms').toList()}');

      final best = results?.firstOrNull;
      final isConnected = ref.read(isConnectedProvider);
      final isVpnMode = ref.read(isVpnModeProvider);

      if (mounted) {
        if (best != null && best.latencyMs > 0) {
          // Ignore FakeDNS local loopback pings (which always return 1-5ms)
          if (isConnected && isVpnMode && best.latencyMs <= 5) {
            debugPrint('[_refreshLatency] Ignored ${best.latencyMs}ms FakeDNS local loopback');
            setState(() => _isMeasuringLatency = false);
            return;
          }
          
          setState(() {
            _bestNodeLatencyMs = best.latencyMs;
            _latencyProbeError = false;
          });
        } else {
          setState(() => _latencyProbeError = true);
        }
      }
    } catch (e, st) {
      debugPrint('[_refreshLatency] failed: $e\n$st');
      if (mounted) setState(() => _latencyProbeError = true);
    } finally {
      if (mounted) setState(() => _isMeasuringLatency = false);
    }
  }

  // ── Connection logic ──────────────────────────────────────────────────────

  Future<void> _toggleConnection() async {
    final isConnected = ref.read(isConnectedProvider);
    final isVpnMode = ref.read(isVpnModeProvider);

    // ── DISCONNECT LOGIC ──
    if (isConnected) {
      debugPrint('[_toggleConnection] Disconnect initiated. Force stopping Xray.');
      
      // 1. Instantly update UI and Provider states
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

      // 2. Abort any in-flight DNS optimization (fire-and-forget — disconnect
      //    must be instant). The _cancelled flag is set synchronously inside
      //    cancel() so any probe Futures still running will short-circuit.
      // ignore: discarded_futures
      _connectionOptimizer.cancel();

      // 3. Safely tear down the isolate and VPN natively
      if (Platform.isWindows) {
        try {
          _winDivertFFI.close();
          _wintunFFI.close();
        } catch (_) {}
      }
      if (Platform.isAndroid && isVpnMode) {
        const vpnChannel = MethodChannel('candyconnect/vpn');
        await vpnChannel.invokeMethod('stopVpn').catchError((_) {});
      }
      await XrayBridge.stopXray();
      return;
    }

    // ── CONNECT LOGIC ──
    if (Platform.isWindows && isVpnMode) {
      if (!ElevationUtils.isElevated()) {
        ElevationUtils.relaunchElevated(['--auto-connect-vpn']);
        return;
      }
    }
    final subJsonList = ref.read(subscriptionJsonProvider);
    if (subJsonList == null || subJsonList.isEmpty) return;

    setState(() => _isConnecting = true);

    // ── Phase 1 (TCP): Race all nodes via TCP handshake ───────────────────
    // This is the FAST phase. It populates the UI badge and picks top-3 nodes
    // to feed into the real-delay benchmark. _bestNodeLatencyMs is set here
    // and is NEVER touched again — the UI always shows the TCP ping (Phase 5).
    NodeLatencyResult? bestResult;
    List<dynamic> top3Nodes = [];
    try {
      final oneShot = LatencyTester();
      final results = await oneShot.measureAll(subJsonList);
      oneShot.stop();
      bestResult = results?.firstOrNull;
      // Collect top-3 reachable nodes for variant generation
      top3Nodes = results
              ?.where((r) => r.isReachable)
              .take(3)
              .map((r) => r.node)
              .toList() ??
          [];
    } catch (_) {}

    // Publish TCP-ping result to UI immediately (Phase 5 — badge = TCP only)
    _currentNode = bestResult?.node ?? subJsonList.first;
    _currentNodeLatencyMs = bestResult?.latencyMs ?? -1;
    if (mounted && _currentNodeLatencyMs > 0) {
      setState(() => _bestNodeLatencyMs = _currentNodeLatencyMs);
    }

    // ── Phase 2 & 3 (Silent): Bootstrap DNS race + Real-delay benchmark ───
    // Runs entirely in the background — no setState, no UI changes.
    // The result is stored in _lastOptimizedResult for use in _connectNode().
    _lastOptimizedResult = null;
    final config = ref.read(remoteConfigProvider);
    if (config != null && top3Nodes.isNotEmpty) {
      try {
        _connectionOptimizer.reset(); // clear any prior cancellation flag

        // Phase 1: Race Bootstrap DNS candidates (TCP-to-port-53)
        final bootstrapDns = await _dnsManager.raceBestBootstrap(
          config.dnsRouting.bootstrapDnsPool,
        );

        // Phase 2: Cross-multiply top-3 nodes × remoteDnsPool
        final variants = _dnsManager.generateVariants(
          nodes: top3Nodes,
          remoteDnsPool: config.dnsRouting.remoteDnsPool,
        );

        // Phase 3: HTTP real-delay benchmark via temporary Xray isolate
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
        // Optimization is best-effort; a failure here is non-fatal.
        // _connectNode() will use the TCP winner and no custom DNS injection.
        debugPrint('[HomeTab] Silent DNS optimization failed: $e');
      }
    }

    // ── Phase 4: Connect with the best available node ─────────────────────
    // Prefer the real-delay winner; fall back to TCP winner if optimization
    // failed or was skipped.
    final nodeToConnect = (_lastOptimizedResult?.node ??
        (bestResult?.node ?? subJsonList.first)) as Map<String, dynamic>;
    _currentNode = nodeToConnect;

    await _connectNode(nodeToConnect);
  }

  /// Stops the current Xray instance (if any) and starts a new one on [rawNode].
  Future<void> _connectNode(dynamic rawNode) async {
    if (rawNode is! Map<String, dynamic>) return;

    final node = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(rawNode)) as Map<String, dynamic>,
    );

    _currentNode = rawNode;

    final isConnected = ref.read(isConnectedProvider);
    final isVpnMode = ref.read(isVpnModeProvider);
    
    if (isConnected) {
      // Instantly kill it if replacing an active connection
      ref.read(isConnectedProvider.notifier).state = false;
      if (Platform.isWindows) {
        try {
          _winDivertFFI.close();
          _wintunFFI.close();
        } catch (_) {}
      }
      await XrayBridge.stopXray();
    }

    if (Platform.isAndroid && isVpnMode) {
      const vpnChannel = MethodChannel('candyconnect/vpn');
      try {
        // 1. Await permission (halts until user decides via onActivityResult)
        final granted = await vpnChannel.invokeMethod<bool>('prepareVpn') ?? false;
        if (!granted) {
          if (mounted) setState(() => _isConnecting = false);
          return;
        }

        // 2. Fetch Proxy state from Riverpod
        final proxyMode = ref.read(perAppProxyModeProvider);
        final selectedApps = ref.read(selectedAppsProvider).toList();

        // 3. Start VPN and get fd
        final fd = await vpnChannel.invokeMethod<int>('startVpn', {
          'proxyMode': proxyMode,
          'selectedApps': selectedApps,
        }) ?? -1;

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

    // ── Phase 4: DNS Architecture Injection (all modes, all platforms) ───────
    // When the ConnectionOptimizer produced a result, we inject the two-tier
    // DNS architecture into the Xray config:
    //   • Bootstrap DNS → routed DIRECT (resolves proxy server IPs natively)
    //   • Remote DNS    → routed via PROXY (resolves blocked domains safely)
    // This block runs before the VPN-specific FakeDNS block below so that
    // the Windows VPN path can simply prepend "fakedns" to our server list.
    final optimized = _lastOptimizedResult;
    if (optimized != null) {
      // Ensure the dns key is a mutable map
      if (node['dns'] == null || node['dns'] is! Map) {
        node['dns'] = <String, dynamic>{};
      }
      final dnsMap = node['dns'] as Map<String, dynamic>;

      // Preserve any domain-specific DNS server overrides already in the config
      // (e.g. geolocation-based split-DNS rules from the subscription server).
      // Discard bare IP strings and plain 'localhost' — we replace them below.
      final preservedServers = <dynamic>[];
      if (dnsMap['servers'] is List) {
        for (final s in dnsMap['servers'] as List) {
          if (s is Map && s.containsKey('domains')) {
            preservedServers.add(s);
          }
        }
      }

      // Bootstrap DNS first — Xray queries this for direct-routed domains,
      // including the proxy server's own hostname.
      // Remote DNS second — used for all other (proxy-routed) lookups.
      dnsMap['servers'] = [
        optimized.bootstrapDns,
        optimized.remoteDns,
        'localhost', // final fallback for local LAN names
        ...preservedServers,
      ];

      // Routing: force Bootstrap DNS traffic to go Direct so Xray can resolve
      // the proxy server's IP without routing through the proxy itself.
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

      debugPrint(
        '[_connectNode] DNS architecture injected — '
        'bootstrap: ${optimized.bootstrapDns} (→ direct), '
        'remote: ${optimized.remoteDns} (→ proxy)',
      );
    }

    if (Platform.isWindows && isVpnMode) {
      // 1. Enable FakeDNS
      node['dns'] ??= {};
      node['dns']['servers'] = [
        "fakedns",
        ...(node['dns']['servers'] as List? ?? [])
      ];
      node['fakedns'] = [
        {"ipPool": "198.18.0.0/15", "poolSize": 65535}
      ];

      // 2. Inject Xray's native TUN inbound for Windows (replaces dokodemo-door & manual Wintun)
      final existingInbounds = List<dynamic>.from(node['inbounds'] as List? ?? []);
      for (var inbound in existingInbounds) {
        if (inbound is Map && inbound['port'] == 10808) {
          inbound['port'] = 10810; // Remap to avoid conflict if necessary
        }
      }

      node['inbounds'] = [
        {
          "tag": "tun-in",
          "protocol": "tun",
          "settings": {
            "name": "CandyConnectVPN",
            "desc": "CandyConnectVPN",
            "mtu": 1500,
            "gateway": ["10.0.0.1/16", "fc00::1/64"],
            "dns": optimized != null
                ? [optimized.remoteDns, optimized.remoteDns]
                : ["1.1.1.1", "8.8.8.8"],
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
      
      // 3. Inject FakeDNS Routing Rules
      final existingOutbounds = List<dynamic>.from(node['outbounds'] as List? ?? []);
      bool hasDnsOut = existingOutbounds.any((o) => o is Map && o['tag'] == 'dns-out');
      if (!hasDnsOut) {
        existingOutbounds.insert(0, {
          "tag": "dns-out",
          "protocol": "dns"
        });
        node['outbounds'] = existingOutbounds;
      }
      
      node['routing'] ??= {};
      final existingRules = List<dynamic>.from(node['routing']['rules'] as List? ?? []);
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

    // ── Universal Geo-Routing Asset Injection ──────────────────────────────
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
      final existingRules = List<dynamic>.from(routingMap['rules'] as List? ?? []);
      routingMap['rules'] = [
        {'type': 'field', 'ip':     ['geoip:private'], 'outboundTag': 'direct'},
        {'type': 'field', 'ip':     ['geoip:ir'],      'outboundTag': 'direct'},
        {'type': 'field', 'domain': ['geosite:ir'],    'outboundTag': 'direct'},
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
              errorMessage =
                  jsonMap['error']?.toString() ?? 'Unknown error';
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

      if (hasError) {
        ref.read(isConnectedProvider.notifier).state = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('خطا در اجرای هسته: $errorMessage'),
                backgroundColor: Colors.red),
          );
        }
      } else {
        ref.read(isConnectedProvider.notifier).state = true;
        if (mounted) setState(() => _isConnecting = false); // Stop the spinner instantly
        
        // After Xray starts, activate DNS leak protection in the background
        if (Platform.isWindows && isVpnMode) {
          Future.microtask(() async {
            int wintunIfIdx = -1;
            for (int i = 0; i < 10; i++) {
              await Future.delayed(const Duration(milliseconds: 500));
              wintunIfIdx = await _wintunFFI.getInterfaceIndex("CandyConnectVPN Tunnel");
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


  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(isConnectedProvider);
    final isVpnMode = ref.watch(isVpnModeProvider);
    final stats = ref.watch(subscriptionStatsProvider);

    return Column(
      children: [
        // ── Top Navbar toggles ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: GlassCard(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(isVpnModeProvider.notifier).state = true,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: isVpnMode
                            ? AppTheme.neonCyan.withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'VPN',
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
                    onTap: () =>
                        ref.read(isVpnModeProvider.notifier).state = false,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: !isVpnMode
                            ? AppTheme.neonPurple.withOpacity(0.2)
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

        // ── Connection Button ────────────────────────────────────────────
        GestureDetector(
          onTap: _isConnecting ? null : _toggleConnection,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.oledDark,
              border: Border.all(
                color: isConnected ? AppTheme.neonCyan : Colors.white24,
                width: 2,
              ),
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: AppTheme.neonCyan.withOpacity(0.5),
                        blurRadius: 50,
                        spreadRadius: 10,
                      )
                    ]
                  : [],
            ),
            alignment: Alignment.center,
            child: _isConnecting
                ? const CircularProgressIndicator(color: AppTheme.neonCyan)
                : Icon(
                    Icons.power_settings_new,
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
                  ? 'در حال اتصال...'
                  : 'برای اتصال ضربه بزنید'),
          style: TextStyle(
            color: isConnected ? AppTheme.neonCyan : Colors.white70,
            fontSize: 18,
          ),
        ),

        // ── Latency badge — only visible when connected ───────────────────
        if (isConnected)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
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
                                '$_bestNodeLatencyMs میلی ثانیه',
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
                                    'اتصال ضعیف — دوباره امتحان',
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
                                      size: 13, color: Colors.white60),
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

        // ── Premium Stats Progress Bars ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              // ── Traffic bar ─────────────────────────────────────────────
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

              // ── Days bar ─────────────────────────────────────────────────
              _PremiumStatBar(
                label: 'روزهای باقیمانده:',
                valueText: stats == null
                    ? '—'
                    : stats.isUnlimitedTime
                        ? 'نامحدود روز'
                        : stats.isExpired
                            ? 'منقضی شده'
                            : '${stats.daysRemaining} روز',
                isUnlimited: stats?.isUnlimitedTime ?? false,
                isDanger: stats != null &&
                    !stats.isUnlimitedTime &&
                    (stats.isExpired || stats.daysRemaining <= 5),
                fraction: stats == null
                    ? 0.0
                    : stats.isUnlimitedTime
                        ? 1.0
                        : stats.isExpired
                            ? 0.0
                            : (stats.daysRemaining / 30.0)
                                .clamp(0.0, 1.0),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Support Button ───────────────────────────────────────────────
        TextButton.icon(
          onPressed: () => UrlLauncherUtils.launchTelegramSupport(),
          icon: const Icon(Icons.support_agent, color: AppTheme.neonCyan),
          label: const Text('پشتیبانی',
              style: TextStyle(color: AppTheme.neonCyan)),
        ),

        const SizedBox(height: 120),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Premium Stat Bar Widget
// ════════════════════════════════════════════════════════════════════════════

/// Cyberpunk-style progress bar with dynamic Safe/Danger zone color shifting.
class _PremiumStatBar extends StatelessWidget {
  final String label;
  final String valueText;
  final bool isUnlimited;

  /// Fraction in [0.0, 1.0]; 1.0 when unlimited.
  final double fraction;

  /// Force the bar into danger (red) mode — e.g. expired or fully consumed.
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
        // ── Label row ─────────────────────────────────────────────────────
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
                fontWeight:
                    isUnlimited ? FontWeight.bold : FontWeight.w600,
                shadows: [
                  Shadow(
                    color: _barColor.withOpacity(0.8),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(valueText),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ── Bar track ─────────────────────────────────────────────────────
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
                    color: Colors.white.withOpacity(0.05),
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
                        color: _barColor.withOpacity(0.65),
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

/// A frosted-glass pill that wraps any child with a tap handler.
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
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: glowColor.withOpacity(0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withOpacity(0.20),
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