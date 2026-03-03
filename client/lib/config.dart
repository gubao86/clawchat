import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AppConfig {
  static const _storage = FlutterSecureStorage();
  static String _baseUrl = '';
  static String _wsUrl = '';

  static String get baseUrl => _baseUrl;
  static String get wsUrl => _wsUrl;

  static Future<bool> load() async {
    final url = await _storage.read(key: 'server_url');
    if (url != null && url.isNotEmpty) {
      _setUrl(url);
      return true;
    }
    return false;
  }

  static void _setUrl(String url) {
    _baseUrl = url.startsWith('http') ? url : 'http://$url';
    _wsUrl = _baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    if (!_wsUrl.endsWith('/ws')) _wsUrl += '/ws';
  }

  static Future<void> save(String url) async {
    final trimmed = url.trim();
    await _storage.write(key: 'server_url', value: trimmed);
    _setUrl(trimmed);
  }

  static Future<bool> ping() async {
    if (_baseUrl.isEmpty) return false;
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/ping'))
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(res.body);
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
