# Safe Ralph Loop

安全的 Ralph Loop 执行器 — 自动检测 Docker Sandbox (sbx) 环境，提供沙箱/容器化建议，执行 Docker 快照备份 + git 保护分支，结束后提供保留/回滚选项并自动清理残留。

## 功能

- **环境检测**：自动检测 sbx、Docker、Git 环境，确定保护等级
- **沙箱/容器决策**：根据可用环境推荐最优隔离方案
- **三层保护**：sbx 沙箱 > Docker 快照 > git 分支保护
- **自动清理**：结束后自动清理残留

## 安装

将 `SKILL.md` 放入 Claude Code 的 skills 目录：
```
C:\Users\<用户名>\.claude\skills\safe-ralph-loop\SKILL.md
```

## 使用

```
/safe-ralph-loop <prompt> [--max-iterations N] [--completion-promise "TEXT"]
```

## 依赖

- Docker Desktop（可选，用于 Docker 快照保护）
- Docker Sandbox (sbx)（可选，用于沙箱隔离保护）
- Git（必需，用于分支保护）

## License

MIT
