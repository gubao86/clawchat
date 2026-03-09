import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../providers/chat_provider.dart';
import '../services/auth_service.dart';
import '../services/command_service.dart';
import '../services/session_service.dart';
import '../models/message.dart';
import '../config.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

// ── 统一的待上传附件 ─────────────────────────────────────────────────────────
class _PendingAttachment {
  final String name;
  final String path;
  final int size;
  final String type; // 'image' | 'video' | 'audio' | 'document'

  const _PendingAttachment({
    required this.name,
    required this.path,
    required this.size,
    required this.type,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  late ChatProvider _chat;

  // 命令面板
  bool _showCmdPalette = false;
  List<CommandDef> _filteredCmds = [];

  // 待上传附件
  _PendingAttachment? _pendingAttachment;

  // 语音录制
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _recordCancelled = false;
  double _recordSlideX = 0;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _chat = ChatProvider();
    _chat.connect();
    _chat.addListener(_scrollToBottom);
    _inputCtrl.addListener(_onInputChanged);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _onInputChanged() {
    final text = _inputCtrl.text;
    if (text.startsWith('/') && !text.contains(' ')) {
      final q = text.substring(1);
      setState(() {
        _showCmdPalette = true;
        _filteredCmds = CommandService.filter(q);
      });
    } else {
      if (_showCmdPalette) setState(() => _showCmdPalette = false);
    }
  }

  void _selectCommand(CommandDef cmd) {
    setState(() { _showCmdPalette = false; });
    if (!cmd.exec && cmd.terminal != null) {
      _chat.execCommand('terminal', [], cmd.cmd);
      _inputCtrl.clear();
      return;
    }
    // 无需参数的命令直接执行
    if (cmd.argHint == null) {
      _inputCtrl.clear();
      _chat.execCommand(cmd.key, [], cmd.cmd);
      return;
    }
    // 需要参数的命令填充到输入框
    _inputCtrl.text = cmd.cmd + ' ';
    _inputCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputCtrl.text.length));
    _inputFocus.requestFocus();
  }

  // ── 发送 ──────────────────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty && _pendingAttachment == null) return;

    if (text.startsWith('/') && text.length > 1) {
      _inputCtrl.clear();
      setState(() { _showCmdPalette = false; });
      await _handleCommand(text);
      return;
    }

    String? fileId, fileName, fileType, fileMime;
    if (_pendingAttachment != null) {
      try {
        final uploaded = await _uploadFile(_pendingAttachment!.path, _pendingAttachment!.name);
        fileId   = uploaded['id'];
        fileName = uploaded['name'];
        fileType = _pendingAttachment!.type;
        fileMime = uploaded['type'];
      } catch (e) {
        _showSnack('上传失败: $e');
        return;
      }
      setState(() => _pendingAttachment = null);
    }

