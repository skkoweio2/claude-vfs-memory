#!/bin/sh
# Codex 监测的 launchd 管理：install（每60s定时运行）/ uninstall / status。
# 用法：sh ~/.claude/vfs/bin/codex-watch-ctl.sh install|uninstall|status
LABEL="com.vfs.codex-ctx-watch"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/codex-ctx-watch.sh"
INTERVAL="${CODEX_CTX_INTERVAL:-60}"

case "${1:-status}" in
  install)
    mkdir -p "${HOME}/Library/LaunchAgents" 2>/dev/null
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>${SCRIPT}</string>
  </array>
  <key>StartInterval</key><integer>${INTERVAL}</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>${HOME}/.claude/vfs/codex-state/launchd.err</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null
    if launchctl load "$PLIST" 2>/dev/null; then
      echo "✅ 已安装并加载：${LABEL}（每 ${INTERVAL}s 运行一次）"
      echo "   关停：sh $0 uninstall   |   临时禁用：touch ~/.claude/vfs/codex-state/DISABLED"
    else
      echo "⚠️ plist 已写入但 launchctl load 失败，可手动：launchctl load $PLIST"
    fi
    ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null
    rm -f "$PLIST" 2>/dev/null
    echo "✅ 已卸载 ${LABEL}"
    ;;
  status)
    if launchctl list 2>/dev/null | grep -q "$LABEL"; then
      echo "运行中：$(launchctl list 2>/dev/null | grep "$LABEL")"
    else
      echo "未加载（plist 存在: $([ -f "$PLIST" ] && echo 是 || echo 否)）"
    fi
    [ -f "${HOME}/.claude/vfs/codex-state/DISABLED" ] && echo "⚠️ 当前被 DISABLED kill switch 禁用中"
    exit 0
    ;;
  *) echo "用法: $0 install|uninstall|status" ;;
esac
