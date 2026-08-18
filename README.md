# isoftstone-skills

iSoftStone 共享 Skills 合集，跨 AI CLI 平台使用。

## 安装

### Claude Code（推荐：Marketplace 方式）

```bash
# 1. 注册 marketplace
/plugin marketplace add mazhenxiao/isoftstone-skills

# 2. 安装插件
/plugin install share-task@isoftstone-skills
```

### Claude Code（手动 symlink）

```bash
ln -s ~/isoftstone-skills/share-task-skill ~/.claude/skills/share-task
```

### OpenCode

```bash
ln -s ~/isoftstone-skills/share-task-skill ~/.opencode/skills/share-task
```

## 插件列表

### share-task

跨 AI CLI 平台的任务共享工具。通过文件级黑板，在不同 AI 工具（Claude Code、OpenCode、Cursor 等）之间共享任务上下文和会话摘要。

- **start** — 初始化任务，设置口令和平台名
- **set** — 生成当前会话摘要并写入共享黑板
- **get** — 读取其他平台的摘要，注入当前上下文
- **clear** — 清除指定任务或全部任务

#### 使用示例

```bash
# 在 Claude Code 中初始化任务
share-task:start mzx claude

# Claude Code 完成工作后，提交摘要
share-task:set

# 切换到 OpenCode，读取 Claude 的摘要
share-task:get mzx claude

# 清除任务记录
share-task:clear mzx claude
```

#### 工作原理

```
{blackboard}/
├── index.json              # 任务索引和状态
└── {token}/                 # 按口令隔离
    └── {platform}/         # 按平台隔离
        └── {timestamp}.md  # 会话摘要文件
```

首次使用 `start` 时会提示配置黑板目录路径，配置持久化后无需重复输入。

## 依赖

无第三方依赖。仅需要文件读写权限和基本 shell 命令（mkdir、ls、rm）。
