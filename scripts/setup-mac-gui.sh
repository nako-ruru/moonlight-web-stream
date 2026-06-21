#!/bin/bash
set -e

CURRENT_USER=$(whoami)
echo "=== 当前 CI 主用户: $CURRENT_USER ==="

# 1. 放弃修改 runner 密码，直接创建一个全新的管理员用户 (完美绕过 Secure Token 限制)
echo "=== 正在创建全新的 VNC 专用测试用户 ==="
VNC_USER="vncuser"
# 使用 sysadminctl 创建一个带密码的全新管理员账户
sudo sysadminctl -addUser "$VNC_USER" -fullName "VNC User" -password "$USER_PASSWORD" -admin

# 2. 激活 macOS 原生屏幕共享 (开启全局访问权限)
echo "=== 正在启动 macOS 原生桌面共享 ==="
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate \
  -configure \
  -allowAccessFor -allUsers \
  -privs -all

# 3. 显式关闭只允许 VNC 独立密码的传统校验（强制走我们刚创建的系统账户认证）
sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist VNCPasswordAuthenticationCheck -bool false

# 4. 安装并正确启动 Tailscale
echo "=== 开始安装 Tailscale ==="
brew install tailscale

echo "=== 正在后台启动 tailscaled 守护进程 ==="
sudo /opt/homebrew/opt/tailscale/bin/tailscaled --tun=utun > /dev/null 2>&1 &
sleep 5

# 5. 认证并加入你的 Tailscale 网络
echo "=== 正在连接 Tailscale 虚拟网 ==="
sudo /opt/homebrew/bin/tailscale up --authkey="$TS_AUTHKEY" --hostname="mac-ci-node" --accept-dns=false

# 6. 打印最新的内网 IP 和登录凭据
echo "=================================================="
echo " Tailscale 连接成功！"
echo " 本台 Mac 的内网 IP 为: $(/opt/homebrew/bin/tailscale ip -4)"
echo "--------------------------------------------------"
echo " 📌 VNC 最新登录指引："
echo " 1. 打开本地 RealVNC Viewer，连上方的 IP"
echo " 2. 账号(Username) 必须输入: vncuser  (不再是 runner)"
echo " 3. 密码(Password) 输入: [你设置的 USER_PASSWORD]"
echo "=================================================="

# 7. 阻塞进程，保持会话 2 小时
echo "=== 保持会话中，你可以进行人工 GUI 测试... ==="
sleep 7200