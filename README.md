# Mihomo Multi-User

多用户环境下的 Mihomo 一键部署工具，适配 `mihomo@.service` 模板服务。

---

## 一键部署

```bash
# 前置条件：系统已安装 mihomo
sudo apt install mihomo  # 或其他安装方式

# 一键部署（自动完成所有配置）
./deploy.sh --sub "你的订阅链接"

# 如需代理环境变量
SET_PROXY=y ./deploy.sh --sub "你的订阅链接"
```

**deploy.sh 自动完成：**
- 端口冲突检测与自动分配
- 订阅配置下载
- DNS 配置修复（解决 bug #1422）
- Web UI 下载安装
- 服务启动 + 开机自启
- GLOBAL 自动切换到代理节点

---

## 手动部署（详细步骤）

如果一键部署失败，按以下步骤操作。

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

### 2. 创建目录结构

```bash
mkdir -p ~/.config/clash/resources/dist
```

### 3. 下载订阅配置

```bash
wget -O ~/.config/clash/config.yaml "你的订阅链接"
```

### 4. 修改配置文件

编辑 `~/.config/clash/config.yaml`：

```yaml
# 端口配置（检查是否冲突：ss -tunl | grep 7890）
mixed-port: 7890

# 控制台配置
external-controller: 0.0.0.0:9090
external-ui: /home/$(whoami)/.config/clash/resources/dist
secret: "mihomo"

# DNS 配置（解决节点域名解析问题）
dns:
  enable: true
  respect-rules: false
  listen: 0.0.0.0:1053
  default-nameserver:
    - 223.5.5.5
  proxy-server-nameserver:
    - system
  enhanced-mode: redir-host
  nameserver-policy:
    "+.<节点域名后缀>":  # 如 "+.example.com"
      - 223.5.5.5
```

### 5. 下载 Web UI

```bash
cd ~/.config/clash/resources
wget https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip
unzip dist.zip -d dist/
# 修正嵌套目录
[ -d dist/dist ] && mv dist/dist/* dist/ && rmdir dist/dist
rm dist.zip
```

### 6. 启动服务

```bash
sudo systemctl start mihomo@$USER
sudo systemctl enable mihomo@$USER  # 开机自启
```

### 7. 切换代理节点

**重要！** GLOBAL 默认是 DIRECT，需要切换：

```bash
# API 方式切换
curl -X PUT "http://localhost:9090/proxies/GLOBAL" \
  -H "Authorization: Bearer mihomo" \
  -H "Content-Type: application/json" \
  -d '{"name":"♻️ 故障切换"}'
```

或在 Web UI (`http://127.0.0.1:9090/ui/`) 中切换。

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

**验证流量走向：**
```bash
# 访问网站后查看日志
curl -x http://127.0.0.1:7890 https://www.google.com
journalctl -u mihomo@$USER -n 3 --no-pager

# 示例输出：
# Google → match RuleSet(Global) → 🌐 国际网站[🇯🇵 日本 05]
# Bilibili → match RuleSet(AsianMedia) → DIRECT
```

---

## 使用方法

### 设置代理环境变量

```bash
# 临时
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"

# 永久（写入 ~/.bashrc）
echo 'export http_proxy="http://127.0.0.1:7890"' >> ~/.bashrc
echo 'export https_proxy="http://127.0.0.1:7890"' >> ~/.bashrc
source ~/.bashrc
```

### 验证代理

```bash
# 不走代理（SSH 转发）
curl -s https://ipinfo.io/json | jq '.ip, .country'

# 走代理
curl -s --connect-timeout 30 -x http://127.0.0.1:7890 https://ipinfo.io/json | jq '.ip, .country'

# 测试 Google
curl -x http://127.0.0.1:7890 https://www.google.com -o /dev/null -w "%{http_code}\n"
```

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
| 代理 (HTTP/SOCKS5) | `http://127.0.0.1:7890` |
| Web UI (本地) | `http://127.0.0.1:9090/ui/` |
| Web UI (远程) | `http://<服务器IP>:9090/ui/` |
| API | `http://localhost:9090` |
| 密钥 | `mihomo` |

> **远程访问 Web UI**: 将 `<服务器IP>` 替换为你的服务器地址

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

### Q: operation not permitted？

服务缺少网络权限，检查服务模板是否有 `CapabilityBoundingSet` 配置。

### Q: 代理不生效？

1. 确认服务运行：`systemctl status mihomo@$USER`
2. 确认端口监听：`ss -tln | grep 7890`
3. 确认 GLOBAL 不是 DIRECT
4. 查看日志确认流量走向

---

## 参考链接

- [Mihomo (MetaCubeX)](https://github.com/MetaCubeX/mihomo)
- [DNS Bug #1422](https://github.com/MetaCubeX/mihomo/issues/1422)
- [Zashboard (Web UI)](https://github.com/Zephyruso/zashboard)
