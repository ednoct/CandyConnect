import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/remote_config.dart';

class RemoteConfigService {
  static const String _configUrl = 'https://api.github.com/repos/ednoct/private/contents/config.json?ref=main';
  // Keep the token as user requested
  static const String _githubToken = 'CANDY_PAT'; 

  Future<RemoteConfig?> fetchConfig() async {
    try {
      final response = await http.get(Uri.parse(_configUrl), headers: {
        'Authorization': 'token $_githubToken', 
        'Accept': 'application/vnd.github.v3.raw', 
        'Cache-Control': 'no-cache', 
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return RemoteConfig.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
