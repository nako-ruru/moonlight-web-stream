#!/bin/bash
set -e

CURRENT_USER=$(whoami)
echo "=== 当前 CI 主用户: $CURRENT_USER ==="

# 1. 创建全新的管理员用户 (加入 || true 防止由于用户已存在导致脚本中断)
echo "=== 正在创建全新的 VNC 专用测试用户 ==="
VNC_USER="vncuser"
sudo sysadminctl -addUser "$VNC_USER" -fullName "VNC User" -password "$VNC_PASSWORD" -admin || true

# 2. 干净配置 macOS 14 屏幕共享 (移除易碎的 SQLite 注入代码)
echo "=== 正在清理并配置 macOS 屏幕共享服务 ==="

# 停止可能冲突的旧 ARD 服务
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop || true

# 强制卸载并初始化屏幕共享服务状态
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
sudo launchctl disable system/com.apple.screensharing 2>/dev/null || true

# 写入全局系统配置覆盖层：显式允许原生屏幕共享服务
sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist ScreenSharingAllowed -bool true
sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false

# ==========================================================
# 核心安全修复：直接操作 macOS 官方 ACL 权限组，优雅避开 TCC.db 结构变动
# ==========================================================
echo "=== 正在将测试用户注入系统屏幕共享白名单组 ==="
# 确保系统级屏幕共享控制组存在，若不存在则创建
sudo dscl . -read /Groups/com.apple.access_screensharing > /dev/null 2>&1 || sudo dseditgroup -o create -q com.apple.access_screensharing

# 将新用户以及当前跑 CI 的主用户均添加进允许远程连接的白名单中
sudo dseditgroup -o edit -a "$VNC_USER" -t user com.apple.access_screensharing
sudo dseditgroup -o edit -a "$CURRENT_USER" -t user com.apple.access_screensharing

# 3. 重新启用并干净拉起屏幕共享守护进程
sudo launchctl enable system/com.apple.screensharing
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
sudo launchctl kickstart -k system/com.apple.screensharing
echo "=== 屏幕共享权限组与服务配置完成 ==="

# 4. 安装并正确启动 Tailscale
echo "=== 开始安装 Tailscale ==="
brew install tailscale
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
echo " 📌 登录指引："
echo " 账号(Username): vncuser"
echo " 密码(Password): [你设置的 VNC_PASSWORD]"
echo "=================================================="

# 7. 阻塞进程保持连接 2 小时以供调试
sleep 7200