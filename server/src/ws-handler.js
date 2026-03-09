import { WebSocketServer } from 'ws';
import { verifyToken } from './auth.js';
import { streamFromGateway } from './gateway.js';
import db from './db.js';
import { v4 as uuid } from 'uuid';
import { parseAndExecCommand } from './routes/commands.js';
import logger from './utils/logger.js';

/**
 * Parse and strip <!--buttons:...--> marker from AI response.
 * Returns { text, buttons } where buttons is a 2D array or null.
 */
function parseButtons(fullResponse) {
  const marker = /<!--buttons:([\s\S]*?)-->/;
  const match = fullResponse.match(marker);
  if (!match) return { text: fullResponse, buttons: null };
  try {
    const buttons = JSON.parse(match[1]);
    if (!Array.isArray(buttons)) return { text: fullResponse, buttons: null };
    const text = fullResponse.replace(marker, '').trim();
    return { text, buttons };
  } catch {
    return { text: fullResponse, buttons: null };
  }
}

const clients = new Map();

export function setupWebSocket(server) {
  const wss = new WebSocketServer({ server, path: '/ws' });
  wss.on('connection', (ws, req) => {
    let user = null;
    const authTimeout = setTimeout(() => { if (!user) ws.close(4001, 'Auth timeout'); }, 30000);

    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw); } catch { return ws.send(JSON.stringify({ error: 'Invalid JSON' })); }

      // 认证握手
      if (msg.type === 'auth') {
        try {
          user = verifyToken(msg.token);
          // 检查账号状态
          const dbUser = db.prepare("SELECT status FROM users WHERE id = ?").get(user.id);
          if (!dbUser || dbUser.status === 'banned') {
            ws.send(JSON.stringify({ type: 'auth_error', error: '账号已被封禁' }));
            return ws.close(4003, 'Banned');
          }
          clearTimeout(authTimeout);
          if (!clients.has(user.id)) clients.set(user.id, new Set());
          clients.get(user.id).add(ws);
          ws.send(JSON.stringify({ type: 'auth_ok', user: { id: user.id, username: user.username } }));
        } catch {
          ws.send(JSON.stringify({ type: 'auth_error', error: 'Invalid token' }));
          ws.close(4003, 'Auth failed');
        }
        return;
      }

      if (!user) return ws.send(JSON.stringify({ error: 'Not authenticated' }));

      if (msg.type === 'message') await handleMessage(ws, user, msg);
      if (msg.type === 'callback') await handleCallback(ws, user, msg);
    });

    ws.on('close', () => {
      clearTimeout(authTimeout);
      if (user && clients.has(user.id)) {
        clients.get(user.id).delete(ws);
        if (clients.get(user.id).size === 0) clients.delete(user.id);
      }
    });
    ws.on('error', (err) => logger.error('WS error:', err.message));
  });
  return wss;
}

