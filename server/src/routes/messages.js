import { Router } from 'express';
import { authMiddleware } from '../auth.js';
import db from '../db.js';

const router = Router();

router.get('/history', authMiddleware, (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 50, 200);
  const before = parseInt(req.query.before) || Math.floor(Date.now() / 1000) + 1;
  const sessionKey = req.query.session || 'main';

  // 校验该 session 属于当前用户
  const session = db.prepare(`SELECT id FROM sessions WHERE user_id = ? AND session_key = ?`).get(req.user.id, sessionKey);
  if (!session) return res.status(404).json({ error: '会话不存在' });

  const rows = db.prepare(
    `SELECT id, role, content, content_type, file_id, file_name, file_path, created_at
     FROM messages WHERE user_id = ? AND session_key = ? AND created_at < ?
     ORDER BY created_at DESC LIMIT ?`
  ).all(req.user.id, sessionKey, before, limit);

  res.json({ ok: true, messages: rows.reverse() });
});

export default router;
