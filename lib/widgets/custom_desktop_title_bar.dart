import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class CustomDesktopTitleBar extends ConsumerStatefulWidget {
  const CustomDesktopTitleBar({super.key});

  @override
  ConsumerState<CustomDesktopTitleBar> createState() => _CustomDesktopTitleBarState();
}

class _CustomDesktopTitleBarState extends ConsumerState<CustomDesktopTitleBar> {
  bool _isExitHovered = false;

  void _onExitPressed() async {
    final currentLicense = ref.read(currentLicenseProvider);
    
    if (currentLicense != null && currentLicense.isNotEmpty) {
      // User is logged in
      await windowManager.hide();
    } else {
      // User is NOT logged in
      await windowManager.destroy();
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DragToMoveArea(
        child: Container(
          height: 40,
          decoration: const BoxDecoration(
            color: AppTheme.oledDark,
          ),
          child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Exit Button
            MouseRegion(
              onEnter: (_) => setState(() => _isExitHovered = true),
              onExit: (_) => setState(() => _isExitHovered = false),
              child: GestureDetector(
                onTap: _onExitPressed,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 40,
                  alignment: Alignment.center,
                  color: _isExitHovered ? Colors.red : Colors.transparent,
                  child: Icon(
                    Icons.close,
                    color: _isExitHovered ? Colors.white : Colors.white70,
                    size: 20,
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
