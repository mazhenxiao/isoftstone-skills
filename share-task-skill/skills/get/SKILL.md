---
name: get
description: "读取其他平台的共享摘要并注入上下文。当用户提到'share-task:get'、'读取摘要'、'获取上下文'时触发。"
---

# share-task:get — 读取共享摘要

读取指定平台上其他 AI 工具提交的会话摘要，注入当前上下文供分析。

## 参数格式

`share-task:get [token] [platform]`（推荐直接使用点号地址：`share-task:get {token}.{platform}`）

- `token`（可选）：任务口令。不传则尝试使用 config.json 中的 lastToken
- `platform`（可选）：要读取的目标平台标识。不传则尝试使用 config.json 中的 lastPlatform

参数解析规则（四个命令统一）：

| 输入 | 解析 |
|------|------|
| 1 个参数且含点号 | 按最后一个点拆分：token=前段, platform=后段（platform 不含点号） |
| 2 个参数 | 旧格式：token=$1, platform=$2 |
| 0 个参数 | 走现有 lastToken/lastPlatform 免参回落（见 Phase 2） |

点号示例：`share-task:get report.oc` 等价于 `share-task:get report oc`（读取 oc 写入的 report 摘要）。

## 执行流程

### Phase 1: 校验黑板配置

1. 读取 `{plugin-dir}/config.json`
   - 无 blackboard → 提示：`请先执行 share-task:start 配置黑板路径`

### Phase 2: 确定 token 和 platform

2. **两个参数都已传入**：直接使用
3. **参数不全（缺一个或两个）**：
   - 检查 config.json 中的 lastToken / lastPlatform
   - **有对应值** → 提示：`使用上次配置 — 口令: {lastToken}, 平台: {lastPlatform}，是否使用？(y/n)`
     - y → 使用已有值
     - n → 提示用户输入新的 token 和 platform，更新 config.json
   - **无对应值** → 提示用户输入缺失的 token 和/或 platform，写入 config.json

### Phase 3: 校验存在性

4. 读取 `{blackboard}/index.json`
5. 检查 `tasks.{token}.{platform}` 是否存在
   - 不存在则输出：`未找到口令 "{token}" + 平台 "{platform}" 的任务记录`

### Phase 4: 读取摘要

6. **状态为 pending**：
   - 输出：`平台 "{platform}" 尚未提交摘要，当前状态为 pending`
   - 结束
7. **状态为 set**：
   - 获取 `logs` 数组最后一个文件名
   - 读取 `{blackboard}/{token}/{platform}/{filename}` 的完整内容

### Phase 5: 注入上下文

8. 将摘要内容注入当前上下文，供 AI 分析
9. 输出：
   - 摘要完整内容
   - 来源路径：`来源: {blackboard}/{token}/{platform}/{filename}`
10. 建议用户基于摘要内容提出下一步指令

## 错误处理

| 场景 | 处理 |
|------|------|
| config.json 不存在 | 提示先配置黑板 |
| 条目不存在 | 报错：未找到记录 |
| 状态为 pending | 提示尚未提交摘要 |
| logs 为空 | 提示无可用摘要文件 |
