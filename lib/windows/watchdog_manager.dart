import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef CreateMutexWNative = Pointer<Void> Function(
  Pointer<Void> lpMutexAttributes,
  Int32 bInitialOwner,
  Pointer<Utf16> lpName,
);
typedef CreateMutexWDart = Pointer<Void> Function(
  Pointer<Void> lpMutexAttributes,
  int bInitialOwner,
  Pointer<Utf16> lpName,
);

typedef CloseHandleNative = Int32 Function(Pointer<Void> hObject);
typedef CloseHandleDart = int Function(Pointer<Void> hObject);

class WatchdogManager {
  static final WatchdogManager _instance = WatchdogManager._internal();
  factory WatchdogManager() => _instance;

  Process? _watchdogProcess;
  Pointer<Void>? _globalExitMutex;
  Pointer<Void>? _localExitMutex;
  DynamicLibrary? _kernel32;
  CreateMutexWDart? _createMutex;
  CloseHandleDart? _closeHandle;

  WatchdogManager._internal() {
    if (!Platform.isWindows) return;
    try {
      _kernel32 = DynamicLibrary.open('kernel32.dll');
      _createMutex = _kernel32!
          .lookupFunction<CreateMutexWNative, CreateMutexWDart>('CreateMutexW');
      _closeHandle = _kernel32!
          .lookupFunction<CloseHandleNative, CloseHandleDart>('CloseHandle');
    } catch (e) {
      debugPrint('[WatchdogManager] Failed to load kernel32.dll: $e');
    }
  }

  /// راه‌اندازی پروسه واچ‌داگ جهت پایش کرش‌های احتمالی برنامه در ویندوز
  Future<void> startWatchdog() async {
    if (!Platform.isWindows || _watchdogProcess != null) return;

    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final watchdogFile = File('$exeDir\\candy_watchdog.exe');

      if (!watchdogFile.existsSync()) {
        debugPrint(
            '[WatchdogManager] candy_watchdog.exe not found at ${watchdogFile.path}');
        return;
      }

      _watchdogProcess = await Process.start(
        watchdogFile.path,
        [pid.toString()],
        workingDirectory: exeDir,
        mode: ProcessStartMode.detached,
      );
      debugPrint('[WatchdogManager] Watchdog started monitoring PID $pid.');
    } catch (e) {
      debugPrint('[WatchdogManager] Failed to start watchdog: $e');
    }
  }

  /// اعلام خروج عادی و ایمن برنامه برای جلوگیری از اجرای روتین نجات واچ‌داگ
  void signalCleanExit() {
    if (!Platform.isWindows || _createMutex == null) return;

    try {
      final globalName = 'Global\\CandyConnectCleanExit'.toNativeUtf16();
      final localName = 'Local\\CandyConnectCleanExit'.toNativeUtf16();
      try {
        _globalExitMutex = _createMutex!(nullptr, 1, globalName);
        _localExitMutex = _createMutex!(nullptr, 1, localName);
      } finally {
        calloc.free(globalName);
        calloc.free(localName);
      }
    } catch (e) {
      debugPrint('[WatchdogManager] Failed to signal clean exit mutex: $e');
    }
  }

  /// خاتمه صریح پروسه واچ‌داگ و آزادسازی هندل‌های سیستم‌عامل
  void terminateWatchdog() {
    if (!Platform.isWindows) return;

    try {
      _watchdogProcess?.kill();
    } catch (_) {}
    _watchdogProcess = null;

    if (_closeHandle != null) {
      if (_globalExitMutex != null && _globalExitMutex != nullptr) {
        _closeHandle!(_globalExitMutex!);
        _globalExitMutex = null;
      }
      if (_localExitMutex != null && _localExitMutex != nullptr) {
        _closeHandle!(_localExitMutex!);
        _localExitMutex = null;
      }
    }
  }
}