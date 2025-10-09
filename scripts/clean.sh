#!/usr/bin/env ash
set -euo pipefail

# 载入公共函数（需确保 common.sh 也适配 Alpine 环境）
source "$(dirname "$0")/common.sh"

log_info "Starting clean of System..."

# 清理 APK 缓存
clean_apk() {
  log_info "清理 APK 缓存..."
  apk cache clean || true
  rm -rf /var/cache/apk/* || true
}

# 清理系统日志
clean_logs() {
  log_info "清理系统日志..."
  find /var/log -type f -name "*.log" -delete
  rm -f /var/log/*.gz /var/log/*.1 /var/log/*.old || true
}

# 清理临时文件
clean_temp() {
  log_info "清理临时文件..."
  rm -fr /tmp/* /var/tmp/* || true
}

# 清理用户缓存
clean_user_cache() {
  log_info "清理所有用户的缓存..."
  log_info "清理 root 的缓存"
  [ -d "/root/.cache" ] && rm -fr "/root/.cache"/* 2>/dev/null || true
  for user_home in /home/*; do
    [ -d "${user_home}/.cache" ] || continue
    log_info "清理 ${user_home} 的缓存"
    rm -fr "${user_home}/.cache"/* 2>/dev/null || true
  done
}

# 清理历史记录
clean_history() {
  log_info "清理命令历史记录..."
  
  # 清理当前用户的历史
  if [ -n "${HISTFILE:-}" ]; then
      unset HISTFILE
      history -c || true
  fi

  # 清理 root 用户的历史
  [ -f /root/.ash_history ] && shred -u /root/.ash_history 2>/dev/null || true
  [ -f /root/.zsh_history ] && shred -u /root/.zsh_history 2>/dev/null || true

  # 清理所有用户的历史
  for user_home in /home/*; do
    [ -d "${user_home}" ] || continue
    if [ -f "${user_home}/.ash_history" ]; then
      shred -u "${user_home}/.ash_history" 2>/dev/null || true
    fi
    if [ -f "${user_home}/.zsh_history" ]; then
      shred -u "${user_home}/.zsh_history" 2>/dev/null || true
    fi
  done
}

# 执行清理操作
perform_cleanup() {
  log_info "执行系统清理..."
  clean_apk
  clean_logs
  clean_temp
  clean_user_cache
  clean_history
}

# 主逻辑
perform_cleanup

exit 0