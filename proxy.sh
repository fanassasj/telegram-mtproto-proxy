#!/bin/bash

# Telegram MTProto Proxy 一体化管理脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

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
    echo "8) 健康检查"
    echo "9) 使用报告"
    echo "10) 查看日志"
    echo "11) 更换密钥"
    echo "12) 更换端口"
    echo "13) 备份配置"
    echo "14) 恢复配置"
    echo "15) 更新镜像"
    echo "16) IP 白名单"
    echo "17) 流量限量"
    echo "18) 开机自启"
    echo "19) 完全卸载"
    echo "0) 退出"
    echo ""
    echo -n "请选择 [0-19]: "
}

start_proxy() {
    echo ""
    
    # 检查 xxd 命令
    if ! command -v xxd &> /dev/null; then
        echo "⚠️  缺少 xxd 命令，正在安装..."
        apt-get update -qq && apt-get install -y xxd -qq
        echo "✅ xxd 已安装"
        echo ""
    fi
    
    # 检测是否已启动
    if [ -f .env ] && docker ps | grep -q telegram-mtproto-proxy; then
        echo "⚠️  检测到代理已在运行"
        echo ""
        source .env
        if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
            echo "错误: .env 配置不完整"
            read -p "按回车键继续..."
            return
        fi
        echo "当前配置："
        echo "- 端口: $PORT"
        echo "- 原始密钥: 已隐藏"
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
    
    echo "已生成新密钥"
    echo "生成的端口: $PORT"
    echo ""
    
    USE_QUOTA=y
    QUOTA_LIMIT_GB=30
    QUOTA_RESET_DAY=1
    
    read -p "是否启用告警监控? (y/n, 默认 n): " USE_ALERT
    USE_ALERT=${USE_ALERT:-n}
    
    read -p "是否启用使用统计? (y/n, 默认 n): " USE_STATS
    USE_STATS=${USE_STATS:-n}
    
    echo ""
    echo "正在配置..."
    
    # 自动在本地为当前 CPU 架构构建原生镜像（完美解决 ARM64/AMD64 平台兼容性，实现原生性能）
    cat > Dockerfile <<EOF
FROM ubuntu:24.04

RUN apt-get update -qq && apt-get install -y -qq git python3 python3-uvloop python3-cryptography python3-socks libcap2-bin && apt-get clean

WORKDIR /home/tgproxy
RUN git clone -b stable https://github.com/alexbers/mtprotoproxy.git .

RUN setcap cap_net_bind_service=+ep \$(readlink -f /usr/bin/python3)

USER 1000
CMD ["python3", "mtprotoproxy.py"]
EOF

    mkdir -p ./config
    cat > ./config/config.py <<EOF
PORT = 443
USERS = {
    "tg": "$SECRET"
}
TLS_DOMAIN = "www.microsoft.com"
EOF

    cat > docker-compose.yml <<EOF
services:
  mtproto-proxy:
    build: .
    image: mtprotoproxy:local
    container_name: telegram-mtproto-proxy
    restart: unless-stopped
    ports:
      - "$PORT:443"
    volumes:
      - ./config/config.py:/home/tgproxy/config.py
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
      test: ["CMD", "python3", "-c", "import socket; s = socket.socket(); s.connect(('localhost', 443))"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    sysctls:
      - net.ipv4.tcp_keepalive_time=600
      - net.ipv4.tcp_keepalive_intvl=60
      - net.ipv4.tcp_keepalive_probes=3
EOF
    
    docker compose up -d
    
    echo ""
    echo "设置月度流量限量..."
    (crontab -l 2>/dev/null | grep -v "# telegram-mtproto-proxy"; echo "*/5 * * * * $(pwd)/quota.sh >> /dev/null 2>&1 # telegram-mtproto-proxy") | crontab -
    ./quota.sh >/dev/null 2>&1
    echo "✅ 月度流量限量已启用: ${QUOTA_LIMIT_GB}GiB，每月 ${QUOTA_RESET_DAY} 号刷新"
    
    if [ "$USE_ALERT" = "y" ]; then
        echo ""
        echo "设置告警监控..."
        (crontab -l 2>/dev/null | grep -v "# telegram-mtproto-proxy"; echo "*/5 * * * * $(pwd)/alert.sh # telegram-mtproto-proxy") | crontab -
        echo "✅ 告警监控已启用（每 5 分钟检查）"
    fi
    
    if [ "$USE_STATS" = "y" ]; then
        echo ""
        echo "设置使用统计..."
        (crontab -l 2>/dev/null | grep -v "# telegram-mtproto-proxy"; echo "0 * * * * $(pwd)/report.sh >> /dev/null 2>&1 # telegram-mtproto-proxy") | crontab -
        echo "✅ 使用统计已启用（每小时记录）"
    fi
    
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
    echo "✅ 代理已启动！"
    echo ""
    ./qrcode.sh
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
    
    echo ""
    ./qrcode.sh
    echo ""
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
        if command -v ss >/dev/null 2>&1; then
            CONNECTIONS=$(ss -tan state established "( sport = :$PORT or dport = :$PORT )" 2>/dev/null | tail -n +2 | wc -l)
        elif command -v netstat >/dev/null 2>&1; then
            CONNECTIONS=$(netstat -an 2>/dev/null | grep ":$PORT" | grep ESTABLISHED | wc -l)
        else
            CONNECTIONS="未知"
        fi
        echo "当前活跃连接数: $CONNECTIONS"
        echo "端口: $PORT"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

show_healthcheck() {
    echo ""
    if [ ! -x ./healthcheck.sh ]; then
        echo "错误: 未找到 healthcheck.sh 或没有执行权限"
    else
        ./healthcheck.sh
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
    if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
        echo "错误: .env 配置不完整"
        read -p "按回车键继续..."
        return
    fi
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
    if [ -f ./config/config.py ]; then
        sed -i "s/\"tg\": \"$OLD_SECRET\"/\"tg\": \"$NEW_SECRET\"/" ./config/config.py
    fi
    
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
    if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
        echo "错误: .env 配置不完整"
        read -p "按回车键继续..."
        return
    fi
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
    sed -i "s/\"$OLD_PORT:443\"/\"$NEW_PORT:443\"/" docker-compose.yml
    
    # 重启服务
    docker compose up -d --force-recreate
    ./quota.sh >/dev/null 2>&1
    
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
    
    crontab -l 2>/dev/null | grep "# telegram-mtproto-proxy" > crontab.bak 2>/dev/null || true
    tar -czf "$BACKUP_FILE" .env docker-compose.yml config/ crontab.bak 2>/dev/null
    rm -f crontab.bak
    
    echo "✅ 配置已备份到: $BACKUP_FILE"
    echo ""
    echo "备份包含:"
    echo "- 配置文件 (.env)"
    echo "- Docker 配置 (docker-compose.yml)"
    echo "- 数据目录 (config/)"
    echo "- 定时任务 (crontab.bak)"
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
    
    # 恢复定时任务
    if [ -f crontab.bak ]; then
        (crontab -l 2>/dev/null | grep -v "# telegram-mtproto-proxy"; cat crontab.bak) | crontab - 2>/dev/null
        rm -f crontab.bak
        echo "✅ 定时任务已恢复"
    fi
    
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
                if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
                    echo "错误: .env 配置不完整"
                    read -p "按回车键继续..."
                    return
                fi
                echo ""
                read -p "输入允许的 IP 地址: " ALLOW_IP
                iptables -I INPUT -p tcp --dport $PORT -s $ALLOW_IP -m comment --comment "telegram-proxy" -j ACCEPT
                echo "✅ 已添加 IP: $ALLOW_IP"
                
                # 如果是第一条规则，添加默认拒绝
                if [ $(iptables -L INPUT -n | grep "telegram-proxy" | wc -l) -eq 1 ]; then
                    iptables -A INPUT -p tcp --dport $PORT -m comment --comment "telegram-proxy-drop" -j DROP
                    echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                fi
                echo "⚠️  提示: iptables 规则重启后将丢失，建议安装 iptables-persistent 持久化"
            fi
            ;;
        3)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动"
            else
                source .env
                if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
                    echo "错误: .env 配置不完整"
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
                iptables -I INPUT -p tcp --dport $PORT -s $ALLOW_CIDR -m comment --comment "telegram-proxy" -j ACCEPT
                echo "✅ 已添加 IP 段: $ALLOW_CIDR"
                
                # 如果是第一条规则，添加默认拒绝
                if [ $(iptables -L INPUT -n | grep "telegram-proxy" | wc -l) -eq 1 ]; then
                    iptables -A INPUT -p tcp --dport $PORT -m comment --comment "telegram-proxy-drop" -j DROP
                    echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                fi
                echo "⚠️  提示: iptables 规则重启后将丢失，建议安装 iptables-persistent 持久化"
            fi
            ;;
        4)
            if [ ! -f .env ]; then
                echo ""
                echo "错误: 代理未启动"
            else
                source .env
                if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
                    echo "错误: .env 配置不完整"
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
                    iptables -I INPUT -p tcp --dport $PORT -s $CURRENT_IP -m comment --comment "telegram-proxy" -j ACCEPT
                    echo "✅ 已添加当前 IP: $CURRENT_IP"
                    
                    # 如果是第一条规则，添加默认拒绝
                    if [ $(iptables -L INPUT -n | grep "telegram-proxy" | wc -l) -eq 1 ]; then
                        iptables -A INPUT -p tcp --dport $PORT -m comment --comment "telegram-proxy-drop" -j DROP
                        echo "✅ 已启用白名单模式（其他 IP 将被拒绝）"
                    fi
                    echo "⚠️  提示: iptables 规则重启后将丢失，建议安装 iptables-persistent 持久化"
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

manage_quota() {
    echo ""
    echo "=== 流量限量管理 ==="
    echo ""

    if [ ! -f .env ]; then
        echo "错误: 代理未启动"
        read -p "按回车键继续..."
        return
    fi

    source .env
    if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
        echo "错误: .env 配置不完整"
        read -p "按回车键继续..."
        return
    fi
    USE_QUOTA=${USE_QUOTA:-y}
    QUOTA_LIMIT_GB=${QUOTA_LIMIT_GB:-30}
    QUOTA_RESET_DAY=${QUOTA_RESET_DAY:-1}

    echo "当前状态:"
    echo "- 启用: $USE_QUOTA"
    echo "- 月度限量: ${QUOTA_LIMIT_GB}GiB"
    echo "- 刷新日期: 每月 ${QUOTA_RESET_DAY} 号"
    if [ -f ./config/quota.state ]; then
        source ./config/quota.state
        echo "- 计费周期: ${PERIOD:-unknown}"
        echo "- 超量停止标记: ${STOPPED_BY_QUOTA:-0}"
    fi
    echo ""
    echo "1) 查看限量统计"
    echo "2) 启用限量"
    echo "3) 关闭限量"
    echo "4) 修改月度限量"
    echo "5) 修改刷新日期"
    echo "6) 手动重置本月基线"
    echo "0) 返回"
    echo ""
    read -p "请选择: " choice

    case $choice in
        1)
            ./quota.sh
            ;;
        2)
            sed -i "s/^USE_QUOTA=.*/USE_QUOTA=y/" .env
            (crontab -l 2>/dev/null | grep -v "# telegram-mtproto-proxy"; echo "*/5 * * * * $(pwd)/quota.sh >> /dev/null 2>&1 # telegram-mtproto-proxy") | crontab -
            ./quota.sh reset >/dev/null 2>&1
            echo "✅ 流量限量已启用"
            ;;
        3)
            sed -i "s/^USE_QUOTA=.*/USE_QUOTA=n/" .env
            crontab -l 2>/dev/null | grep -v "quota.sh" | crontab - 2>/dev/null
            if [ "${STOPPED_BY_QUOTA:-0}" = "1" ]; then
                docker compose up -d
            fi
            echo "✅ 流量限量已关闭"
            ;;
        4)
            read -p "输入新的月度限量 GiB (当前 ${QUOTA_LIMIT_GB}): " NEW_LIMIT
            if echo "$NEW_LIMIT" | grep -Eq '^[1-9][0-9]*$'; then
                sed -i "s/^QUOTA_LIMIT_GB=.*/QUOTA_LIMIT_GB=$NEW_LIMIT/" .env
                ./quota.sh reset >/dev/null 2>&1
                echo "✅ 月度限量已修改为 ${NEW_LIMIT}GiB，并已重置本月基线"
            else
                echo "❌ 输入无效"
            fi
            ;;
        5)
            read -p "输入刷新日期 1-28 (当前 ${QUOTA_RESET_DAY}): " NEW_DAY
            if echo "$NEW_DAY" | grep -Eq '^[0-9]+$' && [ "$NEW_DAY" -ge 1 ] && [ "$NEW_DAY" -le 28 ]; then
                sed -i "s/^QUOTA_RESET_DAY=.*/QUOTA_RESET_DAY=$NEW_DAY/" .env
                echo "✅ 刷新日期已修改为每月 ${NEW_DAY} 号"
            else
                echo "❌ 输入无效，请输入 1-28"
            fi
            ;;
        6)
            ./quota.sh reset
            ;;
        0)
            return
            ;;
        *)
            echo "无效选择"
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
    docker rm -f telegram-mtproto-proxy 2>/dev/null
    
    crontab -l 2>/dev/null | grep -v "# telegram-mtproto-proxy" | crontab - 2>/dev/null
    
    # 清理 iptables 白名单规则
    if command -v iptables >/dev/null 2>&1; then
        while iptables -D INPUT -m comment --comment "telegram-proxy" -j ACCEPT 2>/dev/null; do :; done
        while iptables -D INPUT -m comment --comment "telegram-proxy-drop" -j DROP 2>/dev/null; do :; done
    fi
    
    rm -rf config/
    rm -f .env docker-compose.yml Dockerfile
    rm -f /tmp/telegram-proxy-alert.log /tmp/telegram-proxy-traffic-last.total
    
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
        8) show_healthcheck ;;
        9) show_report ;;
        10) show_logs ;;
        11) change_secret ;;
        12) change_port ;;
        13) backup_config ;;
        14) restore_config ;;
        15) update_image ;;
        16) manage_whitelist ;;
        17) manage_quota ;;
        18) manage_autostart ;;
        19) uninstall ;;
        0) echo ""; echo "再见！"; exit 0 ;;
        *) echo ""; echo "无效选择"; sleep 1 ;;
    esac
done
