import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart';
import 'package:image/image.dart' as img;
import '../theme/app_theme.dart';

/// تابع کمکی سطح بالا برای دیکود کردن بارکد از بایت‌های تصویر در یک Isolate مجزا
/// (بدون فریز کردن رابط کاربری و مستقل از Google Play Services)
Future<String?> decodeQrFromBytesIsolate(Uint8List bytes) async {
  return Isolate.run(() {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      // بهینه‌سازی ابعاد تصاویر بزرگ گالری برای افزایش ۱۰ برابری سرعت پردازش
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
  final ImagePicker _imagePicker = ImagePicker();

  bool _isProcessing = false;
  bool _isAnalyzingGallery = false;
  bool _torchEnabled = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || _isAnalyzingGallery) return;

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

  /// انتخاب تصویر بارکد از گالری با پشتیبانی دوگانه (MLKit + ZXing2 Fallback)
  Future<void> _pickFromGallery() async {
    if (_isProcessing || _isAnalyzingGallery) return;

    try {
      HapticFeedback.lightImpact();
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile == null || !mounted) return;

      setState(() => _isAnalyzingGallery = true);

      String? extractedCode;

      // تلاش اول: استفاده از موتور بومی MobileScanner
      try {
        final BarcodeCapture? capture =
            await _scannerController.analyzeImage(pickedFile.path);
        if (capture != null && capture.barcodes.isNotEmpty) {
          extractedCode = capture.barcodes.first.rawValue?.trim();
        }
      } catch (_) {
        // در صورت عدم پشتیبانی دستگاه از Google MLKit، به موتور دوم می‌رویم
      }

      // تلاش دوم (پشتیبان قطعی): دیکود در ایزوله پس‌زمینه با ZXing2
      if (extractedCode == null || extractedCode.isEmpty) {
        final bytes = await File(pickedFile.path).readAsBytes();
        extractedCode = await decodeQrFromBytesIsolate(bytes);
      }

      if (!mounted) return;

      if (extractedCode != null && extractedCode.isNotEmpty) {
        _isProcessing = true;
        HapticFeedback.heavyImpact();
        Navigator.pop(context, extractedCode);
      } else {
        setState(() => _isAnalyzingGallery = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'هیچ کد QR معتبری در تصویر انتخابی یافت نشد!',
              style: TextStyle(color: Colors.white, fontFamily: 'Vazirmatn'),
            ),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzingGallery = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'خطا در خواندن تصویر از گالری',
              style: TextStyle(color: Colors.white, fontFamily: 'Vazirmatn'),
            ),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
              child: _isAnalyzingGallery
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppTheme.neonCyan),
                          SizedBox(height: 12),
                          Text(
                            'در حال استخراج بارکد از تصویر...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'Vazirmatn',
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
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

          // ── بخش پایینی: راهنما + دکمه انتخاب بارکد از گالری ──────────────
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'کد QR لایسنس را در کادر قرار دهید',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'یا تصویر بارکد ذخیره‌شده را از گالری انتخاب کنید',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzingGallery ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library_rounded,
                        color: Colors.black, size: 22),
                    label: const Text(
                      'انتخاب تصویر بارکد از گالری',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        fontFamily: 'Vazirmatn',
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonCyan,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
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