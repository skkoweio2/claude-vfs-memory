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
#   - 仅在明确"延续"语境注入：clear / compact / resume；startup 冷启动一律不注入。
#   - 先认【当前 session_id 自己的】handoff（compact/resume 同 id 时命中）。
#   - 若没有且是 clear/compact（实测会起新 session_id、本会话目录是空的）：
#     找【前驱 transcript】——同项目 transcript 目录里、最近 N 分钟内修改、非自身的那份，
#     即时生成 handoff 并注入。新鲜窗口(VFS_CLEAR_FRESH_MIN，默认10)+源限定，杜绝冷启动误接旧任务。
FRESH_MIN="${VFS_CLEAR_FRESH_MIN:-10}"
case "$SOURCE" in
  clear|compact|resume)
    if [ -f "${SESSION_DIR}/handoff.md" ]; then
      HANDOFF_BODY="$(head -c 6000 "${SESSION_DIR}/handoff.md" 2>/dev/null)"
      OUT="## 🗂 VFS 续接：本会话上次交接快照（背景参考，与当前任务无关可忽略）
（来源 ${SESSION_DIR}/handoff.md）

${HANDOFF_BODY}

"
    elif { [ "$SOURCE" = "clear" ] || [ "$SOURCE" = "compact" ]; } && [ -n "$TRANSCRIPT" ]; then
      _tdir="$(dirname "$TRANSCRIPT" 2>/dev/null)"
      _self="$(basename "$TRANSCRIPT" 2>/dev/null)"
      # 同目录、最近 FRESH_MIN 分钟内修改、排除自身的最新 .jsonl = 被 /clear 的前驱会话
      PRED="$(find "$_tdir" -maxdepth 1 -name '*.jsonl' -mmin -"$FRESH_MIN" 2>/dev/null \
        | grep -v -- "$_self" | xargs ls -t 2>/dev/null | head -1)"
      if [ -n "$PRED" ] && [ -f "$PRED" ]; then
        vfs_write_handoff "predecessor:${SOURCE}" "$PRED"
        HANDOFF_BODY="$(head -c 6000 "${SESSION_DIR}/handoff.md" 2>/dev/null)"
        OUT="## 🗂 VFS 续接：上一会话现场（${SOURCE} 前驱，自动生成）
（源 transcript：${PRED}）

${HANDOFF_BODY}

"
        vfs_log "session-start ${SOURCE} predecessor handoff <- $PRED"
      fi
    fi
    ;;
esac

OUT="${OUT}## 🗂 VFS 记忆系统已激活
- 本会话工作区：\`${SESSION_DIR}\`（scratch/ 草稿、large_tool_results/ 卸载的大输出）
- 大于 8KB 的 Bash/WebFetch/Grep 输出会被自动卸载到磁盘并在上下文中替换为摘要+取回路径；需要完整内容时用 Read 取回。
- 手动命令：/recall /offload /handoff /save /vfs"

emit_context "SessionStart" "$OUT"
exit 0
