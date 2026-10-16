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
  static bool _isCoreRunning = false;
  static String? _verifiedAssetDir;

  static void init() {
    if (_initialized) return;

    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libXray.so');
    } else if (Platform.isLinux) {
      _lib = _openLinuxLibrary();
    } else if (Platform.isWindows) {
      _lib = _openWindowsLibrary();
    } else if (Platform.isIOS || Platform.isMacOS) {
      _lib = _openAppleLibrary();
    }

    _invoke = _lib.lookupFunction<CGoInvokeC, CGoInvokeDart>('CGoInvoke');
    _free = _lib.lookupFunction<CGoFreeC, CGoFreeDart>('CGoFree');
    _initialized = true;
  }

  /// بارگذاری ضدخطای libXray.dll در ویندوز (پشتیبانی از مسیر اجرایی، Symlink و مسیر کاری پس از UAC)
  static DynamicLibrary _openWindowsLibrary() {
    String resolvedExePath = Platform.resolvedExecutable;
    try {
      resolvedExePath = File(resolvedExePath).resolveSymbolicLinksSync();
    } catch (_) {}

    final exeDir = File(resolvedExePath).parent.path;
    final candidates = <String>[
      '$exeDir\\libXray.dll',
      '${Directory.current.path}\\libXray.dll',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    }

    return DynamicLibrary.open('libXray.dll');
  }

  /// بارگذاری ضدخطای libXray.so در لینوکس (پشتیبانی از باندل، پکیج .deb در /opt و Symlink در /usr/bin)
  static DynamicLibrary _openLinuxLibrary() {
    String resolvedExePath = Platform.resolvedExecutable;
    try {
      resolvedExePath = File(resolvedExePath).resolveSymbolicLinksSync();
    } catch (_) {}

    final exeDir = File(resolvedExePath).parent.path;
    final candidates = <String>[
      '$exeDir/lib/libXray.so',
      '$exeDir/libXray.so',
      '/opt/CandyConnect/lib/libXray.so',
      '/opt/CandyConnect/libXray.so',
      '/usr/lib/libXray.so',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    }

    return DynamicLibrary.open('libXray.so');
  }

  /// بارگذاری ضدخطای کتابخانه Xray در اکوسیستم اپل (iOS Static Archive و macOS Bundle)
  static DynamicLibrary _openAppleLibrary() {
    final processLib = DynamicLibrary.process();
    if (processLib.providesSymbol('CGoInvoke')) {
      return processLib;
    }

    final executableLib = DynamicLibrary.executable();
    if (executableLib.providesSymbol('CGoInvoke')) {
      return executableLib;
    }

    if (Platform.isMacOS) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir/../Frameworks/libXray.dylib',
        '$exeDir/libXray.dylib',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }
    }

    return processLib;
  }

  /// فراخوانی ایمن FFI با تضمین آزادسازی حافظه Native در تمام شرایط
  static String invoke(String json) {
    if (!_initialized) init();

    final Pointer<Utf8> ptr = json.toNativeUtf8();
    Pointer<Utf8> resPtr = nullptr;

    try {
      resPtr = _invoke(ptr);
      if (resPtr == nullptr || resPtr.address == 0) return '';
      return resPtr.toDartString();
    } finally {
      malloc.free(ptr);
      if (resPtr != nullptr && resPtr.address != 0) {
        try {
          _free(resPtr);
        } catch (_) {}
      }
    }
  }

  static Future<void> startXray(
    String jsonString,
    void Function(String message) onMessage,
  ) async {
    await stopXray(); // اطمینان از بسته شدن کامل نمونه قبلی

    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _isCoreRunning = true;

    receivePort.listen((message) {
      if (message is String) {
        onMessage(message);
      }
    });

    _xrayIsolate = await Isolate.spawn(
      _runXrayInIsolate,
      [receivePort.sendPort, jsonString],
      errorsAreFatal: false,
    );
  }

  static Future<void> stopXray() async {
    if (_xrayIsolate != null || _isCoreRunning) {
      _isCoreRunning = false;
      try {
        invoke(jsonEncode({
          "apiVersion": 1,
          "method": "stopXray",
          "payload": {},
        }));
      } catch (e) {
        debugPrint('[XrayBridge] Error sending stopXray command: $e');
      }

      // فرصت کوتاه به گوروتین‌های Go برای بستن ایمن اینترفیس TUN و سوکت‌ها
      await Future.delayed(const Duration(milliseconds: 300));

      _xrayIsolate?.kill(priority: Isolate.immediate);
      _xrayIsolate = null;
    }

    _receivePort?.close();
    _receivePort = null;

    // پاکسازی فایل‌های کانفیگ موقت احتمالی به‌جامانده در پوشه Temp
    _cleanupStaleTempConfigs();
  }

  static void _cleanupStaleTempConfigs() {
    try {
      final tempDir = Directory.systemTemp;
      if (!tempDir.existsSync()) return;
      for (final entity in tempDir.listSync(followLinks: false)) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if ((fileName.startsWith('xray_config_') ||
                  fileName.startsWith('cc_bench_')) &&
              fileName.endsWith('.json')) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static void _runXrayInIsolate(List<dynamic> args) {
    final SendPort sendPort = args[0] as SendPort;
    final String jsonString = args[1] as String;
    File? tempFile;

    try {
      final tempDir = Directory.systemTemp;
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      final uniqueSuffix =
          '${DateTime.now().microsecondsSinceEpoch}_${Isolate.current.hashCode}';
      tempFile = File('${tempDir.path}/xray_config_$uniqueSuffix.json');
      tempFile.writeAsStringSync(jsonString, flush: true);

      final requestJson = jsonEncode({
        "apiVersion": 1,
        "method": "runXray",
        "payload": {"configPath": tempFile.path},
      });

      final result = XrayBridge.invoke(requestJson);
      sendPort.send(result);
    } catch (e) {
      sendPort.send(jsonEncode({"success": false, "error": e.toString()}));
    } finally {
      if (tempFile != null) {
        try {
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
        } catch (_) {}
      }
    }
  }

  /// استخراج و بررسی فایل‌های geoip.dat و geosite.dat همراه با کش در حافظه
  /// جهت جلوگیری از خواندن مجدد ۲۰ مگابایت از باندل در هر بار اتصال
  static Future<String> ensureRoutingAssets() async {
    if (_verifiedAssetDir != null) {
      final cachedDir = _verifiedAssetDir!;
      if (File('$cachedDir/geoip.dat').existsSync() &&
          File('$cachedDir/geosite.dat').existsSync()) {
        return cachedDir;
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

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
        await dest.writeAsBytes(
          assetData.buffer.asUint8List(
            assetData.offsetInBytes,
            assetData.lengthInBytes,
          ),
          flush: true,
        );
      }
    }

    _verifiedAssetDir = dir.path;
    return dir.path;
  }
}