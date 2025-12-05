#!/bin/bash

CONTAINER="telegram-mtproto-proxy"
ALERT_FILE="/tmp/telegram-proxy-alert.log"
TRAFFIC_THRESHOLD=1000000000  # 1GB 流量阈值

# Telegram Bot 配置 (可选)
BOT_TOKEN=""  # 填入你的 Bot Token
CHAT_ID=""    # 填入你的 Chat ID

send_alert() {
    local message="$1"
    echo "[$(date)] $message" >> $ALERT_FILE
    
    # 如果配置了 Telegram Bot，发送通知
    if [ ! -z "$BOT_TOKEN" ] && [ ! -z "$CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d chat_id="$CHAT_ID" \
            -d text="🚨 代理告警: $message" > /dev/null
    fi
}

# 检查容器状态
if ! docker ps | grep -q $CONTAINER; then
    send_alert "容器已停止运行"
    exit 1
fi

# 检查流量
STATS=$(docker stats $CONTAINER --no-stream --format "{{.NetIO}}")
RX=$(echo $STATS | awk '{print $1}' | sed 's/[^0-9.]//g')
TX=$(echo $STATS | awk '{print $3}' | sed 's/[^0-9.]//g')

# 检查 CPU 使用率
CPU=$(docker stats $CONTAINER --no-stream --format "{{.CPUPerc}}" | sed 's/%//g')
if (( $(echo "$CPU > 80" | bc -l) )); then
    send_alert "CPU 使用率过高: ${CPU}%"
fi

# 检查内存使用
MEM=$(docker stats $CONTAINER --no-stream --format "{{.MemPerc}}" | sed 's/%//g')
if (( $(echo "$MEM > 80" | bc -l) )); then
    send_alert "内存使用率过高: ${MEM}%"
fi

echo "监控正常 - CPU: ${CPU}% | 内存: ${MEM}% | 流量: $STATS"
