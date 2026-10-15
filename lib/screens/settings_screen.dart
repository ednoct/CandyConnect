import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/xray_bridge.dart';
import 'package:device_apps/device_apps.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        Text(
          'تنظیمات',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        
        if (Platform.isAndroid) ...[
          _buildSettingsItem(
            context,
            icon: Icons.apps,
            title: 'پروکسی برای هر برنامه',
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PerAppProxyModal(),
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        _buildSettingsItem(
          context,
          icon: Icons.settings_ethernet,
          title: 'تنظیمات پروکسی',
          onTap: () {
            _showProxySettings(context, isDesktop);
          },
        ),
        
        const SizedBox(height: 16),
        
        _buildSettingsItem(
          context,
          icon: Icons.logout,
          title: 'خروج از اکانت',
          color: AppTheme.errorRed,
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('license_key');
            
            final isConnected = ref.read(isConnectedProvider);
            if (isConnected) {
              XrayBridge.invoke(jsonEncode({
                "apiVersion": 1,
                "method": "stopXray",
                "payload": {}
              }));
              ref.read(isConnectedProvider.notifier).state = false;
            }
            
            ref.read(currentLicenseProvider.notifier).state = null;
            ref.read(subscriptionJsonProvider.notifier).state = null;
            
            if (context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        height: 70,
        child: Row(
          children: [
            Icon(icon, color: color ?? AppTheme.neonCyan),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(fontSize: 16, color: color ?? Colors.white),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: Colors.white54),
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
      builder: (context) => _ProxySettingsModal(isDesktop: isDesktop),
    );
  }
}

class _ProxySettingsModal extends ConsumerStatefulWidget {
  final bool isDesktop;
  const _ProxySettingsModal({required this.isDesktop});

  @override
  ConsumerState<_ProxySettingsModal> createState() => _ProxySettingsModalState();
}

class _ProxySettingsModalState extends ConsumerState<_ProxySettingsModal> {
  String _localIp = 'در حال دریافت...';

  @override
  void initState() {
    super.initState();
    _fetchLocalIp();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('127.')) {
            if (mounted) {
              setState(() {
                _localIp = addr.address;
              });
            }
            return;
          }
        }
      }
      if (mounted) {
        setState(() {
          _localIp = 'یافت نشد';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localIp = 'خطا در دریافت';
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final isLanSharing = ref.watch(isLanSharingProvider);

    return GlassCard(
      height: MediaQuery.of(context).size.height * 0.7,
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
          const SizedBox(height: 20),
          const Text('تنظیمات پروکسی', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          _CopyableTextField(label: 'آیپی اتصال', value: '127.0.0.1'),
          const SizedBox(height: 12),
          _CopyableTextField(label: 'پورت اتصال', value: '10808'),
          const SizedBox(height: 12),
          
          SwitchListTile(
            title: const Text('اشتراک گذاری vpn در شبکه محلی'),
            value: isLanSharing,
            activeColor: AppTheme.neonCyan,
            onChanged: (val) {
              ref.read(isLanSharingProvider.notifier).state = val;
            },
          ),
          const SizedBox(height: 12),
          _CopyableTextField(label: 'آیپی اتصال در شبکه محلی', value: _localIp),
          
          if (widget.isDesktop) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('پروکسی کردن کل سیستم'),
              value: false,
              activeColor: AppTheme.neonCyan,
              onChanged: (val) {},
            ),
          ],
          
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('تونل کردن کل دستگاه'),
            value: ref.watch(isVpnModeProvider),
            activeColor: AppTheme.neonCyan,
            onChanged: (val) {
              ref.read(isVpnModeProvider.notifier).state = val;
            },
          ),
        ],
      ),
    );
  }
}

class _CopyableTextField extends StatefulWidget {
  final String label;
  final String value;
  
  const _CopyableTextField({required this.label, required this.value});

  @override
  State<_CopyableTextField> createState() => _CopyableTextFieldState();
}

class _CopyableTextFieldState extends State<_CopyableTextField> {
  bool _isCopied = false;

  void _copyText() {
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
      controller: TextEditingController(text: widget.value),
      decoration: InputDecoration(
        labelText: widget.label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isCopied
              ? Container(
                  key: const ValueKey('copied'),
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  margin: const EdgeInsets.only(right: 8.0, left: 8.0),
                  decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, color: AppTheme.neonCyan, size: 16),
                      const SizedBox(width: 4),
                      const Text(
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
                  icon: const Icon(Icons.copy, color: AppTheme.neonCyan),
                  onPressed: _copyText,
                ),
        ),
      ),
    );
  }
}


// ════════════════════════════════════════════════════════════════════════════
//  Per-App Proxy Modal
// ════════════════════════════════════════════════════════════════════════════

class PerAppProxyModal extends ConsumerStatefulWidget {
  const PerAppProxyModal({super.key});

  @override
  ConsumerState<PerAppProxyModal> createState() => _PerAppProxyModalState();
}

class _PerAppProxyModalState extends ConsumerState<PerAppProxyModal> {
  static const List<String> _modeLabels = [
    'پروکسی کردن تمام برنامه ها',
    'فقط برنامه های انتخاب شده پروکسی شوند',
    'برنامه های انتخاب شده پروکسی نشوند',
  ];

  Future<List<Application>>? _appsFuture;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  void _loadApps() {
    final showSystem = ref.read(showSystemAppsProvider);
    setState(() {
      _appsFuture = DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: showSystem,
        onlyAppsWithLaunchIntent: !showSystem,
      ).then((apps) {
        apps.sort((a, b) => a.appName.compareTo(b.appName));
        return apps;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final proxyMode = ref.watch(perAppProxyModeProvider);
    final showSystem = ref.watch(showSystemAppsProvider);
    final selectedApps = ref.watch(selectedAppsProvider);

    final modalHeight = MediaQuery.of(context).size.height * 0.85;

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
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // ── Header: title ────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'پروکسی برای هر برنامه',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          // ── Controls row: Mode dropdown + System-apps toggle ────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Mode dropdown (RTL start)
                Expanded(
                  child: _ModeDropdown(
                    value: proxyMode,
                    labels: _modeLabels,
                    onChanged: (val) {
                      ref.read(perAppProxyModeProvider.notifier).state = val;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // System-apps toggle (RTL end)
                TextButton(
                  onPressed: () {
                    ref.read(showSystemAppsProvider.notifier).state = !showSystem;
                    _loadApps();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.neonCyan,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(
                    showSystem
                        ? 'پنهان کردن برنامه های سیستمی'
                        : 'نمایش برنامه های سیستمی',
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── App list ────────────────────────────────────────────────────
          Expanded(
            child: FutureBuilder<List<Application>>(
              future: _appsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.neonCyan),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Text(
                      'خطا در بارگذاری برنامه ها',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                final apps = snapshot.data!;
                if (apps.isEmpty) {
                  return const Center(
                    child: Text(
                      'هیچ برنامه ای یافت نشد',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    final isSelected = selectedApps.contains(app.packageName);
                    final hasIcon = app is ApplicationWithIcon;

                    return _AppListTile(
                      app: app,
                      hasIcon: hasIcon,
                      isSelected: isSelected,
                      onChanged: (_) {
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
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          dropdownColor: const Color(0xFF1A1A2E),
          icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.neonCyan, size: 18),
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

// ── App List Tile (extracted to avoid rebuilds) ───────────────────────────────

class _AppListTile extends StatelessWidget {
  final Application app;
  final bool hasIcon;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _AppListTile({
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
