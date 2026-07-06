#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
set -u

echo "=== Telegram MTProto 代理卸载 ==="
echo ""
echo "警告: 此操作将："
echo "- 停止并删除所有容器"
echo "- 删除配置文件和数据"
echo "- 删除月度流量限量任务"
echo "- 删除定时任务"
echo ""
read -p "确认卸载? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "正在卸载..."

# 停止并删除容器
docker compose down -v 2>/dev/null
docker rm -f telegram-mtproto-proxy 2>/dev/null

# 删除定时任务
crontab -l 2>/dev/null | grep -v "# telegram-mtproto-proxy" | crontab - 2>/dev/null

# 清理 systemd 服务
systemctl disable telegram-proxy.service 2>/dev/null
rm -f /etc/systemd/system/telegram-proxy.service
systemctl daemon-reload 2>/dev/null

# 清理 iptables 白名单规则
if command -v iptables >/dev/null 2>&1; then
    while iptables -D INPUT -m comment --comment "telegram-proxy" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D INPUT -m comment --comment "telegram-proxy-drop" -j DROP 2>/dev/null; do :; done
fi

# 删除配置文件
rm -rf config/
rm -f .env docker-compose.yml Dockerfile
rm -f /tmp/telegram-proxy-alert.log /tmp/telegram-proxy-traffic-last.total

echo ""
echo "✅ 卸载完成！"
echo ""
echo "保留的文件（可手动删除）："
echo "- 脚本文件: *.sh"
echo "- 说明文档: README.md"
