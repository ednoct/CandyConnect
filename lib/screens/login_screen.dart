import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_providers.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_wave_background.dart';
import '../theme/app_theme.dart';
import '../services/remote_config_service.dart';
import '../services/subscription_service.dart';
import '../utils/url_launcher_utils.dart';
import 'home_screen.dart';
import 'mobile_qr_scanner.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _licenseController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = false;
  bool _isInvalidLicense = false;
  String? _errorMessage;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final license = _licenseController.text.trim();
    if (license.isEmpty) {
      setState(() {
        _errorMessage = 'لطفاً کلید لایسنس خود را وارد یا اسکن کنید.';
        _isInvalidLicense = false;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isInvalidLicense = false;
    });

    try {
      final config = await RemoteConfigService().fetchConfig();
      if (config == null) {
        if (mounted) {
          setState(() {
            _errorMessage =
                'خطا در دریافت تنظیمات سرور؛ لطفاً دوباره تلاش کنید.';
          });
        }
        return;
      }
      ref.read(remoteConfigProvider.notifier).state = config;

      final subService = SubscriptionService(
        config.apiEndpoints.baseJsonSubUrl,
        config.apiEndpoints.baseSubsStatsUrl.isNotEmpty
            ? config.apiEndpoints.baseSubsStatsUrl.first
            : '',
        failoverSubUrls: config.apiEndpoints.failoverApiUrls,
        failoverStatsUrls: config.apiEndpoints.baseSubsStatsUrl.length > 1
            ? config.apiEndpoints.baseSubsStatsUrl.sublist(1)
            : const [],
      );

      final subscription = await subService.fetchSubscription(license);
      if (subscription != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('license_key', license);

        // پاکسازی استیت‌های قبلی و مقداردهی اکانت جدید
        ref.read(subscriptionStatsProvider.notifier).state = null;
        ref.read(isPromoDismissedProvider.notifier).state = false;
        ref.read(currentLicenseProvider.notifier).state = license;
        ref.read(subscriptionJsonProvider.notifier).state = subscription;
        ref.read(navIndexProvider.notifier).state = 0;

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'خطا در اتصال اولیه؛ لطفاً دوباره امتحان کنید!';
          });
        }
      }
    } on InvalidLicenseException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isInvalidLicense = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'خطا در برقراری ارتباط با سرور؛ لطفاً دوباره تلاش کنید!';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// جایگذاری سریع متن لایسنس از کلیپ‌بورد
  Future<void> _pasteFromClipboard() async {
    HapticFeedback.selectionClick();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty && mounted) {
      setState(() {
        _licenseController.text = text;
        _errorMessage = null;
        _isInvalidLicense = false;
      });
    }
  }

  /// انتخاب مستقیم تصویر بارکد از گالری (در صفحه لاگین)
  Future<void> _handleGalleryQRPick() async {
    try {
      HapticFeedback.lightImpact();
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile == null || !mounted) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final bytes = await File(pickedFile.path).readAsBytes();
      final decodedText = await decodeQrFromBytesIsolate(bytes);

      if (!mounted) return;

      if (decodedText != null && decodedText.isNotEmpty) {
        setState(() {
          _licenseController.text = decodedText;
          _isLoading = false;
        });
        await _login();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'هیچ بارکد معتبری در تصویر انتخابی یافت نشد.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'خطا در بارگذاری تصویر از گالری.';
        });
      }
    }
  }

  /// اسکن بارکد (در دسکتاپ از روی صفحه نمایش، در موبایل با دوربین + گالری)
  Future<void> _handleQRScan() async {
    HapticFeedback.lightImpact();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final CapturedData? capturedData = await screenCapturer.capture(
          mode: CaptureMode.region,
        );
        if (capturedData != null && capturedData.imageBytes != null) {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });

          final decodedText =
              await decodeQrFromBytesIsolate(capturedData.imageBytes!);

          if (!mounted) return;

          if (decodedText != null && decodedText.isNotEmpty) {
            setState(() {
              _licenseController.text = decodedText;
              _isLoading = false;
            });
            await _login();
          } else {
            setState(() {
              _isLoading = false;
              _errorMessage = 'بارکدی در ناحیه انتخاب‌شده تشخیص داده نشد.';
            });
          }
        }
      } catch (e) {
        debugPrint('Desktop QR Scan error: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'خطا در اسکن صفحه نمایش.';
          });
        }
      }
    } else if (Platform.isAndroid || Platform.isIOS) {
      final scannedCode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const MobileQRScannerScreen()),
      );

      if (scannedCode != null && scannedCode.isNotEmpty && mounted) {
        setState(() {
          _licenseController.text = scannedCode.trim();
          _errorMessage = null;
          _isInvalidLicense = false;
        });
        await _login();
      }
    }
  }

  void _openTelegramSupport() {
    HapticFeedback.lightImpact();
    final botHandle =
        ref.read(remoteConfigProvider)?.clientPreferences.telegramBotHandle;
    UrlLauncherUtils.launchTelegramSupport(customHandle: botHandle);
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedWaveBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 36.0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'کندی کانکت',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: AppTheme.neonCyan,
                                fontFamily: 'Vazirmatn',
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(
                                    color: AppTheme.neonCyan,
                                    blurRadius: 12,
                                  )
                                ],
                              ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'نسل جدید ارتباط امن و پایدار',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 32),

                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.errorRed.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color:
                                      AppTheme.errorRed.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppTheme.errorRed,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),

                        if (!_isInvalidLicense) ...[
                          TextField(
                            controller: _licenseController,
                            enabled: !_isLoading,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'لایسنس خود را وارد کنید',
                              labelStyle:
                                  const TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppTheme.neonCyan, width: 1.5),
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'جایگذاری از کلیپ‌بورد',
                                    icon: const Icon(
                                      Icons.content_paste_rounded,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    onPressed:
                                        _isLoading ? null : _pasteFromClipboard,
                                  ),
                                  if (isMobile)
                                    IconButton(
                                      tooltip: 'انتخاب بارکد از گالری',
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                        color: AppTheme.neonCyan,
                                        size: 21,
                                      ),
                                      onPressed: _isLoading
                                          ? null
                                          : _handleGalleryQRPick,
                                    ),
                                  IconButton(
                                    tooltip: isMobile
                                        ? 'اسکن بارکد با دوربین'
                                        : 'اسکن بارکد از صفحه نمایش',
                                    icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                      color: AppTheme.neonCyan,
                                    ),
                                    onPressed:
                                        _isLoading ? null : _handleQRScan,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.neonPurple,
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'ورود به اشتراک',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _openTelegramSupport,
                            icon: const Icon(
                              Icons.shopping_cart_checkout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            label: const Text(
                              'خرید لایسنس جدید',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _openTelegramSupport,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    minimumSize:
                                        const Size(double.infinity, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'خرید لایسنس',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _openTelegramSupport,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[800],
                                    minimumSize:
                                        const Size(double.infinity, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'پشتیبانی',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                                _isInvalidLicense = false;
                                _licenseController.clear();
                              });
                            },
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: Colors.white70, size: 18),
                            label: const Text(
                              'تلاش مجدد با لایسنس دیگر',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}