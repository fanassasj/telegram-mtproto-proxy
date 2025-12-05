# Telegram MTProto Proxy

简单、安全、功能完整的 Telegram MTProto 代理服务器

[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 特性

- 🚀 **一键部署** - 单个脚本完成所有配置
- 🔐 **安全可靠** - 随机端口和密钥，可选 Nginx 伪装
- 📊 **完整监控** - 实时监控、流量统计、使用报告
- 🔔 **智能告警** - CPU/内存异常自动通知
- 🎯 **流量控制** - 可设置带宽限制
- 🔄 **灵活管理** - 支持密钥/端口更换、备份恢复
- 🛡️ **访问控制** - IP 白名单支持
- 📱 **移动友好** - 自动生成二维码，支持 IPv4/IPv6

## 快速开始

### 前置要求

- Docker 和 Docker Compose
- Linux 系统（推荐 Ubuntu/Debian）
- Root 权限

### 一键安装

```bash
# 克隆项目
git clone https://github.com/YOUR_USERNAME/telegram-mtproto-proxy.git
cd telegram-mtproto-proxy

# 运行管理脚本
./proxy.sh
```

### 传统方式

```bash
# 直接启动（交互式配置）
./start.sh

# 查看连接信息和二维码
./qrcode.sh
```

## 功能菜单

运行 `./proxy.sh` 后的完整菜单：

```
==========================================
  Telegram MTProto 代理管理
==========================================

1)  启动代理
2)  停止代理
3)  重启代理
4)  查看状态
5)  查看连接信息/二维码
6)  实时监控
7)  流量统计
8)  使用报告
9)  查看日志
10) 更换密钥
11) 更换端口
12) 备份配置
13) 恢复配置
14) 更新镜像
15) IP 白名单
16) 完全卸载
0)  退出
```

## 配置选项

启动时可选择：

- **Nginx 伪装** - 隐藏代理特征，伪装成普通网站
- **流量限制** - 防止带宽滥用，可自定义速率
- **告警监控** - CPU/内存异常时自动告警（支持 Telegram 通知）
- **使用统计** - 每小时记录流量和资源使用情况

## 性能优化

- ✅ 自动健康检查（30秒间隔）
- ✅ 资源限制（CPU: 1核, 内存: 512MB）
- ✅ TCP 连接优化（keepalive 参数）
- ✅ 异常自动重启
- ✅ 日志自动轮转（最大 10MB × 3 个文件）

## 监控命令

```bash
./monitor.sh  # 实时监控 CPU、内存、网络
./stats.sh    # 查看流量统计和连接数
./report.sh   # 查看历史使用报告
./alert.sh    # 手动检查告警
```

## 高级功能

### 更换密钥/端口

```bash
./proxy.sh
# 选择 10 (更换密钥) 或 11 (更换端口)
```

### 备份和恢复

```bash
# 备份配置
./proxy.sh  # 选择 12

# 恢复配置
./proxy.sh  # 选择 13
```

### IP 白名单

```bash
./proxy.sh  # 选择 15
# 支持单个 IP、IP 段（CIDR）、运营商 IP 段
```

### Telegram 通知

编辑 `alert.sh`，配置：

```bash
BOT_TOKEN="your_bot_token"  # 从 @BotFather 获取
CHAT_ID="your_chat_id"      # 从 @userinfobot 获取
```

## 项目结构

```
telegram-mtproto-proxy/
├── proxy.sh          # 一体化管理脚本（推荐）
├── start.sh          # 启动脚本
├── qrcode.sh         # 二维码生成
├── monitor.sh        # 实时监控
├── stats.sh          # 流量统计
├── report.sh         # 使用报告
├── alert.sh          # 告警检查
├── uninstall.sh      # 完全卸载
├── index.html        # Nginx 伪装页面
├── README.md         # 使用文档
└── PROJECT.md        # 项目详细说明
```

## 连接方式

### 方式1：扫描二维码
运行 `./qrcode.sh` 生成二维码，用 Telegram 扫描

### 方式2：点击链接
```
tg://proxy?server=YOUR_IP&port=PORT&secret=SECRET
```

### 方式3：手动配置
在 Telegram 设置中手动添加代理服务器

## 常见问题

**Q: 端口被封怎么办？**  
A: 运行 `./proxy.sh` 选择 11 (更换端口)

**Q: 如何提高安全性？**  
A: 启用 Nginx 伪装 + IP 白名单 + 定期更换密钥

**Q: 手机 IP 不固定如何设置白名单？**  
A: 添加运营商 IP 段（如 120.0.0.0/8）或不设白名单

**Q: 如何迁移到新服务器？**  
A: 使用备份功能（选项 12/13）

**Q: 支持多用户吗？**  
A: 当前版本单密钥，可通过更换密钥分配给不同用户

## 安全建议

1. ⚠️ 仅供个人使用，了解当地法律法规
2. 🔒 不要公开分享密钥和端口
3. 🔄 定期更换密钥和端口
4. 📊 定期查看监控和日志
5. 🛡️ 考虑启用 IP 白名单

## 技术栈

- [Telegram MTProto Proxy](https://github.com/TelegramMessenger/MTProxy) - 官方代理
- Docker & Docker Compose - 容器化部署
- Nginx - 反向代理和伪装
- Bash - 自动化脚本

## 卸载

```bash
./proxy.sh  # 选择 16 (完全卸载)
# 或
./uninstall.sh
```

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 免责声明

本项目仅供学习和研究使用，使用者需自行承担使用风险，并遵守当地法律法规。

---

⭐ 如果这个项目对你有帮助，请给个 Star！
