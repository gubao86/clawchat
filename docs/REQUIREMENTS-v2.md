# ClawChat v2 改进需求文档

> 创建: 2026-03-09 | 作者: aluo + Claude
> 状态: ✅ 核心功能已实施 (2026-03-09)

---

## 一、项目概述

ClawChat 是基于 OpenClaw Gateway 的移动端 AI 助手应用（Flutter + Node.js）。v2 版本的核心目标是：

1. **复刻 Telegram 风格的交互式命令系统**（内联按钮、多级菜单）
2. **多用户完全隔离**（每个用户一个独立 OpenClaw agent）
3. **通信架构升级**（从 HTTP API 改为 OpenClaw WebSocket 原生协议）
4. **权限分级管理**（admin vs 普通用户）

---

## 二、系统架构

### 2.1 现有架构（v1）

```
Flutter 客户端
    ↓ WebSocket
ClawChat 服务端（Node.js, port 3900）
    ↓ HTTP POST /v1/chat/completions
OpenClaw Gateway（port 18789）
    → agent: main（唯一）
```

**问题：**
- 所有用户共享同一个 agent，私人数据泄露风险
- 命令只能返回纯文本，无法实现交互式菜单
- 无法利用 OpenClaw 内置的 inline buttons 系统

### 2.2 目标架构（v2）

```
Flutter 客户端
    ↓ WebSocket（支持 inline buttons 消息）
ClawChat 服务端（Node.js, port 3900）
    ↓ OpenClaw Gateway WebSocket 协议（chat.send / chat.history）
OpenClaw Gateway（port 18789, inlineButtons 已启用）
    ├── agent: main           ← admin 用户专用（私人 agent）
    ├── agent: clawchat-alice ← 用户 alice 的独立 agent
    ├── agent: clawchat-bob   ← 用户 bob 的独立 agent
    └── agent: clawchat-xxx   ← 自动按需创建
```

---

## 三、功能需求

### 3.1 交互式命令系统（Telegram 风格）

#### 3.1.1 命令触发

| 需求 | 说明 |
|------|------|
| `/` 触发 | 在聊天输入框输入 `/` 时，输入框上方弹出所有可用命令的候选列表 |
| 命令候选 | 显示命令名 + 简短描述，支持模糊搜索过滤 |
| 点击候选 | 无参数命令直接执行；有参数命令填入输入框等待补充 |
| 动态加载 | 命令列表从 OpenClaw 动态获取，新 skill 的命令自动出现 |

#### 3.1.2 内联按钮（Inline Buttons）

| 需求 | 说明 |
|------|------|
| 按钮渲染 | AI 返回带 buttons 的消息时，在消息气泡下方渲染可点击的按钮网格 |
| 多列布局 | 支持 N 列按钮排列（通常2列） |
| 按钮点击 | 点击按钮发送 `callback_data` 到 OpenClaw，获取下一级响应 |
| 多级导航 | 支持无限层级菜单，如：`/models` → provider 列表 → model 列表 → 选中 |
| 选中标记 | 当前选中项在按钮文字前显示 ✓ |
| 返回按钮 | 每级菜单最后一行显示 `<< back` 返回上一级 |
| 加载状态 | 按钮点击后显示 loading 状态，防止重复点击 |

#### 3.1.3 命令示例流程（`/models`）

```
用户输入: /models

AI 回复:
┌──────────────────────────────┐
│ Select a provider            │
│                              │
│ [yunyiai (3)]  [moonshot (4)]│
│ [zai (3)]     [siliconflow(5)]│
│ [openrouter(5)]              │
└──────────────────────────────┘

用户点击 "yunyiai (3)":
┌──────────────────────────────┐
│ yunyiai models               │
│                              │
│ [✓ claude-sonnet-4-6]        │
│ [  claude-opus-4-6  ]        │
│ [  claude-haiku-4-5 ]        │
│                              │
│ [<< back]                    │
└──────────────────────────────┘

用户点击 "claude-opus-4-6":
AI 回复: ✅ 模型已切换为 claude-opus-4-6 (yunyiai)
```

#### 3.1.4 支持的命令范围

自动同步 OpenClaw 全部命令，包括但不限于：

| 类别 | 命令 |
|------|------|
| 模型管理 | `/models`, `/model list`, `/model set`, `/model status`, `/model aliases`, `/model fallbacks` |
| 会话管理 | `/clear`, `/new`, `/reset`, `/status`, `/compact` |
| 记忆管理 | `/memory status`, `/memory search` |
| 技能管理 | `/skills list`, `/skills info` |
| 系统状态 | `/status`, `/health`, `/logs` |
| 网关管理 | `/gateway status`, `/gateway health`, `/gateway usage` |
| 定时任务 | `/cron list`, `/cron status`, `/cron runs` |
| 通道管理 | `/channels list`, `/channels status` |
| 插件管理 | `/plugins list`, `/plugins info` |
| 帮助 | `/help` |
| 新增 skill 命令 | 自动发现，无需手动添加 |

