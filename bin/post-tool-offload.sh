#!/bin/sh
# PostToolUse hook：超大工具输出落盘 + 用 updatedToolOutput 把进入上下文的内容替换为
# "摘要 + 取回路径"，真正给上下文减负。必须同步执行（async 无法替换已交付输出）。
# 设计为快进快出：小输出第一时间 exit 0，几乎零延迟。
. "$(dirname "$0")/_common.sh"
[ "$VFS_DISABLED" = "1" ] && exit 0

TOOL="$(vfs_get '.tool_name')"

# 仅对易产生大块非主动检索输出的工具生效；Read/Glob 是用户主动取内容，不抢。
case "$TOOL" in
  Bash|WebFetch|Grep) : ;;
  *) exit 0 ;;
esac

# 取工具输出文本：优先顶层 tool_output，回退 tool_response.content / tool_response
OUT="$(vfs_get '.tool_output')"
[ -z "$OUT" ] && OUT="$(vfs_get '.tool_response.content')"
[ -z "$OUT" ] && OUT="$(printf '%s' "$VFS_INPUT" | jq -r 'if (.tool_response|type)=="string" then .tool_response else empty end' 2>/dev/null)"
[ -z "$OUT" ] && exit 0

THRESHOLD=8000
BYTES="$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
[ "$BYTES" -le "$THRESHOLD" ] 2>/dev/null && exit 0

ensure_session_dir
LTR="${SESSION_DIR}/large_tool_results"
N="$(ls "$LTR" 2>/dev/null | wc -l | tr -d ' ')"
SEQ="$(printf '%04d' $((N + 1)))"
FILE="${LTR}/offload-${SEQ}-${TOOL}.txt"

{
  printf '# VFS 卸载产物\n# tool=%s  bytes=%s  time=%s\n' "$TOOL" "$BYTES" "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
  printf '# tool_input: %s\n\n' "$(vfs_get '.tool_input' | tr '\n' ' ' | cut -c1-300)"
  printf '%s\n' "$OUT"
} > "$FILE" 2>/dev/null

LINES="$(printf '%s' "$OUT" | wc -l | tr -d ' ')"
HEAD="$(printf '%s' "$OUT" | head -c 1200)"
SUMMARY="$(printf '%s\n\n[⤵ VFS 已卸载此输出：完整 %s 字节 / %s 行已存至 %s —— 需要完整内容时用 Read 取回该文件]' "$HEAD" "$BYTES" "$LINES" "$FILE")"

vfs_log "offload tool=$TOOL bytes=$BYTES -> $FILE"

esc="$(json_escape "$SUMMARY")"
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":%s}}\n' "$esc"
exit 0
