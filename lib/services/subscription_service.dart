import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/subscription_stats.dart';

class SubscriptionService {
  final String baseSubUrl;
  final String baseStatsUrl;
  final List<String> failoverSubUrls;
  final List<String> failoverStatsUrls;

  SubscriptionService(
    this.baseSubUrl,
    this.baseStatsUrl, {
    this.failoverSubUrls = const [],
    this.failoverStatsUrls = const [],
  });

  /// استخراج تمیز کلید لایسنس (اگر کاربر به اشتباه کل لینک را کپی کرده باشد، فقط توکن انتهایی را جدا می‌کند)
  static String _sanitizeLicense(String rawLicense) {
    String cleaned = rawLicense.trim();
    if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
      final uri = Uri.tryParse(cleaned);
      if (uri != null) {
        if (uri.queryParameters.containsKey('id')) {
          return uri.queryParameters['id']!.trim();
        }
        if (uri.pathSegments.isNotEmpty) {
          return uri.pathSegments.last.trim();
        }
      }
    }
    return cleaned;
  }

  /// ساخت امن آدرس نهایی بدون ایجاد اسلش تکراری یا خطای کاراکترهای خاص
  static Uri? _buildEndpointUri(String baseUrl, String rawLicense) {
    final trimmedBase = baseUrl.trim();
    final cleanLicense = _sanitizeLicense(rawLicense);
    if (trimmedBase.isEmpty || cleanLicense.isEmpty) return null;

    final encodedLicense = Uri.encodeComponent(cleanLicense);
    return Uri.tryParse('$trimmedBase$encodedLicense');
  }

  Future<List<dynamic>?> fetchSubscription(String license) async {
    final candidateUrls = <String>[
      if (baseSubUrl.trim().isNotEmpty) baseSubUrl.trim(),
      ...failoverSubUrls.where((u) => u.trim().isNotEmpty),
    ];

    if (candidateUrls.isEmpty) return null;

    for (final urlPrefix in candidateUrls) {
      final uri = _buildEndpointUri(urlPrefix, license);
      if (uri == null) continue;

      try {
        final response = await http.get(
          uri,
          headers: {
            'User-Agent': 'CandyConnect/1.0.0',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final String utf8Body = utf8.decode(response.bodyBytes).trim();
          final dynamic decoded = jsonDecode(utf8Body);
          if (decoded is List<dynamic>) {
            return decoded;
          } else if (decoded is Map<String, dynamic> &&
              decoded['outbounds'] is List) {
            return [decoded];
          }
        } else if (response.statusCode == 404 ||
            response.statusCode == 401 ||
            response.statusCode == 403) {
          throw InvalidLicenseException();
        }
      } on InvalidLicenseException {
        rethrow;
      } catch (e) {
        debugPrint(
            '[SubscriptionService.fetchSubscription] Endpoint failed ($urlPrefix): $e');
      }
    }

    return null;
  }

  Future<SubscriptionStats?> fetchStats(String license) async {
    final candidateUrls = <String>[
      if (baseStatsUrl.trim().isNotEmpty) baseStatsUrl.trim(),
      ...failoverStatsUrls.where((u) => u.trim().isNotEmpty),
    ];

    if (candidateUrls.isEmpty || license.trim().isEmpty) return null;

    for (final urlPrefix in candidateUrls) {
      final uri = _buildEndpointUri(urlPrefix, license);
      if (uri == null) continue;

      try {
        final response = await http.get(
          uri,
          headers: {
            'User-Agent': 'Chrome/120.0.0.0',
            'Accept': 'application/json, text/html, application/xhtml+xml',
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final String utf8Body = utf8.decode(response.bodyBytes).trim();
          final dynamic decoded = jsonDecode(utf8Body);
          if (decoded is Map<String, dynamic>) {
            return SubscriptionStats.fromMap(decoded);
          }
        }
      } catch (e) {
        debugPrint(
            '[SubscriptionService.fetchStats] Stats endpoint failed ($urlPrefix): $e');
      }
    }

    return null;
  }
}

class InvalidLicenseException implements Exception {
  final String message =
      "لایسنس شما نامعتبر است اگر به اعتبار آن اطمینان دارید با پشتیبانی تماس بگیرید در غیر اینصورت اشتراک لایسنس خریداری کنید";

  @override
  String toString() => message;
}