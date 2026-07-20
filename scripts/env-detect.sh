#!/usr/bin/env bash
# Safe Ralph Loop — 环境检测脚本
# 跨 shell 进程共享检测结果：输出 KEY:VALUE 行供 Claude 解析
# 同时写入 $HOME/.safe-ralph-meta.sh 供后续步骤读取
# Usage: . ./scripts/env-detect.sh

set -o pipefail

META_FILE="$HOME/.safe-ralph-meta.sh"

# 初始化
rm -f "$META_FILE"

echo "# Safe Ralph Loop Meta" > "$META_FILE"

# ============================
# 1. Git 检测
# ============================
detect_git() {
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) && {
    echo "GIT_OK:YES"
    echo "export GIT_OK=true" >> "$META_FILE"

    local default_branch current_branch uncommitted
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@')
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    uncommitted=$(git status --porcelain 2>/dev/null | wc -l)

    echo "DEFAULT_BRANCH:${default_branch:-main}"
    echo "CURRENT_BRANCH:${current_branch}"
    echo "UNCOMMITTED_CHANGES:${uncommitted}"

    echo "export DEFAULT_BRANCH='${default_branch:-main}'" >> "$META_FILE"
    echo "export CURRENT_BRANCH='${current_branch}'" >> "$META_FILE"
    echo "export UNCOMMITTED_CHANGES='${uncommitted}'" >> "$META_FILE"
  } || {
    echo "GIT_OK:NO"
    echo "export GIT_OK=false" >> "$META_FILE"
  }
}

# ============================
# 2. Docker 检测
# ============================
detect_docker() {
  if docker --version >/dev/null 2>&1; then
    echo "DOCKER_CLI:AVAILABLE"
    echo "export DOCKER_CLI=true" >> "$META_FILE"

    if docker info >/dev/null 2>&1; then
      echo "DOCKER_DAEMON:RUNNING"
      echo "export DOCKER_DAEMON=true" >> "$META_FILE"
    else
      echo "DOCKER_DAEMON:STOPPED"
      echo "export DOCKER_DAEMON=false" >> "$META_FILE"
    fi
  else
    echo "DOCKER_CLI:UNAVAILABLE"
    echo "export DOCKER_CLI=false" >> "$META_FILE"
    echo "export DOCKER_DAEMON=false" >> "$META_FILE"
  fi

  # 是否已在容器内
  if [ -f /.dockerenv ] 2>/dev/null; then
    echo "IN_CONTAINER:YES"
    echo "export IN_CONTAINER=true" >> "$META_FILE"
  elif grep -qE 'docker|lxc|containerd' /proc/1/cgroup 2>/dev/null; then
    echo "IN_CONTAINER:YES"
    echo "export IN_CONTAINER=true" >> "$META_FILE"
  else
    echo "IN_CONTAINER:NO"
    echo "export IN_CONTAINER=false" >> "$META_FILE"
  fi
}

# ============================
# 3. sbx (Docker Sandbox) 检测
# ============================
detect_sbx() {
  local sbx_path=""

  # 方法 1: PATH 中的 sbx
  sbx_path=$(command -v sbx 2>/dev/null || true)

  # 方法 2: 常见安装路径（Windows）
  if [ -z "$sbx_path" ]; then
    sbx_path=$(find /c/Users -path "*/DockerSandboxes/bin/sbx.exe" 2>/dev/null | head -1 || true)
  fi

  # 方法 3: macOS 路径
  if [ -z "$sbx_path" ]; then
    [ -f "/usr/local/bin/sbx" ] && sbx_path="/usr/local/bin/sbx"
  fi

  if [ -n "$sbx_path" ]; then
    echo "SBX_INSTALLED:YES"
    echo "SBX_PATH:${sbx_path}"
    echo "export SBX_PATH='${sbx_path}'" >> "$META_FILE"
    echo "export SBX_INSTALLED=true" >> "$META_FILE"

    # 检查 daemon
    if "$sbx_path" daemon status >/dev/null 2>&1; then
      echo "SBX_DAEMON:RUNNING"
      echo "export SBX_DAEMON=true" >> "$META_FILE"
    else
      echo "SBX_DAEMON:STOPPED"
      echo "export SBX_DAEMON=false" >> "$META_FILE"
    fi

    # 策略检查
    if "$sbx_path" policy ls 2>/dev/null | grep -q 'fs:mount'; then
      echo "SBX_POLICY:CONFIGURED"
      echo "export SBX_POLICY=true" >> "$META_FILE"
    else
      echo "SBX_POLICY:UNCONFIGURED"
      echo "export SBX_POLICY=false" >> "$META_FILE"
    fi
  else
    echo "SBX_INSTALLED:NO"
    echo "export SBX_INSTALLED=false" >> "$META_FILE"
    echo "export SBX_DAEMON=false" >> "$META_FILE"
    echo "export SBX_POLICY=false" >> "$META_FILE"
  fi

  # sbx 沙箱内检测（环境变量方式）
  if env | grep -q SBX_ 2>/dev/null; then
    echo "IN_SBX_SANDBOX:YES"
    echo "export IN_SBX_SANDBOX=true" >> "$META_FILE"
  else
    echo "IN_SBX_SANDBOX:NO"
    echo "export IN_SBX_SANDBOX=false" >> "$META_FILE"
  fi
}

# ============================
# 4. 代理检测
# ============================
detect_proxy() {
  local proxy_vars=""
  for var in HTTPS_PROXY HTTP_PROXY https_proxy http_proxy ALL_PROXY all_proxy; do
    if [ -n "${!var}" ]; then
      proxy_vars="${proxy_vars} ${var}=${!var}"
      echo "PROXY_${var}:${!var}"
      echo "export ${var}='${!var}'" >> "$META_FILE"
    fi
  done
  if [ -n "$proxy_vars" ]; then
    echo "PROXY_DETECTED:YES"
    echo "export PROXY_DETECTED=true" >> "$META_FILE"
  else
    echo "PROXY_DETECTED:NO"
    echo "export PROXY_DETECTED=false" >> "$META_FILE"
  fi
}

# ============================
# 5. 磁盘空间检测
# ============================
detect_disk() {
  local available
  available=$(df -k . 2>/dev/null | tail -1 | awk '{print $4}')
  if [ -n "$available" ] && [ "$available" -lt 1048576 ] 2>/dev/null; then
    echo "DISK_SPACE:LOW (${available}KB available)"
    echo "export DISK_SPACE_LOW=true" >> "$META_FILE"
  else
    echo "DISK_SPACE:OK"
    echo "export DISK_SPACE_LOW=false" >> "$META_FILE"
  fi
}

# ============================
# 主流程
# ============================
detect_git
detect_docker
detect_sbx
detect_proxy
detect_disk

# 输出保护等级摘要
echo ""
echo "=== PROTECTION_SUMMARY ==="
if [ "$(grep SBX_DAEMON=true "$META_FILE" 2>/dev/null)" ]; then
  echo "LEVEL:GREEN_SBX"
elif [ "$(grep DOCKER_DAEMON=true "$META_FILE" 2>/dev/null)" ] && [ "$(grep GIT_OK=true "$META_FILE" 2>/dev/null)" ]; then
  echo "LEVEL:GREEN_STANDARD"
elif [ "$(grep GIT_OK=true "$META_FILE" 2>/dev/null)" ]; then
  echo "LEVEL:YELLOW_BASIC"
else
  echo "LEVEL:RED_NONE"
fi

echo "检测完成。元数据已写入: ${META_FILE}"
