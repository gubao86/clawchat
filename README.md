# 🦞 ClawChat

OpenClaw AI 的自托管即时通讯客户端 —— 数据完全在自己的服务器，手机端完整操控 OpenClaw。

---

## 目录

- [功能特性](#功能特性)
- [架构概览](#架构概览)
- [服务端部署](#服务端部署)
- [Android 客户端安装](#android-客户端安装)
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
| 🤖 OpenClaw 命令 | 手机端完整执行 `/model`、`/gateway`、`/memory` 等命令 |
| 🔊 语音消息 | 按住麦克风按钮录音，左滑取消，松开发送 |
| 📷 图片/文件 | 相机拍照、相册选图、文件选择，直接发送 |
| 👥 多用户 | 邀请码注册体系，首位用户自动成为管理员 |
| 🔄 Token 自动续期 | 活跃状态下每 20 分钟自动刷新 Token，无需重新登录 |
| 📱 管理面板 | 管理员可在手机端管理用户、邀请码、查看统计 |

---

## 架构概览

```
┌─────────────────────────────────────┐
│           Android 客户端             │
│    (Flutter · ClawChat APK)         │
└──────────┬──────────────────────────┘
           │ HTTP REST + WebSocket
           ▼
┌─────────────────────────────────────┐
│         ClawChat Server             │
│    (Node.js · Express · SQLite)     │
│    监听 :3900                        │
└──────────┬──────────────────────────┘
           │ HTTP
           ▼
┌─────────────────────────────────────┐
│         OpenClaw Gateway            │
│         监听 :18789                  │
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

### 使用 PM2 持久运行

```bash
npm install -g pm2
cd ~/clawchat/server
pm2 start src/index.js --name clawchat
pm2 save
pm2 startup   # 开机自启
```

### 反向代理（可选，Nginx 示例）

```nginx
server {
    listen 80;
    server_name your.domain.com;

    location / {
        proxy_pass http://127.0.0.1:3900;
        proxy_http_version 1.1;
        # WebSocket 支持
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Android 客户端安装

### 方式一：GitHub Actions 自动构建（推荐）

每次向 `main` 分支推送代码，GitHub Actions 自动构建 APK 并发布到 Releases。

1. 进入仓库 → **Releases** 页面
2. 下载最新的 `app-release.apk`
3. 在 Android 设备上安装（需开启"允许未知来源"）

### 方式二：本地构建

```bash
# 环境要求：Flutter 3.24+、Java 17+、Android SDK

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
      chat.example.com      （默认80端口）
```

输入后等待约 1.5 秒自动检测连通性：
- 🟢 绿色 = 服务器可达
- 🔴 红色 = 无法连接
- ⚫ 灰色 = 未配置

### 2. 注册首位管理员账号

切换到「注册」Tab：

- **首位用户**：无需邀请码，自动成为管理员
- 用户名：2-32 位
- 密码：6-128 位

注册成功后直接进入聊天界面。

### 3. 开始对话

连接成功（AppBar 显示「已连接」）后即可开始与 AI 对话。

---

## 用户使用指南

### 多会话管理

点击 AppBar 左侧 **☰** 打开会话 Drawer：

| 操作 | 方式 |
|------|------|
| 新建对话 | 点击「+ 新建对话」 |
| 切换会话 | 点击会话列表项 |
| 重命名 | 长按会话项 → 重命名 |
| 删除会话 | 长按会话项 → 删除（主对话不可删除） |
| 点击会话名 | AppBar 标题可点击，快速重命名当前会话 |

> **自动命名**：新建会话发送第一条消息后，AI 回复的前 20 个字自动成为会话标题。

### 发送消息

**文字消息**

直接在输入框输入，按发送按钮或回车发送。

**附件（⊕ 按钮）**

| 类型 | 操作 |
|------|------|
| 📷 相机 | 实时拍照 |
| 🖼️ 相册 | 从相册选图 |
| 📁 文件 | 选择任意文件（PDF/文档/音视频等） |

**语音消息（🎤 按钮）**

- 输入框为空且无附件时，发送按钮变为麦克风 🎤
- **按住** 麦克风开始录音，显示录音时长
- **松开** 发送语音消息
- **向左滑动超过 80px** 取消录音

### 命令系统

**方式一：输入 `/` 触发命令面板**

在输入框输入 `/` 开头的文字，自动弹出命令筛选列表，点击执行。

**方式二：⌨ 命令菜单按钮**

点击输入栏右侧 ⌨ 按钮，打开完整命令面板，支持搜索：

| 命令组 | 常用命令 |
|--------|---------|
| 🤖 模型管理 | `/model list`、`/model set <模型ID>`、`/model status` |
| 💬 会话 | `/clear`（清空当前会话）、`/help` |
| 🧠 记忆 | `/memory status`、`/memory search <关键词>` |
| 🌐 网关 | `/gateway status`、`/gateway usage` |
| 📊 系统 | `/status`、`/logs`、`/health` |

### 消息操作（长按气泡）

长按任意消息气泡弹出操作菜单：

| 选项 | 说明 |
|------|------|
| 📋 复制全文 | 复制消息全部文本到剪贴板 |
| ✏️ 编辑重新发送 | 将消息内容填入输入框（仅自己的消息） |
| 🔁 重新生成 | 触发 AI 重新回答（仅 AI 消息） |
| 🗑️ 删除 | 从本地移除（不影响服务端记录） |

### 设置页面

**聊天界面** → AppBar 右侧 ⚙️ → 设置

- **修改密码**：填写旧密码和新密码（至少6位）
- **管理面板**：仅管理员可见

---

## 管理员指南

### 进入管理面板

设置 → 管理面板（仅 admin 账号可见）

### 用户管理

| 操作 | 说明 |
|------|------|
| 封禁 / 解封 | 被封禁用户无法登录和发消息 |
| 升为管理员 | 赋予管理员权限 |
| 重置密码 | 随机生成或手动指定新密码，成功后显示新密码 |
| 删除用户 | 同时删除该用户的所有消息和会话 |

### 邀请码管理

**生成邀请码**：

1. 点击「生成邀请码」
2. 设置使用次数（1-100）和有效天数（1-365）
3. 确认后邀请码显示在列表，点击 📋 复制

**邀请码列表**展示：
- 使用次数（已用/上限）
- 到期时间
- 过期或耗尽自动标灰

### 统计信息

| 指标 | 说明 |
|------|------|
| 总用户数 | 所有注册用户 |
| 活跃用户 | 未被封禁的用户数 |
| 封禁用户 | 已封禁账号数量 |
| 消息总数 | 全平台消息数 |
| 有效邀请码 | 未过期且未耗尽的邀请码数 |

### 新用户注册流程

1. 管理员在管理面板生成邀请码，复制发给新用户
2. 新用户打开 App → 注册 Tab → 填写邀请码
3. 注册成功，邀请码使用次数 +1

---

## GitHub Actions 自动构建

### 工作流配置

文件路径：`.github/workflows/build-apk.yml`

触发条件：
- 推送到 `main` 分支（自动构建 + 发布 Release）
- 手动触发（`workflow_dispatch`）

### APK 签名（可选）

在 GitHub 仓库 **Settings → Secrets and variables → Actions** 中添加：

| Secret 名称 | 说明 |
|------------|------|
| `KEYSTORE_BASE64` | Keystore 文件的 Base64 编码 |
| `KEY_ALIAS` | 签名 Key 别名 |
| `KEY_PASSWORD` | Key 密码 |
| `STORE_PASSWORD` | Keystore 密码 |

**生成签名 Keystore：**

```bash
keytool -genkey -v -keystore release.keystore \
  -alias clawchat -keyalg RSA -keysize 2048 -validity 10000

# 转为 Base64
base64 -w 0 release.keystore
```

不配置 Secrets 时，构建无签名 Debug APK（仅限测试）。

---

## API 参考

### 认证

所有需要认证的接口均需在 Header 中携带 Token：

```
Authorization: Bearer <token>
```

### 主要端点

#### 认证

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/ping` | 连通性检测（无需认证） |
| `POST` | `/auth/login` | 登录，返回 Token |
| `POST` | `/auth/register` | 注册 |
| `POST` | `/auth/refresh` | Token 续期（需认证） |
| `POST` | `/auth/change-password` | 修改密码（需认证） |
| `GET` | `/auth/check-first` | 判断是否首位用户 |

#### 会话

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/sessions` | 列出所有会话 |
| `POST` | `/sessions` | 创建新会话 |
| `PATCH` | `/sessions/:key` | 重命名会话 |
| `DELETE` | `/sessions/:key` | 删除会话（main 不可删） |

#### 消息

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/messages/history` | 获取消息历史，支持 `?session=<key>&limit=50` |

#### 文件

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/files/upload` | 上传文件（multipart/form-data） |
| `GET` | `/files/:id` | 下载文件（需认证） |

#### 命令

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/commands/list` | 获取命令列表 |
| `POST` | `/commands/exec` | 执行命令 `{ key, args }` |
| `DELETE` | `/commands/clear` | 清空会话消息，支持 `?session=<key>` |

#### WebSocket

连接地址：`ws://host:port/ws`

握手消息：
```json
{ "type": "auth", "token": "<jwt>" }
```

发送消息：
```json
{
  "type": "message",
  "content": "消息内容",
  "sessionKey": "会话key（默认 main）",
  "fileId": "文件ID（可选）",
  "fileName": "文件名（可选）",
  "fileType": "image|video|audio|document（可选）"
}
```

服务端推送事件类型：`auth_ok`、`message`、`stream_start`、`stream_chunk`、`stream_end`、`error`、`session_renamed`

---

## 常见问题

**Q: 状态灯一直是红色？**

A: 检查以下几项：
1. 服务端是否正在运行：`pm2 status` 或 `ps aux | grep node`
2. 端口是否放行：防火墙 / 安全组是否开放 3900 端口
3. 地址格式是否正确：填写 `IP:端口` 不含 `http://`

**Q: 登录后显示"连接中..."一直不变？**

A: WebSocket 连接失败。检查：
1. 服务端日志有无报错
2. 如果使用 Nginx 反代，确认已配置 WebSocket 支持（`Upgrade` 头）
3. HTTPS/WSS 场景下确认证书有效

**Q: AI 回复失败，提示"AI 回复失败，请重试"？**

A: OpenClaw Gateway 未运行或配置有误。
```bash
openclaw gateway status
openclaw gateway start
```

**Q: 命令执行失败？**

A: 确认 `openclaw` 命令在服务端用户的 PATH 中可用：
```bash
which openclaw
openclaw status
```

**Q: 如何迁移数据？**

A: 备份并恢复 SQLite 数据库文件和上传目录：
```bash
# 备份
cp ~/clawchat/server/data/clawchat.db backup.db
cp -r ~/clawchat/server/data/uploads backup-uploads/

# 恢复
cp backup.db ~/clawchat/server/data/clawchat.db
cp -r backup-uploads/ ~/clawchat/server/data/uploads/
```

**Q: Token 过期后需要重新登录？**

A: 正常使用时 App 每 20 分钟自动续期 Token。如果长时间（>24h）未使用则需重新登录。

---

## 项目结构

```
clawchat/
├── .github/
│   └── workflows/
│       └── build-apk.yml       # APK 自动构建
├── server/                      # Node.js 服务端
│   ├── src/
│   │   ├── index.js            # 入口，路由注册
│   │   ├── db.js               # SQLite 数据库 + 迁移
│   │   ├── auth.js             # JWT 工具
│   │   ├── config.js           # 配置读取
│   │   ├── gateway.js          # OpenClaw 网关调用
│   │   ├── ws-handler.js       # WebSocket 处理
│   │   └── routes/
│   │       ├── auth.js         # 认证路由
│   │       ├── sessions.js     # 会话路由
│   │       ├── messages.js     # 消息路由
│   │       ├── files.js        # 文件路由
│   │       ├── commands.js     # 命令路由
│   │       └── admin.js        # 管理员路由
│   └── data/                   # 运行时数据（gitignore）
│       ├── clawchat.db
│       └── uploads/
└── client/                      # Flutter 客户端
    ├── lib/
    │   ├── main.dart
    │   ├── config.dart
    │   ├── models/
    │   │   └── message.dart
    │   ├── services/
    │   │   ├── auth_service.dart
    │   │   ├── session_service.dart
    │   │   ├── command_service.dart
    │   │   └── ws_service.dart
    │   ├── providers/
    │   │   └── chat_provider.dart
    │   └── screens/
    │       ├── login_screen.dart
    │       ├── chat_screen.dart
    │       ├── settings_screen.dart
    │       └── admin_screen.dart
    └── android/
        └── app/src/main/
            └── AndroidManifest.xml
```

---

## License

MIT
