---
name: safe-ralph-loop
description: Safe Ralph Loop — 安全 Loop 执行器。环境检测、保护分支/快照、自动选择 /loop 或 /ralph-loop、达成目标自动取消。每次 loop 任务前必须调用。
user_invocable: true
---

# Safe Ralph Loop v2

安全的 loop 生命周期管理器。核心职责：**保护环境 → 选对 loop 类型 → 启动 → 完成自动取消**。

```
① 环境检测 → ② 保护措施 → ③ Loop 选择 → ④ 启动执行 → ⑤ 完成取消 → ⑥ 清理恢复
```

## 使用方式

```
/safe-ralph-loop <prompt> [--loop-type cron|ralph] [--check-interval 5m] [--max-iterations N] [--completion-promise "TEXT"]
```

| 参数 | 默认 | 说明 |
|------|------|------|
| prompt | 必填 | 任务描述 |
| --loop-type | 自动判断 | cron（外部轮询）或 ralph（迭代开发） |
| --check-interval | 5m | cron 模式的检查间隔 |
| --max-iterations | 20 | 最大迭代次数 |
| --completion-promise | — | ralph-loop 完成标记字符串 |

示例：
```
/safe-ralph-loop "检查 CI 编译结果，有错就修直到全绿"
/safe-ralph-loop "重构缓存层" --loop-type ralph --completion-promise "ALL TESTS PASSING"
/safe-ralph-loop "每 2 小时检查一次部署状态" --check-interval 2h
```

---

## 我的执行步骤

### 第一步：环境检测

检测 Docker、sbx、Git 状态，确定保护等级。

```bash
docker --version 2>/dev/null && echo "DOCKER_AVAILABLE" || echo "DOCKER_UNAVAILABLE"
sbx ls 2>/dev/null && echo "SBX_AVAILABLE" || echo "SBX_UNAVAILABLE"
git rev-parse --git-dir 2>/dev/null && echo "GIT_OK" || echo "NOT_GIT"
```

| sbx | Docker | Git | 保护等级 |
|---|---|---|---|
| ✅ | any | any | 🟢 sbx 沙箱 |
| ❌ | ✅ | ✅ | 🟢 Docker + Git |
| ❌ | ✅ | ❌ | 🟡 Docker 快照 |
| ❌ | ❌ | ✅ | 🟡 纯 Git 分支 |
| ❌ | ❌ | ❌ | 🔴 无保护 |

> Windows 含中文路径时 sbx 可能挂载失败 → 自动降级到 Docker/Git 方案。

向用户报告检测结果。

---

### 第二步：保护措施

#### 2.1 创建 Git 保护分支

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BRANCH_NAME="safe-ralph-${TIMESTAMP}-${CURRENT_BRANCH}"

git stash push -m "safe-ralph-auto-stash-${TIMESTAMP}" --include-untracked 2>/dev/null || true
git checkout -b "${BRANCH_NAME}"
```

#### 2.2 创建快照（可回滚）

```bash
# sbx 可用 → 用 sbx 创建沙箱快照
sbx create shell --name "ralph-backup-${TIMESTAMP}" --cpus 1 --memory 2g "$(pwd)" 2>/dev/null

# 回退到 Docker volume 快照
docker volume create "ralph-backup-${TIMESTAMP}" 2>/dev/null
docker run --rm -v "$(pwd):/workspace:ro" -v "ralph-backup-${TIMESTAMP}:/backup" alpine:latest \
  sh -c "cd /workspace && tar czf /backup/snapshot.tar.gz \
    --exclude=node_modules --exclude=.git --exclude=target \
    --exclude=__pycache__ --exclude=.venv --exclude=venv \
    --exclude=dist --exclude=build ."
```

> 详细 sbx/Docker 操作见记忆文件 [[sbx-setup]] 和 [[sbx-handover]]。

---

### 第三步：Loop 类型选择（核心新增）

根据 prompt 特征判断用哪种 loop：

**判断逻辑**（按关键词匹配）：

| 关键词 | 推荐 | 原因 |
|--------|------|------|
| CI、检查、监控、轮询、部署、状态 | `cron` | 外部状态变化，需定时重启 session 检查 |
| 修复、重构、开发、实现、写代码 | `ralph` | 同一 session 内迭代改文件 |

默认推断规则：prompt 中提到外部系统状态 → cron；提到代码修改 → ralph。

**向用户展示推断结果并确认**，用户可用 `--loop-type` 覆盖。

#### 3.1 cron 模式（/loop）

用于外部状态轮询：CI 监控、部署检查、PR 状态。

```
操作:
  1. CronCreate:
     cron: "根据 --check-interval 计算"
     prompt: "<原始 prompt>"
     recurring: true

  2. 记录 cron_job_id 到对话状态（稍后用于取消）

  3. 立即执行第一次检查
