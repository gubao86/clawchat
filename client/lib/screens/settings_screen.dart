import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverCtrl  = TextEditingController();
  final _oldPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _cfmPassCtrl = TextEditingController();

  Timer? _pingDebounce;
  bool? _pingStatus;
  bool _pinging = false;
  bool _loading = true;
  bool _changingPwd = false;

  bool get _isLoggedIn => AuthService.isLoggedIn;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    await AppConfig.load();
    final display = AppConfig.baseUrl.replaceFirst('http://', '').replaceFirst('https://', '');
    setState(() { _serverCtrl.text = display; _loading = false; });
    if (AppConfig.baseUrl.isNotEmpty) _doPing();
  }

  void _onServerChanged(String value) {
    _pingDebounce?.cancel();
    setState(() { _pingStatus = null; });
    if (value.trim().isEmpty) return;
    _pingDebounce = Timer(const Duration(milliseconds: 1500), () async {
      await AppConfig.save(value.trim());
      _doPing();
    });
  }

  Future<void> _doPing() async {
    if (AppConfig.baseUrl.isEmpty) return;
    setState(() { _pinging = true; _pingStatus = null; });
    final ok = await AppConfig.ping();
    if (mounted) setState(() { _pingStatus = ok; _pinging = false; });
  }

  Future<void> _changePassword() async {
    final old = _oldPassCtrl.text;
    final neo = _newPassCtrl.text;
    final cfm = _cfmPassCtrl.text;
    if (old.isEmpty || neo.isEmpty || cfm.isEmpty) {
      _snack('请填写所有密码字段'); return;
    }
    if (neo != cfm) { _snack('两次输入的新密码不一致'); return; }
    if (neo.length < 6) { _snack('新密码至少6位'); return; }
    setState(() => _changingPwd = true);
    try {
      final res = await AuthService.changePassword(old, neo);
      if (res['ok'] == true) {
        _snack('密码修改成功', success: true);
        _oldPassCtrl.clear(); _newPassCtrl.clear(); _cfmPassCtrl.clear();
      } else {
        _snack(res['error'] ?? '修改失败');
      }
    } catch (_) {
      _snack('网络错误');
    }
    if (mounted) setState(() => _changingPwd = false);
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : Colors.redAccent,
    ));
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _oldPassCtrl.dispose();
    _newPassCtrl.dispose();
    _cfmPassCtrl.dispose();
    _pingDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('设置', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.grey),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [

        // ── 服务器地址 ──────────────────────────────────────────────────
        _sectionTitle('服务器地址'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _serverCtrl,
            enabled: !_isLoggedIn,
            onChanged: _isLoggedIn ? null : _onServerChanged,
            style: TextStyle(color: _isLoggedIn ? Colors.grey[400] : Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: '域名:端口 或 IP:端口',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF16213E),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          )),
          const SizedBox(width: 10),
          _pinging
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _pingStatus == null ? Colors.grey[600]
                        : _pingStatus! ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                ),
        ]),
        if (_isLoggedIn)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('登录后不可修改服务器地址',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
        const SizedBox(height: 24),

        // ── 修改密码（需登录）──────────────────────────────────────────
        if (_isLoggedIn) ...[
          _sectionTitle('修改密码'),
          const SizedBox(height: 8),
          _passField(_oldPassCtrl, '当前密码'),
          const SizedBox(height: 10),
          _passField(_newPassCtrl, '新密码（至少6位）'),
          const SizedBox(height: 10),
          _passField(_cfmPassCtrl, '确认新密码'),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 44,
            child: ElevatedButton(
              onPressed: _changingPwd ? null : _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _changingPwd
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('修改密码', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── 管理面板（仅 admin）─────────────────────────────────────────
        if (_isLoggedIn && AuthService.isAdmin) ...[
          _sectionTitle('管理'),
          const SizedBox(height: 8),
          _menuTile(
            icon: Icons.admin_panel_settings_outlined,
            label: '管理面板',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminScreen())),
          ),
          const SizedBox(height: 24),
        ],

        // ── 关于 ────────────────────────────────────────────────────────
        _sectionTitle('关于'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('🦞 ', style: TextStyle(fontSize: 20)),
              Text('ClawChat', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text('版本 1.0.1', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const SizedBox(height: 4),
            Text('OpenClaw AI 自托管专用客户端', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));
  }

  Widget _passField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      obscureText: true,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600]),
        filled: true,
        fillColor: const Color(0xFF16213E),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _menuTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.grey[400], size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15))),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ]),
      ),
    );
  }
}
