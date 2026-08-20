# share-task — 跨 AI CLI 平台任务共享

在同一台机器上的不同 AI CLI 工具（Claude Code、OpenCode、QoderCLI 等）之间共享任务上下文与会话摘要。

**解决的痛点**：在 Claude Code 里干了半天的任务，想换到 OpenCode 继续，上下文全丢。share-task 通过一块文件级"共享黑板"，让任意一端把会话摘要**自动推送**到其他端，其他端**自动接收并注入上下文**，无缝接力。

- 零服务、零第三方依赖：bash + node，文件即协议
- 双模式：push（自动投递 + 自动消费，主推）与 pull（手动拉取，保底）
- 消息带原子写入与并发保护，多会话同时消费安全

## 一、两种工作模式

| 模式 | 链路 | 用法 |
|---|---|---|
| **push（主推）** | A 平台 `set` → 写摘要 + 自动投递消息 → B 平台 hook/指令自动消费 → 摘要自动注入 B 的上下文 | B 端零操作 |
| **pull（保底）** | A 平台 `set` 写摘要 → B 平台 `get` 手动读取注入 | 永远可用，不受队列状态影响 |

**物理边界（诚实声明）**：AI 会话无法被文件事件远程唤醒。push 模式的"自动"指：

- 对端会话**运行中** → 下一轮用户输入时经 hook 自动感知并消费（人无感）
- 对端会话**未运行** → 下次会话启动时（SessionStart）自动感知并消费

## 二、安装

### 2.1 Claude Code（安装插件）

```text
# 1. 注册 marketplace
/plugin marketplace add mazhenxiao/isoftstone-skills

# 2. 安装插件
/plugin install share-task@isoftstone-skills
```

重启 Claude Code 后，`/share-task:start` 等 5 个命令可用。

### 2.2 Claude Code（启用自动消费 hooks —— push 模式的关键）

只装插件不装 hooks，claude 侧仍可手动 `/share-task:consume`；装了 hooks 才是全自动。两种方式任选：

**方式 A：源码仓方式（推荐，hook 路径稳定）**

```bash
git clone https://github.com/mazhenxiao/isoftstone-skills ~/skills/isoftstone-skills
bash ~/skills/isoftstone-skills/share-task-skill/install.sh hooks
```

`install.sh hooks` 会向 `~/.claude/settings.json` 幂等注册 SessionStart + UserPromptSubmit 两个 hook（重复执行安全，只增不删）。hook 指向 clone 出来的稳定路径，插件升级不影响。

**方式 B：手动注册（不 clone 仓库）**

编辑 `~/.claude/settings.json`，将 `<PLUGIN_ROOT>` 替换为插件实际路径（marketplace 安装后在 `~/.claude/plugins/cache/isoftstone-skills/share-task/<版本>/`，注意升级后版本号变化需同步更新），合并以下配置：

```json
"hooks": {
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": "bash '<PLUGIN_ROOT>/scripts/consume.sh' --auto --platform claude" }] }
  ],
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "bash '<PLUGIN_ROOT>/scripts/consume.sh' --auto --platform claude" }] }
  ]
}
```

**验证**：重启 Claude Code 后执行——

```bash
bash '<PLUGIN_ROOT>/scripts/consume.sh' --auto --platform claude
```

队列空时无输出、退出码 0 即正常。之后每次会话启动、每轮用户输入前都会自动检查一次（毫秒级文件操作，无感）。

### 2.3 OpenCode（指令驱动）

OpenCode 没有 hook 机制，靠全局指令文件驱动。把下面的模板追加到 `~/.config/opencode/AGENTS.md`（`<PLUGIN_ROOT>` 替换为插件实际路径；本机源码仓或 clone 均可）：

```markdown
## share-task 跨平台上下文

每次会话开始时及每个任务开始前，执行：
bash '<PLUGIN_ROOT>/scripts/consume.sh' --auto --platform oc
若输出包含摘要块，将其作为任务上下文参与后续推理，然后继续原任务。
写入摘要时遵循 <PLUGIN_ROOT>/references/cross-platform-protocol.md 的写入协议（生成摘要 + 调 produce.sh）。
```

### 2.4 QoderCLI

同 OpenCode，把上面的模板贴进 QoderCLI 的全局指令文件，仅将 `--platform oc` 换成 `--platform qodercli`。

### 2.5 依赖