```

检查间隔规则：
- `--check-interval 5m` → 使用避开整点的分钟值（如 `7-57/5`）
- `--check-interval 2h` → `7 */2 * * *`
- 默认 5m

#### 3.2 ralph 模式（/ralph-loop）

用于代码迭代：修 bug、重构、功能开发。

```
操作:
  1. 调 Skill("ralph-loop:ralph-loop", "<prompt> --max-iterations N --completion-promise 'TEXT'")

  2. ralph-loop 自行管理生命周期（Stop Hook 拦截、检测 <promise> 标签）

  3. ralph-loop 结束后 → 直接进入第六步清理恢复
```

> ralph 模式不需要"完成检测"步骤（第五步），因为 ralph-loop 自带完成机制。

---

### 第四步：确认并启动

向用户展示摘要，必须确认：

```
🛡️ Safe Ralph Loop — 确认摘要

  📂 项目: <路径>
  📋 任务: <prompt>
  🌿 保护分支: <分支名>
  🛡️ 保护等级: 🟢/🟡/🔴
  🔄 Loop 类型: cron / ralph
  ⏱ 检查间隔: <N>m（仅 cron）
  🔢 最大迭代: <N>
  🎯 完成条件: <completion-promise 或 "CI 全绿">

  确认启动？(y/N)
```

---

### 第五步：完成检测与自动取消（核心新增，仅 cron 模式）

cron 模式下，每轮 loop 触发时：

```
① 检查目标状态（CI 结果、部署状态等）

② 判断是否满足完成条件：
   ✅ 达成 → CronDelete(cron_job_id) → 报告 → 进入第六步
   ❌ 未达成 → 继续修复/等待 → 下一轮
```

**完成条件判断方式**：根据 prompt 推断并在确认摘要中明确。例如：
- "CI 通过" → 查 GitHub Actions API，`conclusion == "success"`
- "部署成功" → 查部署状态
- "PR 已合并" → 查 PR status

**自动取消的操作**：
```
CronDelete("<cron_job_id>")
# 删除定时任务，loop 停止
```

---

### 第六步：清理恢复

Loop 结束后（自然完成 / 达到上限 / 用户取消），展示选项：

```
🔄 Loop 已结束

  🌿 保护分支: <分支名>
  📂 原始分支: <原始分支>
  📦 快照: ✅ / ❌
  🎯 完成状态: 已达成 / 未达成 / 用户取消

  [1] ✅ 保留修改 → 合并回原始分支，删快照
  [2] ❌ 全部回滚 → 从快照恢复，丢弃所有修改
  [3] 🤔 查看差异 → 看 diff 后决定
```

#### [1] 保留修改
```bash
git checkout "${CURRENT_BRANCH}"
git merge "${BRANCH_NAME}" --no-edit
git branch -D "${BRANCH_NAME}"
docker volume rm "ralph-backup-${TIMESTAMP}" 2>/dev/null || true
sbx rm "ralph-backup-${TIMESTAMP}" --force 2>/dev/null || true
```

#### [2] 全部回滚（二次确认后执行）
```bash
# 从快照恢复
docker run --rm -v "$(pwd):/workspace" -v "ralph-backup-${TIMESTAMP}:/backup" alpine:latest \
  sh -c "cd /workspace && tar xzf /backup/snapshot.tar.gz"
git checkout "${CURRENT_BRANCH}"
git branch -D "${BRANCH_NAME}"
docker volume rm "ralph-backup-${TIMESTAMP}" 2>/dev/null || true
```

---

## 关键规则

1. **启动前必须用户确认**，不可自动执行
2. **cron 模式必须记录 cron_job_id**，用于第五步自动取消
3. **ralph 模式的完成由自身 Stop Hook 处理**，无需额外检测
4. **回滚不可逆**，执行前二次确认
5. **保护分支从当前分支创建**，不硬编码 main/master
6. **sbx 不可用时自动降级**（sbx → Docker → 纯 Git）
7. **含中文路径时跳过 sbx**，直接走 Docker/Git
