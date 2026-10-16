import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_config.dart';

class RemoteConfigService {
  static const String _configUrl =
      'https://api.github.com/repos/ednoct/private/contents/config.json?ref=main';

  // پشتیبانی همزمان از تزریق با sed و هر دو پرچم --dart-define در release.yml
  static const String _defaultToken = 'CANDY_PAT';
  static const String _envCandyPat = String.fromEnvironment('CANDY_PAT');
  static const String _envRemotePat =
      String.fromEnvironment('REMOTE_CONFIG_PAT');

  static String get _githubToken {
    if (_envCandyPat.isNotEmpty && _envCandyPat != 'CANDY_PAT') {
      return _envCandyPat;
    }
    if (_envRemotePat.isNotEmpty && _envRemotePat != 'CANDY_PAT') {
      return _envRemotePat;
    }
    return _defaultToken;
  }

  static const String _cacheKey = 'cached_remote_config_json';

  Future<RemoteConfig?> fetchConfig() async {
    try {
      final response = await http.get(
        Uri.parse(_configUrl),
        headers: {
          'Authorization': 'token $_githubToken',
          'Accept': 'application/vnd.github.v3.raw',
          'Cache-Control': 'no-cache',
          'User-Agent': 'CandyConnect-Client',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final String utf8Body = utf8.decode(response.bodyBytes);
        final dynamic decoded = jsonDecode(utf8Body);
        if (decoded is Map<String, dynamic>) {
          final config = RemoteConfig.fromJson(decoded);
          await _saveCache(utf8Body);
          return config;
        }
      }
    } catch (e) {
      debugPrint('[RemoteConfigService] Network fetch failed: $e');
    }

    // در صورت اختلال موقت اینترنت یا مسدود بودن گیت‌هاب، از آخرین کانفیگ سالم کش‌شده استفاده کن
    return _loadFromCache();
  }

  Future<void> _saveCache(String rawJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, rawJson);
    } catch (_) {}
  }

  Future<RemoteConfig?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) {
          debugPrint('[RemoteConfigService] Loaded config from local cache.');
          return RemoteConfig.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('[RemoteConfigService] Cache load failed: $e');
    }
    return null;
  }
}