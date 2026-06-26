# claude-vfs-memory

会话级**外置虚拟文件记忆系统**，对抗 Claude Code 长任务的**失忆与降智**。纯 `sh` + `jq` 实现，hooks 驱动，**无第三方硬依赖**（不需要 claude-hud 等插件）。

## 它做什么

| 时机 | 行为 |
|------|------|
| 工具输出 >8KB（Bash/WebFetch/Grep） | 自动落盘，上下文里替换为"摘要 + 取回路径"，防止单次大输出撑爆窗口 |
| 每条用户消息 | 按关键词从持久记忆与本会话工作区召回相关文件，给路径清单供按需 Read |
| 上下文 ≥ 75%（自读 transcript usage 算，claude-hud 有则优先用） | 备好加强版 handoff，并注入一行提醒建议 `/clear` 或 `/compact`。**只提醒，绝不自动开窗/停会话** |
| 压缩前 / 会话结束（含 `/clear`、退出） | 快照 transcript + 生成加强版 handoff（含最近用户意图、上次停在哪、改动文件、git 现场）。手写的 `/handoff` 不会被覆盖 |
| 新会话 `clear`/`compact`/`resume` | 仅注入【当前会话自己的】handoff 续接；冷启动不注入，杜绝新任务被旧现场干扰 |
| 每日一次（会话结束时节流触发） | 清理 90 天前的会话工作区；**绝不触碰 `~/.claude/memory` 持久记忆** |

手动命令：`/vfs` 看状态 · `/recall <主题>` 召回 · `/offload` 卸载上一段大输出 · `/handoff` 写交接快照 · `/save <要点>` 固化长期记忆。

## 依赖

- `jq`（必需；缺失则所有 hook 自动降级为 no-op，绝不影响会话）
- `python3`（recall 的中文分词需要；缺失只影响召回质量）
- `shasum`（macOS 自带；用于读 claude-hud 缓存，可选）

## 安装

**方式一：marketplace（推荐分享）**
```
/plugin marketplace add skkoweio2/claude-vfs-memory
/plugin install claude-vfs-memory
```

**方式二：本地目录**
```
/plugin marketplace add /path/to/claude-vfs-memory
/plugin install claude-vfs-memory
```

安装后在**新会话**生效，hooks 自动接线，无需手改 `settings.json`。

## 配置（环境变量）

| 变量 | 默认 | 含义 |
|------|------|------|
| `VFS_HOME` | `~/.claude/vfs` | 数据根目录（会话工作区、索引、日志） |
| `VFS_CTX_THRESHOLD` | `75` | 上下文提醒阈值（%） |
| `VFS_CONTEXT_WINDOW` | 自动 | 无 claude-hud 时的窗口大小回退（如 1M 会话设 `1000000`） |
| `VFS_GC_DAYS` | `90` | 会话工作区保留天数 |

## Codex CLI 支持（可选，单独安装）

Codex 没有 per-tool hook，所以用一个 **launchd 后台守护**（每 60s）扫描活跃 rollout，≥75% 时写 handoff + 发 macOS 通知。**同样只提醒、不开窗。**

```
sh bin/codex-watch-ctl.sh install     # 安装并启动
sh bin/codex-watch-ctl.sh status      # 查看状态
sh bin/codex-watch-ctl.sh uninstall   # 卸载
```
配置：`CODEX_CTX_THRESHOLD` / `CODEX_CTX_IDLE_MIN` / `CODEX_CTX_COOLDOWN_MIN`。
临时禁用：`touch ~/.claude/vfs/codex-state/DISABLED`。

## 隐私

handoff 与 transcript 快照会把**对话原文**落盘到本机 `~/.claude/vfs`（或 `VFS_HOME`）。**纯本地、不外传**。删除：清空该目录即可。

## 卸载

```
/plugin uninstall claude-vfs-memory
```
数据目录 `~/.claude/vfs` 不会被自动删除，按需手动清理。Codex 守护单独 `sh bin/codex-watch-ctl.sh uninstall`。

## License

MIT
