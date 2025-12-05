#!/bin/bash

echo "=========================================="
echo "  GitHub 快速上传脚本"
echo "=========================================="
echo ""
echo "仓库信息："
echo "- 用户名: fanassasj"
echo "- 仓库名: telegram-mtproto-proxy"
echo "- 地址: https://github.com/fanassasj/telegram-mtproto-proxy"
echo ""
echo "请确认已在 GitHub 创建仓库！"
echo ""
read -p "按回车键继续，或 Ctrl+C 取消..."

echo ""
echo "正在添加远程仓库..."
git remote add origin https://github.com/fanassasj/telegram-mtproto-proxy.git 2>/dev/null || echo "远程仓库已存在"

echo ""
echo "正在推送代码..."
git branch -M main
git push -u origin main

echo ""
echo "=========================================="
echo "  上传完成！"
echo "=========================================="
echo ""
echo "访问: https://github.com/fanassasj/telegram-mtproto-proxy"
echo ""
