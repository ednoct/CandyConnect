import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subscription_stats.dart';

class SubscriptionService {
  final String baseSubUrl;
  final String baseStatsUrl;

  SubscriptionService(this.baseSubUrl, this.baseStatsUrl);

  Future<List<dynamic>?> fetchSubscription(String license) async {
    try {
      final response = await http.get(
        Uri.parse('$baseSubUrl$license'),
        headers: {'User-Agent': 'CandyConnect/1.0.0'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else if (response.statusCode == 404) {
        throw InvalidLicenseException();
      }
      return null;
    } on InvalidLicenseException {
      rethrow;
    } catch (e) {
      return null;
    }
  }

Future<SubscriptionStats?> fetchStats(String license) async {
  if (baseStatsUrl.isEmpty || license.isEmpty) return null;

  try {
    final response = await http.get(
      Uri.parse('$baseStatsUrl$license'),
      headers: {
        'User-Agent': 'Chrome/120.0.0.0',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return SubscriptionStats.fromJson(response.body);
      }
    }
  } catch (_) {}

  return null;
  }
}

class InvalidLicenseException implements Exception {
  final String message = "لایسنس شما نامعتبر است اگر به اعتبار آن اطمینان دارید با پشتیبانی تماس بگیرید در غیر اینصورت اشتراک لایسنس خریداری کنید";
}