---

### 3.2 多用户 Agent 隔离

#### 3.2.1 用户与 Agent 映射

| 用户类型 | Agent | 说明 |
|----------|-------|------|
| Admin（aluo） | `main` | 复用现有私人 agent，拥有 MEMORY.md、私人 workspace |
| 普通注册用户 | `clawchat-<userId>` | 每人一个独立 agent，自动创建 |

#### 3.2.2 Agent 生命周期

| 事件 | 动作 |
|------|------|
| 用户注册 | 调用 `openclaw agents add clawchat-<userId>` 创建独立 agent |
| 用户发消息 | 路由到对应 agent |
| 用户注销 | 调用 `openclaw agents delete clawchat-<userId>` 清理 |
| 用户被封禁 | 禁止消息路由，agent 保留（可恢复） |

#### 3.2.3 Agent 隔离内容

每个 agent 独立拥有：

| 内容 | 说明 |
|------|------|
| Workspace | 独立目录，包含该用户的文件 |
| SOUL.md | 从通用模板初始化 |
| MEMORY.md | 用户独立的长期记忆 |
| 会话历史 | 独立的 JSONL 转录文件 |
| 模型选择 | 可独立选择模型（从全局可用列表中） |

#### 3.2.4 通用 Agent 模板（SOUL.md）

新用户的 agent 自动使用通用模板初始化：

```markdown
# SOUL.md - AI 助手

你是一个友好、专业的 AI 助手，运行在 ClawChat 平台上。

## 核心原则
- 直接、清晰地回答问题
- 有自己的观点，不做没有立场的复读机
- 遇到不确定的问题诚实说明
- 保护用户隐私

## 风格
- 简洁为主，必要时详细展开
- 支持中英文对话
- 适当使用 emoji 增加亲和力

## 能力
- 日常对话、问答
- 代码编写、技术咨询
- 文本创作、翻译
- 数据分析、信息整理
```

#### 3.2.5 Agent 数量

- 暂不设上限
- 后续可通过 ClawChat 服务端配置 `maxUsers` 限制

---

### 3.3 权限管理

#### 3.3.1 权限矩阵

| 功能 | Admin | 普通用户 |
|------|-------|---------|
| 聊天对话 | ✅ | ✅ |
| 选择模型（`/models`） | ✅ | ✅（从已有列表选择） |
| 添加/删除模型 | ✅ | ❌ |
| 使用 skill 命令 | ✅ | ✅ |
| 添加/删除 skill | ✅ | ❌ |
| 查看系统状态 | ✅ | ✅（`/status`, `/health`） |
| Gateway 管理 | ✅ | ❌ |
| Daemon 管理 | ✅ | ❌ |
| 安全审计 | ✅ | ❌ |
| 会话清理 | ✅ | ❌（仅清理自己的对话） |
| 记忆索引重建 | ✅ | ❌ |
| 用户管理 | ✅ | ❌ |

#### 3.3.2 敏感命令清单（普通用户禁止）

| 命令 | 原因 |
|------|------|
| `/gateway start/stop/restart` | 系统管理 |
| `/daemon start/stop/restart` | 系统管理 |
| `/model scan` | 模型管理（修改配置） |
| `/model auth` | 模型认证管理 |
| `/security audit` | 安全审计 |
| `/sessions cleanup` | 全局会话清理 |
| `/memory index` | 记忆索引重建 |
| `/cron run/enable/disable` | 定时任务管理 |
| `/plugins enable/disable` | 插件管理 |
| `/nodes approve/reject` | 节点审批 |
| `/devices approve/reject/revoke` | 设备管理 |
| 所有 `admin: true` 标记的命令 | 后续新增的管理命令自动禁止 |

#### 3.3.3 禁止命令的 UI 表现

| 位置 | 表现 |
|------|------|
| 命令候选列表 | 命令文字显示为**灰色**，带 🔒 图标 |
| 命令面板 | 灰色 + 透明度降低（opacity: 0.45） |
| 点击禁止命令 | 不执行，聊天区显示系统消息：`🔒 禁止使用该命令` |
| 输入框直接输入 | 同上，返回 `🔒 禁止使用该命令` |

---

### 3.4 通信架构改造

#### 3.4.1 协议迁移

