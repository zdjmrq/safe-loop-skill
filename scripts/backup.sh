#!/usr/bin/env bash
# Safe Ralph Loop — 创建 Docker 快照备份
# Usage: . ./scripts/backup.sh

set -o pipefail

META_FILE="$HOME/.safe-ralph-meta.sh"
[ -f "$META_FILE" ] && . "$META_FILE"

TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
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

# 统一排除列表
EXCLUDE_DIRS=(
  "node_modules" ".git" "target" "__pycache__" ".claude"
  ".venv" "venv" "dist" "build" ".next" "out"
)

build_exclude_cmd() {
  for d in "${EXCLUDE_DIRS[@]}"; do
    echo -n "--exclude=${d} "
  done
}

# 检查 Docker Daemon
if [ "$DOCKER_DAEMON" != "true" ]; then
  echo "DOCKER_BACKUP:SKIPPED (daemon not running)"
  exit 0
fi

# 检查磁盘空间
AVAILABLE=$(df -k . 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -lt 512000 ] 2>/dev/null; then
  echo "⚠️ 磁盘空间不足 (${AVAILABLE}KB)，跳过快照备份"
  echo "DOCKER_BACKUP:SKIPPED (low disk space)"
  exit 0
fi

# 创建备份卷
BACKUP_VOLUME="ralph-backup-${TIMESTAMP}"
while docker volume inspect "${BACKUP_VOLUME}" >/dev/null 2>&1; do
  BACKUP_VOLUME="ralph-backup-${TIMESTAMP}-$RANDOM"
done

docker volume create "${BACKUP_VOLUME}" >/dev/null
echo "📦 正在创建 Docker 快照备份..."

# 构建排除参数
EXCLUDE_CMD=$(build_exclude_cmd)

# shellcheck disable=SC2086
if docker run --rm \
  -v "$(pwd):/workspace:ro" \
  -v "${BACKUP_VOLUME}:/backup" \
  ${PROXY_ARGS} \
  alpine:latest \
  sh -c "
    cd /workspace
    tar czf /backup/project-snapshot.tar.gz ${EXCLUDE_CMD} .
  "; then

  # 验证备份完整性
  if docker run --rm \
    -v "${BACKUP_VOLUME}:/backup" \
    alpine:latest \
    sh -c "tar tzf /backup/project-snapshot.tar.gz >/dev/null 2>&1 && echo 'BACKUP_VERIFIED' || echo 'BACKUP_FAILED'"; then

    echo "BACKUP_VOLUME:${BACKUP_VOLUME}"
    echo "export BACKUP_VOLUME='${BACKUP_VOLUME}'" >> "$META_FILE"
    echo "✅ Docker 快照创建并验证通过"
  else
    echo "⚠️ 快照验证失败，检查 Docker 状态后重试"
    docker volume rm "${BACKUP_VOLUME}" 2>/dev/null || true
  fi
else
  echo "❌ Docker 快照创建失败"
  docker volume rm "${BACKUP_VOLUME}" 2>/dev/null || true
fi
