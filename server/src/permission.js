import db from './db.js';

// Commands that require admin role
const ADMIN_COMMANDS = new Set([
  'model:scan', 'model:auth',
  'sessions:cleanup',
  'memory:index',
  'security:audit',
  'gateway:start', 'gateway:stop', 'gateway:restart',
  'daemon:start', 'daemon:stop', 'daemon:restart',
  'cron:run', 'cron:enable', 'cron:disable',
  'plugins:enable', 'plugins:disable',
  'nodes:pending', 'nodes:approve', 'nodes:reject',
  'devices:approve', 'devices:reject', 'devices:revoke',
  'pairing:approve',
]);

/**
 * Check if a user is admin
 * @param {string} userId
 * @returns {boolean}
 */
export function isAdmin(userId) {
  const user = db.prepare('SELECT role FROM users WHERE id = ?').get(userId);
  return user?.role === 'admin';
}

/**
 * Check if a user can execute a command
 * @param {string} userId
 * @param {string} commandKey - e.g. 'gateway:restart'
 * @returns {{ allowed: boolean, reason?: string }}
 */
export function checkCommandPermission(userId, commandKey) {
  if (!ADMIN_COMMANDS.has(commandKey)) {
    return { allowed: true };
  }

  if (isAdmin(userId)) {
    return { allowed: true };
  }

  return { allowed: false, reason: '🔒 需要管理员权限' };
}

/**
 * Get user role info
 * @param {string} userId
 * @returns {{ role: string, agentId: string | null }}
 */
export function getUserRole(userId) {
  const user = db.prepare('SELECT role, agent_id FROM users WHERE id = ?').get(userId);
  return {
    role: user?.role || 'user',
    agentId: user?.agent_id || null,
  };
}

export default { isAdmin, checkCommandPermission, getUserRole };
