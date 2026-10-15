import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'watchdog_manager.dart';

// --- shell32.dll FFI Types ---
typedef IsUserAnAdminNative = Int32 Function();
typedef IsUserAnAdminDart = int Function();

// INT_PTR ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile, LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd)
typedef ShellExecuteNative = IntPtr Function(
  IntPtr hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  Int32 nShowCmd,
);
typedef ShellExecuteDart = int Function(
  int hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  int nShowCmd,
);

class ElevationUtils {
  static DynamicLibrary? _shell32Instance;

  static DynamicLibrary? get _shell32 {
    if (!Platform.isWindows) return null;
    return _shell32Instance ??= DynamicLibrary.open('shell32.dll');
  }

  /// کالبک آزادسازی سوکت تک‌نمونه‌ای (ثبت‌شده در main.dart) تا نمونه Admin جدید مسدود نشود
  static Future<void> Function()? onBeforeRelaunchExit;

  /// بررسی اجرای فعلی برنامه با دسترسی Administrator
  static bool isElevated() {
    if (!Platform.isWindows) return false;
    try {
      final lib = _shell32;
      if (lib == null) return false;
      final isUserAnAdmin = lib
          .lookupFunction<IsUserAnAdminNative, IsUserAnAdminDart>('IsUserAnAdmin');
      return isUserAnAdmin() != 0;
    } catch (e) {
      debugPrint('[ElevationUtils] Failed to check elevation: $e');
      return false;
    }
  }

  /// راه‌اندازی مجدد برنامه با دسترسی Administrator (UAC) و خروج ایمن از نمونه فعلی
  static Future<void> relaunchElevated(List<String> args) async {
    if (!Platform.isWindows) return;

    Pointer<Utf16> pOperation = nullptr;
    Pointer<Utf16> pFile = nullptr;
    Pointer<Utf16> pParameters = nullptr;
    Pointer<Utf16> pDirectory = nullptr;

    try {
      final lib = _shell32;
      if (lib == null) return;

      final shellExecute = lib
          .lookupFunction<ShellExecuteNative, ShellExecuteDart>('ShellExecuteW');

      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      // ۱. آزادسازی پورت تک‌نمونه‌ای قبل از اسپاون پروسه جدید تا نمونه Admin کرش نکند
      if (onBeforeRelaunchExit != null) {
        await onBeforeRelaunchExit!();
      }

      pOperation = 'runas'.toNativeUtf16();
      pFile = exePath.toNativeUtf16();
      pParameters = args.join(' ').toNativeUtf16();
      pDirectory = exeDir.toNativeUtf16();

      // SW_SHOWNORMAL = 1
      final result = shellExecute(
        0,
        pOperation,
        pFile,
        pParameters,
        pDirectory,
        1,
      );

      // در Win32 مقدار بزرگ‌تر از 32 به معنای موفقیت اجرای پروسه جدید است
      if (result > 32) {
        debugPrint(
            '[ElevationUtils] Relaunched elevated successfully, exiting current instance.');
        WatchdogManager().signalCleanExit();
        WatchdogManager().terminateWatchdog();
        exit(0);
      } else {
        debugPrint(
            '[ElevationUtils] UAC canceled or failed, code: $result');
      }
    } catch (e) {
      debugPrint('[ElevationUtils] Failed to relaunch elevated: $e');
    } finally {
      if (pOperation != nullptr) calloc.free(pOperation);
      if (pFile != nullptr) calloc.free(pFile);
      if (pParameters != nullptr) calloc.free(pParameters);
      if (pDirectory != nullptr) calloc.free(pDirectory);
    }
  }
}