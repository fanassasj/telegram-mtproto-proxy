#!/bin/bash

echo "=== Telegram MTProto 代理卸载 ==="
echo ""
echo "警告: 此操作将："
echo "- 停止并删除所有容器"
echo "- 删除配置文件和数据"
echo "- 清除流量限制规则"
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
docker rm -f telegram-mtproto-proxy telegram-nginx 2>/dev/null

# 清除流量限制
IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -1)
tc qdisc del dev $IFACE root 2>/dev/null

# 删除定时任务
crontab -l 2>/dev/null | grep -v "alert.sh" | grep -v "report.sh" | crontab - 2>/dev/null

# 删除配置文件
rm -rf config/
rm -f .env docker compose.yml nginx-runtime.conf
rm -f /tmp/telegram-proxy-alert.log

echo ""
echo "✅ 卸载完成！"
echo ""
echo "保留的文件（可手动删除）："
echo "- 脚本文件: *.sh"
echo "- 说明文档: README.md"
echo "- 伪装页面: index.html"
