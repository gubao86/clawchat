import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'auth_service.dart';

class CommandDef {
  final String key;
  final String cmd;
  final String desc;
  final String group;
  final bool exec;
  final bool admin;
  final String? argHint;
  final String? terminal;

  const CommandDef({
    required this.key,
    required this.cmd,
    required this.desc,
    required this.group,
    required this.exec,
    this.admin = false,
    this.argHint,
    this.terminal,
  });

  factory CommandDef.fromJson(Map<String, dynamic> j) => CommandDef(
    key:      j['key'] ?? '',
    cmd:      j['cmd'] ?? '',
    desc:     j['desc'] ?? '',
    group:    j['group'] ?? '',
    exec:     j['exec'] == true,
    admin:    j['admin'] == true,
    argHint:  j['argHint'],
    terminal: j['terminal'],
  );
}

class CommandService {
  static List<CommandDef> _commands = [];
  static bool _isAdmin = false;

  static List<CommandDef> get commands => _commands;
  static bool get isAdmin => _isAdmin;

  static Future<void> loadCommands() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/commands/list'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _commands = (data['commands'] as List)
            .map((e) => CommandDef.fromJson(e))
            .toList();
        _isAdmin = data['isAdmin'] == true;
      }
    } catch (_) {}
  }

  static List<CommandDef> filter(String query) {
    if (query.isEmpty) return _commands;
    final q = query.toLowerCase().replaceAll('/', '');
    return _commands.where((c) =>
      c.cmd.toLowerCase().contains(q) ||
      c.desc.contains(q) ||
      c.group.contains(q)
    ).toList();
  }

  static Future<({bool ok, String output})> exec(
      String key, List<String> args) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/commands/exec'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'key': key, 'args': args}),
      );
      final data = jsonDecode(res.body);
      return (ok: data['ok'] == true, output: data['output'] ?? data['error'] ?? '');
    } catch (e) {
      return (ok: false, output: '请求失败: $e');
    }
  }

  static Future<bool> clearHistory({String sessionKey = 'main'}) async {
    try {
      final res = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/commands/clear?session=$sessionKey'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
