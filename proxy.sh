#!/bin/bash

# Telegram MTProto Proxy 一体化管理脚本

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
    echo "0) 退出"
    echo ""
    echo -n "请选择 [0-17]: "
}

start_proxy() {
    echo ""
    
    # 检测是否已启动
    if [ -f .env ] && docker ps | grep -q telegram-mtproto-proxy; then
        echo "⚠️  检测到代理已在运行"
        echo ""
        source .env
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
    
    SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    PORT=$((RANDOM % 55535 + 10000))
    
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
    
    docker compose up -d
    
    if [ "$USE_LIMIT" = "y" ]; then
        echo ""
        echo "设置流量限制..."
        IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -1)
        tc qdisc del dev $IFACE root 2>/dev/null
        tc qdisc add dev $IFACE root handle 1: htb default 10
        tc class add dev $IFACE parent 1: classid 1:1 htb rate $LIMIT_RATE ceil $((${LIMIT_RATE%mbit}*2))mbit
        tc filter add dev $IFACE protocol ip parent 1:0 prio 1 u32 match ip dport $PORT 0xffff flowid 1:1
        echo "✅ 流量限制已设置: $LIMIT_RATE"
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
    echo "正在停止代理..."
    docker compose stop
    echo "✅ 代理已停止"
    read -p "按回车键继续..."
}

restart_proxy() {
    echo ""
    echo "正在重启代理..."
    docker compose restart
    echo "✅ 代理已重启"
    read -p "按回车键继续..."
}

show_status() {
    echo ""
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
    
    source .env
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
            ENCODED_URL4=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PROXY_URL4'))" 2>/dev/null || echo "$PROXY_URL4")
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
            ENCODED_URL6=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PROXY_URL6'))" 2>/dev/null || echo "$PROXY_URL6")
            echo "IPv6 在线二维码:"
            echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$ENCODED_URL6"
        fi
        echo ""
    fi
    read -p "按回车键继续..."
}

show_monitor() {
    if ! docker ps | grep -q telegram-mtproto-proxy; then
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
    if ! docker ps | grep -q telegram-mtproto-proxy; then
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
        CONNECTIONS=$(netstat -an 2>/dev/null | grep ":$PORT" | grep ESTABLISHED | wc -l)
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
    echo "=== 代理日志 (按 Ctrl+C 返回菜单) ==="
    echo ""
    docker compose logs -f
}

change_secret() {
    if [ ! -f .env ]; then
        echo ""
        echo "错误: 代理未启动"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 更换密钥 ==="
    echo ""
    
    source .env
    OLD_SECRET=$SECRET
    NEW_SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    
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
    sed -i "s/SECRET=$OLD_SECRET/SECRET=$NEW_SECRET/" .env
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
    if [ ! -f .env ]; then
        echo ""
        echo "错误: 代理未启动"
        read -p "按回车键继续..."
        return
    fi
    
    echo ""
    echo "=== 更换端口 ==="
    echo ""
    
    source .env
    OLD_PORT=$PORT
    NEW_PORT=$((RANDOM % 55535 + 10000))
    
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
    sed -i "s/PORT=$OLD_PORT/PORT=$NEW_PORT/" .env
    sed -i "s/$OLD_PORT/$NEW_PORT/g" docker-compose.yml
    
    if [ -f nginx-runtime.conf ]; then
        sed -i "s/$OLD_PORT/$NEW_PORT/g" nginx-runtime.conf
    fi
    
    # 更新流量限制
    if [ "$USE_LIMIT" = "y" ] && [ ! -z "$LIMIT_RATE" ]; then
        IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -1)
        tc qdisc del dev $IFACE root 2>/dev/null
        tc qdisc add dev $IFACE root handle 1: htb default 10
        tc class add dev $IFACE parent 1: classid 1:1 htb rate $LIMIT_RATE ceil $((${LIMIT_RATE%mbit}*2))mbit
        tc filter add dev $IFACE protocol ip parent 1:0 prio 1 u32 match ip dport $NEW_PORT 0xffff flowid 1:1
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
    
    tar -czf "$BACKUP_FILE" .env docker-compose.yml nginx-runtime.conf index.html config/ 2>/dev/null
    
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
    tar -xzf "$BACKUP_FILE"
    
    # 启动服务
    docker compose up -d
    
    echo ""
    echo "✅ 配置已恢复！"
    echo ""
    read -p "按回车键继续..."
}

update_image() {
    echo ""
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
                source .env
                echo ""
                read -p "输入允许的 IP 地址: " ALLOW_IP
                iptables -I INPUT -p tcp --dport $PORT -s $ALLOW_IP -m comment --comment "telegram-proxy" -j ACCEPT
                echo "✅ 已添加 IP: $ALLOW_IP"
                
                # 如果是第一条规则，添加默认拒绝
                if [ $(iptables -L INPUT -n | grep "telegram-proxy" | wc -l) -eq 1 ]; then
                    iptables -A INPUT -p tcp --dport $PORT -m comment --comment "telegram-proxy-drop" -j DROP
                    echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                fi
            fi
            ;;
        3)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动"
            else
                source .env
                echo ""
                echo "常用运营商 IP 段示例:"
                echo "- 中国移动: 120.0.0.0/8"
                echo "- 中国联通: 112.0.0.0/8"
                echo "- 中国电信: 117.0.0.0/8"
                echo ""
                read -p "输入 IP 段 (CIDR 格式，如 192.168.1.0/24): " ALLOW_CIDR
                iptables -I INPUT -p tcp --dport $PORT -s $ALLOW_CIDR -m comment --comment "telegram-proxy" -j ACCEPT
                echo "✅ 已添加 IP 段: $ALLOW_CIDR"
                
                # 如果是第一条规则，添加默认拒绝
                if [ $(iptables -L INPUT -n | grep "telegram-proxy" | wc -l) -eq 1 ]; then
                    iptables -A INPUT -p tcp --dport $PORT -m comment --comment "telegram-proxy-drop" -j DROP
                    echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                fi
            fi
            ;;
        4)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动"
            else
                source .env
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
                    iptables -I INPUT -p tcp --dport $PORT -s $CURRENT_IP -m comment --comment "telegram-proxy" -j ACCEPT
                    echo "✅ 已添加当前 IP: $CURRENT_IP"
                    
                    # 如果是第一条规则，添加默认拒绝
                    if [ $(iptables -L INPUT -n | grep "telegram-proxy" | wc -l) -eq 1 ]; then
                        iptables -A INPUT -p tcp --dport $PORT -m comment --comment "telegram-proxy-drop" -j DROP
                        echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
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
            iptables -D INPUT $LINE_NUM 2>/dev/null && echo "✅ 已删除规则" || echo "❌ 删除失败"
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
        0) echo ""; echo "再见！"; exit 0 ;;
        *) echo ""; echo "无效选择"; sleep 1 ;;
    esac
done
