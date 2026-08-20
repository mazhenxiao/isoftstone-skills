# share-task Push 模式设计 v2（修订版）

> 日期：2026-08-20
> 基于：QoderWork 初版方案（share-task-push-design.md）评审修订
> 状态：已确认，实施中

## 一、目标与总体架构

**目标**：`set` = 总结记录并投递通知；对端注册了相同口令的平台**自动接收、自动消费、自动进入上下文**参与任务推理。

**物理边界（诚实声明）**：AI 会话无法被文件事件远程唤醒。能做到的最优形态：
- 对端会话运行中 → 下一轮用户输入时经 hook 自动感知并消费（人无感）
- 对端会话未运行 → 会话启动时（SessionStart）自动感知并消费

**三层架构**：

```
┌─ 感知触发层（每平台一个触发器）─────────────────────────┐
│ claude:    SessionStart + UserPromptSubmit hooks（全自动） │
│ opencode:  AGENTS.md 指令，AI 会话开始/任务开始时执行      │
│ qodercli:  全局指令文件，同上                              │
│ watcher.sh（可选兜底）→ macOS 系统通知，面向人             │
└──────────────────┬────────────────────────────┘
                   ↓ 调用（stdout 即注入内容）
┌─ 共享逻辑层（bash + node 脚本，唯一实现）────────────────┐
│ scripts/produce.sh   写消息（set 后调用，best-effort）     │
│ scripts/consume.sh   消费：读队列→读摘要→mv→格式化输出     │
│ scripts/watcher.sh   轮询通知（带去重 state）              │
└──────────────────┬────────────────────────────┘
                   ↓ 读写
┌─ 投递契约层（平台中立的文件结构）────────────────────────┐
│ {blackboard}/topics/{token}.{platform}/queue|done|failed  │
└─────────────────────────────────────────────┘
```

核心原则：
1. **逻辑只写一遍**（bash 脚本），平台差异只体现在触发方式
2. **消费的 stdout 即注入内容**——claude 的 hook 直接注入上下文；opencode/qodercli 的 AI 执行脚本后把 stdout 当上下文
3. **注册即订阅**：收件人从 index.json 注册表自动推导，`set` 用法零变化

## 二、目录结构与消息格式

### 黑板结构

```
{blackboard}/
├── index.json                          # 现有，不变
├── topics/                             # 新增：消息队列
│   └── {token}.{platform}/             # platform = 消费方（收件人）平台
│       ├── queue/                      # 待消费消息 000000001.json ...
│       ├── done/                       # 已消费
│       └── failed/                     # 摘要缺失等无法消费的消息（无重试计数）
└── {token}/{platform}/                 # 现有摘要区，不变（platform = 写入方）
```

### 消息格式（扁平 JSON，无 retryCount）

```json
{
  "id": 1,
  "topic": "report.claude",
  "token": "report",
  "source": "oc",
  "recipient": "claude",
  "action": "set",
  "summaryFile": "report/oc/2026-08-20-101530.md",
  "timestamp": "2026-08-20T10:15:30+08:00"
}
```

- 消息文件**写入后不可变**（v2 无原地更新；原方案 retryCount 原地更新违反该原则，已移除）
- `summaryFile` 为相对 blackboard 的路径
- ID：9 位零填充，文件名即 topic 内排序键；跨 topic 排序用 `timestamp`
- 消费时摘要缺失 → 一次判定 `mv queue→failed/`，不做重试计数

### 平台标识约定

`claude` / `oc` / `qodercli`（与现有黑板 `report.oc` 用法一致）。

### config.json（{plugin-root}/skills/start/config.json）

```json
{
  "blackboard": "/absolute/path",
  "platform": "claude",
  "lastToken": "report",
  "lastPlatform": "oc"
}
```

- `blackboard`：黑板绝对路径（现有）
- `platform`：**本平台身份**（start 时写入，供 consume/produce 默认值与 hooks 过滤）
- `lastToken`/`lastPlatform`：现有免参回落（保留，不受本次改造影响）
- 多平台共用脚本时身份由调用参数显式指定（hooks 带 `--platform claude`，opencode 指令带 `--platform oc`），config 的 platform 仅为省略时的默认值

## 三、参数格式：{口令}.{平台}（新旧兼容）

四个命令统一支持点号地址格式，**并保留旧两参数写法**：

| 命令 | 新格式 | 旧格式（兼容） | 语义 |
|---|---|---|---|
| start | `start report.oc` | `start report oc` | 注册本平台身份（.oc = 自己） |
| set | `set report.oc` | `set report oc` | 在本平台写入 report 摘要并投递 |
| get | `get report.oc` | `get report oc` | 读取 oc 写的 report 摘要 |
| clear | `clear report.oc` | `clear report oc` | 清除 report 的 oc 侧数据 |

**参数解析规则（四个 SKILL.md 统一写法）**：

