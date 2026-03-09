// ══════════════════════════════════════════════════════════════════
//  ClawChat PWA Client
// ══════════════════════════════════════════════════════════════════
const API    = location.origin;
const WS_URL = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`;

let token     = localStorage.getItem('token');
let userRole  = localStorage.getItem('userRole') || 'user';
let ws        = null;
let reconnectTimer = null;
let currentStreamId = null;
let streamBuffer    = '';
let isRegistering   = false;

// 待上传文件
let pendingFile = null;   // { id, name, type, mime, url }

// ── OpenClaw 完整命令定义（与服务端 commands.js 保持同步）──────────────────
let COMMANDS = [];   // 从服务端 /commands/list 加载
let isAdmin  = false;

// ══════════════════════════════════════════════════════════════════
//  登录/注册
// ══════════════════════════════════════════════════════════════════
function toggleRegister() {
  isRegistering = !isRegistering;
  const btn       = document.querySelector('#login-page .btn-secondary');
  const inviteRow = document.getElementById('invite-row');
  const hint      = document.getElementById('first-user-hint');
  btn.textContent = isRegistering ? '切换到登录' : '注册账号';
  inviteRow.style.display = isRegistering ? 'block' : 'none';
  document.getElementById('auth-error').textContent = '';

  if (isRegistering) {
    // 判断是否首位用户
    fetch(`${API}/auth/check-first`).then(r => r.json()).then(d => {
      hint.style.display = (d.isFirst) ? 'block' : 'none';
      document.getElementById('invite-code').required = !d.isFirst;
    }).catch(() => {});
  } else {
    hint.style.display = 'none';
  }
}

async function doLogin() {
  if (isRegistering) return doRegister();
  const username = document.getElementById('username').value.trim();
  const password = document.getElementById('password').value;
  if (!username || !password) return showAuthError('请填写用户名和密码');
  try {
    const res  = await fetch(`${API}/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });
    const data = await res.json();
    if (!res.ok) return showAuthError(data.error || '登录失败');
    saveSession(data);
    showChat();
  } catch { showAuthError('网络错误'); }
}

async function doRegister() {
  const username   = document.getElementById('username').value.trim();
  const password   = document.getElementById('password').value;
  const inviteCode = document.getElementById('invite-code').value.trim();
  if (!username || !password) return showAuthError('请填写用户名和密码');
  if (password.length < 6) return showAuthError('密码至少6位');
  try {
    const res  = await fetch(`${API}/auth/register`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password, inviteCode })
    });
    const data = await res.json();
    if (!res.ok) return showAuthError(data.error || '注册失败');
    if (data.isFirstUser) showAuthError('🎉 已成为管理员，欢迎！');
    saveSession(data);
    showChat();
  } catch { showAuthError('网络错误'); }
}

function saveSession(data) {
  token    = data.token;
  userRole = data.user.role || 'user';
  localStorage.setItem('token',    token);
  localStorage.setItem('username', data.user.username);
  localStorage.setItem('userRole', userRole);
}

function doLogout() {
  token = null;
  localStorage.removeItem('token');
  localStorage.removeItem('username');
  localStorage.removeItem('userRole');
  if (ws) ws.close();
  document.getElementById('login-page').style.display = 'flex';
  document.getElementById('chat-page').style.display  = 'none';
  document.getElementById('messages').innerHTML = '';
  isRegistering = false;
}

function showAuthError(msg) { document.getElementById('auth-error').textContent = msg; }

// ══════════════════════════════════════════════════════════════════
//  WebSocket
// ══════════════════════════════════════════════════════════════════
function connectWS() {
  if (ws && ws.readyState <= 1) return;
  ws = new WebSocket(WS_URL);
  ws.onopen = () => {
    ws.send(JSON.stringify({ type: 'auth', token }));
    setStatus('已连接', true);
  };
  ws.onmessage = (e) => handleWSMessage(JSON.parse(e.data));
  ws.onclose   = () => {
    setStatus('已断开', false);
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(connectWS, 3000);
  };
  ws.onerror = () => ws.close();
}

