import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../windows/watchdog_manager.dart';
import 'xray_bridge.dart';

/// مدل حالت‌های شبکه در دسکتاپ
enum DesktopRoutingMode {
  proxyLocal,
  proxySystem,
  tunnelVpn,
}

class DesktopManager with WindowListener, TrayListener {
  static final DesktopManager _instance = DesktopManager._internal();
  factory DesktopManager() => _instance;
  DesktopManager._internal();

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool _isConnected = false;
  DesktopRoutingMode _currentMode = DesktopRoutingMode.tunnelVpn;

  /// کالبک‌های ارتباطی برای اتصال مستقیم منوی Tray به وضعیت Riverpod در MainScreen / HomeTab
  VoidCallback? onToggleConnectionRequested;
  void Function(DesktopRoutingMode mode)? onModeChanged;
  Future<void> Function()? onBeforeExitCleanup;

  Future<void> init() async {
    if (!isDesktop) return;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    // جلوگیری از بسته شدن ناگهانی پروسه هنگام زدن دکمه ضربدر پنجره
    await windowManager.setPreventClose(true);

    // مخفی کردن نوار عنوان پیش‌فرض سیستم‌عامل
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    const WindowOptions windowOptions = WindowOptions(
      size: Size(400, 800),
      minimumSize: Size(360, 700),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'CandyConnect',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await _loadInitialModeFromPrefs();
    await _initTray();
  }

  Future<void> _loadInitialModeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sysProxy = prefs.getBool('desktop_system_proxy') ?? false;
      final vpnMode = prefs.getBool('desktop_vpn_mode') ?? true;
      if (vpnMode) {
        _currentMode = DesktopRoutingMode.tunnelVpn;
      } else if (sysProxy) {
        _currentMode = DesktopRoutingMode.proxySystem;
      } else {
        _currentMode = DesktopRoutingMode.proxyLocal;
      }
    } catch (_) {}
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    await updateTrayIcon(false);
  }

  /// بروزرسانی آیکون، Tooltip و تیک‌های منوی راست‌کلیک Tray بر اساس وضعیت لحظه‌ای
  Future<void> updateTrayIcon(
    bool isConnected, {
    DesktopRoutingMode? mode,
  }) async {
    if (!isDesktop) return;
    _isConnected = isConnected;
    if (mode != null) {
      _currentMode = mode;
    }

    try {
      final String iconPath = Platform.isWindows
          ? (isConnected
              ? 'assets/icons/tray_icon.ico'
              : 'assets/icons/tray_icon_off.ico')
          : (isConnected
              ? 'assets/icons/tray_icon.png'
              : 'assets/icons/tray_icon_off.png');

      await trayManager.setIcon(iconPath);

      if (!Platform.isLinux) {
        await trayManager.setToolTip(
          isConnected ? 'CandyConnect — متصل' : 'CandyConnect — قطع',
        );
      }

      await _rebuildTrayMenu();

      // اعمال یا پاکسازی خودکار پروکسی سیستم در صورت تغییر وضعیت اتصال
      if (isConnected && _currentMode == DesktopRoutingMode.proxySystem) {
        await applySystemProxy(enable: true);
      } else if (!isConnected) {
        await applySystemProxy(enable: false);
      }
    } catch (e) {
      debugPrint('Failed to update tray icon/menu: $e');
    }
  }

  Future<void> _rebuildTrayMenu() async {
    String checkMark(DesktopRoutingMode target) =>
        _currentMode == target ? '✓ ' : '   ';

    final List<MenuItem> items = [
      MenuItem(
        key: 'show_window',
        label: 'نمایش پنجره کندی‌کانکت',
      ),
      MenuItem(
        key: 'toggle_connect',
        label: _isConnected
            ? '🟢 وضعیت: متصل (قطع اتصال)'
            : '⚪ وضعیت: قطع (اتصال سریع)',
      ),
      MenuItem.separator(),
      MenuItem.submenu(
        key: 'proxy',
        label: 'حالت پروکسی',
        submenu: Menu(
          items: [
            MenuItem(
              key: 'proxy_local',
              label:
                  '${checkMark(DesktopRoutingMode.proxyLocal)}پروکسی لوکال (127.0.0.1:10808)',
            ),
            MenuItem(
              key: 'proxy_system',
              label:
                  '${checkMark(DesktopRoutingMode.proxySystem)}پروکسی کردن کل سیستم',
            ),
          ],
        ),
      ),
      MenuItem(
        key: 'tunnel',
        label:
            '${checkMark(DesktopRoutingMode.tunnelVpn)}تونل کردن کل سیستم (VPN)',
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit',
        label: 'خروج کامل از برنامه',
      ),
    ];

    await trayManager.setContextMenu(Menu(items: items));
  }

  /// تنظیم یا غیرفعال‌سازی پروکسی کل سیستم‌عامل در ویندوز، مک و لینوکس
  Future<void> applySystemProxy({
    required bool enable,
    String host = '127.0.0.1',
    int port = 10808,
  }) async {
    if (!isDesktop) return;
    try {
      if (Platform.isWindows) {
        const regKey =
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        if (enable) {
          await Process.run('reg', [
            'add',
            regKey,
            '/v',
            'ProxyEnable',
            '/t',
            'REG_DWORD',
            '/d',
            '1',
            '/f',
          ]);
          await Process.run('reg', [
            'add',
            regKey,
            '/v',
            'ProxyServer',
            '/t',
            'REG_SZ',
            '/d',
            '$host:$port',
            '/f',
          ]);
        } else {
          await Process.run('reg', [
            'add',
            regKey,
            '/v',
            'ProxyEnable',
            '/t',
            'REG_DWORD',
            '/d',
            '0',
            '/f',
          ]);
        }
      } else if (Platform.isLinux) {
        if (enable) {
          await Process.run(
              'gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'manual']);
          await Process.run('gsettings',
              ['set', 'org.gnome.system.proxy.http', 'host', host]);
          await Process.run('gsettings',
              ['set', 'org.gnome.system.proxy.http', 'port', '$port']);
          await Process.run('gsettings',
              ['set', 'org.gnome.system.proxy.https', 'host', host]);
          await Process.run('gsettings',
              ['set', 'org.gnome.system.proxy.https', 'port', '$port']);
          await Process.run('gsettings',
              ['set', 'org.gnome.system.proxy.socks', 'host', host]);
          await Process.run('gsettings',
              ['set', 'org.gnome.system.proxy.socks', 'port', '$port']);
        } else {
          await Process.run(
              'gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'none']);
        }
      } else if (Platform.isMacOS) {
        for (final service in ['Wi-Fi', 'Ethernet']) {
          if (enable) {
            await Process.run('networksetup',
                ['-setsocksfirewallproxy', service, host, '$port']);
            await Process.run(
                'networksetup', ['-setsocksfirewallproxystate', service, 'on']);
          } else {
            await Process.run('networksetup',
                ['-setsocksfirewallproxystate', service, 'off']);
          }
        }
      }
    } catch (e) {
      debugPrint('[DesktopManager] Failed to configure OS system proxy: $e');
    }
  }

  Future<void> _bringWindowToFront() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() async {
    final bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconMouseDown() {
    _bringWindowToFront();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final prefs = await SharedPreferences.getInstance();

    switch (menuItem.key) {
      case 'show_window':
        await _bringWindowToFront();
        break;

      case 'toggle_connect':
        await _bringWindowToFront();
        onToggleConnectionRequested?.call();
        break;

      case 'proxy_local':
        _currentMode = DesktopRoutingMode.proxyLocal;
        await prefs.setBool('desktop_system_proxy', false);
        await prefs.setBool('desktop_vpn_mode', false);
        await applySystemProxy(enable: false);
        await _rebuildTrayMenu();
        onModeChanged?.call(_currentMode);
        break;

      case 'proxy_system':
        _currentMode = DesktopRoutingMode.proxySystem;
        await prefs.setBool('desktop_system_proxy', true);
        await prefs.setBool('desktop_vpn_mode', false);
        if (_isConnected) {
          await applySystemProxy(enable: true);
        }
        await _rebuildTrayMenu();
        onModeChanged?.call(_currentMode);
        break;

      case 'tunnel':
        _currentMode = DesktopRoutingMode.tunnelVpn;
        await prefs.setBool('desktop_system_proxy', false);
        await prefs.setBool('desktop_vpn_mode', true);
        await applySystemProxy(enable: false);
        await _rebuildTrayMenu();
        onModeChanged?.call(_currentMode);
        break;

      case 'exit':
        await hardExit();
        break;
    }
  }

  /// خروج ایمن و کامل بدون باقی گذاشتن پروکسی سیستم، کارت شبکه مجازی یا واچ‌داگ فعال
  Future<void> hardExit() async {
    try {
      // ۱. اعلام خروج مجاز به واچ‌داگ ویندوز پیش از بستن منابع
      if (Platform.isWindows) {
        WatchdogManager().signalCleanExit();
      }

      // ۲. مخفی‌سازی آنی پنجره برای حس سرعت بالا در سمت کاربر
      await windowManager.hide();

      // ۳. خاموش کردن پروکسی سیستم‌عامل تا اینترنت مرورگر کاربر قطع نماند
      await applySystemProxy(enable: false);

      // ۴. اجرای کالبک پاکسازی درایورهای Wintun/WinDivert در صورت ثبت شدن
      if (onBeforeExitCleanup != null) {
        await onBeforeExitCleanup!();
      }

      // ۵. توقف کامل ایزوله Xray و حذف فایل‌های کانفیگ موقت
      await XrayBridge.stopXray();

      // ۶. خاتمه دادن به پروسه واچ‌داگ و تخریب پنجره
      if (Platform.isWindows) {
        WatchdogManager().terminateWatchdog();
      }
      await windowManager.destroy();
    } catch (e) {
      debugPrint('[DesktopManager] Error during hardExit: $e');
    } finally {
      exit(0);
    }
  }
}