| 项目 | v1（现状） | v2（目标） |
|------|-----------|-----------|
| 接口 | HTTP POST `/v1/chat/completions` | OpenClaw Gateway WebSocket |
| 消息发送 | 构造 OpenAI 格式请求体 | `chat.send` RPC |
| 历史获取 | ClawChat 自有 SQLite | `chat.history` RPC + 本地缓存 |
| 流式输出 | 自己解析 SSE `data:` 行 | Gateway WS 原生推送 |
| 命令处理 | ClawChat 调 `openclaw` CLI | OpenClaw 内部处理，返回结构化响应 |
| 按钮交互 | ❌ 不支持 | callback_data 回调 |
| Agent 路由 | `model: "openclaw:main"` 固定 | 按用户路由到对应 agent |

#### 3.4.2 Gateway WebSocket 协议要点

| 方法 | 用途 |
|------|------|
| `chat.send` | 发送用户消息到指定 agent |
| `chat.history` | 获取会话历史（含按钮消息） |
| `chat.inject` | 注入系统消息 |
| callback 处理 | 用户点击 inline button 后发送 callback_data |

#### 3.4.3 配置变更

| 配置项 | 值 | 状态 |
|------|------|------|
| `gateway.http.endpoints.chatCompletions.enabled` | `true` | ✅ 已完成 |
| `webchat.capabilities.inlineButtons` | `"all"` | 待启用 |
| `session.dmScope` | `"per-channel-peer"` | ✅ 已完成 |

---

## 四、前端改动（Flutter）

### 4.1 新增组件

#### 4.1.1 InlineButtonGrid Widget

```
┌─────────────────────────────────┐
│  消息文本内容                     │
│                                 │
│  ┌──────────┐  ┌──────────┐    │
│  │ Button 1  │  │ Button 2  │    │
│  └──────────┘  └──────────┘    │
│  ┌──────────┐  ┌──────────┐    │
│  │ Button 3  │  │ Button 4  │    │
│  └──────────┘  └──────────┘    │
│  ┌──────────────────────────┐  │
│  │       << back             │  │
│  └──────────────────────────┘  │
└─────────────────────────────────┘
```

- 支持 N 列布局
- 按钮样式：`primary`（蓝色）、`success`（绿色）、`danger`（红色）、默认（灰色）
- 选中状态：✓ 前缀 + 高亮边框
- 禁用状态：灰色 + 不可点击
- 点击反馈：ripple 效果 + loading 状态

#### 4.1.2 消息气泡扩展

| 消息类型 | 渲染方式 |
|----------|---------|
| 纯文本 | 现有 Markdown 渲染（不变） |
| 文本 + buttons | 文本气泡 + 底部按钮网格 |
| 纯 buttons | 仅按钮网格（无文本） |
| 命令结果 | 现有命令气泡样式（保留） |

### 4.2 修改组件

| 组件 | 改动 |
|------|------|
| `ChatProvider` | 新增 inline button 回调处理；agent 路由逻辑 |
| `WsService` | 适配 OpenClaw Gateway WS 协议（`chat.send`/`chat.history`） |
| `CommandService` | 命令列表从 OpenClaw 动态获取；权限过滤 |
| `chat_screen.dart` | 消息气泡支持渲染 buttons；禁止命令灰显 |
| `AuthService` | 注册流程集成 agent 创建 |

---

## 五、服务端改动（Node.js）

### 5.1 新增模块

| 模块 | 功能 |
|------|------|
| `agent-manager.js` | Agent CRUD：创建、删除、列表、模板初始化 |
| `gateway-ws.js` | OpenClaw Gateway WebSocket 客户端，替代 HTTP gateway.js |
| `permission.js` | 权限检查：admin vs 普通用户 × 命令白名单 |

### 5.2 修改模块

| 模块 | 改动 |
|------|------|
| `routes/auth.js` | 注册时调用 agent-manager 创建 agent |
| `ws-handler.js` | 消息路由到用户对应的 agent；转发 inline button 回调 |
| `routes/commands.js` | 权限过滤；禁止命令返回结构化拦截响应 |
| `config.js` | 新增 agent 模板路径、权限配置 |

### 5.3 注册流程改造

```
用户提交注册
    → 创建 ClawChat 数据库用户
    → 调用 openclaw agents add clawchat-<userId> --non-interactive --workspace ~/clawchat/agents/<userId>
    → 复制通用 SOUL.md 模板到新 workspace
    → 返回注册成功
```

### 5.4 消息流程改造

```
用户发送消息
    → ClawChat WS 收到
    → 查询用户角色，确定 agentId:
        - admin → "main"
        - 普通用户 → "clawchat-<userId>"
    → 通过 Gateway WS 发送到对应 agent（chat.send）
    → 接收 Gateway 响应（含 text + buttons）
    → 转发给 Flutter 客户端
    → 客户端渲染文本 + inline buttons
```

### 5.5 按钮回调流程

```
用户点击 inline button
    → Flutter 发送 { type: "callback", callback_data: "mdl_sel_yunyiai/claude-opus-4-6" }
    → ClawChat 服务端转发到 Gateway
    → Gateway 处理回调，返回新消息（可能是新菜单或确认文本）
    → 转发回客户端渲染
```

