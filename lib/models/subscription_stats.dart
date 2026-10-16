import 'dart:convert';

class SubscriptionStats {
  final double remainingTrafficGB;
  final double trafficFraction;
  final int daysRemaining;
  final bool isUnlimitedTraffic;
  final bool isUnlimitedTime;
  final bool isExpired;

  const SubscriptionStats({
    required this.remainingTrafficGB,
    required this.trafficFraction,
    required this.daysRemaining,
    required this.isUnlimitedTraffic,
    required this.isUnlimitedTime,
    required this.isExpired,
  });

  /// پارس هوشمند حجم باقیمانده با پشتیبانی از اعداد منفی، اعشاری و واحدهای مختلف
  static double _parseRemainingToGB(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) return 0.0;

    // تشخیص علامت منفی (در صورتی که کاربر بیش از سقف مجاز مصرف کرده باشد)
    final numMatch = RegExp(r'-?[\d.]+').firstMatch(s);
    if (numMatch == null) return 0.0;

    final value = double.tryParse(numMatch.group(0)!) ?? 0.0;
    if (value <= 0) return 0.0;

    final suffix = s.substring(numMatch.end).replaceAll(' ', '');

    if (suffix.startsWith('TB') || suffix.startsWith('TIB')) {
      return value * 1024.0;
    }
    if (suffix.startsWith('GB') || suffix.startsWith('GIB')) {
      return value;
    }
    if (suffix.startsWith('MB') || suffix.startsWith('MIB')) {
      return value / 1024.0;
    }
    if (suffix.startsWith('KB') || suffix.startsWith('KIB')) {
      return value / (1024.0 * 1024.0);
    }
    if (suffix.startsWith('B')) {
      return value / (1024.0 * 1024.0 * 1024.0);
    }

    // اگر واحدی ذکر نشده بود، بر حسب بایت خام محاسبه می‌شود
    return value / (1024.0 * 1024.0 * 1024.0);
  }

  factory SubscriptionStats.fromJson(String jsonString) {
    final dynamic decoded = jsonDecode(jsonString);
    final Map<String, dynamic> data =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    return SubscriptionStats.fromMap(data);
  }

  factory SubscriptionStats.fromMap(Map<String, dynamic> data) {
    // ── ۱. محاسبه وضعیت ترافیک ──────────────────────────────────────────────
    final double totalBytes =
        double.tryParse(data['total_bytes']?.toString() ?? '0') ?? 0.0;
    final bool isUnlimitedTraffic = totalBytes <= 0;

    double remainingGB = 0.0;
    double fraction = 1.0;

    if (!isUnlimitedTraffic) {
      final String rawRem = data['remaining']?.toString() ?? '0';
      remainingGB = _parseRemainingToGB(rawRem).clamp(0.0, double.infinity);
      final double totalGB = totalBytes / (1024.0 * 1024.0 * 1024.0);
      fraction = totalGB > 0 ? (remainingGB / totalGB).clamp(0.0, 1.0) : 0.0;
    }

    // ── ۲. محاسبه وضعیت زمان و انقضا ────────────────────────────────────────
    // پشتیبانی همزمان از اعداد صحیح، اعشاری، ثانیه، میلی‌ثانیه و اکانت‌های On-Hold (منفی در 3x-ui)
    final double rawExpireNum =
        double.tryParse(data['expire_timestamp']?.toString() ?? '0') ?? 0.0;
    final int expireTs = rawExpireNum.round();

    final bool isUnlimitedTime = expireTs == 0;
    bool isExpired = false;
    int daysLeft = 0;

    if (!isUnlimitedTime) {
      if (expireTs < 0) {
        // در 3x-ui تایم‌استمپ منفی یعنی اشتراک «شروع پس از اولین اتصال» است و هنوز منقضی نشده
        final int absVal = expireTs.abs();
        final int durationSeconds =
            absVal > 1000000000 ? (absVal ~/ 1000) : absVal;
        daysLeft = (durationSeconds / 86400).ceil().clamp(1, 3650);
        isExpired = false;
      } else {
        // تشخیص خودکار ثانیه (۱۰ رقمی) در برابر میلی‌ثانیه (۱۳ رقمی)
        final int expiryMillis =
            expireTs > 10000000000 ? expireTs : expireTs * 1000;
        final DateTime expiry =
            DateTime.fromMillisecondsSinceEpoch(expiryMillis);
        final Duration diff = expiry.difference(DateTime.now());

        if (diff.isNegative) {
          isExpired = true;
          daysLeft = 0;
        } else {
          daysLeft = (diff.inSeconds / 86400).ceil();
        }
      }
    }

    // بررسی فلگ صریح وضعیت در صورت ارسال از سمت سرور
    final String statusFlag =
        (data['status'] ?? '').toString().trim().toLowerCase();
    final bool ExplicitlyDisabled =
        data['enable'] == false || statusFlag == 'expired' || statusFlag == 'disabled';

    if (ExplicitlyDisabled || (!isUnlimitedTraffic && remainingGB <= 0)) {
      isExpired = true;
    }

    return SubscriptionStats(
      remainingTrafficGB: remainingGB,
      trafficFraction: fraction,
      daysRemaining: daysLeft,
      isUnlimitedTraffic: isUnlimitedTraffic,
      isUnlimitedTime: isUnlimitedTime,
      isExpired: isExpired,
    );
  }
}