async function handleMessage(ws, user, msg) {
  const content    = (msg.content || '').trim();
  const fileId     = msg.fileId   || null;
  const fileName   = msg.fileName || null;
  const fileType   = msg.fileType || null;   // 'image' | 'video' | 'audio' | 'document'
  const fileMime   = msg.fileMime || null;
  const sessionKey = msg.sessionKey || 'main';

  // 必须有内容或附件
  if (!content && !fileId) return;
  if (content.length > 50000) return;

  // ── 斜杠命令拦截 ─────────────────────────────────────────────────────────
  if (content.startsWith('/')) {
    try {
      const cmdResult = await parseAndExecCommand(content, user.id);
      if (cmdResult && cmdResult.matched) {
        // /clear 特殊处理
        if (cmdResult.key === 'clear' && cmdResult.output === '__CLEAR__') {
          const session = db.prepare('SELECT id FROM sessions WHERE user_id = ? AND session_key = ?').get(user.id, sessionKey);
          if (session) {
            db.prepare('DELETE FROM messages WHERE user_id = ? AND session_key = ?').run(user.id, sessionKey);
            broadcast(user.id, { type: 'command_result', command: '/clear', output: '✅ 对话已清空', sessionKey });
          }
          return;
        }
        // 普通命令：返回结果
        const cmdMsgId = uuid();
        db.prepare('INSERT INTO messages (id, user_id, role, content, session_key) VALUES (?, ?, \'user\', ?, ?)').run(cmdMsgId, user.id, content, sessionKey);
        broadcast(user.id, { type: 'message', id: cmdMsgId, role: 'user', content, sessionKey, ts: Date.now() });

        const resMsgId = uuid();
        const output = cmdResult.output || '（无输出）';
        db.prepare('INSERT INTO messages (id, user_id, role, content, session_key) VALUES (?, ?, \'assistant\', ?, ?)').run(resMsgId, user.id, output, sessionKey);
        broadcast(user.id, { type: 'message', id: resMsgId, role: 'assistant', content: output, sessionKey, ts: Date.now() });
        return;
      }
    } catch (err) {
      logger.error('Command exec error:', err.message);
    }
  }

  // v2: 获取用户的 agent_id
  const userRecord = db.prepare('SELECT agent_id, role FROM users WHERE id = ?').get(user.id);
  const agentId = userRecord?.agent_id || (userRecord?.role === 'admin' ? 'main' : `clawchat-${user.id}`);

  // 校验该 session 属于当前用户
  let session = db.prepare(`SELECT id, title FROM sessions WHERE user_id = ? AND session_key = ?`).get(user.id, sessionKey);
  if (!session) {
    ws.send(JSON.stringify({ error: '会话不存在' }));
    return;
  }

  const userMsgId = uuid();
  db.prepare(`
    INSERT INTO messages (id, user_id, role, content, content_type, file_id, file_name, session_key)
    VALUES (?, ?, 'user', ?, ?, ?, ?, ?)
  `).run(userMsgId, user.id, content || (fileName || '文件'), fileType || 'text', fileId, fileName, sessionKey);

  // 更新 session 的 updated_at
  db.prepare(`UPDATE sessions SET updated_at = unixepoch() WHERE user_id = ? AND session_key = ?`).run(user.id, sessionKey);

  // 广播用户消息给自己的所有连接（多端同步）
  broadcast(user.id, {
    type: 'message', id: userMsgId, role: 'user',
    content, fileId, fileName, fileType, fileMime,
    sessionKey, ts: Date.now(),
  });

  // 构造发往 AI 的消息历史
  const history = db.prepare(`
    SELECT role, content FROM messages
    WHERE user_id = ? AND session_key = ?
    ORDER BY created_at DESC LIMIT 20
  `).all(user.id, sessionKey).reverse();

  // 最后一条用户消息的 AI 可见内容
  const aiContent = fileId
    ? `${content ? content + '\n' : ''}[用户发送了${fileType === 'image' ? '图片' : fileType === 'video' ? '视频' : fileType === 'audio' ? '音频' : '文件'}: ${fileName || fileId}]`
    : content;

  // 替换 history 中最后一条 user 消息的 content 为 aiContent
  const aiHistory = history.map((m, i) =>
    (i === history.length - 1 && m.role === 'user') ? { role: 'user', content: aiContent } : m
  );

  const assistantMsgId = uuid();
  let fullResponse = '';
  try {
    broadcast(user.id, { type: 'stream_start', id: assistantMsgId, sessionKey });
    for await (const chunk of streamFromGateway(aiHistory, `clawchat:${user.id}:${sessionKey}`, agentId)) {
      fullResponse += chunk;
      broadcast(user.id, { type: 'stream_chunk', id: assistantMsgId, content: chunk, sessionKey });
    }
    const { text: cleanText, buttons: parsedButtons } = parseButtons(fullResponse);
    broadcast(user.id, { type: 'stream_end', id: assistantMsgId, sessionKey, buttons: parsedButtons });
    db.prepare(`
      INSERT INTO messages (id, user_id, role, content, buttons, session_key) VALUES (?, ?, 'assistant', ?, ?, ?)
    `).run(assistantMsgId, user.id, cleanText, parsedButtons ? JSON.stringify(parsedButtons) : null, sessionKey);

    // 更新 session updated_at
    db.prepare(`UPDATE sessions SET updated_at = unixepoch() WHERE user_id = ? AND session_key = ?`).run(user.id, sessionKey);

    // 自动命名 session：若 title = '新对话'，取 AI 回复前 20 字作为标题
    if ((session.title === '新对话' || session.title === '') && cleanText.length > 0) {
      const autoTitle = cleanText.slice(0, 20).replace(/\n/g, ' ').trim();
      const changed = db.prepare(
        `UPDATE sessions SET title = ? WHERE user_id = ? AND session_key = ? AND (title = '新对话' OR title = '')`
      ).run(autoTitle, user.id, sessionKey);
      if (changed.changes > 0) {
        broadcast(user.id, { type: 'session_renamed', sessionKey, title: autoTitle });
      }
    }
  } catch (err) {
    logger.error('Gateway stream error:', err.message);
    broadcast(user.id, { type: 'error', message: 'AI 回复失败，请重试' });
  }
}

async function handleCallback(ws, user, msg) {
  const callbackData = (msg.callbackData || '').trim();
  const sessionKey   = msg.sessionKey || 'main';
  if (!callbackData) return;

  // Get user's agent_id
  const userRecord = db.prepare('SELECT agent_id, role FROM users WHERE id = ?').get(user.id);
  const agentId = userRecord?.agent_id || (userRecord?.role === 'admin' ? 'main' : `clawchat-${user.id}`);

  // Send callback as a user message to the AI
  const history = db.prepare(`
    SELECT role, content FROM messages
    WHERE user_id = ? AND session_key = ?
    ORDER BY created_at DESC LIMIT 20
  `).all(user.id, sessionKey).reverse();

  // Add callback as user message
  history.push({ role: 'user', content: callbackData });

  const assistantMsgId = uuid();
  let fullResponse = '';
  try {
    broadcast(user.id, { type: 'stream_start', id: assistantMsgId, sessionKey });
    for await (const chunk of streamFromGateway(history, `clawchat:${user.id}:${sessionKey}`, agentId)) {
      fullResponse += chunk;
      broadcast(user.id, { type: 'stream_chunk', id: assistantMsgId, content: chunk, sessionKey });
    }
    const { text: cbCleanText, buttons: cbButtons } = parseButtons(fullResponse);
    broadcast(user.id, { type: 'stream_end', id: assistantMsgId, sessionKey, buttons: cbButtons });
    db.prepare(`
      INSERT INTO messages (id, user_id, role, content, session_key, callback_data) VALUES (?, ?, 'user', ?, ?, ?)
    `).run(uuid(), user.id, callbackData, sessionKey, callbackData);
    db.prepare(`
      INSERT INTO messages (id, user_id, role, content, buttons, session_key) VALUES (?, ?, 'assistant', ?, ?, ?)
    `).run(assistantMsgId, user.id, cbCleanText, cbButtons ? JSON.stringify(cbButtons) : null, sessionKey);
  } catch (err) {
    logger.error('Callback error:', err.message);
    broadcast(user.id, { type: 'error', message: '回调处理失败' });
  }
}

function broadcast(userId, data) {
  const sockets = clients.get(userId);
  if (!sockets) return;
  const payload = JSON.stringify(data);
  for (const ws of sockets) if (ws.readyState === 1) ws.send(payload);
}