    _chat.sendMessage(text,
        fileId: fileId, fileName: fileName, fileType: fileType, fileMime: fileMime);
    _inputCtrl.clear();
  }

  Future<void> _handleCommand(String text) async {
    final parts   = text.trim().split(RegExp(r'\s+'));
    final cmdStr  = parts[0].toLowerCase();
    final sub     = parts.length > 1 ? parts[1].toLowerCase() : '';
    final args    = parts.length > 2 ? parts.sublist(2) : <String>[];
    final fullCmd = sub.isNotEmpty ? '$cmdStr $sub' : cmdStr;

    if (cmdStr == '/help') { await _chat.execCommand('help', [], '/help'); return; }
    if (cmdStr == '/clear') { await _chat.execCommand('clear', [], '/clear'); return; }

    final def = CommandService.commands.firstWhere(
      (c) => c.cmd.toLowerCase() == fullCmd,
      orElse: () => CommandService.commands.firstWhere(
        (c) => c.cmd.toLowerCase() == cmdStr,
        orElse: () => const CommandDef(key:'', cmd:'', desc:'未知命令', group:'', exec:false),
      ),
    );

    if (def.key.isEmpty) {
      _chat.execCommand('error', [], '$text → 未知命令，输入 /help 查看列表');
      return;
    }
    if (!def.exec) {
      final terminal = def.terminal ?? 'openclaw ${def.key.replaceAll(":", " ")}';
      _chat.execCommand('terminal', [], '${def.cmd}\n\n此命令需在终端执行：\n$terminal');
      return;
    }
    await _chat.execCommand(def.key, args, def.cmd);
  }

  // ── 附件选择 ─────────────────────────────────────────────────────────────
  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _attachItem(Icons.camera_alt, '相机', () {
              Navigator.pop(context);
              _pickCamera();
            }),
            _attachItem(Icons.photo_library, '相册', () {
              Navigator.pop(context);
              _pickGallery();
            }),
            _attachItem(Icons.folder_open, '文件', () {
              Navigator.pop(context);
              _pickFile();
            }),
          ]),
        ),
      ),
    );
  }

  Widget _attachItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Colors.grey[300], size: 28),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      ]),
    );
  }

  Future<void> _pickCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) { _showSnack('需要相机权限'); return; }
    final xfile = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (xfile == null) return;
    final file = File(xfile.path);
    final size = await file.length();
    setState(() => _pendingAttachment = _PendingAttachment(
        name: xfile.name, path: xfile.path, size: size, type: 'image'));
  }

  Future<void> _pickGallery() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xfile == null) return;
    final file = File(xfile.path);
    final size = await file.length();
    setState(() => _pendingAttachment = _PendingAttachment(
        name: xfile.name, path: xfile.path, size: size, type: 'image'));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg','jpeg','png','gif','webp','mp4','webm','mp3','ogg','wav','pdf','txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;
    final path = pf.path;
    if (path == null) return;
    final mime = lookupMimeType(pf.name) ?? 'application/octet-stream';
    String type = 'document';
    if (mime.startsWith('image/'))       type = 'image';
    else if (mime.startsWith('video/')) type = 'video';
    else if (mime.startsWith('audio/')) type = 'audio';
    setState(() => _pendingAttachment = _PendingAttachment(
        name: pf.name, path: path, size: pf.size, type: type));
  }

  // ── 语音录制 ─────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) { _showSnack('需要麦克风权限'); return; }
    }
    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: _recordingPath!,
    );
    setState(() {
      _isRecording = true;
      _recordCancelled = false;
      _recordSlideX = 0;
      _recordDuration = Duration.zero;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording) {
        setState(() => _recordDuration += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() { _isRecording = false; _recordDuration = Duration.zero; });
    if (path == null || _recordCancelled) {
      if (path != null) { try { File(path).deleteSync(); } catch (_) {} }
      setState(() => _recordCancelled = false);
      return;
    }
    // 上传音频文件
    try {
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final uploaded = await _uploadFile(path, name);
      _chat.sendMessage('',
          fileId: uploaded['id'],
          fileName: uploaded['name'],
          fileType: 'audio',
          fileMime: uploaded['type']);
    } catch (e) {
      _showSnack('录音上传失败: $e');
    }
    try { File(path).deleteSync(); } catch (_) {}
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordCancelled = true;
    final path = await _recorder.stop();
    if (path != null) { try { File(path).deleteSync(); } catch (_) {} }
    setState(() { _isRecording = false; _recordCancelled = false; _recordDuration = Duration.zero; });
  }

  // ── 文件上传 ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _uploadFile(String path, String name) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('${AppConfig.baseUrl}/files/upload'));
    request.headers['Authorization'] = 'Bearer ${AuthService.token}';
    final bytes = await File(path).readAsBytes();
    final mime = lookupMimeType(name) ?? 'application/octet-stream';
    final parts = mime.split('/');
    request.files.add(http.MultipartFile.fromBytes(
      'file', bytes, filename: name,
      contentType: MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream'),
    ));
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return (jsonDecode(body)['file']) as Map<String, dynamic>;
  }

  // ── 命令面板 BottomSheet ──────────────────────────────────────────────────
  void _showCommandSheet() {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final cmds = CommandService.filter(query);
        final groups = <String, List<CommandDef>>{};
        for (final c in cmds) groups.putIfAbsent(c.group, () => []).add(c);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scroll) => Column(children: [
            // 搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                onChanged: (v) => setS(() => query = v),
                decoration: InputDecoration(
                  hintText: '搜索命令...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                  filled: true,
                  fillColor: const Color(0xFF1E2A3A),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
            const Divider(color: Color(0xFF2D3748), height: 1),
            // 命令列表
            Expanded(child: cmds.isEmpty
              ? const Center(child: Text('没有匹配的命令', style: TextStyle(color: Colors.grey)))
              : ListView(controller: scroll, padding: EdgeInsets.zero,
                  children: groups.entries.expand((entry) => [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: Text(entry.key,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: Colors.grey, letterSpacing: 0.5)),
                    ),
                    ...entry.value.map((c) {
                      final locked = c.admin && !CommandService.isAdmin;
                      return InkWell(
                        onTap: locked ? null : () {
                          Navigator.pop(ctx);
                          _selectCommandDirect(c);
                        },
                        child: Opacity(
                          opacity: locked ? 0.45 : 1.0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(children: [
                              SizedBox(width: 170,
                                child: Text(c.cmd,
                                    style: const TextStyle(color: Color(0xFF93C5FD),
                                        fontFamily: 'monospace', fontSize: 13))),
                              Expanded(child: Text(c.desc,
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  overflow: TextOverflow.ellipsis)),
                              if (locked) _badge('管理员', const Color(0xFF7C3AED)),
                              if (!c.exec && !locked) _badge('终端', const Color(0xFFD97706)),
                            ]),
                          ),
                        ),
                      );
                    }),
                  ]).toList(),
                ),
            ),
          ]),
        );
      }),
    );
  }

  void _selectCommandDirect(CommandDef cmd) {
    if (!cmd.exec && cmd.terminal != null) {
      _chat.execCommand('terminal', [], cmd.cmd);
      return;
    }
    // 无需参数的命令直接执行
    if (cmd.argHint == null) {
      _chat.execCommand(cmd.key, [], cmd.cmd);
      return;
    }
    // 需要参数的命令填充到输入框
    _inputCtrl.text = cmd.cmd + ' ';
    _inputCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputCtrl.text.length));
    _inputFocus.requestFocus();
  }

  // ── 消息长按菜单 ─────────────────────────────────────────────────────────
  void _showMessageMenu(ChatMessage m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          // 复制全文
          if (m.type == MessageType.text || m.type == MessageType.command)
            _menuItem(Icons.copy, '复制全文', () {
              Clipboard.setData(ClipboardData(text: m.content));
              Navigator.pop(context);
              _showSnack('已复制');
            }),
          // 编辑重新发送（仅用户消息）
          if (m.role == 'user' && m.type == MessageType.text)
            _menuItem(Icons.edit_outlined, '编辑重新发送', () {
              Navigator.pop(context);
              _inputCtrl.text = m.content;
              _inputCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: m.content.length));
              _inputFocus.requestFocus();
            }),
          // 重新生成（仅 AI 消息）
          if (m.role == 'assistant' && m.type == MessageType.text)
            _menuItem(Icons.refresh, '重新生成', () {
              Navigator.pop(context);
              _regenerate(m);
            }),
          // 删除（本地）
          _menuItem(Icons.delete_outline, '删除（本地）', () {
            Navigator.pop(context);
            _chat.deleteMessageLocally(m.id);
          }, color: Colors.redAccent),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final c = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: c, fontSize: 15)),
        ]),
      ),
    );
  }

  void _regenerate(ChatMessage aiMsg) {
    // 找到 AI 消息前的最后一条用户消息并重发
    final idx = _chat.messages.indexOf(aiMsg);
    if (idx <= 0) return;
    final userMsg = _chat.messages.sublist(0, idx).lastWhere(
        (m) => m.role == 'user', orElse: () => aiMsg);
    if (userMsg.role != 'user') return;
    _chat.deleteMessageLocally(aiMsg.id);
    _chat.sendMessage(userMsg.content);
  }

  // ── Drawer: 会话列表 ──────────────────────────────────────────────────────
  Widget _buildSessionDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A2E),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 用户信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              const Icon(Icons.account_circle, color: Colors.grey, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text(AuthService.username ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
              if (AuthService.isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.2),
                    border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('admin',
                      style: TextStyle(color: Color(0xFF7C3AED), fontSize: 10, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          // 新建对话按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              onTap: () { Navigator.pop(context); _chat.createSession(); },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE94560).withOpacity(0.15),
                  border: Border.all(color: const Color(0xFFE94560).withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.add, color: Color(0xFFE94560), size: 18),
                  SizedBox(width: 8),
                  Text('新建对话', style: TextStyle(color: Color(0xFFE94560), fontSize: 14)),
                ]),
              ),
            ),
          ),
          const Divider(color: Color(0xFF2D3748)),
          // 会话列表
          Expanded(child: Consumer<ChatProvider>(builder: (_, chat, __) {
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: chat.sessions.length,
              itemBuilder: (_, i) {
                final s = chat.sessions[i];
                final isActive = s.key == chat.currentSessionKey;
                return GestureDetector(
                  onLongPress: () => _showSessionOptions(s),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      if (!isActive) chat.switchSession(s.key);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFE94560).withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isActive ? Border.all(color: const Color(0xFFE94560).withOpacity(0.3)) : null,
                      ),
                      child: Row(children: [
                        const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 16),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.title,
                              style: TextStyle(
                                  color: isActive ? const Color(0xFFE94560) : Colors.white,
                                  fontSize: 14, fontWeight: FontWeight.w500),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (s.lastMessage != null)
                            Text(s.lastMessage!,
                                style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                      ]),
                    ),
                  ),
                );
              },
            );
          })),
        ]),
      ),
    );
  }

  void _showSessionOptions(SessionInfo s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          _menuItem(Icons.drive_file_rename_outline, '重命名', () {
            Navigator.pop(context);
            _renameSessionDialog(s);
          }),
          if (s.key != 'main')
            _menuItem(Icons.delete_outline, '删除会话', () {
              Navigator.pop(context);
              _chat.deleteSession(s.key);
            }, color: Colors.redAccent),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _renameSessionDialog(SessionInfo s) {
    final ctrl = TextEditingController(text: s.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('重命名会话', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true, fillColor: const Color(0xFF16213E),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('取消', style: TextStyle(color: Colors.grey[400]))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final title = ctrl.text.trim();
              if (title.isNotEmpty) _chat.renameCurrentSession(title);
            },
            child: const Text('确定', style: TextStyle(color: Color(0xFFE94560))),
          ),
        ],
      ),
    );
  }

  void _renameCurrentSessionDialog() {
    final s = _chat.sessions.where((s) => s.key == _chat.currentSessionKey).toList();
    if (s.isNotEmpty) _renameSessionDialog(s.first);
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A2E),
      elevation: 0,
      leading: Builder(builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu, color: Colors.grey),
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      )),
      title: Consumer<ChatProvider>(builder: (_, chat, __) => GestureDetector(
        onTap: _renameCurrentSessionDialog,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(chat.currentSessionTitle,
              style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(chat.isConnected ? '已连接' : '连接中...',
              style: TextStyle(fontSize: 11,
                  color: chat.isConnected ? Colors.greenAccent : Colors.grey[500])),
        ]),
      )),
      actions: [
        IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.grey), onPressed: _openSettings),
        IconButton(icon: const Icon(Icons.logout, color: Colors.grey), onPressed: _logout),
      ],
    );
  }

  // ── 消息列表 ──────────────────────────────────────────────────────────────
  Widget _buildMessageList() {
    return Consumer<ChatProvider>(builder: (_, chat, __) {
      final count = chat.messages.length + (chat.isStreaming ? 1 : 0);
      return ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        itemCount: count,
        itemBuilder: (_, i) {
          if (i == chat.messages.length && chat.isStreaming) {
            return _buildTextBubble('assistant', '${chat.streamBuffer}▌');
          }
          return GestureDetector(
            onLongPress: () => _showMessageMenu(chat.messages[i]),
            child: _buildMessageBubble(chat.messages[i]),
          );
        },
      );
    });
  }

  Widget _buildMessageBubble(ChatMessage m) {
    switch (m.type) {
      case MessageType.image:    return _buildImageBubble(m);
      case MessageType.audio:    return _AudioBubble(message: m);
      case MessageType.video:    return _buildFileBubble(m, Icons.video_file, Colors.purple);
      case MessageType.document: return _buildFileBubble(m, Icons.description, Colors.blue);
      case MessageType.command:  return _buildCommandBubble(m);
      case MessageType.text:
      default:                   return _buildTextBubble(m.role, m.content);
    }
  }

  Widget _buildTextBubble(String role, String content) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF16213E) : const Color(0xFF1A1A3E),
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(14),
            topRight:    const Radius.circular(14),
            bottomLeft:  Radius.circular(isUser ? 14 : 3),
            bottomRight: Radius.circular(isUser ? 3 : 14),
          ),
        ),
        child: isUser
            ? SelectableText(content,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5))
            : MarkdownBody(
                data: content,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                  code: const TextStyle(color: Color(0xFF93C5FD), fontFamily: 'monospace', fontSize: 13),
                  codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  blockquoteDecoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Color(0xFFE94560), width: 3)),
                  ),
                ),
                selectable: true,
              ),
      ),
    );
  }

  Widget _buildImageBubble(ChatMessage m) {
    final isUser  = m.role == 'user';
    final fileUrl = '${AppConfig.baseUrl}/files/${m.fileId}';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF16213E) : const Color(0xFF1A1A3E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: () => _openImageViewer(fileUrl),
              child: CachedNetworkImage(
                imageUrl: fileUrl,
                httpHeaders: {'Authorization': 'Bearer ${AuthService.token}'},
                width: double.infinity, fit: BoxFit.cover,
                placeholder: (_, __) => const SizedBox(height: 160,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                errorWidget: (_, __, ___) => const SizedBox(height: 80,
                    child: Center(child: Icon(Icons.broken_image, color: Colors.grey))),
              ),
            ),
          ),
          if (m.content.isNotEmpty && m.content != (m.fileName ?? ''))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Text(m.content, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            ),
        ]),
      ),
    );
  }

  Widget _buildFileBubble(ChatMessage m, IconData icon, Color color) {
    final isUser  = m.role == 'user';
    final fileUrl = '${AppConfig.baseUrl}/files/${m.fileId}';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF16213E) : const Color(0xFF1A1A3E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.fileName ?? '文件',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            if (m.content.isNotEmpty && m.content != m.fileName)
              Text(m.content, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ])),
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.grey),
            onPressed: () => _showSnack('文件地址：$fileUrl'),
          ),
        ]),
      ),
    );
  }

  Widget _buildCommandBubble(ChatMessage m) {
    final parts   = m.content.split('\n\n');
    final title   = parts.first;
    final output  = parts.length > 1 ? parts.sublist(1).join('\n\n') : '';
    final success = m.cmdSuccess ?? true;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.95),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          border: Border.all(color: success ? const Color(0xFF2D3748) : const Color(0xFFE94560).withOpacity(0.4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(success ? Icons.terminal : Icons.error_outline,
                size: 14,
                color: success ? const Color(0xFF60A5FA) : Colors.redAccent),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace',
                    color: success ? const Color(0xFF60A5FA) : Colors.redAccent)),
          ]),
          if (output.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(output,
                  style: const TextStyle(
                      color: Color(0xFFD1D5DB), fontSize: 12,
                      fontFamily: 'monospace', height: 1.5)),
            ),
          ],
        ]),
      ),
    );
  }

  // ── 命令面板（输入触发）──────────────────────────────────────────────────
  Widget _buildCommandPalette() {
    final groups = <String, List<CommandDef>>{};
    for (final c in _filteredCmds) {
      groups.putIfAbsent(c.group, () => []).add(c);
    }
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(top: BorderSide(color: Color(0xFF2D3748))),
      ),
      child: _filteredCmds.isEmpty
          ? const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('没有匹配的命令',
                  style: TextStyle(color: Colors.grey, fontSize: 14))))
          : ListView(
              padding: EdgeInsets.zero,
              children: groups.entries.expand((entry) => [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text(entry.key,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: Colors.grey, letterSpacing: 0.5)),
                ),
                ...entry.value.map((c) {
                  final locked = c.admin && !CommandService.isAdmin;
                  return InkWell(
                    onTap: locked ? null : () => _selectCommand(c),
                    child: Opacity(
                      opacity: locked ? 0.45 : 1.0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(children: [
                          SizedBox(width: 180,
                            child: Text(c.cmd,
                                style: const TextStyle(color: Color(0xFF93C5FD),
                                    fontFamily: 'monospace', fontSize: 13))),
                          Expanded(child: Text(c.desc,
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                              overflow: TextOverflow.ellipsis)),
                          if (locked) _badge('管理员', const Color(0xFF7C3AED)),
                          if (!c.exec && !locked) _badge('终端', const Color(0xFFD97706)),
                        ]),
                      ),
                    ),
                  );
                }),
              ]).toList(),
            ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  // ── 文件预览条 ───────────────────────────────────────────────────────────
  Widget _buildFilePreview() {
    final att = _pendingAttachment!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      color: const Color(0xFF1E2A3A),
      child: Row(children: [
        Icon(
          att.type == 'image' ? Icons.image :
          att.type == 'video' ? Icons.video_file :
          att.type == 'audio' ? Icons.audiotrack : Icons.description,
          color: Colors.grey, size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(att.name,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis)),
        Text('${(att.size / 1024).toStringAsFixed(0)} KB',
            style: TextStyle(color: Colors.grey[500], fontSize: 11)),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
          onPressed: () => setState(() => _pendingAttachment = null),
        ),
      ]),
    );
  }

  // ── 录音 UI 条 ───────────────────────────────────────────────────────────
  Widget _buildRecordingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF1A1A2E),
      child: Row(children: [
        // 红色动画圆
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          builder: (_, v, __) => Opacity(
            opacity: v,
            child: Container(
              width: 12, height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.red),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(_formatDuration(_recordDuration),
            style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'monospace')),
        const Spacer(),
        const Icon(Icons.arrow_back_ios, color: Colors.grey, size: 13),
        Text(' 左滑取消', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      ]),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(1, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── 输入栏 ───────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        top: false,
        child: Consumer<ChatProvider>(builder: (_, chat, __) {
          final hasContent = _inputCtrl.text.isNotEmpty || _pendingAttachment != null;
          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // ⊕ 附件按钮
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.grey, size: 26),
              onPressed: _showAttachmentSheet,
            ),
            // 输入框
            Expanded(child: TextField(
              controller: _inputCtrl,
              focusNode: _inputFocus,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              maxLines: 5, minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '输入消息，或 / 查看命令...',
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
                filled: true, fillColor: const Color(0xFF16213E),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFE94560), width: 1)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            )),
            const SizedBox(width: 6),
            // 右侧：发送 / 录音 / 命令
            if (!hasContent && !chat.isStreaming)
              // 麦克风（按住录音）
              GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressMoveUpdate: (details) {
                  setState(() => _recordSlideX = details.offsetFromOrigin.dx);
                  if (_recordSlideX < -80 && _isRecording) _cancelRecording();
                },
                onLongPressEnd: (_) {
                  if (_isRecording) _stopAndSendRecording();
                },
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF2D3748),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: _isRecording ? Colors.red : Colors.grey,
                    size: 22,
                  ),
                ),
              )
            else
              // 发送按钮
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE94560),
                child: IconButton(
                  icon: Icon(chat.isStreaming ? Icons.stop : Icons.send,
                      color: Colors.white, size: 20),
                  onPressed: chat.isStreaming ? null : _send,
                ),
              ),
            const SizedBox(width: 4),
            // ⌨ 命令菜单按钮
            IconButton(
              icon: const Icon(Icons.keyboard_command_key, color: Colors.grey, size: 22),
              onPressed: _showCommandSheet,
              tooltip: '命令菜单',
            ),
          ]);
        }),
      ),
    );
  }

  // ── 工具方法 ─────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _logout() async {
    _chat.dispose();
    await AuthService.logout();
    if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) async {
      _chat.dispose();
      setState(() {
        _chat = ChatProvider();
        _chat.connect();
        _chat.addListener(_scrollToBottom);
      });
    });
  }

  void _openImageViewer(String url) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _ImageViewer(url: url)));
  }

  @override
  void dispose() {
    _chat.removeListener(_scrollToBottom);
    _chat.dispose();
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _chat,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F23),
        drawer: _buildSessionDrawer(),
        appBar: _buildAppBar(),
        body: Column(children: [
          Expanded(child: _buildMessageList()),
          if (_showCmdPalette) _buildCommandPalette(),
          if (_pendingAttachment != null) _buildFilePreview(),
          if (_isRecording) _buildRecordingBar(),
          _buildInputBar(),
        ]),
      ),
    );
  }
}

