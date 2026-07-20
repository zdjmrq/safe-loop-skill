---
name: safe-ralph-loop
description: >-
  Safe Ralph Loop — 安全的 Ralph Loop 执行器。
  自动检测 Docker、Docker Sandbox (sbx) 与容器环境状态，
  提供沙箱/容器化建议，执行 sbx 沙箱隔离 / Docker 快照 / git 保护分支，
  结束后提供保留/回滚选项并自动清理残留。
  
  使用此技能的时机：
  - 用户输入 /safe-ralph-loop 时，必须立即调用此技能
  - 用户计划运行 ralph-loop 做有风险的修改时，应主动建议使用此技能
  - 用户提到「安全运行」「保护」「备份」「回滚」「翻车」「sbx」「沙箱」「sandbox」等语境时
    应询问是否需要此技能保护
  - 检测到 sbx (Docker Sandboxes) 可用时，优先推荐 sbx 沙箱方案
  
  此技能是 ralph-loop 的强制安全层，不能跳过。
---

# Safe Ralph Loop

ralph-loop 的安全保护层。每次使用 ralph-loop 时，自动执行完整保护流程：

```
① 环境检测 → ② 沙箱/容器决策 → ③ 预检确认 → ④ 执行保护 → ⑤ 清理恢复
```

## 核心概念

本技能提供三层递进保护机制，优先级从高到低：

| 层级 | 保护方式 | 依赖 | 隔离程度 |
|---|---|---|---|
| **🟢 沙箱** | Docker Sandbox (`sbx`) | sbx 已安装 + 运行中 | 完全隔离（宿主机不受影响） |
| **🟢 容器** | Docker 容器 + 快照 | Docker Desktop 运行中 | 文件级隔离 |
| **🟡 分支** | git 保护分支 + stash | git 仓库 | 代码级保护（无文件快照） |
| **🔴 无** | 仅警告 | — | 无保护 |

---

## 使用方式

### 启动带保护的 ralph-loop

```
/safe-ralph-loop <prompt> [--max-iterations N] [--completion-promise "TEXT"]
```

| 参数 | 必填 | 默认值 | 说明 |
|---|---|---|---|
| `prompt` | ✅ | — | 精确描述需要完成的任务 |
| `--max-iterations` | ❌ | 10 | 最大循环迭代次数 |
| `--completion-promise` | ❌ | 无 | 可验证的完成条件，如 `"ALL TESTS PASSING"` |

**示例：**
```
/safe-ralph-loop "修复登录页的 bug" --max-iterations 10 --completion-promise "ALL TESTS PASSING"
/safe-ralph-loop "重构缓存层" --max-iterations 5
/safe-ralph-loop "把 Python 脚本转成 Rust 实现"
```

### 手动恢复（翻车时用）

如果 safe-ralph-loop 流程中断导致残留，可运行：
```
/ralph-recover
```

---

## ⚠️ 重要：元数据文件机制

本技能 5 个步骤中的 bash 命令运行在不同 shell 进程中，变量不能互相传递。
因此使用 **元数据文件 `~/.safe-ralph-meta.sh`** 来跨步骤共享数据：

- **写入：** 每段 bash 向 `~/.safe-ralph-meta.sh` 写入 `export KEY=VALUE`
- **读取：** 后续 bash 第一行执行 `. ~/.safe-ralph-meta.sh`
- **清理：** 流程结束时自动删除

Claude 自己也需要在上下文中保存 `META_` 开头的变量，用于展示进度和构建命令。

---

## 我的执行步骤

### 第一步：环境检测

#### 1.1 检测 Docker Sandbox (sbx)

