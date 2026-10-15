import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

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
  static final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');

  /// Checks if the current process runs with Administrator privileges.
  static bool isElevated() {
    if (!Platform.isWindows) return false;
    try {
      final isUserAnAdmin = _shell32.lookupFunction<IsUserAnAdminNative, IsUserAnAdminDart>('IsUserAnAdmin');
      return isUserAnAdmin() != 0;
    } catch (e) {
      debugPrint('[ElevationUtils] Failed to check elevation: $e');
      return false;
    }
  }

  /// Relaunches the current executable with UAC elevation (Administrator rights)
  /// and exits the current non-elevated instance.
  static void relaunchElevated(List<String> args) {
    if (!Platform.isWindows) return;

    try {
      final shellExecute = _shell32.lookupFunction<ShellExecuteNative, ShellExecuteDart>('ShellExecuteW');
      
      final exePath = Platform.resolvedExecutable;
      
      final pOperation = 'runas'.toNativeUtf16();
      final pFile = exePath.toNativeUtf16();
      final pParameters = args.join(' ').toNativeUtf16();
      
      // SW_SHOWNORMAL = 1
      final result = shellExecute(
        0, 
        pOperation, 
        pFile, 
        pParameters, 
        nullptr, 
        1,
      );
      
      calloc.free(pOperation);
      calloc.free(pFile);
      calloc.free(pParameters);

      // If result > 32, ShellExecute was successful.
      if (result > 32) {
        debugPrint('[ElevationUtils] Relaunched successfully, exiting current instance.');
        exit(0);
      } else {
        debugPrint('[ElevationUtils] Failed to relaunch elevated, error code: $result');
      }
    } catch (e) {
      debugPrint('[ElevationUtils] Failed to relaunch elevated: $e');
    }
  }
}
