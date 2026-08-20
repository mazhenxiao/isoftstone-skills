#!/usr/bin/env bash
# produce.sh — 消息投递：从 index.json 注册表推导收件人，向每个对端 topic 原子写入一条消息
# 用法：produce.sh <blackboard> <token> <source-platform> <summaryFile-rel>
# 示例：produce.sh /path/to/blackboard report oc report/oc/2026-08-20-101530.md
# 说明：
#   - 收件人 = index.json 中 tasks.{token} 的平台 keys − source（注册即订阅）
#   - 无对端注册 → 仅提示不投递（stderr），退出码仍为 0
#   - 消息文件写入后不可变；ID 为 9 位零填充，防覆盖取号（跨 queue/done/failed 取 maxId）
#   - JSON 读写用 node -e（与 install.sh 先例一致），不依赖 jq

set -euo pipefail

usage() {
  cat <<'EOF'
用法: produce.sh <blackboard> <token> <source-platform> <summaryFile-rel>

参数:
  blackboard      黑板根目录（绝对路径）
  token           口令（如 report）
  source-platform 写入方平台（即自身，如 oc）
  summaryFile-rel 摘要文件路径（相对 blackboard）

示例:
  produce.sh /path/to/blackboard report oc report/oc/2026-08-20-101530.md
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 4 ]]; then
    usage >&2
    exit 1
fi

BLACKBOARD="$1"
TOKEN="$2"
SOURCE="$3"
SUMMARY_FILE="$4"

command -v node >/dev/null 2>&1 || {
    echo "ERROR: 未找到 node，produce 依赖 node 处理 JSON" >&2
    exit 1
}

# 时间戳：本地时区 ISO8601
TIMESTAMP="$(date +%Y-%m-%dT%H:%M:%S%z)"

# 读注册表 → 推导收件人 → 逐个投递（防覆盖取号 + tmp/mv 原子写）
# node 失败（如 index.json 缺失/损坏）→ set -e 以退出码 1 中断
OUTPUT="$(node -e '
    const fs = require("fs");
    const pathLib = require("path");

    const [blackboard, token, source, summaryFile, timestamp] = process.argv.slice(1);

    // 1. 读 index.json，推导收件人 = tasks.{token} 的平台 keys − source
    let platforms;
    try {
        const index = JSON.parse(fs.readFileSync(pathLib.join(blackboard, "index.json"), "utf8"));
        platforms = Object.keys((index.tasks && index.tasks[token]) || {});
    } catch (e) {
        console.error("ERROR: 读取 index.json 失败: " + e.message);
        process.exit(1);
    }
    const recipients = platforms.filter((p) => p !== source);

    const SUBS = ["queue", "done", "failed"];
    const pad = (n) => String(n).padStart(9, "0");

    for (const recipient of recipients) {
        const topic = token + "." + recipient;
        const topicDir = pathLib.join(blackboard, "topics", topic);

        // 2. 建目录（幂等，存量黑板零迁移）
        for (const sub of SUBS) {
            fs.mkdirSync(pathLib.join(topicDir, sub), { recursive: true });
        }

        // 3. 防覆盖取号：跨 queue/done/failed 取 maxId；+1 后目标已存在则继续 +1（并发竞态兜底）
        let maxId = 0;
        for (const sub of SUBS) {
            for (const f of fs.readdirSync(pathLib.join(topicDir, sub))) {
                const m = /^(\d{9})\.json$/.exec(f);
                if (m) maxId = Math.max(maxId, parseInt(m[1], 10));
            }
        }
        const exists = (n) =>
            SUBS.some((sub) => fs.existsSync(pathLib.join(topicDir, sub, pad(n) + ".json")));
        let id = maxId + 1;
        while (exists(id)) id += 1;

        // 4. 构造消息（写入后不可变）+ tmp/mv 原子写入
        const msg = {
            id: id,
            topic: topic,
            token: token,
            source: source,
            recipient: recipient,
            action: "set",
            summaryFile: summaryFile,
            timestamp: timestamp
        };
        const queueDir = pathLib.join(topicDir, "queue");
        const tmp = pathLib.join(queueDir, ".tmp." + process.pid + "." + Date.now());
        fs.writeFileSync(tmp, JSON.stringify(msg, null, 2) + "\n");
        fs.renameSync(tmp, pathLib.join(queueDir, pad(id) + ".json"));

        console.log("已投递 → topics/" + topic + "/queue/" + pad(id) + ".json");
    }
' "$BLACKBOARD" "$TOKEN" "$SOURCE" "$SUMMARY_FILE" "$TIMESTAMP")"

# 输出：每个 recipient 一行；recipients 为空 → stderr 提示（退出码 0，pull 模式保底）
if [[ -n "$OUTPUT" ]]; then
    printf '%s\n' "$OUTPUT"
else
    echo "无对端平台注册，仅写入摘要未投递（对端可先执行 start 注册）" >&2
fi
exit 0