```bash
# sbx 通常安装在以下路径（Windows）
SBX_PATHS=(
  "/c/Users/$USERNAME/AppData/Local/DockerSandboxes/bin/sbx.exe"
  "$HOME/AppData/Local/DockerSandboxes/bin/sbx.exe"
)
SBX_PATH=""
for p in "${SBX_PATHS[@]}"; do
  [ -f "$p" ] && { SBX_PATH="$p"; break; }
done

if [ -n "$SBX_PATH" ]; then
  echo "SBX_INSTALLED:YES"
  # 检查 daemon 是否运行
  "$SBX_PATH" daemon status >/dev/null 2>&1 && echo "SBX_DAEMON:RUNNING" || echo "SBX_DAEMON:STOPPED"
  # 检查策略是否允许挂载工作目录
  "$SBX_PATH" policy ls 2>/dev/null | grep -q 'fs:mount' && echo "SBX_POLICY:CONFIGURED" || echo "SBX_POLICY:UNCONFIGURED"
else
  echo "SBX_INSTALLED:NO"
fi
```

**提醒：** sbx 有策略系统控制文件系统访问。如果检测到 `SBX_POLICY:UNCONFIGURED`，使用 sbx 前需要用户手动运行：
```bash
sbx policy allow --type fs:mount:rw --resource "D:\项目路径"
```

#### 1.2 检测 Docker

```bash
# Docker CLI 是否安装
docker --version 2>/dev/null && echo "DOCKER_CLI:AVAILABLE" || echo "DOCKER_CLI:UNAVAILABLE"

# Docker daemon 是否运行（比 --version 更严格）
docker info >/dev/null 2>&1 && echo "DOCKER_DAEMON:RUNNING" || echo "DOCKER_DAEMON:STOPPED"

# 是否已在 Docker 容器内部
test -f /.dockerenv 2>/dev/null && echo "IN_CONTAINER:YES" || echo "IN_CONTAINER:NO"
if grep -qE 'docker|lxc|containerd' /proc/1/cgroup 2>/dev/null; then echo "IN_CONTAINER:YES"; fi
```

#### 1.3 检测 Git

```bash
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) && echo "GIT_OK" || echo "NOT_GIT"

if [ -n "$GIT_DIR" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@')
  echo "DEFAULT_BRANCH:${DEFAULT_BRANCH:-main}"
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  echo "CURRENT_BRANCH:${CURRENT_BRANCH}"
  UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
  echo "UNCOMMITTED_CHANGES:${UNCOMMITTED}"
fi
```

#### 1.4 确定保护等级

根据检测结果确定实际可用的保护等级，向用户展示：

| sbx | Docker Daemon | Git | 保护等级 | 建议 |
|---|---|---|---|---|
| ✅ | ✅ | ✅ | 🟢 **完整保护** | 沙箱隔离 + 快照 + 分支（推荐） |
| ✅ | ❌ | ✅ | 🟢 **沙箱保护** | sbx --clone 隔离 + git 分支 |
| ✅ | ✅ | ❌ | 🟡 **沙箱+快照** | sbx 隔离 + Docker 快照 |
| ✅ | ❌ | ❌ | 🟡 **沙箱保护** | sbx 隔离（建议 git init） |
| ❌ | ✅ | ✅ | 🟢 **标准保护** | Docker 快照 + git 分支 |
| ❌ | ✅ | ❌ | 🟡 **快照保护** | 仅 Docker 快照 |
| ❌ | ❌ | ✅ | 🟡 **降级保护** | 仅 git 分支 |
| ❌ | ❌ | ❌ | 🔴 **无保护** | 强烈建议中止 |

展示检测结果：

```bash
echo "环境检测完成"
echo "  sbx:     $([ -n "$SBX_PATH" ] && echo '✅' || echo '❌')  $( [ -n "$SBX_PATH" ] && "$SBX_PATH" version 2>/dev/null | head -1 || echo '')"
echo "  Docker:  $(docker --version 2>/dev/null && echo '✅' || echo '❌')  $(docker info >/dev/null 2>&1 && echo '(daemon 运行中)' || echo '(daemon 未运行)')"
echo "  容器内:  $(test -f /.dockerenv 2>/dev/null && echo '是' || echo '否')"
echo "  Git:     $(git rev-parse --git-dir 2>/dev/null && echo "✅ $(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || echo '❌')"
echo "  保护等级: $(从上方矩阵查找)"
```

