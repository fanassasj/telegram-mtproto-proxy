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
SECRET=$(head -c 32 /dev/urandom | xxd -ps)
PORT=$((RANDOM % 55535 + 10000))

echo "生成的密钥: $SECRET"
echo "生成的端口: $PORT"
echo ""

# 询问是否启用 Nginx 伪装
read -p "是否启用 Nginx 伪装? (y/n, 默认 n): " USE_NGINX
USE_NGINX=${USE_NGINX:-n}

# 询问是否设置流量限制
read -p "是否设置流量限制? (y/n, 默认 n): " USE_LIMIT
USE_LIMIT=${USE_LIMIT:-n}

if [ "$USE_LIMIT" = "y" ]; then
    read -p "输入限制速率 (默认 10mbit): " LIMIT_RATE
    LIMIT_RATE=${LIMIT_RATE:-10mbit}
fi

# 询问是否启用告警
read -p "是否启用告警监控? (y/n, 默认 n): " USE_ALERT
USE_ALERT=${USE_ALERT:-n}

# 询问是否启用统计
read -p "是否启用使用统计? (y/n, 默认 n): " USE_STATS
USE_STATS=${USE_STATS:-n}

echo ""
echo "正在配置..."

# 生成 docker-compose.yml
if [ "$USE_NGINX" = "y" ]; then
    # 先生成 Nginx 配置文件
    cat > nginx-runtime.conf <<'NGINX_EOF'
upstream mtproxy {
    server mtproto-proxy:443;
}

server {
    listen 80;
    server_name _;
    
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}

server {
    listen PORT_PLACEHOLDER;
    server_name _;
    
    location / {
        proxy_pass http://mtproxy;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX_EOF
    sed -i "s/PORT_PLACEHOLDER/$PORT/g" nginx-runtime.conf

    cat > docker-compose.yml <<EOF
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: telegram-mtproto-proxy
    restart: unless-stopped
    ports:
      - "127.0.0.1:8443:443"
    environment:
      - SECRET=$SECRET
    volumes:
      - ./config:/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - proxy-net
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

  nginx:
    image: nginx:alpine
    container_name: telegram-nginx
    restart: unless-stopped
    ports:
      - "$PORT:$PORT"
    volumes:
      - ./nginx-runtime.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - mtproto-proxy
    networks:
      - proxy-net
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 64M

networks:
  proxy-net:
    driver: bridge
EOF
else
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
fi

# 启动服务
docker compose up -d

# 设置流量限制
if [ "$USE_LIMIT" = "y" ]; then
    echo ""
    echo "设置流量限制..."
    IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -1)
    tc qdisc del dev $IFACE root 2>/dev/null
    tc qdisc add dev $IFACE root handle 1: htb default 10
    tc class add dev $IFACE parent 1: classid 1:1 htb rate $LIMIT_RATE ceil $((${LIMIT_RATE%mbit}*2))mbit
    tc filter add dev $IFACE protocol ip parent 1:0 prio 1 u32 match ip dport $PORT 0xffff flowid 1:1
    echo "✅ 流量限制已设置: $LIMIT_RATE (接口: $IFACE)"
fi

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
USE_NGINX=$USE_NGINX
USE_LIMIT=$USE_LIMIT
LIMIT_RATE="$LIMIT_RATE"
USE_ALERT=$USE_ALERT
USE_STATS=$USE_STATS
EOF

echo ""
echo "=========================================="
echo "✅ 代理已启动！"
echo "=========================================="
echo ""
echo "连接信息："
echo "- 端口: $PORT"
echo "- 密钥: $SECRET"
echo ""
echo "连接链接:"
echo "tg://proxy?server=YOUR_SERVER_IP&port=$PORT&secret=$SECRET"
echo ""

if [ "$USE_NGINX" = "y" ]; then
    echo "伪装网站: http://YOUR_SERVER_IP"
    echo ""
fi

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
echo ""
echo "提示: 运行 ./qrcode.sh 生成二维码"
