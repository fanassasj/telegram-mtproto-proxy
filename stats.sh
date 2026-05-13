#!/bin/bash

CONTAINER="telegram-mtproto-proxy"

to_bytes() {
    local value unit
    value=$(printf "%s" "$1" | sed -E 's/^([0-9.]+).*/\1/')
    unit=$(printf "%s" "$1" | sed -E 's/^[0-9.]+([A-Za-z]+)$/\1/')

    awk -v value="$value" -v unit="$unit" '
        BEGIN {
            if (value == "" || unit == "") {
                print 0
                exit
            }
            scale["B"] = 1
            scale["kB"] = 1000
            scale["MB"] = 1000^2
            scale["GB"] = 1000^3
            scale["TB"] = 1000^4
            scale["KiB"] = 1024
            scale["MiB"] = 1024^2
            scale["GiB"] = 1024^3
            scale["TiB"] = 1024^4
            printf "%.0f\n", (value + 0) * scale[unit]
        }
    '
}

if ! docker ps | grep -q $CONTAINER; then
    echo "错误: 容器未运行"
    exit 1
fi

echo "=== 流量统计 ==="
echo ""

# 获取网络统计
STATS=$(docker stats $CONTAINER --no-stream --format "{{.NetIO}}")
echo "总流量: $STATS"

if [ -f .env ]; then
    source .env
fi

if [ "${USE_QUOTA:-y}" = "y" ] && [ -f ./config/quota.state ]; then
    source ./config/quota.state
    QUOTA_LIMIT_GB=${QUOTA_LIMIT_GB:-30}
    LIMIT_BYTES=$((QUOTA_LIMIT_GB * 1024 * 1024 * 1024))
    NET_IO=$(docker stats $CONTAINER --no-stream --format "{{.NetIO}}")
    RX_TEXT=${NET_IO%% / *}
    TX_TEXT=${NET_IO##* / }
    RX_BYTES=$(to_bytes "$RX_TEXT")
    TX_BYTES=$(to_bytes "$TX_TEXT")
    USED_BYTES=$((RX_BYTES - BASE_RX_BYTES + TX_BYTES - BASE_TX_BYTES))
    [ "$USED_BYTES" -lt 0 ] && USED_BYTES=0
    USED_GIB=$(awk -v b="$USED_BYTES" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }')
    echo "本月限量: ${USED_GIB}GiB / ${QUOTA_LIMIT_GB}GiB"
    echo "计费周期: ${PERIOD:-unknown}，每月 ${QUOTA_RESET_DAY:-1} 号刷新"
fi

echo ""
echo "=== 容器日志 (最近 50 行) ==="
docker logs --tail 50 $CONTAINER

echo ""
echo "=== 连接统计 ==="
PORT=$(docker port $CONTAINER 443 | cut -d: -f2)
if [ ! -z "$PORT" ]; then
    if command -v ss >/dev/null 2>&1; then
        CONNECTIONS=$(ss -tan state established "( sport = :$PORT or dport = :$PORT )" 2>/dev/null | tail -n +2 | wc -l)
    elif command -v netstat >/dev/null 2>&1; then
        CONNECTIONS=$(netstat -an | grep ":$PORT" | grep ESTABLISHED | wc -l)
    else
        CONNECTIONS="未知"
    fi
    echo "当前活跃连接数: $CONNECTIONS"
    echo "端口: $PORT"
fi
