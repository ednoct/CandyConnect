import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlLauncherUtils {
  static const String _defaultBotHandle = 'CandyConnectbot';

  /// باز کردن پشتیبانی یا ربات تلگرام با قابلیت دریافت هندل پویا از RemoteConfig
  /// و پشتیبانی از لینک مستقیم اپلیکیشن تلگرام (tg://) همراه با پشتیبان مرورگر (https://)
  static Future<void> launchTelegramSupport({
    String? customHandle,
    String? startParam,
  }) async {
    final String handle = _sanitizeHandle(customHandle ?? _defaultBotHandle);
    final String cleanStart = startParam?.trim() ?? '';

    final String tgQuery = cleanStart.isNotEmpty
        ? 'domain=$handle&start=${Uri.encodeComponent(cleanStart)}'
        : 'domain=$handle';
    final String webQuery = cleanStart.isNotEmpty
        ? '?start=${Uri.encodeComponent(cleanStart)}'
        : '';

    final Uri appUri = Uri.parse('tg://resolve?$tgQuery');
    final Uri webUri = Uri.parse('https://t.me/$handle$webQuery');

    try {
      final bool launched = await launchUrl(
        appUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[UrlLauncherUtils] App URI failed, falling back to web: $e');
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (err) {
        debugPrint('[UrlLauncherUtils] Web fallback also failed: $err');
      }
    }
  }

  /// حذف کاراکتر @ یا پیشوند لینک در صورتی که در کانفیگ به صورت کامل وارد شده باشد
  static String _sanitizeHandle(String raw) {
    String s = raw.trim();
    if (s.isEmpty) return _defaultBotHandle;
    if (s.startsWith('@')) {
      s = s.substring(1).trim();
    }
    if (s.contains('t.me/')) {
      s = s.split('t.me/').last.split('?').first.replaceAll('/', '').trim();
    }
    return s.isEmpty ? _defaultBotHandle : s;
  }
}