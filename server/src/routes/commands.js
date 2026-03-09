import { Router } from 'express';
import discovery from '../command-discovery.js';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { authMiddleware } from '../auth.js';
import db from '../db.js';

const router = Router();
const execFileAsync = promisify(execFile);

// ── 命令白名单 ──────────────────────────────────────────────────────────────
// exec: true  = 可从 Web 直接执行
// admin: true = 仅管理员可执行
// args: 允许用户追加的参数位置说明
export const COMMAND_DEFS = [
  // ── 🤖 模型管理 ───────────────────────────────────────────────────────────
  { key: 'model:list',       cmd: '/model list',        desc: '列出所有可用模型',      group: '🤖 模型管理',   cli: ['models','list'],               exec: true  },
  { key: 'model:status',     cmd: '/model status',      desc: '查看模型连通状态',      group: '🤖 模型管理',   cli: ['models','status'],             exec: true  },
  { key: 'model:set',        cmd: '/model set',         desc: '切换当前使用的模型',    group: '🤖 模型管理',   cli: ['models','set'],                exec: true,  argHint: '模型ID，如 yunyi/claude-sonnet-4-6' },
  { key: 'model:aliases',    cmd: '/model aliases',     desc: '查看模型别名映射',      group: '🤖 模型管理',   cli: ['models','aliases'],            exec: true  },
  { key: 'model:fallbacks',  cmd: '/model fallbacks',   desc: '查看备用模型链',        group: '🤖 模型管理',   cli: ['models','fallbacks'],          exec: true  },
  { key: 'model:scan',       cmd: '/model scan',        desc: '扫描并更新可用模型',    group: '🤖 模型管理',   cli: ['models','scan'],               exec: true,  admin: true },
  { key: 'model:auth',       cmd: '/model auth',        desc: '管理模型 API 认证',     group: '🤖 模型管理',   cli: null,  terminal: 'openclaw models auth', exec: false },

  // ── 💬 会话管理 ───────────────────────────────────────────────────────────
  { key: 'clear',            cmd: '/clear',             desc: '清空当前对话历史',      group: '💬 会话',       cli: null,  special: true,                exec: true  },
  { key: 'sessions:cleanup', cmd: '/sessions cleanup',  desc: '清理所有过期会话',      group: '💬 会话',       cli: ['sessions','cleanup'],          exec: true,  admin: true },

  // ── 🧠 记忆管理 ───────────────────────────────────────────────────────────
  { key: 'memory:status',    cmd: '/memory status',     desc: '记忆系统状态',          group: '🧠 记忆',       cli: ['memory','status'],             exec: true  },
  { key: 'memory:search',    cmd: '/memory search',     desc: '搜索记忆内容',          group: '🧠 记忆',       cli: ['memory','search'],             exec: true,  argHint: '搜索关键词' },
  { key: 'memory:index',     cmd: '/memory index',      desc: '重建记忆索引',          group: '🧠 记忆',       cli: ['memory','index'],              exec: true,  admin: true },

  // ── 🛠️ 技能 ──────────────────────────────────────────────────────────────
  { key: 'skills:list',      cmd: '/skills list',       desc: '列出所有已安装技能',    group: '🛠️ 技能',      cli: ['skills','list'],               exec: true  },
  { key: 'skills:info',      cmd: '/skills info',       desc: '查看技能详情',          group: '🛠️ 技能',      cli: ['skills','info'],               exec: true,  argHint: '技能名称' },
  { key: 'skills:check',     cmd: '/skills check',      desc: '检查技能运行状态',      group: '🛠️ 技能',      cli: ['skills','check'],              exec: true  },

  // ── 📊 系统状态 ───────────────────────────────────────────────────────────
  { key: 'status',           cmd: '/status',            desc: '系统状态总览',          group: '📊 系统',       cli: ['status'],                      exec: true  },
  { key: 'health',           cmd: '/health',            desc: '健康检查',              group: '📊 系统',       cli: ['health'],                      exec: true  },
  { key: 'logs',             cmd: '/logs',              desc: '查看最近 30 条日志',    group: '📊 系统',       cli: ['logs','--limit','30','--plain','--no-color'], exec: true },
  { key: 'update:status',    cmd: '/update status',     desc: '检查更新状态',          group: '📊 系统',       cli: ['update','status'],             exec: true  },
  { key: 'security:audit',   cmd: '/security audit',    desc: '安全配置审计',          group: '📊 系统',       cli: ['security','audit'],            exec: true,  admin: true },
  { key: 'approvals:get',    cmd: '/approvals get',     desc: '查看操作审批规则',      group: '📊 系统',       cli: ['approvals','get'],             exec: true  },

  // ── 🌐 网关 ───────────────────────────────────────────────────────────────
  { key: 'gateway:status',   cmd: '/gateway status',    desc: '网关运行状态',          group: '🌐 网关',       cli: ['gateway','status'],            exec: true  },
  { key: 'gateway:health',   cmd: '/gateway health',    desc: '网关健康检查',          group: '🌐 网关',       cli: ['gateway','health'],            exec: true  },
  { key: 'gateway:usage',    cmd: '/gateway usage',     desc: '用量与费用统计',        group: '🌐 网关',       cli: ['gateway','usage-cost'],        exec: true  },
  { key: 'gateway:start',    cmd: '/gateway start',     desc: '启动网关服务',          group: '🌐 网关',       cli: ['gateway','start'],             exec: true,  admin: true },
  { key: 'gateway:stop',     cmd: '/gateway stop',      desc: '停止网关服务',          group: '🌐 网关',       cli: ['gateway','stop'],              exec: true,  admin: true },
  { key: 'gateway:restart',  cmd: '/gateway restart',   desc: '重启网关服务',          group: '🌐 网关',       cli: ['gateway','restart'],           exec: true,  admin: true },

  // ── 🔧 守护进程 ───────────────────────────────────────────────────────────
  { key: 'daemon:status',    cmd: '/daemon status',     desc: '守护进程状态',          group: '🔧 守护进程',   cli: ['daemon','status'],             exec: true  },
  { key: 'daemon:start',     cmd: '/daemon start',      desc: '启动守护进程',          group: '🔧 守护进程',   cli: ['daemon','start'],              exec: true,  admin: true },
  { key: 'daemon:stop',      cmd: '/daemon stop',       desc: '停止守护进程',          group: '🔧 守护进程',   cli: ['daemon','stop'],               exec: true,  admin: true },
  { key: 'daemon:restart',   cmd: '/daemon restart',    desc: '重启守护进程',          group: '🔧 守护进程',   cli: ['daemon','restart'],            exec: true,  admin: true },

  // ── 👥 代理 ───────────────────────────────────────────────────────────────
  { key: 'agents:list',      cmd: '/agents list',       desc: '列出所有代理配置',      group: '👥 代理',       cli: ['agents','list'],               exec: true  },
  { key: 'agent:run',        cmd: '/agent',             desc: '向代理发送一次性指令',  group: '👥 代理',       cli: ['agent'],                       exec: true,  argHint: '指令内容' },

  // ── ⏰ 定时任务 ───────────────────────────────────────────────────────────
  { key: 'cron:list',        cmd: '/cron list',         desc: '列出所有定时任务',      group: '⏰ 定时任务',   cli: ['cron','list'],                 exec: true  },
  { key: 'cron:status',      cmd: '/cron status',       desc: '定时任务运行状态',      group: '⏰ 定时任务',   cli: ['cron','status'],               exec: true  },
  { key: 'cron:runs',        cmd: '/cron runs',         desc: '查看任务执行历史',      group: '⏰ 定时任务',   cli: ['cron','runs'],                 exec: true  },
  { key: 'cron:run',         cmd: '/cron run',          desc: '手动触发定时任务',      group: '⏰ 定时任务',   cli: ['cron','run'],                  exec: true,  admin: true, argHint: '任务名称' },
  { key: 'cron:enable',      cmd: '/cron enable',       desc: '启用定时任务',          group: '⏰ 定时任务',   cli: ['cron','enable'],               exec: true,  admin: true, argHint: '任务名称' },
  { key: 'cron:disable',     cmd: '/cron disable',      desc: '禁用定时任务',          group: '⏰ 定时任务',   cli: ['cron','disable'],              exec: true,  admin: true, argHint: '任务名称' },

  // ── 🔌 插件 ───────────────────────────────────────────────────────────────
  { key: 'plugins:list',     cmd: '/plugins list',      desc: '列出已安装插件',        group: '🔌 插件',       cli: ['plugins','list'],              exec: true  },
  { key: 'plugins:info',     cmd: '/plugins info',      desc: '查看插件详情',          group: '🔌 插件',       cli: ['plugins','info'],              exec: true,  argHint: '插件名称' },
  { key: 'plugins:enable',   cmd: '/plugins enable',    desc: '启用插件',              group: '🔌 插件',       cli: ['plugins','enable'],            exec: true,  admin: true, argHint: '插件名称' },
  { key: 'plugins:disable',  cmd: '/plugins disable',   desc: '禁用插件',              group: '🔌 插件',       cli: ['plugins','disable'],           exec: true,  admin: true, argHint: '插件名称' },
  { key: 'plugins:doctor',   cmd: '/plugins doctor',    desc: '插件健康诊断',          group: '🔌 插件',       cli: ['plugins','doctor'],            exec: true  },

  // ── 📡 通道 ───────────────────────────────────────────────────────────────
  { key: 'channels:list',    cmd: '/channels list',     desc: '列出所有通道',          group: '📡 通道',       cli: ['channels','list'],             exec: true  },
  { key: 'channels:status',  cmd: '/channels status',   desc: '通道连接状态',          group: '📡 通道',       cli: ['channels','status'],           exec: true  },
  { key: 'channels:caps',    cmd: '/channels caps',     desc: '通道功能能力',          group: '📡 通道',       cli: ['channels','capabilities'],     exec: true  },
  { key: 'channels:logs',    cmd: '/channels logs',     desc: '通道日志',              group: '📡 通道',       cli: ['channels','logs'],             exec: true,  argHint: '通道名称（可选）' },

  // ── 🌐 节点 ───────────────────────────────────────────────────────────────
  { key: 'nodes:list',       cmd: '/nodes list',        desc: '列出所有节点',          group: '🌐 节点',       cli: ['nodes','list'],                exec: true  },
  { key: 'nodes:status',     cmd: '/nodes status',      desc: '节点运行状态',          group: '🌐 节点',       cli: ['nodes','status'],              exec: true  },
  { key: 'nodes:pending',    cmd: '/nodes pending',     desc: '待审批节点列表',        group: '🌐 节点',       cli: ['nodes','pending'],             exec: true,  admin: true },
  { key: 'nodes:approve',    cmd: '/nodes approve',     desc: '批准节点接入',          group: '🌐 节点',       cli: ['nodes','approve'],             exec: true,  admin: true, argHint: '节点ID' },
  { key: 'nodes:reject',     cmd: '/nodes reject',      desc: '拒绝节点接入',          group: '🌐 节点',       cli: ['nodes','reject'],              exec: true,  admin: true, argHint: '节点ID' },

  // ── 📱 设备 ───────────────────────────────────────────────────────────────
  { key: 'devices:list',     cmd: '/devices list',      desc: '列出已配对设备',        group: '📱 设备',       cli: ['devices','list'],              exec: true  },
  { key: 'devices:approve',  cmd: '/devices approve',   desc: '批准设备配对请求',      group: '📱 设备',       cli: ['devices','approve'],           exec: true,  admin: true, argHint: '设备ID' },
  { key: 'devices:reject',   cmd: '/devices reject',    desc: '拒绝设备配对请求',      group: '📱 设备',       cli: ['devices','reject'],            exec: true,  admin: true, argHint: '设备ID' },
  { key: 'devices:revoke',   cmd: '/devices revoke',    desc: '撤销设备访问权限',      group: '📱 设备',       cli: ['devices','revoke'],            exec: true,  admin: true, argHint: '设备ID' },

  // ── 🔍 目录 ───────────────────────────────────────────────────────────────
  { key: 'directory:self',   cmd: '/directory self',    desc: '本节点身份信息',        group: '🔍 目录',       cli: ['directory','self'],            exec: true  },
  { key: 'directory:peers',  cmd: '/directory peers',   desc: '查看对等节点',          group: '🔍 目录',       cli: ['directory','peers'],           exec: true  },
  { key: 'directory:groups', cmd: '/directory groups',  desc: '查看节点分组',          group: '🔍 目录',       cli: ['directory','groups'],          exec: true  },

  // ── 🤝 配对 ───────────────────────────────────────────────────────────────
  { key: 'pairing:list',     cmd: '/pairing list',      desc: '配对请求列表',          group: '🤝 配对',       cli: ['pairing','list'],              exec: true  },
  { key: 'pairing:approve',  cmd: '/pairing approve',   desc: '批准配对请求',          group: '🤝 配对',       cli: ['pairing','approve'],           exec: true,  admin: true, argHint: '配对ID' },

  // ── 🖥️ 高级工具 ──────────────────────────────────────────────────────────
  { key: 'browser:status',   cmd: '/browser status',    desc: '浏览器自动化状态',      group: '🖥️ 高级',      cli: ['browser','status'],            exec: true  },
  { key: 'sandbox:list',     cmd: '/sandbox list',      desc: '列出沙箱环境',          group: '🖥️ 高级',      cli: ['sandbox','list'],              exec: true  },
  { key: 'hooks:list',       cmd: '/hooks list',        desc: '列出 Git Hooks',        group: '🖥️ 高级',      cli: ['hooks','list'],                exec: true  },
  { key: 'tui',              cmd: '/tui',               desc: '终端界面（需 SSH）',    group: '🖥️ 高级',      cli: null, terminal: 'openclaw tui',      exec: false },
  { key: 'dashboard',        cmd: '/dashboard',         desc: '打开控制台（本地）',    group: '🖥️ 高级',      cli: null, terminal: 'openclaw dashboard', exec: false },
  { key: 'qr',               cmd: '/qr',                desc: '生成配对二维码',        group: '🖥️ 高级',      cli: null, terminal: 'openclaw qr',       exec: false },

  // ── ❓ 帮助 ───────────────────────────────────────────────────────────────
  { key: 'help',             cmd: '/help',              desc: '显示所有可用命令',      group: '❓ 帮助',       cli: null,  special: true,                exec: true  },
];

