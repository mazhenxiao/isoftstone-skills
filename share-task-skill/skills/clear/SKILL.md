---
name: clear
description: "清除共享黑板上的指定任务或全部任务。当用户提到'share-task:clear'、'清除任务'、'清空黑板'时触发。"
---

# share-task:clear — 清除任务

清除黑板上的指定条目或全部任务数据，并同步清理对应的消息队列（topics/）；`--compact` 模式仅压缩队列归档。

## 参数格式

- `share-task:clear {token}.{platform}` — 清除指定条目（点号地址格式）
- `share-task:clear {token} {platform}` — 清除指定条目（旧两参格式）
- `share-task:clear` — 清除全部（需二次确认）
- `share-task:clear --compact` — 仅压缩消息队列：清除各 topic 的 done/ 与 failed/，保留 queue

参数解析规则（四个命令统一）：

| 输入 | 解析 |
|------|------|
| 1 个参数且含点号 | 按最后一个点拆分：token=前段, platform=后段（platform 不含点号） |
| 2 个参数 | 旧格式：token=$1, platform=$2 |
| 0 个参数 | 进入全量清除流程（Phase 2B，需二次确认） |

点号示例：`share-task:clear report.oc` 等价于 `share-task:clear report oc`。`--compact` 为模式开关，不带地址单独使用。

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

（v2 追加）同步删除该条目的消息队列整目录（不存在则跳过，幂等）：

```bash
rm -rf {blackboard}/topics/{token}.{platform}/
```

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

（v2 追加）全量清空包含 `topics/` 消息队列：所有 topic 的 queue/done/failed 一并清除（上述 find 命令已覆盖，topics/ 不存在时跳过）。

### Phase 2C: compact 模式（--compact）

1. 遍历 `{blackboard}/topics/` 下所有 topic 目录
2. 删除各 topic 的 `done/` 与 `failed/` 归档目录（produce.sh / consume.sh 会按需重建）：
   ```bash
   find {blackboard}/topics -mindepth 2 -maxdepth 2 -type d \( -name done -o -name failed \) -exec rm -rf {} +
   ```
3. **保留全部 `queue/`（待消费消息不动）**；不涉及摘要区（`{token}/{platform}/`）与 index.json
4. 输出确认：`消息队列已压缩 — done/failed 归档已清理，queue 保留`

## 错误处理

| 场景 | 处理 |
|------|------|
| 条目不存在 | 静默成功（幂等操作） |
| 黑板目录不存在 | 提示未初始化 |
| 用户取消全部清除 | 不执行，静默返回 |
| topics/ 不存在 | 静默跳过队列清理（幂等操作） |
