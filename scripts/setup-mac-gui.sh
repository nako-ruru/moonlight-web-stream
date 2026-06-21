#!/bin/bash
set -e

# 1. 动态获取当前 CI 的环境用户名（GitHub 是 runner，CircleCI 是 circleci）
CURRENT_USER=$(whoami)
echo "=== 当前 CI 用户: $CURRENT_USER ==="

# 2. 使用现代 sysadminctl 工具强制重置当前用户密码（无需旧密码）
sudo sysadminctl -resetPasswordFor "$CURRENT_USER" -newPassword "$USER_PASSWORD"

# 3. 激活 macOS 原生屏幕共享服务 (VNC)
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -access -on \
  -clientopts -setvncpasswd -vncpasswd "$USER_PASSWORD" \
  -restart -agent -privs -all
echo "=== macOS VNC 服务已成功启动 ==="

# 4. 安装并启动 Tailscale
echo "=== 开始安装 Tailscale ==="
brew install tailscale

# 绕过 brew services 的权限界限，直接用 root 权限在后台拉起 tailscaled 守护进程
BREW_PREFIX=$(brew --prefix)
sudo "$BREW_PREFIX/sbin/tailscaled" --state=mem: > /dev/null 2>&1 &
sleep 3

# 5. 认证并加入你的 Tailnet 内网
echo "=== 正在连接 Tailscale 虚拟网 ==="
sudo tailscale up --authkey="$TS_AUTHKEY" --hostname="mac-ci-${CURRENT_USER}" --accept-dns=false

# 6. 打印内网 IP
echo "=================================================="
echo " Tailscale 连接成功！"
echo " 本台 Mac 的内网 IP 为: $(tailscale ip -4)"
echo " 现在你可以打开本地的 VNC Viewer，输入上方 IP 进行连接。"
echo " 登录用户: $CURRENT_USER  密码: [你设置的 USER_PASSWORD]"
echo "=================================================="

# 7. 阻塞进程，防止 CI 脚本执行完后虚拟机直接关闭（此处维持会话 2 小时，可自行调整）
echo "=== 保持会话中，你可以进行人工 GUI 测试... ==="
sleep 7200