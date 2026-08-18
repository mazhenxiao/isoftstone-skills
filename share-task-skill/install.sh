#!/usr/bin/env bash
# share-task-skill 安装脚本
# 自动检测 AI CLI 工具并安装到对应 skills 目录

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_NAME="share-task"

# 检测已安装的 AI CLI 工具
detect_platforms() {
  local found=()
  [[ -d "$HOME/.claude/skills" ]] && found+=("claude:$HOME/.claude/skills")
  [[ -d "$HOME/.opencode/skills" ]] && found+=("opencode:$HOME/.opencode/skills")
  [[ -d "$HOME/.cursor/skills" ]] && found+=("cursor:$HOME/.cursor/skills")

  if [[ ${#found[@]} -eq 0 ]]; then
    echo "未检测到支持的 AI CLI 工具（claude / opencode / cursor）"
    echo "请手动指定安装路径："
    echo "  $0 --target /path/to/skills/dir"
    exit 1
  fi

  echo "检测到以下 AI CLI 工具："
  for item in "${found[@]}"; do
    local name="${item%%:*}"
    local path="${item##*:}"
    echo "  - $name ($path)"
  done
}

install_to() {
  local target="$1"
  local dest="${target}/${SKILL_NAME}"

  if [[ -d "$dest" ]]; then
    echo "目标已存在: $dest"
    read -rp "是否覆盖？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "已取消" && exit 0
    rm -rf "$dest"
  fi

  cp -r "$SCRIPT_DIR" "$dest"
  chmod +x "$dest/scripts/sync-index.sh"
  echo "已安装到: $dest"
}

# 主逻辑
if [[ "${1:-}" == "--target" ]]; then
  [[ -z "${2:-}" ]] && echo "用法: $0 --target /path/to/skills/dir" && exit 1
  install_to "$2"
else
  detect_platforms
  echo ""
  read -rp "输入要安装的平台名称（如 claude），或输入 all 安装到所有检测到的平台: " choice

  if [[ "$choice" == "all" ]]; then
    for item in $(detect_platforms); do
      local name="${item%%:*}"
      local path="${item##*:}"
      install_to "$path"
    done
  else
    local found_path=""
    for item in $(detect_platforms); do
      local name="${item%%:*}"
      local path="${item##*:}"
      if [[ "$name" == "$choice" ]]; then
        found_path="$path"
        break
      fi
    done

    if [[ -z "$found_path" ]]; then
      echo "未找到平台: $choice"
      echo "用法: $0 --target /path/to/skills/dir"
      exit 1
    fi

    install_to "$found_path"
  fi
fi

echo "安装完成！使用方式: 在 AI CLI 中输入 share-task:start {口令} {平台名}"