const CMD_MAP = Object.fromEntries(COMMAND_DEFS.map(c => [c.key, c]));

// 校验追加参数：只允许安全字符
function sanitizeArg(arg) {
  if (typeof arg !== 'string') return null;
  return /^[\w\-_./@:, ]{1,200}$/.test(arg) ? arg : null;
}

// 提供命���定义列表给前端（静态 + 动态）
router.get('/list', authMiddleware, async (req, res) => {
  const user = db.prepare("SELECT role FROM users WHERE id = ?").get(req.user.id);
  const isAdmin = user?.role === 'admin';

  // Dynamic commands from OpenClaw CLI
  let dynamicCommands = [];
  try {
    dynamicCommands = await discovery.buildHelpButtons();
  } catch (_) {}

  res.json({ ok: true, commands: COMMAND_DEFS, dynamicCommands, isAdmin });
});

// 执行命令
router.post('/exec', authMiddleware, async (req, res) => {
  const { key, args = [] } = req.body;
  const def = CMD_MAP[key];
  if (!def) return res.status(400).json({ ok: false, error: '未知命令' });
  if (!def.exec) return res.json({ ok: false, error: `此命令需在终端执行：${def.terminal}` });
  if (def.special) return res.status(400).json({ ok: false, error: '特殊命令请走专用接口' });

  // 权限检查
  if (def.admin) {
    const user = db.prepare("SELECT role FROM users WHERE id = ?").get(req.user.id);
    if (user?.role !== 'admin') return res.status(403).json({ ok: false, error: '需要管理员权限' });
  }

  // 清洗用户追加的参数
  const safeArgs = args.map(sanitizeArg).filter(Boolean);
  const cliArgs = [...def.cli, ...safeArgs];

  try {
    const { stdout, stderr } = await execFileAsync('openclaw', cliArgs, {
      timeout: 20000,
      maxBuffer: 512 * 1024,
      env: { ...process.env },
    });
    res.json({ ok: true, output: (stdout || stderr || '（无输出）').trim() });
  } catch (err) {
    const out = (err.stdout || err.stderr || err.message || '执行失败').trim();
    res.json({ ok: false, output: out });
  }
});

