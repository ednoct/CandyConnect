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

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final autoConnectVpn = args.contains('--auto-connect-vpn');
  
  try {
    final serverSocket = await ServerSocket.bind('127.0.0.1', 45321);
    serverSocket.listen((_) async {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  } catch (e) {
    if (e is SocketException) {
      exit(0);
    }
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
      child: CandyConnectApp(initialLicense: savedLicense, autoConnectVpn: autoConnectVpn),
    ),
  );
}

class CandyConnectApp extends StatelessWidget {
  final String? initialLicense;
  final bool autoConnectVpn;
  const CandyConnectApp({super.key, this.initialLicense, this.autoConnectVpn = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CandyConnect',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19), // Deep OLED Dark Mode
        fontFamily: 'Vazirmatn',
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                const CustomDesktopTitleBar(),
              Expanded(child: child!),
            ],
          ),
        );
      },
      home: (initialLicense != null && initialLicense!.isNotEmpty) 
          ? MainScreen(autoConnectVpn: autoConnectVpn) 
          : const LoginScreen(),
    );
  }
}
