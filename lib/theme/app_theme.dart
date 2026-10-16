import 'package:flutter/material.dart';

class AppTheme {
  static const Color oledDark = Color(0xFF0B0F19);
  static const Color deepSpace = Color(0xFF060911);
  static const Color surfaceGlass = Color(0xFF141B2D);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonPurple = Color(0xFFD500F9);
  static const Color electricBlue = Color(0xFF0052D4);
  static const Color errorRed = Color(0xFFFF1744);

  static ThemeData get darkTheme {
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Vazirmatn',
      scaffoldBackgroundColor: oledDark,
      primaryColor: neonCyan,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        secondary: neonPurple,
        surface: oledDark,
        error: errorRed,
        onPrimary: Colors.black,
        onSecondary: Colors.white,
        onSurface: Colors.white,
      ),
    );

    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        fontFamily: 'Vazirmatn',
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: neonCyan,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: neonCyan,
        selectionColor: neonCyan.withValues(alpha: 0.28),
        selectionHandleColor: neonCyan,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceGlass,
        contentTextStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          color: Colors.white,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: neonCyan.withValues(alpha: 0.35)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceGlass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Colors.white12),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return neonCyan.withValues(alpha: 0.6);
          }
          return Colors.white24;
        }),
        thickness: WidgetStateProperty.all(4.0),
        radius: const Radius.circular(8),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1A2238),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: neonCyan.withValues(alpha: 0.3)),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          color: Colors.white,
          fontSize: 11.5,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}