#!/bin/bash

CONTAINER="telegram-mtproto-proxy"
STATS_FILE="./config/stats.log"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "错误: 容器未运行"
    exit 1
fi

# 创建统计目录
mkdir -p ./config

# 获取当前统计
TIMESTAMP=$(date +%s)
DATE=$(date '+%Y-%m-%d %H:%M:%S')
STATS=$(docker stats $CONTAINER --no-stream --format "{{.NetIO}}")
CPU=$(docker stats $CONTAINER --no-stream --format "{{.CPUPerc}}" | sed 's/%//g')
MEM=$(docker stats $CONTAINER --no-stream --format "{{.MemUsage}}")

# 记录到日志
echo "$TIMESTAMP|$DATE|$STATS|$CPU|$MEM" >> $STATS_FILE

echo "=== Telegram 代理使用统计 ==="
echo ""
echo "当前状态 ($DATE):"
echo "- 流量: $STATS"
echo "- CPU: ${CPU}%"
echo "- 内存: $MEM"
echo ""

# 统计分析
if [ -f "$STATS_FILE" ]; then
    TOTAL_LINES=$(wc -l < $STATS_FILE)
    
    if [ $TOTAL_LINES -gt 1 ]; then
        echo "历史统计:"
        echo "- 记录数: $TOTAL_LINES"
        
        # 最近24小时
        YESTERDAY=$(date -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s 2>/dev/null || echo 0)
        RECENT=$(awk -F'|' -v ts=$YESTERDAY '$1 > ts' $STATS_FILE | wc -l)
        echo "- 最近24小时记录: $RECENT"
        
        # 平均 CPU
        AVG_CPU=$(awk -F'|' '{sum+=$4; count++} END {if(count>0) printf "%.2f", sum/count}' $STATS_FILE)
        echo "- 平均 CPU: ${AVG_CPU}%"
        
        echo ""
        echo "最近10条记录:"
        tail -10 $STATS_FILE | awk -F'|' '{printf "%s | 流量: %s | CPU: %s%%\n", $2, $3, $4}'
    fi
fi

echo ""
echo "提示: 此脚本每次运行都会记录统计数据"
echo "查看完整日志: cat $STATS_FILE"
