#!/usr/bin/env bash
# share-task-skill 安装脚本（plugin 模式）
# 将 skill 注册为本地 plugin，支持 Claude Code 的 plugin-name:skill-name 格式

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_NAME="share-task"
CLAUDE_PLUGINS_DIR="$HOME/.claude/plugins"
INSTALLED_JSON="${CLAUDE_PLUGINS_DIR}/installed_plugins.json"
INSTALL_PATH="${CLAUDE_PLUGINS_DIR}/${PLUGIN_NAME}"

# 检测目标安装方式
detect_install_mode() {
  # 如果 isoftstone-skills 目录下，用软链接
  local canonical_src
  canonical_src="$(cd "$SCRIPT_DIR" && pwd)"

  if [[ "$canonical_src" != "$INSTALL_PATH" ]]; then
    echo "symlink"
  else
    echo "direct"
  fi
}

# 安装到 ~/.claude/plugins/
install_plugin() {
  local mode
  mode="$(detect_install_mode)"

  mkdir -p "$CLAUDE_PLUGINS_DIR"

  # 创建指向源目录的软链接（或直接拷贝）
  if [[ "$mode" == "symlink" ]]; then
    if [[ -L "$INSTALL_PATH" ]]; then
      echo "软链接已存在: $INSTALL_PATH -> $(readlink "$INSTALL_PATH")"
    elif [[ -d "$INSTALL_PATH" ]]; then
      echo "目标目录已存在: $INSTALL_PATH（非软链接），将覆盖"
      rm -rf "$INSTALL_PATH"
      ln -s "$SCRIPT_DIR" "$INSTALL_PATH"
      echo "已替换为软链接: $INSTALL_PATH -> $SCRIPT_DIR"
    else
      ln -s "$SCRIPT_DIR" "$INSTALL_PATH"
      echo "已创建软链接: $INSTALL_PATH -> $SCRIPT_DIR"
    fi
  else
    echo "源目录即安装目录，无需操作"
  fi

  # 注册到 installed_plugins.json
  register_plugin
}

# 注册到 installed_plugins.json
register_plugin() {
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

  if [[ ! -f "$INSTALLED_JSON" ]]; then
    echo '{"version":2,"plugins":{}}' > "$INSTALLED_JSON"
  fi

  # 用 node 来安全地操作 JSON
  node -e "
    const fs = require('fs');
    const path = '$INSTALLED_JSON';
    const data = JSON.parse(fs.readFileSync(path, 'utf8'));

    const key = '${PLUGIN_NAME}@local';
    data.plugins[key] = [{
      scope: 'user',
      installPath: '$INSTALL_PATH',
      version: '1.0.0',
      installedAt: '${now}',
      lastUpdated: '${now}',
      gitCommitSha: 'local'
    }];

    fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
    console.log('已注册到 installed_plugins.json: ' + key);
  "

  # 确保旧 skills 目录不存在（避免冲突）
  local old_skill="$HOME/.claude/skills/${PLUGIN_NAME}"
  if [[ -d "$old_skill" ]]; then
    rm -rf "$old_skill"
    echo "已清理旧 skill 目录: $old_skill"
  fi
}

# 卸载
uninstall() {
  # 移除软链接或目录
  if [[ -L "$INSTALL_PATH" || -d "$INSTALL_PATH" ]]; then
    rm -rf "$INSTALL_PATH"
    echo "已移除: $INSTALL_PATH"
  fi

  # 从 installed_plugins.json 移除
  node -e "
    const fs = require('fs');
    const path = '$INSTALLED_JSON';
    if (!fs.existsSync(path)) return;
    const data = JSON.parse(fs.readFileSync(path, 'utf8'));
    delete data.plugins['${PLUGIN_NAME}@local'];
    fs.writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
    console.log('已从 installed_plugins.json 移除');
  "

  echo "卸载完成"
}

# 主逻辑
case "${1:-install}" in
  install)
    install_plugin
    echo ""
    echo "安装完成！重启 Claude Code 后生效。"
    echo "可用命令："
    echo "  /share-task:start {口令} {平台名}"
    echo "  /share-task:set"
    echo "  /share-task:get {口令} {平台名}"
    echo "  /share-task:clear"
    ;;
  uninstall)
    uninstall
    ;;
  *)
    echo "用法: $0 [install|uninstall]"
    ;;
esac
