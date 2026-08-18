#!/usr/bin/env bash
# sync-index.sh — 原子写入 index.json，防止写入中断导致文件损坏
# 用法：sync-index.sh <blackboard-path> <json-content>
# 示例：sync-index.sh /path/to/blackboard '{"blackboard":"/path","tasks":{}}'

set -euo pipefail

BLACKBOARD="$1"
JSON_CONTENT="$2"
INDEX_FILE="${BLACKBOARD}/index.json"
TMP_FILE="${BLACKBOARD}/.index.tmp.$$"

# 确保黑板目录存在
mkdir -p "$BLACKBOARD"

# 写入临时文件
printf '%s' "$JSON_CONTENT" > "$TMP_FILE"

# 原子替换
mv -f "$TMP_FILE" "$INDEX_FILE"

# 如果 mv 失败（不应发生，但保险起见清理临时文件）
if [ $? -ne 0 ] && [ -f "$TMP_FILE" ]; then
    rm -f "$TMP_FILE"
    echo "ERROR: Failed to write index.json" >&2
    exit 1
fi
