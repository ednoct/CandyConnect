import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:zxing2/qrcode.dart';
import 'package:image/image.dart' as img;
import '../providers/app_providers.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_wave_background.dart';
import '../theme/app_theme.dart';
import '../services/remote_config_service.dart';
import '../services/subscription_service.dart';
import '../utils/url_launcher_utils.dart';
import 'home_screen.dart';
import 'mobile_qr_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _licenseController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    final license = _licenseController.text.trim();
    if (license.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final config = await RemoteConfigService().fetchConfig();
      if (config == null) {
        setState(() {
          _errorMessage = "خطا در دریافت تنظیمات سرور دوباره امتحان کنید";
        });
        return;
      }
      ref.read(remoteConfigProvider.notifier).state = config;

      final subService = SubscriptionService(
        config.apiEndpoints.baseJsonSubUrl,
        config.apiEndpoints.baseSubsStatsUrl.isNotEmpty ? config.apiEndpoints.baseSubsStatsUrl.first : '',
      );

      final subscription = await subService.fetchSubscription(license);
      if (subscription != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('license_key', license);
        
        ref.read(currentLicenseProvider.notifier).state = license;
        ref.read(subscriptionJsonProvider.notifier).state = subscription;
        if (!mounted) return;
        ref.read(navIndexProvider.notifier).state = 0;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      } else {
        setState(() {
          _errorMessage = "خطا در اتصال اولیه دوباره امتحان کنید!";
        });
      }
    } on InvalidLicenseException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "خطا در اتصال اولیه به سرور دوباره امتحان کنید!";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleQRScan() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        CapturedData? capturedData = await screenCapturer.capture(
          mode: CaptureMode.region,
        );
        if (capturedData != null && capturedData.imageBytes != null) {
          final image = img.decodeImage(capturedData.imageBytes!);
          if (image != null) {
            final pixels = Int32List(image.width * image.height);
            for (int y = 0; y < image.height; y++) {
              for (int x = 0; x < image.width; x++) {
                final p = image.getPixel(x, y);
                final r = p.r.toInt();
                final g = p.g.toInt();
                final b = p.b.toInt();
                pixels[y * image.width + x] = (0xFF << 24) | (r << 16) | (g << 8) | b;
              }
            }
            final source = RGBLuminanceSource(image.width, image.height, pixels);
            final bitmap = BinaryBitmap(HybridBinarizer(source));
            final reader = QRCodeReader();
            final result = reader.decode(bitmap);
            setState(() {
              _licenseController.text = result.text;
            });
          }

        }
      } catch (e) {
        debugPrint('QR Scan error: $e');
      }
    } else if (Platform.isAndroid || Platform.isIOS) {
      final scannedCode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const MobileQRScannerScreen()),
      );

      if (scannedCode != null && scannedCode.isNotEmpty) {
        setState(() {
          _licenseController.text = scannedCode;
        });
      }
    }
  }

  void _openTelegramSupport() {
    UrlLauncherUtils.launchTelegramSupport(); // Using existing util if it points to CandyConnectbot, or directly:
    // launchUrl(Uri.parse('tg://resolve?domain=CandyConnectbot'));
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = _errorMessage != null && _errorMessage!.contains("لایسنس شما نامعتبر است");

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedWaveBackground(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: GlassCard(
                height: 480,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'کندی کانکت',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppTheme.neonCyan,
                            fontFamily: 'Vazirmatn',
                            fontWeight: FontWeight.bold,
                            shadows: [
                              const Shadow(color: AppTheme.neonCyan, blurRadius: 10)
                            ],
                          ),
                    ),
                    const SizedBox(height: 40),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppTheme.errorRed, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (!hasError) ...[
                      TextField(
                        controller: _licenseController,
                        decoration: InputDecoration(
                          labelText: 'لایسنس خود را وارد کنید',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _handleQRScan,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonPurple,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('ورود', style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _openTelegramSupport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('خرید لایسنس', style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _openTelegramSupport,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text('خرید لایسنس', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _openTelegramSupport,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[800],
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text('پشتیبانی', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                            _licenseController.clear();
                          });
                        },
                        child: const Text('بازگشت', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
