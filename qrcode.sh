#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
set -u

if [ ! -f .env ]; then
    echo "错误: 未找到配置文件，请先运行 ./start.sh"
    exit 1
fi

source .env
if [ -z "${PORT:-}" ] || [ -z "${SECRET:-}" ]; then
    echo "错误: .env 配置不完整，缺少 PORT 或 SECRET"
    exit 1
fi
FAKE_TLS_DOMAIN=${FAKE_TLS_DOMAIN:-www.microsoft.com}
FAKE_TLS_DOMAIN_HEX=$(printf "%s" "$FAKE_TLS_DOMAIN" | xxd -ps -c 256)
FAKE_TLS_SECRET="dd${SECRET}${FAKE_TLS_DOMAIN_HEX}"

ensure_qrencode() {
    if command -v qrencode >/dev/null 2>&1; then
        return 0
    fi

    echo "未检测到 qrencode，正在安装本地二维码工具..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y qrencode -qq
    else
        echo "错误: 当前系统没有 apt-get，请手动安装 qrencode"
        return 1
    fi

    command -v qrencode >/dev/null 2>&1
}

print_qrcode() {
    local label="$1"
    local url="$2"

    if ensure_qrencode; then
        echo "$label"
        echo ""
        qrencode -t ANSIUTF8 "$url"
        echo ""
    else
        echo "无法生成二维码: 未安装 qrencode"
        echo "已禁止在线二维码，避免泄露代理链接"
        echo ""
    fi
}

# 获取服务器 IPv4 和 IPv6
SERVER_IP4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null)
SERVER_IP6=$(curl -6 -s ifconfig.me 2>/dev/null)

echo "=== Telegram 代理连接信息 ==="
echo ""
echo "端口: $PORT"
echo "Fake TLS 域名: $FAKE_TLS_DOMAIN"
echo ""

if [ ! -z "$SERVER_IP4" ]; then
    PROXY_URL4_FAKE_TLS="tg://proxy?server=$SERVER_IP4&port=$PORT&secret=$FAKE_TLS_SECRET"
    PROXY_URL4_PLAIN="tg://proxy?server=$SERVER_IP4&port=$PORT&secret=$SECRET"
    echo "IPv4 服务器: $SERVER_IP4"
    echo "IPv4 推荐链接 (Fake TLS):"
    echo "$PROXY_URL4_FAKE_TLS"
    echo ""
    echo "IPv4 普通链接 (备用):"
    echo "$PROXY_URL4_PLAIN"
    echo ""
    
    print_qrcode "IPv4 推荐二维码 (Fake TLS):" "$PROXY_URL4_FAKE_TLS"
    print_qrcode "IPv4 普通二维码 (备用):" "$PROXY_URL4_PLAIN"
fi

if [ ! -z "$SERVER_IP6" ]; then
    PROXY_URL6_FAKE_TLS="tg://proxy?server=$SERVER_IP6&port=$PORT&secret=$FAKE_TLS_SECRET"
    PROXY_URL6_PLAIN="tg://proxy?server=$SERVER_IP6&port=$PORT&secret=$SECRET"
    echo "IPv6 服务器: $SERVER_IP6"
    echo "IPv6 推荐链接 (Fake TLS):"
    echo "$PROXY_URL6_FAKE_TLS"
    echo ""
    echo "IPv6 普通链接 (备用):"
    echo "$PROXY_URL6_PLAIN"
    echo ""
    
    print_qrcode "IPv6 推荐二维码 (Fake TLS):" "$PROXY_URL6_FAKE_TLS"
    print_qrcode "IPv6 普通二维码 (备用):" "$PROXY_URL6_PLAIN"
fi

if [ -z "$SERVER_IP4" ] && [ -z "$SERVER_IP6" ]; then
    echo "错误: 无法获取服务器 IP 地址"
fi
