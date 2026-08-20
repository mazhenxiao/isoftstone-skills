# 跨平台接入协议（OpenCode / QoderCLI）

> 适用对象：OpenCode（平台标识 `oc`）、QoderCLI（平台标识 `qodercli`）——没有 hook 机制、由"指令驱动"的 AI CLI 平台。
> 对应设计：`docs/2026-08-20-push-mode-v2-design.md` §六 感知触发层。
> claude 平台**不需要**本文档：执行 `bash install.sh hooks` 即全自动注册（见 install.sh）。

本文档定义两件事：

1. **消费协议**：如何接收 claude 等其他平台推送的任务摘要（一段指令模板，贴进全局指令文件即可）
2. **写入协议**：如何向黑板写入摘要并投递通知（`share-task:set` 的等价 bash 步骤）

两个方向与 claude 侧共用同一套脚本（`scripts/consume.sh` / `scripts/produce.sh`），逻辑只写一遍，平台差异只体现在触发方式。

## 〇、前置约定

| 项 | 值 |
|---|---|
| 插件源码仓 `<PLUGIN_ROOT>` | `/Users/issuser/work/个人积累/isoftstone-skills/share-task-skill`（路径含中文，bash 中必须用单引号包裹） |
| 黑板路径 | 读 `<PLUGIN_ROOT>/skills/start/config.json` 的 `blackboard` 字段（consume.sh 自动读取；也可 `--blackboard` 显式传入） |
| 运行依赖 | bash + node（JSON 操作统一用 node，不依赖 jq） |
| 平台标识 | `claude` / `oc` / `qodercli`（与黑板 `report.oc` 等既有用法一致） |

## 一、黑板结构与地址格式

```
{blackboard}/
├── index.json                          # 注册表：tasks.{token}.{platform} → status/logs/created/updated
├── topics/                             # 消息队列（投递契约层）
│   └── {token}.{platform}/             # platform = 消费方（收件人）平台
│       ├── queue/                      # 待消费消息 000000001.json ...
│       ├── done/                       # 已消费
│       └── failed/                     # 无法消费的消息（如摘要缺失），无重试
└── {token}/{platform}/                 # 摘要区（platform = 写入方）
    └── YYYY-MM-DD-HHmmss.md            # 摘要文件
```

**地址格式 `{token}.{platform}`**，三处统一：

| 场合 | 写法 | 示例（token=report） |
|---|---|---|
| 命令参数 | `{token}.{platform}` | `get report.claude`（读 claude 写的摘要，platform = 写入方） |
| 摘要路径 | `{token}/{platform}/` | `report/oc/`（oc 写入的摘要） |
| 消息 topic | `topics/{token}.{platform}/` | `topics/report.claude/`（claude 消费的队列） |

注意两处 platform 语义相反：**摘要区**的 platform 是写入方；**topics 队列**的 platform 是收件人（消费方）。因此消费方限定单个 topic 时，address 后缀是**自己的平台**，如 oc 消费 report：`report.oc`。

## 二、消息格式

`topics/{token}.{recipient}/queue/{id:09d}.json`，扁平 JSON：

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

字段表：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | number | topic 内单调递增；文件名 9 位零填充（`000000001.json`），仅作 topic 内文件名排序键 |
| `topic` | string | 消息主题，格式 `{token}.{recipient}` |
| `token` | string | 任务口令 |
| `source` | string | 写入方平台标识（如 `oc`） |
| `recipient` | string | 收件人平台标识（= topic 目录后缀，如 `claude`） |
| `action` | string | 动作类型，当前为 `set` |
| `summaryFile` | string | 摘要文件路径，相对 blackboard |
| `timestamp` | string | ISO8601 本地时区；消费时跨 topic 统一排序键 |

队列生命周期与不变式：

- 消息文件**写入后不可变**（无原地更新）
- 消费成功 `queue → done`；摘要缺失等一次判定 `queue → failed`，无重试计数
- 滞留超过 7 天的消息，消费时块头附加"建议确认时效"警告（不自动删除）

## 三、消费协议（接收摘要）

### consume.sh 接口

```
用法: consume.sh [--auto] [--all] [--list] [--blackboard <path>] [--platform <id>] [address]

--auto       队列空 → 无输出 exit 0；非空 → 消费（上限 3 条）【指令模板用】
--all        取消 3 条上限
--list       只列出待消费数，不消费
--blackboard 黑板路径，缺省读 config.json
--platform   本平台身份（oc / qodercli），缺省读 config.json 的 platform 字段
address      可选，{token}.{platform} 限定单个 topic（后缀为本平台自己）
```

`--auto` 模式下 stdout 即注入内容（队列空时无输出、不干扰会话），格式：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
来自 {source} 的任务摘要 | {token}.{source} | {timestamp}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{摘要文件全文}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
以上摘要已注入上下文，请在后续思考和对话中参考此内容。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 指令模板（贴进全局指令文件）

**OpenCode** → 追加到 `~/.config/opencode/AGENTS.md`：

```markdown
## share-task 跨平台上下文

每次会话开始时及每个任务开始前，执行：
bash '/Users/issuser/work/个人积累/isoftstone-skills/share-task-skill/scripts/consume.sh' --auto --platform oc
若输出包含摘要块，将其作为任务上下文参与后续推理，然后继续原任务。
写入摘要时遵循 /Users/issuser/work/个人积累/isoftstone-skills/share-task-skill/references/cross-platform-protocol.md 的写入协议（生成摘要 + 调 produce.sh）。
```

**QoderCLI** → 追加到其全局指令文件（同上，仅把 `--platform oc` 换成 `--platform qodercli`）：

