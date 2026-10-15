// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// --- Wintun & IP Helper FFI Type Definitions ---

final class GUID extends Struct {
  @Uint32()
  external int Data1;
  @Uint16()
  external int Data2;
  @Uint16()
  external int Data3;
  @Array(8)
  external Array<Uint8> Data4;
}

typedef WintunCreateAdapterNative = Pointer<Void> Function(
    Pointer<Utf16> Name,
    Pointer<Utf16> TunnelType,
    Pointer<GUID> RequestedGUID);
typedef WintunCreateAdapterDart = Pointer<Void> Function(
    Pointer<Utf16> Name,
    Pointer<Utf16> TunnelType,
    Pointer<GUID> RequestedGUID);

typedef WintunCloseAdapterNative = Void Function(Pointer<Void> Adapter);
typedef WintunCloseAdapterDart = void Function(Pointer<Void> Adapter);

typedef WintunStartSessionNative = Pointer<Void> Function(
    Pointer<Void> Adapter, Uint32 Capacity);
typedef WintunStartSessionDart = Pointer<Void> Function(
    Pointer<Void> Adapter, int Capacity);

typedef WintunEndSessionNative = Void Function(Pointer<Void> Session);
typedef WintunEndSessionDart = void Function(Pointer<Void> Session);

// --- iphlpapi.dll Native Types (برای دریافت فوق‌سریع ifIndex بدون PowerShell) ---
typedef ConvertInterfaceAliasToLuidNative = Int32 Function(
    Pointer<Utf16> InterfaceAlias, Pointer<Uint64> InterfaceLuid);
typedef ConvertInterfaceAliasToLuidDart = int Function(
    Pointer<Utf16> InterfaceAlias, Pointer<Uint64> InterfaceLuid);

typedef ConvertInterfaceLuidToIndexNative = Int32 Function(
    Pointer<Uint64> InterfaceLuid, Pointer<Uint32> InterfaceIndex);
typedef ConvertInterfaceLuidToIndexDart = int Function(
    Pointer<Uint64> InterfaceLuid, Pointer<Uint32> InterfaceIndex);

class WintunFFI {
  DynamicLibrary? _wintunLib;
  DynamicLibrary? _iphlpapiLib;

  WintunCreateAdapterDart? _createAdapter;
  WintunCloseAdapterDart? _closeAdapter;
  WintunStartSessionDart? _startSession;
  WintunEndSessionDart? _endSession;

  ConvertInterfaceAliasToLuidDart? _aliasToLuid;
  ConvertInterfaceLuidToIndexDart? _luidToIndex;

  Pointer<Void>? _adapter;
  Pointer<Void>? _session;
  String? _lastGatewayIp;

  WintunFFI() {
    if (!Platform.isWindows) return;
    _initLibraries();
  }

