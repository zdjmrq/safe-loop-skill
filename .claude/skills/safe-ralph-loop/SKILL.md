---
name: safe-ralph-loop
description: >
  Safe Ralph Loop — 安全的 Loop 生命周期管理器。当你需要反复执行某个任务直到完成时，
  必须调用此 skill：CI 自动修复、部署状态轮询、bug 修复直到测试全绿、迭代重构、
  任何需要定时检查或循环执行的自动化任务。自动检测环境、创建 git 保护分支、
  根据任务特征选择 /loop（cron 轮询）或 /ralph-loop（迭代开发）、
  将完成条件注入定时任务中、达成目标后自动取消。每次用户说"循环""反复""直到"
  "轮询""定时检查""自动修复""监控状态""等 CI"时都应触发。
user_invocable: true
---

# Safe Ralph Loop v2

安全的 loop 生命周期管理器。核心职责：**保护 → 选择 → 启动 → 注入完成逻辑 → 自动结束**。

```
① 环境检测 → ② Git 保护分支 → ③ Loop 选择 → ④ 确认 → ⑤ 注入完成逻辑并启动 → ⑥ 结束清理
```

## 使用方式

```
/safe-ralph-loop <任务描述> [--loop-type cron|ralph] [--check-interval 5m] [--max-iterations N] [--completion-promise "TEXT"]
```

| 参数 | 默认 | 说明 |
|------|------|------|
| 任务描述 | 必填 | 要反复执行的任务 |
| --loop-type | 自动判断 | cron（外部轮询）或 ralph（迭代开发） |
| --check-interval | 5m | cron 模式的检查间隔 |
| --max-iterations | 20 | 最大迭代次数 |
| --completion-promise | — | ralph-loop 完成标记字符串 |

示例：
```
/safe-ralph-loop "检查 CI 编译结果，有错就修直到全绿"
/safe-ralph-loop "重构缓存层" --loop-type ralph --completion-promise "ALL TESTS PASSING"
/safe-ralph-loop "每 2 小时检查部署是否成功" --check-interval 2h
```

---

## 我的执行步骤

### 第一步：环境检测

```bash
git rev-parse --git-dir 2>/dev/null && echo "GIT_OK" || echo "NOT_GIT"
docker --version 2>/dev/null && echo "DOCKER_AVAILABLE" || echo "DOCKER_UNAVAILABLE"
sbx ls 2>/dev/null && echo "SBX_AVAILABLE" || echo "SBX_UNAVAILABLE"
```

| Git | 结果 |
|-----|------|
| ✅ | 🟢 正常——创建保护分支 |
| ❌ | ⚠️ 无 git——提示用户先 `git init` |

向用户报告。sbx/Docker 信息供参考，不作为硬性要求。

---

### 第二步：Git 保护分支

Loop 开始前创建一次，隔离 AI 的所有改动。loop 结束后合并或丢弃。

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BRANCH_NAME="safe-ralph-${TIMESTAMP}-${CURRENT_BRANCH}"

git stash push -m "safe-ralph-auto-stash-${TIMESTAMP}" --include-untracked 2>/dev/null || true
git checkout -b "${BRANCH_NAME}"
```

记录 `CURRENT_BRANCH`、`BRANCH_NAME`、`TIMESTAMP` 到对话状态，第六步清理时用。

---

### 第三步：Loop 类型选择

根据任务描述判断用哪种 loop。

**判断逻辑**：

| 特征 | 推荐 | 原因 |
|------|------|------|
| 提到 CI、检查、监控、轮询、部署、状态 | `cron` | 外部状态变化，需定时重启 session 检查 |
| 提到修复、重构、开发、实现、写代码 | `ralph` | 同一 session 内迭代改文件 |
| 两种特征都有 | `cron` | "检查并修复" → 优先外部轮询模式 |
| 无法判断 | **询问用户** | 不要猜，让用户选 |

**展示推断结果并确认**，用户可用 `--loop-type` 覆盖。

#### 3.1 cron 模式（/loop）

用于外部状态轮询。

→ **不直接开始工作**。而是：

1. 根据任务描述提炼出**完成条件**（例如 "CI conclusion == success"）
2. 构造一个完整的 cron prompt，**把完成检测和 CronDelete 逻辑写进去**
3. 创建 CronCreate 定时任务
4. 记录 cron_job_id

#### 3.2 ralph 模式（/ralph-loop）

用于同一 session 内迭代开发。

→ 调用 `Skill("ralph-loop:ralph-loop", args)`，ralph-loop 的 Stop Hook 自行检测 `<promise>` 标签完成。结束后直接进入第六步。

---

### 第四步：确认摘要

向用户展示，**必须确认后才执行**：

```
🛡️ Safe Ralph Loop — 确认摘要

  📂 项目: <路径>
  📋 任务: <任务描述>
  🌿 保护分支: <BRANCH_NAME>（原始: <CURRENT_BRANCH>）
  🔄 Loop 类型: cron（每 <N> 分钟）/ ralph（最多 <N> 轮）
  🎯 完成条件: <具体条件>

  确认启动？(y/N)
```

---

### 第五步：构造 prompt 并启动（核心）

这是 skill 最重要的工作——**把完成检测逻辑注入到定时任务的 prompt 里**。

#### cron 模式：构造定时 prompt

CronCreate 的 prompt 必须包含以下结构：

```
<用户原始任务描述>

## 你的执行流程

1. 检查目标状态（CI 结果、部署状态等）
2. 判断完成条件是否满足：
   - ✅ 完成条件: <具体可验证的条件>
   - 如果满足 → CronDelete("<cron_job_id>") → 报告完成 → 结束
   - 如果不满足 → 执行必要的修复操作 → 等待下一轮
3. 如果已达成最大迭代次数仍未完成 → 报告情况 → CronDelete("<cron_job_id>")
```

然后：

```
CronCreate(
  cron: "<根据 --check-interval 计算>",
  prompt: "<上面构造的完整 prompt>",
  recurring: true
)
```

记录返回的 cron_job_id。**立即执行一次首次检查**。

#### ralph 模式：直接调 ralph-loop

```
Skill("ralph-loop:ralph-loop", "<任务描述> --max-iterations <N> --completion-promise '<TEXT>'")
```

ralph-loop 结束后进入第六步。

---

### 第六步：清理恢复

Loop 结束后展示：

```
🔄 Loop 已结束

  🌿 保护分支: <BRANCH_NAME>
  📂 原始分支: <CURRENT_BRANCH>
  🎯 完成状态: 已达成 / 未达成

  [1] ✅ 保留修改 → 合并回 <CURRENT_BRANCH>，删除保护分支
  [2] ❌ 全部丢弃 → 切回 <CURRENT_BRANCH>，删除保护分支
```

**保留修改**：
```bash
git checkout "${CURRENT_BRANCH}"
git merge "${BRANCH_NAME}" --no-edit
git branch -D "${BRANCH_NAME}"
```

**全部丢弃**：
```bash
git checkout "${CURRENT_BRANCH}"
git branch -D "${BRANCH_NAME}"
```

---

## 关键规则

1. **启动前必须用户确认**
2. **cron 的 prompt 必须包含 CronDelete 自毁逻辑**——这是实现"达成目标自动取消"的唯一方式
3. **ralph 模式不需要手动注入完成逻辑**——Stop Hook 自带
4. **保护分支只创建一次**——loop 开始时，不是每次迭代
5. **不确定选哪种 loop 时，问用户**——不要猜
