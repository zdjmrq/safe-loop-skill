# 🛡️ Safe Ralph Loop

**安全的 Ralph Loop 执行器** — 在运行 `ralph-loop` 时自动提供多层保护，防止代码丢失或项目被破坏，翻车了一键回滚。

[![Claude Code Skill](https://img.shields.io/badge/Claude_Code-Skill-8A2BE2)](https://claude.ai/code)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Test Pass Rate](https://img.shields.io/badge/Test%20Pass-100%25-brightgreen)]()

---

## 为什么需要这个？

`ralph-loop` 是强大的自动迭代工具，但它会持续修改你的代码。如果不加保护：

| 风险 | 后果 |
|---|---|
| 🐛 改出 bug | 找不到原始代码，无从对比 |
| ♾️ 无限循环 | 项目被改废，无法恢复 |
| ↩️ 想回滚 | 发现没有备份，只能重写 |

**Safe Ralph Loop** 给 ralph-loop 加了一层"安全气囊"。

---

## 核心功能

### 🔍 环境智能检测

自动检测你电脑上可用的保护能力：

| 检测项 | 检测方法 | 作用 |
|---|---|---|
| **Docker Sandbox (sbx)** | `sbx daemon status` | 提供最高等级的环境隔离 |
| **Docker Desktop** | `docker --version` + `docker info` | 提供文件级快照备份 |
| **Git 仓库** | `git rev-parse --git-dir` | 提供分支保护和版本管理 |
| **Docker 容器** | `/.dockerenv` + `/proc/1/cgroup` | 容器内操作提示 |
| **HTTPS 代理** | 环境变量检测 | 自动传递代理配置 |
| **磁盘空间** | `df -k` 检查 | 空间不足时跳过快照 |

### 🏰 四层保护体系

根据检测结果自动选择最优方案：

```
sbx + Docker + Git  → 🟢 完整保护（沙箱隔离 + 快照 + 分支）
sbx + Git          → 🟢 沙箱保护（sbx --clone + 分支）
Docker + Git       → 🟢 标准保护（快照 + 分支）
仅 Git             → 🟡 降级保护（分支保护保底）
全部不可用          → 🔴 无保护（强烈建议中止）
```

### 🤖 Docker Sandbox (sbx)

自动检测是 Docker 官方沙箱工具并提供使用建议：

- 检测安装状态、daemon 运行状态、策略配置
- 推荐 `--clone` 模式（宿主机只读 + git clone）
- 自动检测策略配置，未配置时给出指引
- 完成后可一键清理沙箱

### 📦 Docker 快照备份

Docker 可用时自动创建文件级快照：

- 使用 Docker volume 存储压缩归档
- 智能排除 `node_modules`、`.git`、`target` 等大目录
- 备份后自动验证完整性
- 支持从快照一键恢复

### 🌿 Git 分支保护

只要检测到 Git 仓库，都创建保护分支：

- 从**当前分支**创建（不硬编码 main/master）
- 自动 stash 未提交修改
- 结束后自由选择：保留 / 回滚 / 查看差异
- 支持 submodule 安全处理

### 🧹 自动清理

无论选择保留还是回滚，自动清理所有残留：

- 合并或删除保护分支
- 清理 Docker 备份卷
- 清理 sbx 沙箱
- 清除临时元数据文件

---

## 安装

### 前置条件

| 依赖 | 是否必需 | 说明 |
|---|---|---|
| [Claude Code](https://claude.ai/code) | ✅ **必需** | AI 代码助手运行环境 |
| Git | ✅ **必需** | 用于分支保护和版本管理 |
| Bash | ✅ **必需** | 脚本运行环境（Git Bash 内置） |
| Docker Desktop | ❌ 可选 | 用于快照备份和容器隔离 |
| [Docker Sandbox](https://docs.docker.com/desktop/features/sandbox/) | ❌ 可选 | 用于沙箱隔离（需要 Docker） |

### 安装到 Claude Code

```bash
# 方式一：从 GitHub 克隆（推荐）
git clone https://github.com/zdjmrq/safe-ralph-loop-skill.git
cp -r safe-ralph-loop-skill/SKILL.md ~/.claude/skills/safe-ralph-loop/
cp -r safe-ralph-loop-skill/scripts ~/.claude/skills/safe-ralph-loop/
cp -r safe-ralph-loop-skill/references ~/.claude/skills/safe-ralph-loop/

# 方式二：直接下载
mkdir -p ~/.claude/skills/safe-ralph-loop
curl -o ~/.claude/skills/safe-ralph-loop/SKILL.md \
  https://raw.githubusercontent.com/zdjmrq/safe-ralph-loop-skill/main/SKILL.md
# 并下载 scripts/ 和 references/ 目录
```

### sbx 策略配置（如需沙箱功能）

```bash
# 授权你的项目目录让 sbx 访问
sbx policy allow --type fs:mount:rw --resource "D:\你的项目路径"

# 验证策略
sbx policy ls
```

---

## 使用

```bash
/safe-ralph-loop <prompt> [--max-iterations N] [--completion-promise "TEXT"]
```

| 参数 | 必填 | 默认值 | 说明 |
|---|---|---|---|
| `prompt` | ✅ | — | 精确描述需要完成的任务 |
| `--max-iterations` | ❌ | 10 | 最大循环迭代次数，防止无限循环 |
| `--completion-promise` | ❌ | 无 | 可验证的完成条件，如 `"ALL TESTS PASSING"` |

**示例：**

```bash
/safe-ralph-loop "修复登录页的 bug"
/safe-ralph-loop "重构缓存层" --max-iterations 5
/safe-ralph-loop "把 Python 转 Rust" --max-iterations 15 --completion-promise "ALL TESTS PASSING"
```

**异常恢复：** 流程中断导致残留时可运行：
```bash
/ralph-recover
```

---

## 工作流程

```
用户输入 /safe-ralph-loop "任务"
    │
    ├─ ① 环境检测
    │    ├─ sbx 是否安装并运行？
    │    ├─ Docker 是否可用？
    │    ├─ Git 是否可用？
    │    ├─ 是否在容器内？
    │    ├─ 代理环境检测
    │    └─ 磁盘空间检测
    │
    ├─ ② 沙箱/容器决策
    │    ├─ sbx 可用 → 推荐沙箱隔离
    │    ├─ Docker 可用 → 推荐容器
    │    └─ 都不可用 → 降级提示
    │
    ├─ ③ 预检确认（参数解析 + 用户确认）
    │
    ├─ ④ 执行保护
    │    ├─ sbx 路径 → 创建沙箱 → 隔离执行
    │    └─ 宿主机路径 → 保护分支 + Docker快照 → 执行
    │
    └─ ⑤ 清理恢复
         ├─ [1] 保留修改 → 合并 + 清理
         ├─ [2] 回滚 → 从快照恢复
         └─ [3] 查看差异 → 再决定
```

---

## 项目结构

```
safe-ralph-loop-skill/
├── SKILL.md                  # 核心 skill 定义（<500行，遵循 skill-creator 标准）
├── README.md                 # 本文档
├── scripts/
│   ├── env-detect.sh         # 环境自动检测脚本
│   ├── backup.sh             # Docker 快照备份脚本
│   └── cleanup.sh            # 清理恢复脚本
├── references/
│   ├── protection-matrix.md  # 保护等级判定矩阵
│   └── edge-cases.md         # 边界情况详细处理
└── evals/
    └── evals.json            # 自动化评测用例
```

### 设计理念

遵循 [skill-creator](https://claude.ai/code) 标准：

- **渐进式加载**：SKILL.md 控制在 500 行以内，引用文件按需加载
- **DRY 原则**：公共逻辑抽取为独立脚本，避免多处方修改
- **可维护性**：环境检测/备份/清理各职责分离

---

## 测试结果

项目经过两轮自动化评测。

### 迭代 2 结果（旧版基线）

| 指标 | With Skill | Without Skill | 差异 |
|---|---|---|---|
| 通过率 | **100% ± 0%** | 17% ± 29% | **+83%** |
| Token 消耗 | 34,257 ± 8,191 | 28,991 ± 3,867 | +5,266 |
| 执行时间 | 300s | 300s | ±0s |

### 迭代 3 结果（优化版）

| 测试用例 | 验证项 | 结果 |
|---|---|---|
| **Eval 1** - 基础调用 | sbx 检测 + 沙箱推荐 + 保护矩阵 | ✅ 全部通过 |
| **Eval 2** - 完整参数 | 参数解析 + 确认摘要 | ✅ 全部通过 |
| **Eval 3** - 自然语言触发 | 环境检测 + 降级保护 | ✅ 全部通过 |
| **脚本语法** | env-detect.sh / backup.sh / cleanup.sh | ✅ 全部通过 |
| **env-detect 运行** | Git + sbx + 代理 + 磁盘完整检测 | ✅ 输出正确 |

---

## 边界情况

详细处理策略见 [边界情况文档](references/edge-cases.md)。快速参考：

| 情况 | 处理方式 |
|---|---|
| 用户取消 ralph-loop | 保护资源保持有效，不丢失数据 |
| sbx 启动超时 | 沙箱可能已创建，`sbx ls` 检查后连接 |
| sbx 策略未配置 | 显示 policy 配置指引，不自动创建 |
| Docker 快照验证失败 | 提示用户，选择是否继续 |
| 合并冲突 | 提示手动解决，保护分支暂保留 |
| Git submodule | 备份和回滚自动跳过子模块 |
| 代理环境 | 自动检测并传递代理设置 |
| 磁盘空间不足 | 跳过快照备份，仅 git 保护 |
| 中文路径 | sbx 可能失败，自动降级到 Docker/纯 git |

---

## 设计原则

1. **确认先行** — 必须获得用户确认才能启动 ralph-loop
2. **全程透明** — 每一步的命令和输出都向用户展示
3. **优先级递进** — sbx 沙箱 > Docker 容器 > git 分支 > 警告
4. **优雅降级** — 高级保护不可用时自动降级，不中断流程
5. **回滚安全** — 回滚操作不可逆，执行前二次确认
6. **Windows 兼容** — 适配 Git Bash 和 Windows 路径
7. **DRY 原则** — 公共逻辑抽取到独立脚本，便于维护
8. **渐进式** — SKILL.md 控制在 500 行以内，引用文件按需加载

---

## 许可

[MIT License](LICENSE)

---

## 相关资源

- [Claude Code](https://claude.ai/code) — AI 代码助手
- [Docker Sandbox](https://docs.docker.com/desktop/features/sandbox/) — 官方沙箱工具
- [ralph-loop 插件](https://github.com/claude-plugins-official/ralph-loop) — 自动迭代工具
- [skill-creator](https://claude.ai/code) — 标准 skill 创建方法论

---

## 贡献

欢迎提交 Issue 和 PR！如果你有新的边界情况需要处理，或者发现了优化空间：

1. Fork 本仓库
2. 创建特性分支（`git checkout -b feature/优化点`）
3. 提交修改（`git commit -m '优化: 新增XXX功能'`）
4. 推送到分支（`git push origin feature/优化点`）
5. 创建 Pull Request
