#!/usr/bin/env ash
set -euo pipefail

# 加载公共函数（请确保 common.sh 也适配 Alpine 下的 ash）
source "$(dirname "$0")/common.sh"

# 定义日志文件并确保 /var/log 存在
LOG_FILE="/var/log/samba_startup.log"
if [ ! -d "/var/log" ]; then
  log_error "/var/log directory does not exist. Please check volume mounts."
  exit 1
fi

# 将所有后续标准输出和错误追加到日志文件中
exec > >(tee -a "${LOG_FILE}") 2>&1

log_info "Starting Samba service..."

# 检查关键命令是否存在
for cmd in smbd; do
  if ! command_exists "$cmd"; then
    log_error "$cmd is not installed. Aborting."
    exit 1
  fi
done

# ---------------- Samba 配置 ----------------
# 设置环境变量 USER_NAME 与 PASSWORD（如果未定义则提供默认值）
USER_NAME=${USER_NAME:-root}
PASSWORD=${PASSWORD:-123456}
log_info "Setting USER_NAME=${USER_NAME} for Samba"
log_info "Setting PASSWORD for Samba (value hidden)"

# 如果 /etc/samba/smb.conf 不存在，则从备份目录复制，并替换其中的占位符
if [ ! -f /etc/samba/smb.conf ]; then
    if [ -f /etc/samba.bak/smb.conf ]; then
      cp -fv /etc/samba.bak/smb.conf /etc/samba/smb.conf
      # 替换配置文件中 " = replace" 为 " = <USER_NAME>"
      sed -i "s/ = replace/ = ${USER_NAME}/g" /etc/samba/smb.conf
      # 调用 testparm 检查配置（如果支持）
      echo "" | testparm
    else
      log_warning "Backup smb.conf not found, skipping configuration copy."
    fi
fi

# 判断 /etc/samba/smbpasswd 是否存在，不存在则设置 Samba 用户（以及系统用户、组）
if [ ! -f /etc/samba/smbpasswd ]; then
    if [ "$USER_NAME" = "root" ]; then
        log_info "Default user is root; skipping user/group creation."
    else
        # 创建系统组（-S 表示系统组）
        addgroup -S "${USER_NAME}"
        # 创建系统用户，不进行密码交互，并将其加入刚创建的组
        adduser -D -S -G "${USER_NAME}" "${USER_NAME}"
    fi
    # 设置 sudo 权限（NOPASSWD 模式），确保该用户使用 sudo 时无需输入密码
    echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"${USER_NAME}"
    chmod 0440 /etc/sudoers.d/"${USER_NAME}"
    
    # 输出用户信息以便核对
    id "${USER_NAME}"
    
    # 非交互方式设置系统密码
    echo "${USER_NAME}:${PASSWORD}" | chpasswd
    
    # 更新登录密码并设置 Samba 密码（通过管道传递密码两次）
    printf "%s\n%s\n" "${PASSWORD}" "${PASSWORD}" | passwd "${USER_NAME}"
    printf "%s\n%s\n" "${PASSWORD}" "${PASSWORD}" | smbpasswd -a "${USER_NAME}"
fi

# ---------------- 启动 Samba ----------------
log_info "Launching Samba on ports 139 and 445..."
/usr/sbin/smbd
tail -f /var/log/samba/log.smbd