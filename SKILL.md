---
name: safe-ralph-loop
description: >-
  Safe Ralph Loop — 安全的 Ralph Loop 执行器。
  检测 Docker、Docker Sandbox (sbx) 与容器环境状态，
  提供沙箱/容器化建议，执行隔离/快照/分支保护，
  结束后自动清理和提供回滚选项。
  强制安全层，每次运行 ralph-loop 前必须调用。
trigger:
  - 用户输入 /safe-ralph-loop 时，必须立即调用
  - 用户计划运行 ralph-loop 做有风险修改时，应主动建议
  - 用户提到「安全运行」「保护」「备份」「回滚」「翻车」「sbx」「沙箱」「sandbox」时
    应询问是否需要此技能提供的安全保护
  - 检测到 sbx 可用时，优先推荐 sbx 沙箱方案
  - 此技能是 ralph-loop 的强制安全层，不能跳过
compatibility:
  requires: [git, bash]
  optional: [docker, sbx]
---

# Safe Ralph Loop

ralph-loop 的安全保护层。每次使用 ralph-loop 时按以下流程执行完整保护：

```
① 环境检测 → ② 沙箱/容器决策 → ③ 预检确认 → ④ 执行保护 → ⑤ 清理恢复
```

## 使用方式

```
/safe-ralph-loop <prompt> [--max-iterations N] [--completion-promise "TEXT"]
```

| 参数 | 必填 | 默认值 | 说明 |
|---|---|---|---|
| `prompt` | ✅ | — | 精确描述要完成的任务 |
| `--max-iterations` | ❌ | 10 | 最大循环迭代次数 |
| `--completion-promise` | ❌ | 无 | 可验证的完成条件，如 `"ALL TESTS PASSING"` |

**手动恢复**（流程中断导致残留时用）：
```
/ralph-recover
```

---

## 第一步：环境检测

### 1.1 运行检测脚本

使用脚本进行全自动检测，脚本会输出标准化的环境状态行供你解析：

```bash
bash ./scripts/env-detect.sh
```

此脚本检测以下维度：
- **Git**: 是否在 git 仓库、默认分支、当前分支、未提交修改数
- **Docker**: CLI 是否安装、Daemon 是否运行、是否在容器内
- **sbx**: 是否安装（多种路径查找）、Daemon 状态、策略配置、是否在沙箱内
- **代理**: 检测 HTTPS_PROXY/HTTP_PROXY 等代理环境变量
- **磁盘**: 检测可用磁盘空间，空间不足时跳过备份

检测结果会同时：
1. 打印 `KEY:VALUE` 格式供你解析（如 `GIT_OK:YES`、`DOCKER_DAEMON:RUNNING`）
2. 写入 `$HOME/.safe-ralph-meta.sh` 供后续步骤读取

### 1.2 确定保护等级

根据检测结果对照[保护等级矩阵](references/protection-matrix.md)确定可用等级：

| 等级 | 条件 | 说明 |
|---|---|---|
| 🟢 完整 | sbx + Docker + Git | 沙箱隔离 + 快照 + 分支 |
| 🟢 沙箱 | sbx + Git | sbx --clone + 分支 |
| 🟢 标准 | Docker + Git | 快照 + 分支 |
| 🟡 降级 | 仅 Git | 仅分支保护，无文件快照 |
| 🔴 无 | 全部不可用 | 仅警告 |

### 1.3 向用户报告

用清晰的可视化方式向用户展示检测结果，例如：

```
🔍 环境检测完成

  sbx:     ✅ v0.35.0 (daemon 运行中 | 策略已配置)
  Docker:  ✅ 24.0.7 (daemon 运行中)
  容器内:  否
  Git:     ✅ main (3个未提交修改)
  磁盘:    ✅ 充足 (50.2GB 可用)
  代理:    ✅ HTTPS_PROXY 已设置

🛡️ 保护等级: 🟢 完整保护
```

---

## 第二步：沙箱/容器决策

核心原则：**提供信息和建议，决策权在用户手中**。不要自动做决定。

### 场景 A：sbx 可用（最高优先级推荐）

显示推荐信息后询问用户是否使用 sbx 沙箱：

```
✅ Docker Sandbox (sbx) 可用

  sbx 是 Docker 官方出品的 AI agent 沙箱，提供：
  • 完整的文件系统隔离（--clone 模式：宿主机只读）
  • 一键创建/清理，无需手动管理容器
  • 内置策略系统控制网络和文件访问

  是否使用 Docker Sandbox 沙箱执行本次 ralph-loop？(y/N)
```

- **用户选「是」且策略已配置** → 进入 4-sbx 路径
- **用户选「是」但策略未配置** → 显示策略配置指南：
  ```bash
  sbx policy allow --type fs:mount:rw --resource "D:\项目路径"
  ```
- **用户选「否」** → 继续检查 Docker

### 场景 B：Docker 可用

```
🐳 Docker 可用（当前未在容器内）

  是否要在 Docker 容器中执行本次 ralph-loop？(y/N)
```