---

### 第二步：沙箱/容器决策

**核心原则：** 提供信息和建议，决策权始终在用户手中。

#### 场景 A：sbx 可用（最高优先级推荐）

如果 `SBX_DAEMON:RUNNING`：

```
✅ Docker Sandbox (sbx) 可用

  sbx 是 Docker 官方出品的 AI agent 沙箱工具，提供：
  • 完整的文件系统隔离（--clone 模式：宿主机只读）
  • 一键创建/清理，无需手动管理容器
  • 内置策略系统控制网络和文件访问
  • 支持 cp 命令方便地取回结果

  使用 sbx 沙箱执行 ralph-loop：
  - 项目文件完全隔离，翻车直接删沙箱
  - 无需手动备份和回滚
  - 适合高风险任务

  是否要使用 Docker Sandbox 沙箱执行本次 ralph-loop？(y/N)
```

- **用户选择「是」且策略已配置**：进入 sbx 执行流程（跳到 4.1-sbx）。
- **用户选择「是」但策略未配置**：先显示策略配置指南，用户配置后继续。
- **用户选择「否」**：继续检查 Docker 容器选项。

**策略未配置时的提示：**
```
⚠️ sbx 的文件系统策略未配置。
   使用前需要为你的项目目录授权：

   sbx policy allow --type fs:mount:rw --resource "D:\你的项目路径"

   配置后重新运行 /safe-ralph-loop
```

#### 场景 B：Docker Daemon 运行中（未在容器内，且 sbx 不可用）

```
🐳 Docker 可用（当前未在容器内）

  💡 可在 Docker 容器中执行以获得环境隔离。
  是否要在 Docker 容器中执行本次 ralph-loop？(y/N)
```

- **用户选择「是」**：提供进入容器的命令，终止当前流程。
- **用户选择「否」**：执行宿主机保护流程（第三步）。

#### 场景 C：已在 Docker 容器内

展示容器信息和操作提示，然后进入第三步。

```bash
echo "CONTAINER_ID:$(hostname 2>/dev/null)"
test -n "$ANTHROPIC_API_KEY" && echo "API_KEY:AVAILABLE" || echo "API_KEY:MISSING"
```

```
📦 已在 Docker 容器内运行

  🆔 容器 ID:  <hostname>
  🔑 API 密钥: ✅ / ❌

  💡 提示：git 保护分支机制仍然有效，照常执行。
```

#### 场景 D：所有保护都不可用

```
⚠️ 无法提供容器/沙箱保护
   已降级为基础保护（git 分支或纯警告）。
```

进入第三步，根据可用能力执行对应保护。

---

### 第三步：预检与确认

#### 3.1 解析并补全参数

如果用户未提供完整参数，逐个询问补全：

```
请确认以下参数：

  📋 工作需求（prompt）:  <用户输入的任务描述>
  🔄 最大迭代次数:        <未设置则默认 10>
  🎯 完成条件:            <推荐设置，如 "ALL TESTS PASSING">
```

> `--completion-promise` 是 ralph-loop 判断任务完成的依据。设置可验证的条件能让循环在达成时自动停止。好的示例：`"ALL TESTS PASSING"`、`"BUILD_SUCCESS"`、`"NO_ERRORS"`

#### 3.2 展示确认摘要

**必须获得用户明确确认后才能继续。**

```
🛡️  Safe Ralph Loop — 启动前确认

  📂 项目路径:  <当前路径>
  📋 工作需求:  <prompt>
  🌿 当前分支:  <当前分支名>
  🛡️ 保护方案:  <🟢沙箱 / 🟢标准 / 🟡降级 / 🔴无保护>
  🔄 最大迭代:  <N> 次
  🎯 完成条件:  <promise 或无>
  🐳 隔离方式:  <sbx沙箱 / Docker容器 / 宿主机分支 / 无>

  确认启动 ralph-loop？(y/N)
```

