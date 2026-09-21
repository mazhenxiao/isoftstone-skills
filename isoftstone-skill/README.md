# isoftstone

isoftstone 团队插件。当前包含 skill：`isoftstone-debug-recovery`（调用名 `isoftstone:isoftstone-debug-recovery`），后续团队 skill 可继续加入本插件的 `skills/` 目录。

## 安装

```bash
/plugin marketplace update isoftstone-skills
/plugin install isoftstone@isoftstone-skills
```

依赖：Claude Code，且已安装 `agent-skills` 插件（提供 debugging-and-error-recovery）与 `superpowers` 插件（提供 requesting-code-review）。

---

# isoftstone-debug-recovery 基础教程

Bug 修复编排工作流：以 `debugging-and-error-recovery` 做根因分析 → **方案经你确认后**才修改 → 修改后由 `requesting-code-review` 独立审查（是否解决问题、是否超出范围、是否符合仓库规范）。自动区分前端 / 后端 / 双端问题；双端问题派发前后端独立 subagent 串行执行（接口变更先后端再前端），TaskList 跟踪状态、文件黑板做后端→前端交接。

## 1. 调用格式

```
/isoftstone:isoftstone-debug-recovery <问题描述> [前端代码路径] [后端代码路径]
```

也可以不敲命令，直接说"帮我修个 bug：……""排查一下这个问题：……"，命中触发词自动进入本流程。

## 2. 参数说明

| 参数 | 必填 | 格式 | 说明 |
|------|------|------|------|
| 问题描述 | 是 | 自由文本 | 说了什么现象、什么报错、怎么复现 |
| 前端代码路径 | 否 | 绝对路径（`/` 或 `~` 开头的真实目录） | 提供后所有前端修改在该仓库内进行，自动遵循该仓库的 CLAUDE.md 与规范 |
| 后端代码路径 | 否 | 同上 | 同上，后端侧 |

要点：

- **问题描述缺失不会瞎猜**——会停下来向你追问
- **路径不存在会报错**并要求更正，不会静默跳过
- 路径可选；不给路径时会从问题描述关键词推断问题侧（见 §4）

### 问题描述怎么写（直接影响定位速度）

建议包含四要素：**现象、报错信息、复现步骤、期望 vs 实际**。

```
较差：列表页有 bug，帮我看看
较好：订单列表页切到第 2 页时表格数据不刷新，控制台报
     "Cannot read properties of undefined (reading 'rows')"，
     复现：列表页→点分页第 2 页；期望加载第 2 页数据，实际表格停留第 1 页
```

## 3. 参数组合 → 问题类型判定

| 前端路径 | 后端路径 | 描述特征 | 判定结果 | 执行方式 |
|:---:|:---:|------|------|------|
| ✓ | ✓ | 任意（或涉及接口调用链/跨端数据流） | 双端问题 | 前后端独立 subagent，先后端再前端 |
| ✓ | ✗ | 常规前端描述 | 前端单端 | 主会话直接修 |
| ✓ | ✗ | 明显指向后端（接口返回错误等） | 反问你确认归属 | 确认后按结论执行 |
| ✗ | ✓ | 常规后端描述 | 后端单端 | 主会话直接修 |
| ✗ | ✗ | 页面/组件/渲染/样式/交互 | 推断为前端 | 开工前告诉你结论 |
| ✗ | ✗ | 接口/SQL/服务/事务/数据 | 推断为后端 | 同上 |
| ✗ | ✗ | 推不出来 | 反问你 | 不会瞎猜 |

## 4. Demo

### Demo 1：前端单端

```
/isoftstone:isoftstone-debug-recovery 订单列表页切第 2 页表格不刷新，
控制台报 undefined reading 'rows'，复现：列表页→点第 2 页；
期望加载新数据，实际停留第 1 页 ~/work/project/srm2-web
```

流程：分析（定位到分页回调丢失 rows 判空）→ 给出方案（根因/修改点/影响面）→ **你回复确认** → 修改 → code review 通过 → 汇报 + 建议验证命令。

### Demo 2：后端单端

```
/isoftstone:isoftstone-debug-recovery /api/charge/records 分页查询第 2 页
total 数量和列表对不上，疑似 count 语句没带 where 条件
~/work/project/charging-backend
```

同 Demo 1，只是执行侧为后端仓库。

### Demo 3：双端（接口字段不一致）

```
/isoftstone:isoftstone-debug-recovery 充电订单详情页支付状态显示为空：
前端取 payStatus，后端返回 pay_status，统一命名并排查详情接口
是否还有其他字段不一致 ~/work/project/srm2-web ~/work/project/charging-backend
```

双端执行编排：

1. 跨端分析后给出**联合方案**：后端改动点、接口契约变更、前端适配点、执行顺序 → 你确认
2. TaskList 自动建任务：T1 后端修改 → T2 后端 review → T3 前端修改 → T4 前端 review
3. 后端 subagent 先改并自验，写黑板交接记录（接口契约变更、修改清单、前端适配要点），review 通过后前端 subagent 才开工
4. 全部通过后汇总报告 + 建议联调验证步骤

### Demo 4：不给路径，自然语言触发

> 帮我修个 bug：登录页点登录按钮没反应

"页面/按钮/交互"命中前端关键词 → 告知"判定为前端问题" → 追问前端仓库路径后开工。推不出侧时同样会问，不会瞎猜。

## 5. 产物文件

工作目录下生成 `.debug-recovery/<问题slug>/`：

| 文件 | 内容 | 写入者 |
|------|------|--------|
| `issue.md` | 问题描述、参数、判定结论、确认后的方案 | 主会话 |
| `blackboard.md` | 双端时的后端→前端交接：状态机（backend-in-progress → backend-done → backend-done-review-passed → frontend-in-progress → done）、接口契约变更、修改文件清单、前端适配要点 | 后端 subagent / 主会话 |

黑板是前端任务的"权威依据"——前端 subagent 拿到的接口变更以黑板记录为准。

## 6. 注意事项

- 方案未经你确认，**不会改动任何代码**；拒绝方案可带反馈重新分析
- code review 连续 2 轮不通过会停下来汇报阻塞点，由你决策
- 前后端 subagent 分别在各自仓库目录工作，自动遵循各仓库 CLAUDE.md 与规范；修改范围以确认的方案为边界
- subagent 失败时黑板保留现场，询问你后再重试
- 与 share-task 互不冲突（见下），可同时启用

## 与 share-task 的关系

互不冲突，可同时启用：

| | share-task | isoftstone-debug-recovery |
|---|---|---|
| 定位 | 跨 AI CLI 平台的任务共享（跨会话/跨工具投递消息与上下文） | 单会话内的 bug 修复编排（分析→确认→修复→审查） |
| 黑板 | share-task 自己的共享黑板文件 | 会话工作区本地 `.debug-recovery/<slug>/blackboard.md` + 内置 TaskList |

二者数据、状态、触发互不影响；如需把 bug 修复结果跨会话/跨人交接，可先用本 skill 完成修复，再用 share-task 投递摘要。
