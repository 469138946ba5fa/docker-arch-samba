#!/usr/bin/env ash
set -euo pipefail

# 载入公共函数（需确保 common.sh 也适配 Alpine 环境）
source "$(dirname "$0")/common.sh"

log_info "Starting Samba environment setup..."

# 定义一个重试安装所有包的函数
retry_apk_install_bulk() {
    attempts=1
    max_attempts=3
    sleep_seconds=2
    # "$@" 中包含所有包名
    while [ "$attempts" -le "$max_attempts" ]; do
        log_info "Installing packages in bulk (attempt $attempts/$max_attempts)"
        if apk add --no-cache "$@"; then
            log_info "All packages installed successfully."
            return 0
        else
            log_warning "Failed attempt $attempts to install packages, retrying after $sleep_seconds s..."
            sleep "$sleep_seconds"
        fi
        attempts=$(($attempts + 1))
    done
    log_error "Failed to install packages after $max_attempts attempts."
    exit 1
}

# 安装 Samba
log_info "Installing Samba..."

# 定义需要安装的软件包列表
apk_packages="shadow font-noto-cjk font-wqy-zenhei samba sudo"

log_info "Installing packages with retries..."
retry_apk_install_bulk $apk_packages

# 循环安装各软件包
#for pkg in ${apk_packages}; do
#  log_info "Installing linux packages individually with retries..."
#  retry_apk_install_bulk "${pkg}"
#done


# 以下操作在容器挂载的一瞬间就会改变，根本毫无意义
#log_info "Creating shared group ${GROUP_NAME} and configuring shared directory ${SHARE_DIR}"
# 自定义组与共享路径
#GROUP_NAME='sambashare'
#SHARE_DIR='/sharedir'
# 创建共享组（如果不存在）
#if ! getent group "${GROUP_NAME}" >/dev/null 2>&1; then
#    addgroup -S "${GROUP_NAME}"
#fi
# 设置属组为共享组，权限为 2775（含 setgid 位）
#chown root:"${GROUP_NAME}" "${SHARE_DIR}"
#chmod 2775 "${SHARE_DIR}"
# 限制其他用户访问，确保 root 和组用户可读写
#chmod g+rwxs,o-rwx "${SHARE_DIR}"

log_info "Samba setup is complete."
smbd --version