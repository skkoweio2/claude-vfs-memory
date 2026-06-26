---
description: 手动把上一个大输出卸载到 VFS 磁盘，给上下文减负
---

把本对话中最近一次的大段工具输出/长内容卸载到当前会话的 VFS 工作区。

执行：
1. 定位当前会话 VFS 目录：`~/.claude/vfs/sessions/` 下 mtime 最新的目录。
2. 用 Write 把要卸载的完整内容存到该目录的 `large_tool_results/manual-<序号>-<简述>.txt`。
3. 之后在对话中只保留一段简短摘要 + 该文件路径；需要完整内容时再 Read 取回。

附加说明：$ARGUMENTS（可指定要卸载的是哪段内容）。
