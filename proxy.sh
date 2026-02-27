#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1


# Telegram MTProto Proxy 一体化管理脚本

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "错误: 未安装 Docker"
        return 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        echo "错误: 未检测到 docker compose，请先安装 Docker Compose 插件"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "错误: Docker 服务未运行，请先启动 Docker"
        return 1
    fi

    return 0
}

ensure_docker_or_return() {
    if ! require_docker; then
        echo ""
        read -p "按回车键继续..."
        return 1
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

    return 1
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

url_encode() {
    local raw="$1"
    echo -n "$raw" | jq -sRr @uri 2>/dev/null || \
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip()))" <<< "$raw" 2>/dev/null || \
    echo "$raw"
}

load_env_config() {
    local env_file="${1:-.env}"
    local key value

    if [ ! -f "$env_file" ]; then
        echo "错误: 未找到配置文件 $env_file"
        return 1
    fi

    PORT=""
    SECRET=""
    USE_NGINX="n"
    USE_LIMIT="n"
    LIMIT_RATE=""
    USE_ALERT="n"
    USE_STATS="n"

    while IFS='=' read -r key value; do
        key=$(echo "$key" | tr -d ' \t\r')
        value=$(echo "$value" | tr -d '\r')
        value="${value%\"}"
        value="${value#\"}"

        case "$key" in
            PORT|SECRET|USE_NGINX|USE_LIMIT|LIMIT_RATE|USE_ALERT|USE_STATS)
                printf -v "$key" '%s' "$value"
                ;;
        esac
    done < "$env_file"

    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "错误: 配置文件中的 PORT 无效"
        return 1
    fi

    if ! [[ "$SECRET" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "错误: 配置文件中的 SECRET 无效"
        return 1
    fi

    if [ "$USE_LIMIT" = "y" ] && [ -n "$LIMIT_RATE" ]; then
        LIMIT_RATE=$(sanitize_rate "$LIMIT_RATE")
        if ! is_valid_rate "$LIMIT_RATE"; then
            echo "错误: 配置文件中的 LIMIT_RATE 无效"
            return 1
        fi
    fi

    return 0
}

is_valid_ipv4() {
    local ip="$1"
    local IFS='.'
    local octets
    local octet

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    read -r -a octets <<< "$ip"
    [ "${#octets[@]}" -eq 4 ] || return 1

    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    return 0
}

is_valid_cidr() {
    local cidr="$1"
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"

    [ "$cidr" != "$ip" ] || return 1
    is_valid_ipv4 "$ip" || return 1
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ]
}

ensure_whitelist_drop_rule() {
    local port="$1"

    if iptables -C INPUT -p tcp --dport "$port" -m comment --comment "telegram-proxy-drop" -j DROP 2>/dev/null; then
        return 0
    fi

    iptables -A INPUT -p tcp --dport "$port" -m comment --comment "telegram-proxy-drop" -j DROP
}

show_self_check() {
    echo ""
    echo "=== 环境自检 ==="
    echo ""

    if command -v docker >/dev/null 2>&1; then
        echo "Docker: ✅ 已安装"
    else
        echo "Docker: ❌ 未安装"
    fi

    if command -v docker >/dev/null 2>&1; then
        if docker compose version >/dev/null 2>&1; then
            echo "Docker Compose: ✅ 可用"
        else
            echo "Docker Compose: ❌ 不可用"
        fi

        if docker info >/dev/null 2>&1; then
            echo "Docker Daemon: ✅ 运行中"
        else
            echo "Docker Daemon: ❌ 未运行/无权限"
        fi
    else
        echo "Docker Compose: ❌ 不可用"
        echo "Docker Daemon: ❌ 未运行/无权限"
    fi

    if [ -f .env ] && load_env_config .env >/dev/null 2>&1; then
        echo ".env 配置: ✅ 有效 (PORT=$PORT)"
    elif [ -f .env ]; then
        echo ".env 配置: ❌ 存在但无效"
    else
        echo ".env 配置: ⚠️ 未找到"
    fi

    if [ -f docker-compose.yml ]; then
        echo "docker-compose.yml: ✅ 存在"
    else
        echo "docker-compose.yml: ⚠️ 未找到"
    fi

    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q "^telegram-mtproto-proxy$"; then
        echo "代理容器: ✅ 运行中"
    else
        echo "代理容器: ⚠️ 未运行"
    fi

    for cmd in curl iptables tc crontab systemctl; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "$cmd: ✅ 可用"
        else
            echo "$cmd: ⚠️ 不可用"
        fi
    done

    echo ""
    read -p "按回车键继续..."
}

