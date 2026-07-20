---
name: safe-ralph-loop
description: Safe Ralph Loop - 安全的 Ralph Loop 执行器。自动检测 Docker、Docker Sandbox (sbx) 与容器环境状态，提供沙箱/容器化建议，执行 sbx 沙箱隔离 / Docker 快照 / git 保护分支，结束后提供保留/回滚选项并自动清理残留。每次使用 ralph-loop 时都应调用此 skill 提供完整保护。使用 /safe-ralph-loop 调用。
---

# Safe Ralph Loop

ralph-loop 的安全保护层。每次使用 ralph-loop 时，自动执行完整保护流程：

```
① 环境检测 → ② 容器决策 → ③ 预检确认 → ④ 执行保护 → ⑤ 清理恢复
```

## 使用方式

### 启动带保护的 ralph-loop

```
/safe-ralph-loop <prompt> [--max-iterations N] [--completion-promise "TEXT"]
```

示例：
```
/safe-ralph-loop "修复登录页的 bug" --max-iterations 10 --completion-promise "ALL TESTS PASSING"
/safe-ralph-loop "重构缓存层" --max-iterations 5
/safe-ralph-loop "把 Python 脚本转成 Rust 实现"
```

### 手动恢复（翻车时用）

```
/ralph-recover
```

---

## 我的执行步骤

### 第一步：环境检测

#### 1.1 检测 Docker 状态

```bash
# Docker 是否可用
docker --version 2>/dev/null && echo "DOCKER_AVAILABLE" || echo "DOCKER_UNAVAILABLE"

# 是否已在 Docker 容器内
test -f /.dockerenv 2>/dev/null && echo "IN_CONTAINER_YES" || echo "IN_CONTAINER_NO"

# 备用检测
if grep -qE 'docker|lxc|containerd' /proc/1/cgroup 2>/dev/null; then echo "IN_CONTAINER_YES"; fi
```

#### 1.2 检测 sbx (Docker Sandbox) 状态

```bash
# sbx CLI 是否可用
sbx ls 2>/dev/null && echo "SBX_AVAILABLE" || echo "SBX_UNAVAILABLE"

# 是否已在 sbx 沙箱中
# sbx 沙箱本质是 Docker 容器，通过 /.dockerenv 和 SBX_ 环境变量双重检测
if test -f /.dockerenv 2>/dev/null; then
  if env | grep -q SBX_ 2>/dev/null; then
    echo "IN_SBX_YES"
  else
    echo "IN_SBX_NO"
  fi
else
  echo "IN_SBX_NO"
fi

# 列出当前 sbx 沙箱（用于后续清理追踪）
sbx ls --quiet 2>/dev/null || sbx ls 2>/dev/null | tail -n +2 || echo "SBX_NO_SANDBOXES"
```

#### 1.3 检测 Git 状态

```bash
# 是否在 git 仓库
git rev-parse --git-dir 2>/dev/null && echo "GIT_OK" || echo "NOT_GIT"

# 检测默认分支名
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@')
echo "DEFAULT_BRANCH:${DEFAULT_BRANCH:-main}"

# 当前分支
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
echo "CURRENT_BRANCH:${CURRENT_BRANCH}"

# 工作区是否干净
git status --porcelain 2>/dev/null | wc -l | xargs echo "UNCOMMITTED_CHANGES:"
```

#### 1.4 确定保护等级

| sbx | Docker | Git | 保护等级 | 说明 |
|---|---|---|---|---|
| ✅ | any | ✅ | 🟢 **完整** | **sbx 沙箱隔离优先** + git 分支保护 |
| ✅ | any | ❌ | 🟢 **完整** | **sbx 沙箱隔离优先**（推荐先 git init 但非必须） |
| ❌ | ✅ | ✅ | 🟢 **完整** | Docker 快照 + git 分支保护 |
| ❌ | ✅ | ❌ | 🟡 **部分** | 仅 Docker 快照（推荐先 git init） |
| ❌ | ❌ | ✅ | 🟡 **降级** | 仅 git 分支保护 |
| ❌ | ❌ | ❌ | 🔴 **无保护** | 强烈建议中止 |

检测优先级：**sbx > Docker > 纯 git**。sbx 可用时自动优先采用 sbx 沙箱方案。

向用户报告检测结果和保护等级。

---

### 第二步：容器决策

**核心原则：** 这一步是提供信息和建议，不代替用户做决定。

