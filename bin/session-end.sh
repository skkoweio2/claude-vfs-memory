#!/bin/sh
# SessionEnd hook：会话结束时向全局索引追加一行摘要，便于日后回溯历史任务现场。
# 注意：SessionEnd 不保证总能触发（崩溃等），关键现场由 PreCompact 兜底。
. "$(dirname "$0")/_common.sh"
[ "$VFS_DISABLED" = "1" ] && exit 0

REASON="$(vfs_get '.reason')"
[ -d "$SESSION_DIR" ] || exit 0   # 没产生过 VFS 活动则不记账

# 抢救现场：/clear、退出等不触发 PreCompact 的收尾路径，会丢失"未落盘"的进度。
# 这里在会话结束时从 transcript 自动补写 handoff，把每次结束变成安全检查点。
# 但不覆盖用户用 /handoff 精炼过的手动版（无 vfs:auto 标记者视为手动，保留）。
EXIST="${SESSION_DIR}/handoff.md"
if [ -f "$EXIST" ] && ! grep -q 'vfs:auto' "$EXIST" 2>/dev/null; then
  vfs_log "session-end keep manual handoff (reason=$REASON)"
elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  vfs_write_handoff "session-end:${REASON}"
fi

HANDOFF=""
[ -f "${SESSION_DIR}/handoff.md" ] && HANDOFF="${SESSION_DIR}/handoff.md"
NOFF="$(ls "${SESSION_DIR}/large_tool_results" 2>/dev/null | wc -l | tr -d ' ')"

mkdir -p "${VFS_ROOT}/index" 2>/dev/null
LINE="$(printf '{"session_id":"%s","project":"%s","cwd":"%s","ended":"%s","reason":"%s","handoff":"%s","offloads":%s}' \
  "$SESSION_ID" "$PROJECT" "$CWD" "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" "$REASON" "$HANDOFF" "${NOFF:-0}")"
printf '%s\n' "$LINE" >> "${VFS_ROOT}/index/sessions.jsonl" 2>/dev/null

vfs_log "session-end reason=$REASON offloads=$NOFF"

# 每日节流 GC：清理 90 天前的会话工作区（不动 memory）。放在会话收尾，零启动延迟。
# stamp 比 1 天旧（或不存在）才触发；</dev/null 防 gc 内 _common.sh 的 cat 阻塞。
STAMP="${VFS_ROOT}/.last-gc"
if [ ! -f "$STAMP" ] || find "$STAMP" -mtime +1 2>/dev/null | grep -q .; then
  : > "$STAMP" 2>/dev/null
  "$(dirname "$0")/gc.sh" </dev/null >/dev/null 2>&1
fi
exit 0
