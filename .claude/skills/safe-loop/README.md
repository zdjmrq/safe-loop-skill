# Safe Loop

安全的 Loop 生命周期管理器。在启动任何循环任务前提供环境保护和生命周期管理。

## v2 功能

- **自动模式选择**：根据任务描述判断用 `/loop`（定时轮询外部状态）还是 `/ralph-loop`（session 内迭代开发），不确定时询问用户
- **Git 保护分支**：启动时创建，结束后可选择保留合并或直接丢弃
- **完成自动取消**：cron 模式将完成检测逻辑注入定时 prompt，达成目标后通过 CronList+CronDelete 自毁
- **精简**：不依赖 Docker、不依赖 sbx，只需 Git

## 使用

```
/safe-loop <任务描述> [--loop-type cron|ralph] [--check-interval 5m] [--max-iterations N] [--completion-promise "TEXT"]
```

## 执行流程

```
① 环境检测 → ② Git 保护分支 → ③ Loop 类型选择 → ④ 用户确认 → ⑤ 注入完成逻辑并启动 → ⑥ 结束清理
```

## v1 → v2 变化

| | v1 | v2 |
|---|----|----|
| 模式 | 只支持 ralph-loop | cron + ralph 自动选 |
| 保护 | Docker/sbx 快照 + Git 分支 | 仅 Git 分支 |
| 完成 | 手动 | cron 模式自动 CronDelete |
| 体积 | ~580 行 | ~210 行 |
| 依赖 | 需要 Docker/sbx | 只需 Git |