#### 场景 A：已在 Docker 容器内（含 sbx 沙箱）

检测并报告以下信息，然后直接进入第三步：

```bash
# 容器基本信息
echo "CONTAINER_ID:$(hostname 2>/dev/null)"

# 卷挂载信息
mount | grep -E '^/dev/' | head -5 2>/dev/null || true

# API 密钥
test -n "$ANTHROPIC_API_KEY" && echo "API_KEY:YES" || echo "API_KEY:NO"

# sbx 沙箱检测
env | grep SBX_ 2>/dev/null && echo "SBX_SANDBOX:YES" || echo "SBX_SANDBOX:NO"
```

向用户展示：
```
📦 已在 Docker 容器内运行

  🆔 容器 ID: <hostname>
  📂 工作目录: <pwd>
  🔗 卷挂载: <挂载信息>
  🔑 API 密钥: ✅/❌
  🌿 Git: ✅/❌
  🏖️ sbx 沙箱: ✅/❌

  💡 容器内操作提示：
    1. 修改的文件是否持久化取决于卷挂载配置，确认后再开始
    2. 建议经常 git commit，防止容器意外退出导致代码丢失
    3. 退出容器后如需保存工作，用 docker commit 保存镜像
    4. 现有 git 保护分支机制在容器内同样有效
    5. sbx 沙箱内已有环境隔离，Docker 快照步骤自动跳过
```

然后直接进入**第三步**。

#### 场景 B：Docker Desktop 可用 / sbx 可用，但未在容器内

```
🐳 Docker / sbx 可用（当前未在容器内）

  💡 对于风险较高的 ralph-loop 任务，在沙箱中执行
     可获得更好的环境隔离（文件系统隔离、依赖隔离）。

  检测到以下可用沙箱方案：
```

- **sbx 可用（推荐）**：Docker Sandbox 提供 microVM 级隔离，会自动注入 API 凭证。
- **Docker 容器**：标准 Docker 容器隔离。

**sbx 方案——用户选「是」：**

提供 sbx 启动命令（因为 Claude Code 会话本身无法透明迁移到沙箱中），然后告知用户进入沙箱后重新执行：

```
请在终端中执行以下命令进入 sbx 沙箱，
然后在沙箱内重新运行 /safe-ralph-loop：

cd "D:\AI工作区\Claude Code CLI工作区"
$env:HTTPS_PROXY="http://127.0.0.1:7897"
sbx run claude --kit deepseek-kit

# 进入沙箱后，Claude Code 会自动启动，
# 在沙箱内重新输入 /safe-ralph-loop 继续
```

> **注意**：sbx 沙箱会通过 kit 的 credential injection 自动注入 API 密钥，
> 无需手动设置 `ANTHROPIC_API_KEY`。kit 文件：`deepseek-kit/spec.yaml`

**然后终止当前 safe-ralph-loop 流程。**

**Docker 方案——用户选「是」：**

```
请在终端中执行以下命令进入 Docker 容器，
然后在容器内重新运行 /safe-ralph-loop：

docker run -it --rm \
  -v "/当前项目路径:/workspace" \
  -w /workspace \
  -e ANTHROPIC_API_KEY \
  -e ANTHROPIC_BASE_URL \
  node:20-slim bash

# 进入容器后安装 Claude Code 并重新运行
```

**然后终止当前 safe-ralph-loop 流程。**

- **用户选「否」**或默认超时：继续在宿主机上执行完整保护流程。

#### 场景 C：Docker 和 sbx 均不可用

```
⚠️ Docker 和 sbx 均未安装或不可用
   已自动降级为「纯 git 分支保护」模式，无法提供文件级快照恢复。
```

继续执行后续步骤，跳过 Docker/sbx 快照备份。

---

### 第三步：预检与确认

#### 3.1 解析参数

从用户的命令中提取参数。如果用户未提供，逐个询问：

| 参数 | 默认值 | 说明 |
|---|---|---|
| prompt | **必填** | 精确描述需要完成的任务 |
| --max-iterations | 10 | 最大循环迭代次数 |
| --completion-promise | 无（选填） | 可验证的完成条件 |

> 建议用户提供精确、可验证的完成条件，让 ralph-loop 在达成目标时自动停止。示例：`"ALL TESTS PASSING"`、`"BUILD_SUCCESS"`、`"NO_ERRORS"`。

