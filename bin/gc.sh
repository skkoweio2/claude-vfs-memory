#!/bin/sh
# VFS 垃圾回收：清理 N 天前（默认 90）的会话工作区，并保持索引/日志精简。
# 只清理 vfs/sessions/ 下的会话产物（scratch、卸载、handoff、transcript 快照）；
# 绝不触碰 ~/.claude/memory 的持久记忆——那是长期知识，不随时间删除。
# 由 session-end 每日节流触发，也可手动运行：sh ~/.claude/vfs/bin/gc.sh
# 天数可用环境变量覆盖：VFS_GC_DAYS=180 sh gc.sh
. "$(dirname "$0")/_common.sh"
[ "$VFS_DISABLED" = "1" ] && exit 0

DAYS="${VFS_GC_DAYS:-90}"
SESS="${VFS_ROOT}/sessions"

# 1) 删除 mtime 超过 DAYS 天的会话目录（UUID 目录，无空格，安全）
REMOVED=0
if [ -d "$SESS" ]; then
  REMOVED="$(find "$SESS" -mindepth 1 -maxdepth 1 -type d -mtime +"$DAYS" 2>/dev/null | wc -l | tr -d ' ')"
  find "$SESS" -mindepth 1 -maxdepth 1 -type d -mtime +"$DAYS" -exec rm -rf {} + 2>/dev/null
fi

# 2) 索引瘦身：只保留"目录仍存在"的会话行（jq 不可用则跳过）
IDX="${VFS_ROOT}/index/sessions.jsonl"
if [ -f "$IDX" ]; then
  TMP="${IDX}.tmp.$$"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    sid="$(printf '%s' "$line" | jq -r '.session_id // empty' 2>/dev/null)"
    [ -n "$sid" ] && [ -d "${SESS}/${sid}" ] && printf '%s\n' "$line"
  done < "$IDX" > "$TMP" 2>/dev/null
  mv "$TMP" "$IDX" 2>/dev/null
fi

# 3) 日志轮转：超过 1000 行只保留尾部 800 行
if [ -f "$VFS_LOG" ]; then
  LC="$(wc -l < "$VFS_LOG" 2>/dev/null | tr -d ' ')"
  if [ "${LC:-0}" -gt 1000 ] 2>/dev/null; then
    tail -n 800 "$VFS_LOG" > "${VFS_LOG}.tmp" 2>/dev/null && mv "${VFS_LOG}.tmp" "$VFS_LOG" 2>/dev/null
  fi
fi

vfs_log "gc done days=$DAYS removed=$REMOVED"
exit 0
