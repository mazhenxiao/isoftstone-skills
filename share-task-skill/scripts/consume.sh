#!/usr/bin/env bash
# consume.sh — 消息消费：读队列 → 读摘要 → 归档（done/failed）→ stdout 输出注入块
# 用法：consume.sh [--auto] [--all] [--list] [--blackboard <path>] [--platform <id>] [address]
# 示例：
#   consume.sh --auto --platform claude   # hooks 全自动模式：空队列完全无输出
#   consume.sh                            # 手动模式：身份缺省读 config.json
#   consume.sh --all report.claude        # 消费指定 topic 全部消息（取消 3 条上限）
#   consume.sh --list                     # 只列待消费数，不消费
# 说明：
#   - stdout 即注入内容（claude 的 hook 直接注入上下文）
#   - 跨 topic 按 JSON 内 timestamp 升序消费（不用文件名）
#   - 滞留 > 7 天 → 块头加警告行；摘要缺失 → 归档 failed/ 并输出说明，不中断其余消息
#   - mv 原子性保证多会话并发消费时唯一赢家，输家静默跳过
#   - 退出码：0 正常 / 1 错误 / 2 未配置（无 blackboard 或 platform）

set -euo pipefail

AUTO=0
ALL=0
LIST=0
BLACKBOARD=""
PLATFORM=""
ADDRESS=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${PLUGIN_ROOT}/skills/start/config.json"

usage() {
  cat <<'EOF'
用法: consume.sh [--auto] [--all] [--list] [--blackboard <path>] [--platform <id>] [address]

参数:
  --auto        空队列无输出 exit 0；非空 drain（上限 3 条）【hooks 用】
  （默认）      空队列输出 "无待消费消息"；非空 drain（上限 3 条）【手动/skill 用】
  --all         取消 3 条上限
  --list        列出匹配 topic 的待消费数，不消费，exit 0
  --blackboard  黑板根目录，缺省读 skills/start/config.json 的 blackboard
  --platform    本平台身份，缺省读 config.json 的 platform 字段（无则 exit 2）
  address       可选，{token}.{platform} 格式，限定单个 topic（platform 后缀应为调用方自己）

示例:
  consume.sh --auto --platform claude
  consume.sh
  consume.sh --all report.claude
  consume.sh --list
EOF
}

