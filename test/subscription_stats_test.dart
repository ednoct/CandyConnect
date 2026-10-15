// test/subscription_stats_test.dart
// Validates SubscriptionStats.fromJson against the 6-case test matrix.
// Run with:  flutter test test/subscription_stats_test.dart
//
// No external package required — uses only dart:core and the local model.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:candyconnect/models/subscription_stats.dart';

void main() {
  // Helper to build a future timestamp relative to now.
  String futureTs(int days) =>
      ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + days * 86400)
          .toString();
  String pastTs(int days) =>
      ((DateTime.now().millisecondsSinceEpoch ~/ 1000) - days * 86400)
          .toString();

  group('SubscriptionStats.fromJson — test matrix', () {
    // ── Case 1: fully unlimited ──────────────────────────────────────────────
    test('Case 1: total_bytes="0", expire_timestamp="0" → fully unlimited', () {
      const raw = '{"remaining":"","total_bytes":"0","expire_timestamp":"0"}';
      final s = SubscriptionStats.fromJson(raw);
      expect(s.isUnlimitedTraffic, isTrue,
          reason: 'traffic should be unlimited');
      expect(s.isUnlimitedTime, isTrue, reason: 'time should be unlimited');
      expect(s.isExpired, isFalse);
      // fraction in home_screen: unlimited → 1.0 (bars fully lit)
    });

    // ── Case 2: server-side expired flag ─────────────────────────────────────
    test('Case 2: expire_timestamp="-1" → isExpiredTime=true', () {
      const raw =
          '{"remaining":"0.00B","total_bytes":"107374182","expire_timestamp":"-1"}';
      final s = SubscriptionStats.fromJson(raw);
      expect(s.isExpired, isTrue);
      expect(s.isUnlimitedTime, isFalse);
      expect(s.isUnlimitedTraffic, isFalse);
    });

    // ── Case 3: 50 GB of 100 GB, future expiry ───────────────────────────────
    test('Case 3: 50 GB of 100 GB, ~45 days remaining', () {
      final raw = jsonEncode({
        'remaining': '53687091200',   // 50 * 1024^3 bytes
        'total_bytes': '107374182400', // 100 * 1024^3 bytes
        'expire_timestamp': futureTs(45),
      });
      final s = SubscriptionStats.fromJson(raw);
      expect(s.isUnlimitedTraffic, isFalse);
      expect(s.isUnlimitedTime, isFalse);
      expect(s.isExpired, isFalse);
      expect(s.remainingTrafficGB, closeTo(50.0, 0.5));
      expect(s.daysRemaining, inInclusiveRange(44, 46));
    });

    // ── Case 4: 1 GB of 10 GB, unlimited time ────────────────────────────────
    test('Case 4: 1 GB of 10 GB, unlimited time', () {
      const raw =
          '{"remaining":"1073741824","total_bytes":"10737418240","expire_timestamp":"0"}';
      final s = SubscriptionStats.fromJson(raw);
      expect(s.isUnlimitedTraffic, isFalse);
      expect(s.isUnlimitedTime, isTrue);
      // 1 GB / 10 GB = 10 % → danger zone
      expect(s.remainingTrafficGB, closeTo(1.0, 0.05));
      expect(s.trafficFraction, closeTo(0.10, 0.02), reason: 'should be ~10%');
    });

    // ── Case 5: stale past timestamp → daysRemaining clamped to 0 ────────────
    test('Case 5: past timestamp → daysRemaining==0 (never negative)', () {
      final raw = jsonEncode({
        'remaining': '0B',
        'total_bytes': '5368709120',
        'expire_timestamp': pastTs(10),
      });
      final s = SubscriptionStats.fromJson(raw);
      expect(s.daysRemaining, equals(0),
          reason: 'days must be clamped to 0, never negative');
      expect(s.isExpired, isFalse,
          reason: 'isExpired is only for the -1 sentinel');
      // The UI treats daysRemaining <= 0 as expired-display even when isExpiredTime is false.
    });

    // ── Case 6: missing `remaining` key → degrade to 0 remaining ─────────────
    test('Case 6: missing "remaining" key → no throw, 0 remaining', () {
      const raw = '{"total_bytes":"5368709120"}';
      SubscriptionStats? s;
      expect(() => s = SubscriptionStats.fromJson(raw), returnsNormally);
      // With remaining absent → treated as "0" → remainingTrafficGB ≈ 0
      expect(s!.remainingTrafficGB, closeTo(0.0, 0.01));
    });
  });
}
