#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1


CONTAINER="telegram-mtproto-proxy"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "错误: 容器未运行"
    exit 1
fi

echo "=== 流量统计 ==="
echo ""

# 获取网络统计
STATS=$(docker stats $CONTAINER --no-stream --format "{{.NetIO}}")
echo "总流量: $STATS"

echo ""
echo "=== 容器日志 (最近 50 行) ==="
docker logs --tail 50 $CONTAINER

echo ""
echo "=== 连接统计 ==="
PORT=$(docker port $CONTAINER 443 | cut -d: -f2)
if [ ! -z "$PORT" ]; then
    if command -v ss >/dev/null 2>&1; then
        CONNECTIONS=$(ss -tan 2>/dev/null | awk -v port=":$PORT" '$1 == "ESTAB" && $4 ~ port"$" {count++} END {print count+0}')
    else
        CONNECTIONS=$(netstat -an 2>/dev/null | grep ":$PORT" | grep ESTABLISHED | wc -l)
    fi
    echo "当前活跃连接数: $CONNECTIONS"
    echo "端口: $PORT"
fi