---

### 第四步：执行保护

根据第二步的决策，选择对应的执行路径。

---

#### 4-sbx 路径：使用 Docker Sandbox 沙箱

**设计意图：** sbx 提供最佳隔离。在沙箱内执行 ralph-loop，修改不影响宿主机。完成后通过 `sbx cp` 取回成果，或通过 `--clone` 模式的 git remote 拉取。

##### 4.1-sbx 初始化元数据

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
rm -f "$META_FILE"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SANDBOX_NAME="sralph-${TIMESTAMP}"

# 写入元数据
{
  echo "export TIMESTAMP='${TIMESTAMP}'"
  echo "export SANDBOX_NAME='${SANDBOX_NAME}'"
  echo "export SBX_MODE='clone'"  # clone = 完全隔离, mount = 直接挂载
} >> "$META_FILE"

echo "META_TIMESTAMP:${TIMESTAMP}"
echo "META_SANDBOX_NAME:${SANDBOX_NAME}"
```

##### 4.2-sbx 创建沙箱

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"

# 定位 sbx
SBX_PATH=$(find /c/Users -path "*/DockerSandboxes/bin/sbx.exe" 2>/dev/null | head -1)

if [ -z "$SBX_PATH" ]; then
  echo "❌ 无法定位 sbx，请确认安装路径"
  exit 1
fi

echo "📦 正在创建 Docker Sandbox: ${SANDBOX_NAME}"
echo "  使用 --clone 模式（宿主项目只读，沙箱内可写克隆）"

# 检测 git 是否可用，决定是否使用 --clone
HAS_GIT=false
git rev-parse --git-dir >/dev/null 2>&1 && HAS_GIT=true

SBX_ARGS=("create" "--name" "${SANDBOX_NAME}")
if [ "$HAS_GIT" = true ]; then
  SBX_ARGS+=("--clone")
fi
SBX_ARGS+=("shell" "$(pwd)")

# 创建沙箱
if "$SBX_PATH" "${SBX_ARGS[@]}" 2>&1; then
  echo "SANDBOX_CREATED:YES"
  echo "✅ 沙箱创建成功"
  
  # 记录沙箱信息
  echo "export SBX_PATH='${SBX_PATH}'" >> "$META_FILE"
  
  # 如果使用 --clone，沙箱内会有一个完整的 git clone
  # 宿主机可通过 git remote add sandbox-${SANDBOX_NAME} ... 拉取变更
else
  echo "SANDBOX_CREATED:NO"
  echo "❌ 沙箱创建失败，降级到备用保护方案"
  # 降级到 4-host 路径
fi
```

##### 4.3-sbx 在沙箱内执行 ralph-loop

沙箱创建成功后，向用户展示操作说明：

```
✅ Docker Sandbox 已就绪

  📦 沙箱名称: ${SANDBOX_NAME}
  📂 项目目录: $(pwd)（宿主机只读）
  🔄 沙箱模式: $( [ "$HAS_GIT" = true ] && echo '--clone (完全隔离)' || echo '直接挂载')
  
  请按以下步骤在沙箱中工作：

  [1] 进入沙箱:
      ${SBX_PATH} exec -it ${SANDBOX_NAME} bash

  [2] 在沙箱内安装 Claude Code（如需）:
      npm install -g @anthropic-ai/claude-code

  [3] 在沙箱内运行 ralph-loop（使用你的项目文件）:
      cd $(pwd)
      claude /ralph-loop "<prompt>"...

  [4] 完成后取回成果:
      ${SBX_PATH} cp ${SANDBOX_NAME}:$(pwd)/<输出文件> <宿主机路径>

  [5] 清理沙箱:
      ${SBX_PATH} stop ${SANDBOX_NAME}
      # 或彻底删除：${SBX_PATH} rm --force ${SANDBOX_NAME}

  ⚠️ 安全提示：
  • --clone 模式下宿主机文件只读，沙箱内修改不会影响宿主机
  • 如果使用挂载模式（非 --clone），修改会直接写入宿主机
  • 完成后记得清理沙箱
```

