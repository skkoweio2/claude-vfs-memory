#!/bin/sh
# SessionStart hook：仅在 clear/compact/resume 续接语境、且存在【当前 session_id 自己的】
# handoff 时注入，杜绝冷启动/新任务被无关旧现场干扰。不重复注入 MEMORY.md（harness 已加载）。
. "$(dirname "$0")/_common.sh"
[ "$VFS_DISABLED" = "1" ] && exit 0

ensure_session_dir
SOURCE="$(vfs_get '.source')"
vfs_log "session-start source=$SOURCE project=$PROJECT id=$SESSION_ID"

OUT=""

# 续接策略（保守，杜绝跨会话/跨项目干扰）：
#   - 仅在明确"延续同一会话"的语境注入：clear / compact / resume；
#   - 且只认【当前 session_id 自己的】handoff.md，没有就不注入；
#   - startup 等冷启动一律不注入，避免新任务被旧现场带偏。
case "$SOURCE" in
  clear|compact|resume)
    if [ -f "${SESSION_DIR}/handoff.md" ]; then
      HANDOFF_BODY="$(head -c 6000 "${SESSION_DIR}/handoff.md" 2>/dev/null)"
      OUT="## 🗂 VFS 续接：本会话上次交接快照（背景参考，与当前任务无关可忽略）
（来源 ${SESSION_DIR}/handoff.md）

${HANDOFF_BODY}

"
    fi
    ;;
esac

OUT="${OUT}## 🗂 VFS 记忆系统已激活
- 本会话工作区：\`${SESSION_DIR}\`（scratch/ 草稿、large_tool_results/ 卸载的大输出）
- 大于 8KB 的 Bash/WebFetch/Grep 输出会被自动卸载到磁盘并在上下文中替换为摘要+取回路径；需要完整内容时用 Read 取回。
- 手动命令：/recall /offload /handoff /save /vfs"

emit_context "SessionStart" "$OUT"
exit 0
