# Mihomo Multi-User

多用户环境下的 Mihomo 一键部署工具，适配 `mihomo@.service` 模板服务。

---

## 快速开始

```bash
# 一键部署（自动完成所有配置）
./deploy.sh --sub "你的订阅链接"

# 更新订阅
./update_subscription.sh
```

**deploy.sh 自动完成：**
- 端口冲突检测与自动分配
- 订阅配置下载
- DNS 配置修复（解决 bug #1422）
- Web UI 下载安装
- 服务启动 + 开机自启
- GLOBAL 自动切换到代理节点

---

## 用户配置文件

部署后生成 `~/.config/clash/.env`，存储用户配置：

```bash
# ~/.config/clash/.env
MIXED_PORT=27890        # 代理端口
EXTERNAL_PORT=8305      # Web UI 端口
SECRET=mihomo           # Web UI 密钥
SUB_URL=https://...     # 订阅链接
NODE_DOMAIN=xxx.com     # 节点域名后缀
```

> **重要：** 更新订阅时会读取此文件，确保端口配置一致。

---

## 目录结构

```
~/.config/clash/
├── config.yaml         # mihomo 主配置文件
├── .env                # 用户环境配置（端口、订阅等）
└── resources/
    └── dist/           # Web UI 文件
```

---

## 订阅更新

### 手动更新

```bash
# 更新当前用户订阅
./update_subscription.sh

# 更新指定用户
./update_subscription.sh --user username

# 查看状态
./update_subscription.sh --status
```

### 定时自动更新

```bash
# 添加 crontab 任务（每天凌晨 4 点更新）
(crontab -l 2>/dev/null; echo "0 4 * * * $PWD/update_subscription.sh --auto") | crontab -
```

**update_subscription.sh 功能：**
- 从 `~/.config/clash/.env` 读取端口配置
- 保留原有端口设置
- 自动备份旧配置（保留最近 10 个）
- 自动重启服务
- 自动切换 GLOBAL

---

## 服务管理

```bash
sudo systemctl start mihomo@$USER     # 启动
sudo systemctl stop mihomo@$USER      # 停止
sudo systemctl restart mihomo@$USER   # 重启
sudo systemctl enable mihomo@$USER    # 开机自启
systemctl status mihomo@$USER         # 状态
journalctl -u mihomo@$USER -f         # 日志
```

---

## 访问地址

| 服务 | 地址 |
|------|------|
| 代理 (HTTP/SOCKS5) | `http://127.0.0.1:<MIXED_PORT>` |
| Web UI (本地) | `http://127.0.0.1:<EXTERNAL_PORT>/ui/` |
| Web UI (远程) | `http://<服务器IP>:<EXTERNAL_PORT>/ui/` |
| 密钥 | `mihomo` |

> 端口从 `~/.config/clash/.env` 读取，默认 7890/9090

---

## 手动部署（详细步骤）

如果一键部署失败，参考 [SETUP_GUIDE.md](SETUP_GUIDE.md)。

### 1. 安装服务模板（首次使用）

```bash
sudo tee /etc/systemd/system/mihomo@.service <<'EOF'
[Unit]
Description=Mihomo Daemon for %i
After=network.target

[Service]
Type=simple
User=%i
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WorkingDirectory=/home/%i/.config/clash
ExecStart=/usr/bin/mihomo -d /home/%i/.config/clash
Restart=always
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
```

### 2. 创建目录

```bash
mkdir -p ~/.config/clash/resources/dist
```

### 3. 下载订阅并配置

```bash
# 下载订阅
wget -O ~/.config/clash/config.yaml "你的订阅链接"

# 创建用户配置
cat > ~/.config/clash/.env <<EOF
MIXED_PORT=7890
EXTERNAL_PORT=9090
SECRET=mihomo
SUB_URL=你的订阅链接
EOF
```

### 4. 启动服务

```bash
sudo systemctl start mihomo@$USER
sudo systemctl enable mihomo@$USER
```

---

## 规则匹配说明

Mihomo 的流量走向：

```
请求 → 规则匹配 → 代理组 → 节点
                      ↑
               GLOBAL 可覆盖
```

| 层级 | 作用 |
|------|------|
| 规则 | 根据 domain/IP 决定走哪个代理组 |
| 代理组 | 如"国外流量"、"大陆流量"等 |
| GLOBAL | 兜底选择，未匹配规则的流量走这里 |

---

## 常见问题

### Q: 节点全部超时？

1. 检查 GLOBAL 是否为 DIRECT → 切换到代理节点
2. 检查 DNS 配置是否正确
3. 查看日志：`journalctl -u mihomo@$USER -n 50`

### Q: DNS 解析失败？

添加 `nameserver-policy`：
```yaml
dns:
  nameserver-policy:
    "+.<节点域名后缀>":
      - 223.5.5.5
```

### Q: 更新订阅后端口变了？

确保 `~/.config/clash/.env` 文件存在且端口配置正确。

### Q: operation not permitted？

服务缺少网络权限，检查服务模板是否有 `CapabilityBoundingSet` 配置。

---

## 参考链接

- [Mihomo (MetaCubeX)](https://github.com/MetaCubeX/mihomo)
- [DNS Bug #1422](https://github.com/MetaCubeX/mihomo/issues/1422)
- [Zashboard (Web UI)](https://github.com/Zephyruso/zashboard)
