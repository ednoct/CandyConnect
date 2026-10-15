import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// --- Wintun FFI Type Definitions ---

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
    Pointer<Utf16> Name, Pointer<Utf16> TunnelType, Pointer<GUID> RequestedGUID);
typedef WintunCreateAdapterDart = Pointer<Void> Function(
    Pointer<Utf16> Name, Pointer<Utf16> TunnelType, Pointer<GUID> RequestedGUID);

typedef WintunCloseAdapterNative = Void Function(Pointer<Void> Adapter);
typedef WintunCloseAdapterDart = void Function(Pointer<Void> Adapter);

typedef WintunStartSessionNative = Pointer<Void> Function(
    Pointer<Void> Adapter, Uint32 Capacity);
typedef WintunStartSessionDart = Pointer<Void> Function(
    Pointer<Void> Adapter, int Capacity);

typedef WintunEndSessionNative = Void Function(Pointer<Void> Session);
typedef WintunEndSessionDart = void Function(Pointer<Void> Session);

class WintunFFI {
  late DynamicLibrary _wintunLib;

  late WintunCreateAdapterDart _createAdapter;
  late WintunCloseAdapterDart _closeAdapter;
  late WintunStartSessionDart _startSession;
  late WintunEndSessionDart _endSession;

  Pointer<Void>? _adapter;
  Pointer<Void>? _session;

  WintunFFI() {
    // Note: In VPN mode, wintun.dll is shipped next to the executable.
    _wintunLib = DynamicLibrary.open('wintun.dll');

    _createAdapter = _wintunLib.lookupFunction<WintunCreateAdapterNative,
        WintunCreateAdapterDart>('WintunCreateAdapter');
    _closeAdapter = _wintunLib.lookupFunction<WintunCloseAdapterNative,
        WintunCloseAdapterDart>('WintunCloseAdapter');
    _startSession = _wintunLib.lookupFunction<WintunStartSessionNative,
        WintunStartSessionDart>('WintunStartSession');
    _endSession = _wintunLib.lookupFunction<WintunEndSessionNative,
        WintunEndSessionDart>('WintunEndSession');
  }

  /// Initializes the Wintun adapter.
  bool initializeAdapter(String adapterName, String tunnelType) {
    final pName = adapterName.toNativeUtf16();
    final pTunnelType = tunnelType.toNativeUtf16();

    _adapter = _createAdapter(pName, pTunnelType, nullptr);
    
    calloc.free(pName);
    calloc.free(pTunnelType);

    return _adapter != nullptr;
  }

  /// Starts a session on the adapter.
  bool startSession(int capacity) {
    if (_adapter == nullptr || _adapter == null) return false;
    _session = _startSession(_adapter!, capacity);
    return _session != nullptr;
  }

  /// Configures adapter IP, subnet, gateway, and routing metrics.
  /// Replaces existing default routes to enforce VPN traffic via Wintun.
  Future<void> configureRouting({
    required String adapterName,
    required String localIp,
    required String subnetPrefix,
    required String gatewayIp,
  }) async {
    // 1. Assign IP address and Gateway to the Wintun adapter
    await Process.run('netsh', [
      'interface', 'ipv4', 'set', 'address',
      'name=$adapterName', 'static', localIp, subnetPrefix, gatewayIp, '1' // metric 1
    ]);

    // 2. Adjust Interface Metrics for high priority
    await Process.run('netsh', [
      'interface', 'ipv4', 'set', 'interface',
      adapterName, 'metric=1'
    ]);

    // 3. Add explicit routes overriding default routing table (Zero-Leak)
    // Route all traffic through the VPN gateway
    await Process.run('route', ['add', '0.0.0.0', 'mask', '128.0.0.0', gatewayIp, 'METRIC', '1']);
    await Process.run('route', ['add', '128.0.0.0', 'mask', '128.0.0.0', gatewayIp, 'METRIC', '1']);
  }

  void close() {
    if (_session != null && _session != nullptr) {
      _endSession(_session!);
      _session = null;
    }
    if (_adapter != null && _adapter != nullptr) {
      _closeAdapter(_adapter!);
      _adapter = null;
    }
  }

  Future<int> getInterfaceIndex(String adapterName) async {
    try {
      final result = await Process.run('powershell', ['-Command', '(Get-NetAdapter -Name "$adapterName").ifIndex']);
      return int.tryParse(result.stdout.toString().trim()) ?? -1;
    } catch (e) {
      return -1;
    }
  }
}
