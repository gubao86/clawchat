import { Router } from 'express';
import { authMiddleware } from '../auth.js';
import db from '../db.js';
import { randomUUID } from 'crypto';

const router = Router();
router.use(authMiddleware);

// GET /sessions — 列出当前用户所有会话（含 lastMessage 预览 + updatedAt）
router.get('/', (req, res) => {
  const sessions = db.prepare(`
    SELECT s.session_key AS key, s.title, s.updated_at,
      (SELECT content FROM messages
       WHERE user_id = s.user_id AND session_key = s.session_key
       ORDER BY created_at DESC LIMIT 1) AS lastMessage
    FROM sessions s
    WHERE s.user_id = ?
    ORDER BY s.updated_at DESC
  `).all(req.user.id);
  res.json({ ok: true, sessions });
});

// POST /sessions — 创建新会话
router.post('/', (req, res) => {
  const key = randomUUID();
  db.prepare(`
    INSERT INTO sessions (id, user_id, session_key, title) VALUES (?, ?, ?, '新对话')
  `).run(randomUUID(), req.user.id, key);
  res.json({ ok: true, session: { key, title: '新对话', updated_at: Math.floor(Date.now() / 1000) } });
});

// PATCH /sessions/:key — 修改标题
router.patch('/:key', (req, res) => {
  const { title } = req.body;
  if (!title || typeof title !== 'string') return res.status(400).json({ error: '标题不能为空' });
  const info = db.prepare(`
    UPDATE sessions SET title = ? WHERE user_id = ? AND session_key = ?
  `).run(title.slice(0, 50), req.user.id, req.params.key);
  if (info.changes === 0) return res.status(404).json({ error: '会话不存在' });
  res.json({ ok: true });
});

// DELETE /sessions/:key — 删除会话及消息（main session 禁止删除）
router.delete('/:key', (req, res) => {
  if (req.params.key === 'main') return res.status(400).json({ error: '主会话不能删除' });
  db.prepare(`DELETE FROM messages WHERE user_id = ? AND session_key = ?`).run(req.user.id, req.params.key);
  const info = db.prepare(`DELETE FROM sessions WHERE user_id = ? AND session_key = ?`).run(req.user.id, req.params.key);
  if (info.changes === 0) return res.status(404).json({ error: '会话不存在' });
  res.json({ ok: true });
});

export default router;
