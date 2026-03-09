/**
 * Dynamic command discovery from OpenClaw CLI.
 * Top-level: parsed from `openclaw help` (cached 5 min)
 * Subcommands: lazy-loaded on demand per group (cached 10 min)
 */
import { execFile } from 'child_process';
import { promisify } from 'util';
import logger from './utils/logger.js';

const execFileAsync = promisify(execFile);
const EXEC_OPTS = { timeout: 20000, maxBuffer: 512 * 1024, env: { ...process.env, NO_COLOR: '1' } };

let topCache = null;
const TOP_TTL = 5 * 60 * 1000;
const subCache = new Map(); // groupName → { subs, ts }
const SUB_TTL = 10 * 60 * 1000;

const ADMIN_PATTERNS = [
  'gateway start', 'gateway stop', 'gateway restart',
  'daemon start', 'daemon stop', 'daemon restart',
  'uninstall', 'config set', 'config unset',
  'models scan', 'models auth', 'memory index',
];

const SKIP = new Set([
  'tui', 'dashboard', 'configure', 'onboard', 'completion', 'help', 'uninstall',
]);

const ICONS = {
  models: '🤖', gateway: '🌐', daemon: '🔧', channels: '📡',
  cron: '⏰', skills: '🛠️', plugins: '🔌', agents: '👥',
  nodes: '🌐', devices: '📱', memory: '🧠', status: '📊',
  health: '📊', logs: '📊', pairing: '🤝', directory: '🔍',
  browser: '🖥️', hooks: '🖥️', sandbox: '🖥️', approvals: '🔒',
  update: '📊', message: '💬', system: '⚙️', webhooks: '🔗',
  agent: '👤', acp: '🤖', dns: '🌐', docs: '📖', node: '🌐',
};

/**
 * Parse top-level commands only (no subcommand expansion)
 */
async function discoverTopLevel() {
  if (topCache && Date.now() - topCache.ts < TOP_TTL) return topCache.cmds;

  try {
    const { stdout, stderr } = await execFileAsync('openclaw', ['help', '--no-color'], EXEC_OPTS);
    const output = (stdout || '') + (stderr || '');
    const cmds = [];
    let inCommands = false;

    for (const line of output.split('\n')) {
      if (line.includes('Commands:')) { inCommands = true; continue; }
      if (line.includes('Examples:') || line.includes('Options:')) { inCommands = false; continue; }
      if (!inCommands) continue;

      const match = line.match(/^\s{2}(\S+)\s*(\*)?\s{2,}(.+)/);
      if (!match) continue;
      const [, name, hasSub, desc] = match;
      if (SKIP.has(name)) continue;

      cmds.push({
        name, desc: desc.trim(),
        hasSub: hasSub === '*',
        icon: ICONS[name] || '📎',
      });
    }
    topCache = { cmds, ts: Date.now() };
    return cmds;
  } catch (err) {
    logger.error('Command discovery failed:', err.message);
    return topCache?.cmds || [];
  }
}

/**
 * Lazy-load subcommands for a specific group
 */
async function getSubcommands(parent) {
  const cached = subCache.get(parent);
  if (cached && Date.now() - cached.ts < SUB_TTL) return cached.subs;

  try {
    const { stdout, stderr } = await execFileAsync('openclaw', [parent, '--help', '--no-color'], EXEC_OPTS);
    const output = (stdout || '') + (stderr || '');
    const subs = [];
    let inCommands = false;

    for (const line of output.split('\n')) {
      if (line.includes('Commands:')) { inCommands = true; continue; }
      if (inCommands && (line.includes('Options:') || line.includes('Examples:'))) { inCommands = false; continue; }
      if (!inCommands) continue;

      const match = line.match(/^\s{2}(\S+)\s*(\*)?\s{2,}(.+)/);
      if (!match) continue;
      const [, name, , desc] = match;
      const fullCmd = `${parent} ${name}`;
      subs.push({
        name, fullCmd, desc: desc.trim(),
        admin: ADMIN_PATTERNS.some(p => p === fullCmd),
      });
    }
    subCache.set(parent, { subs, ts: Date.now() });
    return subs;
  } catch (err) {
    logger.error(`Subcommand discovery for ${parent}:`, err.message);
    return cached?.subs || [];
  }
}

export async function execCommand(args) {
  try {
    const { stdout, stderr } = await execFileAsync('openclaw', [...args, '--no-color'], EXEC_OPTS);
    return { ok: true, output: (stdout || stderr || '（无输出）').trim() };
  } catch (err) {
    return { ok: false, output: (err.stdout || err.stderr || err.message || '执行失败').trim() };
  }
}

export async function buildHelpButtons() {
  const cmds = await discoverTopLevel();
  if (!cmds.length) return { output: '❌ 无法获取命令列表', buttons: null };

  const buttons = [];
  for (let i = 0; i < cmds.length; i += 2) {
    const row = [];
    const c1 = cmds[i];
    row.push({ text: `${c1.icon} ${c1.name}${c1.hasSub ? ' *' : ''}`, callback_data: `cmd_group_${c1.name}`, style: 'primary' });
    if (i + 1 < cmds.length) {
      const c2 = cmds[i + 1];
      row.push({ text: `${c2.icon} ${c2.name}${c2.hasSub ? ' *' : ''}`, callback_data: `cmd_group_${c2.name}`, style: 'primary' });
    }
    buttons.push(row);
  }
  return { output: '📋 可用命令（* 有子命令）：', buttons };
}

export async function buildGroupDetail(groupName) {
  const cmds = await discoverTopLevel();
  const cmd = cmds.find(c => c.name === groupName);
  if (!cmd) return { output: `❌ 未知命令: ${groupName}` };

  if (!cmd.hasSub) {
    return {
      output: `${cmd.icon} **${cmd.name}** — ${cmd.desc}`,
      buttons: [
        [{ text: `▶ 执行 /${cmd.name}`, callback_data: `cmd_exec_${cmd.name}`, style: 'success' }],
        [{ text: '<< 返回', callback_data: 'cmd_help_back', style: 'danger' }],
      ],
    };
  }

  const subs = await getSubcommands(groupName);
  let output = `${cmd.icon} **${cmd.name}** — ${cmd.desc}\n\n`;
  const buttons = [];
  for (const sub of subs) {
    output += `\`/${sub.fullCmd}\` — ${sub.desc}${sub.admin ? ' 🔒' : ''}\n`;
    buttons.push([{
      text: `${sub.admin ? '🔒 ' : ''}${sub.name} — ${sub.desc.slice(0, 25)}`,
      callback_data: `cmd_exec_${sub.fullCmd}`,
      style: sub.admin ? 'danger' : 'default',
    }]);
  }
  buttons.push([{ text: '<< 返回', callback_data: 'cmd_help_back', style: 'danger' }]);
  return { output, buttons };
}

export function invalidateCache() {
  topCache = null;
  subCache.clear();
}

export default { execCommand, buildHelpButtons, buildGroupDetail, invalidateCache };
