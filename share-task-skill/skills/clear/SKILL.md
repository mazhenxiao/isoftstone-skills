---
name: clear
description: "清除共享黑板上的指定任务或全部任务。当用户提到'share-task:clear'、'清除任务'、'清空黑板'时触发。"
---

# share-task:clear — 清除任务

清除黑板上的指定条目或全部任务数据。

## 参数格式

- `share-task:clear {token} {platform}` — 清除指定条目
- `share-task:clear` — 清除全部（需二次确认）

## 执行流程

### Phase 1: 校验与读取

1. 读取 `{plugin-dir}/config.json` 获取黑板路径
2. 读取 `{blackboard}/index.json`

### Phase 2A: 清除指定条目（有 token + platform）

1. 执行 `rm -rf {blackboard}/{token}/{platform}/`
2. 从 index.json 中移除 `tasks.{token}.{platform}` 条目
3. 如果 `tasks.{token}` 下已无子条目：
   - 删除 `{blackboard}/{token}/` 目录
   - 从 index.json 中移除 `tasks.{token}` 键
4. 用 `{plugin-dir}/scripts/sync-index.sh` 原子写入 index.json
5. 静默成功，输出：`已清除 口令: {token}, 平台: {platform}`

### Phase 2B: 清除全部（无参数）

1. 提示用户确认：`将清空黑板下所有任务数据，仅保留配置。确认？`
2. 用户确认后：
   - 删除 `{blackboard}/` 下除 index.json 外的所有内容：
     ```bash
     find {blackboard} -mindepth 1 ! -name index.json -delete
     ```
   - 清理空子目录：
     ```bash
     find {blackboard} -type d -empty -delete
     ```
   - index.json 重置为 `{"blackboard": "...", "tasks": {}}`
   - 用 `sync-index.sh` 原子写入
3. 输出确认：`黑板已清空，配置已保留`

## 错误处理

| 场景 | 处理 |
|------|------|
| 条目不存在 | 静默成功（幂等操作） |
| 黑板目录不存在 | 提示未初始化 |
| 用户取消全部清除 | 不执行，静默返回 |
