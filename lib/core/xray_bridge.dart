import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef CGoInvokeC = Pointer<Utf8> Function(Pointer<Utf8> requestJSON);
typedef CGoInvokeDart = Pointer<Utf8> Function(Pointer<Utf8> requestJSON);

typedef CGoFreeC = Void Function(Pointer<Utf8> value);
typedef CGoFreeDart = void Function(Pointer<Utf8> value);

class XrayBridge {
  static late DynamicLibrary _lib;
  static late CGoInvokeDart _invoke;
  static late CGoFreeDart _free;
  static bool _initialized = false;

  static Isolate? _xrayIsolate;
  static ReceivePort? _receivePort;

  static void init() {
    if (_initialized) return;
    
    if (Platform.isAndroid || Platform.isLinux) {
      _lib = DynamicLibrary.open('libXray.so');
    } else if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      _lib = DynamicLibrary.open('$exeDir\\libXray.dll');
    } else if (Platform.isIOS || Platform.isMacOS) {
      // Statically linked
      _lib = DynamicLibrary.process();
    }
    
    _invoke = _lib.lookupFunction<CGoInvokeC, CGoInvokeDart>('CGoInvoke');
    _free = _lib.lookupFunction<CGoFreeC, CGoFreeDart>('CGoFree');
    _initialized = true;
  }

  static String invoke(String json) {
    if (!_initialized) init();
    
    final ptr = json.toNativeUtf8();
    final resPtr = _invoke(ptr);
    malloc.free(ptr);
    
    if (resPtr.address == 0) return '';
    final res = resPtr.toDartString();
    _free(resPtr);
    return res;
  }

  static Future<void> startXray(String jsonString, void Function(String message) onMessage) async {
    await stopXray(); // Ensure any previous is stopped

    _receivePort = ReceivePort();
    _receivePort!.listen((message) {
      if (message is String) {
        onMessage(message);
      }
    });

    _xrayIsolate = await Isolate.spawn(_runXrayInIsolate, [_receivePort!.sendPort, jsonString]);
  }

  static Future<void> stopXray() async {
    if (_xrayIsolate != null) {
      try {
        invoke(jsonEncode({
          "apiVersion": 1,
          "method": "stopXray",
          "payload": {}
        }));
      } catch (e) {
        debugPrint('[XrayBridge] Error sending stopXray command: $e');
      }

      // Wait a short amount of time to allow the Go routine to tear down TUN properly
      await Future.delayed(const Duration(milliseconds: 300));

      _xrayIsolate?.kill(priority: Isolate.immediate);
      _xrayIsolate = null;
    }

    _receivePort?.close();
    _receivePort = null;
  }

  static void _runXrayInIsolate(List<dynamic> args) {
    final SendPort sendPort = args[0];
    final String jsonString = args[1];

    try {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/xray_config_${DateTime.now().millisecondsSinceEpoch}.json');
      tempFile.writeAsStringSync(jsonString);

      final requestJson = jsonEncode({
        "apiVersion": 1,
        "method": "runXray",
        "payload": {"configPath": tempFile.path}
      });

      final result = XrayBridge.invoke(requestJson);

      try {
        tempFile.deleteSync();
      } catch (_) {}

      sendPort.send(result);
    } catch (e) {
      sendPort.send(e.toString());
    }
  }

  /// Copies geoip.dat and geosite.dat from Flutter assets to the app documents
  /// directory. Prevents stale caching by comparing byte lengths.
  static Future<String> ensureRoutingAssets() async {
    final dir = await getApplicationDocumentsDirectory();
    for (final name in ['geoip.dat', 'geosite.dat']) {
      final dest = File('${dir.path}/$name');
      final assetData = await rootBundle.load('assets/routing/$name');
      
      bool needsCopy = true;
      if (dest.existsSync()) {
        if (dest.lengthSync() == assetData.lengthInBytes) {
          needsCopy = false;
        }
      }
      
      if (needsCopy) {
        await dest.writeAsBytes(assetData.buffer.asUint8List());
      }
    }
    return dir.path;
  }
}