#### 3.2 确认摘要

**必须获得用户明确确认后才能继续。**

```
🛡️ Safe Ralph Loop - 预检摘要

  📂 项目路径: <当前路径>
  📋 工作需求: <prompt>
  🌿 当前分支: <当前分支名>
  🛡️ 保护等级: <等级>
  🐳 沙箱方案: sbx / Docker / 纯 git
  🔄 最大迭代: <N> 次
  🎯 完成条件: <promise 或无>

  确认启动 ralph-loop？(y/N)
```

---

### 第四步：执行保护

#### 4.1 创建保护分支

```bash
# 记录当前状态
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BRANCH_NAME="safe-ralph-${TIMESTAMP}-${CURRENT_BRANCH}"

echo "🌿 创建保护分支: ${BRANCH_NAME}"

# 暂存未提交修改（包括未跟踪文件）
git stash push -m "safe-ralph-auto-stash-${TIMESTAMP}" --include-untracked 2>/dev/null || true

# 从当前分支创建保护分支
git checkout -b "${BRANCH_NAME}"

# 记录元数据
echo "META_BRANCH:${BRANCH_NAME}"
echo "META_ORIGIN:${CURRENT_BRANCH}"
echo "META_TIMESTAMP:${TIMESTAMP}"
```

#### 4.2 创建快照备份

优先使用 sbx 快照，不可用时回退到 Docker 快照。

**sbx 快照模式（sbx 可用时）：**

```bash
if sbx ls >/dev/null 2>&1; then
  echo "📦 使用 sbx 沙箱创建项目快照..."
  
  # 在当前目录启动一个 sbx shell 沙箱来做备份
  BACKUP_NAME="ralph-backup-${TIMESTAMP}"
  
  # 用 sbx 创建备份容器，将当前项目打包
  # sbx 的 microVM 隔离确保备份过程不影响宿主机
  docker run --rm \
    -v "$(pwd):/workspace:ro" \
    alpine:latest \
    sh -c "
      cd /workspace
      tar czf /tmp/project-snapshot.tar.gz \
        --exclude=node_modules \
        --exclude=.git \
        --exclude=target \
        --exclude=__pycache__ \
        --exclude=.claude \
        --exclude=.venv \
        --exclude=venv \
        --exclude=dist \
        --exclude=build \
        .
      # 输出到 stdout，sbx 可以捕获
      cat /tmp/project-snapshot.tar.gz
    " > "$(pwd)/.safe-ralph-snapshot-${TIMESTAMP}.tar.gz" 2>/dev/null || {
      # 如果 stdout 重定向失败，尝试用临时 Docker volume
      docker volume create "${BACKUP_NAME}" >/dev/null 2>&1
      docker run --rm \
        -v "$(pwd):/workspace:ro" \
        -v "${BACKUP_NAME}:/backup" \
        alpine:latest \
        sh -c "
          cd /workspace
          tar czf /backup/project-snapshot.tar.gz \
            --exclude=node_modules --exclude=.git \
            --exclude=target --exclude=__pycache__ \
            --exclude=.claude --exclude=.venv \
            --exclude=venv --exclude=dist --exclude=build .
        "
      echo "META_SBX_VOLUME:${BACKUP_NAME}"
    }
  echo "📦 sbx 快照创建完成"
else
  echo "sbx 不可用，回退到 Docker 快照..."
  # 回退到 Docker 快照（原有逻辑）
fi
```

**Docker 快照模式（sbx 不可用时回退）：**

```bash
if docker --version >/dev/null 2>&1; then
  BACKUP_VOLUME="ralph-backup-${TIMESTAMP}"
  
  # 避免卷名冲突
  while docker volume inspect "${BACKUP_VOLUME}" >/dev/null 2>&1; do
    BACKUP_VOLUME="ralph-backup-${TIMESTAMP}-$RANDOM"
  done
  
  docker volume create "${BACKUP_VOLUME}" >/dev/null
  echo "📦 正在创建 Docker 快照备份..."
  
  docker run --rm \
    -v "$(pwd):/workspace:ro" \
    -v "${BACKUP_VOLUME}:/backup" \
    alpine:latest \
    sh -c "
      cd /workspace
      tar czf /backup/project-snapshot.tar.gz \
        --exclude=node_modules \
        --exclude=.git \
        --exclude=target \
        --exclude=__pycache__ \
        --exclude=.claude \
        --exclude=.venv \
        --exclude=venv \
        --exclude=dist \
        --exclude=build \
        .
    "
  
  # 验证备份完整性
  docker run --rm \
    -v "${BACKUP_VOLUME}:/backup" \
    alpine:latest \
    sh -c "tar tzf /backup/project-snapshot.tar.gz >/dev/null 2>&1 && echo 'BACKUP_VERIFIED' || echo 'BACKUP_FAILED'"
  
  echo "META_VOLUME:${BACKUP_VOLUME}"
fi
```