- **选「是」** → 提供容器进入命令（见下方），终止当前流程
- **选「否」** → 进入宿主机保护流程（第四步）

**容器进入命令模板**：
```bash
docker run -it --rm \
  -v "$(pwd):/workspace" \
  -w /workspace \
  -e ANTHROPIC_API_KEY \
  -e HTTPS_PROXY \
  node:20-slim bash
# 在容器内安装 Claude Code 并重新运行 /safe-ralph-loop
```

### 场景 C：已在容器内

展示容器信息后直接进入第三步：
```
📦 已在 Docker 容器内运行
  🆔 容器 ID: <hostname>
  🔑 API 密钥: ✅/❌
  💡 git 保护分支机制仍然有效
```

### 场景 D：全部不可用

```
⚠️ 无法提供容器/沙箱保护，已降级为纯 git 分支保护
```

进入第三步。

---

## 第三步：预检与确认

### 3.1 解析参数

如果用户未提供完整参数，逐一询问补全：

```
请确认以下参数：

  📋 工作需求（prompt）:  <用户输入的任务描述>
  🔄 最大迭代次数:        <默认 10>
  🎯 完成条件:            <推荐设置，如 "ALL TESTS PASSING">
```

> `--completion-promise` 是 ralph-loop 判断任务完成的依据。设置可验证的条件能让循环在达成时自动停止。好的示例：`"ALL TESTS PASSING"`、`"BUILD_SUCCESS"`、`"NO_ERRORS"`。建议用户设置此值，但不强制。

### 3.2 展示确认摘要

**必须获得用户明确确认后才能继续。** 展示完整摘要：

```
🛡️  Safe Ralph Loop — 启动前确认

  📂 项目路径:  <当前路径>
  📋 工作需求:  <prompt>
  🌿 当前分支:  <分支名>
  🛡️ 保护方案:  <🟢完整 / 🟢沙箱 / 🟢标准 / 🟡降级 / 🔴无保护>
  🔄 最大迭代:  <N> 次
  🎯 完成条件:  <promise 或无>
  🐳 隔离方式:  <sbx沙箱 / Docker容器 / 宿主机分支 / 无>

  确认启动 ralph-loop？(y/N)
```

如果用户确认「是」，根据第二步的决策进入对应的执行路径。

---

## 第四步：执行保护

### 4-sbx 路径：Docker Sandbox 沙箱

#### 4.1-sbx 初始化

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SANDBOX_NAME="sralph-${TIMESTAMP}"

# 写入元数据
{
  echo "export TIMESTAMP='${TIMESTAMP}'"
  echo "export SANDBOX_NAME='${SANDBOX_NAME}'"
} >> "$HOME/.safe-ralph-meta.sh"
```

#### 4.2-sbx 创建沙箱

```bash
. "$HOME/.safe-ralph-meta.sh"

# 定位 sbx（先 PATH，再常见路径）
SBX_PATH=$(command -v sbx 2>/dev/null || find /c/Users -path "*/DockerSandboxes/bin/sbx.exe" 2>/dev/null | head -1)
[ -z "$SBX_PATH" ] && { echo "❌ 无法定位 sbx"; exit 1; }

echo "📦 正在创建 Docker Sandbox: ${SANDBOX_NAME}（--clone 模式）"

if git rev-parse --git-dir >/dev/null 2>&1; then
  "$SBX_PATH" create --name "${SANDBOX_NAME}" --clone shell "$(pwd)" 2>&1
else
  "$SBX_PATH" create --name "${SANDBOX_NAME}" shell "$(pwd)" 2>&1
fi

if [ $? -eq 0 ]; then
  echo "export SBX_PATH='${SBX_PATH}'" >> "$HOME/.safe-ralph-meta.sh"
  echo "✅ 沙箱创建成功"
else
  echo "❌ 沙箱创建失败，降级到 4-host 路径"
  # 继续执行宿主机保护
fi
```

#### 4.3-sbx 沙箱内操作说明

向用户展示操作说明后，**终止当前 safe-ralph-loop 流程，让用户在沙箱内自行操作**：

```
✅ Docker Sandbox 已就绪

  📦 沙箱名称: ${SANDBOX_NAME}
  🔄 沙箱模式: --clone（宿主机只读）

  [1] 进入沙箱:
      ${SBX_PATH} exec -it ${SANDBOX_NAME} bash

  [2] 在沙箱内安装 Claude Code:
      npm install -g @anthropic-ai/claude-code

  [3] 运行 ralph-loop:
      cd $(pwd)
      claude /ralph-loop "<prompt>" --max-iterations N

  [4] 完成后取回成果:
      ${SBX_PATH} cp ${SANDBOX_NAME}:<容器路径> <宿主机路径>

  [5] 清理沙箱:
      ${SBX_PATH} stop ${SANDBOX_NAME}    # 停止
      ${SBX_PATH} rm --force ${SANDBOX_NAME}  # 彻底删除

  ⚠️ --clone 模式下宿主机文件只读，修改不会影响宿主机