function handleWSMessage(msg) {
  switch (msg.type) {
    case 'auth_ok':
      loadHistory();
      loadCommandDefs();
      if (userRole === 'admin') document.getElementById('admin-btn').style.display = 'flex';
      break;
    case 'auth_error': doLogout(); break;
    case 'message':
      if (msg.role === 'user' || msg.role === 'assistant') addMessage(msg);
      break;
    case 'stream_start':
      currentStreamId = msg.id; streamBuffer = ''; showTyping(true); addStreamBubble(msg.id);
      break;
    case 'stream_chunk':
      streamBuffer += msg.content; updateStreamBubble(msg.id, streamBuffer);
      break;
    case 'stream_end':
      showTyping(false); finalizeStream(msg.id, streamBuffer);
      currentStreamId = null; streamBuffer = '';
      break;
    case 'error':
      showTyping(false); addSystemMsg('⚠️ ' + msg.message); break;
  }
}

function setStatus(text, online) {
  const el = document.getElementById('conn-status');
  el.textContent = text;
  el.className   = 'status' + (online ? ' online' : '');
}

// ══════════════════════════════════════════════════════════════════
//  消息显示
// ══════════════════════════════════════════════════════════════════
function addMessage(msg) {
  const container = document.getElementById('messages');
  const div = document.createElement('div');
  div.className = `msg ${msg.role}`;
  if (msg.id) div.dataset.id = msg.id;

  const time = msg.ts
    ? new Date(msg.ts).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    : '';

  let bubbleHtml = '';

  // 文件消息
  if (msg.fileId) {
    const fileUrl = `${API}/files/${msg.fileId}`;
    if (msg.fileType === 'image') {
      bubbleHtml = `<div class="bubble bubble-media">
        ${msg.content ? `<div class="file-caption">${escapeHtml(msg.content)}</div>` : ''}
        <img src="${fileUrl}" alt="${escapeHtml(msg.fileName || '图片')}" class="msg-image"
             onclick="openLightbox('${fileUrl}')" loading="lazy">
      </div>`;
    } else if (msg.fileType === 'video') {
      bubbleHtml = `<div class="bubble bubble-media">
        ${msg.content ? `<div class="file-caption">${escapeHtml(msg.content)}</div>` : ''}
        <video controls class="msg-video"><source src="${fileUrl}" type="${msg.fileMime || 'video/mp4'}"></video>
      </div>`;
    } else if (msg.fileType === 'audio') {
      bubbleHtml = `<div class="bubble bubble-media">
        ${msg.content ? `<div class="file-caption">${escapeHtml(msg.content)}</div>` : ''}
        <audio controls class="msg-audio"><source src="${fileUrl}" type="${msg.fileMime || 'audio/mpeg'}"></audio>
      </div>`;
    } else {
      bubbleHtml = `<div class="bubble bubble-file">
        <a href="${fileUrl}" target="_blank" class="file-download-link">
          <span class="file-icon">${fileIcon(msg.fileMime)}</span>
          <span class="file-info"><b>${escapeHtml(msg.fileName || '文件')}</b></span>
          <span class="file-dl">⬇</span>
        </a>
        ${msg.content ? `<div class="file-caption">${escapeHtml(msg.content)}</div>` : ''}
      </div>`;
    }
  } else {
    // 普通文本消息（支持 markdown 基础格式）
    const textHtml = msg.role === 'assistant' ? simpleMarkdown(msg.content || '') : escapeHtml(msg.content || '');
    bubbleHtml = `<div class="bubble">${textHtml}</div>`;
  }

  // v2: inline buttons 渲染
  if (msg.buttons && Array.isArray(msg.buttons) && msg.buttons.length > 0) {
    bubbleHtml += renderInlineButtons(msg.buttons);
  }

  div.innerHTML = bubbleHtml + (time ? `<span class="time">${time}</span>` : '');
  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
}

