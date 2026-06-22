#!/bin/bash
set -e

CURRENT_USER=$(whoami)
echo "=== 当前 CI 主用户: $CURRENT_USER ==="

# 1. 创建全新的管理员用户 (避开 Secure Token 限制)
echo "=== 正在创建全新的 VNC 专用测试用户 ==="
VNC_USER="vncuser"
sudo sysadminctl -addUser "$VNC_USER" -fullName "VNC User" -password "$VNC_PASSWORD" -admin

# 2. 修复 macOS 14 Sonoma 专属的 "不允许屏幕共享" 冲突
echo "=== 正在清理并重置 macOS 屏幕共享服务 ==="
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
sudo launchctl disable system/com.apple.screensharing 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist ScreenSharingAllowed -bool true
sudo launchctl enable system/com.apple.screensharing
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
sudo launchctl kickstart -kp system/com.apple.screensharing
echo "=== 屏幕共享服务重置完成 ==="

# 3. 安装并正确启动 Tailscale
echo "=== 开始安装 Tailscale ==="
brew install tailscale
sudo /opt/homebrew/opt/tailscale/bin/tailscaled --tun=utun > /dev/null 2>&1 &
sleep 5

# 4. 认证并加入你的 Tailscale 网络
echo "=== 正在连接 Tailscale 虚拟网 ==="
sudo /opt/homebrew/bin/tailscale up --authkey="$TS_AUTHKEY" --hostname="mac-ci-node" --accept-dns=false

# 5. 打印最新的内网 IP 和登录凭据
echo "=================================================="
echo " Tailscale 连接成功！"
echo " 本台 Mac 的内网 IP 为: $(/opt/homebrew/bin/tailscale ip -4)"
echo "--------------------------------------------------"
echo " 📌 登录指引："
echo " 账号(Username): vncuser"
echo " 密码(Password): [你设置的 VNC_PASSWORD]"
echo "=================================================="

# 6. 阻塞进程保持连接
sleep 7200