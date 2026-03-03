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
  });

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
