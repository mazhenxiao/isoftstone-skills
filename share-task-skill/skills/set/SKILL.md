---
name: set
description: "生成会话摘要并写入共享黑板。当用户提到'share-task:set'、'写入摘要'、'提交上下文'时触发。"
---

# share-task:set — 写入会话摘要

基于当前会话上下文生成结构化摘要，写入黑板供其他平台读取。

## 前置条件

必须先执行 `share-task:start {token} {platform}`。否则提示：`请先执行 share-task:start {token} {platform} 初始化任务`

## 执行流程

### Phase 1: 校验上下文

1. 检查当前会话上下文中是否有 token 和 platform（来自之前的 start）
   - 无则提示：`请先执行 share-task:start {token} {platform} 初始化任务`
   - 有则继续
2. 读取 `{plugin-dir}/config.json` 获取黑板路径

### Phase 2: 生成摘要

3. 读取 `{plugin-dir}/references/log-template.md` 获取模板
4. 基于当前会话上下文，生成 500-1000 字结构化摘要，遵循模板格式：
   - **任务描述**：一两句话说明目标
   - **关键决策**：做了什么决策，为什么
   - **代码变更**：文件路径 + 变更概述（不贴大段代码）
   - **结论/结果**：最终产出和完成状态
   - **遗留问题**：未解决的问题（诚实记录，不遗漏）
5. 不记录与当前任务无关的上下文

### Phase 3: 写入黑板

6. 生成时间戳文件名：`YYYY-MM-DD-HHmmss.md`（用当前时间）
7. 执行 `mkdir -p {blackboard}/{token}/{platform}/`
8. 写入摘要文件到 `{blackboard}/{token}/{platform}/{timestamp}.md`
9. 更新 index.json：
   - `tasks.{token}.{platform}.status` → `"set"`
   - `tasks.{token}.{platform}.logs` → 追加 `{timestamp}.md`
   - `tasks.{token}.{platform}.updated` → 当前 ISO8601 时间
10. 用 `{plugin-dir}/scripts/sync-index.sh` 原子写入 index.json
11. 输出确认：`摘要已写入 — 位置: {blackboard}/{token}/{platform}/{timestamp}.md, 状态: set`
