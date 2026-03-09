# 🦞 ClawChat

OpenClaw AI 的自托管即时通讯客户端 —— 数据完全在自己的服务器，手机端 + Web 端完整操控 OpenClaw。

---

## 目录

- [功能特性](#功能特性)
- [架构概览](#架构概览)
- [服务端部署](#服务端部署)
- [客户端安装](#客户端安装)
- [首次使用流程](#首次使用流程)
- [用户使用指南](#用户使用指南)
- [管理员指南](#管理员指南)
- [GitHub Actions 自动构建](#github-actions-自动构建)
- [API 参考](#api-参考)
- [常见问题](#常见问题)

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 🔒 自托管 | 所有数据保存在自有服务器，不经过第三方 |
| 💬 多会话 | 支持创建多个独立对话，左滑 Drawer 切换 |
| 🤖 交互式命令系统 | Telegram 风格的内联按钮菜单，输入 `/` 弹出命令候选 |
| 🎛️ 动态命令发现 | 命令列表从 OpenClaw CLI 动态获取，新 skill 自动出现 |
| 🔘 内联按钮 (Inline Buttons) | 多级菜单导航、按钮点击执行命令、支持 4 种样式 |
| 🔊 语音消息 | 按住麦克风按钮录音，左滑取消，松开发送 |
| 📷 图片/文件 | 相机拍照、相册选图、文件选择，直接发送 |
| 👥 多用户隔离 | 每个用户独立 OpenClaw Agent，会话/记忆完全隔离 |
| 🔐 权限分级 | Admin 可执行所有命令，普通用户敏感命令灰显+拦截 |
| 😀 表情选择器 | 7 分类表情面板，点击插入 |
| 🌐 Web + 移动端 | 浏览器直接访问 + Android APK 双端支持 |
| 📱 管理面板 | 管理员可在手机端/Web 端管理用户、邀请码、查看统计 |
| 🔄 Token 自动续期 | 活跃状态下每 20 分钟自动刷新 Token |

---

## 架构概览

```
┌─────────────────────────────────────┐
│       Android 客户端 / Web 前端      │
│    (Flutter APK / 浏览器 PWA)       │
└──────────┬──────────────────────────┘
           │ WebSocket (实时双向)
           ▼
┌─────────────────────────────────────┐
│         ClawChat Server             │
│    (Node.js · Express · SQLite)     │
│    监听 :3900                        │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ command-discovery.js        │    │
│  │ 动态解析 openclaw help       │    │
│  │ 延迟加载子命令 (缓存5min)     │    │
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ agent-manager.js            │    │
│  │ 用户→Agent 映射与生命周期     │    │
│  └─────────────────────────────┘    │
└──────────┬──────────────────────────┘
           │ HTTP + CLI
           ▼
┌─────────────────────────────────────┐
│         OpenClaw Gateway            │
│         监听 :18789                  │
│  ├── agent: main        (admin)     │
│  ├── agent: clawchat-xx (用户)      │
│  └── ...                            │
└─────────────────────────────────────┘
```

**数据存储：** `~/clawchat/server/data/clawchat.db`（SQLite）

---

## 服务端部署

### 环境要求

- Node.js ≥ 18
- OpenClaw 已安装并配置完毕（`openclaw` 命令可用）
- OpenClaw Gateway 处于运行状态

### 安装步骤

```bash
# 1. 进入服务端目录
cd ~/clawchat/server

# 2. 安装依赖
npm install

# 3. （可选）创建环境变量文件
cat > .env <<'EOF'
PORT=3900
HOST=0.0.0.0
JWT_SECRET=your-strong-secret-here
EOF

# 4. 启动服务
node src/index.js
```

### 配置说明

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `PORT` | `3900` | 监听端口 |
| `HOST` | `0.0.0.0` | 监听地址 |
| `JWT_SECRET` | 从 openclaw.json 读取 | JWT 签名密钥，生产环境务必设置 |

### 使用 systemd 持久运行（推荐）

```bash
# 创建用户级 systemd 服务
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/clawchat.service <<'EOF'
[Unit]
Description=ClawChat Server
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/clawchat/server
ExecStart=/usr/bin/node src/index.js
Restart=on-failure
RestartSec=5
Environment=PATH=%h/.npm-global/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now clawchat
```

> **注意**：`Environment=PATH=...` 必须包含 `openclaw` 所在目录（如 `~/.npm-global/bin`），否则命令执行会报 ENOENT。

### 反向代理（可选，Nginx 示例）

```nginx
server {
    listen 80;
    server_name your.domain.com;

    location / {
        proxy_pass http://127.0.0.1:3900;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 客户端安装

### Web 端（即开即用）

浏览器访问 `http://your-server:3900/` 即可使用，无需安装。

支持 PWA 安装到桌面（Chrome → 菜单 → "安装应用"）。

### Android 客户端

#### 方式一：GitHub Actions 自动构建（推荐）

每次向 `main` 分支推送代码，GitHub Actions 自动构建 APK 并发布到 Releases。

1. 进入仓库 → **Releases** 页面
2. 下载最新的 `app-release.apk`
3. 在 Android 设备上安装（需开启"允许未知来源"）

#### 方式二：本地构建

```bash
cd ~/clawchat/client
flutter pub get
flutter build apk --release
# APK 位于：build/app/outputs/flutter-apk/app-release.apk
```

---

## 首次使用流程

### 1. 配置服务器地址

打开 ClawChat App，顶部输入框填写服务器地址：

```
格式：IP:端口  或  域名:端口
示例：192.168.1.100:3900
      chat.example.com:3900
```

Web 端直接访问即可，无需配置。

### 2. 注册首位管理员账号

- **首位用户**：无需邀请码，自动成为管理员
- 后续用户需管理员生成的邀请码
- 用户名：2-32 位，密码：6-128 位

### 3. 开始对话

连接成功（状态显示「已连接」）后即可开始与 AI 对话。

---

## 用户使用指南

### 交互式命令系统 ⭐

ClawChat v2 的核心特性——复刻 Telegram 风格的交互式命令菜单。

#### 命令候选面板

在输入框输入 `/` 即可触发命令候选面板（**不需要按回车**）：

- 在输入框上方弹出所有可用命令，按组分类
- 支持模糊搜索过滤（输入 `/mod` 只显示 model 相关）
- 管理员命令标记 🔒，普通用户灰显不可点击
- 终端命令标记「终端」，需 SSH 执行

#### 内联按钮 (Inline Buttons)

命令执行后，响应消息可包含可点击的按钮网格：

```
用户输入: /help

┌──────────────────────────────────┐
│ 📋 可用命令（* 有子命令）：        │
│                                  │
│ [🤖 models *] [📡 channels *]   │
│ [⏰ cron *]   [🛠️ skills *]     │
│ [📊 status]   [🌐 gateway *]    │
│ ...                              │
└──────────────────────────────────┘

点击 "⏰ cron *":
┌──────────────────────────────────┐
│ ⏰ cron — Manage cron jobs       │
│                                  │
│ [add — Add a cron job]           │
│ [list — List cron jobs]          │
│ [status — Show scheduler...]     │
│ [<< 返回]                        │
└──────────────────────────────────┘

点击 "list" → 直接执行 `openclaw cron list`
点击 "<< 返回" → 回到命令分组
```

#### 模型切换菜单

```
用户输入: /model list

┌──────────────────────────────────┐
│ 🤖 选择一个 Provider 查看模型：    │
│                                  │
│ [yunyiai (4)]   [deepseek (2)]   │
│ [moonshot (2)]  [siliconflow (3)]│
│ [openrouter (5)]                 │
└──────────────────────────────────┘

点击 "moonshot (2)":
┌──────────────────────────────────┐
│ 🤖 moonshot 的模型：              │
│                                  │
│ [kimi-k2-thinking]               │
│ [kimi-k2.5]                      │
│ [<< 返回]                        │
└──────────────────────────────────┘

点击模型 → ✅ 模型已切换
```

#### 按钮样式

| 样式 | 颜色 | 用途 |
|------|------|------|
| `primary` | 蓝色 | 分组/导航按钮 |
| `success` | 绿色 | 执行/确认按钮 |
| `danger` | 红色 | 返回/管理员按钮 |
| `default` | 灰色 | 普通选项 |

#### 动态命令发现

命令列表从 OpenClaw CLI **动态获取**，不是硬编码：

- 顶级命令从 `openclaw help` 解析（缓存 5 分钟）
- 子命令在点击分组时延迟加载（缓存 10 分钟）
- 安装新 skill 后，相关命令自动出现在 `/help` 菜单中
- 无需修改 ClawChat 代码

### 多会话管理

点击 AppBar 左侧 **☰** 打开会话 Drawer：

| 操作 | 方式 |
|------|------|
| 新建对话 | 点击「+ 新建对话」 |
| 切换会话 | 点击会话列表项 |
| 重命名 | 长按会话项 → 重命名 |
| 删除会话 | 长按会话项 → 删除（主对话不可删除） |

### 发送消息

**输入栏布局：**

```
[☰ Menu] [😀 表情] [输入框...] [📎 文件] [➤ 发送]
```

| 按钮 | 功能 |
|------|------|
| ☰ Menu | 打开全屏命令面板，支持搜索，点击即执行 |
| 😀 表情 | 弹出表情选择器（7 个分类），点击插入到光标位置 |
| 📎 文件 | 选择附件（📷 相机 / 🖼️ 相册 / 📁 文件） |
| ➤ 发送 | 发送消息（或按 Enter） |

**语音消息**（🎤 按钮，仅 App）：输入框为空时出现，按住录音，松开发送，左滑取消。

### 消息操作（长按气泡）

| 选项 | 说明 |
|------|------|
| 📋 复制全文 | 复制到剪贴板 |
| ✏️ 编辑重新发送 | 填入输入框（仅自己的消息） |
| 🔁 重新生成 | AI 重新回答（仅 AI 消息） |
| 🗑️ 删除 | 本地移除 |

---

## 管理员指南

### 管理面板

设置 → 管理面板（仅 admin 可见），或 Web 端点击 ⚙️ 按钮。

### 用户管理

| 操作 | 说明 |
|------|------|
| 封禁 / 解封 | 被封禁用户无法登录和发消息 |
| 升为管理员 | 赋予管理员权限 |
| 重置密码 | 随机生成或手动指定新密码 |
| 删除用户 | 同时删除该用户的所有消息和会话 |

### 邀请码管理

- 设置使用次数（1-100）和有效天数（1-365）
- 点击 📋 复制邀请码
- 过期或耗尽自动标灰

### 多用户 Agent 隔离

| 用户类型 | Agent | 说明 |
|----------|-------|------|
| Admin（aluo） | `main` | 复用现有私人 agent，拥有完整 workspace |
| 普通注册用户 | `clawchat-<userId>` | 每人独立 agent，自动创建 |

每个 agent 独立拥有：workspace 目录、SOUL.md、MEMORY.md、会话历史、模型选择。

### 权限矩阵

| 功能 | Admin | 普通用户 |
|------|-------|---------|
| 聊天对话 | ✅ | ✅ |
| 选择模型 | ✅ | ✅ |
| 添加/删除模型 | ✅ | ❌ |
| 查看系统状态 | ✅ | ✅ |
| Gateway/Daemon 管理 | ✅ | ❌ |
| 安全审计 | ✅ | ❌ |
| 用户管理 | ✅ | ❌ |

---

## GitHub Actions 自动构建

文件：`.github/workflows/build-apk.yml`

触发条件：推送到 `main` 分支 或 手动触发。

### APK 签名（可选）

在 GitHub → Settings → Secrets 中添加：

| Secret | 说明 |
|--------|------|
| `KEYSTORE_BASE64` | Keystore 文件的 Base64 |
| `KEY_ALIAS` | Key 别名 |
| `KEY_PASSWORD` | Key 密码 |
| `STORE_PASSWORD` | Keystore 密码 |

不配置 Secrets 时构建无签名 Debug APK。

---

## API 参考

### 认证

```
Authorization: Bearer <token>
```

### REST 端点

#### 认证

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/ping` | 连通性检测 |
| `POST` | `/auth/login` | 登录 |
| `POST` | `/auth/register` | 注册（需邀请码） |
| `POST` | `/auth/refresh` | Token 续期 |
| `POST` | `/auth/change-password` | 修改密码 |
| `GET` | `/auth/check-first` | 是否首位用户 |

#### 会话

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/sessions` | 列出会话 |
| `POST` | `/sessions` | 创建会话 |
| `PATCH` | `/sessions/:key` | 重命名 |
| `DELETE` | `/sessions/:key` | 删除（main 不可删） |

#### 消息

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/messages/history` | 历史消息 `?session=<key>&limit=50` |

#### 文件

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/files/upload` | 上传（multipart） |
| `GET` | `/files/:id` | 下载 |

#### 命令

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/commands/list` | 命令定义列表（静态+动态） |
| `POST` | `/commands/exec` | 执行命令 `{ key, args }` |
| `DELETE` | `/commands/clear` | 清空消息 `?session=<key>` |

### WebSocket

连接：`ws://host:port/ws`

#### 客户端→服务端

```json
// 认证
{ "type": "auth", "token": "<jwt>" }

// 发送消息（普通文本或 / 命令）
{ "type": "message", "content": "...", "sessionKey": "main" }

// 按钮回调
{ "type": "callback", "callbackData": "cmd_group_cron", "sessionKey": "main" }
```

#### 服务端→客户端

```json
// 认证成功
{ "type": "auth_ok", "user": { "id": "...", "username": "..." } }

// 完整消息（命令结果 / 按钮响应）
{
  "type": "message",
  "id": "uuid",
  "role": "assistant",
  "content": "📋 可用命令...",
  "buttons": [[{"text": "...", "callback_data": "...", "style": "primary"}]],
  "sessionKey": "main",
  "ts": 1234567890
}

// AI 流式输出
{ "type": "stream_start", "id": "uuid", "sessionKey": "main" }
{ "type": "stream_chunk", "content": "...", "sessionKey": "main" }
{ "type": "stream_end", "id": "uuid", "buttons": [...], "sessionKey": "main" }

// 错误
{ "type": "error", "message": "..." }
```

#### 按钮回调数据格式

| 前缀 | 用途 | 示例 |
|------|------|------|
| `cmd_group_` | 展开命令分组 | `cmd_group_cron` |
| `cmd_exec_` | 执行命令 | `cmd_exec_cron list` |
| `cmd_help_back` | 返回帮助首页 | — |
| `mdl_provider_` | 展开模型 Provider | `mdl_provider_moonshot` |
| `mdl_sel_` | 切换模型 | `mdl_sel_moonshot/kimi-k2.5` |
| `mdl_back` | 返回 Provider 列表 | — |

---

## 常见问题

**Q: 输入 `/` 没有弹出命令面板？**

A: 确认命令列表已加载。检查浏览器 Console 是否有 `/commands/list` 请求失败。服务端需确保 `openclaw` 在 PATH 中。

**Q: 按钮点击后无反应？**

A: 检查 WebSocket 连接状态。按钮通过 WS 发送 callback，需保持连接活跃。

**Q: 状态灯一直是红色？**

A: 检查：
1. 服务端是否运行：`systemctl --user status clawchat`
2. 端口是否放行：防火墙 3900 端口
3. 地址格式：填 `IP:端口` 不含 `http://`

**Q: AI 回复失败？**

A: OpenClaw Gateway 未运行：
```bash
openclaw gateway status
openclaw gateway start
```

**Q: 命令执行报 ENOENT？**

A: systemd 环境没有 `openclaw` 路径。编辑 service 文件添加：
```ini
Environment=PATH=%h/.npm-global/bin:/usr/local/bin:/usr/bin:/bin
```

**Q: 新安装的 skill 命令没出现？**

A: 动态命令有 5 分钟缓存。等待缓存过期或重启 ClawChat 服务。

---

## 项目结构

```
clawchat/
├── .github/workflows/
│   └── build-apk.yml              # APK 自动构建
├── docs/
│   └── REQUIREMENTS-v2.md         # v2 需求文档
├── server/                         # Node.js 服务端
│   ├── src/
│   │   ├── index.js               # 入口
│   │   ├── db.js                  # SQLite + v2 迁移
│   │   ├── auth.js                # JWT
│   │   ├── config.js              # 配置
│   │   ├── gateway.js             # OpenClaw Gateway HTTP 调用
│   │   ├── ws-handler.js          # WebSocket：消息路由 + 命令拦截 + 按钮回调
│   │   ├── command-discovery.js   # 🆕 动态命令发现（解析 openclaw help）
│   │   ├── agent-manager.js       # 🆕 Agent 生命周期管理
│   │   └── routes/
│   │       ├── auth.js            # 认证（含 agent 创建）
│   │       ├── sessions.js        # 会话
│   │       ├── messages.js        # 消息
│   │       ├── files.js           # 文件
│   │       ├── commands.js        # 命令（静态定义 + 动态发现 + 模型菜单）
│   │       └── admin.js           # 管理员
│   ├── templates/
│   │   └── SOUL.md                # 🆕 新用户 Agent 模板
│   ├── public/                    # 🆕 Web 前端
│   │   ├── index.html             # 主页面
│   │   ├── app.js                 # JS（含 buttons 渲染）
│   │   ├── style.css              # 样式（含 inline-btn 样式）
│   │   └── admin.html             # 管理面板
│   └── data/                      # 运行时数据（gitignore）
│       ├── clawchat.db
│       └── uploads/
├── client/                         # Flutter 客户端
│   └── lib/
│       ├── main.dart
│       ├── config.dart
│       ├── models/
│       │   └── message.dart       # 消息模型（含 buttons 字段）
│       ├── services/
│       │   ├── auth_service.dart
│       │   ├── session_service.dart
│       │   ├── command_service.dart
│       │   └── ws_service.dart    # WS（含 sendCallback）
│       ├── providers/
│       │   └── chat_provider.dart # 状态管理（含 buttons 处理）
│       ├── widgets/
│       │   └── inline_buttons.dart # 🆕 InlineButtonGrid 组件
│       └── screens/
│           ├── login_screen.dart
│           ├── chat_screen.dart   # 聊天（命令走 WS）
│           ├── settings_screen.dart
│           └── admin_screen.dart
└── README.md                      # 本文档
```

---

## 更新日志

### v2.1 (2026-03-09)

- ✨ **交互式命令系统**：内联按钮、多级菜单、`/help` 分组导航
- ✨ **动态命令发现**：从 OpenClaw CLI 实时解析，新 skill 自动出现
- ✨ **模型切换菜单**：Provider 分组 → 模型列表 → 一键切换
- ✨ **Web 前端 buttons**：浏览器端支持内联按钮渲染和回调
- ✨ **多用户 Agent 隔离**：每用户独立 Agent + workspace
- 🔧 **命令走 WS**：所有命令通过 WebSocket 发送，获取结构化 buttons 响应
- 🔧 **systemd PATH 修复**：`openclaw` CLI 在服务环境中正常工作
- 🐛 **assistant 消息处理**：前端正确处理 WS 返回的 assistant 消息

### v1.0

- 基础聊天功能（文字/文件/语音）
- 多会话管理
- 静态命令系统（HTTP exec）
- 管理员面板
- GitHub Actions APK 自动构建

---

## License

MIT