| 依赖 | 用途 |
|---|---|
| bash | 全部脚本 |
| node | JSON 读写（produce / consume / hooks 注册，不依赖 jq） |
| macOS（可选） | 仅 watcher.sh 的系统通知用到 osascript，缺失时降级为日志行 |

**平台标识约定**：`claude` / `oc` / `qodercli`（自定义平台名亦可，不含点号即可）。

## 三、5 分钟上手（claude ↔ oc 双向）

场景：Claude Code 与 OpenCode 协作同一任务，口令定为 `report`。

> 前提：claude 已装插件 + hooks（§2.2）；oc 已贴指令模板（§2.3）。

### 第 1 步：claude 侧注册

Claude Code 会话中：

```text
/share-task:start report.claude
```

首次运行会提示输入黑板目录的绝对路径（如 `~/work/share-tasks`）——**所有平台必须共用同一块黑板**。预期输出：

```text
黑板已配置 — 路径: ~/work/share-tasks
本平台身份已注册 — 口令: report, 平台: claude
```

### 第 2 步：oc 侧注册（通过首次写入）

OpenCode 会话中，对 AI 说：

> 把当前任务摘要写入 share-task 黑板，口令 report，平台 oc

AI 按 AGENTS.md 指令执行写入协议：生成摘要 → 写 `{blackboard}/report/oc/<时间戳>.md` → 更新 index.json（**这一步同时完成了 oc 的注册**）→ 自动投递一条消息到 `topics/report.claude/queue/`。

### 第 3 步：claude 自动接收

在 Claude Code 输入任意消息（或新开 会话）时，hook 自动消费，上下文里出现：

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
来自 oc 的任务摘要 | report.oc | 2026-08-20T10:15:30+08:00
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
（摘要全文）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
以上摘要已注入上下文，请在后续思考和对话中参考此内容。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 第 4 步：claude 侧回投

```text
/share-task:set
```

免参调用自动沿用上次的 `report.claude`：生成当前会话摘要写入黑板，并投递到 `topics/report.oc/queue/`（oc 已注册，见第 2 步）。输出确认：

```text
摘要已写入 — 位置: {blackboard}/report/claude/<时间戳>.md, 状态: set
消息已投递 → topics/report.oc/queue/000000001.json
```

### 第 5 步：闭环

oc 下次会话/任务开始时自动消费注入；之后再循环第 4 步或反向写入。任一时刻都可 `get` 手动拉取对端最新摘要作保底。

> **关键规则：注册即订阅。** `set` 只向 index.json 中已注册（`tasks.{token}` 下有平台条目）的对端投递。双方都完成注册（各自的第 1/2 步）之后，推送链路才通；此前 `set` 会提示"无对端平台注册，仅写入摘要未投递"。

## 四、命令手册

### 4.1 参数格式：点号地址

四个带地址的命令统一支持 `{token}.{platform}` 写法（推荐），并兼容旧的两参数写法：

| 输入 | 解析 |
|---|---|
| 1 个参数且含点号 | 按最后一个点拆分：token = 前段，platform = 后段（platform 不含点号） |
| 2 个参数 | 旧格式：token = $1，platform = $2 |
| 0 个参数 | set/get 走 lastToken/lastPlatform 免参回落；clear 进入全量清除；start 提示输入 |

示例：`/share-task:set report.claude` 等价于 `/share-task:set report claude`。

### 4.2 命令速查

| 命令 | 作用 | 示例 |
|---|---|---|
| `/share-task:start` | 配置黑板路径 + 注册本平台身份（首次或变更时） | `/share-task:start report.claude` |
| `/share-task:set` | 生成会话摘要写入黑板 + 自动投递对端 | `/share-task:set`（免参） |
| `/share-task:get` | 手动拉取指定平台的最新摘要（pull 模式） | `/share-task:get report.oc` |
| `/share-task:consume` | 手动消费推送给本平台的消息（push 补充/排查） | `/share-task:consume` |
| `/share-task:clear` | 清除任务数据与消息队列 | `/share-task:clear report.oc` |

### 4.3 各命令要点

**start** — 配置黑板路径（交互确认，写入 config.json），并注册 `tasks.{token}.{platform}` 条目（status: pending）。点号后缀即**自己**：`start report.oc` 表示"我是 oc"。重复 start 幂等：条目已存在只更新时间，不重置状态。

