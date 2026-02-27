#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1


CONTAINER="telegram-mtproto-proxy"
ALERT_FILE="/tmp/telegram-proxy-alert.log"
TRAFFIC_THRESHOLD=1000000000  # 单次检查周期增量阈值（默认 1GB）
TRAFFIC_STATE_FILE="/tmp/telegram-proxy-traffic-last.total"

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

is_over_threshold() {
    local value="$1"
    local threshold="$2"
    awk -v v="$value" -v t="$threshold" 'BEGIN { exit !(v > t) }'
}

to_bytes() {
    local token="$1"
    local normalized value unit multiplier

    normalized=$(echo "$token" | tr -d ' ')
    value=$(echo "$normalized" | sed -E 's/^([0-9.]+).*/\1/')
    unit=$(echo "$normalized" | sed -E 's/^[0-9.]+([A-Za-z]+)$/\1/')
    unit=${unit/iB/B}
    unit=${unit^^}

    case "$unit" in
        B)  multiplier=1 ;;
        KB) multiplier=1024 ;;
        MB) multiplier=$((1024 * 1024)) ;;
        GB) multiplier=$((1024 * 1024 * 1024)) ;;
        TB) multiplier=$((1024 * 1024 * 1024 * 1024)) ;;
        *)  echo 0; return ;;
    esac

    awk -v v="$value" -v m="$multiplier" 'BEGIN { printf "%.0f", v * m }'
}

# 检查容器状态
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    send_alert "容器已停止运行"
    exit 1
fi

# 检查流量
STATS=$(docker stats $CONTAINER --no-stream --format "{{.NetIO}}")
RX=$(echo "$STATS" | awk -F' / ' '{print $1}')
TX=$(echo "$STATS" | awk -F' / ' '{print $2}')
TOTAL_TRAFFIC=$(( $(to_bytes "$RX") + $(to_bytes "$TX") ))
PREV_TOTAL=0
if [ -f "$TRAFFIC_STATE_FILE" ]; then
    PREV_TOTAL=$(cat "$TRAFFIC_STATE_FILE" 2>/dev/null)
    [[ "$PREV_TOTAL" =~ ^[0-9]+$ ]] || PREV_TOTAL=0
fi

DELTA_TRAFFIC=$((TOTAL_TRAFFIC - PREV_TOTAL))
[ "$DELTA_TRAFFIC" -lt 0 ] && DELTA_TRAFFIC=0

if [ "$DELTA_TRAFFIC" -gt "$TRAFFIC_THRESHOLD" ]; then
    send_alert "流量增量超阈值: ${DELTA_TRAFFIC} bytes (总流量: $STATS)"
fi
echo "$TOTAL_TRAFFIC" > "$TRAFFIC_STATE_FILE"

# 检查 CPU 使用率
CPU=$(docker stats $CONTAINER --no-stream --format "{{.CPUPerc}}" | sed 's/%//g')
if is_over_threshold "$CPU" 80; then
    send_alert "CPU 使用率过高: ${CPU}%"
fi

# 检查内存使用
MEM=$(docker stats $CONTAINER --no-stream --format "{{.MemPerc}}" | sed 's/%//g')
if is_over_threshold "$MEM" 80; then
    send_alert "内存使用率过高: ${MEM}%"
fi

echo "监控正常 - CPU: ${CPU}% | 内存: ${MEM}% | 流量: $STATS"