// ── 音频气泡 ─────────────────────────────────────────────────────────────────
class _AudioBubble extends StatefulWidget {
  final ChatMessage message;
  const _AudioBubble({required this.message});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  late final AudioPlayer _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.stop();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (!_loaded) {
      final url = '${AppConfig.baseUrl}/files/${widget.message.fileId}';
      await _player.setUrl(url, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      _loaded = true;
    }
    await _player.play();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString();
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        constraints: BoxConstraints(
            minWidth: 180,
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF16213E) : const Color(0xFF1A1A3E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          IconButton(
            icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle,
                color: const Color(0xFFE94560), size: 32),
            onPressed: _togglePlay,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          Expanded(child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: progress,
              onChanged: (v) {
                final ms = (v * _duration.inMilliseconds).toInt();
                _player.seek(Duration(milliseconds: ms));
              },
              activeColor: const Color(0xFFE94560),
              inactiveColor: Colors.grey[700],
            ),
          )),
          Text(_fmt(_duration),
              style: TextStyle(color: Colors.grey[400], fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

// ── 图片全屏预览 ──────────────────────────────────────────────────────────────
class _ImageViewer extends StatelessWidget {
  final String url;
  const _ImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: {'Authorization': 'Bearer ${AuthService.token}'},
              fit: BoxFit.contain,
              placeholder: (_, __) => const CircularProgressIndicator(),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.grey, size: 60),
            ),
          ),
        ),
      ),
    );
  }
}