**set** — 按 `references/log-template.md` 模板生成 500-1000 字结构化摘要（任务描述/关键决策/代码变更/结论/遗留问题），写入 `{blackboard}/{token}/{platform}/`，随后 best-effort 投递。护栏：最终确定的 platform 与 config.json 中本平台身份不一致时会要求确认，防止误写他人摘要槽位。

**get** — 读 `{token}/{platform}` 下最新一篇摘要注入上下文（这里的 platform 是**写入方**）。状态为 pending 时提示对端尚未提交。

**consume** — 消费 `topics/*.{本平台}/queue/` 中投给本平台的消息。claude 侧正常由 hooks 自动完成，此命令用于手动补消费与排查。单次上限 3 条，剩余提示"下轮自动继续"。

**clear** — 三种模式：
- `/share-task:clear report.oc`：删除该条目摘要 + index 记录 + 对应 topic 队列整目录
- `/share-task:clear`：清空黑板全部任务（含 topics/，保留 index.json 骨架），需二次确认
- `/share-task:clear --compact`：仅清理各 topic 的 done/、failed/ 归档，**不动 queue**

## 五、工作原理

### 5.1 三层架构

```text
┌─ 感知触发层（每平台一个触发器）─────────────────────────┐
│ claude:    SessionStart + UserPromptSubmit hooks（全自动） │
│ oc/qodercli: AGENTS.md / 全局指令，会话/任务开始时执行     │
│ watcher.sh（可选兜底）→ macOS 系统通知，面向人             │
└──────────────────┬────────────────────────────┘
                   ↓ 调用（stdout 即注入内容）
┌─ 共享逻辑层（bash + node 脚本，唯一实现）────────────────┐
│ scripts/produce.sh   投递（收件人自动推导）                │
│ scripts/consume.sh   消费：读队列→读摘要→归档→格式化输出  │
│ scripts/watcher.sh   轮询通知（state 去重防通知风暴）      │
└──────────────────┬────────────────────────────┘
                   ↓ 读写
┌─ 投递契约层（平台中立的文件结构）────────────────────────┐
│ {blackboard}/topics/{token}.{platform}/queue|done|failed  │
└─────────────────────────────────────────────────────────┘
```

逻辑只写一遍（脚本层），平台差异只体现在触发方式；消费脚本的 stdout 就是注入内容——claude 的 hook 直接注入上下文，oc/qodercli 由 AI 执行脚本后把 stdout 当上下文。

### 5.2 黑板结构

```text
{blackboard}/
├── index.json                      # 注册表：tasks.{token}.{platform} → status/logs/created/updated
├── {token}/
│   └── {platform}/                 # 摘要区（platform = 写入方）
│       └── YYYY-MM-DD-HHmmss.md    # 会话摘要文件
└── topics/                         # 消息队列（push 模式）
    └── {token}.{platform}/         # platform = 收件人
        ├── queue/                  # 待消费消息 000000001.json ...
        ├── done/                   # 已消费归档
        └── failed/                 # 无法消费归档（如摘要缺失）
```

### 5.3 消息格式

`topics/{token}.{recipient}/queue/{id:09d}.json`，扁平 JSON：

```json
{
  "id": 1,
  "topic": "report.oc",
  "token": "report",
  "source": "claude",
  "recipient": "oc",
  "action": "set",
  "summaryFile": "report/claude/2026-08-20-101530.md",
  "timestamp": "2026-08-20T10:15:30+08:00"
}
```

### 5.4 关键语义（易错点）

**platform 双语义**——两处 platform 含义相反，命令里统一用"自己"的视角理解即可：

| 场合 | platform 含义 | 示例（token=report） |
|---|---|---|
| 摘要路径 `{token}/{platform}/` | **写入方** | `report/oc/` = oc 写的摘要 |
| 消息 topic `topics/{token}.{platform}/` | **收件人** | `topics/report.oc/` = oc 消费的队列 |

因此：`set report.oc` 由 oc 自己执行；`get report.oc` 是读 oc 写的（claude 执行）；oc 消费时限定 topic 的地址 `report.oc` 后缀也是自己。

**注册即订阅**——`set` 的收件人 = index.json 中 `tasks.{token}` 的平台 keys 减去自己，无需参数指定。多端注册（如 claude + oc + qodercli）则一次 `set` 向每个对端各投一条。

**可靠性语义**：

