#!/usr/bin/env ash
set -euo pipefail

# 载入公共函数（需确保 common.sh 也适配 Alpine 环境）
source "$(dirname "$0")/common.sh"

log_info "Starting system initialization..."

# 设置目标时区
TZ='Asia/Shanghai'

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

# 更新 apk 索引
apk update

# 定义需要安装的软件包列表
apk_packages="tzdata tini ca-certificates coreutils"

log_info "Installing packages with retries..."
retry_apk_install_bulk $apk_packages

# 循环安装各软件包
#for pkg in ${apk_packages}; do
#  log_info "Installing linux packages individually with retries..."
#  retry_apk_install_bulk "${pkg}"
#done

# 配置时区：复制指定时区文件到 /etc/localtime 并写入 /etc/timezone
cp /usr/share/zoneinfo/"$TZ" /etc/localtime
echo "$TZ" > /etc/timezone

# 对比当前系统时间与目标时区（上海）的时间
compare_time() {
    current_time=$(date '+%Y-%m-%d %T')
    shanghai_time=$(TZ="$TZ" date '+%Y-%m-%d %T')
    echo "Current time: ${current_time} <-> Shanghai time: ${shanghai_time}"
}
compare_time

# 配置中文 locale
echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen
if command -v locale-gen >/dev/null 2>&1; then
    locale-gen zh_CN.UTF-8
else
    log_warning "locale-gen not found. Skipping locale generation."
fi

# 导出中文环境变量
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export LANGUAGE=zh_CN.UTF-8
export LC_CTYPE=zh_CN.UTF-8

# 直接将环境变量配置写入到全局和用户登录配置中，
# 确保所有 shell（例如 ash、bash 等）启动时都加载相同的 locale 设置
for file in /etc/profile "${HOME}/.profile"; do
  echo "export LANG=zh_CN.UTF-8" >> "$file"
  echo "export LC_ALL=zh_CN.UTF-8" >> "$file"
  echo "export LANGUAGE=zh_CN.UTF-8" >> "$file"
  echo "export LC_CTYPE=zh_CN.UTF-8" >> "$file"
done

log_info "System initialization completed."
