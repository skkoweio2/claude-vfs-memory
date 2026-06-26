---
description: 把要点固化为长期记忆（写入 ~/.claude/memory 并登记索引）
---

将「$ARGUMENTS」固化为一条长期记忆，遵循现有记忆约定（单事实单文件 + frontmatter + MEMORY.md 索引）。

执行：
1. 判断归属：与本项目强相关 → `~/.claude/memory/<项目名>/`；通用偏好/事实 → `~/.claude/memory/`。
2. 先检查是否已有覆盖同一事实的文件，有则更新而非新建。
3. 用 Write 写记忆文件，frontmatter 含 `name`、`description`、`metadata.type`（user|feedback|project|reference），正文为该事实；相关项用 `[[name]]` 互链。
4. 在对应的 `MEMORY.md` 追加一行索引指针。
5. 告诉我写到了哪个文件。

不要保存代码结构/git 历史能体现的内容；只保存非显而易见、对未来会话有用的事实。