- 消息文件**写入后不可变**；tmp + mv 原子写，防覆盖取号（并发竞态兜底）
- 多会话并发消费安全：mv 原子性保证唯一赢家，输家静默跳过
- **无重试**：摘要文件缺失 → 一次判定归档 `failed/` 并输出说明，不中断其余消息
- 消息滞留超过 **7 天**：消费时块头附加"建议确认时效"警告（不自动删除）
- 单轮消费上限 **3 条**（`consume.sh --all` 取消），未消费完下轮自动继续
- produce 为 best-effort：失败仅警告不中断 set，pull 模式（get）永远保底

## 六、运维与排查 FAQ

**Q1：`set` 之后对端没收到？**
看 set 输出。若为"无对端平台注册，仅写入摘要未投递"——对端还没注册（claude 端未 start / oc 端未执行过写入协议）。注册即订阅：补注册后，**下一次** set 才会投递。

**Q2：claude 侧没有自动注入？**
依次检查：`~/.claude/settings.json` 是否有 SessionStart/UserPromptSubmit hook（§2.2）；注册后是否**重启过** Claude Code；`bash '<PLUGIN_ROOT>/scripts/consume.sh' --list` 看队列里是否有待消费消息；都没有就手动 `/share-task:consume` 补一次。

**Q3：想看队列里积压了多少消息？**

```bash
bash '<PLUGIN_ROOT>/scripts/consume.sh' --list
```

**Q4：done/failed 归档越攒越多？**

```text
/share-task:clear --compact
```

只清归档、不动 queue，安全。

**Q5：人不在任何 AI 会话里，也想被提醒有新消息？**

```bash
bash '<PLUGIN_ROOT>/scripts/watcher.sh' <blackboard绝对路径> claude [间隔秒数，默认5]
```

轮询待消费数，仅数量**增加**时发一次 macOS 通知（state 去重，防通知风暴）。默认不常驻，按需手动启动，Ctrl+C 停止。

**Q6：换了一台机器/目录，配置在哪？**
黑板路径与本平台身份存于 `<PLUGIN_ROOT>/skills/start/config.json`；任务注册表在 `{blackboard}/index.json`。重新 `/share-task:start` 即可重配。

**Q7：路径含中文，脚本报错？**
bash 中引用路径必须用**单引号**包裹：`bash '<PLUGIN_ROOT>/scripts/consume.sh' ...`。

**Q8：推送链路整体不可用，任务等不了？**
pull 模式保底：对端任何时候可 `/share-task:get {token}.{platform}` 直接读摘要，与队列状态无关。

## 七、附录

### 7.1 插件目录结构

```text
share-task-skill/
├── install.sh                    # 安装脚本：install / uninstall / hooks
├── package.json
├── .claude-plugin/plugin.json
├── skills/
│   ├── start/    SKILL.md + config.json（黑板路径与本平台身份落盘处）
│   ├── set/      SKILL.md
│   ├── get/      SKILL.md
│   ├── consume/  SKILL.md
│   └── clear/    SKILL.md
├── scripts/
│   ├── produce.sh     # 投递：index 推导收件人 → 原子写 queue
│   ├── consume.sh     # 消费：--auto/--all/--list，stdout 即注入内容
│   ├── watcher.sh     # 可选轮询通知
│   └── sync-index.sh  # index.json 原子写入
├── references/
│   ├── log-template.md            # 摘要模板（set 遵循）
│   └── cross-platform-protocol.md # oc/qodercli 完整接入协议
└── docs/
    └── 2026-08-20-push-mode-v2-design.md   # v2 设计决策与取舍
```

### 7.2 脚本接口一览

```text
install.sh  [install|uninstall|hooks]                    # 安装/卸载/注册自动消费 hooks（均幂等）
produce.sh  <blackboard> <token> <source平台> <摘要相对路径>   # 投递（一般不直接调用）
consume.sh  [--auto] [--all] [--list] [--blackboard <path>] [--platform <id>] [address]
watcher.sh  <blackboard> <platform> [interval=5]         # 可选：轮询通知
sync-index.sh <blackboard> <json内容>                    # index.json 原子写入（内部使用）
```

### 7.3 深入阅读

- `docs/2026-08-20-push-mode-v2-design.md` — push 模式 v2 设计：三层架构、消息不可变、与初版方案的 8 处差异及理由
- `references/cross-platform-protocol.md` — OpenCode/QoderCLI 完整接入协议（消费指令模板 + 写入协议 bash 步骤 + 端到端时序）
