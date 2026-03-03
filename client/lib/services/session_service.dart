import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'auth_service.dart';

class SessionInfo {
  final String key;
  String title;
  final String? lastMessage;
  final int updatedAt;

  SessionInfo({
    required this.key,
    required this.title,
    this.lastMessage,
    required this.updatedAt,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
        key: j['key'] ?? '',
        title: j['title'] ?? '新对话',
        lastMessage: j['lastMessage'],
        updatedAt: j['updated_at'] ?? 0,
      );
}

class SessionService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      };

  static Future<List<SessionInfo>> listSessions() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/sessions'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['ok'] == true) {
        return (data['sessions'] as List)
            .map((e) => SessionInfo.fromJson(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<SessionInfo?> createSession() async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/sessions'),
        headers: _headers,
      );
      final data = jsonDecode(res.body);
      if (data['ok'] == true) {
        return SessionInfo.fromJson(data['session']);
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> renameSession(String key, String title) async {
    try {
      final res = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/sessions/$key'),
        headers: _headers,
        body: jsonEncode({'title': title}),
      );
      return jsonDecode(res.body)['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteSession(String key) async {
    try {
      final res = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/sessions/$key'),
        headers: _headers,
      );
      return jsonDecode(res.body)['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
