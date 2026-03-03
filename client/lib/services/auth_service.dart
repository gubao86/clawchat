import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static String? _token;
  static String? _username;
  static String? _role;
  static String? get token => _token;
  static String? get username => _username;
  static String? get role => _role;
  static bool get isLoggedIn => _token != null;
  static bool get isAdmin => _role == 'admin';

  static Future<void> init() async {
    _token    = await _storage.read(key: 'token');
    _username = await _storage.read(key: 'username');
    _role     = await _storage.read(key: 'role');
  }

  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
  };

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 200 && data['ok'] == true) {
      _token    = data['token'];
      _username = data['user']['username'];
      _role     = data['user']['role'] ?? 'user';
      await _storage.write(key: 'token',    value: _token);
      await _storage.write(key: 'username', value: _username);
      await _storage.write(key: 'role',     value: _role);
    }
    return data;
  }

  static Future<Map<String, dynamic>> register(
      String username, String password, {String? inviteCode}) async {
    final body = <String, dynamic>{
      'username': username,
      'password': password,
    };
    if (inviteCode != null && inviteCode.isNotEmpty) {
      body['inviteCode'] = inviteCode;
    }
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 200 && data['ok'] == true) {
      _token    = data['token'];
      _username = data['user']['username'];
      _role     = data['user']['role'] ?? 'user';
      await _storage.write(key: 'token',    value: _token);
      await _storage.write(key: 'username', value: _username);
      await _storage.write(key: 'role',     value: _role);
    }
    return data;
  }

  // 查询是否首位用户（无需邀请码）
  static Future<bool> checkIsFirstUser() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.baseUrl}/auth/check-first'));
      final data = jsonDecode(res.body);
      return data['isFirst'] == true;
    } catch (_) {
      return false;
    }
  }

  // Token 续期：POST /auth/refresh，成功则更新本地 Token
  static Future<void> refreshToken() async {
    if (_token == null) return;
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/auth/refresh'),
        headers: _authHeaders,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['ok'] == true && data['token'] != null) {
          _token = data['token'];
          await _storage.write(key: 'token', value: _token);
        }
      }
    } catch (_) {}
  }

  // 修改密码
  static Future<Map<String, dynamic>> changePassword(
      String oldPassword, String newPassword) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/change-password'),
      headers: _authHeaders,
      body: jsonEncode({'oldPassword': oldPassword, 'newPassword': newPassword}),
    );
    return jsonDecode(res.body);
  }

  // 退出：只清 Token，不清服务器地址
  static Future<void> logout() async {
    _token = null;
    _username = null;
    _role = null;
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'username');
    await _storage.delete(key: 'role');
  }
}