show_menu() {
    clear
    echo "=========================================="
    echo "  Telegram MTProto 代理管理"
    echo "=========================================="
    echo ""
    echo "1) 启动代理"
    echo "2) 停止代理"
    echo "3) 重启代理"
    echo "4) 查看状态"
    echo "5) 查看连接信息/二维码"
    echo "6) 实时监控"
    echo "7) 流量统计"
    echo "8) 使用报告"
    echo "9) 查看日志"
    echo "10) 更换密钥"
    echo "11) 更换端口"
    echo "12) 备份配置"
    echo "13) 恢复配置"
    echo "14) 更新镜像"
    echo "15) IP 白名单"
    echo "16) 开机自启"
    echo "17) 完全卸载"
    echo "18) 环境自检"
    echo "0) 退出"
    echo ""
    echo -n "请选择 [0-18]: "
}

start_proxy() {
    echo ""

    ensure_docker_or_return || return
    
    # 检测是否已启动
    if [ -f .env ] && docker ps --format '{{.Names}}' | grep -q "^telegram-mtproto-proxy$"; then
        echo "⚠️  检测到代理已在运行"
        echo ""
        if ! load_env_config .env; then
            read -p "按回车键继续..."
            return
        fi
        echo "当前配置："
        echo "- 端口: $PORT"
        echo "- 密钥: $SECRET"
        echo ""
        read -p "是否重新配置? 将停止当前服务 (y/n): " RECONFIG
        
        if [ "$RECONFIG" != "y" ]; then
            echo "已取消"
            read -p "按回车键继续..."
            return
        fi
        
        echo ""
        echo "正在停止当前服务..."
        docker compose down
    fi
    
    echo "=== 启动代理配置 ==="
    echo ""
    
    SECRET=$(generate_secret)
    PORT=$(generate_port)
    if [ -z "$PORT" ]; then
        echo "错误: 无法找到空闲端口，请稍后重试"
        read -p "按回车键继续..."
        return
    fi
    
    echo "生成的密钥: $SECRET"
    echo "生成的端口: $PORT"
    echo ""
    
    read -p "是否启用 Nginx 伪装? (y/n, 默认 n): " USE_NGINX
    USE_NGINX=${USE_NGINX:-n}
    
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
    
    read -p "是否启用告警监控? (y/n, 默认 n): " USE_ALERT
    USE_ALERT=${USE_ALERT:-n}
    
    read -p "是否启用使用统计? (y/n, 默认 n): " USE_STATS
    USE_STATS=${USE_STATS:-n}
    
    echo ""
    echo "正在配置..."
    
    if [ "$USE_NGINX" = "y" ]; then
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

networks:
  proxy-net:
    driver: bridge
EOF
        
        [ ! -f index.html ] && cat > index.html <<'HTML_EOF'
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
EOF
    fi
    
    mkdir -p config

    if ! docker compose up -d; then
        echo "❌ 启动失败，请检查日志: docker compose logs --tail 100"
        read -p "按回车键继续..."
        return
    fi
    
    if [ "$USE_LIMIT" = "y" ]; then
        echo ""
        echo "设置流量限制..."
        apply_traffic_limit "$LIMIT_RATE" "$PORT" || echo "⚠️  流量限制设置失败，请检查 tc 参数"
    fi
    
    if [ "$USE_ALERT" = "y" ]; then
        echo ""
        echo "设置告警监控..."
        (crontab -l 2>/dev/null | grep -v "alert.sh"; echo "*/5 * * * * $(pwd)/alert.sh") | crontab -
        echo "✅ 告警监控已启用（每 5 分钟检查）"
    fi
    
    if [ "$USE_STATS" = "y" ]; then
        echo ""
        echo "设置使用统计..."
        (crontab -l 2>/dev/null | grep -v "report.sh"; echo "0 * * * * $(pwd)/report.sh >> /dev/null 2>&1") | crontab -
        echo "✅ 使用统计已启用（每小时记录）"
    fi
    
    cat > .env <<EOF
PORT=$PORT
SECRET=$SECRET
USE_NGINX=$USE_NGINX
USE_LIMIT=$USE_LIMIT
LIMIT_RATE=$LIMIT_RATE
USE_ALERT=$USE_ALERT
USE_STATS=$USE_STATS
EOF
    
    echo ""
    echo "✅ 代理已启动！"
    echo ""
    echo "连接信息："
    echo "- 端口: $PORT"
    echo "- 密钥: $SECRET"
    echo ""
    read -p "按回车键继续..."
}

