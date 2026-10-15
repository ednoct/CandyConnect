import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_apps/device_apps.dart';

import '../providers/app_providers.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import '../core/desktop_manager.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final selectedAppsCount = ref.watch(selectedAppsProvider).length;
    final perAppMode = ref.watch(perAppProxyModeProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      physics: const BouncingScrollPhysics(),
      children: [
        Text(
          'تنظیمات',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 20),

        if (Platform.isAndroid) ...[
          _buildSettingsItem(
            context,
            icon: Icons.apps_rounded,
            title: 'پروکسی برای هر برنامه',
            subtitle: perAppMode == 0
                ? 'فعال برای تمام برنامه‌ها'
                : '$selectedAppsCount برنامه انتخاب شده',
            onTap: () {
              HapticFeedback.lightImpact();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PerAppProxyModal(),
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        _buildSettingsItem(
          context,
          icon: Icons.settings_ethernet_rounded,
          title: 'تنظیمات پروکسی و شبکه',
          subtitle: 'پورت، شبکه محلی (LAN) و حالت تونل',
          onTap: () {
            HapticFeedback.lightImpact();
            _showProxySettings(context, isDesktop);
          },
        ),

        const SizedBox(height: 16),

        _buildSettingsItem(
          context,
          icon: Icons.logout_rounded,
          title: 'خروج از اکانت',
          subtitle: 'حذف لایسنس فعلی از این دستگاه',
          color: AppTheme.errorRed,
          onTap: () {
            HapticFeedback.mediumImpact();
            _confirmLogout(context, ref);
          },
        ),
      ],
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? AppTheme.neonCyan;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        height: subtitle != null ? 78 : 70,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: effectiveColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: color ?? Colors.white,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white38,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showProxySettings(BuildContext context, bool isDesktop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ProxySettingsModal(isDesktop: isDesktop),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Text(
          'خروج از حساب کاربری',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'آیا مطمئن هستید که می‌خواهید از اشتراک خود خارج شوید؟ در صورت اتصال، VPN شما قطع خواهد شد.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج از اکانت'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('license_key');

    if (DesktopManager().isDesktop) {
      await DesktopManager().applySystemProxy(enable: false);
    }

    final isConnected = ref.read(isConnectedProvider);
    if (isConnected) {
      // توقف قطعی و ایمن تمام لایه‌های تونل، درایورهای کرنل (Wintun/WinDivert)، پروکسی سیستم و هسته
      await safeStopAllTunnels();
      ref.read(isConnectedProvider.notifier).set(false);
    }

    // ── Bug Fix: پاکسازی سراسری تمام استیت‌های وابسته ──────────────────────────
    ref.read(currentLicenseProvider.notifier).set(null);
    ref.read(subscriptionJsonProvider.notifier).set(null);
    ref.read(subscriptionStatsProvider.notifier).set(null);
    ref.read(navIndexProvider.notifier).set(0);
    ref.read(isPromoDismissedProvider.notifier).set(false);

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Proxy Settings Modal
// ════════════════════════════════════════════════════════════════════════════

class _ProxySettingsModal extends ConsumerStatefulWidget {
  final bool isDesktop;
  const _ProxySettingsModal({required this.isDesktop});

  @override
  ConsumerState<_ProxySettingsModal> createState() =>
      _ProxySettingsModalState();
}

class _ProxySettingsModalState extends ConsumerState<_ProxySettingsModal> {
  String _localIp = 'در حال دریافت...';
  bool _isValidIp = false;

  @override
  void initState() {
    super.initState();
    _fetchLocalIpSmart();
  }

  /// تشخیص هوشمند آی‌پی واقعی شبکه محلی (LAN) و فیلتر کردن آداپتورهای مجازی VPN/TUN/WSL
  Future<void> _fetchLocalIpSmart() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final ignoredKeywords = [
        'tun',
        'tap',
        'ppp',
        'wintun',
        'candy',
        'xray',
        'vethernet',
        'wsl',
        'docker',
        'vmware',
        'vbox',
        'rmnet',
        'ccmni',
      ];

      String? fallbackIp;

      for (final interface in interfaces) {
        final nameLower = interface.name.toLowerCase();
        final isVirtual = ignoredKeywords.any((k) => nameLower.contains(k));
        if (isVirtual) continue;

        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;

          // اولویت اول با رنج استاندارد مودم‌ها و روترهای خانگی
          if (ip.startsWith('192.168.')) {
            if (mounted) {
              setState(() {
                _localIp = ip;
                _isValidIp = true;
              });
            }
            return;
          }
          fallbackIp ??= ip;
        }
      }

      if (mounted) {
        setState(() {
          _localIp = fallbackIp ?? 'یافت نشد (به Wi-Fi/LAN متصل نیستید)';
          _isValidIp = fallbackIp != null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localIp = 'خطا در دریافت آی‌پی شبکه';
          _isValidIp = false;
        });
      }
    }
  }

  void _notifyReconnectIfActive() {
    final isConnected = ref.read(isConnectedProvider);
    if (isConnected && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'برای اعمال تغییرات شبکه، لطفاً یک‌بار اتصال را قطع و مجدداً وصل کنید.',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          backgroundColor: const Color(0xFF1A1A2E),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.neonCyan, width: 1),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLanSharing = ref.watch(isLanSharingProvider);
    final isVpnMode = ref.watch(isVpnModeProvider);
    final isSystemProxy = ref.watch(isSystemProxyProvider);

    return GlassCard(
      height: MediaQuery.of(context).size.height * 0.72,
      borderRadius: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'تنظیمات پروکسی و شبکه',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.neonCyan),
                tooltip: 'بروزرسانی آی‌پی شبکه',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _localIp = 'در حال دریافت...';
                    _isValidIp = false;
                  });
                  _fetchLocalIpSmart();
                },
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 16),

          // ── Scrollable Body (جلوگیری از RenderFlex Overflow) ─────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const _CopyableTextField(
                    label: 'آی‌پی اتصال محلی (Loopback)',
                    value: '127.0.0.1',
                  ),
                  const SizedBox(height: 12),
                  const _CopyableTextField(
                    label: 'پورت اتصال (SOCKS / HTTP)',
                    value: '10808',
                  ),
                  const SizedBox(height: 12),

                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text(
                      'اشتراک‌گذاری VPN در شبکه محلی (Allow LAN)',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'امکان اتصال سایر دستگاه‌های متصل به مودم شما',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: isLanSharing,
                    activeThumbColor: AppTheme.neonCyan,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      ref.read(isLanSharingProvider.notifier).set(val);
                      _notifyReconnectIfActive();
                    },
                  ),
                  const SizedBox(height: 8),
                  _CopyableTextField(
                    label: 'آی‌پی دستگاه در شبکه محلی (LAN IP)',
                    value: _localIp,
                    canCopy: _isValidIp,
                  ),

                  if (widget.isDesktop) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: const Text(
                        'پروکسی کردن کل سیستم (System Proxy)',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'تنظیم خودکار پروکسی مرورگرها و سیستم‌عامل',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      value: isSystemProxy,
                      activeThumbColor: AppTheme.neonCyan,
                      onChanged: (val) async {
                        HapticFeedback.selectionClick();
                        ref.read(isSystemProxyProvider.notifier).set(val);
                        if (val) {
                          ref.read(isVpnModeProvider.notifier).set(false);
                        }
                        final isConnected = ref.read(isConnectedProvider);
                        await DesktopManager().applySystemProxy(
                          enable: val && isConnected,
                        );
                        await DesktopManager().updateTrayIcon(
                          isConnected,
                          mode: val
                              ? DesktopRoutingMode.proxySystem
                              : (ref.read(isVpnModeProvider)
                                  ? DesktopRoutingMode.tunnelVpn
                                  : DesktopRoutingMode.proxyLocal),
                        );
                        _notifyReconnectIfActive();
                      },
                    ),
                  ],

                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text(
                      'تونل کردن کل دستگاه (TUN / VPN Mode)',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'عبور تمام ترافیک برنامه‌ها و بازی‌ها از کارت شبکه مجازی',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: isVpnMode,
                    activeThumbColor: AppTheme.neonCyan,
                    onChanged: (val) async {
                      HapticFeedback.selectionClick();
                      ref.read(isVpnModeProvider.notifier).set(val);
                      if (widget.isDesktop) {
                        if (val) {
                          ref.read(isSystemProxyProvider.notifier).set(false);
                          await DesktopManager().applySystemProxy(enable: false);
                        }
                        await DesktopManager().updateTrayIcon(
                          ref.read(isConnectedProvider),
                          mode: val
                              ? DesktopRoutingMode.tunnelVpn
                              : (ref.read(isSystemProxyProvider)
                                  ? DesktopRoutingMode.proxySystem
                                  : DesktopRoutingMode.proxyLocal),
                        );
                      }
                      _notifyReconnectIfActive();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Copyable TextField (بدون نشت حافظه کنترلر)
// ════════════════════════════════════════════════════════════════════════════

class _CopyableTextField extends StatefulWidget {
  final String label;
  final String value;
  final bool canCopy;

  const _CopyableTextField({
    required this.label,
    required this.value,
    this.canCopy = true,
  });

  @override
  State<_CopyableTextField> createState() => _CopyableTextFieldState();
}

class _CopyableTextFieldState extends State<_CopyableTextField> {
  late final TextEditingController _controller;
  bool _isCopied = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _CopyableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _copyText() {
    if (!widget.canCopy) return;
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: widget.value));
    setState(() => _isCopied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _isCopied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      controller: _controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: Colors.white70),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        suffixIcon: !widget.canCopy
            ? const SizedBox.shrink()
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isCopied
                    ? Container(
                        key: const ValueKey('copied'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 4.0),
                        margin: const EdgeInsets.symmetric(horizontal: 8.0),
                        decoration: BoxDecoration(
                          color: AppTheme.neonCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check,
                                color: AppTheme.neonCyan, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'کپی شد!',
                              style: TextStyle(
                                color: AppTheme.neonCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : IconButton(
                        key: const ValueKey('copy'),
                        icon: const Icon(Icons.copy_rounded,
                            color: AppTheme.neonCyan),
                        onPressed: _copyText,
                      ),
              ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Per-App Proxy Modal (با قابلیت جستجو، سنجاق منتخبان و کش آیکون)
// ════════════════════════════════════════════════════════════════════════════

class PerAppProxyModal extends ConsumerStatefulWidget {
  const PerAppProxyModal({super.key});

  @override
  ConsumerState<PerAppProxyModal> createState() => _PerAppProxyModalState();
}

class _PerAppProxyModalState extends ConsumerState<PerAppProxyModal> {
  static const List<String> _modeLabels = [
    'پروکسی کردن تمام برنامه‌ها',
    'فقط برنامه‌های انتخاب‌شده',
    'استثنا کردن برنامه‌های انتخاب‌شده ',
  ];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Future<List<Application>>? _appsFuture;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadApps() {
    final showSystem = ref.read(showSystemAppsProvider);
    final currentlySelected = ref.read(selectedAppsProvider);

    setState(() {
      _appsFuture = DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: showSystem,
        onlyAppsWithLaunchIntent: !showSystem,
      ).then((apps) {
        // مرتب‌سازی هوشمند: ابتدا برنامه‌های تیک‌خورده، سپس بر اساس حروف الفبا
        apps.sort((a, b) {
          final aSel = currentlySelected.contains(a.packageName);
          final bSel = currentlySelected.contains(b.packageName);
          if (aSel && !bSel) return -1;
          if (!aSel && bSel) return 1;
          return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        });
        return apps;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final proxyMode = ref.watch(perAppProxyModeProvider);
    final showSystem = ref.watch(showSystemAppsProvider);
    final selectedApps = ref.watch(selectedAppsProvider);
    final isListDisabled = proxyMode == 0;

    final modalHeight = MediaQuery.of(context).size.height * 0.88;

    return GlassCard(
      height: modalHeight,
      borderRadius: 30,
      child: Column(
        children: [
          // ── Drag handle ─────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // ── Header: title & selected badge ──────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'پروکسی برای هر برنامه',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (selectedApps.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.neonCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.neonCyan.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${selectedApps.length} انتخاب شده',
                      style: const TextStyle(
                        color: AppTheme.neonCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Controls row: Mode dropdown + System-apps toggle ────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _ModeDropdown(
                    value: proxyMode,
                    labels: _modeLabels,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      ref.read(perAppProxyModeProvider.notifier).set(val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(showSystemAppsProvider.notifier).set(
                        !showSystem);
                    _loadApps();
                  },
                  icon: Icon(
                    showSystem
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.neonCyan,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  label: Text(
                    showSystem ? 'حذف سیستمی‌ها' : 'برنامه‌های سیستمی',
                  ),
                ),
              ],
            ),
          ),

          // ── Search Bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextField(
              controller: _searchController,
              enabled: !isListDisabled,
              onChanged: (val) {
                setState(() => _searchQuery = val.trim().toLowerCase());
              },
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'جستجوی نام برنامه یا پکیج (مثلاً Telegram)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.neonCyan, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            color: Colors.white54, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── App list ────────────────────────────────────────────────────
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isListDisabled ? 0.45 : 1.0,
              child: IgnorePointer(
                ignoring: isListDisabled,
                child: FutureBuilder<List<Application>>(
                  future: _appsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.neonCyan),
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Center(
                        child: Text(
                          'خطا در بارگذاری برنامه‌ها',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    final allApps = snapshot.data!;
                    final filteredApps = _searchQuery.isEmpty
                        ? allApps
                        : allApps.where((app) {
                            return app.appName
                                    .toLowerCase()
                                    .contains(_searchQuery) ||
                                app.packageName
                                    .toLowerCase()
                                    .contains(_searchQuery);
                          }).toList();

                    if (filteredApps.isEmpty) {
                      return const Center(
                        child: Text(
                          'هیچ برنامه‌ای با این مشخصات یافت نشد',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      physics: const BouncingScrollPhysics(),
                      itemCount: filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = filteredApps[index];
                        final isSelected =
                            selectedApps.contains(app.packageName);
                        final hasIcon = app is ApplicationWithIcon;

                        return _AppListTile(
                          key: ValueKey(app.packageName),
                          app: app,
                          hasIcon: hasIcon,
                          isSelected: isSelected,
                          onChanged: (_) {
                            HapticFeedback.selectionClick();
                            ref
                                .read(selectedAppsProvider.notifier)
                                .toggle(app.packageName);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode Dropdown ─────────────────────────────────────────────────────────────

class _ModeDropdown extends StatelessWidget {
  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  const _ModeDropdown({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          dropdownColor: const Color(0xFF1A1A2E),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppTheme.neonCyan,
            size: 18,
          ),
          isExpanded: true,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFamily: 'Vazirmatn',
          ),
          items: List.generate(labels.length, (i) {
            return DropdownMenuItem<int>(
              value: i,
              child: Text(
                labels[i],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: i == value ? AppTheme.neonCyan : Colors.white70,
                  fontSize: 12,
                ),
              ),
            );
          }),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ── App List Tile (بهینه‌سازی شده با cacheWidth برای رندر سریع آیکون) ───────────

class _AppListTile extends StatelessWidget {
  final Application app;
  final bool hasIcon;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _AppListTile({
    super.key,
    required this.app,
    required this.hasIcon,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: isSelected,
      onChanged: onChanged,
      activeColor: AppTheme.neonCyan,
      checkColor: Colors.black,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      title: Text(
        app.appName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        app.packageName,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
        overflow: TextOverflow.ellipsis,
      ),
      secondary: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: hasIcon
            ? Image.memory(
                (app as ApplicationWithIcon).icon,
                width: 40,
                height: 40,
                cacheWidth: 120,
                cacheHeight: 120,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : Container(
                width: 40,
                height: 40,
                color: Colors.white12,
                child: const Icon(Icons.android, color: Colors.white38),
              ),
      ),
    );
  }
}