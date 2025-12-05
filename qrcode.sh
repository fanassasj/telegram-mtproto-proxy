#!/bin/bash

if [ ! -f .env ]; then
    echo "错误: 未找到配置文件，请先运行 ./start.sh"
    exit 1
fi

source .env

# 获取服务器 IPv4 和 IPv6
SERVER_IP4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null)
SERVER_IP6=$(curl -6 -s ifconfig.me 2>/dev/null)

echo "=== Telegram 代理连接信息 ==="
echo ""
echo "端口: $PORT"
echo "密钥: $SECRET"
echo ""

if [ ! -z "$SERVER_IP4" ]; then
    PROXY_URL4="tg://proxy?server=$SERVER_IP4&port=$PORT&secret=$SECRET"
    echo "IPv4 服务器: $SERVER_IP4"
    echo "IPv4 连接链接:"
    echo "$PROXY_URL4"
    echo ""
    
    if command -v qrencode &> /dev/null; then
        echo "IPv4 二维码:"
        echo ""
        qrencode -t ANSIUTF8 "$PROXY_URL4"
        echo ""
    else
        ENCODED_URL4=$(echo -n "$PROXY_URL4" | jq -sRr @uri 2>/dev/null || python3 -c "import urllib.parse; print(urllib.parse.quote(input()))" <<< "$PROXY_URL4" 2>/dev/null || echo "$PROXY_URL4")
        echo "IPv4 在线二维码:"
        echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$ENCODED_URL4"
        echo ""
    fi
fi

if [ ! -z "$SERVER_IP6" ]; then
    PROXY_URL6="tg://proxy?server=$SERVER_IP6&port=$PORT&secret=$SECRET"
    echo "IPv6 服务器: $SERVER_IP6"
    echo "IPv6 连接链接:"
    echo "$PROXY_URL6"
    echo ""
    
    if command -v qrencode &> /dev/null; then
        echo "IPv6 二维码:"
        echo ""
        qrencode -t ANSIUTF8 "$PROXY_URL6"
        echo ""
    else
        ENCODED_URL6=$(echo -n "$PROXY_URL6" | jq -sRr @uri 2>/dev/null || python3 -c "import urllib.parse; print(urllib.parse.quote(input()))" <<< "$PROXY_URL6" 2>/dev/null || echo "$PROXY_URL6")
        echo "IPv6 在线二维码:"
        echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$ENCODED_URL6"
        echo ""
    fi
fi

if [ -z "$SERVER_IP4" ] && [ -z "$SERVER_IP6" ]; then
    echo "错误: 无法获取服务器 IP 地址"
fi