---

## 六、数据库变更

### 6.1 users 表新增字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `agent_id` | TEXT | 对应的 OpenClaw agent ID（如 `clawchat-alice`） |
| `model_override` | TEXT | 用户当前选择的模型（可空，空则使用 agent 默认） |

### 6.2 messages 表扩展

| 字段 | 类型 | 说明 |
|------|------|------|
| `buttons` | TEXT (JSON) | inline buttons 定义（可空） |
| `callback_data` | TEXT | 按钮回调数据（可空） |

---

## 七、文件结构变更

```
clawchat/
├── server/
│   ├── src/
│   │   ├── agent-manager.js     ← 新增：Agent 生命周期管理
│   │   ├── gateway-ws.js        ← 新增：OpenClaw Gateway WS 客户端
│   │   ├── permission.js        ← 新增：权限检查
│   │   ├── gateway.js           ← 废弃（被 gateway-ws.js 替代）
│   │   ├── ws-handler.js        ← 修改：agent 路由 + button 回调
│   │   ├── config.js            ← 修改：新增配置项
│   │   └── routes/
│   │       ├── auth.js          ← 修改：注册集成 agent 创建
│   │       └── commands.js      ← 修改：权限过滤
│   └── templates/
│       └── SOUL.md              ← 新增：通用 agent 模板
├── client/
│   └── lib/
│       ├── widgets/
│       │   └── inline_buttons.dart  ← 新增：InlineButtonGrid 组件
│       ├── providers/
│       │   └── chat_provider.dart   ← 修改：button 回调处理
│       ├── services/
│       │   ├── ws_service.dart      ← 修改：适配 Gateway WS 协议
│       │   └── command_service.dart ← 修改：动态命令 + 权限
│       ├── screens/
│       │   └── chat_screen.dart     ← 修改：渲染 buttons
│       └── models/
│           └── message.dart         ← 修改：新增 buttons 字段
└── docs/
    └── REQUIREMENTS-v2.md           ← 本文档
```

---

## 八、实施计划

### Phase 1：基础设施（服务端）
1. 创建通用 SOUL.md 模板
2. 实现 `agent-manager.js`（agent 创建/删除）
3. 修改注册流程，集成 agent 自动创建
4. 实现 `permission.js` 权限检查模块
5. 启用 `webchat.capabilities.inlineButtons`

### Phase 2：通信架构改造（服务端）
1. 实现 `gateway-ws.js`（OpenClaw Gateway WS 客户端）
2. 修改 `ws-handler.js`（agent 路由 + button 回调转发）
3. 废弃 `gateway.js`（HTTP 方式）
4. 数据库 migration（users 新增 agent_id，messages 新增 buttons）

### Phase 3：前端改造（Flutter）
1. 新增 `InlineButtonGrid` Widget
2. 修改 `WsService` 适配新协议
3. 修改 `ChatProvider` 处理 button 回调
4. 修改 `chat_screen.dart` 渲染 buttons + 权限灰显
5. 修改 `CommandService` 动态命令加载

### Phase 4：测试 & 构建
1. 服务端功能测试（agent 创建、消息路由、权限拦截）
2. 客户端功能测试（按钮渲染、多级菜单、命令交互）
3. 多用户场景测试（隔离验证）
4. 构建 APK 并发布

---

## 九、风险与注意事项

| 风险 | 应对 |
|------|------|
| Gateway WS 协议未充分文档化 | 参考 OpenClaw 源码 + 现有 webchat 实现 |
| Agent 数量过多占用磁盘 | 后续可加上限 + 定期清理不活跃 agent |
| 模型 API 费用被普通用户消耗 | 可按用户设置模型白名单/配额（v3 考虑） |
| callback_data 格式依赖 OpenClaw 内部实现 | 作为透传处理，不硬编码格式 |
| 现有 ClawChat 用户数据迁移 | 现有用户自动关联到 `clawchat-<userId>` agent |

---

## 十、验收标准

1. ✅ 输入 `/` 弹出完整命令候选列表
2. ✅ 输入 `/models` 显示 provider 按钮列表
3. ✅ 点击 provider 按钮显示 model 按钮列表，当前模型有 ✓
4. ✅ 点击 model 按钮切换模型并确认
5. ✅ `<< back` 按钮返回上一级
6. ✅ 新注册用户自动获得独立 agent
7. ✅ 不同用户之间会话完全隔离
8. ✅ Admin 可执行所有命令
9. ✅ 普通用户敏感命令显示灰色，点击提示 `🔒 禁止使用该命令`
10. ✅ 新安装的 skill 命令自动出现在命令列表中
11. ✅ Admin 用户路由到 `agent:main`，保留完整私人功能
