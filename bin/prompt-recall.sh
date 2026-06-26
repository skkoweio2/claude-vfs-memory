#!/bin/sh
# UserPromptSubmit hook：按用户 prompt 关键词，从持久记忆与本会话工作区召回相关文件，
# 以"路径清单 + 极短摘要"形式注入，让 Claude 按需 Read（不灌大段内容，控制在数 KB）。
# 必须快（默认超时 30s）：只做 grep -l，命中即列路径。
. "$(dirname "$0")/_common.sh"
[ "$VFS_DISABLED" = "1" ] && exit 0

PROMPT="$(vfs_get '.prompt')"
[ -z "$PROMPT" ] && exit 0

# 提取关键词：ASCII 词(>=3 字母数字) + 中文二元组(bigram)，去停用词，最多 14 个。
# 用 python3 做 UTF-8 安全分词（tr 无法对无空格的中文正确切词）。
KW="$(printf '%s' "$PROMPT" | python3 -c '
import sys,re
t=sys.stdin.read().lower()
stop=set("the and for you are this that with have how what can please 帮我 一下 怎么 什么 多少 这个 那个 可以".split())
out=[]
for w in re.findall(r"[a-z0-9_]{3,}", t):
    if w not in stop: out.append(w)
for run in re.findall(r"[一-鿿]+", t):
    if len(run)<2:
        continue
    for i in range(len(run)-1):
        bg=run[i:i+2]
        if bg not in stop: out.append(bg)
seen=[]
for w in out:
    if w not in seen: seen.append(w)
print("\n".join(seen[:14]))
' 2>/dev/null)"
[ -z "$KW" ] && exit 0

# 搜索范围：本项目持久记忆 + 全局 memory 顶层 + 本会话 scratch/卸载索引
SEARCH_DIRS=""
[ -d "$PROJ_MEM" ] && SEARCH_DIRS="$SEARCH_DIRS $PROJ_MEM"
[ -d "$VFS_MEM" ] && SEARCH_DIRS="$SEARCH_DIRS $VFS_MEM"
[ -d "${SESSION_DIR}/scratch" ] && SEARCH_DIRS="$SEARCH_DIRS ${SESSION_DIR}/scratch"
[ -d "${SESSION_DIR}/large_tool_results" ] && SEARCH_DIRS="$SEARCH_DIRS ${SESSION_DIR}/large_tool_results"
[ -z "$SEARCH_DIRS" ] && exit 0

# 逐关键词 grep，收集命中文件（去重），最多 8 个
HITS="$(for k in $KW; do
  grep -rilm1 -- "$k" $SEARCH_DIRS 2>/dev/null
done | sort -u | head -8)"
[ -z "$HITS" ] && exit 0

LIST="$(printf '%s\n' "$HITS" | while IFS= read -r f; do
  [ -f "$f" ] || continue
  # 摘要优先取 frontmatter 的 description: 字段；取不到再回退第一条有内容的行
  # （跳过 frontmatter 分隔符 --- 与空行，避免 memory 文件摘要显示成无意义的 "---"）
  sum="$(awk '/^description:[[:space:]]*/{sub(/^description:[[:space:]]*/,"");print;exit}' "$f" 2>/dev/null)"
  [ -z "$sum" ] && sum="$(grep -m1 -vE '^(---[[:space:]]*$|[[:space:]]*$)' "$f" 2>/dev/null)"
  sum="$(printf '%s' "$sum" | cut -c1-80)"
  printf -- '- %s — %s\n' "$f" "$sum"
done)"
[ -z "$LIST" ] && exit 0

vfs_log "recall kw=[$(printf '%s' "$KW" | tr '\n' ' ')] hits=$(printf '%s' "$HITS" | wc -l | tr -d ' ')"

emit_context "UserPromptSubmit" "## 🔎 VFS 召回：可能相关的已存记忆/产物（按需 Read 取用）
${LIST}"
exit 0
