---
name: get
description: "读取其他平台的共享摘要并注入上下文。当用户提到'share-task:get'、'读取摘要'、'获取上下文'时触发。"
---

# share-task:get — 读取共享摘要

读取指定平台上其他 AI 工具提交的会话摘要，注入当前上下文供分析。

## 参数格式

`share-task:get {token} {platform}`

- `token`：任务口令
- `platform`：要读取的目标平台标识

## 执行流程

### Phase 1: 校验存在性

1. 读取 `{plugin-dir}/config.json`
   - 无则提示：`请先执行 share-task:start 配置黑板路径`
2. 读取 `{blackboard}/index.json`
   - 检查 `tasks.{token}.{platform}` 是否存在
   - 不存在则输出错误：`未找到口令 "{token}" + 平台 "{platform}" 的任务记录`

### Phase 2: 读取摘要

3. **状态为 pending**：
   - 输出提示：`平台 "{platform}" 尚未提交摘要，当前状态为 pending`
   - 结束，不继续
4. **状态为 set**：
   - 获取 `logs` 数组最后一个文件名
   - 读取 `{blackboard}/{token}/{platform}/{filename}` 的完整内容

### Phase 3: 注入上下文

5. 将摘要内容注入当前上下文，供 AI 分析
6. 输出：
   - 摘要完整内容
   - 来源路径：`来源: {blackboard}/{token}/{platform}/{filename}`
7. 建议用户基于摘要内容提出下一步指令

## 错误处理

| 场景 | 处理 |
|------|------|
| config.json 不存在 | 提示先配置黑板 |
| 条目不存在 | 报错：未找到记录 |
| 状态为 pending | 提示尚未提交摘要 |
| logs 为空 | 提示无可用摘要文件 |
