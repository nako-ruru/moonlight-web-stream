#!/bin/bash
set -e

CURRENT_USER=$(whoami)
echo "=== 当前 CI 用户: $CURRENT_USER ==="

# 1. 强行修改当前用户密码 (绕过 macOS 14 Secure Token 限制)
echo "=== 正在配置用户密码 ==="
sudo sysadminctl -password "$USER_PASSWORD" -user "$CURRENT_USER" || true
# 如果 sysadminctl 仍受限，采用第二种 CI 常用 hack 方案
echo -e "\n$USER_PASSWORD" | sudo passwd "$CURRENT_USER"

# 2. 激活 macOS 原生屏幕共享 (使用标准系统用户认证，不再用 vncpasswd)
echo "=== 正在启动 macOS 原生桌面共享 ==="
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate \
  -configure \
  -allowAccessFor -allUsers \
  -privs -all

# 3. 允许 VNC 客户端使用传统的 VNC 认证/加密方式（防止第三方客户端连不上）
sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist VNCPasswordAuthenticationCheck -bool false

# 4. 安装并正确启动 Tailscale
echo "=== 开始安装 Tailscale ==="
brew install tailscale

echo "=== 正在后台启动 tailscaled 守护进程 ==="
# macOS 14 下必须指明正确的绝对路径，且不能使用 mem: 状态，让其走默认配置
sudo /opt/homebrew/opt/tailscale/bin/tailscaled --tun=utun > /dev/null 2>&1 &
sleep 5

# 5. 认证并加入你的 Tailscale 网络
echo "=== 正在连接 Tailscale 虚拟网 ==="
sudo /opt/homebrew/bin/tailscale up --authkey="$TS_AUTHKEY" --hostname="mac-ci-${CURRENT_USER}" --accept-dns=false

# 6. 打印内网 IP
echo "=================================================="
echo " Tailscale 连接成功！"
echo " 本台 Mac 的内网 IP 为: $(/opt/homebrew/bin/tailscale ip -4)"
echo "--------------------------------------------------"
echo " 📌 VNC 连接指引："
echo " 1. 打开本地 VNC Viewer，连接上方 IP"
echo " 2. 账号(Username): $CURRENT_USER"
echo " 3. 密码(Password): [你设置的 USER_PASSWORD]"
echo "=================================================="

# 7. 阻塞进程，保持会话 2 小时
echo "=== 保持会话中，你可以进行人工 GUI 测试... ==="
sleep 7200