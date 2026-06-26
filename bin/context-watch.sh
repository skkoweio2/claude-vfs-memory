#!/bin/sh
# PostToolUse hook：监测上下文使用率，到阈值时【备好加强版 handoff + 注入一行提醒】。
# 安全第一——只提醒，绝不 spawn 新窗口、绝不停会话（杜绝 CCR 的 fork-bomb 类风险）。
# 本会话只提醒一次(latch)；使用率跌回阈值-迟滞以下自动重置，使 /compact 后还能再提醒。
# 阈值可调：VFS_CTX_THRESHOLD（默认 75）。
. "$(dirname "$0")/_common.sh"
[ "$VFS_DISABLED" = "1" ] && exit 0

THRESHOLD="${VFS_CTX_THRESHOLD:-75}"
case "$THRESHOLD" in *[!0-9]*) THRESHOLD=75 ;; esac

PCT="$(vfs_context_pct)"
[ -z "$PCT" ] && exit 0
case "$PCT" in *[!0-9]*) exit 0 ;; esac

ensure_session_dir
LATCH="${SESSION_DIR}/.ctx-warned"
HYST=$((THRESHOLD - 5))

# 跌回阈值-5% 以下：解除 latch（compact 后可再次提醒），退出
if [ "$PCT" -lt "$HYST" ]; then
  [ -f "$LATCH" ] && rm -f "$LATCH" 2>/dev/null
  exit 0
fi

# 死区（HYST~THRESHOLD）或未达阈值：不动作
[ "$PCT" -lt "$THRESHOLD" ] && exit 0
# 已提醒过则静默，不重复打扰
[ -f "$LATCH" ] && exit 0

# 到阈值且首次：备好加强版 handoff（保护用户手动 /handoff 的精炼版，不覆盖）
EXIST="${SESSION_DIR}/handoff.md"
if [ -f "$EXIST" ] && ! grep -q 'vfs:auto' "$EXIST" 2>/dev/null; then
  :
else
  vfs_write_handoff "ctx-watch:${PCT}pct"
fi

: > "$LATCH" 2>/dev/null
vfs_log "ctx-watch fired pct=${PCT} threshold=${THRESHOLD}"

MSG="⚠️ 上下文已用 ${PCT}%（阈值 ${THRESHOLD}%）。交接快照已自动备好：${SESSION_DIR}/handoff.md
建议尽快【新开会话或 /clear】——SessionStart 会自动接回该 handoff 续接现场；或 /compact。
继续在接近满载的窗口里工作会更慢、更易降智。本提醒每会话仅一次。"
emit_context "PostToolUse" "$MSG"
exit 0
