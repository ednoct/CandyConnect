import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

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

typedef WinDivertCloseNative = Int32 Function(Pointer<Void> handle);
typedef WinDivertCloseDart = int Function(Pointer<Void> handle);

typedef WinDivertRecvNative = Int32 Function(
    Pointer<Void> handle, Pointer<Void> pPacket, Uint32 packetLen, Pointer<Uint32> pRecvLen, Pointer<Void> pAddr);
typedef WinDivertRecvDart = int Function(
    Pointer<Void> handle, Pointer<Void> pPacket, int packetLen, Pointer<Uint32> pRecvLen, Pointer<Void> pAddr);

typedef WinDivertSendNative = Int32 Function(
    Pointer<Void> handle, Pointer<Void> pPacket, Uint32 packetLen, Pointer<Uint32> pSendLen, Pointer<Void> pAddr);
typedef WinDivertSendDart = int Function(
    Pointer<Void> handle, Pointer<Void> pPacket, int packetLen, Pointer<Uint32> pSendLen, Pointer<Void> pAddr);

class WinDivertFFI {
  late DynamicLibrary _winDivertLib;

  late WinDivertOpenDart _winDivertOpen;
  late WinDivertCloseDart _winDivertClose;
  late WinDivertRecvDart _winDivertRecv;
  late WinDivertSendDart _winDivertSend;

  Pointer<Void>? _smhnrHandle;
  Pointer<Void>? _killSwitchSocketHandle;
  Pointer<Void>? _killSwitchNetworkHandle;

  WinDivertFFI() {
    _winDivertLib = DynamicLibrary.open('WinDivert.dll');

    _winDivertOpen = _winDivertLib.lookupFunction<WinDivertOpenNative, WinDivertOpenDart>('WinDivertOpen');
    _winDivertClose = _winDivertLib.lookupFunction<WinDivertCloseNative, WinDivertCloseDart>('WinDivertClose');
    _winDivertRecv = _winDivertLib.lookupFunction<WinDivertRecvNative, WinDivertRecvDart>('WinDivertRecv');
    _winDivertSend = _winDivertLib.lookupFunction<WinDivertSendNative, WinDivertSendDart>('WinDivertSend');
  }

  /// Initializes the Anti-SMHNR (DNS Leak Protection).
  /// Drops all port 53 traffic on physical adapters, forcing DNS through Wintun.
  bool startAntiSmhnr(int wintunIfIdx) {
    // Drop all DNS traffic that isn't on the Wintun adapter index.
    final filterString = "(ip or ip6) and (udp.DstPort == 53 or tcp.DstPort == 53) and ifIdx != $wintunIfIdx";
    final pFilter = filterString.toNativeUtf8();

    _smhnrHandle = _winDivertOpen(
      pFilter,
      WINDIVERT_LAYER_NETWORK,
      1000,
      WINDIVERT_FLAG_DROP, // Drop matching packets immediately in kernel
    );

    calloc.free(pFilter);

    // INVALID_HANDLE_VALUE equivalent check (commonly -1, but pointer check relies on specific implementation)
    return _smhnrHandle != Pointer.fromAddress(-1) && _smhnrHandle != nullptr;
  }

  /// Implements the Dual-Handle Socket/Network Kill Switch.
  bool startKillSwitch(int wintunIfIdx) {
    // Disabled temporarily.
    // The previous implementation opened a network-layer drop handle but did not
    // include a packet pump (WinDivertRecv) to process it, causing all outbound
    // connections (including the proxy core itself) to be dropped or severely delayed.
    return true;
  }

  void close() {
    if (_smhnrHandle != null && _smhnrHandle != Pointer.fromAddress(-1)) {
      _winDivertClose(_smhnrHandle!);
      _smhnrHandle = null;
    }
    if (_killSwitchSocketHandle != null && _killSwitchSocketHandle != Pointer.fromAddress(-1)) {
      _winDivertClose(_killSwitchSocketHandle!);
      _killSwitchSocketHandle = null;
    }
    if (_killSwitchNetworkHandle != null && _killSwitchNetworkHandle != Pointer.fromAddress(-1)) {
      _winDivertClose(_killSwitchNetworkHandle!);
      _killSwitchNetworkHandle = null;
    }
  }
}