**终止当前 safe-ralph-loop 流程**，让用户在沙箱内自行操作。

---

#### 4-host 路径：宿主机保护（sbx/Docker 不可用或用户拒绝）

##### 4.1-host 初始化元数据

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
rm -f "$META_FILE"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

{
  echo "export TIMESTAMP='${TIMESTAMP}'"
} >> "$META_FILE"
```

##### 4.2-host 创建保护分支（git 可用时）

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"

if git rev-parse --git-dir >/dev/null 2>&1; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  BRANCH_NAME="safe-ralph-${TIMESTAMP}-${CURRENT_BRANCH}"

  echo "🌿 创建保护分支: ${BRANCH_NAME}"

  git stash push -m "safe-ralph-auto-stash-${TIMESTAMP}" --include-untracked 2>/dev/null || true
  git checkout -b "${BRANCH_NAME}"

  {
    echo "export CURRENT_BRANCH='${CURRENT_BRANCH}'"
    echo "export BRANCH_NAME='${BRANCH_NAME}'"
  } >> "$META_FILE"

  echo "META_CURRENT_BRANCH:${CURRENT_BRANCH}"
  echo "META_BRANCH_NAME:${BRANCH_NAME}"
else
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  echo "export CURRENT_BRANCH='(非 git 仓库)'" >> "$META_FILE"
  echo "export TIMESTAMP='${TIMESTAMP}'" >> "$META_FILE"
  echo "⚠️ 非 git 仓库，跳过保护分支创建"
fi
```

##### 4.3-host 创建 Docker 快照（Docker Daemon 运行时）

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"

if docker info >/dev/null 2>&1; then
  BACKUP_VOLUME="ralph-backup-${TIMESTAMP}"
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

  echo "export BACKUP_VOLUME='${BACKUP_VOLUME}'" >> "$META_FILE"
  echo "META_BACKUP_VOLUME:${BACKUP_VOLUME}"
fi
```

##### 4.4-host 保存元数据到上下文

从 bash 输出中捕获 `META_` 开头的行：

```
META_CURRENT_BRANCH=main
META_BRANCH_NAME=safe-ralph-20260720-145630-main
META_TIMESTAMP=20260720-145630
META_BACKUP_VOLUME=ralph-backup-20260720-145630
```

##### 4.5-host 启动 ralph-loop

用户确认后调用 ralph-loop skill：

```
/ralph-loop "<prompt>" --max-iterations <N> --completion-promise "<promise>"
```

**等待 ralph-loop 完成后**进入下一步清理。

---

### 第五步：清理恢复

#### 5.1 沙箱路径清理（如果使用了 sbx）

如果用户使用了 sbx 沙箱且已完成工作：

```
🧹 是否要清理 Docker Sandbox？
  
  沙箱 ${SANDBOX_NAME} 仍然存在。
  
  [1] ✅ 保留沙箱（稍后手动处理）
  [2] ❌ 彻底删除沙箱（sbx rm --force）
  [3] 🛑 停止沙箱（保留状态，可重新进入）
```

- **[2] 删除：** 执行 `"$SBX_PATH" rm --force "${SANDBOX_NAME}"`
- **[3] 停止：** 执行 `"$SBX_PATH" stop "${SANDBOX_NAME}"`
- **[1] 保留：** 提示用户手动管理

#### 5.2 宿主机路径清理

##### 5.2-host 报告结果

```
🔄 Ralph 循环已结束

  ⏱ 总迭代次数:  <次数>
  🌿 保护分支:    <META_BRANCH_NAME>
  📂 原始分支:    <META_CURRENT_BRANCH>
  🐳 Docker 快照: <有/无>
  🎯 完成条件:    已达成 / 未达成 / 未设置

  请选择处理方式：

  [1] ✅ 保留修改 → 合并回原始分支，清理备份
  [2] ❌ 全部回滚 → 从 Docker 快照恢复
  [3] 🤔 我先看看改了什么 → 查看 git diff 后决定
