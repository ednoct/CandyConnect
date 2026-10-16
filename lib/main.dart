import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/desktop_manager.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/custom_desktop_title_bar.dart';
import 'providers/app_providers.dart';
import 'theme/app_theme.dart';
import 'windows/elevation_utils.dart';
import 'windows/watchdog_manager.dart';

const int _kSingleInstancePort = 45321;
ServerSocket? _singleInstanceSocket;

/// مدیریت هوشمند تک‌نمونه‌ای (Single-Instance) در دسکتاپ همراه با بیدار کردن پنجره مخفی در Tray
Future<bool> _acquireSingleInstanceLock({required bool isElevationRelaunch}) async {
  final isDesktop =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  if (!isDesktop) return true;

  // ثبت کالبک آزادسازی سوکت قبل از ارتقای UAC تا نمونه جدید Admin با خطای پورت مواجه نشود
  ElevationUtils.onBeforeRelaunchExit = () async {
    try {
      await _singleInstanceSocket?.close();
      _singleInstanceSocket = null;
    } catch (_) {}
  };

  final int maxAttempts = isElevationRelaunch ? 8 : 1;

  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      _singleInstanceSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _kSingleInstancePort,
      );

      _singleInstanceSocket!.listen((Socket client) async {
        client.listen(
          (_) {},
          onDone: () async {
            if (await windowManager.isMinimized()) {
              await windowManager.restore();
            }
            await windowManager.show();
            await windowManager.focus();
          },
        );
      });
      return true;
    } on SocketException {
      if (isElevationRelaunch && attempt < maxAttempts - 1) {
        // صبر کوتاه تا نمونه غیر Admin قبلی پورت را کامل آزاد کند
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }

      // نمونه دیگری از برنامه از قبل باز است: به آن سیگنال بیدار شدن بده و خارج شو
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _kSingleInstancePort,
          timeout: const Duration(milliseconds: 500),
        );
        socket.add(utf8.encode('WAKEUP'));
        await socket.flush();
        await socket.close();
      } catch (_) {}
      return false;
    }
  }
  return false;
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final autoConnectVpn = args.contains('--auto-connect-vpn');

  final acquired = await _acquireSingleInstanceLock(
    isElevationRelaunch: autoConnectVpn,
  );
  if (!acquired) {
    exit(0);
  }

  if (Platform.isWindows) {
    await WatchdogManager().startWatchdog();
  }

  await DesktopManager().init();

  final container = ProviderContainer();
  final prefs = await SharedPreferences.getInstance();
  final savedLicense = prefs.getString('license_key');

  if (savedLicense != null && savedLicense.isNotEmpty) {
    container.read(currentLicenseProvider.notifier).state = savedLicense;
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: CandyConnectApp(
        initialLicense: savedLicense,
        autoConnectVpn: autoConnectVpn,
      ),
    ),
  );
}

class CandyConnectApp extends StatelessWidget {
  final String? initialLicense;
  final bool autoConnectVpn;

  const CandyConnectApp({
    super.key,
    this.initialLicense,
    this.autoConnectVpn = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return MaterialApp(
      title: 'CandyConnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        // جلوگیری از به‌هم‌ریختگی کارت‌های شیشه‌ای در صورت بزرگ بودن بیش از حد فونت سیستم‌عامل
        final clampedScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.15,
        );

        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedScaler),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.oledDark,
                border: isDesktop
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1.0,
                      )
                    : null,
              ),
              child: Column(
                children: [
                  if (isDesktop) const CustomDesktopTitleBar(),
                  Expanded(child: child ?? const SizedBox.shrink()),
                ],
              ),
            ),
          ),
        );
      },
      home: (initialLicense != null && initialLicense!.isNotEmpty)
          ? MainScreen(autoConnectVpn: autoConnectVpn)
          : const LoginScreen(),
    );
  }
}