> 使用 `:ro`（只读挂载）防止备份过程中意外修改源代码。
> sbx 可用时优先使用 sbx 方案，Docker 快照作为回退。

#### 4.3 启动 ralph-loop

用户确认后，通过 Skill 工具调用 ralph-loop：

```
/ralph-loop "<prompt>" --max-iterations <N> --completion-promise "<promise>"
```

**等待 ralph-loop 完成后**再进入下一步清理。

---

### 第五步：清理恢复

ralph-loop 结束后（自然结束 / 达成目标 / 用户取消），执行清理。

#### 5.1 报告结果

```
🔄 Ralph 循环已结束

  ⏱ 总迭代次数: <次数>
  🌿 保护分支: ${BRANCH_NAME}
  📂 原始分支: ${CURRENT_BRANCH}
  🐳 Docker 快照: ✅ / ❌ / 未使用
  🏖️ sbx 快照: ✅ / ❌ / 未使用
  🎯 完成条件: 已达成 / 未达成 / 未设置

  请选择处理方式：

  [1] ✅ 保留修改 → 合并回 ${CURRENT_BRANCH}，清理备份
  [2] ❌ 全部回滚 → 从快照恢复，删除保护分支
  [3] 🤔 我先看看改了什么 → 查看 git diff 后选择 [1] 或 [2]
```

#### 5.2 选项 [1] 保留修改

```bash
# 切回原始分支
git checkout "${CURRENT_BRANCH}"

# 合并保护分支
git merge "${BRANCH_NAME}" --no-edit 2>/dev/null || {
  echo "⚠️ 合并冲突，请手动解决后提交"
  echo "  冲突文件: $(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')"
  exit 1
}

# 删除保护分支
git branch -D "${BRANCH_NAME}"

# 恢复 stash
git stash list 2>/dev/null | grep -q "safe-ralph-auto-stash-${TIMESTAMP}" && git stash pop 2>/dev/null || true

# 清理 Docker/sbx 快照文件
rm -f "$(pwd)/.safe-ralph-snapshot-${TIMESTAMP}.tar.gz" 2>/dev/null || true
docker volume rm "${BACKUP_VOLUME}" 2>/dev/null || true

echo "✅ 修改已合并到 ${CURRENT_BRANCH}，保护分支已删除，备份已清理"
```

#### 5.3 选项 [2] 全部回滚

**二次确认后执行：**

```bash
# 二次确认
echo "⚠️ 即将执行完全回滚，这将丢弃 ralph-loop 的所有修改！确认回滚？(y/N): "

# 等待用户输入 y/Y

# --- 从快照恢复（优先 sbx 快照文件，回退 Docker volume） ---
if [ -f "$(pwd)/.safe-ralph-snapshot-${TIMESTAMP}.tar.gz" ]; then
  echo "📦 正在从 sbx 快照文件恢复..."
  # 安全清理工作目录（保留 .git）
  find . -not -path './.git/*' -not -name '.git' -delete 2>/dev/null || true
  tar xzf "$(pwd)/.safe-ralph-snapshot-${TIMESTAMP}.tar.gz" -C "$(pwd)"
  rm -f "$(pwd)/.safe-ralph-snapshot-${TIMESTAMP}.tar.gz"
  echo "✅ sbx 快照恢复成功"
elif [ -n "${BACKUP_VOLUME}" ] && docker volume inspect "${BACKUP_VOLUME}" >/dev/null 2>&1; then
  echo "📦 正在从 Docker 快照恢复..."
  
  # 安全清理工作目录（保留 .git）
  # 检测 submodule 并跳过
  EXCLUDE_SUBMODULES=""
  if [ -f ".gitmodules" ]; then
    for dir in $(git config --file .gitmodules --get-regexp path | awk '{print $2}'); do
      EXCLUDE_SUBMODULES="${EXCLUDE_SUBMODULES} -not -path './${dir}/*' -not -name '${dir}'"
    done
  fi
  
  eval "find . -not -path './.git/*' -not -name '.git' ${EXCLUDE_SUBMODULES:-} -delete 2>/dev/null" || true
  
  docker run --rm \
    -v "$(pwd):/workspace" \
    -v "${BACKUP_VOLUME}:/backup" \
    alpine:latest \
    sh -c "tar xzf /backup/project-snapshot.tar.gz -C /workspace"
  
  if [ $? -eq 0 ]; then
    echo "✅ Docker 快照恢复成功"
  else
    echo "❌ Docker 快照恢复失败！请手动检查 ${BACKUP_VOLUME}"
  fi
fi

# --- Git 恢复 ---
git checkout "${CURRENT_BRANCH}"
git branch -D "${BRANCH_NAME}"

# 恢复 stash
git stash list 2>/dev/null | grep -q "safe-ralph-auto-stash-${TIMESTAMP}" && git stash pop 2>/dev/null || true

# 清理备份
docker volume rm "${BACKUP_VOLUME}" 2>/dev/null || true

echo "✅ 已完全回滚到 ${CURRENT_BRANCH} 的备份状态"
```