function fileIcon(mime) {
  if (!mime) return '📄';
  if (mime.includes('pdf'))   return '📕';
  if (mime.includes('text'))  return '📃';
  return '📎';
}

function addSystemMsg(text) {
  const container = document.getElementById('messages');
  const div = document.createElement('div');
  div.className = 'msg system';
  div.innerHTML = `<div class="bubble">${escapeHtml(text)}</div>`;
  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
}

// 命令结果气泡（特殊样式）
function addCommandResult(title, output, isError) {
  const container = document.getElementById('messages');
  const div = document.createElement('div');
  div.className = 'msg system';
  div.innerHTML = `<div class="bubble bubble-cmd ${isError ? 'bubble-cmd-error' : ''}">
    <div class="cmd-result-title">${escapeHtml(title)}</div>
    <pre class="cmd-result-body">${escapeHtml(output)}</pre>
  </div>`;
  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
}

function addStreamBubble(id) {
  const container = document.getElementById('messages');
  const div = document.createElement('div');
  div.className = 'msg assistant'; div.id = `stream-${id}`;
  div.innerHTML = `<div class="bubble">▌</div>`;
  container.appendChild(div); container.scrollTop = container.scrollHeight;
}

function updateStreamBubble(id, content) {
  const el = document.getElementById(`stream-${id}`);
  if (el) el.querySelector('.bubble').textContent = content + '▌';
  document.getElementById('messages').scrollTop = 99999;
}

function finalizeStream(id, content) {
  const el = document.getElementById(`stream-${id}`);
  if (el) el.querySelector('.bubble').textContent = content;
}

function showTyping(show) {
  document.getElementById('typing').style.display = show ? 'block' : 'none';
}

function escapeHtml(text) {
  const d = document.createElement('div'); d.textContent = text; return d.innerHTML;
}

// 图片灯箱
function openLightbox(url) {
  let lb = document.getElementById('lightbox');
  if (!lb) {
    lb = document.createElement('div');
    lb.id = 'lightbox';
    lb.onclick = () => lb.style.display = 'none';
    lb.innerHTML = '<img id="lb-img">';
    document.body.appendChild(lb);
  }
  document.getElementById('lb-img').src = url;
  lb.style.display = 'flex';
}

// ══════════════════════════════════════════════════════════════════
//  发送消息 & 输入处理
// ══════════════════════════════════════════════════════════════════
//  Inline Buttons
// ══════════════════════════════════════════════════════════════════
function renderInlineButtons(buttons) {
  let html = '<div class="inline-buttons">';
  for (const row of buttons) {
    html += '<div class="btn-row">';
    for (const btn of row) {
      const style = btn.style || 'default';
      html += `<button class="inline-btn inline-btn-${style}" onclick="sendCallback('${escapeHtml(btn.callback_data || btn.callbackData || '')}')">${escapeHtml(btn.text)}</button>`;
    }
    html += '</div>';
  }
  html += '</div>';
  return html;
}

function sendCallback(callbackData) {
  if (!ws || ws.readyState !== 1) return;
  // Disable clicked button, show loading
  event.target.disabled = true;
  event.target.textContent = '⏳';
  ws.send(JSON.stringify({ type: 'callback', callbackData }));
}

function simpleMarkdown(text) {
  return escapeHtml(text)
    .replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\n/g, '<br>');
}

// ══════════════════════════════════════════════════════════════════
async function sendMessage() {
  const input   = document.getElementById('input');
  const content = input.value.trim();

  // 命令优先处理
  if (content.startsWith('/') && content.length > 1) {
    hideCmdPalette();
    input.value = ''; input.style.height = '44px';
    // /clear 本地处理，其他命令通过 WS 发送（服务端返回 buttons）
    if (content.trim().toLowerCase() === '/clear') {
      await clearHistory();
      return;
    }
    ws.send(JSON.stringify({ type: 'message', content: content.trim() }));
    return;
  }

  // 普通消息（可带附件）
  if (!content && !pendingFile) return showChatError('请输入消息或选择文件');
  if (!ws || ws.readyState !== 1) return showChatError('未连接到服务器，请稍候');

  let fileId = null, fileName = null, fileType = null, fileMime = null;

  if (pendingFile) {
    try {
      ({ fileId, fileName, fileType, fileMime } = await uploadFile(pendingFile.file));
    } catch (e) {
      return showChatError('文件上传失败：' + e.message);
    }
    clearFilePreview();
  }

  ws.send(JSON.stringify({ type: 'message', content, fileId, fileName, fileType, fileMime }));
  input.value = ''; input.style.height = '44px';
}