stop_proxy() {
    echo ""
    ensure_docker_or_return || return
    echo "正在停止代理..."
    docker compose stop
    echo "✅ 代理已停止"
    read -p "按回车键继续..."
}

restart_proxy() {
    echo ""
    ensure_docker_or_return || return
    echo "正在重启代理..."
    docker compose restart
    echo "✅ 代理已重启"
    read -p "按回车键继续..."
}

show_status() {
    echo ""
    ensure_docker_or_return || return
    echo "=== 代理状态 ==="
    docker compose ps
    echo ""
    read -p "按回车键继续..."
}

show_qrcode() {
    if [ ! -f .env ]; then
        echo ""
        echo "错误: 未找到配置文件，请先启动代理"
        read -p "按回车键继续..."
        return
    fi
    
    if ! load_env_config .env; then
        read -p "按回车键继续..."
        return
    fi
    SERVER_IP4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null)
    SERVER_IP6=$(curl -6 -s ifconfig.me 2>/dev/null)
    
    echo ""
    echo "=== 连接信息 ==="
    echo ""
    echo "端口: $PORT"
    echo "密钥: $SECRET"
    echo ""
    
    if [ ! -z "$SERVER_IP4" ]; then
        echo "IPv4 服务器: $SERVER_IP4"
        PROXY_URL4="tg://proxy?server=$SERVER_IP4&port=$PORT&secret=$SECRET"
        echo "IPv4 连接链接:"
        echo "$PROXY_URL4"
        echo ""
        
        if command -v qrencode &> /dev/null; then
            echo "IPv4 二维码:"
            qrencode -t ANSIUTF8 "$PROXY_URL4"
            echo ""
        else
            ENCODED_URL4=$(url_encode "$PROXY_URL4")
            echo "IPv4 在线二维码:"
            echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$ENCODED_URL4"
            echo ""
        fi
    fi
    
    if [ ! -z "$SERVER_IP6" ]; then
        echo "IPv6 服务器: $SERVER_IP6"
        PROXY_URL6="tg://proxy?server=$SERVER_IP6&port=$PORT&secret=$SECRET"
        echo "IPv6 连接链接:"
        echo "$PROXY_URL6"
        echo ""
        
        if command -v qrencode &> /dev/null; then
            echo "IPv6 二维码:"
            qrencode -t ANSIUTF8 "$PROXY_URL6"
        else
            ENCODED_URL6=$(url_encode "$PROXY_URL6")
            echo "IPv6 在线二维码:"
            echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$ENCODED_URL6"
        fi
        echo ""
    fi
    read -p "按回车键继续..."
}

show_monitor() {
    ensure_docker_or_return || return

    if ! docker ps --format '{{.Names}}' | grep -q "^telegram-mtproto-proxy$"; then
        echo ""
        echo "错误: 容器未运行"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 实时监控 (按 Ctrl+C 返回菜单) ==="
    echo ""
    docker stats telegram-mtproto-proxy
}

