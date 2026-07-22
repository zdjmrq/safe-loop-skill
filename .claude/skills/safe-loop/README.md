# Safe Loop

安全的 Loop 生命周期管理器。

## 使用

```
/safe-loop <任务描述> [--loop-type cron|ralph] [--check-interval 5m] [--max-iterations N]
```

## 功能

- 自动选 `/loop`（定时轮询）或 `/ralph-loop`（迭代开发）
- Git 保护分支，结束后可保留或回滚
- 达成目标自动取消

## 示例

```bash
/safe-loop "等部署完成后通知我"
/safe-loop "重构某个模块" --loop-type ralph
```