function handleKey(e) {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage(); }
  if (e.key === 'Escape') hideCmdPalette();
  if (e.key === 'ArrowDown' && document.getElementById('cmd-palette').style.display !== 'none') {
    e.preventDefault(); moveCmdSelection(1);
  }
  if (e.key === 'ArrowUp' && document.getElementById('cmd-palette').style.display !== 'none') {
    e.preventDefault(); moveCmdSelection(-1);
  }
}

function handleInput(el) {
  el.style.height = '44px';
  el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  const val = el.value;
  if (val === '/' || (val.startsWith('/') && !val.includes(' '))) {
    showCmdPalette(val.slice(1));
  } else {
    hideCmdPalette();
  }
}

function showChatError(msg) {
  const el = document.getElementById('chat-error');
  el.textContent = msg; el.style.display = 'block';
  setTimeout(() => el.style.display = 'none', 3000);
}

// ══════════════════════════════════════════════════════════════════
//  文件上传
// ══════════════════════════════════════════════════════════════════
function handleFileSelect(input) {
  const file = input.files[0];
  if (!file) return;
  input.value = '';

  const maxMB = 50;
  if (file.size > maxMB * 1024 * 1024) return showChatError(`文件大小不能超过 ${maxMB}MB`);

  let fileType = 'document';
  if (file.type.startsWith('image/'))  fileType = 'image';
  else if (file.type.startsWith('video/')) fileType = 'video';
  else if (file.type.startsWith('audio/')) fileType = 'audio';

  pendingFile = { file, name: file.name, type: fileType, mime: file.type };

  // 显示预览
  const preview = document.getElementById('file-preview');
  const content = document.getElementById('file-preview-content');
  preview.style.display = 'flex';

  if (fileType === 'image') {
    const url = URL.createObjectURL(file);
    content.innerHTML = `<img src="${url}" class="preview-img">
      <span class="preview-name">${escapeHtml(file.name)}</span>`;
  } else {
    content.innerHTML = `<span class="preview-icon">${fileType === 'video' ? '🎬' : fileType === 'audio' ? '🎵' : '📄'}</span>
      <span class="preview-name">${escapeHtml(file.name)}</span>
      <span class="preview-size">${(file.size / 1024).toFixed(0)} KB</span>`;
  }
}

