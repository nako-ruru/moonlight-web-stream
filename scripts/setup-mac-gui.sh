#!/bin/bash
set -e

CURRENT_USER=$(whoami)
echo "=== 当前 CI 主用户: $CURRENT_USER ==="

# 1. 创建全新的管理员用户 (避开 Secure Token 限制)
echo "=== 正在创建全新的 VNC 专用测试用户 ==="
VNC_USER="vncuser"
sudo sysadminctl -addUser "$VNC_USER" -fullName "VNC User" -password "$VNC_PASSWORD" -admin

# 2. 修复 macOS 14 Sonoma 专属的 "不允许屏幕共享" 冲突
# ==========================================================
# 终极修复：针对 macOS 14 Sonoma 的系统权限深层重置
# ==========================================================
echo "=== 开始针对 macOS 14 深入重置屏幕共享与沙盒权限 ==="

# 1. 深度彻底物理抹去 ARD (Remote Management)
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop
sudo rm -rf /Library/Preferences/com.apple.RemoteManagement.plist
sudo rm -rf /Library/Preferences/com.apple.ARDAgent.plist

# 2. 写入全局Overrides配置：明确允许原生屏幕共享服务
# 这确保系统不会因为找不到物理显示器或处于Headless状态而禁用它
sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false

# 3. 核心步骤：直接使用 root 权限强行注入 TCC (透明度、同意和控制) 数据库
# 这一步将强制授予原生屏幕共享进程 kTCCServiceScreenCapture (屏幕录制) 权限，
# 从而彻底解决由于没有物理交互界面导致权限卡死的黑屏或不允许连接错误。
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
# 如果数据库由于 Sandbox 保护不可写，尝试赋予写权限后注入
sudo chmod o+w "$TCC_DB"
sudo sqlite3 "$TCC_DB" "REPLACE INTO access VALUES('kTCCServiceScreenCapture','com.apple.screensharingd',0,1,1,NULL,NULL,NULL,'UNUSED',NULL,0,$(date +%s));"
# 恢复 TCC.db 的默认权限
sudo chmod 644 "$TCC_DB"

# 4. 深度重启 screensharing 服务
echo "=== 正在强制重启并激活新的屏幕共享服务线程 ==="
sudo launchctl disable system/com.apple.screensharing || true
sudo launchctl enable system/com.apple.screensharing
# 使用 launchctl kickstart -k (kill) 强制杀掉旧的僵尸进程并拉起全新的
sudo launchctl kickstart -k system/com.apple.screensharing
sleep 3
echo "=== 屏幕共享系统级沙盒重置完成 ==="
# ==========================================================

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