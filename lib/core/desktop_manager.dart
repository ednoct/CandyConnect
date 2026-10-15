import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'xray_bridge.dart';

class DesktopManager with WindowListener, TrayListener {
  static final DesktopManager _instance = DesktopManager._internal();
  factory DesktopManager() => _instance;
  DesktopManager._internal();

  bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> init() async {
    if (!isDesktop) return;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    
    // Intercept OS Close so the OS doesn't kill the Dart process.
    await windowManager.setPreventClose(true);

    // Hide the native title bar as per architectural requirement
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 800),
      minimumSize: Size(350, 700),
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

    await _initTray();
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    
    // Using default flutter icon for tray based on platform
    String iconPath = Platform.isWindows ? 'assets/icons/tray_icon_off.ico' : 'assets/icons/tray_icon_off.png';
    await trayManager.setIcon(iconPath);
    
    List<MenuItem> items = [
      MenuItem.submenu(
        key: 'proxy',
        label: 'پروکسی',
        submenu: Menu(
          items: [
            MenuItem(key: 'proxy_local', label: 'پروکسی لوکال'),
            MenuItem(key: 'proxy_system', label: 'پروکسی کردن کل سیستم'),
          ],
        ),
      ),
      MenuItem(
        key: 'tunnel',
        label: 'تونل کردن کل سیستم',
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit',
        label: 'خروج از برنامه',
      ),
    ];
    await trayManager.setContextMenu(Menu(items: items));
  }

  Future<void> updateTrayIcon(bool isConnected) async {
    if (!isDesktop) return;
    try {
      final String iconPath = Platform.isWindows
          ? (isConnected ? 'assets/icons/tray_icon.ico' : 'assets/icons/tray_icon_off.ico')
          : (isConnected ? 'assets/icons/tray_icon.png' : 'assets/icons/tray_icon_off.png');
      await trayManager.setIcon(iconPath);
    } catch (e) {
      debugPrint('Failed to update tray icon: $e');
    }
  }

  @override
  void onWindowClose() async {
    // Hide to tray instead of closing
    bool isPreventClose = await windowManager.isPreventClose();
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
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'exit':
        await hardExit();
        break;
      case 'proxy_local':
        // Handle local proxy
        break;
      case 'proxy_system':
        // Handle system proxy
        break;
      case 'tunnel':
        // Handle full system tunnel
        break;
    }
  }

  Future<void> hardExit() async {
    // 1. Instantly hide UI
    await windowManager.destroy();
    
    // 2. Asynchronous, non-blocking cleanup of Xray core
    Future.microtask(() {
      try {
        // Since Xray handles stop gracefully if we send stop command,
        // or just let exit(0) kill the process tree.
        XrayBridge.invoke(jsonEncode({
          "apiVersion": 1,
          "method": "stopXray",
          "payload": {}
        }));
      } catch (_) {}
    });
    
    // 3. Hard exit
    exit(0);
  }
}
