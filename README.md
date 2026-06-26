# claude-vfs-memory

**English** · [简体中文](./README.zh-CN.md)

A session-scoped **external virtual-file memory system** that fights **context loss and degradation** on long Claude Code tasks. Pure `sh` + `jq`, hooks-driven, **no hard third-party dependencies** (no claude-hud or other plugins required).

## What it does

| When | Behavior |
|------|----------|
| Tool output > 8KB (Bash/WebFetch/Grep) | Auto-offloads to disk and replaces it in context with a "summary + retrieval path", so one big dump can't blow up your window |
| Every user message | Recalls relevant files from persistent memory and the current session workspace by keyword, returning a path list for on-demand Read |
| Context ≥ 75% (computed from transcript usage; uses claude-hud's value if present) | Prepares an enhanced handoff and injects a one-line reminder to `/clear` or `/compact`. **Reminds only — never auto-opens a window or kills the session** |
| Before compaction / on session end (incl. `/clear`, exit) | Snapshots the transcript + generates an enhanced handoff (recent user intent, where you stopped, changed files, git state). A hand-written `/handoff` is never overwritten |
| New session via `clear`/`compact`/`resume` | Injects **only the current session's own** handoff to resume; cold starts inject nothing, so a fresh task is never polluted by an old context |
| Once daily (throttled, triggered on session end) | Cleans up session workspaces older than 90 days; **never touches `~/.claude/memory` persistent memory** |

Manual commands: `/vfs` status · `/recall <topic>` recall · `/offload` offload the last big output · `/handoff` write a handoff snapshot · `/save <points>` persist long-term memory.

## Dependencies

- `jq` (required; if missing, all hooks degrade to no-ops and never disrupt the session)
- `python3` (needed for CJK tokenization in recall; if missing, only recall quality is affected)
- `shasum` (bundled on macOS; used to read the claude-hud cache, optional)

## Install

**Option 1: marketplace (recommended for sharing)**
```
/plugin marketplace add skkoweio2/claude-vfs-memory
/plugin install claude-vfs-memory
```

**Option 2: local directory**
```
/plugin marketplace add /path/to/claude-vfs-memory
/plugin install claude-vfs-memory
```

Takes effect in a **new session**; hooks wire up automatically, no manual `settings.json` edits needed.

## Configuration (environment variables)

| Variable | Default | Meaning |
|----------|---------|---------|
| `VFS_HOME` | `~/.claude/vfs` | Data root (session workspaces, index, logs) |
| `VFS_CTX_THRESHOLD` | `75` | Context reminder threshold (%) |
| `VFS_CONTEXT_WINDOW` | auto | Window-size fallback when claude-hud is absent (e.g. set `1000000` for a 1M session) |
| `VFS_GC_DAYS` | `90` | Retention days for session workspaces |

## Codex CLI support (optional, installed separately)

Codex has no per-tool hooks, so a **launchd background daemon** (every 60s) scans active rollouts and, at ≥75%, writes a handoff + sends a macOS notification. **Reminds only — never opens a window.**

```
sh bin/codex-watch-ctl.sh install     # install and start
sh bin/codex-watch-ctl.sh status      # check status
sh bin/codex-watch-ctl.sh uninstall   # uninstall
```
Config: `CODEX_CTX_THRESHOLD` / `CODEX_CTX_IDLE_MIN` / `CODEX_CTX_COOLDOWN_MIN`.
Temporarily disable: `touch ~/.claude/vfs/codex-state/DISABLED`.

## Privacy

Handoffs and transcript snapshots write your **raw conversation** to local `~/.claude/vfs` (or `VFS_HOME`). **Local only, never sent anywhere.** To delete: just clear that directory.

## Uninstall

```
/plugin uninstall claude-vfs-memory
```
The data directory `~/.claude/vfs` is not auto-deleted; clean it up manually if you want. The Codex daemon is removed separately via `sh bin/codex-watch-ctl.sh uninstall`.

## License

Released under the [MIT License](./LICENSE) — free to use, modify, distribute, and use commercially; just retain the copyright and license notice.

> Provided "as is", without warranty of any kind. See [LICENSE](./LICENSE).

Copyright © 2026 skkoweio2

Issues / PRs welcome.
