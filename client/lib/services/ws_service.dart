import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class WsService {
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _reconnectTimer;
  String? _token;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  void connect(String token) {
    _token = token;
    _doConnect();
  }

  void _doConnect() {
    if (_disposed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));
      _channel!.stream.listen((data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['type'] == 'auth_ok') _controller.add({'type': 'connected'});
        _controller.add(msg);
      }, onDone: _onDisconnect, onError: (_) => _onDisconnect());
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': _token}));
    } catch (_) { _onDisconnect(); }
  }

  void _onDisconnect() {
    _channel = null;
    _controller.add({'type': 'disconnected'});
    if (!_disposed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), _doConnect);
    }
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void sendMessage(String content, {
    String? sessionKey,
    String? fileId,
    String? fileName,
    String? fileType,
    String? fileMime,
  }) {
    send({
      'type':    'message',
      'content': content,
      if (sessionKey != null) 'sessionKey': sessionKey,
      if (fileId   != null) 'fileId':   fileId,
      if (fileName != null) 'fileName': fileName,
      if (fileType != null) 'fileType': fileType,
      if (fileMime != null) 'fileMime': fileMime,
    });
  }

  void sendCallback(String callbackData, {String? sessionKey}) {
    send({
      'type': 'callback',
      'callbackData': callbackData,
      if (sessionKey != null) 'sessionKey': sessionKey,
    });
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
