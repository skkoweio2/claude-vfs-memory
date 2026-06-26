#!/bin/sh
# PreCompact hook：上下文压缩前抢救现场——快照 transcript + 生成 handoff.md，
# 供下次 SessionStart 注入，实现跨压缩/跨会话的任务续接。
. "$(dirname "$0")/_common.sh"
[ "$VFS_DISABLED" = "1" ] && exit 0

TRIGGER="$(vfs_get '.trigger')"
vfs_log "pre-compact trigger=$TRIGGER transcript=$TRANSCRIPT"

# 快照 transcript + 生成 handoff（逻辑见 _common.sh::vfs_write_handoff）
vfs_write_handoff "precompact:${TRIGGER}"
exit 0