show_stats() {
    ensure_docker_or_return || return

    if ! docker ps --format '{{.Names}}' | grep -q "^telegram-mtproto-proxy$"; then
        echo ""
        echo "错误: 容器未运行"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 流量统计 ==="
    echo ""
    
    STATS=$(docker stats telegram-mtproto-proxy --no-stream --format "{{.NetIO}}")
    echo "总流量: $STATS"
    
    echo ""
    PORT=$(docker port telegram-mtproto-proxy 443 2>/dev/null | cut -d: -f2)
    if [ ! -z "$PORT" ]; then
        if command -v ss >/dev/null 2>&1; then
            CONNECTIONS=$(ss -tan 2>/dev/null | awk -v port=":$PORT" '$1 == "ESTAB" && $4 ~ port"$" {count++} END {print count+0}')
        else
            CONNECTIONS=$(netstat -an 2>/dev/null | grep ":$PORT" | grep ESTABLISHED | wc -l)
        fi
        echo "当前活跃连接数: $CONNECTIONS"
        echo "端口: $PORT"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

show_report() {
    STATS_FILE="./config/stats.log"
    
    if [ ! -f "$STATS_FILE" ]; then
        echo ""
        echo "暂无统计数据，请先启用使用统计功能"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 使用报告 ==="
    echo ""
    
    TOTAL_LINES=$(wc -l < $STATS_FILE)
    echo "总记录数: $TOTAL_LINES"
    
    if [ $TOTAL_LINES -gt 0 ]; then
        AVG_CPU=$(awk -F'|' '{sum+=$4; count++} END {if(count>0) printf "%.2f", sum/count}' $STATS_FILE)
        echo "平均 CPU: ${AVG_CPU}%"
        
        echo ""
        echo "最近10条记录:"
        tail -10 $STATS_FILE | awk -F'|' '{printf "%s | 流量: %s | CPU: %s%%\n", $2, $3, $4}'
    fi
    
    echo ""
    read -p "按回车键继续..."
}

show_logs() {
    echo ""
    ensure_docker_or_return || return
    echo "=== 代理日志 (按 Ctrl+C 返回菜单) ==="
    echo ""
    docker compose logs -f
}

change_secret() {
    ensure_docker_or_return || return

    if [ ! -f .env ]; then
        echo ""
        echo "错误: 代理未启动"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 更换密钥 ==="
    echo ""
    
    if ! load_env_config .env; then
        read -p "按回车键继续..."
        return
    fi
    OLD_SECRET=$SECRET
    NEW_SECRET=$(generate_secret)
    
    echo "当前密钥: $OLD_SECRET"
    echo "新密钥: $NEW_SECRET"
    echo ""
    read -p "确认更换? (y/n): " CONFIRM
    
    if [ "$CONFIRM" != "y" ]; then
        echo "已取消"
        read -p "按回车键继续..."
        return
    fi
    
    # 更新配置文件
    sed -i -E "s/^SECRET=${OLD_SECRET}$/SECRET=${NEW_SECRET}/" .env
    sed -i "s/SECRET=$OLD_SECRET/SECRET=$NEW_SECRET/" docker-compose.yml
    
    # 重启服务
    docker compose up -d --force-recreate
    
    echo ""
    echo "✅ 密钥已更换！"
    echo "新密钥: $NEW_SECRET"
    echo ""
    read -p "按回车键继续..."
}

change_port() {
    ensure_docker_or_return || return

    if [ ! -f .env ]; then
        echo ""
        echo "错误: 代理未启动"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 更换端口 ==="
    echo ""
    
    if ! load_env_config .env; then
        read -p "按回车键继续..."
        return
    fi
    OLD_PORT=$PORT
    NEW_PORT=""
    while [ -z "$NEW_PORT" ] || [ "$NEW_PORT" = "$OLD_PORT" ]; do
        NEW_PORT=$(generate_port)
        if [ -z "$NEW_PORT" ]; then
            echo "错误: 无法找到可用的新端口"
            read -p "按回车键继续..."
            return
        fi
    done
    
    echo "当前端口: $OLD_PORT"
    echo "新端口: $NEW_PORT"
    echo ""
    read -p "确认更换? (y/n): " CONFIRM
    
    if [ "$CONFIRM" != "y" ]; then
        echo "已取消"
        read -p "按回车键继续..."
        return
    fi
    
    # 更新配置文件
    sed -i -E "s/^PORT=${OLD_PORT}$/PORT=${NEW_PORT}/" .env
    sed -i -E \
        -e "s/\"${OLD_PORT}:443\"/\"${NEW_PORT}:443\"/g" \
        -e "s/\"${OLD_PORT}:${OLD_PORT}\"/\"${NEW_PORT}:${NEW_PORT}\"/g" \
        docker-compose.yml
    
    if [ -f nginx-runtime.conf ]; then
        sed -i -E "s/listen ${OLD_PORT};/listen ${NEW_PORT};/g" nginx-runtime.conf
    fi
    
    # 更新流量限制
    if [ "$USE_LIMIT" = "y" ] && [ ! -z "$LIMIT_RATE" ]; then
        LIMIT_RATE=$(sanitize_rate "$LIMIT_RATE")
        apply_traffic_limit "$LIMIT_RATE" "$NEW_PORT" || echo "⚠️  流量限制更新失败，请检查 tc 参数"
    fi
    
    # 重启服务
    docker compose up -d --force-recreate
    
    echo ""
    echo "✅ 端口已更换！"
    echo "新端口: $NEW_PORT"
    echo ""
    read -p "按回车键继续..."
}

backup_config() {
    if [ ! -f .env ]; then
        echo ""
        echo "错误: 没有配置可备份"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 备份配置 ==="
    echo ""
    
    BACKUP_FILE="telegram-proxy-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    BACKUP_ITEMS=(.env docker-compose.yml config/)
    [ -f nginx-runtime.conf ] && BACKUP_ITEMS+=(nginx-runtime.conf)
    [ -f index.html ] && BACKUP_ITEMS+=(index.html)

    if ! tar -czf "$BACKUP_FILE" "${BACKUP_ITEMS[@]}"; then
        echo "❌ 备份失败"
        read -p "按回车键继续..."
        return
    fi
    
    echo "✅ 配置已备份到: $BACKUP_FILE"
    echo ""
    echo "备份包含:"
    echo "- 配置文件 (.env)"
    echo "- Docker 配置 (docker-compose.yml)"
    echo "- Nginx 配置 (如果有)"
    echo "- 数据目录 (config/)"
    echo ""
    read -p "按回车键继续..."
}

restore_config() {
    echo ""
    ensure_docker_or_return || return
    echo "=== 恢复配置 ==="
    echo ""
    
    echo "可用的备份文件:"
    ls -1 telegram-proxy-backup-*.tar.gz 2>/dev/null || echo "无备份文件"
    echo ""
    
    read -p "输入备份文件名: " BACKUP_FILE
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "错误: 文件不存在"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    read -p "确认恢复? 当前配置将被覆盖 (y/n): " CONFIRM
    
    if [ "$CONFIRM" != "y" ]; then
        echo "已取消"
        read -p "按回车键继续..."
        return
    fi
    
    # 停止服务
    docker compose down 2>/dev/null
    
    # 恢复备份
    if ! tar -xzf "$BACKUP_FILE"; then
        echo "❌ 恢复失败，备份文件可能损坏"
        read -p "按回车键继续..."
        return
    fi

    # 启动服务
    if ! docker compose up -d; then
        echo "❌ 恢复后启动失败，请检查: docker compose logs --tail 100"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "✅ 配置已恢复！"
    echo ""
    read -p "按回车键继续..."
}

update_image() {
    echo ""
    ensure_docker_or_return || return
    echo "=== 更新 Docker 镜像 ==="
    echo ""
    
    read -p "确认更新? 服务将短暂中断 (y/n): " CONFIRM
    
    if [ "$CONFIRM" != "y" ]; then
        echo "已取消"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "正在拉取最新镜像..."
    docker compose pull
    
    echo ""
    echo "正在重启服务..."
    docker compose up -d --force-recreate
    
    echo ""
    echo "✅ 镜像已更新！"
    echo ""
    read -p "按回车键继续..."
}

manage_whitelist() {
    if ! command -v iptables >/dev/null 2>&1; then
        echo ""
        echo "错误: 未找到 iptables 命令"
        read -p "按回车键继续..."
        return
    fi

    echo ""
    echo "=== IP 白名单管理 ==="
    echo ""
    echo "1) 查看白名单"
    echo "2) 添加单个 IP"
    echo "3) 添加 IP 段（CIDR）"
    echo "4) 添加当前连接 IP"
    echo "5) 删除规则"
    echo "6) 清空白名单"
    echo "7) 禁用白名单"
    echo "0) 返回"
    echo ""
    read -p "请选择: " choice
    
    case $choice in
        1)
            echo ""
            echo "当前白名单规则:"
            iptables -L INPUT -n --line-numbers | grep "telegram-proxy" || echo "无规则"
            ;;
        2)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动"
            else
                if ! load_env_config .env; then
                    echo "错误: 配置文件无效"
                    echo ""
                    read -p "按回车键继续..."
                    return
                fi
                echo ""
                read -p "输入允许的 IP 地址: " ALLOW_IP
                if ! is_valid_ipv4 "$ALLOW_IP"; then
                    echo "❌ IP 格式无效"
                elif iptables -I INPUT -p tcp --dport "$PORT" -s "$ALLOW_IP" -m comment --comment "telegram-proxy" -j ACCEPT; then
                    echo "✅ 已添加 IP: $ALLOW_IP"
                    if ensure_whitelist_drop_rule "$PORT"; then
                        echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                    else
                        echo "⚠️  添加默认拒绝规则失败，请手动检查 iptables"
                    fi
                else
                    echo "❌ 添加失败"
                fi
            fi
            ;;
        3)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动"
            else
                if ! load_env_config .env; then
                    echo "错误: 配置文件无效"
                    echo ""
                    read -p "按回车键继续..."
                    return
                fi
                echo ""
                echo "常用运营商 IP 段示例:"
                echo "- 中国移动: 120.0.0.0/8"
                echo "- 中国联通: 112.0.0.0/8"
                echo "- 中国电信: 117.0.0.0/8"
                echo ""
                read -p "输入 IP 段 (CIDR 格式，如 192.168.1.0/24): " ALLOW_CIDR
                if ! is_valid_cidr "$ALLOW_CIDR"; then
                    echo "❌ CIDR 格式无效"
                elif iptables -I INPUT -p tcp --dport "$PORT" -s "$ALLOW_CIDR" -m comment --comment "telegram-proxy" -j ACCEPT; then
                    echo "✅ 已添加 IP 段: $ALLOW_CIDR"
                    if ensure_whitelist_drop_rule "$PORT"; then
                        echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                    else
                        echo "⚠️  添加默认拒绝规则失败，请手动检查 iptables"
                    fi
                else
                    echo "❌ 添加失败"
                fi
            fi
            ;;
        4)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动"
            else
                if ! load_env_config .env; then
                    echo "错误: 配置文件无效"
                    echo ""
                    read -p "按回车键继续..."
                    return
                fi
                echo ""
                echo "检测当前连接的 IP..."
                CURRENT_IP=$(who am i | awk '{print $5}' | tr -d '()')
                if [ -z "$CURRENT_IP" ]; then
                    CURRENT_IP=$(echo $SSH_CLIENT | awk '{print $1}')
                fi
                
                if [ -z "$CURRENT_IP" ]; then
                    echo "无法检测当前 IP，请手动输入"
                    read -p "输入你的 IP: " CURRENT_IP
                fi
                
                echo "检测到 IP: $CURRENT_IP"
                read -p "确认添加? (y/n): " CONFIRM
                
                if [ "$CONFIRM" = "y" ]; then
                    if ! is_valid_ipv4 "$CURRENT_IP"; then
                        echo "❌ IP 格式无效"
                    elif iptables -I INPUT -p tcp --dport "$PORT" -s "$CURRENT_IP" -m comment --comment "telegram-proxy" -j ACCEPT; then
                        echo "✅ 已添加当前 IP: $CURRENT_IP"
                        if ensure_whitelist_drop_rule "$PORT"; then
                            echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                        else
                            echo "⚠️  添加默认拒绝规则失败，请手动检查 iptables"
                        fi
                    else
                        echo "❌ 添加失败"
                    fi
                fi
            fi
            ;;
        5)
            echo ""
            echo "当前规则:"
            iptables -L INPUT -n --line-numbers | grep -E "telegram-proxy|^num"
            echo ""
            read -p "输入要删除的规则编号: " LINE_NUM
            if [[ ! "$LINE_NUM" =~ ^[0-9]+$ ]]; then
                echo "❌ 规则编号无效"
            else
                iptables -D INPUT "$LINE_NUM" 2>/dev/null && echo "✅ 已删除规则" || echo "❌ 删除失败"
            fi
            ;;
        6)
            echo ""
            read -p "确认清空白名单? (y/n): " CONFIRM
            if [ "$CONFIRM" = "y" ]; then
                while iptables -D INPUT -m comment --comment "telegram-proxy" -j ACCEPT 2>/dev/null; do :; done
                while iptables -D INPUT -m comment --comment "telegram-proxy-drop" -j DROP 2>/dev/null; do :; done
                echo "✅ 白名单已清空"
            fi
            ;;
        7)
            echo ""
            read -p "确认禁用白名单? 所有 IP 将可访问 (y/n): " CONFIRM
            if [ "$CONFIRM" = "y" ]; then
                while iptables -D INPUT -m comment --comment "telegram-proxy" -j ACCEPT 2>/dev/null; do :; done
                while iptables -D INPUT -m comment --comment "telegram-proxy-drop" -j DROP 2>/dev/null; do :; done
                echo "✅ 白名单已禁用"
            fi
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
}

