# Safe Loop

安全的 Loop 生命周期管理器。

## 快速开始

```
/safe-loop "检查 CI 编译结果，有错就修直到全绿"
```

## 它能做什么

- **自动选模式**：根据任务描述判断用 `/loop`（定时轮询 CI/部署状态）还是 `/ralph-loop`（session 内迭代开发）
- **Git 保护分支**：启动前创建，隔离 AI 改动，结束后可选择保留或丢弃
- **自动取消**：cron 模式下，达成目标后自动 `CronDelete` 取消定时任务，不会一直跑

## 命令选项

```
/safe-loop <任务描述>
  --loop-type cron|ralph    手动指定模式（默认自动判断）
  --check-interval 5m         cron 检查间隔（默认 5m）
  --max-iterations 20         最大迭代次数
  --completion-promise "TEXT" ralph-loop 完成标记
```

## 示例

```bash
# CI 自动修复
/safe-loop "检查 CI 直到全绿，有错自动修"

# 重构（ralph 模式）
/safe-loop "重构缓存层" --loop-type ralph --completion-promise "ALL TESTS PASS"

# 部署监控
/safe-loop "每 2 小时检查部署状态" --check-interval 2h
```

## 不需要什么

- 不需要 Docker
- 不需要 sbx
- 只需 Git——保护分支用 `git checkout -b` 实现，翻车了 `git checkout` 回去
