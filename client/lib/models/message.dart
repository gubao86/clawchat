import '../widgets/inline_buttons.dart';

enum MessageType { text, image, video, audio, document, command }

class ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final MessageType type;
  // 文件相关
  final String? fileId;
  final String? fileName;
  final String? fileMime;
  // 命令结果相关
  final bool? cmdSuccess;
  // v2: inline buttons
  final List<List<InlineButton>>? buttons;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.type = MessageType.text,
    this.fileId,
    this.fileName,
    this.fileMime,
    this.cmdSuccess,
    this.buttons,
  });

  static List<List<InlineButton>>? _parseButtons(dynamic raw) {
    if (raw == null) return null;
    try {
      final List<dynamic> rows = raw is String ? [] : raw;
      if (raw is String) {
        // JSON string
        final decoded = raw;
        return null; // skip malformed
      }
      return rows.map<List<InlineButton>>((row) {
        return (row as List).map<InlineButton>((btn) {
          return InlineButton.fromJson(btn as Map<String, dynamic>);
        }).toList();
      }).toList();
    } catch (_) {
      return null;
    }
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    MessageType type = MessageType.text;
    final ct = json['content_type'] ?? 'text';
    switch (ct) {
      case 'image':    type = MessageType.image;    break;
      case 'video':    type = MessageType.video;    break;
      case 'audio':    type = MessageType.audio;    break;
      case 'document': type = MessageType.document; break;
    }
    return ChatMessage(
      id:        json['id'] ?? '',
      role:      json['role'] ?? 'user',
      content:   json['content'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch((json['created_at'] ?? 0) * 1000),
      type:      type,
      fileId:    json['file_id'],
      fileName:  json['file_name'],
      buttons:   _parseButtons(json['buttons']),
    );
  }

  factory ChatMessage.fromWs(Map<String, dynamic> msg) {
    MessageType type = MessageType.text;
    switch (msg['fileType']) {
      case 'image':    type = MessageType.image;    break;
      case 'video':    type = MessageType.video;    break;
      case 'audio':    type = MessageType.audio;    break;
      case 'document': type = MessageType.document; break;
    }
    return ChatMessage(
      id:        msg['id'] ?? '',
      role:      msg['role'] ?? 'user',
      content:   msg['content'] ?? '',
      createdAt: msg['ts'] != null
          ? DateTime.fromMillisecondsSinceEpoch(msg['ts'])
          : DateTime.now(),
      type:      type,
      fileId:    msg['fileId'],
      fileName:  msg['fileName'],
      fileMime:  msg['fileMime'],
      buttons:   _parseButtons(msg['buttons']),
    );
  }

  factory ChatMessage.command(String title, String output, {bool success = true}) {
    return ChatMessage(
      id:        DateTime.now().millisecondsSinceEpoch.toString(),
      role:      'system',
      content:   '$title\n\n$output',
      createdAt: DateTime.now(),
      type:      MessageType.command,
      cmdSuccess: success,
    );
  }
}