// /clear 专用接口：清除当前用户的聊天记录，支持 session 参数
router.delete('/clear', authMiddleware, (req, res) => {
  const sessionKey = req.query.session || 'main';
  // 校验 session 属于当前用户
  const session = db.prepare("SELECT id FROM sessions WHERE user_id = ? AND session_key = ?").get(req.user.id, sessionKey);
  if (!session) return res.status(404).json({ error: '会话不存在' });
  db.prepare("DELETE FROM messages WHERE user_id = ? AND session_key = ?").run(req.user.id, sessionKey);
  res.json({ ok: true });
});


// ── 供 ws-handler 调用的命令执行函数 ────────────────────────────────────────
export async function parseAndExecCommand(text, userId) {
  let trimmed = (text || '').trim();
  if (!trimmed.startsWith('/')) return null;

  // 命令别��映射（兼容 Telegram 风格命令）
  const ALIASES = {
    '/models': '/model list',
    '/models list': '/model list',
    '/models status': '/model status',
    '/models set': '/model set',
    '/models aliases': '/model aliases',
    '/models fallbacks': '/model fallbacks',
    '/models scan': '/model scan',
  };
  // 检查别名（保留额外参数）
  for (const [alias, target] of Object.entries(ALIASES)) {
    if (trimmed === alias || trimmed.startsWith(alias + ' ')) {
      const extra = trimmed.slice(alias.length);
      trimmed = target + extra;
      break;
    }
  }

  if (trimmed === '/help') {
    return buildHelpWithButtons();
  }

  // help_group_<group> callback
  if (trimmed.startsWith('/help_group_')) {
    const group = decodeURIComponent(trimmed.slice('/help_group_'.length));
    return buildHelpGroupDetail(group);
  }

  const parts = trimmed.slice(1).split(/\s+/);
  let bestMatch = null;
  let bestArgs = [];

  for (const def of COMMAND_DEFS) {
    const cmdParts = def.cmd.slice(1).split(/\s+/);
    if (parts.length >= cmdParts.length) {
      let match = true;
      for (let i = 0; i < cmdParts.length; i++) {
        if (parts[i].toLowerCase() !== cmdParts[i].toLowerCase()) { match = false; break; }
      }
      if (match && (!bestMatch || cmdParts.length > bestMatch.cmd.slice(1).split(/\s+/).length)) {
        bestMatch = def;
        bestArgs = parts.slice(cmdParts.length);
      }
    }
  }

  if (!bestMatch) return { matched: true, key: null, output: `❌ 未知命令: ${trimmed}\n输入 /help 查看所有可用命令` };
  if (!bestMatch.exec) return { matched: true, key: bestMatch.key, output: `⚠️ 此命令需在终端执行：${bestMatch.terminal}` };
  if (bestMatch.special && bestMatch.key === 'clear') return { matched: true, key: 'clear', output: '__CLEAR__' };
  if (bestMatch.special) return { matched: true, key: bestMatch.key, output: '⚠️ 此命令请通过专用接口执行' };

  if (bestMatch.admin) {
    const user = db.prepare("SELECT role FROM users WHERE id = ?").get(userId);
    if (user?.role !== 'admin') return { matched: true, key: bestMatch.key, output: '🔒 需要管理员权限' };
  }

  // ── Interactive model menu ──────────────────────────────────────────────
  if (bestMatch.key === 'model:list') {
    return await buildModelListWithButtons();
  }

  const safeArgs = bestArgs.map(sanitizeArg).filter(Boolean);
  const cliArgs = [...bestMatch.cli, ...safeArgs];

  try {
    const { stdout, stderr } = await execFileAsync('openclaw', cliArgs, {
      timeout: 20000, maxBuffer: 512 * 1024, env: { ...process.env },
    });
    return { matched: true, key: bestMatch.key, output: (stdout || stderr || '（无输出）').trim() };
  } catch (err) {
    const out = (err.stdout || err.stderr || err.message || '执行失败').trim();
    return { matched: true, key: bestMatch.key, output: out };
  }
}

