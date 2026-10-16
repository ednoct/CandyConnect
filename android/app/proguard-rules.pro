# Flutter Wrapper & Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# CandyConnect Native VPN Service & Activity
-keep class com.vpn.candyconnect.** { *; }

# Keep JNI / Dart FFI / CGo methods in libXray.so
-keepclasseswithmembernames class * {
    native <methods>;
}

# Prevent stripping of device_apps and mobile_scanner models
-keep class fr.g123k.deviceapps.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn androidx.camera.**