```
1 个参数且含点号 → 按最后一个点拆分（platform 不含点号）：token=前段, platform=后段
2 个参数        → 旧格式：token=$1, platform=$2
0 个参数        → set/get 走现有 lastToken/lastPlatform 免参回落
```

三处地址格式统一：命令 `report.oc` ↔ 摘要路径 `report/oc/` ↔ 消息 topic `topics/report.oc/`。

**防误用护栏**：`set` 的平台后缀应为本平台（config.platform）；不匹配时提示用户确认，避免误写他人 slot。

## 四、produce（写入方）

### 收件人推导（注册即订阅）

```
recipients = index.json 中 tasks.{token} 的平台 keys − {set 的平台参数（source 自身）}
```

- 多个对端注册（如 claude + qodercli）→ 每个对端各投一条到 `topics/{token}.{recipient}/queue/`
- 无对端注册 → 仅写摘要不投递，输出提示（不报错）

### set 的改动（现有 Phase 1-4 不动）

```
Phase 4.5: produce（best-effort）
  bash {plugin-root}/scripts/produce.sh "{blackboard}" "{token}" "{platform}" "{token}/{platform}/{timestamp}.md"
  → 失败仅输出警告，不中断 set（pull 模式保底）

Phase 5: 输出（追加一行）
  "消息已投递 → topics/{topic}/queue/{id}.json"（或"无对端平台注册，未投递"提示）
```

### produce.sh 接口契约

```
用法: produce.sh <blackboard> <token> <source-platform> <summaryFile-rel>

行为:
  1. node 读 {blackboard}/index.json → recipients = keys(tasks.{token}) − source
  2. 对每个 recipient:
     topic = {token}.{recipient}
     mkdir -p topics/{topic}/{queue,done,failed}
     防覆盖取号循环: maxId+1 → 若目标文件已存在则继续 +1（修复并发竞态）
     消息 JSON 构造（timestamp = 当前 ISO8601 本地时区）
     tmp+mv 原子写入 queue/{id:09d}.json
  3. JSON 操作用 node -e（与 install.sh 先例一致，不依赖 jq）

输出(stdout): 每个 recipient 一行 "已投递 → topics/{topic}/queue/{id}.json"
退出码: 0 成功（含 recipients 为空）/ 1 错误
recipients 为空时: stderr 提示 "无对端平台注册，仅写入摘要未投递（对端可先执行 start 注册）"
```

## 五、consume（消费方）

### consume.sh 接口契约

```
用法: consume.sh [--auto] [--all] [--list] [--blackboard <path>] [--platform <id>] [address]

  address      可选，{token}.{platform} 格式，限定单个 topic（platform 后缀应为调用方自己）
  --blackboard 缺省读 PLUGIN_ROOT/skills/start/config.json 的 blackboard
  --platform   本平台身份；缺省读 config.json 的 platform 字段（无则 exit 2 提示先 start）
  --list       列出匹配 topic 的待消费数，不消费，exit 0
  --auto       队列空 → 无输出 exit 0；非空 → drain（上限 3 条）【hooks 用】
  （默认）     队列空 → 输出 "无待消费消息"；非空 → drain（上限 3 条）【手动/skill 用】
  --all        取消 3 条上限

drain 单条流程:
  候选 = 匹配 topics/{*.{platform} 或 address}/queue/*.json
  按 JSON 内 timestamp 升序取最早一条（跨 topic 统一排序，不用文件名）:
    读消息 → 读 {blackboard}/{summaryFile}
    成功 → 输出格式化注入块；mv queue → done
    滞留 > 7 天 → 块头加 "⚠ 该消息已滞留 N 天，建议确认时效"
    summaryFile 缺失/不可读 → 输出 "消息 #{id}: 摘要文件缺失（{file}），已归档 failed/"；mv queue → failed
  结束时若仍有剩余 → "（还有 N 条待消费，下轮自动继续）"

注入块格式（stdout，即 hook 注入内容）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
来自 {source} 的任务摘要 | {token}.{source} | {timestamp}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{摘要文件全文}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
以上摘要已注入上下文，请在后续思考和对话中参考此内容。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

退出码: 0 正常 / 1 错误 / 2 未配置（无 blackboard 或 platform）
```

### claude 侧 consume SKILL.md（新增，薄封装）

指导 AI 调 `consume.sh`（默认模式），消费后基于注入内容建议下一步。带 address 参数可指定单个 topic。

## 六、感知触发层

### claude（全自动）

`install.sh hooks` 子命令（opt-in）向 `~/.claude/settings.json` 幂等合并：

```json
"hooks": {
  "SessionStart":     [{ "hooks": [{ "type": "command", "command": "bash '<PLUGIN_ROOT>/scripts/consume.sh' --auto --platform claude" }] }],
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash '<PLUGIN_ROOT>/scripts/consume.sh' --auto --platform claude" }] }]
}
```

