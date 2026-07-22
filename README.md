# Safe Loop

安全的 Loop 生命周期管理器。在启动任何需要反复执行直到完成的任务时，全程提供环境保护和生命周期管理。

## 解决什么问题

Claude Code 内置了两种循环机制——`/loop`（定时 cron）和 `/ralph-loop`（session 内迭代），但它们缺少统一的启动流程、保护措施和自动停止机制。Safe Loop 补上这一层：

- 你不需要自己判断用哪种 loop
- 你不需要手动取消跑完了的定时任务
- 万一 AI 改坏了代码，有 git 分支可以回滚

## 功能

### 自动模式选择

分析你的任务描述，自动推荐最合适的 loop 类型：

| 任务特征 | 选择 | 原理 |
|----------|------|------|
| 提到监控、检查、轮询、CI、部署状态等 | `/loop`（cron 定时） | 外部状态在变化，需要每隔一段时间重新检查 |
| 提到修复、重构、开发、写代码等 | `/ralph-loop`（迭代） | 在同一 session 内反复改文件，逐步完善 |
| 两种特征都有 | `/loop` | "检查并修复"场景，优先外部轮询 |
| 无法判断 | 问你 | 不猜，让你选 |

你也可以用 `--loop-type` 手动指定。

### Git 保护分支

启动前自动从当前分支创建一个保护分支。AI 的所有改动都在这个分支上进行，原始分支不受影响。

任务结束后你决定：
- **保留**：合并回原始分支
- **丢弃**：切回原始分支，删除保护分支，代码完全不变

不需要 Docker、不需要 sbx，只需 Git。

### 自动取消（cron 模式）

这是 Safe Loop 区别于直接使用 `/loop` 的关键功能。

启动时，Safe Loop 会把完成检测逻辑**注入到定时任务的 prompt 里**。每轮 cron 触发时，AI 会先检查目标是否已达成（比如 CI 通过了），如果达成了就调用 `CronDelete` 自行销毁，loop 自动结束。你不会留下一堆忘了关的定时任务。

### 用户确认

启动前展示完整摘要——项目路径、保护分支名、loop 类型、完成条件——必须你确认后才执行。不会静默创建 cron 任务。

## 六步执行流程

```
① 环境检测
   检查 Git/Docker/sbx 状态，确定能用什么保护措施

② Git 保护分支
   从当前分支创建 safe-loop-时间戳-原分支名 分支

③ Loop 类型选择
   分析任务描述，推荐 cron 或 ralph，等你确认

④ 确认摘要
   展示完整配置，等你确认

⑤ 构造 prompt 并启动
   cron: 把完成检测+CronDelete 逻辑注入 prompt，创建定时任务
   ralph: 调用 ralph-loop 插件

⑥ 清理恢复
   结束后展示结果，你选择保留修改还是丢弃
```

## 命令参考

```
/safe-loop <任务描述> [选项]
```

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--loop-type cron\|ralph` | 自动判断 | 手动指定 loop 类型 |
| `--check-interval <N>m\|h` | 5m | cron 模式的检查间隔 |
| `--max-iterations <N>` | 20 | 最大迭代次数或 cron 触发次数 |
| `--completion-promise "<TEXT>"` | 无 | ralph-loop 完成标记，AI 达成时输出 `<promise>TEXT</promise>` 结束循环 |

## 使用示例

```bash
# 等 CI 通过——自动选 cron 模式，通过后自动取消
/safe-loop "检查 CI 编译结果，有错就修直到全绿"

# 每 2 小时检查一次——调整间隔
/safe-loop "检查部署是否成功" --check-interval 2h

# 迭代开发——指定 ralph 模式
/safe-loop "重构某个模块" --loop-type ralph --completion-promise "ALL TESTS PASSING"
```

## 安装

```bash
mkdir -p ~/.claude/skills/safe-loop
cp SKILL.md ~/.claude/skills/safe-loop/
```

## 依赖

- Git（必需）

不需要 Docker 或 sbx。
