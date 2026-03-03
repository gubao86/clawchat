import 'dotenv/config';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const HOME = process.env.HOME || '/home/aluo';
const OPENCLAW_CONFIG = join(HOME, '.openclaw/openclaw.json');

let gatewayToken = '';
let gatewayPort = 18789;

if (existsSync(OPENCLAW_CONFIG)) {
  const raw = JSON.parse(readFileSync(OPENCLAW_CONFIG, 'utf8'));
  gatewayToken = raw?.gateway?.auth?.token || '';
  gatewayPort = raw?.gateway?.port || 18789;
}

export default {
  port: parseInt(process.env.PORT || '3900'),
  host: process.env.HOST || '0.0.0.0',
  jwtSecret: process.env.JWT_SECRET || gatewayToken || 'change-me-in-production',
  jwtExpiry: '24h',
  gateway: {
    url: `http://127.0.0.1:${gatewayPort}`,
    token: gatewayToken,
  },
  db: join(HOME, 'clawchat/server/data/clawchat.db'),
  uploads: join(HOME, 'clawchat/server/data/uploads'),
  maxFileSize: 50 * 1024 * 1024,
  rateLimit: { windowMs: 15 * 60 * 1000, max: 100 },
  authRateLimit: { windowMs: 15 * 60 * 1000, max: 10 },
};