manage_autostart() {
    echo ""
    echo "=== 开机自启管理 ==="
    echo ""
    echo "1) 启用开机自启"
    echo "2) 禁用开机自启"
    echo "3) 查看状态"
    echo "0) 返回"
    echo ""
    read -p "请选择: " choice
    
    case $choice in
        1)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动，请先启动代理"
            else
                echo ""
                SCRIPT_DIR=$(pwd)
                
                # 创建 systemd 服务
                cat > /etc/systemd/system/telegram-proxy.service <<EOF
[Unit]
Description=Telegram MTProto Proxy
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose stop
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF
                
                systemctl daemon-reload
                systemctl enable telegram-proxy.service
                
                echo "✅ 开机自启已启用"
                echo ""
                echo "服务将在系统重启后自动启动"
            fi
            ;;
        2)
            echo ""
            systemctl disable telegram-proxy.service 2>/dev/null
            rm -f /etc/systemd/system/telegram-proxy.service
            systemctl daemon-reload
            echo "✅ 开机自启已禁用"
            ;;
        3)
            echo ""
            if systemctl is-enabled telegram-proxy.service 2>/dev/null | grep -q enabled; then
                echo "状态: ✅ 已启用"
                echo ""
                systemctl status telegram-proxy.service --no-pager
            else
                echo "状态: ❌ 未启用"
            fi
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
}

