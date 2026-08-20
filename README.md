# isoftstone-skills

iSoftStone 共享 Skills 合集，跨 AI CLI 平台使用。

## 安装（Claude Code）

```bash
# 1. 注册 marketplace
/plugin marketplace add mazhenxiao/isoftstone-skills

# 2. 安装插件
/plugin install share-task@isoftstone-skills
```

也可 clone 本仓库后直接使用：`bash share-task-skill/install.sh install`。

## 插件列表

### share-task

跨 AI CLI 平台的任务共享工具。通过文件级黑板，在同一机器上的不同 AI 工具（Claude Code、OpenCode、QoderCLI 等）之间共享任务上下文和会话摘要。

- **push 模式（主推）**：`set` 写摘要后自动投递，对端经 hooks/指令**自动接收并注入上下文**，无需任何操作
- **pull 模式（保底）**：`get` 手动拉取对端摘要，永远可用

| 命令 | 作用 |
|---|---|
| `/share-task:start` | 配置黑板路径 + 注册本平台身份 |
| `/share-task:set` | 生成会话摘要写入黑板，并自动投递对端 |
| `/share-task:get` | 读取其他平台的摘要，注入当前上下文 |
| `/share-task:consume` | 消费推送消息（claude 侧通常由 hooks 自动完成） |
| `/share-task:clear` | 清除指定任务、全部任务或压缩队列归档（`--compact`） |

#### 快速开始

```bash
# 在 Claude Code 中初始化任务（点号后缀即本平台）
/share-task:start report.claude

# 完成阶段性工作后，提交摘要（自动投递给已注册的对端平台）
/share-task:set

# 切换到 OpenCode（已按教程接入），下一轮会话自动收到注入的摘要；
# 也可在任何平台手动拉取
/share-task:get report.oc
```

**完整教程**（安装细节、hooks 注册、OpenCode/QoderCLI 接入、工作原理、排查 FAQ）：见 [share-task-skill/README.md](share-task-skill/README.md)。

## 依赖

bash + node（JSON 操作，不依赖 jq）。无其他第三方依赖，仅需文件读写权限。
