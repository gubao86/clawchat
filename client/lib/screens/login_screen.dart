import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _serverCtrl = TextEditingController();
  Timer? _pingDebounce;

  // 状态灯：null=未配置，true=连通，false=不通
  bool? _pingStatus;
  bool _pinging = false;

  // 登录
  final _loginUserCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  bool _loginLoading = false;
  String? _loginError;

  // 注册
  final _regUserCtrl  = TextEditingController();
  final _regPassCtrl  = TextEditingController();
  final _inviteCtrl   = TextEditingController();
  bool _regLoading  = false;
  String? _regError;
  bool _isFirstUser = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && !_tabCtrl.indexIsChanging) {
        _checkFirstUser();
      }
    });
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    await AppConfig.load();
    if (AppConfig.baseUrl.isNotEmpty) {
      final display = AppConfig.baseUrl.replaceFirst('http://', '').replaceFirst('https://', '');
      _serverCtrl.text = display;
      _doPing();
    }
  }

  void _onServerChanged(String value) {
    _pingDebounce?.cancel();
    setState(() { _pingStatus = null; _pinging = false; });
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

  Future<void> _checkFirstUser() async {
    final first = await AuthService.checkIsFirstUser();
    if (mounted) setState(() => _isFirstUser = first);
  }

  Future<void> _login() async {
    if (_loginLoading) return;
    final u = _loginUserCtrl.text.trim();
    final p = _loginPassCtrl.text;
    if (u.isEmpty || p.isEmpty) return setState(() => _loginError = '请填写用户名和密码');
    setState(() { _loginLoading = true; _loginError = null; });
    try {
      final res = await AuthService.login(u, p);
      if (res['ok'] == true) {
        if (mounted) Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const ChatScreen()));
      } else {
        setState(() => _loginError = res['error'] ?? '登录失败');
      }
    } catch (_) {
      setState(() => _loginError = '网络错误，请检查服务器地址');
    }
    if (mounted) setState(() => _loginLoading = false);
  }

  Future<void> _register() async {
    if (_regLoading) return;
    final u = _regUserCtrl.text.trim();
    final p = _regPassCtrl.text;
    if (u.isEmpty || p.isEmpty) return setState(() => _regError = '请填写用户名和密码');
    if (p.length < 6) return setState(() => _regError = '密码至少6位');
    setState(() { _regLoading = true; _regError = null; });
    try {
      final res = await AuthService.register(u, p,
          inviteCode: _inviteCtrl.text.trim().isEmpty ? null : _inviteCtrl.text.trim());
      if (res['ok'] == true) {
        if (mounted) Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const ChatScreen()));
      } else {
        setState(() => _regError = res['error'] ?? '注册失败');
      }
    } catch (_) {
      setState(() => _regError = '网络错误，请检查服务器地址');
    }
    if (mounted) setState(() => _regLoading = false);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _serverCtrl.dispose();
    _pingDebounce?.cancel();
    _loginUserCtrl.dispose();
    _loginPassCtrl.dispose();
    _regUserCtrl.dispose();
    _regPassCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      body: SafeArea(
        child: Column(children: [
          // ── 顶部：服务器地址 + 设置图标 ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(children: [
              const Icon(Icons.dns_outlined, color: Colors.grey, size: 18),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _serverCtrl,
                onChanged: _onServerChanged,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '服务器地址（如 192.168.1.1:3900）',
                  hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF16213E),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
              )),
              const SizedBox(width: 8),
              // 状态灯
              _pinging
                  ? const SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
                  : Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _pingStatus == null ? Colors.grey[600]
                            : _pingStatus! ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                    ),
              // 设置图标
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.grey, size: 20),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ]),
          ),

          // ── Logo + 标题 ──────────────────────────────────────────────────
          const SizedBox(height: 16),
          const Text('🦞', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 6),
          const Text('ClawChat',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text('OpenClaw AI 专用客户端',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 24),

          // ── TabBar ──────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabCtrl,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              indicator: BoxDecoration(
                color: const Color(0xFFE94560),
                borderRadius: BorderRadius.circular(12),
              ),
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: '登录'), Tab(text: '注册')],
            ),
          ),
          const SizedBox(height: 8),

          // ── Tab 内容 ─────────────────────────────────────────────────────
          Expanded(child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildLoginTab(),
              _buildRegisterTab(),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(children: [
        _inputField(_loginUserCtrl, '用户名', false, Icons.person_outline,
            onSubmit: (_) => _login()),
        const SizedBox(height: 12),
        _inputField(_loginPassCtrl, '密码', true, Icons.lock_outline,
            onSubmit: (_) => _login()),
        if (_loginError != null) ...[
          const SizedBox(height: 12),
          Text(_loginError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _loginLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              disabledBackgroundColor: const Color(0xFFE94560).withOpacity(0.5),
            ),
            child: _loginLoading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('登录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _buildRegisterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(children: [
        _inputField(_regUserCtrl, '用户名', false, Icons.person_outline,
            onSubmit: (_) => _register()),
        const SizedBox(height: 12),
        _inputField(_regPassCtrl, '密码（至少6位）', true, Icons.lock_outline,
            onSubmit: (_) => _register()),
        const SizedBox(height: 12),
        _inputField(_inviteCtrl, '邀请码（可选）', false, Icons.card_giftcard,
            onSubmit: (_) => _register()),
        if (_isFirstUser)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.greenAccent, size: 14),
              const SizedBox(width: 4),
              Expanded(child: Text('首位用户无需邀请码，将自动成为管理员',
                  style: TextStyle(color: Colors.greenAccent[400], fontSize: 12))),
            ]),
          ),
        if (_regError != null) ...[
          const SizedBox(height: 12),
          Text(_regError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _regLoading ? null : _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              disabledBackgroundColor: const Color(0xFFE94560).withOpacity(0.5),
            ),
            child: _regLoading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('注册', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _inputField(TextEditingController c, String hint, bool obscure, IconData icon,
      {void Function(String)? onSubmit}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      onSubmitted: onSubmit,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
        filled: true,
        fillColor: const Color(0xFF16213E),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE94560))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
