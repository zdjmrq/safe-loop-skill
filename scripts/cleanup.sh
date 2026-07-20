#!/usr/bin/env bash
# Safe Ralph Loop — 清理恢复脚本
# 支持三种模式：保留(keep)、回滚(rollback)、查看差异(diff)
# Usage: . ./scripts/cleanup.sh <keep|rollback|diff>

set -o pipefail

META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"

# 默认值
CURRENT_BRANCH="${CURRENT_BRANCH:-}"
BRANCH_NAME="${BRANCH_NAME:-}"
TIMESTAMP="${TIMESTAMP:-}"
BACKUP_VOLUME="${BACKUP_VOLUME:-}"
SBX_PATH="${SBX_PATH:-}"
SANDBOX_NAME="${SANDBOX_NAME:-}"
GIT_OK="${GIT_OK:-false}"
DOCKER_DAEMON="${DOCKER_DAEMON:-false}"
PROXY_DETECTED="${PROXY_DETECTED:-false}"

# 代理参数
PROXY_ARGS=""
if [ "$PROXY_DETECTED" = "true" ]; then
  for var in HTTPS_PROXY HTTP_PROXY https_proxy http_proxy; do
    val="${!var}"
    [ -n "$val" ] && PROXY_ARGS="$PROXY_ARGS -e ${var}=${val}"
  done
fi

# Docker 快照排除列表（统一维护）
EXCLUDE_DIRS=(
  "node_modules" ".git" "target" "__pycache__" ".claude"
  ".venv" "venv" "dist" "build" ".next" "out"
)

build_exclude_args() {
  local prefix="${1:-}"
  for d in "${EXCLUDE_DIRS[@]}"; do
    echo -n "--exclude=${prefix}${d} "
  done
}

# ================================
# [1] 保留修改 — 合并回原始分支
# ================================
keep_changes() {
  echo "📦 正在保留修改..."

  if [ -n "$BRANCH_NAME" ] && [ "$GIT_OK" = "true" ]; then
    git checkout "${CURRENT_BRANCH}" 2>/dev/null
    if git merge "${BRANCH_NAME}" --no-edit 2>/dev/null; then
      echo "✅ 合并成功"
    else
      echo "⚠️ 合并冲突，请手动解决后提交"
      echo "  冲突文件: $(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')"
    fi
    git branch -D "${BRANCH_NAME}" 2>/dev/null || true

    # 恢复 stash
    if git stash list 2>/dev/null | grep -q "safe-ralph-auto-stash-${TIMESTAMP}"; then
      git stash pop 2>/dev/null && echo "✅ stash 恢复成功" || echo "⚠️ stash 冲突，请手动处理"
    fi
    echo "✅ 修改已合并到 ${CURRENT_BRANCH}"
  fi

  cleanup_backup
  cleanup_meta
}

# ================================
# [2] 回滚 — 从快照恢复
# ================================
rollback() {
  echo "⚠️ 正在执行回滚..."

  # 从 Docker 快照恢复
  if [ -n "$BACKUP_VOLUME" ] && [ "$DOCKER_DAEMON" = "true" ]; then
    if docker volume inspect "$BACKUP_VOLUME" >/dev/null 2>&1; then
      echo "📦 正在从 Docker 快照恢复..."

      # 安全清理工作目录（保留 .git）
      EXCLUDE_SUBMODULES=""
      if [ -f ".gitmodules" ]; then
        while IFS= read -r dir; do
          [ -n "$dir" ] && EXCLUDE_SUBMODULES="${EXCLUDE_SUBMODULES} -not -path './${dir}/*' -not -name '${dir}'"
        done < <(git config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}')
      fi

      # shellcheck disable=SC2086
      eval "find . -not -path './.git/*' -not -name '.git' ${EXCLUDE_SUBMODULES:-} -delete 2>/dev/null" || true

      if docker run --rm \
        -v "$(pwd):/workspace" \
        -v "${BACKUP_VOLUME}:/backup" \
        ${PROXY_ARGS} \
        alpine:latest \
        sh -c "tar xzf /backup/project-snapshot.tar.gz -C /workspace"; then
        echo "✅ Docker 快照恢复成功"
      else
        echo "❌ Docker 快照恢复失败！"
      fi
    fi
  fi

  # Git 恢复
  if [ -n "$BRANCH_NAME" ] && [ "$GIT_OK" = "true" ]; then
    git checkout "${CURRENT_BRANCH}" 2>/dev/null || git checkout --detach 2>/dev/null
    git branch -D "${BRANCH_NAME}" 2>/dev/null || true
    if git stash list 2>/dev/null | grep -q "safe-ralph-auto-stash-${TIMESTAMP}"; then
      git stash pop 2>/dev/null && echo "✅ stash 恢复成功" || echo "⚠️ stash 冲突，请手动处理"
    fi
  fi

  cleanup_backup
  cleanup_meta
  echo "✅ 回滚完成"
}

# ================================
# [3] 查看差异
# ================================
show_diff() {
  if [ -n "$BRANCH_NAME" ] && [ "$GIT_OK" = "true" ]; then
    echo "📊 改动统计："
    git diff "${CURRENT_BRANCH}...${BRANCH_NAME}" --stat
    echo ""
    echo "查看完整 diff：git diff ${CURRENT_BRANCH}...${BRANCH_NAME}"
  else
    echo "⚠️ 无法查看差异（缺少 git 信息）"
  fi
}

# ================================
# 通用清理
# ================================
cleanup_backup() {
  if [ -n "$BACKUP_VOLUME" ] && [ "$DOCKER_DAEMON" = "true" ] && docker volume inspect "$BACKUP_VOLUME" >/dev/null 2>&1; then
    docker volume rm "${BACKUP_VOLUME}" 2>/dev/null && echo "✅ Docker 备份卷已删除" || true
  fi

  # 清理本流程创建的已退出容器
  docker ps -a --filter "label=safe-ralph-loop" -q 2>/dev/null | xargs -r docker rm -v 2>/dev/null || true

  # 清理 sbx 残留
  if [ -n "$SBX_PATH" ] && [ -n "$SANDBOX_NAME" ]; then
    echo "💡 sbx 沙箱 ${SANDBOX_NAME} 仍然存在"
    echo "  清理命令: ${SBX_PATH} rm --force ${SANDBOX_NAME}"
  fi
}

cleanup_meta() {
  rm -f "$META_FILE" 2>/dev/null || true
}

# ================================
# 入口
# ================================
case "${1:-}" in
  keep)
    keep_changes
    ;;
  rollback)
    rollback
    ;;
  diff)
    show_diff
    ;;
  cleanup-backup)
    cleanup_backup
    cleanup_meta
    echo "🧹 清理完成"
    ;;
  *)
    echo "用法: . ./scripts/cleanup.sh <keep|rollback|diff|cleanup-backup>"
    exit 1
    ;;
esac