```markdown
## share-task 跨平台上下文

每次会话开始时及每个任务开始前，执行：
bash '/Users/issuser/work/个人积累/isoftstone-skills/share-task-skill/scripts/consume.sh' --auto --platform qodercli
若输出包含摘要块，将其作为任务上下文参与后续推理，然后继续原任务。
写入摘要时遵循 /Users/issuser/work/个人积累/isoftstone-skills/share-task-skill/references/cross-platform-protocol.md 的写入协议（生成摘要 + 调 produce.sh）。
```

说明：

- 指令驱动平台无法被文件事件唤醒，消费时机 = 会话开始 / 任务开始（脚本为毫秒级文件操作，无超时风险）
- 默认消费发往本平台的所有 topic（按 timestamp 排序）；只需消费单个口令时在命令末尾加 address（后缀为本平台），如 `... --auto --platform oc report.oc`

## 四、写入协议（set 等价 bash 步骤）

适用于 opencode/qodercli 会话需要向黑板提交摘要、让 claude 等对端自动接收的场景。等价于 claude 侧 `share-task:set` 的 Phase 3-5 + produce 投递。

前置变量：

```bash
PLUGIN_ROOT='/Users/issuser/work/个人积累/isoftstone-skills/share-task-skill'
BLACKBOARD='<黑板绝对路径>'              # 读 $PLUGIN_ROOT/skills/start/config.json 的 blackboard 字段
TOKEN='report'                           # 任务口令
PLATFORM='oc'                            # 本平台标识（写入方 = 自己；qodercli 则为 qodercli）
TS="$(date +%Y-%m-%d-%H%M%S)"            # 摘要文件名时间戳：YYYY-MM-DD-HHmmss
NOW="$(date +%Y-%m-%dT%H:%M:%S%z)"       # ISO8601（index.json 时间字段）
```

**Step 1 — 生成摘要**：基于当前会话上下文生成 500-1000 字结构化摘要，遵循 `<PLUGIN_ROOT>/references/log-template.md` 模板（任务描述 / 关键决策 / 代码变更 / 结论结果 / 遗留问题），不记录与当前任务无关的上下文。

**Step 2 — 写入摘要文件**：

```bash
mkdir -p "${BLACKBOARD}/${TOKEN}/${PLATFORM}"
cat > "${BLACKBOARD}/${TOKEN}/${PLATFORM}/${TS}.md" <<'EOF'
<遵循 log-template.md 的结构化摘要正文>
EOF
```

**Step 3 — 更新 index.json**（node 操作 `tasks.{token}.{platform}` 的 status/logs/updated，首次写入时补 created）：

```bash
BLACKBOARD="${BLACKBOARD}" TOKEN="${TOKEN}" PLATFORM="${PLATFORM}" TS="${TS}" NOW="${NOW}" node -e '
  const fs = require("fs");
  const p = process.env.BLACKBOARD + "/index.json";
  const data = JSON.parse(fs.readFileSync(p, "utf8"));
  data.tasks = data.tasks || {};
  data.tasks[process.env.TOKEN] = data.tasks[process.env.TOKEN] || {};
  const slot = data.tasks[process.env.TOKEN][process.env.PLATFORM] || {};
  slot.status = "set";
  slot.logs = [process.env.TS + ".md"];
  slot.created = slot.created || process.env.NOW;
  slot.updated = process.env.NOW;
  data.tasks[process.env.TOKEN][process.env.PLATFORM] = slot;
  fs.writeFileSync(p, JSON.stringify(data, null, 2) + "\n");
'
```

（可选：需原子写入防中断时，把最终 JSON 内容传给 `<PLUGIN_ROOT>/scripts/sync-index.sh "{blackboard}" "{json内容}"`。）

**Step 4 — 投递通知**（best-effort，失败仅警告、不回滚摘要写入，pull 模式保底）：

```bash
bash "${PLUGIN_ROOT}/scripts/produce.sh" "${BLACKBOARD}" "${TOKEN}" "${PLATFORM}" "${TOKEN}/${PLATFORM}/${TS}.md"
```

produce.sh 行为：

- 收件人 = `index.json` 中 `tasks.{token}` 的平台 keys **减去** source 自身（注册即订阅，无需指定收件人）
- 对每个收件人：写 `topics/{token}.{recipient}/queue/{id:09d}.json`（tmp+mv 原子写、防覆盖取号）
- 每个收件人输出一行 `已投递 → topics/{topic}/queue/{id}.json`；无收件人时 stderr 提示"仅写入摘要未投递"，退出码仍为 0
- 对端只要在 `tasks.{token}` 下拥有自己的平台 key 即视为已注册（执行一次本写入协议即自动注册）

补充：

- 复用上次 token+platform（update 语义）时，Step 2 后可删除同目录旧摘要、仅保留最新：
  `(cd "${BLACKBOARD}/${TOKEN}/${PLATFORM}" && ls -t *.md | tail -n +2 | xargs rm -f)`
- 对端（claude）由 hooks 自动消费，无需任何额外操作

## 五、端到端时序示例

```
claude 侧执行 set（report.claude）
  1. 写 {blackboard}/report/claude/2026-08-20-101530.md
  2. 更新 index.json 的 tasks.report.claude
  3. produce.sh → topics/report.oc/queue/000000001.json（oc 已注册为收件人）

oc 侧会话开始 / 任务开始（指令模板触发）
  4. consume.sh --auto --platform oc
  5. 读消息 → 读 summaryFile → stdout 输出摘要块 → AI 作为上下文参与推理
  6. 消息 mv queue → done

oc 侧执行 §四写入协议（report.oc）
  7. 反向同理 → topics/report.claude/queue/…
  8. claude 侧 SessionStart/UserPromptSubmit hook 自动消费注入
```
