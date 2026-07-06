#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
source "$SCRIPT_DIR/lib.sh"

CONTAINER="telegram-mtproto-proxy"
STATE_FILE="./config/quota.state"
LOG_FILE="./config/quota.log"

log() {
    mkdir -p ./config
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}


read_net_bytes() {
    local net_io rx_text tx_text
    net_io=$(docker stats "$CONTAINER" --no-stream --format "{{.NetIO}}" 2>/dev/null) || return 1
    rx_text=${net_io%% / *}
    tx_text=${net_io##* / }
    RX_BYTES=$(to_bytes "$rx_text")
    TX_BYTES=$(to_bytes "$tx_text")
}

reset_baseline() {
    if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        PERIOD=$(date '+%Y-%m')
        BASE_RX_BYTES=0
        BASE_TX_BYTES=0
        STOPPED_BY_QUOTA=0
        save_state
        log "容器未运行，已重置月度流量基线为空"
        return 0
    fi

    if ! read_net_bytes; then
        log "无法读取 Docker 网络统计"
        return 1
    fi

    PERIOD=$(date '+%Y-%m')
    BASE_RX_BYTES=$RX_BYTES
    BASE_TX_BYTES=$TX_BYTES
    STOPPED_BY_QUOTA=0
    save_state
    log "已手动重置月度流量基线: $PERIOD"
}

save_state() {
    mkdir -p ./config
    cat > "$STATE_FILE" <<EOF
PERIOD=$PERIOD
BASE_RX_BYTES=$BASE_RX_BYTES
BASE_TX_BYTES=$BASE_TX_BYTES
STOPPED_BY_QUOTA=$STOPPED_BY_QUOTA
EOF
}

if [ ! -f .env ]; then
    log "未找到 .env，跳过流量限量检查"
    exit 1
fi

source .env
USE_QUOTA=${USE_QUOTA:-y}
QUOTA_LIMIT_GB=${QUOTA_LIMIT_GB:-30}
QUOTA_RESET_DAY=${QUOTA_RESET_DAY:-1}

if [ "${1:-}" = "reset" ]; then
    reset_baseline
    exit $?
fi

if [ "$USE_QUOTA" != "y" ]; then
    log "流量限量未启用"
    exit 0
fi

CURRENT_PERIOD=$(date '+%Y-%m')
CURRENT_DAY=$(date '+%d')
LIMIT_BYTES=$((QUOTA_LIMIT_GB * 1024 * 1024 * 1024))

PERIOD=""
BASE_RX_BYTES=0
BASE_TX_BYTES=0
STOPPED_BY_QUOTA=0

if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    if [ "${STOPPED_BY_QUOTA:-0}" = "1" ] && [ "$PERIOD" != "$CURRENT_PERIOD" ] && [ "$CURRENT_DAY" -ge "$QUOTA_RESET_DAY" ]; then
        log "进入新月份，重置流量限量并启动代理"
        PERIOD=$CURRENT_PERIOD
        BASE_RX_BYTES=0
        BASE_TX_BYTES=0
        STOPPED_BY_QUOTA=0
        save_state
        docker compose up -d
        exit $?
    fi

    log "容器未运行，跳过流量限量检查"
    exit 0
fi

if ! read_net_bytes; then
    log "无法读取 Docker 网络统计"
    exit 1
fi

if [ "$PERIOD" != "$CURRENT_PERIOD" ]; then
    PERIOD=$CURRENT_PERIOD
    BASE_RX_BYTES=$RX_BYTES
    BASE_TX_BYTES=$TX_BYTES
    STOPPED_BY_QUOTA=0
    save_state
    log "已刷新月度流量基线: $PERIOD"
    exit 0
fi

USED_BYTES=$((RX_BYTES - BASE_RX_BYTES + TX_BYTES - BASE_TX_BYTES))
if [ "$USED_BYTES" -lt 0 ]; then
    BASE_RX_BYTES=$RX_BYTES
    BASE_TX_BYTES=$TX_BYTES
    STOPPED_BY_QUOTA=0
    save_state
    log "检测到 Docker 统计重置，已重建月度基线"
    exit 0
fi

if [ "$USED_BYTES" -ge "$LIMIT_BYTES" ]; then
    STOPPED_BY_QUOTA=1
    save_state
    log "本月流量已达 $(format_gib "$USED_BYTES") / ${QUOTA_LIMIT_GB}GiB，停止代理"
    docker stop "$CONTAINER" >/dev/null
    exit 0
fi

STOPPED_BY_QUOTA=0
save_state
log "本月流量 $(format_gib "$USED_BYTES") / ${QUOTA_LIMIT_GB}GiB"