# ---- 参数解析 ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO=1 ;;
        --all)
            ALL=1 ;;
        --list)
            LIST=1 ;;
        --blackboard)
            [[ $# -ge 2 ]] || { echo "ERROR: --blackboard 需要路径参数" >&2; exit 1; }
            BLACKBOARD="$2"; shift ;;
        --platform)
            [[ $# -ge 2 ]] || { echo "ERROR: --platform 需要平台参数" >&2; exit 1; }
            PLATFORM="$2"; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --*)
            echo "ERROR: 未知选项: $1" >&2; exit 1 ;;
        *)
            if [[ -n "$ADDRESS" ]]; then
                echo "ERROR: 最多一个 address 参数" >&2; exit 1
            fi
            ADDRESS="$1" ;;
    esac
    shift
done

if [[ -n "$ADDRESS" && "$ADDRESS" != *.* ]]; then
    echo "ERROR: address 需为 {token}.{platform} 格式，如 report.claude" >&2
    exit 1
fi

command -v node >/dev/null 2>&1 || {
    echo "ERROR: 未找到 node，consume 依赖 node 处理 JSON" >&2
    exit 1
}

# ---- 身份解析：缺省读 config.json（blackboard / platform）----
if [[ -z "$BLACKBOARD" || -z "$PLATFORM" ]]; then
    CFG="$(node -e '
        const fs = require("fs");
        const f = process.argv[1];
        let out = ["", ""];
        try {
            const c = JSON.parse(fs.readFileSync(f, "utf8"));
            out = [c.blackboard || "", c.platform || ""];
        } catch (e) { /* 无配置/损坏均视为未配置 */ }
        process.stdout.write(out.join("\t"));
    ' "$CONFIG_FILE")"
    CFG_BB=""
    CFG_PLATFORM=""
    IFS=$'\t' read -r CFG_BB CFG_PLATFORM <<< "$CFG"
    if [[ -z "$BLACKBOARD" ]]; then
        BLACKBOARD="$CFG_BB"
    fi
    if [[ -z "$PLATFORM" ]]; then
        PLATFORM="$CFG_PLATFORM"
    fi
fi

if [[ -z "$BLACKBOARD" ]]; then
    echo "ERROR: 未配置 blackboard，请先执行 share-task:start（或用 --blackboard 指定）" >&2
    exit 2
fi
if [[ -z "$PLATFORM" ]]; then
    echo "ERROR: 未配置 platform，请先执行 share-task:start 注册本平台身份（或用 --platform 指定）" >&2
    exit 2
fi

# ---- 匹配 topic：默认 topics/*.{platform}，address 模式限定单目录 ----
TOPICS_DIR="${BLACKBOARD}/topics"
TOPIC_DIRS=()
if [[ -n "$ADDRESS" ]]; then
    if [[ -d "${TOPICS_DIR}/${ADDRESS}" ]]; then
        TOPIC_DIRS+=("${TOPICS_DIR}/${ADDRESS}")
    fi
else
    shopt -s nullglob
    for d in "${TOPICS_DIR}/"?*."${PLATFORM}"; do
        [[ -d "$d" ]] && TOPIC_DIRS+=("$d")
    done
    shopt -u nullglob
fi

# 统计匹配 topic 的待消费消息总数（TOPIC_DIRS 为空时返回 0）
pending_count() {
    local total=0 d f
    if [[ "${#TOPIC_DIRS[@]}" -gt 0 ]]; then
        shopt -s nullglob
        for d in "${TOPIC_DIRS[@]}"; do
            for f in "$d"/queue/*.json; do
                total=$((total + 1))
            done
        done
        shopt -u nullglob
    fi
    echo "$total"
}

# ---- --list：只列数不消费 ----
if [[ "$LIST" -eq 1 ]]; then
    TOTAL=0
    if [[ "${#TOPIC_DIRS[@]}" -gt 0 ]]; then
        shopt -s nullglob
        for d in "${TOPIC_DIRS[@]}"; do
            n=0
            for f in "$d"/queue/*.json; do
                n=$((n + 1))
            done
            TOTAL=$((TOTAL + n))
            echo "topics/$(basename "$d"): ${n} 条待消费"
        done
        shopt -u nullglob
    fi
    echo "共 ${TOTAL} 条待消费"
    exit 0
fi

# ---- 空队列：--auto 完全无输出；默认模式输出提示 ----
INITIAL="$(pending_count)"
if [[ "$INITIAL" -eq 0 ]]; then
    if [[ "$AUTO" -eq 0 ]]; then
        echo "无待消费消息"
    fi
    exit 0
fi

# ---- drain ----
LIMIT=3
if [[ "$ALL" -eq 1 ]]; then
    LIMIT=1000000000
fi

SEP="$(printf '━%.0s' {1..40})"

# 扫描匹配 topic 的 queue/，按 JSON 内 timestamp 升序取最早一条
# 输出（tab 分隔）: 文件 topic id token source timestamp summaryFile 滞留天数
scan_earliest() {
    if [[ "${#TOPIC_DIRS[@]}" -eq 0 ]]; then
        return 0
    fi
    node -e '
        const fs = require("fs");
        const pathLib = require("path");
        const topicDirs = process.argv.slice(1);

        // 兼容 +0800（无冒号）时区后缀
        const norm = (ts) => String(ts).replace(/([+-]\d{2})(\d{2})$/, "$1:$2");

        let best = null;
        for (const dir of topicDirs) {
            const queueDir = pathLib.join(dir, "queue");
            let files = [];
            try {
                files = fs.readdirSync(queueDir);
            } catch (e) { continue; }
            for (const f of files) {
                if (!f.endsWith(".json") || f.startsWith(".")) continue;
                const full = pathLib.join(queueDir, f);
                let msg;
                try {
                    msg = JSON.parse(fs.readFileSync(full, "utf8"));
                } catch (e) { continue; }
                const parsed = Date.parse(norm(msg.timestamp));
                const time = Number.isNaN(parsed) ? 0 : parsed;
                if (!best || time < best.time) {
                    best = {
                        time: time,
                        file: full,
                        topic: pathLib.basename(dir),
                        id: msg.id != null ? msg.id : "",
                        token: msg.token || "",
                        source: msg.source || "",
                        timestamp: msg.timestamp || "",
                        summaryFile: msg.summaryFile || "",
                        staleDays: Math.max(0, Math.floor((Date.now() - time) / 86400000))
                    };
                }
            }
        }
        if (best) {
            console.log([best.file, best.topic, best.id, best.token, best.source,
                best.timestamp, best.summaryFile, best.staleDays].join("\t"));
        }
    ' "$@"
}

consume_count=0
while [[ "$consume_count" -lt "$LIMIT" ]]; do
    CAND="$(scan_earliest "${TOPIC_DIRS[@]}")"
    if [[ -z "$CAND" ]]; then
        break
    fi
    IFS=$'\t' read -r MSG_FILE TOPIC MSG_ID TOKEN SOURCE TIMESTAMP SUMMARY_FILE STALE_DAYS <<< "$CAND"
    STALE_DAYS="${STALE_DAYS:-0}"

    BASE_NAME="$(basename "$MSG_FILE")"
    DONE_FILE="${TOPICS_DIR}/${TOPIC}/done/${BASE_NAME}"
    FAILED_FILE="${TOPICS_DIR}/${TOPIC}/failed/${BASE_NAME}"
    SUMMARY_PATH="${BLACKBOARD}/${SUMMARY_FILE}"

    # 归档目录兜底（正常由 produce 创建，手写黑板可能缺失）
    mkdir -p "${TOPICS_DIR}/${TOPIC}/done" "${TOPICS_DIR}/${TOPIC}/failed"

    # 读摘要；缺失/不可读 → 抢占式归档 failed/，输出说明（不中断 drain 其余消息）
    SUMMARY_CONTENT=""
    SUMMARY_OK=0
    if [[ -f "$SUMMARY_PATH" ]] && SUMMARY_CONTENT="$(cat "$SUMMARY_PATH")"; then
        SUMMARY_OK=1
    fi

    if [[ "$SUMMARY_OK" -eq 0 ]]; then
        # mv 原子性：并发时唯一赢家归档成功，输家静默跳过
        if mv "$MSG_FILE" "$FAILED_FILE" 2>/dev/null; then
            echo "消息 #${MSG_ID}: 摘要文件缺失（${SUMMARY_PATH}），已归档 failed/"
        fi
    else
        if mv "$MSG_FILE" "$DONE_FILE" 2>/dev/null; then
            # 注入块（stdout 即 hook 注入内容）
            echo "$SEP"
            echo "来自 ${SOURCE} 的任务摘要 | ${TOKEN}.${SOURCE} | ${TIMESTAMP}"
            if [[ "$STALE_DAYS" -gt 7 ]]; then
                echo "⚠ 该消息已滞留 ${STALE_DAYS} 天，建议确认时效"
            fi
            echo "$SEP"
            printf '%s\n' "$SUMMARY_CONTENT"
            echo "$SEP"
            echo "以上摘要已注入上下文，请在后续思考和对话中参考此内容。"
            echo "$SEP"
        fi
    fi

    # 防御：消息既没归档成功也没被并发方取走（如权限问题）→ 报错退出，避免死循环
    if [[ -e "$MSG_FILE" ]]; then
        echo "ERROR: 消息归档失败: ${MSG_FILE}" >&2
        exit 1
    fi

    consume_count=$((consume_count + 1))
done

# 结束时若仍有剩余 → 提示下轮继续
REMAINING="$(pending_count)"
if [[ "$REMAINING" -gt 0 ]]; then
    echo "（还有 ${REMAINING} 条待消费，下轮自动继续）"
fi
exit 0
