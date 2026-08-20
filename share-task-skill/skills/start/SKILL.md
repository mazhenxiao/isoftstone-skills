---
name: start
description: "配置共享数据文件地址（黑板路径）。当用户提到'share-task:start'、'初始化共享任务'、'配置黑板'时触发。"
---

# share-task:start — 配置黑板路径

配置跨平台共享数据的存储目录（黑板），仅在首次或需要修改时执行。同时注册本平台任务身份（token + platform），供 push 模式投递与消费使用。

## 参数格式

`share-task:start {token}.{platform}`（推荐）或 `share-task:start {token} {platform}`（旧格式兼容）

- `token`：任务口令
- `platform`：本平台标识（如 claude / oc / qodercli），点号后缀即自己（`start report.oc` = 我是 oc）

参数解析规则（四个命令统一）：

| 输入 | 解析 |
|------|------|
| 1 个参数且含点号 | 按最后一个点拆分：token=前段, platform=后段（platform 不含点号） |
| 2 个参数 | 旧格式：token=$1, platform=$2 |
| 0 个参数 | 提示用户输入 token 和 platform（start 无免参回落） |

补充说明：

- 单个**不含点号**的参数视为黑板绝对路径（旧用法，仅配置路径，不注册身份）
- 黑板路径不通过地址参数传入：未配置或需修改时按 Phase 2 交互确认
- 点号示例：`share-task:start report.oc` 等价于 `share-task:start report oc`

## 执行流程

### Phase 1: 读取现有配置

1. 读取 `{plugin-dir}/config.json`

### Phase 2: 路径确认

2. **已有 blackboard 且未传入路径参数**：
   - 提示：`当前黑板路径: {path}，是否需要修改？(y/n)`
   - 用户选 n → 结束，输出：`黑板路径未变更: {path}`
   - 用户选 y → 提示输入新路径，更新 config.json 的 blackboard 字段
3. **传入了路径参数**：
   - 直接使用传入的路径，更新 config.json 的 blackboard 字段
4. **无 blackboard**：
   - 提示：`请输入共享黑板目录的绝对路径（如 ~/work/share-tasks）：`
   - 将路径写入 config.json

（v2 追加）路径确认完成后，若本次已确定 token 和 platform（地址参数解析得出，或 0 参数时提示用户补输），执行身份写入——即使路径确认环节以"黑板路径未变更"收尾也不跳过：

- config.json 写入 `platform` → `{platform}`（本平台身份，供 produce/consume 与 hooks 作为默认平台）
- config.json 写入 `lastToken` → `{token}`、`lastPlatform` → `{platform}`

### Phase 3: 初始化目录

5. 执行 `mkdir -p {blackboard}` 确保目录存在
6. 读取 `{blackboard}/index.json`，不存在则初始化为：
   ```json
   {"blackboard": "{blackboard}", "tasks": {}}
   ```
7. 输出确认：`黑板已配置 — 路径: {blackboard}`

（v2 追加）：

- 执行 `mkdir -p {blackboard}/topics/`（幂等；push 模式消息队列根目录）
- 本次注册了身份时，将任务条目注册到 index.json（produce.sh 依赖 `tasks.{token}` 的平台 keys 推导收件人，注册即订阅）：
  - `tasks.{token}.{platform}` **不存在** → 创建：`{"status": "pending", "created": 当前ISO8601, "updated": 当前ISO8601, "logs": []}`
  - **已存在** → 保留原条目，仅更新 `updated`（不重置 status/logs）
  - 用 `{plugin-dir}/scripts/sync-index.sh` 原子写入 index.json
- 本次注册了身份时追加输出：`本平台身份已注册 — 口令: {token}, 平台: {platform}`

## 错误处理

| 场景 | 处理 |
|------|------|
| config.json 不存在 | 自动创建并进入路径配置流程 |
| 用户取消输入 | 不修改配置，静默返回 |
| topics/ 创建失败 | 输出警告，不中断（produce.sh 会按需重建） |
