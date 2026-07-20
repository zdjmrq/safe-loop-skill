# 边界情况处理

本文件列出所有已知边界情况及对应处理策略。当遇到以下情况时，参考对应条目处理。

## 1. ralph-loop 被取消（/cancel-ralph）

如果用户在 ralph-loop 执行期间取消：
- 立即进入**清理恢复**阶段
- 保护分支和快照（Docker / sbx）仍然有效，数据不会丢失
- 提示用户保护资源的位置和恢复方式

## 2. 用户手动中断（Ctrl+C）

- **sbx 路径**：沙箱保持运行，可重新进入
- **宿主机路径**：保护分支保留在仓库中
- 若清理流程被中断，运行 `/ralph-recover` 手动清理

## 3. sbx 启动超时

sbx 在启动时可能报 `inspect exec: context deadline exceeded`，但沙箱实际已创建成功：
- 用 `sbx ls` 检查状态
- 如果 running 则直接用 `sbx exec -it <name> bash` 连接
- 如果 safe-ralph-loop 在宿主机运行，此超时不阻断流程

## 4. sbx 策略未配置

检测到 `SBX_POLICY:UNCONFIGURED` 时：
- 不自动创建沙箱
- 显示策略配置指南：
  ```bash
  sbx policy allow --type fs:mount:rw --resource "D:\项目路径"
  ```
- 配置后重新运行 `/safe-ralph-loop`
- 提供手动配置命令示例

## 5. 备份验证失败

```
⚠️ 快照备份验证未通过
   可能原因：磁盘空间不足、文件被锁定、Docker/sbx 异常
   建议：检查 Docker 状态后重试
```

让用户选择是否继续（回滚功能可能不可用）。

## 6. 合并冲突

合并保护分支时自动处理失败：
```
⚠️ 合并时出现冲突，无法自动合并
   冲突文件: <列表>
   请手动解决后 git commit
   保护分支 <名称> 暂保留，解决后可手动删除
```

## 7. Git submodule

- 回滚时 `find -delete` 自动跳过子模块目录
- 子模块需手动 `git submodule update --init --recursive` 恢复
- 备份时自动跳过 `.gitmodules` 中列出的子模块路径

## 8. 非 git 仓库

- 跳过分支保护
- 若 sbx 或 Docker 可用则继续提供隔离保护
- 否则仅警告，不强阻止

## 9. Docker Daemon 未运行 vs CLI 未安装

区分两种情况：
- **CLI 未安装**：`docker --version` 失败 → 提示安装 Docker Desktop
- **Daemon 未运行**：`docker info` 失败但 CLI 存在 → 提示启动 Docker Desktop
- 分别给出不同的解决方案建议

## 10. sbx 路径不在 PATH

使用多种方式定位 sbx：
1. 检查 PATH 中的 `sbx` 命令
2. 检查常见安装路径（`/c/Users/*/AppData/Local/DockerSandboxes/bin/sbx.exe`）
3. 如果找到但不在此用户 PATH 中，使用完整路径调用
4. 提示用户可将 sbx 加入 PATH：
   ```bash
   export PATH="$PATH:$HOME/AppData/Local/DockerSandboxes/bin"
   ```

## 11. 中/日文路径

sbx v0.35.0 在含中文/空格的路径上有 mount 策略拒绝问题：
- 如果当前项目路径含中文，建议走 Docker 或纯 git 保护模式
- 不强制用户更换路径

## 12. 代理环境

如果用户使用了 HTTP 代理（常见于中国大陆网络环境）：
- Docker 需要配置代理才能拉取镜像
- 检测 `HTTPS_PROXY` / `HTTP_PROXY` / `https_proxy` 环境变量
- 在 Docker 快照和容器命令中自动传递代理设置

## 13. macOS 兼容

虽然主要针对 Windows，部分用户可能在 macOS 上使用：
- 路径格式不同（`/Users/xxx` vs `/c/Users/xxx`）
- Docker 安装路径不同（`/Applications/Docker.app`）
- sbx 在 macOS 上的路径：`/usr/local/bin/sbx` 或通过 Homebrew 安装

## 14. 磁盘空间不足

- Docker 快照创建前检查可用空间（`df -h .`）
- 如果空间不足，警告用户并跳过快照，仅使用 git 分支保护
