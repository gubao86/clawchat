import { Router } from 'express';
import { authMiddleware } from '../auth.js';
import db from '../db.js';
import { randomBytes } from 'crypto';
import pkg from 'bcryptjs';
const { hashSync } = pkg;

const router = Router();

// 管理员鉴权中间件
function adminOnly(req, res, next) {
  const user = db.prepare("SELECT role, status FROM users WHERE id = ?").get(req.user.id);
  if (!user || user.role !== 'admin') return res.status(403).json({ error: '需要管理员权限' });
  next();
}

router.use(authMiddleware);
router.use(adminOnly);

// ── 用户管理 ──────────────────────────────────────────────────────────────

// 用户列表
router.get('/users', (req, res) => {
  const users = db.prepare(`
    SELECT id, username, role, status, invited_by, created_at FROM users ORDER BY created_at ASC
  `).all();
  res.json({ ok: true, users });
});

// 修改用户状态（active / banned）
router.patch('/users/:id/status', (req, res) => {
  const { status } = req.body;
  if (!['active', 'banned'].includes(status)) return res.status(400).json({ error: '无效状态' });
  if (req.params.id === req.user.id) return res.status(400).json({ error: '不能修改自己的状态' });
  const info = db.prepare("UPDATE users SET status = ? WHERE id = ?").run(status, req.params.id);
  if (info.changes === 0) return res.status(404).json({ error: '用户不存在' });
  res.json({ ok: true });
});

// 修改用户角色（user / admin）
router.patch('/users/:id/role', (req, res) => {
  const { role } = req.body;
  if (!['user', 'admin'].includes(role)) return res.status(400).json({ error: '无效角色' });
  if (req.params.id === req.user.id) return res.status(400).json({ error: '不能修改自己的角色' });
  const info = db.prepare("UPDATE users SET role = ? WHERE id = ?").run(role, req.params.id);
  if (info.changes === 0) return res.status(404).json({ error: '用户不存在' });
  res.json({ ok: true });
});

// 删除用户
router.delete('/users/:id', (req, res) => {
  if (req.params.id === req.user.id) return res.status(400).json({ error: '不能删除自己' });
  db.prepare("DELETE FROM messages WHERE user_id = ?").run(req.params.id);
  db.prepare("DELETE FROM sessions WHERE user_id = ?").run(req.params.id);
  const info = db.prepare("DELETE FROM users WHERE id = ?").run(req.params.id);
  if (info.changes === 0) return res.status(404).json({ error: '用户不存在' });
  res.json({ ok: true });
});

// 重置用户密码
router.post('/users/:id/reset-password', (req, res) => {
  const { mode, password } = req.body;
  if (!['random', 'manual'].includes(mode)) return res.status(400).json({ error: '无效模式' });

  let newPassword;
  if (mode === 'random') {
    newPassword = randomBytes(6).toString('hex'); // 12位随机密码
  } else {
    if (!password || password.length < 6) return res.status(400).json({ error: '密码至少6位' });
    newPassword = password;
  }

  const hash = hashSync(newPassword, 12);
  const info = db.prepare("UPDATE users SET password_hash = ? WHERE id = ?").run(hash, req.params.id);
  if (info.changes === 0) return res.status(404).json({ error: '用户不存在' });
  res.json({ ok: true, newPassword });
});

// ── 邀请码管理 ────────────────────────────────────────────────────────────

// 生成邀请码
router.post('/invite-codes', (req, res) => {
  const { maxUses = 1, expiresInDays = 7 } = req.body;
  if (maxUses < 1 || maxUses > 100) return res.status(400).json({ error: '无效使用次数' });

  const code = randomBytes(5).toString('hex').toUpperCase(); // 10位大写码，如 A1B2C3D4E5
  const expiresAt = expiresInDays
    ? Math.floor(Date.now() / 1000) + expiresInDays * 86400
    : null;

  db.prepare(`
    INSERT INTO invite_codes (code, created_by, expires_at, max_uses)
    VALUES (?, ?, ?, ?)
  `).run(code, req.user.id, expiresAt, maxUses);

  res.json({ ok: true, code, expiresAt, maxUses });
});

// 邀请码列表
router.get('/invite-codes', (req, res) => {
  const codes = db.prepare(`
    SELECT ic.code, ic.use_count, ic.max_uses, ic.expires_at, ic.created_at,
           u_creator.username AS creator,
           u_used.username AS used_by_name
    FROM invite_codes ic
    LEFT JOIN users u_creator ON ic.created_by = u_creator.id
    LEFT JOIN users u_used ON ic.used_by = u_used.id
    ORDER BY ic.created_at DESC
  `).all();
  res.json({ ok: true, codes });
});

// 撤销邀请码
router.delete('/invite-codes/:code', (req, res) => {
  const info = db.prepare("DELETE FROM invite_codes WHERE code = ?").run(req.params.code);
  if (info.changes === 0) return res.status(404).json({ error: '邀请码不存在' });
  res.json({ ok: true });
});

// ── 统计 ──────────────────────────────────────────────────────────────────

router.get('/stats', (req, res) => {
  const totalUsers   = db.prepare("SELECT COUNT(*) AS n FROM users").get().n;
  const activeUsers  = db.prepare("SELECT COUNT(*) AS n FROM users WHERE status='active'").get().n;
  const bannedUsers  = db.prepare("SELECT COUNT(*) AS n FROM users WHERE status='banned'").get().n;
  const totalMsgs    = db.prepare("SELECT COUNT(*) AS n FROM messages").get().n;
  const activeCodes  = db.prepare("SELECT COUNT(*) AS n FROM invite_codes WHERE (expires_at IS NULL OR expires_at > unixepoch()) AND (use_count < max_uses)").get().n;
  res.json({ ok: true, stats: { totalUsers, activeUsers, bannedUsers, totalMsgs, activeCodes } });
});

export default router;
