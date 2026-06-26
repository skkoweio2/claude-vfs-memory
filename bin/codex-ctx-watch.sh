#!/bin/sh
# Codex 上下文监测（安全版）：扫描近期活跃的 rollout，到阈值就【写 handoff 到 VFS + 发 macOS 通知】。
# 只读 rollout 自算%，零侵入——绝不 spawn 新窗口、绝不停会话、绝不碰 config.toml / notify。
# 由 launchd 定时（默认 60s）运行，或手动：sh ~/.claude/vfs/bin/codex-ctx-watch.sh
# 配置：CODEX_CTX_THRESHOLD(75) CODEX_CTX_IDLE_MIN(45) CODEX_CTX_COOLDOWN_MIN(20)
# kill switch：touch ~/.claude/vfs/codex-state/DISABLED
VFS_ROOT="${VFS_HOME:-${HOME}/.claude/vfs}"
STATE="${VFS_ROOT}/codex-state"
LOG="${VFS_ROOT}/vfs.log"
SESS_ROOT="${HOME}/.codex/sessions"
mkdir -p "$STATE" 2>/dev/null

[ -f "${STATE}/DISABLED" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ -d "$SESS_ROOT" ] || exit 0

THRESHOLD="${CODEX_CTX_THRESHOLD:-75}"; case "$THRESHOLD" in *[!0-9]*) THRESHOLD=75 ;; esac
IDLE_MIN="${CODEX_CTX_IDLE_MIN:-45}"
COOLDOWN_MIN="${CODEX_CTX_COOLDOWN_MIN:-20}"

log() { ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"; printf '%s [codex] %s\n' "$ts" "$*" >> "$LOG" 2>/dev/null; }

# 只看最近 IDLE_MIN 分钟内有写入的 rollout（活跃且 turn 已结束/空闲——Codex 在回合末写 token_count）
find "$SESS_ROOT" -name 'rollout-*.jsonl' -mmin -"$IDLE_MIN" 2>/dev/null | while IFS= read -r f; do
  tc="$(jq -c 'select(.type=="event_msg" and .payload.type=="token_count") | .payload.info' "$f" 2>/dev/null | tail -1)"
  [ -z "$tc" ] && continue
  win="$(printf '%s' "$tc" | jq -r '.model_context_window // empty' 2>/dev/null)"
  inp="$(printf '%s' "$tc" | jq -r '.last_token_usage.input_tokens // empty' 2>/dev/null)"
  { [ -z "$win" ] || [ -z "$inp" ] || [ "$win" = "0" ]; } && continue
  pct="$(awk "BEGIN{printf \"%d\", $inp/$win*100}" 2>/dev/null)"
  { [ -z "$pct" ] || [ "$pct" -gt 100 ] 2>/dev/null; } && continue

  id="$(jq -r 'select(.type=="session_meta") | .payload.id // empty' "$f" 2>/dev/null | head -1)"
  [ -z "$id" ] && id="$(basename "$f" .jsonl)"
  latch="${STATE}/${id}.warned"

  # 跌回阈值-5% 以下 → 解除 latch（compact/新窗口后可再提醒）
  if [ "$pct" -lt "$((THRESHOLD - 5))" ]; then
    [ -f "$latch" ] && rm -f "$latch" 2>/dev/null
    continue
  fi
  [ "$pct" -lt "$THRESHOLD" ] && continue
  [ -f "$latch" ] && continue

  # 全局冷却：上次任意提醒在 COOLDOWN_MIN 内则跳过（防通知风暴）
  CD="${STATE}/.last-notify"
  if [ -f "$CD" ] && [ -z "$(find "$CD" -mmin +"$COOLDOWN_MIN" 2>/dev/null)" ]; then
    continue
  fi

  cwd="$(jq -r 'select(.type=="session_meta") | .payload.cwd // empty' "$f" 2>/dev/null | head -1)"
  [ -z "$cwd" ] && cwd="(unknown)"

  hdir="${VFS_ROOT}/sessions/codex-${id}"
  mkdir -p "$hdir" 2>/dev/null
  # 近期真实用户请求（滤掉 AGENTS.md / 权限 / 文件清单等注入消息）
  reqs="$(jq -r 'select(.type=="response_item" and .payload.type=="message" and .payload.role=="user")
    | .payload.content | if type=="array" then (map(.text//empty)|join(" ")) else tostring end' "$f" 2>/dev/null \
    | grep -vE '^# AGENTS\.md|^# Codex|^<|^# Files mentioned' | grep -v '^$' | tail -6 | sed 's/^/- /' | cut -c1-200)"
  gstat="$( (cd "$cwd" 2>/dev/null && git status --short 2>/dev/null | head -30) )"
  {
    printf '<!-- vfs:auto -->\n# Codex 交接快照\n\n'
    printf '> VFS Codex 监测于 %s 生成（%s%%，阈值 %s%%）。在新 codex 会话里读本文件即可接回。\n\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pct" "$THRESHOLD"
    printf '- 会话 id：%s\n- 工作目录：%s\n- rollout：%s\n- 上下文：%s / %s tok = %s%%\n\n' "$id" "$cwd" "$f" "$inp" "$win" "$pct"
    printf '## 最近用户请求\n%s\n\n' "${reqs:-（无法提取）}"
    [ -n "$gstat" ] && printf '## Git 现场（未提交改动）\n```\n%s\n```\n\n' "$gstat"
    printf '## 续接\n完整历史见上面的 rollout 文件；建议在干净的新 codex 窗口里继续。\n'
  } > "${hdir}/handoff.md" 2>/dev/null

  : > "$latch" 2>/dev/null
  : > "$CD" 2>/dev/null
  log "fired id=$id pct=$pct cwd=$cwd -> ${hdir}/handoff.md"

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"Codex 上下文 ${pct}% · 交接快照已备好，建议新开会话续接\" with title \"VFS Codex 监测\" sound name \"Submarine\"" >/dev/null 2>&1
  fi
done
exit 0