  void _initLibraries() {
    if (_wintunLib == null) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final localDll = File('$exeDir\\wintun.dll');
        _wintunLib = localDll.existsSync()
            ? DynamicLibrary.open(localDll.path)
            : DynamicLibrary.open('wintun.dll');

        _createAdapter = _wintunLib!.lookupFunction<WintunCreateAdapterNative,
            WintunCreateAdapterDart>('WintunCreateAdapter');
        _closeAdapter = _wintunLib!.lookupFunction<WintunCloseAdapterNative,
            WintunCloseAdapterDart>('WintunCloseAdapter');
        _startSession = _wintunLib!.lookupFunction<WintunStartSessionNative,
            WintunStartSessionDart>('WintunStartSession');
        _endSession = _wintunLib!.lookupFunction<WintunEndSessionNative,
            WintunEndSessionDart>('WintunEndSession');
      } catch (e) {
        debugPrint('[WintunFFI] Failed to load wintun.dll: $e');
      }
    }

    if (_iphlpapiLib == null) {
      try {
        _iphlpapiLib = DynamicLibrary.open('iphlpapi.dll');
        _aliasToLuid = _iphlpapiLib!.lookupFunction<
            ConvertInterfaceAliasToLuidNative,
            ConvertInterfaceAliasToLuidDart>('ConvertInterfaceAliasToLuid');
        _luidToIndex = _iphlpapiLib!.lookupFunction<
            ConvertInterfaceLuidToIndexNative,
            ConvertInterfaceLuidToIndexDart>('ConvertInterfaceLuidToIndex');
      } catch (e) {
        debugPrint('[WintunFFI] Failed to load iphlpapi.dll: $e');
      }
    }
  }

  /// Initializes the Wintun adapter.
  bool initializeAdapter(String adapterName, String tunnelType) {
    if (!Platform.isWindows) return false;
    _initLibraries();
    if (_createAdapter == null) return false;

    final pName = adapterName.toNativeUtf16();
    final pTunnelType = tunnelType.toNativeUtf16();

    try {
      _adapter = _createAdapter!(pName, pTunnelType, nullptr);
    } finally {
      calloc.free(pName);
      calloc.free(pTunnelType);
    }

    return _adapter != null && _adapter != nullptr;
  }

  /// Starts a session on the adapter.
  bool startSession(int capacity) {
    if (!Platform.isWindows ||
        _adapter == null ||
        _adapter == nullptr ||
        _startSession == null) {
      return false;
    }
    _session = _startSession!(_adapter!, capacity);
    return _session != null && _session != nullptr;
  }

  /// Configures adapter IP, subnet, gateway, and routing metrics.
  Future<void> configureRouting({
    required String adapterName,
    required String localIp,
    required String subnetPrefix,
    required String gatewayIp,
  }) async {
    if (!Platform.isWindows) return;
    _lastGatewayIp = gatewayIp;

    await Process.run('netsh', [
      'interface',
      'ipv4',
      'set',
      'address',
      'name=$adapterName',
      'static',
      localIp,
      subnetPrefix,
      gatewayIp,
      '1',
    ]);

    await Process.run('netsh', [
      'interface',
      'ipv4',
      'set',
      'interface',
      adapterName,
      'metric=1',
    ]);

    await Process.run(
        'route', ['add', '0.0.0.0', 'mask', '128.0.0.0', gatewayIp, 'METRIC', '1']);
    await Process.run(
        'route', ['add', '128.0.0.0', 'mask', '128.0.0.0', gatewayIp, 'METRIC', '1']);
  }

  /// حذف قطعی روت‌های اضافه شده در جدول مسیریابی ویندوز جهت جلوگیری از قطع اینترنت کاربر
  Future<void> cleanupRouting({String? gatewayIp}) async {
    if (!Platform.isWindows) return;
    final gw = gatewayIp ?? _lastGatewayIp ?? '10.0.0.1';
    try {
      await Process.run('route', ['delete', '0.0.0.0', 'mask', '128.0.0.0', gw]);
      await Process.run('route', ['delete', '128.0.0.0', 'mask', '128.0.0.0', gw]);
    } catch (e) {
      debugPrint('[WintunFFI] cleanupRouting error: $e');
    }
  }

  void close({String? gatewayIp}) {
    if (!Platform.isWindows) return;

    final gw = gatewayIp ?? _lastGatewayIp;
    if (gw != null) {
      cleanupRouting(gatewayIp: gw);
      _lastGatewayIp = null;
    }

    if (_session != null && _session != nullptr && _endSession != null) {
      try {
        _endSession!(_session!);
      } catch (_) {}
      _session = null;
    }
    if (_adapter != null && _adapter != nullptr && _closeAdapter != null) {
      try {
        _closeAdapter!(_adapter!);
      } catch (_) {}
      _adapter = null;
    }
  }

  /// دریافت آنی شماره اینترفیس (ifIndex) از طریق کرنل ویندوز (iphlpapi.dll)
  /// در کمتر از ۱ میلی‌ثانیه بدون نیاز به اجرای PowerShell سنگین
  Future<int> getInterfaceIndex(String adapterName) async {
    if (!Platform.isWindows) return -1;
    _initLibraries();

    // تلاش اول: استفاده فوق‌سریع از Win32 Native API (ConvertInterfaceAliasToLuid)
    if (_aliasToLuid != null && _luidToIndex != null) {
      final pAlias = adapterName.toNativeUtf16();
      final pLuid = calloc<Uint64>();
      final pIndex = calloc<Uint32>();

      try {
        final err1 = _aliasToLuid!(pAlias, pLuid);
        if (err1 == 0) {
          final err2 = _luidToIndex!(pLuid, pIndex);
          if (err2 == 0 && pIndex.value > 0) {
            return pIndex.value;
          }
        }
      } catch (_) {
      } finally {
        calloc.free(pAlias);
        calloc.free(pLuid);
        calloc.free(pIndex);
      }
    }

    // تلاش دوم (پشتیبان): استفاده از PowerShell در صورت عدم تطابق Alias
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-NetAdapter -Name "$adapterName" -ErrorAction SilentlyContinue).ifIndex'
        ],
      );
      return int.tryParse(result.stdout.toString().trim()) ?? -1;
    } catch (e) {
      return -1;
    }
  }
}