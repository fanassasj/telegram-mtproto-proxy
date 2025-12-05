#!/bin/bash

CONTAINER="telegram-mtproto-proxy"

if ! docker ps | grep -q $CONTAINER; then
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
    CONNECTIONS=$(netstat -an | grep ":$PORT" | grep ESTABLISHED | wc -l)
    echo "当前活跃连接数: $CONNECTIONS"
    echo "端口: $PORT"
fi
