#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
source "$SCRIPT_DIR/lib.sh"


CONTAINER="telegram-mtproto-proxy"
ALERT_FILE="./config/alert.log"
TRAFFIC_THRESHOLD=1000000000  # 单次检查周期增量阈值（默认 1GB）
TRAFFIC_STATE_FILE="./config/traffic-last.total"

# Telegram Bot 配置 (优先从 .env 读取，也可在下方硬编码)
BOT_TOKEN=""  # 填入你的 Bot Token
CHAT_ID=""    # 填入你的 Chat ID

if [ -f .env ]; then
    # shellcheck disable=SC1091
    source .env
fi

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


# 检查容器状态
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    send_alert "容器已停止运行"
    exit 1
fi

# 检查流量
RAW_STATS=$(docker stats $CONTAINER --no-stream --format "{{.NetIO}}|{{.CPUPerc}}|{{.MemPerc}}")
STATS=$(echo "$RAW_STATS" | cut -d'|' -f1)
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
CPU=$(echo "$RAW_STATS" | cut -d'|' -f2 | sed 's/%//g')
if is_over_threshold "$CPU" 80; then
    send_alert "CPU 使用率过高: ${CPU}%"
fi

# 检查内存使用
MEM=$(echo "$RAW_STATS" | cut -d'|' -f3 | sed 's/%//g')
if is_over_threshold "$MEM" 80; then
    send_alert "内存使用率过高: ${MEM}%"
fi

echo "监控正常 - CPU: ${CPU}% | 内存: ${MEM}% | 流量: $STATS"
