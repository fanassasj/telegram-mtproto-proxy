# Telegram MTProto Proxy 项目说明

## 项目结构

```
telegram-mtproto-proxy/
├── proxy.sh          # 一体化管理脚本（主入口）
├── start.sh          # 启动脚本（已整合至 proxy.sh，保留作为转发）
├── lib.sh            # 共用函数库
├── qrcode.sh         # 生成连接二维码
├── healthcheck.sh    # 健康检查
├── monitor.sh        # 实时监控
├── stats.sh          # 流量统计
├── report.sh         # 使用报告（历史数据）
├── alert.sh          # 告警检查
├── uninstall.sh      # 完全卸载
├── README.md         # 使用文档
├── .env              # 环境变量配置文件（系统参数）
└── config/           # 配置与运行数据目录
    └── config.py     # 代理后端配置文件
```

> [!NOTE]
> 配置参数同时保存在 `.env` (供 Docker Compose 及 Bash 脚本读取) 与 `config/config.py` (供 Python 后端读取) 中。

## 核心功能

### 1. 一键启动 (proxy.sh / start.sh)
- 支持通过主脚本 `proxy.sh` 或向后兼容的 `start.sh` 包装器进行一键部署和启动
- 自动生成随机端口和密钥
- 交互式选择功能：
  - 月度流量限量（默认 30GiB）
  - 告警监控（异常检测）
  - 使用统计（历史记录）

### 2. 安全特性
- **现代 Python 后端**：引入 `alexbers/mtprotoproxy` 后端，支持原生真实的 Fake TLS 混淆，抵抗流量检测。
- **随机与隔离**：随机高位端口（10000-65535）、16字节随机密钥，以及 Docker 容器物理隔离。
- **配置与权限加固**：配置文件权限收紧（`chmod 600`），敏感/临时状态文件均从公共 `/tmp/` 目录迁移至 `./config/` 私有安全目录下。
- **防火墙规则清理**：卸载时自动清理并释放在启用白名单时配置的 iptables 防火墙规则。

### 3. 性能优化
- CPU 限制：1核（预留 0.25核）
- 内存限制：512MB（预留 128MB）
- TCP 连接优化（keepalive）
- **监控开销优化**：合并多次 `docker stats` 调用为单次，大幅降低历史报告及告警检查时的 CPU 开销。
- **健康检查过渡**：容器健康检查机制升级为基于标准 Python socket 的本地 TCP 连接检测，避免频繁的网络请求及额外的检测开销。
- 自动健康检查（30秒间隔）
- 异常自动重启

### 4. 监控系统
- **实时监控** (monitor.sh)：CPU、内存、网络 I/O
- **流量统计** (stats.sh)：当前流量、连接数
- **使用报告** (report.sh)：历史数据、趋势分析
- **告警检查** (alert.sh)：CPU/内存过高告警

### 5. 月度流量限量
- 默认每月 30GiB
- 每月 1 号刷新周期
- 超过限量自动停止代理，下月自动恢复

### 6. 便捷工具
- **二维码生成** (qrcode.sh)：手机扫码连接
- **健康检查** (healthcheck.sh)：检查容器、端口、后端连通和 Fake TLS 链接
- **限量检查** (quota.sh)：检查本月流量并在超量时停止代理
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

所有配置同步保存在 `.env` 文件和 `config/config.py` 文件中：
- PORT：代理端口
- SECRET：连接密钥
- FAKE_TLS_DOMAIN：Fake TLS 链接使用的伪装域名
- USE_QUOTA：是否启用月度流量限量
- QUOTA_LIMIT_GB：月度限量 GiB
- QUOTA_RESET_DAY：每月刷新日期
- USE_ALERT：是否启用告警
- USE_STATS：是否启用统计

## Telegram 通知

编辑 `alert.sh`，配置：
- BOT_TOKEN：从 @BotFather 获取
- CHAT_ID：从 @userinfobot 获取

## 技术栈

- Docker & Docker Compose
- `alexbers/mtprotoproxy` (高性能 Python MTProto 代理后端)
- Bash 脚本

## 注意事项

1. 需要 root 权限（Docker 管理和定时任务）
2. 确保防火墙开放相应端口
3. 定期查看监控和日志
4. 了解当地法律法规
5. 建议仅供个人使用

## 维护命令

建议使用一体化主入口脚本进行日常维护：
```bash
# 进入交互式菜单（包含启动、停止、重启、日志查看、限额配置、卸载等）
./proxy.sh
```

如果需要，也可以使用标准的 Docker Compose 命令进行直接操作：
```bash
# 查看容器运行日志
docker compose logs -f

# 重启代理服务
docker compose restart

# 停止代理服务
docker compose stop

# 完全卸载（也可以在 proxy.sh 菜单中执行）
./uninstall.sh
```

## 文件说明

- `docker-compose.yml`：自动生成，包含代理容器编排配置
- `config/`：配置与状态数据目录
- `config/config.py`：后端服务运行配置文件
- `config/stats.log`：流量统计日志（启用统计时生成）
- `config/alert.log`：历史告警日志
- `config/quota.state`：流量配额检查状态数据
