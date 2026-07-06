#!/bin/bash

# Telegram MTProto 代理启动脚本
# 此脚本已整合到 proxy.sh，保留此文件以向后兼容

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/proxy.sh"