async function uploadFile(file) {
  const formData = new FormData();
  formData.append('file', file);
  const res = await fetch(`${API}/files/upload`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}` },
    body: formData,
  });
  if (!res.ok) { const d = await res.json(); throw new Error(d.error || '上传失败'); }
  const data = await res.json();
  return {
    fileId:   data.file.id,
    fileName: data.file.name,
    fileType: data.file.type.startsWith('image/') ? 'image'
            : data.file.type.startsWith('video/') ? 'video'
            : data.file.type.startsWith('audio/') ? 'audio' : 'document',
    fileMime: data.file.type,
  };
}

function clearFilePreview() {
  pendingFile = null;
  document.getElementById('file-preview').style.display = 'none';
  document.getElementById('file-preview-content').innerHTML = '';
}

// ══════════════════════════════════════════════════════════════════
//  命令面板
// ══════════════════════════════════════════════════════════════════
async function loadCommandDefs() {
  try {
    const res  = await fetch(`${API}/commands/list`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    COMMANDS = data.commands || [];
    isAdmin  = data.isAdmin || false;
  } catch {}
}

let selectedCmdIndex = -1;

function showCmdPalette(query) {
  const palette = document.getElementById('cmd-palette');
  palette.style.display = 'block';
  filterCommands(query);
}

function hideCmdPalette() {
  document.getElementById('cmd-palette').style.display = 'none';
  selectedCmdIndex = -1;
}

function filterCommands(query) {
  const q = query.toLowerCase().replace(/^\//, '');
  const list = document.getElementById('cmd-list');

  const filtered = COMMANDS.filter(c =>
    !q || c.cmd.toLowerCase().includes(q) || c.desc.includes(q) || c.group.includes(q)
  );

  if (filtered.length === 0) {
    list.innerHTML = '<div class="cmd-empty">没有匹配的命令</div>';
    return;
  }

  // 分组显示
  const groups = {};
  filtered.forEach(c => {
    if (!groups[c.group]) groups[c.group] = [];
    groups[c.group].push(c);
  });

  let html = '';
  let idx  = 0;
  for (const [group, cmds] of Object.entries(groups)) {
    html += `<div class="cmd-group-label">${group}</div>`;
    for (const c of cmds) {
      const locked   = c.admin && !isAdmin;
      const noExec   = !c.exec;
      const dataIdx  = idx++;
      html += `<div class="cmd-item ${locked ? 'cmd-locked' : ''} ${noExec && !locked ? 'cmd-terminal' : ''}"
                    data-cmd="${escapeHtml(c.cmd)}" data-key="${escapeHtml(c.key)}"
                    data-idx="${dataIdx}"
                    onclick="selectCommand('${escapeHtml(c.cmd)}', ${c.exec && !c.special}, '${escapeHtml(c.argHint || '')}', '${escapeHtml(c.terminal || '')}')">
        <span class="cmd-name">${escapeHtml(c.cmd)}</span>
        <span class="cmd-desc">${escapeHtml(c.desc)}</span>
        ${locked   ? '<span class="cmd-badge cmd-badge-admin">管理员</span>' : ''}
        ${noExec && !locked ? '<span class="cmd-badge cmd-badge-term">终端</span>' : ''}
        ${c.argHint ? `<span class="cmd-arghint">${escapeHtml(c.argHint)}</span>` : ''}
      </div>`;
    }
  }
  list.innerHTML = html;
  selectedCmdIndex = -1;
}

function selectCommand(cmd, executable, argHint, terminal) {
  hideCmdPalette();
  const input = document.getElementById('input');
  // 需要参数的命令填入输入框
  if (argHint) {
    input.value = cmd + ' ';
    input.focus();
    const len = input.value.length;
    input.setSelectionRange(len, len);
    return;
  }
  // 无参数命令：直接通过 WS 发送
  input.value = '';
  if (cmd.trim().toLowerCase() === '/clear') {
    clearHistory();
  } else {
    ws.send(JSON.stringify({ type: 'message', content: cmd.trim() }));
  }
}

function moveCmdSelection(dir) {
  const items = document.querySelectorAll('#cmd-list .cmd-item');
  if (!items.length) return;
  items[Math.max(0, selectedCmdIndex)]?.classList.remove('selected');
  selectedCmdIndex = Math.max(0, Math.min(items.length - 1, selectedCmdIndex + dir));
  const sel = items[selectedCmdIndex];
  sel?.classList.add('selected');
  sel?.scrollIntoView({ block: 'nearest' });
}

// ══════════════════════════════════════════════════════════════════
//  命令执行
// ══════════════════════════════════════════════════════════════════
async function execCommand(text) {
  const parts  = text.trim().split(/\s+/);
  const cmdStr = parts[0].toLowerCase();         // e.g. "/model"
  const sub    = parts[1]?.toLowerCase() || '';  // e.g. "list"
  const args   = parts.slice(2);                 // e.g. ["deepseek/deepseek-chat"]

  // ── 特殊命令本地处理 ─────────────────────────────────────────
  if (cmdStr === '/help') {
    showHelp(); return;
  }
  if (cmdStr === '/clear') {
    await clearHistory(); return;
  }

  // ── 匹配命令键 ───────────────────────────────────────────────
  const fullCmd = sub ? `${cmdStr} ${sub}` : cmdStr;   // e.g. "/model list"
  const def = COMMANDS.find(c => c.cmd.toLowerCase() === fullCmd);
  if (!def) {
    addCommandResult(text, `未知命令：${text}\n输入 /help 查看所有可用命令`, true);
    return;
  }
  if (!def.exec) {
    addCommandResult(def.cmd, `此命令需在终端执行：\n${def.terminal || 'openclaw ' + def.key.replace(':', ' ')}`, false);
    return;
  }
  if (def.special && def.key !== 'clear') return;

  addCommandResult(def.cmd, '执行中...', false);
  try {
    const res  = await fetch(`${API}/commands/exec`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
      body: JSON.stringify({ key: def.key, args }),
    });
    const data = await res.json();
    // 替换"执行中..."气泡
    replaceLastCmdResult(def.cmd, data.output || data.error || '', !data.ok);
  } catch (e) {
    replaceLastCmdResult(def.cmd, '请求失败：' + e.message, true);
  }
}

function replaceLastCmdResult(title, output, isError) {
  const container = document.getElementById('messages');
  const items = container.querySelectorAll('.bubble-cmd');
  const last  = items[items.length - 1];
  if (last) {
    last.querySelector('.cmd-result-title').textContent = title;
    last.querySelector('.cmd-result-body').textContent  = output;
    if (isError) last.classList.add('bubble-cmd-error');
  }
}

async function clearHistory() {
  try {
    const res = await fetch(`${API}/commands/clear`, {
      method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) throw new Error();
    document.getElementById('messages').innerHTML = '';
    addSystemMsg('✅ 对话历史已清空');
  } catch { showChatError('清空失败，请重试'); }
}

function showHelp() {
  const groups = {};
  COMMANDS.forEach(c => {
    if (!groups[c.group]) groups[c.group] = [];
    groups[c.group].push(c);
  });
  let out = '📖 OpenClaw 命令列表\n\n';
  for (const [g, cmds] of Object.entries(groups)) {
    out += `${g}\n`;
    cmds.forEach(c => {
      const tag = !c.exec ? '[终端]' : c.admin ? '[管理员]' : '';
      const arg = c.argHint ? ` <${c.argHint}>` : '';
      out += `  ${c.cmd}${arg}  ${tag}\n    ${c.desc}\n`;
    });
    out += '\n';
  }
  addCommandResult('/help', out.trim(), false);
}

// ══════════════════════════════════════════════════════════════════
//  历史加载
// ══════════════════════════════════════════════════════════════════
async function loadHistory() {
  try {
    const res  = await fetch(`${API}/messages/history?limit=50`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    if (data.ok && data.messages) {
      document.getElementById('messages').innerHTML = '';
      data.messages.forEach(m => addMessage({
        role:     m.role,
        content:  m.content,
        fileId:   m.file_id,
        fileName: m.file_name,
        fileType: m.content_type !== 'text' ? m.content_type : null,
        ts:       m.created_at * 1000,
      }));
    }
  } catch (e) { console.error('Load history failed:', e); }
}

// ══════════════════════════════════════════════════════════════════
//  页面切换
// ══════════════════════════════════════════════════════════════════
function showChat() {
  document.getElementById('login-page').style.display = 'none';
  document.getElementById('chat-page').style.display  = 'flex';
  if (userRole === 'admin') document.getElementById('admin-btn').style.display = 'flex';
  connectWS();
  document.getElementById('input').focus();
}

// ══════════════════════════════════════════════════════════════════
//  初始化
// ══════════════════════════════════════════════════════════════════
if (token) showChat();

// 点击命令面板外部关闭
document.addEventListener('click', e => {
  const palette = document.getElementById('cmd-palette');
  const input   = document.getElementById('input');
  if (!palette.contains(e.target) && e.target !== input) hideCmdPalette();
});

// PWA Service Worker
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}
