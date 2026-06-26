#!/bin/sh
# VFS 公共库 —— 被各 hook 脚本 source。
# 职责：读取 stdin 的 hook JSON 负载、导出公共变量、提供辅助函数。
# 设计原则：永不破坏会话。缺 jq 时整体降级为 no-op（VFS_DISABLED=1）。

VFS_ROOT="${VFS_HOME:-${HOME}/.claude/vfs}"
VFS_MEM="${HOME}/.claude/memory"
VFS_LOG="${VFS_ROOT}/vfs.log"
VFS_DISABLED=0

# 一次性读入 stdin（hook 的 JSON 负载）
VFS_INPUT="$(cat 2>/dev/null)"

if command -v jq >/dev/null 2>&1; then
  # vfs_get <jq过滤器>，例：vfs_get '.tool_output'
  vfs_get() { printf '%s' "$VFS_INPUT" | jq -r "$1 // empty" 2>/dev/null; }
  json_escape() { printf '%s' "$1" | jq -Rs .; }
else
  # 无 jq → VFS 整体关闭，hook 立即 exit 0，绝不影响会话
  VFS_DISABLED=1
  vfs_get() { printf ''; }
  json_escape() { printf '""'; }
fi

SESSION_ID="$(vfs_get '.session_id')";       [ -z "$SESSION_ID" ] && SESSION_ID="unknown"
CWD="$(vfs_get '.cwd')";                      [ -z "$CWD" ] && CWD="$PWD"
TRANSCRIPT="$(vfs_get '.transcript_path')"
EVENT="$(vfs_get '.hook_event_name')"
PROJECT="$(basename "$CWD" 2>/dev/null)";    [ -z "$PROJECT" ] && PROJECT="default"

SESSION_DIR="${VFS_ROOT}/sessions/${SESSION_ID}"
PROJ_MEM="${VFS_MEM}/${PROJECT}"

vfs_log() {
  ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  printf '%s [%s] %s\n' "$ts" "${EVENT:-?}" "$*" >> "$VFS_LOG" 2>/dev/null
}

ensure_session_dir() {
  mkdir -p "${SESSION_DIR}/scratch" "${SESSION_DIR}/large_tool_results" 2>/dev/null
  if [ ! -f "${SESSION_DIR}/manifest.json" ]; then
    printf '{"session_id":"%s","cwd":"%s","project":"%s","started":"%s"}\n' \
      "$SESSION_ID" "$CWD" "$PROJECT" "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" \
      > "${SESSION_DIR}/manifest.json" 2>/dev/null
  fi
}

# 输出 additionalContext（SessionStart/UserPromptSubmit/PreCompact 通用）
# 用法：emit_context <hookEventName> <文本>
emit_context() {
  [ -z "$2" ] && return 0
  esc="$(json_escape "$2")"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' "$1" "$esc"
}

