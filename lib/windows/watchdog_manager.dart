import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef CreateMutexWNative = Pointer<Void> Function(Pointer<Void> lpMutexAttributes, Int32 bInitialOwner, Pointer<Utf16> lpName);
typedef CreateMutexWDart = Pointer<Void> Function(Pointer<Void> lpMutexAttributes, int bInitialOwner, Pointer<Utf16> lpName);

typedef CloseHandleNative = Int32 Function(Pointer<Void> hObject);
typedef CloseHandleDart = int Function(Pointer<Void> hObject);

class WatchdogManager {
  Process? _watchdogProcess;
  Pointer<Void>? _cleanExitMutex;
  late DynamicLibrary _kernel32;
  late CreateMutexWDart _createMutex;
  late CloseHandleDart _closeHandle;

  WatchdogManager() {
    if (!Platform.isWindows) return;
    _kernel32 = DynamicLibrary.open('kernel32.dll');
    _createMutex = _kernel32.lookupFunction<CreateMutexWNative, CreateMutexWDart>('CreateMutexW');
    _closeHandle = _kernel32.lookupFunction<CloseHandleNative, CloseHandleDart>('CloseHandle');
  }

  /// Spawns the watchdog process to monitor this application.
  Future<void> startWatchdog() async {
    if (!Platform.isWindows) return;

    try {
      // The executable will be next to the main executable
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final watchdogPath = '$exeDir\\candy_watchdog.exe';

      _watchdogProcess = await Process.start(
        watchdogPath,
        [pid.toString()],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      print('Failed to start watchdog: $e');
    }
  }

  /// Signals that the application is exiting cleanly, preventing the watchdog
  /// from triggering the rescue routine.
  void signalCleanExit() {
    if (!Platform.isWindows) return;

    final mutexName = 'Global\\CandyConnectCleanExit'.toNativeUtf16();
    // Create the mutex, initially owned = true
    _cleanExitMutex = _createMutex(nullptr, 1, mutexName);
    calloc.free(mutexName);
  }

  /// Explicitly terminates the watchdog and cleans up IPC mechanisms.
  /// Call this after the Dart-based teardown is complete.
  void terminateWatchdog() {
    if (_watchdogProcess != null) {
      _watchdogProcess!.kill();
      _watchdogProcess = null;
    }

    if (_cleanExitMutex != null && _cleanExitMutex != nullptr) {
      _closeHandle(_cleanExitMutex!);
      _cleanExitMutex = null;
    }
  }
}
