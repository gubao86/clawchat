import { execFile } from 'child_process';
import { promisify } from 'util';
import { copyFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import logger from './utils/logger.js';

const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const TEMPLATE_DIR = join(__dirname, '..', 'templates');
const AGENTS_BASE = join(dirname(__dirname), 'agents');

/**
 * Get agent ID for a user
 * @param {string} userId
 * @param {string} role - 'admin' or 'user'
 * @returns {string} agent ID
 */
export function getAgentId(userId, role) {
  return role === 'admin' ? 'main' : `clawchat-${userId}`;
}

/**
 * Create a new OpenClaw agent for a user
 * @param {string} agentId
 * @returns {Promise<{ok: boolean, error?: string}>}
 */
export async function createAgent(agentId) {
  if (agentId === 'main') {
    // Admin uses existing main agent, no creation needed
    return { ok: true };
  }

  const workspacePath = join(AGENTS_BASE, agentId);

  try {
    // Create agent workspace directory
    mkdirSync(workspacePath, { recursive: true });

    // Copy SOUL.md template
    const templateSoul = join(TEMPLATE_DIR, 'SOUL.md');
    const destSoul = join(workspacePath, 'SOUL.md');
    if (existsSync(templateSoul) && !existsSync(destSoul)) {
      copyFileSync(templateSoul, destSoul);
    }

    // Register agent with OpenClaw
    const { stdout, stderr } = await execFileAsync('openclaw', [
      'agents', 'add', agentId,
      '--workspace', workspacePath,
      '--non-interactive',
    ], { timeout: 15000 });

    logger.info(`Agent created: ${agentId}`, stdout || stderr);
    return { ok: true };
  } catch (err) {
    // Agent might already exist
    if (err.message?.includes('already exists') || err.stderr?.includes('already exists')) {
      logger.info(`Agent already exists: ${agentId}`);
      return { ok: true };
    }
    logger.error(`Failed to create agent ${agentId}:`, err.message);
    return { ok: false, error: err.message };
  }
}

/**
 * Delete an OpenClaw agent
 * @param {string} agentId
 * @returns {Promise<{ok: boolean, error?: string}>}
 */
export async function deleteAgent(agentId) {
  if (agentId === 'main') {
    return { ok: false, error: 'Cannot delete main agent' };
  }

  try {
    await execFileAsync('openclaw', ['agents', 'remove', agentId], { timeout: 15000 });
    logger.info(`Agent deleted: ${agentId}`);
    return { ok: true };
  } catch (err) {
    logger.error(`Failed to delete agent ${agentId}:`, err.message);
    return { ok: false, error: err.message };
  }
}

/**
 * List all agents
 * @returns {Promise<string>}
 */
export async function listAgents() {
  try {
    const { stdout } = await execFileAsync('openclaw', ['agents', 'list'], { timeout: 10000 });
    return stdout.trim();
  } catch (err) {
    logger.error('Failed to list agents:', err.message);
    return '';
  }
}

export default { getAgentId, createAgent, deleteAgent, listAgents };