# 快照 transcript + 生成 handoff.md（PreCompact 与 SessionEnd 共用）。
# 用法：vfs_write_handoff <trigger标签>。无 transcript 时仍写占位 handoff。
# 自动生成的 handoff 首行带 <!-- vfs:auto --> 标记，供调用方判断是否为手动精炼版。
vfs_write_handoff() {
  _trigger="$1"
  _src="${2:-$TRANSCRIPT}"   # 可指定源 transcript（如 /clear 时用前驱会话的）；默认当前会话
  ensure_session_dir
  _snap="${SESSION_DIR}/transcript-snapshot.jsonl"
  [ -n "$_src" ] && [ -f "$_src" ] && cp -f "$_src" "$_snap" 2>/dev/null

  _handoff="${SESSION_DIR}/handoff.md"
  _now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  _recent=""
  _files=""
  _last=""
  if [ -n "$_src" ] && [ -f "$_src" ]; then
    _recent="$(jq -r '
      select(.type=="user") | .message.content
      | if type=="string" then . else (map(select(.type=="text").text)|join(" ")) end
      | select(. != null and (startswith("<")|not) and (length>0))
    ' "$_src" 2>/dev/null | grep -v '^$' | tail -8 | sed 's/^/- /' | cut -c1-200)"

    _files="$(jq -r '
      select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use" and (.name=="Write" or .name=="Edit" or .name=="NotebookEdit"))
      | .input.file_path // empty
    ' "$_src" 2>/dev/null | sort -u | tail -25 | sed 's/^/- /')"

    # 上一条助手文本消息——常含"下一步我要…"，对续接最有价值（借鉴 CCR）
    _last="$(jq -r '
      select(.type=="assistant") | .message.content
      | if type=="string" then . else ((map(select(.type=="text").text)) // [] | join(" ")) end
      | select(. != null and (length>0))
    ' "$_src" 2>/dev/null | grep -v '^$' | tail -1 | cut -c1-600)"
  fi

  # git 现场（在途未提交的工作）——子 shell 切目录，不污染当前 CWD（借鉴 CCR）
  _gitstat=""
  _gitdiff=""
  if command -v git >/dev/null 2>&1; then
    _gitstat="$( (cd "$CWD" 2>/dev/null && git status --short 2>/dev/null | head -40) )"
    _gitdiff="$( (cd "$CWD" 2>/dev/null && git diff --stat 2>/dev/null | tail -30) )"
  fi

  {
    printf '<!-- vfs:auto -->\n'
    printf '# 交接快照 · %s\n\n' "$PROJECT"
    printf '> 由 VFS 自动生成于 %s（trigger=%s）。下次会话 SessionStart 会注入本文件以续接现场。\n\n' "$_now" "$_trigger"
    printf '- 会话：%s\n- 工作目录：%s\n- transcript 快照：%s\n\n' "$SESSION_ID" "$CWD" "$_snap"
    printf '## 最近用户意图（倒序若干条）\n%s\n\n' "${_recent:-（无法从 transcript 提取）}"
    printf '## 上次停在哪（最后一条助手消息）\n%s\n\n' "${_last:-（无）}"
    printf '## 本会话改动过的文件\n%s\n\n' "${_files:-（无记录到的 Write/Edit）}"
    if [ -n "$_gitstat" ]; then
      printf '## Git 现场（未提交改动 git status --short）\n```\n%s\n```\n\n' "$_gitstat"
      [ -n "$_gitdiff" ] && printf '改动规模（git diff --stat）：\n```\n%s\n```\n\n' "$_gitdiff"
    fi
    printf '## 续接提示\n- 完整对话见上方 transcript 快照；大输出见 large_tool_results/。\n- 如需更精炼的"已完成/待办/未决问题"，可手动 /handoff 让我补写。\n'
  } > "$_handoff" 2>/dev/null

  vfs_log "handoff written (trigger=$_trigger) -> $_handoff"
}

# 计算当前会话已用上下文百分比（整数）。拿不到/异常则输出空（调用方据此跳过）。
# 优先 claude-hud 缓存(精确，若装了)；回退读 transcript 最后一条 usage 自算。绝不强依赖插件。
vfs_context_pct() {
  [ -z "$TRANSCRIPT" ] && return 0
  _cf=""
  _hud="${HOME}/.claude/plugins/claude-hud/context-cache"
  if [ -d "$_hud" ]; then
    _sha="$(printf '%s' "$TRANSCRIPT" | shasum -a 256 2>/dev/null | awk '{print $1}')"
    _cf="${_hud}/${_sha}.json"
    if [ -f "$_cf" ]; then
      _p="$(jq -r '.used_percentage // empty' "$_cf" 2>/dev/null)"
      [ -n "$_p" ] && { printf '%s' "${_p%.*}"; return 0; }
    fi
  fi
  # 回退：transcript 最后一条 assistant 的 usage（input + 两类 cache = 当前提示总量）
  [ -f "$TRANSCRIPT" ] || return 0
  _used="$(tail -120 "$TRANSCRIPT" 2>/dev/null | jq -s '
    [.[]|select(.type=="assistant" and .message.usage!=null)] | last
    | if . == null then empty else (.message.usage | (.input_tokens//0) + (.cache_creation_input_tokens//0) + (.cache_read_input_tokens//0)) end
  ' 2>/dev/null)"
  { [ -z "$_used" ] || [ "$_used" = "null" ] || [ "$_used" = "0" ]; } && return 0
  # 窗口：env 覆盖 → claude-hud 缓存的 context_window_size → 默认 200000
  _win="${VFS_CONTEXT_WINDOW:-}"
  if [ -z "$_win" ] && [ -n "$_cf" ] && [ -f "$_cf" ]; then
    _win="$(jq -r '.context_window_size // empty' "$_cf" 2>/dev/null)"
  fi
  [ -z "$_win" ] && _win=200000
  _pct="$(awk "BEGIN{printf \"%d\", $_used/$_win*100}" 2>/dev/null)"
  # 窗口判断错(算出>100)宁可不报，避免误触发
  { [ -z "$_pct" ] || [ "$_pct" -gt 100 ] 2>/dev/null; } && return 0
  printf '%s' "$_pct"
}