```

---

### 4-host 路径：宿主机保护

#### 4.1-host 创建保护分支

```bash
. "$HOME/.safe-ralph-meta.sh"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# 如果已在上一步写入 TIMESTAMP，用已有的
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

if git rev-parse --git-dir >/dev/null 2>&1; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  BRANCH_NAME="safe-ralph-${TIMESTAMP}-${CURRENT_BRANCH}"

  echo "🌿 创建保护分支: ${BRANCH_NAME}"

  # stash 未提交修改
  git stash push -m "safe-ralph-auto-stash-${TIMESTAMP}" --include-untracked 2>/dev/null || true
  git checkout -b "${BRANCH_NAME}"

  echo "export CURRENT_BRANCH='${CURRENT_BRANCH}'" >> "$HOME/.safe-ralph-meta.sh"
  echo "export BRANCH_NAME='${BRANCH_NAME}'" >> "$HOME/.safe-ralph-meta.sh"
else
  echo "⚠️ 非 git 仓库，跳过保护分支"
fi
```

#### 4.2-host 创建 Docker 快照

```bash
. "$HOME/.safe-ralph-meta.sh"

# 只有 Docker daemon 运行时才创建
if docker info >/dev/null 2>&1; then
  bash ./scripts/backup.sh
else
  echo "📦 Docker 快照: 跳过（Docker 不可用）"
fi
```

#### 4.3-host 启动 ralph-loop

用户确认后，通过 Skill 工具调用 ralph-loop：

```
/ralph-loop "<prompt>" --max-iterations <N> --completion-promise "<promise>"
```

**等待 ralph-loop 完成后**进入下一步清理。

---

## 第五步：清理恢复

### 5.1 报告结果

```
🔄 Ralph 循环已结束

  ⏱ 总迭代次数:  <显示实际次数>
  🌿 保护分支:    <名称>
  📂 原始分支:    <名称>
  🐳 Docker 快照: 有/无
  🎯 完成条件:    已达成 / 未达成 / 未设置

  请选择处理方式：

  [1] ✅ 保留修改 → 合并回原始分支，清理备份
  [2] ❌ 全部回滚 → 从快照恢复
  [3] 🤔 查看差异 → git diff 后再决定
```

### 5.2 根据用户选择执行

**选项 [1] 保留修改**：
```bash
bash ./scripts/cleanup.sh keep
```

**选项 [2] 全部回滚**（需二次确认后执行）：
```bash
bash ./scripts/cleanup.sh rollback
```

**选项 [3] 查看差异**：
```bash
bash ./scripts/cleanup.sh diff
```
查看后让用户选择 [1] 或 [2]。

### 5.3 补充清理（无论何种选项都执行）

```bash
bash ./scripts/cleanup.sh cleanup-backup
```

---

## 边界情况速查

遇到异常时查阅 [边​界​情​况​处​理](references/edge-cases.md) 获取详细应对策略。

常见边界快速处理：

| 情况 | 处理 |
|---|---|
| 用户取消 ralph-loop | 立即进入第5步，保护资源有效 |
| sbx 启动超时 | 沙箱可能已创建，`sbx ls` 检查后直接连接 |
| sbx 策略未配置 | 显示配置指引，不自动创建沙箱 |
| Docker 快照验证失败 | 提示用户，询问是否继续 |
| 合并冲突 | 提示用户手动解决，保护分支暂保留 |
| Git submodule | 备份和回滚自动跳过子模块目录 |
| 代理环境 | 脚本自动检测并传递代理设置 |
| 磁盘空间不足 | 跳过快照备份，仅使用 git 保护 |
| 中文路径 | sbx 可能失败，自动降级到 Docker/纯 git |

---

## 脚本文件说明

| 文件 | 用途 |
|---|---|
| `scripts/env-detect.sh` | 环境检测（Git/Docker/sbx/代理/磁盘） |
| `scripts/backup.sh` | Docker 快照创建和验证 |
| `scripts/cleanup.sh` | 清理恢复（保留/回滚/查看差异/通用清理） |
| `references/protection-matrix.md` | 保护等级判定矩阵和排除清单 |
| `references/edge-cases.md` | 边界情况详细处理策略 |

---

## 设计原则

1. **确认先行** — 必须获得用户确认才能启动 ralph-loop
2. **全程透明** — 每一步的命令和输出都向用户展示
3. **优先级递进** — sbx 沙箱 > Docker 容器 > git 分支 > 警告
4. **优雅降级** — 高级保护不可用时自动降级，不中断流程
5. **回滚安全** — 回滚操作不可逆，执行前二次确认
6. **Windows 兼容** — 适配 Git Bash 和 Windows 路径
7. **跨步骤变量** — 通过元数据文件解决 bash 进程间的变量传递
8. **DRY 原则** — 公共逻辑抽取到 scripts/，避免多处方修改
