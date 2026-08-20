#!/usr/bin/env bash
# watcher.sh — 轮询黑板待消费队列，仅当数量增加时发一次 macOS 系统通知（state 去重，防通知风暴）
# 用法：watcher.sh <blackboard> <platform> [interval=5]
# 示例：watcher.sh /path/to/blackboard claude 10
# 说明：
#   - state 文件 {blackboard}/.watcher-state-{platform} 记录上次已通知的 count
#   - count > last → osascript 通知一次（含 topic 列表）；count <= last（含归零）→ 静默更新 state
#   - 默认不安装、不常驻；面向"人不在任何会话里"的场景手动启动

set -euo pipefail

usage() {
  cat <<'EOF'
用法: watcher.sh <blackboard> <platform> [interval=5]

参数:
  blackboard  黑板根目录（绝对路径）
  platform    本平台身份（收件人平台，如 claude）
  interval    轮询间隔秒数，默认 5

示例:
  watcher.sh /path/to/blackboard claude
  watcher.sh /path/to/blackboard claude 10

停止: Ctrl+C（或 kill，收到 INT/TERM 后干净退出）
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage >&2
    exit 1
fi

BLACKBOARD="$1"
PLATFORM="$2"
INTERVAL="${3:-5}"

if [[ ! "$INTERVAL" =~ ^[0-9]+$ ]]; then
    echo "ERROR: interval 需为非负整数: ${INTERVAL}" >&2
    exit 1
fi

TOPICS_DIR="${BLACKBOARD}/topics"
STATE_FILE="${BLACKBOARD}/.watcher-state-${PLATFORM}"

mkdir -p "$BLACKBOARD"

# 读取上次已通知的 count（无 state / 内容非法 → 视为 0）
load_last() {
    if [[ -f "$STATE_FILE" ]]; then
        local v
        v="$(cat "$STATE_FILE" 2>/dev/null || true)"
        if [[ "$v" =~ ^[0-9]+$ ]]; then
            echo "$v"
            return
        fi
    fi
    echo 0
}

# 原子写 state（tmp + mv）
save_state() {
    local tmp
    tmp="${BLACKBOARD}/.watcher-state.tmp.$$"
    printf '%s\n' "$1" > "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

# 统计匹配 topics/*.{platform} 的待消费数（含 topic 明细）
# 结果写入全局 TOTAL（总数）与 DETAIL（"topic N 条, ..." 明细）
poll() {
    TOTAL=0
    DETAIL=""
    local d f n
    shopt -s nullglob
    for d in "${TOPICS_DIR}/"?*."${PLATFORM}"; do
        [[ -d "$d" ]] || continue
        n=0
        for f in "$d"/queue/*.json; do
            n=$((n + 1))
        done
        if [[ "$n" -gt 0 ]]; then
            DETAIL="${DETAIL}$(basename "$d") ${n} 条, "
            TOTAL=$((TOTAL + n))
        fi
    done
    shopt -u nullglob
    DETAIL="${DETAIL%, }"
}

# macOS 系统通知（osascript 缺失时静默跳过，仅打印日志行）
notify() {
    if command -v osascript >/dev/null 2>&1; then
        local title body
        title="share-task 新消息"
        body="平台 ${PLATFORM}：${TOTAL} 条待消费（${DETAIL}）"
        body="${body//\"/\\\"}"
        osascript -e "display notification \"${body}\" with title \"${title}\""
    fi
    echo "[$(date '+%H:%M:%S')] 通知: ${TOTAL} 条待消费（${DETAIL}）"
}

trap 'echo ""; echo "watcher 已停止"; exit 0' INT TERM

echo "watcher 启动: blackboard=${BLACKBOARD} platform=${PLATFORM} interval=${INTERVAL}s"

while :; do
    poll
    LAST="$(load_last)"
    # 仅 count 增加时通知一次；持平/回落（含归零）静默
    if [[ "$TOTAL" -gt "$LAST" ]]; then
        notify
    fi
    save_state "$TOTAL"
    sleep "$INTERVAL"
done
