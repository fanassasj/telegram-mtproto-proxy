# Telegram MTProto Proxy 项目说明

## 项目结构

```
telegram-mtproto-proxy/
├── start.sh          # 主启动脚本（交互式配置）
├── qrcode.sh         # 生成连接二维码
├── monitor.sh        # 实时监控
├── stats.sh          # 流量统计
├── report.sh         # 使用报告（历史数据）
├── alert.sh          # 告警检查
├── uninstall.sh      # 完全卸载
├── index.html        # Nginx 伪装页面
├── README.md         # 使用文档
└── .env              # 配置文件（自动生成）
```

## 核心功能

### 1. 一键启动 (start.sh)
- 自动生成随机端口和密钥
- 交互式选择功能：
  - Nginx 伪装（隐藏代理特征）
  - 流量限制（防止滥用）
  - 告警监控（异常检测）
  - 使用统计（历史记录）

### 2. 安全特性
- 随机端口（10000-65535）
- 16字节随机密钥
- Docker 容器隔离
- 可选 Nginx 反向代理伪装

### 3. 性能优化
- CPU 限制：1核（预留 0.25核）
- 内存限制：512MB（预留 128MB）
- TCP 连接优化（keepalive）
- 自动健康检查（30秒间隔）
- 异常自动重启

### 4. 监控系统
- **实时监控** (monitor.sh)：CPU、内存、网络 I/O
- **流量统计** (stats.sh)：当前流量、连接数
- **使用报告** (report.sh)：历史数据、趋势分析
- **告警检查** (alert.sh)：CPU/内存过高告警

### 5. 流量控制
- 可自定义限速（默认 10Mbps）
- 突发速率为限速的 2 倍
- 基于 tc (traffic control)

### 6. 便捷工具
- **二维码生成** (qrcode.sh)：手机扫码连接
- **一键卸载** (uninstall.sh)：完全清理

## 快速开始

```bash
# 1. 启动服务
./start.sh

# 2. 生成二维码
./qrcode.sh

# 3. 查看监控
./monitor.sh
```

## 配置说明

所有配置保存在 `.env` 文件：
- PORT：代理端口
- SECRET：连接密钥
- USE_NGINX：是否启用 Nginx
- USE_LIMIT：是否限速
- LIMIT_RATE：限速值
- USE_ALERT：是否启用告警
- USE_STATS：是否启用统计

## Telegram 通知

编辑 `alert.sh`，配置：
- BOT_TOKEN：从 @BotFather 获取
- CHAT_ID：从 @userinfobot 获取

## 技术栈

- Docker & Docker Compose
- Telegram 官方 MTProto Proxy
- Nginx (可选)
- Linux tc (流量控制)
- Bash 脚本

## 注意事项

1. 需要 root 权限（流量限制功能）
2. 确保防火墙开放相应端口
3. 定期查看监控和日志
4. 了解当地法律法规
5. 建议仅供个人使用

## 维护命令

```bash
# 查看日志
docker compose logs -f

# 重启服务
docker compose restart

# 停止服务
docker compose stop

# 完全卸载
./uninstall.sh
```

## 文件说明

- `docker compose.yml`：自动生成，包含服务配置
- `nginx-runtime.conf`：Nginx 配置（启用伪装时生成）
- `config/`：数据目录
- `config/stats.log`：统计日志（启用统计时生成）
