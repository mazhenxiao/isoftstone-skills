---
name: start
description: "初始化跨平台共享任务。当用户提到'share-task:start'、'初始化共享任务'、'创建共享黑板'时触发。"
---

# share-task:start — 初始化共享任务

初始化一个跨平台共享任务，在黑板上创建 pending 状态条目。

## 参数格式

`share-task:start {token} {platform}`

- `token`：任务口令（用于跨平台匹配）
- `platform`：当前平台标识（如 claude、opencode、cursor）

## 执行流程

### Phase 1: 读取配置

1. 读取 `{plugin-dir}/config.json`
2. **无 config.json 或缺少 blackboard 字段**：
   - 提示用户输入黑板绝对路径：`请输入共享黑板目录的绝对路径（如 ~/work/share-tasks）：`
   - 将路径写入 config.json：`{"blackboard": "/absolute/path"}`
   - 执行 `mkdir -p` 创建黑板目录
3. **有 blackboard**：检查目录是否存在，不存在则 `mkdir -p`

### Phase 2: 初始化索引

4. 读取 `{blackboard}/index.json`，不存在则初始化为：
   ```json
   {"blackboard": "...", "tasks": {}}
   ```
5. 在 index.json 的 `tasks.{token}.{platform}` 创建条目：
   ```json
   {
     "status": "pending",
     "created": "{当前ISO8601时间}",
     "updated": "{当前ISO8601时间}",
     "logs": []
   }
   ```

### Phase 3: 写入确认

6. 用 `{plugin-dir}/scripts/sync-index.sh` 原子写入 index.json：
   ```bash
   bash {plugin-dir}/scripts/sync-index.sh "{blackboard}" '{json内容}'
   ```
7. 在当前会话上下文中记住 token 和 platform（供后续 set 使用）
8. 输出确认：`任务已初始化 — 口令: {token}, 平台: {platform}, 状态: pending`

## 错误处理

| 场景 | 处理 |
|------|------|
| config.json 不存在 | 提示用户输入黑板路径并自动创建 |
| 黑板目录不存在 | 自动 mkdir -p |
| token + platform 组合已存在 | 提示并覆盖（状态重置为 pending） |
