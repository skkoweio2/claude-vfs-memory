---
description: 从 VFS 记忆与本会话工作区按主题召回相关内容
---

在 VFS 与记忆层中检索与「$ARGUMENTS」相关的内容，并把要点带回当前对话。

执行：
1. 用 Grep 在以下范围搜索关键词（含中文）：`~/.claude/memory/`（全局与本项目命名空间）、`~/.claude/vfs/sessions/`（各会话的 handoff.md、scratch/、large_tool_results/）。
2. 对命中的文件用 Read 取关键片段。
3. 用 3–6 条要点总结与「$ARGUMENTS」相关的已知结论/决策/产物，并标注来源文件路径。

若无命中，如实说明"VFS 中暂无相关记忆"，不要编造。
