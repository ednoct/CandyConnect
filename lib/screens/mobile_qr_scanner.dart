import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart' hide BarcodeFormat;
import 'package:image/image.dart' as img;
import '../theme/app_theme.dart';

/// تابع کمکی سطح بالا برای دیکود کردن بارکد از بایت‌های تصویر در یک Isolate مجزا
/// (بدون فریز کردن رابط کاربری و مستقل از Google Play Services)
Future<String?> decodeQrFromBytesIsolate(Uint8List bytes) async {
  return Isolate.run(() {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      // بهینه‌سازی ابعاد تصاویر بزرگ برای افزایش ۱۰ برابری سرعت پردازش
      if (image.width > 1200 || image.height > 1200) {
        image = img.copyResize(
          image,
          width: image.width >= image.height ? 1000 : null,
          height: image.height > image.width ? 1000 : null,
        );
      }

      final width = image.width;
      final height = image.height;
      final pixels = Int32List(width * height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final p = image.getPixel(x, y);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          pixels[y * width + x] = (0xFF << 24) | (r << 16) | (g << 8) | b;
        }
      }

      final source = RGBLuminanceSource(width, height, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final reader = QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text.trim();
    } catch (_) {
      return null;
    }
  });
}

class MobileQRScannerScreen extends StatefulWidget {
  const MobileQRScannerScreen({super.key});

  @override
  State<MobileQRScannerScreen> createState() => _MobileQRScannerScreenState();
}

class _MobileQRScannerScreenState extends State<MobileQRScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _isProcessing = false;
  bool _torchEnabled = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? rawValue = barcodes.first.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        _isProcessing = true;
        HapticFeedback.mediumImpact();
        Navigator.pop(context, rawValue);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── پیش‌نمایش دوربین ──────────────────────────────────────────────
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),

          // ── لایه تاریک‌کننده اطراف کادر اسکن ──────────────────────────────
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.black54,
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── کادر نئونی هدف‌گیری ───────────────────────────────────────────
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.neonCyan,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonCyan.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // ── نوار ابزار بالای صفحه (بازگشت، چراغ‌قوه، چرخش دوربین) ─────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'چراغ‌قوه',
                        icon: Icon(
                          _torchEnabled
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: _torchEnabled
                              ? AppTheme.neonCyan
                              : Colors.white,
                        ),
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          await _scannerController.toggleTorch();
                          if (mounted) {
                            setState(() => _torchEnabled = !_torchEnabled);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'تغییر دوربین',
                        icon: const Icon(Icons.cameraswitch_rounded,
                            color: Colors.white),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _scannerController.switchCamera();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── بخش پایینی: راهنمای اسکن ──────────────────────────────────────
          const Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'کد QR لایسنس را در کادر قرار دهید',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'بارکد به صورت خودکار و فوق سریع شناسایی می‌شود',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}