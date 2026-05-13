#!/bin/bash

echo "=== Telegram MTProto 代理配置 ==="
echo ""

# 检查 xxd 命令
if ! command -v xxd &> /dev/null; then
    echo "⚠️  缺少 xxd 命令，正在安装..."
    apt-get update -qq && apt-get install -y xxd -qq
    echo "✅ xxd 已安装"
    echo ""
fi

# 生成密钥和端口
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
PORT=$((RANDOM % 55535 + 10000))

echo "已生成新密钥"
echo "生成的端口: $PORT"
echo ""

USE_QUOTA=y
QUOTA_LIMIT_GB=30
QUOTA_RESET_DAY=1

# 询问是否启用告警
read -p "是否启用告警监控? (y/n, 默认 n): " USE_ALERT
USE_ALERT=${USE_ALERT:-n}

# 询问是否启用统计
read -p "是否启用使用统计? (y/n, 默认 n): " USE_STATS
USE_STATS=${USE_STATS:-n}

echo ""
echo "正在配置..."

# 生成 docker-compose.yml
cat > docker-compose.yml <<EOF
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: telegram-mtproto-proxy
    restart: unless-stopped
    ports:
      - "$PORT:443"
    environment:
      - SECRET=$SECRET
    volumes:
      - ./config:/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "443"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    sysctls:
      - net.ipv4.tcp_keepalive_time=600
      - net.ipv4.tcp_keepalive_intvl=60
      - net.ipv4.tcp_keepalive_probes=3
EOF

# 启动服务
docker compose up -d

echo ""
echo "设置月度流量限量..."
(crontab -l 2>/dev/null | grep -v "quota.sh"; echo "*/5 * * * * $(pwd)/quota.sh >> /dev/null 2>&1") | crontab -
./quota.sh >/dev/null 2>&1
echo "✅ 月度流量限量已启用: ${QUOTA_LIMIT_GB}GiB，每月 ${QUOTA_RESET_DAY} 号刷新"

# 设置告警
if [ "$USE_ALERT" = "y" ]; then
    echo ""
    echo "设置告警监控..."
    (crontab -l 2>/dev/null | grep -v "alert.sh"; echo "*/5 * * * * $(pwd)/alert.sh") | crontab -
    echo "✅ 告警监控已启用（每 5 分钟检查）"
fi

# 设置统计
if [ "$USE_STATS" = "y" ]; then
    echo ""
    echo "设置使用统计..."
    (crontab -l 2>/dev/null | grep -v "report.sh"; echo "0 * * * * $(pwd)/report.sh >> /dev/null 2>&1") | crontab -
    echo "✅ 使用统计已启用（每小时记录）"
fi

# 保存配置
cat > .env <<EOF
PORT=$PORT
SECRET=$SECRET
FAKE_TLS_DOMAIN=www.microsoft.com
USE_QUOTA=$USE_QUOTA
QUOTA_LIMIT_GB=$QUOTA_LIMIT_GB
QUOTA_RESET_DAY=$QUOTA_RESET_DAY
USE_ALERT=$USE_ALERT
USE_STATS=$USE_STATS
EOF

echo ""
echo "=========================================="
echo "✅ 代理已启动！"
echo "=========================================="
echo ""
./qrcode.sh

echo "管理命令:"
echo "- 查看连接: ./qrcode.sh"
echo "- 查看日志: docker compose logs -f"
echo "- 实时监控: ./monitor.sh"
echo "- 流量统计: ./stats.sh"
echo "- 使用报告: ./report.sh"
echo "- 停止服务: docker compose stop"
echo "- 重启服务: docker compose restart"
echo "- 完全卸载: ./uninstall.sh"
echo ""
echo "配置已保存到 .env 文件"