#### 5.4 选项 [3] 查看差异

```bash
# 统计摘要
echo "📊 改动统计："
git diff "${CURRENT_BRANCH}...${BRANCH_NAME}" --stat

echo ""
echo "查看完整 diff：git diff ${CURRENT_BRANCH}...${BRANCH_NAME}"
```

然后让用户选择 [1] 保留 或 [2] 回滚。

#### 5.5 补充清理

```bash
# 清理本流程创建的已退出容器
docker ps -a --filter "label=safe-ralph-loop" -q 2>/dev/null | xargs -r docker rm -v 2>/dev/null || true

# 清理 sbx 残留的快照文件
rm -f "$(pwd)/.safe-ralph-snapshot-*.tar.gz" 2>/dev/null || true
```

---

## 边界情况处理

### 1. ralph-loop 被取消（/cancel-ralph）

立即进入**第五步**。保护分支和快照（Docker / sbx）仍然有效，数据不会丢失。

### 2. 用户手动中断

- 中断时快照已完成 → 回滚选项可用
- 中断时快照未完成 → 只有 git 分支保护
- 保护分支留在仓库中，可运行 `/ralph-recover` 清理

### 3. sbx 启动超时

sbx 在启动时可能报 `inspect exec: context deadline exceeded`，但沙箱实际已创建成功。
此时用 `sbx ls` 检查状态，如果 running 则直接 `sbx run --name <name>` 连进去。
如果在宿主机上运行 safe-ralph-loop，此超时不应阻断流程。

### 4. 备份验证失败

```
⚠️ 快照备份验证未通过，可能原因：磁盘空间不足、文件被锁定、Docker/sbx 异常
   建议检查状态，确认是否继续（回滚可能不可用）
```

### 5. 合并冲突

```
⚠️ 合并时出现冲突，无法自动合并。
   冲突文件: <列表>
   请手动解决后 git commit。
   保护分支 ${BRANCH_NAME} 暂保留，解决后可手动删除。
```

### 6. 有 git submodule

回滚时 `find -delete` 会跳过子模块目录。子模块需要手动 `git submodule update --init --recursive` 恢复。

### 7. sbx 中文路径挂载问题

sbx v0.35.0 在含中文/空格的路径上有 mount 策略拒绝问题。如果当前项目路径含中文，
sbx 沙箱建议改为手动执行（由用户在终端操作），safe-ralph-loop 继续走 Docker 或纯 git 保护模式。

---

## 注意事项

1. **必须获得用户确认才能启动 ralph-loop**，不可自动执行
2. **全程透明**：每一步的输出都要向用户展示
3. **快照排除大目录**：node_modules、.git、target、__pycache__、.claude、.venv、venv、dist、build
4. **保护分支从当前分支创建**，而非硬编码的 main/master
5. **容器建议只提供信息**，决策权始终在用户手中
6. **回滚操作不可逆**，执行前必须二次确认
7. **Windows 兼容**：通过 Git Bash 运行命令，Docker Desktop 需提前安装
8. **备份卷只读挂载**（`:ro`），防止备份过程意外修改源码
9. **sbx > Docker > 纯 git**：优先使用 sbx 沙箱方案，自动降级策略