/**
 * Build /help with group buttons
 */
function buildHelpWithButtons() {
  const grouped = {};
  for (const c of COMMAND_DEFS) {
    if (!grouped[c.group]) grouped[c.group] = [];
    grouped[c.group].push(c);
  }
  const groups = Object.keys(grouped);
  const buttons = [];
  for (let i = 0; i < groups.length; i += 2) {
    const row = [];
    row.push({ text: `${groups[i]} (${grouped[groups[i]].length})`, callback_data: `help_group_${groups[i]}`, style: 'primary' });
    if (i + 1 < groups.length) {
      row.push({ text: `${groups[i+1]} (${grouped[groups[i+1]].length})`, callback_data: `help_group_${groups[i+1]}`, style: 'primary' });
    }
    buttons.push(row);
  }
  return { matched: true, key: 'help', output: '📋 选择一个分组查看命令：', buttons };
}

function buildHelpGroupDetail(group) {
  const cmds = COMMAND_DEFS.filter(c => c.group === group);
  if (cmds.length === 0) return { matched: true, key: 'help', output: '未找到该分组' };

  let output = `${group}\n\n`;
  for (const c of cmds) {
    output += `\`${c.cmd}\` — ${c.desc}${c.admin ? ' 🔒' : ''}\n`;
  }

  // Add command buttons for executable ones
  const buttons = cmds
    .filter(c => c.exec && !c.special && !c.argHint)
    .map(c => [{ text: c.cmd, callback_data: c.cmd, style: c.admin ? 'danger' : 'default' }]);
  buttons.push([{ text: '<< 返回帮助', callback_data: 'help_back', style: 'danger' }]);

  return { matched: true, key: 'help', output, buttons };
}