```

##### 5.3-host [1] 保留修改

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"

if [ -n "$BRANCH_NAME" ] && [ "$BRANCH_NAME" != "(无保护分支)" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  git checkout "${CURRENT_BRANCH}" 2>/dev/null
  if git merge "${BRANCH_NAME}" --no-edit 2>/dev/null; then
    echo "✅ 合并成功"
  else
    echo "⚠️ 合并冲突，请手动解决后提交"
    echo "  冲突文件: $(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')"
  fi
  git branch -D "${BRANCH_NAME}" 2>/dev/null || true
  if git stash list 2>/dev/null | grep -q "safe-ralph-auto-stash-${TIMESTAMP}"; then
    if git stash pop 2>/dev/null; then
      echo "✅ stash 恢复成功"
    else
      echo "⚠️ stash 与 ralph-loop 的修改产生冲突，请手动处理："
      echo "   保留 stash 内容 → 手动解决冲突后 git add && git commit"
      echo "   放弃 stash 内容 → git stash drop"
    fi
  fi
  echo "✅ 修改已合并到 ${CURRENT_BRANCH}"
fi

if [ -n "$BACKUP_VOLUME" ] && docker info >/dev/null 2>&1 && docker volume inspect "$BACKUP_VOLUME" >/dev/null 2>&1; then
  docker volume rm "${BACKUP_VOLUME}" 2>/dev/null && echo "✅ Docker 备份卷已删除" || true
fi
```

##### 5.4-host [2] 全部回滚

**⚠️ 此操作不可逆，执行前必须二次确认。**

```bash
echo "⚠️ 即将执行完全回滚，确认？(y/N): "
```

确认后：

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"

RESTORE_SUCCESS=false
if [ -n "$BACKUP_VOLUME" ] && docker info >/dev/null 2>&1 && docker volume inspect "$BACKUP_VOLUME" >/dev/null 2>&1; then
  echo "📦 正在从 Docker 快照恢复..."
  EXCLUDE_DIRS=()
  if [ -f ".gitmodules" ]; then
    while IFS= read -r dir; do
      [ -n "$dir" ] && EXCLUDE_DIRS+=("$dir")
    done < <(git config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}')
  fi
  find . -not -path './.git/*' -not -name '.git' \
    $(for d in "${EXCLUDE_DIRS[@]}"; do echo -not -path "./${d}/*" -not -name "${d}"; done) \
    -delete 2>/dev/null || true
  docker run --rm \
    -v "$(pwd):/workspace" \
    -v "${BACKUP_VOLUME}:/backup" \
    alpine:latest \
    sh -c "tar xzf /backup/project-snapshot.tar.gz -C /workspace" \
    && { echo "✅ Docker 快照恢复成功"; RESTORE_SUCCESS=true; } \
    || echo "❌ Docker 快照恢复失败！"
fi

