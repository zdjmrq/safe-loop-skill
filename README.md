# Safe Loop

安全的 Loop 生命周期管理器。在启动循环任务前提供环境保护和生命周期管理。

## 能做什么

- **自动选模式**：根据任务判断用 `/loop`（定时轮询外部状态）还是 `/ralph-loop`（session 内迭代开发），不确定时会问你
- **Git 保护分支**：启动时创建，隔离 AI 的改动，结束后可保留或丢弃
- **自动取消**：cron 模式下将完成检测逻辑注入定时 prompt，达成目标后自行销毁，不会一直跑下去

## 依赖

只需 Git。不依赖 Docker 或 sbx。

## 使用

```
/safe-loop <任务描述> [选项]
```

| 选项 | 默认 | 说明 |
|------|------|------|
| `--loop-type cron\|ralph` | 自动判断 | 手动指定模式 |
| `--check-interval` | 5m | cron 模式检查间隔 |
| `--max-iterations` | 20 | 最大迭代次数 |
| `--completion-promise` | — | ralph-loop 完成标记 |

## 安装

```
mkdir -p ~/.claude/skills/safe-loop
cp SKILL.md ~/.claude/skills/safe-loop/
```