- `<PLUGIN_ROOT>` 使用**源码仓稳定绝对路径**（避免 cache 版本目录漂移），路径含中文需正确引号包裹
- hook stdout 直接进入会话上下文 → 摘要自动注入，AI 零动作
- 多会话并发消费安全：mv 原子性保证唯一赢家，输家静默跳过
- hook 脚本为毫秒级文件操作，无超时风险

### opencode / qodercli（指令驱动）

`references/cross-platform-protocol.md` 提供协议文档 + 薄指令模板，用户贴进：
- OpenCode：`~/.config/opencode/AGENTS.md`
- QoderCLI：其全局指令文件

指令模板核心（以 oc 为例）：

> 每次会话开始时及每个任务开始前，执行
> `bash '<PLUGIN_ROOT>/scripts/consume.sh' --auto --platform oc`
> 若输出包含摘要块，将其作为任务上下文参与后续推理，然后继续原任务。
> 写入摘要时遵循 cross-platform-protocol.md（生成摘要 + 调 produce.sh）。

### watcher.sh（可选兜底，修复通知风暴）

```
用法: watcher.sh <blackboard> <platform> [interval=5]
state: {blackboard}/.watcher-state-{platform} 记录上次已通知的 count
逻辑: count = 匹配 topics/*.{platform}/queue/*.json 的文件数
  count > last → osascript 通知一次（含 topic 列表），更新 state
  count <= last（含归零）→ 静默更新 state
```

默认不安装、不常驻；面向"人不在任何会话里"的场景手动启动。

## 七、start / clear 改动

### start

- 参数支持 `{address}` 新格式（兼容旧两参）
- Phase 2 追加：config.json 写入 `platform` 字段（本平台身份）+ lastToken/lastPlatform
- 追加 `mkdir -p {blackboard}/topics/`（幂等）

### clear（整合 compact）

- `clear {address}`：现有删除逻辑 + 同步删除 `topics/{token}.{platform}/` 整目录
- `clear`（全量）：现有清空 + 清空 topics/ 下所有内容
- `clear --compact`：只清各 topic 的 done/ 和 failed/，保留 queue（原 compact 的职责，不单独立 skill）

### get：仅参数格式解析变化，逻辑不变（pull 模式完整保留）

## 八、改动文件清单

| 文件 | 动作 | 说明 |
|---|---|---|
| `scripts/produce.sh` | 新增 | 投递（收件人自动推导 + 防覆盖取号 + 原子写） |
| `scripts/consume.sh` | 新增 | 消费（platform 过滤 + timestamp 排序 + TTL 警告 + failed 归档） |
| `scripts/watcher.sh` | 新增 | 轮询通知（state 去重，修复原方案通知风暴） |
| `skills/set/SKILL.md` | 改 | 参数格式 + Phase 4.5 produce + 护栏 |
| `skills/get/SKILL.md` | 改 | 参数格式（兼容） |
| `skills/start/SKILL.md` | 改 | 参数格式 + platform 身份写入 + topics/ 初始化 |
| `skills/clear/SKILL.md` | 改 | 参数格式 + topics 清理 + --compact |
| `skills/consume/SKILL.md` | 新增 | claude 侧薄封装 |
| `references/cross-platform-protocol.md` | 新增 | opencode/qodercli 协议 + 指令模板 |
| `install.sh` | 改 | 追加 `hooks` 子命令（幂等注册） |
| `package.json` | 改 | version 1.0.0 → 1.1.0 |

**不动**：`scripts/sync-index.sh`、`references/log-template.md`、pull 模式全部行为。

## 九、与原方案（QoderWork 初版）的差异清单

| # | 原方案 | v2 修订 | 原因 |
|---|---|---|---|
| 1 | set 的 platform 参数 = 投递目标 | platform = 本平台（语义不变）；收件人从 index 注册表推导 | 原方案与现有 get/set/start 语义冲突，且注册即订阅更符合目标 |
| 2 | consume 扫描所有 topic 取 ID 最小 | 按本平台身份过滤 topics/*.{platform}，timestamp 排序 | 修复串台 + 跨 topic ID 不可比 |
| 3 | retryCount 3 次重试 + failed | 无重试；摘要缺失一次判定进 failed/ | 原地更新违反"消息不可变"；失败场景极罕见 |
| 4 | watcher 每 5s 通知（代码未退出，注释与实现矛盾） | state 去重，仅 count 增加时通知一次 | 修复通知风暴 |
| 5 | compact 独立 skill | 并入 clear --compact | 降低 skill 数量 |
| 6 | 通知只到人（osascript） | claude hooks 全自动注入 + 指令驱动 + watcher 兜底 | 达成"自动接收消费"目标 |
| 7 | queue 无界堆积 | TTL 7 天警告（不自动删） | 陈旧消息可见性 |
| 8 | 旧黑板需 start 才有 topics/ | produce 按需 mkdir，存量黑板零迁移 | 平滑升级 |