if [ -n "$BRANCH_NAME" ] && [ "$BRANCH_NAME" != "(无保护分支)" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  git checkout "${CURRENT_BRANCH}" 2>/dev/null || git checkout --detach 2>/dev/null
  git branch -D "${BRANCH_NAME}" 2>/dev/null || true
  if git stash list 2>/dev/null | grep -q "safe-ralph-auto-stash-${TIMESTAMP}"; then
    if git stash pop 2>/dev/null; then
      echo "✅ stash 恢复成功"
    else
      echo "⚠️ stash 与回滚后的文件产生冲突，请手动处理："
      echo "   保留 stash 内容 → 手动解决冲突后 git add && git commit"
      echo "   放弃 stash 内容 → git stash drop"
    fi
  fi
fi

if [ -n "$BACKUP_VOLUME" ] && docker info >/dev/null 2>&1; then
  docker volume rm "${BACKUP_VOLUME}" 2>/dev/null || true
fi

$RESTORE_SUCCESS && echo "✅ 已完全回滚" || echo "⚠️ 回滚完成（未使用 Docker 快照）"
```

##### 5.5-host [3] 查看差异

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"
if [ -n "$BRANCH_NAME" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  echo "📊 改动统计："
  git diff "${CURRENT_BRANCH}...${BRANCH_NAME}" --stat
fi
```

#### 5.6 补充清理（通用）

```bash
META_FILE="$HOME/.safe-ralph-meta.sh"

# 清理本流程创建的已退出 Docker 容器
docker ps -a --filter "label=safe-ralph-loop" -q 2>/dev/null | xargs -r docker rm -v 2>/dev/null || true

# 清理元数据文件
rm -f "$META_FILE"

# 列出可能残留的 sbx sandbox（仅提示，不自动删除）
SBX_PATH=$(find /c/Users -path "*/DockerSandboxes/bin/sbx.exe" 2>/dev/null | head -1)
if [ -n "$SBX_PATH" ]; then
  REMAINING=$("$SBX_PATH" ls -q 2>/dev/null | grep "sralph-" || true)
  if [ -n "$REMAINING" ]; then
    echo "💡 以下 safe-ralph 沙箱仍存在（可手动清理）："
    echo "$REMAINING"
    echo "  清理命令: $SBX_PATH rm --force <名称>"
  fi
fi

echo "🧹 清理完成"
```

---

## 边界情况处理

### 1. ralph-loop 被取消（/cancel-ralph）

立即进入**第五步**。保护分支/Docker 快照/sbx 沙箱仍然有效。

### 2. 用户手动中断（Ctrl+C）

- sbx 路径：沙箱保持运行，可重新进入
- 宿主机路径：保护分支保留，运行 `/ralph-recover` 清理

### 3. Docker 备份验证失败

```
⚠️ Docker 快照备份验证未通过
   可能原因：磁盘空间不足、文件被锁定、Docker 异常
   建议：检查 Docker 状态后重试
```

让用户选择是否继续。

### 4. sbx 创建失败

如果 `sbx create` 失败（如策略未配置、Docker 未运行）：
- 提示具体失败原因
- 自动降级到 Docker 容器方案（如果 Docker 可用）或 git 分支保护

### 5. sbx 策略未配置

检测到 `SBX_POLICY:UNCONFIGURED` 时，提供明确的配置指引，不自动创建沙箱。

### 6. 合并冲突

合并时冲突则提示用户手动解决，保护分支暂保留。

### 7. 项目包含 git submodule

回滚时 `find -delete` 自动跳过子模块目录，子模块需手动 `git submodule update` 恢复。

### 8. 非 git 仓库

跳过分支保护，若 sbx 或 Docker 可用则继续提供隔离保护，否则仅警告。

### 9. Docker Daemon 未运行 vs CLI 未安装

区分两种情况，分别给出不同的解决方案建议。

### 10. sbx 路径不在 PATH 中

使用完整路径调用 sbx，并提示用户可将 sbx 加入 PATH：
```bash
# 将以下行加入 ~/.bashrc 或 ~/.bash_profile
export PATH="$PATH:$HOME/AppData/Local/DockerSandboxes/bin"
```

---

## 设计原则

1. **确认先行：** 必须获得用户确认才能启动 ralph-loop
2. **全程透明：** 每一步的命令和输出都向用户展示
3. **优先级递进：** sbx 沙箱 > Docker 容器 > git 分支 > 警告
4. **优雅降级：** 高级保护不可用时自动降级，不中断流程
5. **回滚安全：** 回滚操作不可逆，执行前二次确认
6. **sbx 不强制：** 沙箱只是建议，决策权在用户手中
7. **Windows 兼容：** 适配 Git Bash 和 Windows 路径
8. **跨步骤变量：** 通过元数据文件解决 bash 独立进程间的变量传递
