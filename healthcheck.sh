#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

CONTAINER="telegram-mtproto-proxy"

ok() {
    echo "[OK] $1"
}

warn() {
    echo "[WARN] $1"
}

fail() {
    echo "[FAIL] $1"
}

check_tcp() {
    local host="$1"
    local port="$2"
    timeout 4 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

if [ ! -f .env ]; then
    fail "未找到 .env，请先启动代理"
    exit 1
fi

source .env
FAKE_TLS_DOMAIN=${FAKE_TLS_DOMAIN:-www.google.com}
FAKE_TLS_DOMAIN_HEX=$(printf "%s" "$FAKE_TLS_DOMAIN" | xxd -ps -c 256)
FAKE_TLS_SECRET="dd${SECRET}${FAKE_TLS_DOMAIN_HEX}"

echo "=== Telegram MTProto 代理健康检查 ==="
echo ""
echo "端口: $PORT"
echo "Fake TLS 域名: $FAKE_TLS_DOMAIN"
if [ "${USE_QUOTA:-y}" = "y" ]; then
    echo "月度限量: ${QUOTA_LIMIT_GB:-30}GiB，每月 ${QUOTA_RESET_DAY:-1} 号刷新"
fi
echo ""

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    ok "容器正在运行: $CONTAINER"
else
    fail "容器未运行: $CONTAINER"
    exit 1
fi

PORT_MAP=$(docker port "$CONTAINER" 443 2>/dev/null | tr '\n' ' ')
if echo "$PORT_MAP" | grep -q ":$PORT"; then
    ok "Docker 端口映射正常: $PORT_MAP"
else
    fail "Docker 端口映射异常: ${PORT_MAP:-未找到}"
fi

if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\])$PORT$"; then
    ok "宿主机正在监听端口 $PORT"
else
    fail "宿主机未监听端口 $PORT"
fi

if check_tcp 127.0.0.1 "$PORT"; then
    ok "本机 TCP 连通: 127.0.0.1:$PORT"
else
    fail "本机 TCP 不通: 127.0.0.1:$PORT"
fi

PUBLIC_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s --max-time 5 api.ipify.org 2>/dev/null)
if [ -n "$PUBLIC_IP" ]; then
    ok "公网 IPv4: $PUBLIC_IP"
else
    warn "无法获取公网 IPv4"
fi

BACKENDS="149.154.175.50:8888 149.154.161.144:8888 91.105.192.110:443 91.108.4.152:8888 91.108.56.185:8888"
BACKEND_OK=0
for backend in $BACKENDS; do
    host=${backend%:*}
    port=${backend#*:}
    if docker exec "$CONTAINER" python3 -c "import socket; s = socket.socket(); s.settimeout(4); s.connect(('$host', $port))" >/dev/null 2>&1; then
        ok "Telegram 后端可达: $backend"
        BACKEND_OK=1
        break
    fi
done

if [ "$BACKEND_OK" -eq 0 ]; then
    fail "容器内无法连接 Telegram 后端（容器可能缺少 python3 或网络不通）"
fi

if [ "${USE_QUOTA:-y}" = "y" ]; then
    if [ -f ./config/quota.state ]; then
        # shellcheck disable=SC1091
        source ./config/quota.state
        ok "月度限量状态: ${PERIOD:-unknown}，超量停止标记 ${STOPPED_BY_QUOTA:-0}"
    else
        warn "月度限量尚未建立基线，运行 ./quota.sh 可立即初始化"
    fi
fi

echo ""
echo "推荐连接链接 (Fake TLS):"
if [ -n "${PUBLIC_IP:-}" ]; then
    echo "tg://proxy?server=$PUBLIC_IP&port=$PORT&secret=$FAKE_TLS_SECRET"
else
    echo "tg://proxy?server=YOUR_SERVER_IP&port=$PORT&secret=$FAKE_TLS_SECRET"
fi

echo ""
echo "提示: 如果本机检查正常但客户端无法连接，请检查云安全组是否放行 TCP $PORT。"
