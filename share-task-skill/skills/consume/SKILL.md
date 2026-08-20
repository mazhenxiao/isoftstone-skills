---
name: consume
description: "消费其他平台投递的推送消息并注入上下文。当用户提到'share-task:consume'、'消费消息'、'接收通知'时触发。"
---

# share-task:consume — 消费推送消息

消费黑板上其他平台通过 push 模式投递给本平台的消息队列，将摘要注入当前上下文。
claude 平台正常情况下已由 hooks 自动消费（SessionStart / UserPromptSubmit），本命令用于手动补消费、确认队列状态或排查问题。

## 参数格式

`share-task:consume [address]`

- `address`（可选）：`{token}.{platform}` 点号格式，限定只消费单个 topic（platform 后缀应为本平台）
- 不传则消费所有投递给本平台的消息（`topics/*.{本平台}/`）

## 执行流程

### Phase 1: 调用消费脚本

1. 默认执行（消费本平台全部待消费消息）：
   ```bash
   bash {plugin-dir}/scripts/consume.sh
   ```
2. 限定单个 topic 时传入 address：
   ```bash
   bash {plugin-dir}/scripts/consume.sh "{token}.{platform}"
   ```
3. 脚本按消息时间顺序逐条消费（单次上限 3 条）：
   - 读取消息 → 读取对应摘要文件 → 输出注入块 → 归档至 `done/`
   - 摘要文件缺失 → 提示缺失并归档至 `failed/`，继续下一条
   - 消息滞留超过 7 天 → 注入块头部附带滞留警告
   - 队列为空 → 输出 `无待消费消息`，结束
   - 仍有剩余 → 提示 `（还有 N 条待消费，下轮自动继续）`

### Phase 2: 注入上下文

4. 将脚本 stdout 输出的注入块（`来自 {source} 的任务摘要 ...`）作为上下文，参与后续推理与对话

### Phase 3: 建议下一步

5. 基于注入的摘要内容，向用户建议下一步动作，例如：
   - 继续推进对端遗留的任务
   - 核对/采纳对端的关键决策与结论
   - 需要更完整上下文时执行 share-task:get 拉取
   - 本平台有产出后执行 share-task:set 回投对端

## 错误处理

| 场景 | 处理 |
|------|------|
| 未执行过 share-task:start（无 blackboard 或 platform 身份） | 脚本退出码 2，提示先执行 share-task:start |
| address 的平台后缀不是本平台 | 无匹配 topic，提示检查 address |
| 摘要文件缺失 | 脚本归档 failed/ 并提示，不影响其余消息消费 |
