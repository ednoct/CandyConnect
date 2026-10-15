import 'dart:convert';

class SubscriptionStats {
  final double remainingTrafficGB;
  final double trafficFraction;
  final int daysRemaining;
  final bool isUnlimitedTraffic;
  final bool isUnlimitedTime;
  final bool isExpired;

  SubscriptionStats({
    required this.remainingTrafficGB,
    required this.trafficFraction,
    required this.daysRemaining,
    required this.isUnlimitedTraffic,
    required this.isUnlimitedTime,
    required this.isExpired,
  });

  // ── Unit-aware byte parser ──────────────────────────────────────────────
  // The server's `remaining` field is a pre-formatted string that may carry a
  // unit suffix, e.g. "102.40MB", "2.5 GB", "512KB", "1.2TB".
  // We extract the numeric part and the unit separately, then convert to GB.
  // If no recognised unit is found we fall back to treating the value as raw
  // bytes (the original behaviour), which keeps compatibility with any server
  // that already sends bytes.
  static double _parseRemainingToGB(String raw) {
    // Normalise: trim whitespace, uppercase for matching.
    final s = raw.trim().toUpperCase();

    // Extract leading number (digits + optional decimal point).
    final numMatch = RegExp(r'[\d.]+').firstMatch(s);
    if (numMatch == null) return 0.0;
    final value = double.tryParse(numMatch.group(0)!) ?? 0.0;

    // Determine unit from the suffix that follows the number.
    final suffix = s.substring(numMatch.end).replaceAll(' ', '');

    if (suffix.startsWith('TB')) return value * 1024.0;
    if (suffix.startsWith('GB')) return value;
    if (suffix.startsWith('MB')) return value / 1024.0;
    if (suffix.startsWith('KB')) return value / (1024.0 * 1024.0);
    if (suffix.startsWith('B'))  return value / (1024.0 * 1024.0 * 1024.0);

    // No unit — assume raw bytes (legacy behaviour).
    return value / (1024.0 * 1024.0 * 1024.0);
  }

  factory SubscriptionStats.fromJson(String jsonString) {
    final dynamic decoded = jsonDecode(jsonString);
    final Map<String, dynamic> data =
        decoded is Map<String, dynamic> ? decoded : {};

    // ── Traffic ────────────────────────────────────────────────────────────
    // total_bytes is always raw bytes from the server.
    final double totalBytes =
        double.tryParse(data['total_bytes']?.toString() ?? '0') ?? 0.0;
    final bool isUnlimitedTraffic = totalBytes == 0;

    double remainingGB = 0.0;
    double fraction = 1.0;

    if (!isUnlimitedTraffic) {
      final String rawRem = data['remaining']?.toString() ?? '0';
      remainingGB = _parseRemainingToGB(rawRem);
      final double totalGB = totalBytes / (1024.0 * 1024.0 * 1024.0);
      fraction =
          totalGB > 0 ? (remainingGB / totalGB).clamp(0.0, 1.0) : 0.0;
    }

    // ── Time ──────────────────────────────────────────────────────────────
    // Server sends raw Unix timestamp in seconds (0 = unlimited).
    // All expiry math is done here in Dart — no JS, no <script> tag.
    final int expireTs =
        int.tryParse(data['expire_timestamp']?.toString() ?? '0') ?? 0;

    final bool isUnlimitedTime = expireTs == 0;

    bool isExpired = false;
    int daysLeft = 0;

    if (!isUnlimitedTime) {
      final DateTime expiry =
          DateTime.fromMillisecondsSinceEpoch(expireTs * 1000);
      final Duration diff = expiry.difference(DateTime.now());

      if (diff.isNegative) {
        isExpired = true;
      } else {
        // ceil so a partial day still counts as 1 remaining day.
        daysLeft = (diff.inSeconds / 86400).ceil();
      }
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