/**
 * Build interactive model list with provider-grouped inline buttons
 */
async function buildModelListWithButtons() {
  try {
    const { stdout } = await execFileAsync('openclaw', ['models', 'list'], {
      timeout: 15000, maxBuffer: 512 * 1024, env: { ...process.env },
    });

    // Parse models from output
    const lines = stdout.split('\n').slice(1).filter(l => l.trim());
    const providers = {};
    for (const line of lines) {
      const model = line.trim().split(/\s+/)[0];
      if (!model || model === 'Model') continue;
      const slash = model.indexOf('/');
      if (slash < 0) continue;
      const provider = model.slice(0, slash);
      if (!providers[provider]) providers[provider] = [];
      providers[provider].push(model);
    }

    const providerNames = Object.keys(providers);
    if (providerNames.length === 0) {
      return { matched: true, key: 'model:list', output: '没有可用模型' };
    }

    // Build provider buttons (2 per row)
    const buttons = [];
    for (let i = 0; i < providerNames.length; i += 2) {
      const row = [];
      row.push({ text: `${providerNames[i]} (${providers[providerNames[i]].length})`, callback_data: `mdl_provider_${providerNames[i]}`, style: 'primary' });
      if (i + 1 < providerNames.length) {
        row.push({ text: `${providerNames[i+1]} (${providers[providerNames[i+1]].length})`, callback_data: `mdl_provider_${providerNames[i+1]}`, style: 'primary' });
      }
      buttons.push(row);
    }

    return {
      matched: true,
      key: 'model:list',
      output: '🤖 选择一个 Provider 查看模型：',
      buttons,
    };
  } catch (err) {
    return { matched: true, key: 'model:list', output: `获取模型列表失败: ${err.message}` };
  }
}

export default router;
