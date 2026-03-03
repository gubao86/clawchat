import { Router } from 'express';
import pkg from 'bcryptjs';
import { v4 as uuid } from 'uuid';
const { hashSync, compareSync } = pkg;
import { signToken, authMiddleware } from '../auth.js';
import db from '../db.js';
import rateLimit from 'express-rate-limit';
import config from '../config.js';

const router = Router();
const limiter = rateLimit(config.authRateLimit);

// 查询是否首位用户（注册页用于判断是否显示邀请码提示）
router.get('/check-first', (req, res) => {
  const n = db.prepare("SELECT COUNT(*) AS n FROM users").get().n;
  res.json({ isFirst: n === 0 });
});

router.post('/register', limiter, (req, res) => {
  const { username, password, inviteCode } = req.body;
  if (!username || !password) return res.status(400).json({ error: '请填写用户名和密码' });
  if (username.length < 2 || username.length > 32)
    return res.status(400).json({ error: '用户名长度 2-32 位' });
  if (password.length < 6 || password.length > 128)
    return res.status(400).json({ error: '密码长度 6-128 位' });

  // 判断是否为首位用户（首位用户无需邀请码，自动成为管理员）
  const userCount = db.prepare("SELECT COUNT(*) AS n FROM users").get().n;
  const isFirst = userCount === 0;

  if (!isFirst) {
    // 非首位用户必须填写邀请码
    if (!inviteCode) return res.status(400).json({ error: '请填写邀请码' });

    const now = Math.floor(Date.now() / 1000);
    const code = db.prepare(`
      SELECT * FROM invite_codes
      WHERE code = ?
        AND (expires_at IS NULL OR expires_at > ?)
        AND use_count < max_uses
    `).get(inviteCode.trim().toUpperCase(), now);

    if (!code) return res.status(400).json({ error: '邀请码无效或已过期' });

    // 检查用户名是否已存在
    if (db.prepare("SELECT id FROM users WHERE username = ?").get(username))
      return res.status(409).json({ error: '用户名已被占用' });

    const id = uuid();
    const hash = hashSync(password, 12);
    db.prepare(`INSERT INTO users (id, username, password_hash, role, status, invited_by) VALUES (?, ?, ?, 'user', 'active', ?)`
    ).run(id, username, hash, code.created_by);

    // 消耗邀请码次数
    db.prepare("UPDATE invite_codes SET use_count = use_count + 1, used_by = ?, used_at = ? WHERE code = ?")
      .run(id, now, code.code);

    // 创建 main session
    try {
      db.prepare(`INSERT INTO sessions (id, user_id, session_key, title) VALUES (?, ?, 'main', '主对话')`).run(uuid(), id);
    } catch {}

    const token = signToken({ id, username });
    return res.json({ ok: true, token, user: { id, username, role: 'user' } });
  }

  // 首位用户：不需要邀请码，自动成为 admin
  if (db.prepare("SELECT id FROM users WHERE username = ?").get(username))
    return res.status(409).json({ error: '用户名已被占用' });

  const id = uuid();
  const hash = hashSync(password, 12);
  db.prepare(`INSERT INTO users (id, username, password_hash, role, status) VALUES (?, ?, ?, 'admin', 'active')`
  ).run(id, username, hash);

  // 创建 main session
  try {
    db.prepare(`INSERT INTO sessions (id, user_id, session_key, title) VALUES (?, ?, 'main', '主对话')`).run(uuid(), id);
  } catch {}

  const token = signToken({ id, username });
  res.json({ ok: true, token, user: { id, username, role: 'admin' }, isFirstUser: true });
});

router.post('/login', limiter, (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ error: '请填写用户名和密码' });

  const user = db.prepare("SELECT * FROM users WHERE username = ?").get(username);
  if (!user || !compareSync(password, user.password_hash))
    return res.status(401).json({ error: '用户名或密码错误' });

  if (user.status === 'banned') return res.status(403).json({ error: '账号已被封禁' });

  const token = signToken({ id: user.id, username: user.username });
  res.json({ ok: true, token, user: { id: user.id, username: user.username, role: user.role } });
});

// POST /auth/refresh — 需要有效 Token，返回新 Token（24h）
router.post('/refresh', authMiddleware, (req, res) => {
  const user = db.prepare("SELECT id, username, role, status FROM users WHERE id = ?").get(req.user.id);
  if (!user || user.status === 'banned') return res.status(403).json({ error: '账号异常' });
  const token = signToken({ id: user.id, username: user.username });
  res.json({ ok: true, token });
});

// POST /auth/change-password — 验证旧密码，设置新密码
router.post('/change-password', authMiddleware, (req, res) => {
  const { oldPassword, newPassword } = req.body;
  if (!oldPassword || !newPassword) return res.status(400).json({ error: '请填写旧密码和新密码' });
  if (newPassword.length < 6 || newPassword.length > 128)
    return res.status(400).json({ error: '新密码长度 6-128 位' });

  const user = db.prepare("SELECT password_hash FROM users WHERE id = ?").get(req.user.id);
  if (!user || !compareSync(oldPassword, user.password_hash))
    return res.status(401).json({ error: '旧密码错误' });

  const hash = hashSync(newPassword, 12);
  db.prepare("UPDATE users SET password_hash = ? WHERE id = ?").run(hash, req.user.id);
  res.json({ ok: true });
});

export default router;
