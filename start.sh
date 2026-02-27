#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1


require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "错误: 缺少依赖命令 $1"
        exit 1
    fi
}

check_prereqs() {
    require_command docker
    require_command od

    if ! docker compose version >/dev/null 2>&1; then
        echo "错误: 未检测到 docker compose，请先安装 Docker Compose 插件"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "错误: Docker 服务未运行，请先启动 Docker"
        exit 1
    fi
}

generate_secret() {
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

is_port_free() {
    local port="$1"
    local pattern="(^|[:.])${port}$"

    if command -v ss >/dev/null 2>&1; then
        ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "$pattern"
    elif command -v netstat >/dev/null 2>&1; then
        ! netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "$pattern"
    else
        return 0
    fi
}

generate_port() {
    local candidate
    local raw
    local i

    for ((i=0; i<50; i++)); do
        raw=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
        candidate=$((raw % 55536 + 10000))
        if is_port_free "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done

    echo "错误: 无法找到空闲端口，请稍后重试"
    exit 1
}

calc_ceil_rate() {
    local rate="$1"
    local normalized="${rate,,}"

    if [[ "$normalized" =~ ^([0-9]+)(kbit|mbit|gbit)$ ]]; then
        echo "$((BASH_REMATCH[1] * 2))${BASH_REMATCH[2]}"
    else
        echo "$rate"
    fi
}

apply_traffic_limit() {
    local rate="$1"
    local port="$2"
    local iface
    local normalized_rate
    local ceil_rate

    if ! command -v ip >/dev/null 2>&1 || ! command -v tc >/dev/null 2>&1; then
        echo "⚠️  未找到 ip/tc 命令，跳过流量限制"
        return 1
    fi

    iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -1)
    if [ -z "$iface" ]; then
        echo "⚠️  未找到可用网卡，跳过流量限制"
        return 1
    fi

    normalized_rate="${rate,,}"
    ceil_rate=$(calc_ceil_rate "$normalized_rate")
    tc qdisc del dev "$iface" root 2>/dev/null
    tc qdisc add dev "$iface" root handle 1: htb default 10 || return 1
    tc class add dev "$iface" parent 1: classid 1:1 htb rate "$normalized_rate" ceil "$ceil_rate" || return 1
    tc filter add dev "$iface" protocol ip parent 1:0 prio 1 u32 match ip dport "$port" 0xffff flowid 1:1 || return 1

    echo "✅ 流量限制已设置: $normalized_rate (接口: $iface)"
}

is_valid_rate() {
    local rate="${1,,}"
    [[ "$rate" =~ ^[0-9]+(kbit|mbit|gbit)$ ]]
}

sanitize_rate() {
    echo "${1,,}"
}

check_prereqs

echo "=== Telegram MTProto 代理配置 ==="
echo ""

# 生成密钥和端口
SECRET=$(generate_secret)
PORT=$(generate_port)

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
    LIMIT_RATE=$(sanitize_rate "$LIMIT_RATE")
    if ! is_valid_rate "$LIMIT_RATE"; then
        echo "⚠️  限速格式无效，已使用默认值 10mbit"
        LIMIT_RATE="10mbit"
    fi
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
    sysctls:
      - net.ipv4.tcp_keepalive_time=600
      - net.ipv4.tcp_keepalive_intvl=60
      - net.ipv4.tcp_keepalive_probes=3

  nginx:
    image: nginx:alpine
    container_name: telegram-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "$PORT:$PORT"
    volumes:
      - ./index.html:/usr/share/nginx/html/index.html:ro
      - ./nginx-runtime.conf:/etc/nginx/conf.d/default.conf:ro
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
    sysctls:
      - net.ipv4.tcp_keepalive_time=600
      - net.ipv4.tcp_keepalive_intvl=60
      - net.ipv4.tcp_keepalive_probes=3
EOF
fi

# 确保必需目录/文件存在
mkdir -p config
if [ "$USE_NGINX" = "y" ] && [ ! -f index.html ]; then
    cat > index.html <<'HTML_EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Welcome</title>
    <style>
        body { font-family: Arial; text-align: center; padding: 50px; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Welcome</h1>
    <p>This is a personal website.</p>
</body>
</html>
HTML_EOF
fi

# 启动服务
if ! docker compose up -d; then
    echo "❌ 启动失败，请检查日志: docker compose logs --tail 100"
    exit 1
fi

# 设置流量限制
if [ "$USE_LIMIT" = "y" ]; then
    echo ""
    echo "设置流量限制..."
    apply_traffic_limit "$LIMIT_RATE" "$PORT" || echo "⚠️  流量限制设置失败，请检查 tc 参数"
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
