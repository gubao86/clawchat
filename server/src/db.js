import Database from 'better-sqlite3';
import config from './config.js';
import { mkdirSync } from 'fs';
import { dirname } from 'path';
import { randomUUID } from 'crypto';

mkdirSync(dirname(config.db), { recursive: true });
const db = new Database(config.db, { wal: true });

db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT DEFAULT 'user',
    status TEXT DEFAULT 'active',
    invited_by TEXT,
    created_at INTEGER DEFAULT (unixepoch())
  );

  CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('user','assistant','system')),
    content TEXT NOT NULL,
    content_type TEXT DEFAULT 'text',
    file_id TEXT,
    file_name TEXT,
    file_path TEXT,
    created_at INTEGER DEFAULT (unixepoch()),
    session_key TEXT DEFAULT 'main',
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  CREATE TABLE IF NOT EXISTS invite_codes (
    code TEXT PRIMARY KEY,
    created_by TEXT NOT NULL,
    used_by TEXT,
    used_at INTEGER,
    expires_at INTEGER,
    use_count INTEGER DEFAULT 0,
    max_uses INTEGER DEFAULT 1,
    created_at INTEGER DEFAULT (unixepoch()),
    FOREIGN KEY (created_by) REFERENCES users(id)
  );

  CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    session_key TEXT NOT NULL,
    title TEXT DEFAULT '新对话',
    created_at INTEGER DEFAULT (unixepoch()),
    updated_at INTEGER DEFAULT (unixepoch()),
    UNIQUE(user_id, session_key),
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_key, created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id, created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id, updated_at DESC);
`);

// 迁移：为已有安装添加新字段（SQLite ALTER TABLE 不支持 IF NOT EXISTS，用 try/catch）
const userMigrations = [
  "ALTER TABLE users ADD COLUMN role TEXT DEFAULT 'user'",
  "ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active'",
  "ALTER TABLE users ADD COLUMN invited_by TEXT",
];
const msgMigrations = [
  "ALTER TABLE messages ADD COLUMN file_id TEXT",
  "ALTER TABLE messages ADD COLUMN file_name TEXT",
];
[...userMigrations, ...msgMigrations].forEach(sql => { try { db.exec(sql); } catch {} });

// 迁移：首次升级时将第一个注册用户升为 admin
const adminExists = db.prepare("SELECT id FROM users WHERE role = 'admin' LIMIT 1").get();
if (!adminExists) {
  const firstUser = db.prepare("SELECT id FROM users ORDER BY created_at ASC LIMIT 1").get();
  if (firstUser) {
    db.prepare("UPDATE users SET role = 'admin' WHERE id = ?").run(firstUser.id);
  }
}

// 迁移：为已有用户创建 main session
const usersWithoutSession = db.prepare(`
  SELECT id FROM users
  WHERE id NOT IN (SELECT user_id FROM sessions WHERE session_key = 'main')
`).all();
for (const u of usersWithoutSession) {
  try {
    db.prepare(`
      INSERT INTO sessions (id, user_id, session_key, title) VALUES (?, ?, 'main', '主对话')
    `).run(randomUUID(), u.id);
  } catch {}
}

export default db;

// ── v2 迁移：users 表添加 agent_id，messages 表添加 buttons/callback_data ──
const v2Migrations = [
  "ALTER TABLE users ADD COLUMN agent_id TEXT",
  "ALTER TABLE users ADD COLUMN model_override TEXT",
  "ALTER TABLE messages ADD COLUMN buttons TEXT",
  "ALTER TABLE messages ADD COLUMN callback_data TEXT",
];
v2Migrations.forEach(sql => { try { db.exec(sql); } catch {} });

// 迁移：为已有用户设置 agent_id
const usersWithoutAgent = db.prepare("SELECT id, role FROM users WHERE agent_id IS NULL").all();
for (const u of usersWithoutAgent) {
  const agentId = u.role === 'admin' ? 'main' : `clawchat-${u.id}`;
  db.prepare("UPDATE users SET agent_id = ? WHERE id = ?").run(agentId, u.id);
}
