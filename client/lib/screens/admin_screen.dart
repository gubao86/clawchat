import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../services/auth_service.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F23),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('管理面板', style: TextStyle(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.grey),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            labelColor: Color(0xFFE94560),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFE94560),
            tabs: [
              Tab(text: '用户'),
              Tab(text: '邀请码'),
              Tab(text: '统计'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _UsersTab(),
          _InviteCodesTab(),
          _StatsTab(),
        ]),
      ),
    );
  }
}

// ── 用户 Tab ─────────────────────────────────────────────────────────────────
class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/admin/users'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      final data = jsonDecode(res.body);
      setState(() { _users = data['users'] ?? []; _loading = false; });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _toggleStatus(Map user) async {
    final newStatus = user['status'] == 'active' ? 'banned' : 'active';
    await http.patch(
      Uri.parse('${AppConfig.baseUrl}/admin/users/${user['id']}/status'),
      headers: {'Authorization': 'Bearer ${AuthService.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'status': newStatus}),
    );
    _load();
  }

  Future<void> _toggleRole(Map user) async {
    final newRole = user['role'] == 'admin' ? 'user' : 'admin';
    await http.patch(
      Uri.parse('${AppConfig.baseUrl}/admin/users/${user['id']}/role'),
      headers: {'Authorization': 'Bearer ${AuthService.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'role': newRole}),
    );
    _load();
  }

  Future<void> _deleteUser(Map user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text('确定删除用户 ${user['username']} 吗？此操作不可撤销。',
            style: TextStyle(color: Colors.grey[300])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('取消', style: TextStyle(color: Colors.grey[400]))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    await http.delete(
      Uri.parse('${AppConfig.baseUrl}/admin/users/${user['id']}'),
      headers: {'Authorization': 'Bearer ${AuthService.token}'},
    );
    _load();
  }

  Future<void> _resetPassword(Map user) async {
    String mode = 'random';
    final pwdCtrl = TextEditingController();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('重置密码 — ${user['username']}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioListTile<String>(
            value: 'random',
            groupValue: mode,
            onChanged: (v) => setS(() => mode = v!),
            title: const Text('随机生成密码', style: TextStyle(color: Colors.white)),
            activeColor: const Color(0xFFE94560),
          ),
          RadioListTile<String>(
            value: 'manual',
            groupValue: mode,
            onChanged: (v) => setS(() => mode = v!),
            title: const Text('手动输入密码', style: TextStyle(color: Colors.white)),
            activeColor: const Color(0xFFE94560),
          ),
          if (mode == 'manual')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: pwdCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '新密码（至少6位）',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true, fillColor: const Color(0xFF16213E),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('取消', style: TextStyle(color: Colors.grey[400]))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {'mode': mode, 'password': pwdCtrl.text}),
            child: const Text('确认重置', style: TextStyle(color: Color(0xFFE94560))),
          ),
        ],
      )),
    );

    if (result == null) return;
    final body = <String, dynamic>{'mode': result['mode']};
    if (result['mode'] == 'manual') body['password'] = result['password'];

    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/admin/users/${user['id']}/reset-password'),
        headers: {'Authorization': 'Bearer ${AuthService.token}', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final data = jsonDecode(res.body);
      if (data['ok'] == true) {
        final newPwd = data['newPassword'] ?? '';
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: const Text('密码已重置', style: TextStyle(color: Colors.white)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('新密码：', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                const SizedBox(height: 8),
                SelectableText(newPwd,
                    style: const TextStyle(color: Colors.white, fontSize: 18,
                        fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              ]),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: newPwd));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制到剪贴板')));
                  },
                  child: const Text('复制并关闭', style: TextStyle(color: Color(0xFFE94560))),
                ),
              ],
            ),
          );
        }
      } else {
        _snack(data['error'] ?? '重置失败');
      }
    } catch (_) {
      _snack('网络错误');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _users.length,
        itemBuilder: (_, i) {
          final u = _users[i] as Map<String, dynamic>;
          final isSelf = u['id'] == null;
          final isBanned = u['status'] == 'banned';
          final isAdmin  = u['role'] == 'admin';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isAdmin
                    ? const Color(0xFF7C3AED).withOpacity(0.2)
                    : const Color(0xFF1A1A3E),
                child: Text(u['username']?.substring(0, 1).toUpperCase() ?? '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(u['username'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  if (isAdmin)
                    _chip('admin', const Color(0xFF7C3AED)),
                  if (isBanned)
                    _chip('封禁', Colors.redAccent),
                ]),
                Text('注册于 ${_fmtTime(u['created_at'])}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11)),
              ])),
              // 操作按钮
              PopupMenuButton<String>(
                color: const Color(0xFF1A1A2E),
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                onSelected: (action) {
                  if (action == 'status') _toggleStatus(u);
                  if (action == 'role')   _toggleRole(u);
                  if (action == 'delete') _deleteUser(u);
                  if (action == 'reset')  _resetPassword(u);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'status',
                      child: Text(isBanned ? '解封' : '封禁',
                          style: const TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'role',
                      child: Text(isAdmin ? '降为普通用户' : '升为管理员',
                          style: const TextStyle(color: Colors.white))),
                  const PopupMenuItem(value: 'reset',
                      child: Text('重置密码', style: TextStyle(color: Colors.white))),
                  const PopupMenuItem(value: 'delete',
                      child: Text('删除用户', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  String _fmtTime(dynamic ts) {
    if (ts == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch((ts as int) * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ── 邀请码 Tab ────────────────────────────────────────────────────────────────
class _InviteCodesTab extends StatefulWidget {
  const _InviteCodesTab();
  @override
  State<_InviteCodesTab> createState() => _InviteCodesTabState();
}

class _InviteCodesTabState extends State<_InviteCodesTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _codes = [];
  bool _loading = true;
  int _maxUses = 1;
  int _expiresInDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/admin/invite-codes'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      final data = jsonDecode(res.body);
      setState(() { _codes = data['codes'] ?? []; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('生成邀请码', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('使用次数：', style: TextStyle(color: Colors.grey[300], fontSize: 14)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.remove, color: Colors.grey, size: 18),
                onPressed: () => setS(() { if (_maxUses > 1) _maxUses--; })),
            Text('$_maxUses', style: const TextStyle(color: Colors.white, fontSize: 16)),
            IconButton(icon: const Icon(Icons.add, color: Colors.grey, size: 18),
                onPressed: () => setS(() { if (_maxUses < 100) _maxUses++; })),
          ]),
          Row(children: [
            Text('有效天数：', style: TextStyle(color: Colors.grey[300], fontSize: 14)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.remove, color: Colors.grey, size: 18),
                onPressed: () => setS(() { if (_expiresInDays > 1) _expiresInDays--; })),
            Text('$_expiresInDays', style: const TextStyle(color: Colors.white, fontSize: 16)),
            IconButton(icon: const Icon(Icons.add, color: Colors.grey, size: 18),
                onPressed: () => setS(() { if (_expiresInDays < 365) _expiresInDays++; })),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: Colors.grey[400]))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('生成', style: TextStyle(color: Color(0xFFE94560)))),
        ],
      )),
    );
    if (result != true) return;
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/admin/invite-codes'),
        headers: {'Authorization': 'Bearer ${AuthService.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({'maxUses': _maxUses, 'expiresInDays': _expiresInDays}),
      );
      final data = jsonDecode(res.body);
      if (data['ok'] == true) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('邀请码：${data['code']}'),
            action: SnackBarAction(
              label: '复制',
              onPressed: () => Clipboard.setData(ClipboardData(text: data['code'])),
            ),
          ));
        }
      }
    } catch (_) {}
  }

  Future<void> _revoke(String code) async {
    await http.delete(
      Uri.parse('${AppConfig.baseUrl}/admin/invite-codes/$code'),
      headers: {'Authorization': 'Bearer ${AuthService.token}'},
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: double.infinity, height: 44,
          child: ElevatedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('生成邀请码'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _codes.length,
            itemBuilder: (_, i) {
              final c = _codes[i] as Map<String, dynamic>;
              final used = c['use_count'] ?? 0;
              final max  = c['max_uses'] ?? 1;
              final exp  = c['expires_at'];
              final expired = exp != null &&
                  DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(DateTime.now());
              final exhausted = used >= max;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(12),
                  border: (expired || exhausted)
                      ? Border.all(color: Colors.grey.withOpacity(0.2))
                      : null,
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['code'] ?? '',
                        style: TextStyle(
                            color: (expired || exhausted) ? Colors.grey : Colors.white,
                            fontSize: 16, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('使用 $used/$max 次  |  ${exp == null ? "永不过期" : _fmtExpiry(exp, expired)}',
                        style: TextStyle(
                            color: expired ? Colors.redAccent : Colors.grey[500],
                            fontSize: 11)),
                  ])),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.grey, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: c['code'] ?? ''));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制邀请码')));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                    onPressed: () => _revoke(c['code'] ?? ''),
                  ),
                ]),
              );
            },
          ),
        )),
    ]);
  }

  String _fmtExpiry(int ts, bool expired) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final s = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    return expired ? '已过期（$s）' : '到期 $s';
  }
}

// ── 统计 Tab ──────────────────────────────────────────────────────────────────
class _StatsTab extends StatefulWidget {
  const _StatsTab();
  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/admin/stats'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      final data = jsonDecode(res.body);
      setState(() { _stats = data['stats']; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_stats == null) return const Center(child: Text('加载失败', style: TextStyle(color: Colors.grey)));
    final s = _stats!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statCard('总用户数', '${s['totalUsers']}', Icons.people_outline, Colors.blue),
          _statCard('活跃用户', '${s['activeUsers']}', Icons.person_outline, Colors.green),
          _statCard('封禁用户', '${s['bannedUsers']}', Icons.block, Colors.redAccent),
          _statCard('消息总数', '${s['totalMsgs']}', Icons.chat_bubble_outline, Colors.orange),
          _statCard('有效邀请码', '${s['activeCodes']}', Icons.card_giftcard, Colors.purple),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }
}
