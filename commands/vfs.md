---
description: 查看当前 VFS 会话状态（工作区、卸载产物、最近日志）
allowed-tools: Bash(ls:*), Bash(cat:*), Bash(find:*), Bash(tail:*), Bash(wc:*)
---

展示当前 VFS 状态。运行并汇总：

- 当前会话目录（mtime 最新）：`D=$(ls -dt ~/.claude/vfs/sessions/*/ 2>/dev/null | head -1); echo "$D"`
- manifest：`cat "$D/manifest.json" 2>/dev/null`
- 卸载产物清单：`ls -la "$D/large_tool_results/" 2>/dev/null`
- 草稿清单：`ls -la "$D/scratch/" 2>/dev/null`
- 是否已有交接快照：`ls -la "$D/handoff.md" 2>/dev/null`
- 最近 VFS 日志：`tail -15 ~/.claude/vfs/vfs.log 2>/dev/null`
- 历史会话条数：`wc -l ~/.claude/vfs/index/sessions.jsonl 2>/dev/null`

用简洁列表向我汇报：当前会话工作区路径、已卸载几个大输出、是否有交接快照、最近几条活动。
