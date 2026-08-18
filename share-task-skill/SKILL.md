---
name: share-task
description: 跨 AI CLI 平台的任务共享工具。当用户提到"share-task"、"共享任务"、"跨平台任务"、"分享上下文"、"同步会话"、"黑板"、"share-task:start"、"share-task:set"、"share-task:get"、"share-task:clear"时触发。也适用于：用户想在不同 AI 工具（如 Claude Code、OpenCode、Cursor 等）之间传递任务上下文或会话摘要。
---

# share-task — 跨平台任务共享

通过文件级黑板，在不同 AI CLI 工具之间共享任务上下文和会话摘要。

## 命令

| 命令 | 格式 | 说明 |
|------|------|------|
| `start` | `share-task:start {token} {platform}` | 初始化任务，状态设为 pending |
| `set` | `share-task:set` | 生成会话摘要并写入黑板 |
| `get` | `share-task:get {token} {platform}` | 读取其他平台的摘要并注入上下文 |
| `clear` | `share-task:clear [{token} {platform}]` | 清除指定条目或全部 |

## 核心路径

- Skill 目录：`~/.claude/skills/share-task/`
- 配置文件：`{skill-dir}/config.json`（存储黑板路径）
- 黑板目录：由用户在首次 start 时指定

## 执行流程

### share-task:start {token} {platform}

1. 读取 `{skill-dir}/config.json`
2. **无 config.json 或缺少 blackboard 字段**：
   - 提示用户输入黑板绝对路径，例如：`请输入共享黑板目录的绝对路径（如 ~/work/share-tasks）：`
   - 将路径写入 config.json：`{"blackboard": "/absolute/path"}`
   - 执行 `mkdir -p` 创建黑板目录
3. **有 blackboard**：检查目录是否存在，不存在则 `mkdir -p`
4. 读取 `{blackboard}/index.json`，不存在则初始化为 `{"blackboard": "...", "tasks": {}}`
5. 在 index.json 的 `tasks.{token}.{platform}` 创建条目：
   ```json
   {
     "status": "pending",
     "created": "{当前ISO8601时间}",
     "updated": "{当前ISO8601时间}",
     "logs": []
   }
   ```
6. 用 `sync-index.sh` 原子写入 index.json
7. 在当前会话上下文中记住 token 和 platform（供后续 set 使用）
8. 输出确认：`任务已初始化 — 口令: {token}, 平台: {platform}, 状态: pending`

### share-task:set

1. **检查上下文中是否有 token 和 platform**（来自之前的 start）
   - 无则提示：`请先执行 share-task:start {token} {platform} 初始化任务`
   - 有则继续
2. 读取 config.json 获取黑板路径
3. 基于当前会话上下文，AI 生成 500-1000 字结构化摘要。**必须使用 references/log-template.md 中的模板格式**
4. 生成时间戳文件名：`YYYY-MM-DD-HHmmss.md`（用当前时间）
5. 执行 `mkdir -p {blackboard}/{token}/{platform}/`
6. 写入摘要文件到 `{blackboard}/{token}/{platform}/{timestamp}.md`
7. 更新 index.json：
   - `tasks.{token}.{platform}.status` → `"set"`
   - `tasks.{token}.{platform}.logs` → 追加 `{timestamp}.md`
   - `tasks.{token}.{platform}.updated` → 当前 ISO8601 时间
8. 用 `sync-index.sh` 原子写入 index.json
9. 输出确认：`摘要已写入 — 位置: {blackboard}/{token}/{platform}/{timestamp}.md, 状态: set`

### share-task:get {token} {platform}

1. 读取 `{skill-dir}/config.json`
   - 无则提示：`请先执行 share-task:start 配置黑板路径`
2. 读取 `{blackboard}/index.json`
   - 检查 `tasks.{token}.{platform}` 是否存在
   - 不存在则输出错误：`未找到口令 "{token}" + 平台 "{platform}" 的任务记录`
3. **状态为 pending**：输出提示：`平台 "{platform}" 尚未提交摘要，当前状态为 pending`
4. **状态为 set**：
   - 获取 `logs` 数组最后一个文件名
   - 读取 `{blackboard}/{token}/{platform}/{filename}` 的完整内容
   - 将摘要内容注入当前上下文，供 AI 分析
   - 输出：摘要内容 + 来源路径
5. 建议用户基于摘要内容提出下一步指令

### share-task:clear {token} {platform}

1. 读取 config.json 获取黑板路径
2. 执行 `rm -rf {blackboard}/{token}/{platform}/`
3. 从 index.json 中移除 `tasks.{token}.{platform}` 条目
4. 如果 `tasks.{token}` 下已无子条目：
   - 删除 `{blackboard}/{token}/` 目录
   - 从 index.json 中移除 `tasks.{token}` 键
5. 用 `sync-index.sh` 原子写入 index.json
6. 静默成功，输出：`已清除 口令: {token}, 平台: {platform}`

### share-task:clear（全部）

1. 提示用户确认：`将清空黑板下所有任务数据，仅保留配置。确认？`
2. 用户确认后：
   - 删除 `{blackboard}/` 下除 index.json 外的所有内容：`find {blackboard} -mindepth 1 ! -name index.json -delete`
   - 清理空子目录：`find {blackboard} -type d -empty -delete`
   - index.json 重置为 `{"blackboard": "...", "tasks": {}}`
   - 用 `sync-index.sh` 原子写入
3. 输出确认：`黑板已清空，配置已保留`

## 摘要生成规则

执行 `set` 时，AI 需要根据当前会话生成结构化摘要。遵循以下规则：

1. 读取 `references/log-template.md` 获取模板
2. 摘要长度控制在 500-1000 字
3. 聚焦当前任务的核心信息：做了什么、为什么这么做、结果如何、还有什么没解决
4. 不记录与当前任务无关的上下文
5. 代码变更只记路径和概述，不贴大段代码
6. 遗留问题要诚实记录，不要遗漏

## 错误处理速查

| 场景 | 处理 |
|------|------|
| config.json 不存在 | start 时提示用户输入黑板路径并自动创建 |
| 黑板目录不存在 | 自动 mkdir -p |
| 未 start 就 set | 提示先执行 share-task:start |
| get 时状态为 pending | 提示尚未提交摘要 |
| get 时条目不存在 | 报错 |
| clear 不存在的条目 | 静默成功 |
| clear 全部 | 需用户二次确认 |

## 跨平台使用

其他 AI CLI 工具（如 OpenCode、Cursor Agent）要使用此 skill：

1. 软链接：`ln -s ~/.claude/skills/share-task ~/.opencode/skills/share-task`
2. 复制：将整个 `share-task/` 目录复制到对应工具的 skills 目录

工具只需具备：文件读写 + 基本 shell 命令（mkdir、ls、rm）。无第三方依赖。
