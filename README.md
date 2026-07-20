# 🛡️ Safe Ralph Loop

**安全的 Ralph Loop 执行器** — 在运行 `ralph-loop` 时自动提供多层保护，防止代码丢失或项目被破坏，翻车了一键回滚。

---

## 为什么需要这个？

`ralph-loop` 会持续修改你的代码，如果不加保护：

- ❌ 改出 bug 了找不到原始代码
- ❌ 无限循环把项目改废了
- ❌ 想回滚发现没有备份

**Safe Ralph Loop** 就是给 ralph-loop 加的一层"安全气囊"。

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

### 🏰 四层保护体系

根据检测结果自动选择最优方案，保护不足时自动降级：

```
sbx 可用 ──→ 🟢 沙箱隔离（完全隔离，宿主机不受影响）
Docker+Git ─→ 🟢 标准保护（快照备份 + 分支保护）
仅有 Git ───→ 🟡 降级保护（分支保护保底）
都没有 ────→ 🔴 无保护（强烈建议中止）
```

### 🤖 Docker Sandbox (sbx)

当检测到 [Docker Sandbox](https://docs.docker.com/desktop/features/sandbox/) 时，优先推荐沙箱方案：

- 使用 `--clone` 模式，宿主机文件只读
- `sbx create` + `sbx exec` + `sbx cp` 完整工作流
- `sbx rm --force` 一键清理不留痕迹
- 自动检测策略配置，未配置时给出指引

### 📦 Docker 快照

Docker 可用时自动创建文件级快照：

- 使用 Docker volume 存储压缩归档
- 排除 `node_modules`、`.git` 等大目录
- 备份后自动验证完整性
- 支持从快照一键恢复

### 🌿 Git 分支保护

只要检测到 Git 仓库，都创建保护分支：

- 从**当前分支**创建（不硬编码 main/master）
- 自动 stash 未提交修改
- 结束后自由选择：保留 / 回滚 / 查看差异

### 🎯 智能参数提示

自动解析参数，用户未提供时主动询问补全：

```
📋 工作需求（prompt）:  <任务描述>
🔄 最大迭代次数:        10
🎯 完成条件:            ALL TESTS PASSING
```

### 🧹 自动清理

无论选择保留还是回滚，自动清理所有残留：

- 删除保护分支
- 清理 Docker 备份卷
- 删除 sbx 沙箱
- 清除临时元数据文件

---

## 安装

### 前置条件

| 依赖 | 是否必需 | 说明 |
|---|---|---|
| [Claude Code](https://claude.ai/code) | ✅ **必需** | 运行环境 |
| Git | ✅ **必需** | 用于分支保护 |
| Docker Desktop | ❌ 可选 | 用于快照备份 |
| [Docker Sandbox](https://docs.docker.com/desktop/features/sandbox/) | ❌ 可选 | 用于沙箱隔离 |

### 安装步骤

```bash
# 方式一：从 GitHub 克隆
git clone https://github.com/zdjmrq/safe-ralph-loop-skill.git
mkdir -p ~/.claude/skills/safe-ralph-loop
cp safe-ralph-loop-skill/SKILL.md ~/.claude/skills/safe-ralph-loop/

# 方式二：直接下载
mkdir -p ~/.claude/skills/safe-ralph-loop
curl -o ~/.claude/skills/safe-ralph-loop/SKILL.md \
  https://raw.githubusercontent.com/zdjmrq/safe-ralph-loop-skill/main/SKILL.md
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

**异常恢复：** 流程中断导致残留时可运行 `/ralph-recover` 手动清理。

---

## 工作流程

```
用户输入 /safe-ralph-loop "任务"
    │
    ├─ ① 环境检测
    │    ├─ sbx 是否安装并运行？
    │    ├─ Docker 是否可用？
    │    ├─ Git 是否可用？
    │    └─ 是否在容器内？
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

## 测试结果

项目自带完整的 eval 测试套件。迭代 2 测试结果：

| 指标 | With Skill | Without Skill | 差异 |
|---|---|---|---|
| 通过率 | **100%** | 17% | **+83%** |
| sbx 检测与推荐 | ✅ 5/5 | ❌ 0/5 | 正确检测 sbx 并推荐 |
| 无保护降级 | ✅ 3/3 | ❌ 0/3 | 优雅降级无报错 |
| 参数解析确认 | ✅ 2/2 | ⚠️ 1/2 | 正确解析并展示保护方案 |

---

## 设计原则

1. **确认先行** — 必须获得用户确认才能启动 ralph-loop
2. **全程透明** — 每一步的命令和输出都向用户展示
3. **优先级递进** — sbx 沙箱 > Docker 容器 > git 分支 > 警告
4. **优雅降级** — 高级保护不可用时自动降级，不中断流程
5. **回滚安全** — 回滚操作不可逆，执行前二次确认
6. **Windows 兼容** — 适配 Git Bash 和 Windows 路径

---

## 许可

MIT License

---

## 相关资源

- [Claude Code](https://claude.ai/code)
- [Docker Sandboxes](https://docs.docker.com/desktop/features/sandbox/)
- [ralph-loop 插件](https://github.com/claude-plugins-official/ralph-loop)
