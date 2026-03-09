import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/command_service.dart';
import '../services/session_service.dart';
import '../services/ws_service.dart';

class ChatProvider extends ChangeNotifier {
  final WsService _ws = WsService();
  final List<ChatMessage> _messages = [];
  final List<SessionInfo> _sessions = [];
  String _currentSessionKey = 'main';
  String _streamBuffer = '';
  String? _streamId;
  bool _isConnected = false;
  bool _isStreaming  = false;
  StreamSubscription? _sub;
  Timer? _refreshTimer;

  List<ChatMessage> get messages        => _messages;
  List<SessionInfo> get sessions        => _sessions;
  String get currentSessionKey          => _currentSessionKey;
  bool get isConnected                  => _isConnected;
  bool get isStreaming                   => _isStreaming;
  String get streamBuffer               => _streamBuffer;

  String get currentSessionTitle {
    try {
      return _sessions.firstWhere((s) => s.key == _currentSessionKey).title;
    } catch (e) {
      return _currentSessionKey == 'main' ? '主对话' : '新对话';
    }
  }

  void connect() {
    if (AuthService.token == null) return;
    _ws.connect(AuthService.token!);
    _sub = _ws.messages.listen(_handleMessage);
    CommandService.loadCommands();
    // Token 自动续期 Timer（每 20 分钟）
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      AuthService.refreshToken();
    });
  }

  void _handleMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'connected':
      case 'auth_ok':
        _isConnected = true;
        _loadSessionsAndHistory();
        notifyListeners();
        break;
      case 'auth_error':
        _isConnected = false;
        notifyListeners();
        break;
      case 'disconnected':
        _isConnected = false;
        notifyListeners();
        break;
      case 'message':
        final msgSessionKey = msg['sessionKey'] ?? 'main';
        if (msgSessionKey == _currentSessionKey && msg['role'] == 'user') {
          _messages.add(ChatMessage.fromWs(msg));
          notifyListeners();
        }
        break;
      case 'stream_start':
        final startKey = msg['sessionKey'] ?? 'main';
        if (startKey == _currentSessionKey) {
          _streamId = msg['id'];
          _streamBuffer = '';
          _isStreaming = true;
          notifyListeners();
        }
        break;
      case 'stream_chunk':
        final chunkKey = msg['sessionKey'] ?? 'main';
        if (chunkKey == _currentSessionKey) {
          _streamBuffer += msg['content'] ?? '';
          notifyListeners();
        }
        break;
      case 'stream_end':
        final endKey = msg['sessionKey'] ?? 'main';
        if (endKey == _currentSessionKey) {
          _messages.add(ChatMessage(
            id: _streamId ?? '',
            role: 'assistant',
            content: _streamBuffer,
            createdAt: DateTime.now(),
          ));
          _isStreaming = false;
          _streamBuffer = '';
          _streamId = null;
          notifyListeners();
        }
        break;
      case 'error':
        _isStreaming = false;
        _messages.add(ChatMessage(
          id: 'err-${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: '⚠️ ${msg['message'] ?? '错误'}',
          createdAt: DateTime.now(),
        ));
        notifyListeners();
        break;
      case 'session_renamed':
        final renamedKey = msg['sessionKey'] ?? '';
        final newTitle = msg['title'] ?? '';
        final idx = _sessions.indexWhere((s) => s.key == renamedKey);
        if (idx >= 0) {
          _sessions[idx].title = newTitle;
          notifyListeners();
        }
        break;
    }
  }

  Future<void> _loadSessionsAndHistory() async {
    await loadSessions();
    await loadHistory(_currentSessionKey);
  }

  Future<void> loadSessions() async {
    try {
      final list = await SessionService.listSessions();
      _sessions.clear();
      _sessions.addAll(list);
      // 确保 main session 存在
      if (_sessions.isEmpty) {
        _sessions.add(SessionInfo(key: 'main', title: '主对话', updatedAt: 0));
      }
      notifyListeners();
    } catch (e) {
      // 静默处理会话加载失败
    }
  }

  Future<void> switchSession(String key) async {
    _currentSessionKey = key;
    _messages.clear();
    _streamBuffer = '';
    _isStreaming = false;
    notifyListeners();
    await loadHistory(key);
  }

  Future<void> createSession() async {
    final session = await SessionService.createSession();
    if (session != null) {
      _sessions.insert(0, session);
      notifyListeners();
      await switchSession(session.key);
    }
  }

  Future<void> renameCurrentSession(String title) async {
    final ok = await SessionService.renameSession(_currentSessionKey, title);
    if (ok) {
      final idx = _sessions.indexWhere((s) => s.key == _currentSessionKey);
      if (idx >= 0) {
        _sessions[idx].title = title;
        notifyListeners();
      }
    }
  }

  Future<void> deleteSession(String key) async {
    final ok = await SessionService.deleteSession(key);
    if (ok) {
      _sessions.removeWhere((s) => s.key == key);
      if (_currentSessionKey == key) {
        final fallback = _sessions.isNotEmpty ? _sessions.first.key : 'main';
        await switchSession(fallback);
      } else {
        notifyListeners();
      }
    }
  }

  void sendMessage(String content, {
    String? fileId, String? fileName, String? fileType, String? fileMime
  }) {
    _ws.sendMessage(
      content,
      sessionKey: _currentSessionKey,
      fileId:    fileId,
      fileName:  fileName,
      fileType:  fileType,
      fileMime:  fileMime,
    );
  }

  // 执行命令并添加结果气泡
  Future<void> execCommand(String key, List<String> args, String cmdText) async {
    if (key == 'clear') {
      final ok = await CommandService.clearHistory(sessionKey: _currentSessionKey);
      if (ok) {
        _messages.clear();
        _messages.add(ChatMessage.command('/clear', '✅ 对话历史已清空'));
      } else {
        _messages.add(ChatMessage.command('/clear', '❌ 清空失败', success: false));
      }
      notifyListeners();
      return;
    }
    if (key == 'help') {
      final buf = StringBuffer('📖 OpenClaw 命令列表\n\n');
      String? lastGroup;
      for (final c in CommandService.commands) {
        if (c.group != lastGroup) { buf.writeln('\n${c.group}'); lastGroup = c.group; }
        final tag = !c.exec ? ' [终端]' : c.admin ? ' [管理员]' : '';
        final arg = c.argHint != null ? ' <${c.argHint}>' : '';
        buf.writeln('  ${c.cmd}$arg$tag\n    ${c.desc}');
      }
      _messages.add(ChatMessage.command('/help', buf.toString().trim()));
      notifyListeners();
      return;
    }
    // 占位气泡
    _messages.add(ChatMessage.command(cmdText, '执行中...'));
    notifyListeners();
    final result = await CommandService.exec(key, args);
    // 替换最后一条命令气泡
    final last = _messages.lastWhere((m) => m.type == MessageType.command, orElse: () => _messages.last);
    final idx = _messages.indexOf(last);
    if (idx >= 0) {
      _messages[idx] = ChatMessage.command(cmdText, result.output, success: result.ok);
      notifyListeners();
    }
  }

  Future<void> loadHistory(String sessionKey) async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/messages/history?limit=50&session=$sessionKey'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      final data = jsonDecode(res.body);
      if (data['ok'] == true) {
        _messages.clear();
        for (final m in data['messages']) _messages.add(ChatMessage.fromJson(m));
        notifyListeners();
      }
    } catch (e) {
      // 静默处理历史记录加载失败
    }
  }

  // 本地删除消息（不删服务端）
  void deleteMessageLocally(String id) {
    _messages.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sub?.cancel();
    _ws.dispose();
    super.dispose();
  }
}
