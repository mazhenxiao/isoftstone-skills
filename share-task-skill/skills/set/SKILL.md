---
name: set
description: "生成会话摘要并写入共享黑板。当用户提到'share-task:set'、'写入摘要'、'提交上下文'时触发。"
---

# share-task:set — 写入会话摘要

基于当前会话上下文生成结构化摘要，写入黑板供其他平台读取（pull 模式）；写入成功后自动向已注册的对端平台投递推送通知（push 模式，best-effort）。

## 参数格式

`share-task:set [token] [platform]`（推荐直接使用点号地址：`share-task:set {token}.{platform}`）

- `token`（可选）：任务口令。不传则尝试使用 config.json 中的 lastToken
- `platform`（可选）：当前平台标识。不传则尝试使用 config.json 中的 lastPlatform

参数解析规则（四个命令统一）：

| 输入 | 解析 |
|------|------|
| 1 个参数且含点号 | 按最后一个点拆分：token=前段, platform=后段（platform 不含点号） |
| 2 个参数 | 旧格式：token=$1, platform=$2 |
| 0 个参数 | 走现有 lastToken/lastPlatform 免参回落（见 Phase 2） |

点号示例：`share-task:set report.oc` 等价于 `share-task:set report oc`。

## 执行流程

### Phase 1: 校验黑板配置

1. 读取 `{plugin-dir}/config.json`
2. **无 blackboard**：
   - 自动执行 share-task:start 的配置流程（提示用户输入黑板路径）
   - 配置完成后继续后续流程

### Phase 2: 确定 token 和 platform

3. **两个参数都已传入**：直接使用，走**新记录模式**
4. **参数不全（缺一个或两个）**：
   - 检查 config.json 中的 lastToken / lastPlatform
   - **有对应值** → 提示：`使用上次配置 — 口令: {lastToken}, 平台: {lastPlatform}，是否使用？(y/n)`
     - y → 使用已有值，走 **update 模式**
     - n → 提示用户输入新的 token 和 platform，更新 config.json，走**新记录模式**
   - **无对应值** → 提示用户输入缺失的 token 和/或 platform，写入 config.json，走**新记录模式**
5. 将最终使用的 token 写入 config.json 的 lastToken，platform 写入 lastPlatform

（v2 追加）防误用护栏：若 config.json 已有 `platform` 字段（本平台身份），且最终确定的 platform 与其不一致：

- 提示：`当前平台身份为 {config.platform}，将写入 {token}/{platform}/ 摘要槽位，确认？(y/n)`
- y → 按最终确定的 platform 继续
- n → 提示用户重新确认平台（建议使用与 config.platform 一致的平台标识）
- config.json 无 `platform` 字段时跳过本护栏（旧配置兼容）

### Phase 3: 生成摘要

6. 读取 `{plugin-dir}/references/log-template.md` 获取模板
7. 基于当前会话上下文，生成 500-1000 字结构化摘要，遵循模板格式：
   - **任务描述**：一两句话说明目标
   - **关键决策**：做了什么决策，为什么
   - **代码变更**：文件路径 + 变更概述（不贴大段代码）
   - **结论/结果**：最终产出和完成状态
   - **遗留问题**：未解决的问题（诚实记录，不遗漏）
8. 不记录与当前任务无关的上下文

### Phase 4: 写入黑板

#### 新记录模式

9. 生成时间戳文件名：`YYYY-MM-DD-HHmmss.md`
10. 执行 `mkdir -p {blackboard}/{token}/{platform}/`
11. 写入摘要文件到 `{blackboard}/{token}/{platform}/{timestamp}.md`
12. 更新 index.json：
    - `tasks.{token}.{platform}.status` → `"set"`
    - `tasks.{token}.{platform}.logs` → `["{timestamp}.md"]`
    - `tasks.{token}.{platform}.created` → 当前 ISO8601 时间
    - `tasks.{token}.{platform}.updated` → 当前 ISO8601 时间
13. 用 `{plugin-dir}/scripts/sync-index.sh` 原子写入 index.json（v2：索引落盘提前至 Phase 4，供 produce 推导收件人）

#### update 模式（使用上次的 token + platform）

9. 生成时间戳文件名：`YYYY-MM-DD-HHmmss.md`
10. 执行 `mkdir -p {blackboard}/{token}/{platform}/`
11. 写入摘要文件到 `{blackboard}/{token}/{platform}/{timestamp}.md`
12. 删除该 token/platform 下的旧日志文件：
    ```bash
    # 保留最新的，删除其余
    cd {blackboard}/{token}/{platform}/ && ls -t *.md | tail -n +2 | xargs rm -f
    ```
13. 更新 index.json：
    - `tasks.{token}.{platform}.status` → `"set"`
    - `tasks.{token}.{platform}.logs` → `["{timestamp}.md"]`
    - `tasks.{token}.{platform}.updated` → 当前 ISO8601 时间
14. 用 `{plugin-dir}/scripts/sync-index.sh` 原子写入 index.json（v2：索引落盘提前至 Phase 4，供 produce 推导收件人）

### Phase 4.5: produce 投递（v2 追加，best-effort）

摘要与 index.json 均落盘后执行（produce 读取 index.json 推导收件人）：

```bash
bash {plugin-dir}/scripts/produce.sh "{blackboard}" "{token}" "{platform}" "{token}/{platform}/{timestamp}.md"
```

- 第 4 个参数为 Phase 4 刚写入的摘要文件（相对 blackboard 的路径）
- 收件人自动推导：`index.json` 中 `tasks.{token}` 的平台 keys 减去自身（platform），每个对端平台投递一条消息到 `topics/{token}.{对端平台}/queue/`
- **失败仅输出警告，不中断 set**（摘要已落盘，pull 模式保底）

### Phase 5: 确认

14. 输出确认：`摘要已写入 — 位置: {blackboard}/{token}/{platform}/{timestamp}.md, 状态: set`

（v2 追加）输出投递结果行（Phase 4.5 的结果）：

- 有对端平台注册 → 每个收件平台一行：`消息已投递 → topics/{token}.{对端平台}/queue/{id}.json`
- 无对端平台注册 → `无对端平台注册，仅写入摘要未投递（对端可先执行 share-task:start 注册）`

## 错误处理

| 场景 | 处理 |
|------|------|
| config.json 不存在 | 自动创建并进入黑板配置流程 |
| 用户取消输入 | 不修改配置，静默返回 |
| produce.sh 执行失败 | 仅输出警告，不中断 set（摘要已写入，pull 模式保底） |
