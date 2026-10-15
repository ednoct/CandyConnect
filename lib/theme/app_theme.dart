import 'package:flutter/material.dart';

class AppTheme {
  static const Color oledDark = Color(0xFF0B0F19);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonPurple = Color(0xFFD500F9);
  static const Color errorRed = Color(0xFFFF1744);
  
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: oledDark,
      primaryColor: neonCyan,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        secondary: neonPurple,
        surface: oledDark,
        error: errorRed,
      ),
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Vazirmatn'),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: neonCyan,
        unselectedItemColor: Colors.white54,
      ),
    );
  }
}
