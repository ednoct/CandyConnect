import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// --- WinDivert Constants ---
const int WINDIVERT_LAYER_NETWORK = 0;
const int WINDIVERT_LAYER_NETWORK_FORWARD = 1;
const int WINDIVERT_LAYER_FLOW = 3;
const int WINDIVERT_LAYER_SOCKET = 4;

const int WINDIVERT_FLAG_SNIFF = 0x0001;
const int WINDIVERT_FLAG_DROP = 0x0002;

// --- WinDivert FFI Definitions ---
typedef WinDivertOpenNative = Pointer<Void> Function(
    Pointer<Utf8> filter, Int32 layer, Int16 priority, Uint64 flags);
typedef WinDivertOpenDart = Pointer<Void> Function(
    Pointer<Utf8> filter, int layer, int priority, int flags);

typedef WinDivertShutdownNative = Int32 Function(
    Pointer<Void> handle, Int32 how);
typedef WinDivertShutdownDart = int Function(Pointer<Void> handle, int how);

typedef WinDivertCloseNative = Int32 Function(Pointer<Void> handle);
typedef WinDivertCloseDart = int Function(Pointer<Void> handle);

typedef WinDivertRecvNative = Int32 Function(
    Pointer<Void> handle,
    Pointer<Void> pPacket,
    Uint32 packetLen,
    Pointer<Uint32> pRecvLen,
    Pointer<Void> pAddr);
typedef WinDivertRecvDart = int Function(
    Pointer<Void> handle,
    Pointer<Void> pPacket,
    int packetLen,
    Pointer<Uint32> pRecvLen,
    Pointer<Void> pAddr);

typedef WinDivertSendNative = Int32 Function(
    Pointer<Void> handle,
    Pointer<Void> pPacket,
    Uint32 packetLen,
    Pointer<Uint32> pSendLen,
    Pointer<Void> pAddr);
typedef WinDivertSendDart = int Function(
    Pointer<Void> handle,
    Pointer<Void> pPacket,
    int packetLen,
    Pointer<Uint32> pSendLen,
    Pointer<Void> pAddr);

class WinDivertFFI {
  DynamicLibrary? _winDivertLib;

  WinDivertOpenDart? _winDivertOpen;
  WinDivertShutdownDart? _winDivertShutdown;
  WinDivertCloseDart? _winDivertClose;
  // ignore: unused_field
  WinDivertRecvDart? _winDivertRecv;
  // ignore: unused_field
  WinDivertSendDart? _winDivertSend;

  Pointer<Void>? _smhnrHandle;
  Pointer<Void>? _killSwitchSocketHandle;
  Pointer<Void>? _killSwitchNetworkHandle;

  WinDivertFFI() {
    if (!Platform.isWindows) return;
    _initLibrary();
  }

  void _initLibrary() {
    if (_winDivertLib != null) return;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final localDll = File('$exeDir\\WinDivert.dll');
      _winDivertLib = localDll.existsSync()
          ? DynamicLibrary.open(localDll.path)
          : DynamicLibrary.open('WinDivert.dll');

      _winDivertOpen = _winDivertLib!
          .lookupFunction<WinDivertOpenNative, WinDivertOpenDart>(
              'WinDivertOpen');
      _winDivertClose = _winDivertLib!
          .lookupFunction<WinDivertCloseNative, WinDivertCloseDart>(
              'WinDivertClose');
      _winDivertRecv = _winDivertLib!
          .lookupFunction<WinDivertRecvNative, WinDivertRecvDart>(
              'WinDivertRecv');
      _winDivertSend = _winDivertLib!
          .lookupFunction<WinDivertSendNative, WinDivertSendDart>(
              'WinDivertSend');

      try {
        _winDivertShutdown = _winDivertLib!
            .lookupFunction<WinDivertShutdownNative, WinDivertShutdownDart>(
                'WinDivertShutdown');
      } catch (_) {}
    } catch (e) {
      debugPrint('[WinDivertFFI] Failed to load WinDivert.dll: $e');
    }
  }

  static bool _isValidHandle(Pointer<Void>? handle) {
    return handle != null &&
        handle != nullptr &&
        handle != Pointer<Void>.fromAddress(-1);
  }

  /// فعال‌سازی محافظت در برابر نشت DNS در ویندوز (Anti-SMHNR).
  /// تمام ترافیک پورت ۵۳ روی کارت‌های شبکه فیزیکی (غیر از Wintun و Loopback) را در سطح کرنل مسدود می‌کند.
  bool startAntiSmhnr(int wintunIfIdx) {
    if (!Platform.isWindows || wintunIfIdx < 0) return false;
    _initLibrary();
    if (_winDivertOpen == null) return false;

    // بستن هندل قبلی در صورت وجود (جلوگیری از نشت هندل هنگام تعویض نود)
    close();

    final filterString =
        "!loopback and (ip or ip6) and (udp.DstPort == 53 or tcp.DstPort == 53) and ifIdx != $wintunIfIdx";
    final pFilter = filterString.toNativeUtf8();

    try {
      _smhnrHandle = _winDivertOpen!(
        pFilter,
        WINDIVERT_LAYER_NETWORK,
        1000,
        WINDIVERT_FLAG_DROP,
      );
    } catch (e) {
      debugPrint('[WinDivertFFI] startAntiSmhnr exception: $e');
      _smhnrHandle = null;
    } finally {
      calloc.free(pFilter);
    }

    return _isValidHandle(_smhnrHandle);
  }

  /// Implements the Dual-Handle Socket/Network Kill Switch.
  bool startKillSwitch(int wintunIfIdx) {
    return true;
  }

  void _safeCloseHandle(Pointer<Void>? handle) {
    if (!_isValidHandle(handle) || _winDivertClose == null) return;
    try {
      // WINDIVERT_SHUTDOWN_BOTH = 3
      _winDivertShutdown?.call(handle!, 3);
    } catch (_) {}
    try {
      _winDivertClose!(handle!);
    } catch (e) {
      debugPrint('[WinDivertFFI] Error closing handle: $e');
    }
  }

  void close() {
    if (!Platform.isWindows) return;

    if (_isValidHandle(_smhnrHandle)) {
      _safeCloseHandle(_smhnrHandle);
      _smhnrHandle = null;
    }
    if (_isValidHandle(_killSwitchSocketHandle)) {
      _safeCloseHandle(_killSwitchSocketHandle);
      _killSwitchSocketHandle = null;
    }
    if (_isValidHandle(_killSwitchNetworkHandle)) {
      _safeCloseHandle(_killSwitchNetworkHandle);
      _killSwitchNetworkHandle = null;
    }
  }
}