#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1


CONTAINER="telegram-mtproto-proxy"

echo "=== Telegram MTProto 代理流量监控 ==="
echo ""

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "错误: 容器未运行"
    exit 1
fi

echo "实时流量监控 (按 Ctrl+C 退出):"
echo ""

docker stats "$CONTAINER" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

echo ""
echo "持续监控中..."
docker stats "$CONTAINER" --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
