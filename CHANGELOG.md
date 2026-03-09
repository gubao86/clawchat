# Changelog

## v2.1.0 (2026-03-09)

### ✨ 新功能

- **交互式命令系统**（Telegram 风格）
  - 输入 `/` 即弹出命令候选面板，支持模糊搜索过滤
  - 命令执行返回内联按钮 (Inline Buttons)，支持多级菜单导航
  - 4 种按钮样式：primary（蓝）、success（绿）、danger（红）、default（灰）
  - 点击按钮直接执行命令或导航到下一级

- **动态命令发现** (`command-discovery.js`)
  - 从 `openclaw help` 实时解析命令列表
  - 子命令延迟加载（点击分组时才获取）
  - 5 分钟顶级缓存 + 10 分钟子命令缓存
  - 新 skill 安装后自动出现，无需修改代码

- **交互式 /help 菜单**
  - 19 个命令分组按钮（每行 2 个）
  - 点击分组 → 展开子命令列表 + 可执行按钮
  - `<< 返回` 按钮回到分组列表

- **交互式 /model list 菜单**
  - Provider 分组按钮 → 模型列表 → 一键切换
  - 服务端拦截 `mdl_` 前缀回调

- **多用户 Agent 隔离** (`agent-manager.js`)
  - Admin 用户路由到 `agent:main`
  - 普通用户自动创建独立 `clawchat-<userId>` Agent
  - 每个 Agent 拥有独立 workspace、SOUL.md、MEMORY.md
  - 通用 Agent 模板 (`server/templates/SOUL.md`)

- **Web 前端内联按钮**
  - 浏览器端渲染可点击按钮网格
  - `sendCallback()` 通过 WS 发送回调
  - CSS 4 种按钮样式 + hover/loading 状态

### 🔧 改进

- **命令走 WebSocket**：所有 `/` 命令通过 WS 发送（不再走 HTTP exec），服务端返回带 buttons 的结构化响应
- **assistant 消息处理**：前端 WS handler 同时处理 `user` 和 `assistant` 角色消息
- **命令面板定位**：移到 `input-area` 内部，`position: absolute; bottom: 100%` 正确在输入框上方弹出
- **systemd PATH**：service 文件包含 `~/.npm-global/bin`，`openclaw` CLI 可用

### 🐛 修复

- 修复 `_parseButtons` JSON 字符串解析
- 修复 `stream_end` 中 buttons 的解析
- 修复 `InlineButtonGrid` loading 状态自动重置
- 修复命令面板在 Web 端不可见的定位问题

### 📦 数据库迁移

- `users` 表新增 `agent_id`、`model_override` 字段
- `messages` 表新增 `buttons`、`callback_data` 字段
- 自动迁移，无需手动操作

---

## v1.0.0 (2026-03-08)

### 初始版本

- 基础聊天功能（文字/图片/视频/音频/文件）
- WebSocket 实时通信 + 流式输出
- 多会话管理（创建/切换/重命名/删除）
- 语音消息录制与发送
- 静态命令系统（69 条命令，HTTP exec）
- 用户认证（JWT + 邀请码注册）
- 管理员面板（用户/邀请码/统计）
- GitHub Actions 自动构建 APK
- PWA Web 前端
