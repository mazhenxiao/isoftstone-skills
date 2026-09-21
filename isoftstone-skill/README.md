# isoftstone

isoftstone 团队插件。当前包含 skill：`isoftstone-debug-recovery`（调用名 `isoftstone:isoftstone-debug-recovery`），后续团队 skill 可继续加入本插件的 `skills/` 目录。

## isoftstone-debug-recovery

Bug 修复编排工作流 skill：以 `debugging-and-error-recovery` 做根因分析，方案经用户确认后修复，再经 `requesting-code-review` 审查修改准确性与范围。自动区分前端 / 后端 / 双端问题；双端问题派发前后端独立 subagent 串行执行（接口变更先后端再前端），内置 TaskList 跟踪状态、`.debug-recovery/` 文件黑板做后端→前端交接。

## 安装

```bash
/plugin marketplace update isoftstone-skills
/plugin install isoftstone@isoftstone-skills
```

## 用法

```
/isoftstone:isoftstone-debug-recovery <问题描述> [前端代码路径] [后端代码路径]
```

或直接说"帮我修个 bug：……"自动触发（自然语言触发不受插件命名空间影响）。

## 与 share-task 的关系

互不冲突，可同时启用：

| | share-task | isoftstone-debug-recovery |
|---|---|---|
| 定位 | 跨 AI CLI 平台的任务共享（跨会话/跨工具投递消息与上下文） | 单会话内的 bug 修复编排（分析→确认→修复→审查） |
| 黑板 | share-task 自己的共享黑板文件 | 会话工作区本地 `.debug-recovery/<slug>/blackboard.md` + 内置 TaskList |

二者数据、状态、触发互不影响；如需把 bug 修复任务跨会话/跨人交接，可先用本 skill 完成修复，再用 share-task 投递摘要。