uninstall() {
    echo ""
    echo "警告: 此操作将删除所有容器、配置和数据"
    read -p "确认卸载? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "已取消"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "正在卸载..."
    
    # 禁用开机自启
    systemctl disable telegram-proxy.service 2>/dev/null
    rm -f /etc/systemd/system/telegram-proxy.service
    systemctl daemon-reload
    
    docker compose down -v 2>/dev/null
    docker rm -f telegram-mtproto-proxy telegram-nginx 2>/dev/null
    
    IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -1)
    tc qdisc del dev $IFACE root 2>/dev/null
    
    crontab -l 2>/dev/null | grep -v "alert.sh" | grep -v "report.sh" | crontab - 2>/dev/null
    
    rm -rf config/
    rm -f .env docker-compose.yml nginx-runtime.conf
    rm -f /tmp/telegram-proxy-alert.log
    
    echo ""
    echo "✅ 卸载完成！"
    read -p "按回车键继续..."
}

# 主循环
while true; do
    show_menu
    read choice
    
    case $choice in
        1) start_proxy ;;
        2) stop_proxy ;;
        3) restart_proxy ;;
        4) show_status ;;
        5) show_qrcode ;;
        6) show_monitor ;;
        7) show_stats ;;
        8) show_report ;;
        9) show_logs ;;
        10) change_secret ;;
        11) change_port ;;
        12) backup_config ;;
        13) restore_config ;;
        14) update_image ;;
        15) manage_whitelist ;;
        16) manage_autostart ;;
        17) uninstall ;;
        18) show_self_check ;;
        0) echo ""; echo "再见！"; exit 0 ;;
        *) echo ""; echo "无效选择"; sleep 1 ;;
    esac
done
