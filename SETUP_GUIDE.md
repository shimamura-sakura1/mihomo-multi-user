# Mihomo 多用户部署完整指南

本文档提供完整、可复现的部署流程。

---

## 快速开始：一键部署（推荐）

使用 `deploy.sh` 脚本自动完成部署，无需手动配置。

### 使用方法

```bash
# 方式一：自动下载订阅并部署
./deploy.sh --sub "你的订阅链接"

# 方式二：交互式部署（稍后手动添加订阅）
./deploy.sh

# 方式三：自动设置代理环境变量
SET_PROXY=y ./deploy.sh --sub "你的订阅链接"
```

### 脚本功能

| 功能 | 说明 |
|------|------|
| 自动检测端口冲突 | 检测 7890/9090 是否被占用，自动分配可用端口 |
| 自动下载 Web UI | 下载 zashboard 到正确目录 |
| 自动修改配置 | 修改端口、UI 路径、密钥 |
| 自动配置 DNS | 提取节点域名后缀，添加正确的 DNS 配置 |
| 解决 mihomo bug | 自动添加 `proxy-server-nameserver: system` |

### 一键部署示例

```bash
# 完整一键命令
./deploy.sh --sub "https://your-subscription-url"

# 输出示例：
# ✓ 服务模板已存在
# ✓ 目录创建完成: /home/user/.config/clash
# ! 端口 7890 被占用，代理端口自动分配: 17890
# ✓ 代理端口: 17890
# ✓ 控制台端口: 19090
# ✓ 订阅配置下载完成
# ✓ Web UI 下载完成
# ✓ 配置文件已修改
# ✓ 已添加节点域名 DNS 策略: example.com
```

---

## 一、前置条件

- Linux 系统
- 已安装 mihomo：`/usr/bin/mihomo`
- 有订阅链接

---

## 二、安装服务模板（首次使用，需要 root）

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

**说明：** `CapabilityBoundingSet` 是必需的，否则会出现 `operation not permitted` 错误。

---

## 三、手动部署步骤（可选）

如果不想使用一键脚本，可按以下步骤手动部署。

### 3.1 检查端口占用

```bash
ss -tunl | grep -E "7890|9090"
```

**如果端口被占用**，需要使用其他端口（如 17890、19090）。

### 3.2 创建目录结构

```bash
mkdir -p ~/.config/clash/resources/dist
```

### 3.3 下载配置文件

```bash
# 下载订阅配置
wget -O ~/.config/clash/config.yaml "你的订阅链接"

# 下载 Web UI
cd ~/.config/clash/resources
wget https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip
unzip dist.zip -d dist/
rm dist.zip
```

### 3.4 修改配置文件

编辑 `~/.config/clash/config.yaml`，修改以下关键配置：

#### 端口配置

```yaml
mixed-port: 17890  # 避免冲突
external-controller: 0.0.0.0:19090
external-ui: /home/你的用户名/.config/clash/resources/dist
secret: "mihomo"
allow-lan: true
```

#### DNS 配置（关键！解决节点域名解析问题）

```yaml
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
    "+.example.com":  # 替换为你的节点域名后缀
    - 223.5.5.5
```

**查找节点域名后缀：**
```bash
grep "server:" ~/.config/clash/config.yaml | head -3
# 输出示例：server: xxx.jp.node.example.com
# 后缀就是：example.com
```

---

## 四、启动服务

```bash
# 启动
sudo systemctl start mihomo@$USER

# 开机自启
sudo systemctl enable mihomo@$USER

# 检查状态
systemctl status mihomo@$USER
```

---

## 五、切换代理节点（重要！）

**默认 GLOBAL 选择器是 DIRECT，流量不会走代理，必须手动切换！**

### 方式一：Web UI

1. 浏览器访问：`http://localhost:9090/ui`
2. 密钥：`mihomo`
3. 找到 **GLOBAL** 选择器
4. 从 **DIRECT** 切换到代理节点（如"故障切换"）

### 方式二：命令行

```bash
# 查看可用节点组
curl -s -H "Authorization: Bearer mihomo" http://localhost:9090/proxies | \
  python3 -c "import sys,json; d=json.load(sys.stdin); [print(k) for k in d['proxies'].keys()]" | head -20

# 切换到指定节点组
curl -X PUT "http://localhost:9090/proxies/GLOBAL" \
  -H "Authorization: Bearer mihomo" \
  -H "Content-Type: application/json" \
  -d '{"name":"♻️ 故障切换"}'
```

---

## 六、验证代理

```bash
# 测试 Google
curl -x http://127.0.0.1:7890 https://www.google.com

# 测试 YouTube
curl -x http://127.0.0.1:7890 https://www.youtube.com

# 查看代理 IP
curl -x http://127.0.0.1:7890 https://ipinfo.io/json
```

---

## 七、设置环境变量

### 临时设置

```bash
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
export all_proxy="socks5://127.0.0.1:7890"
export no_proxy="localhost,127.0.0.1"
```

### 永久设置

```bash
cat >> ~/.bashrc << 'EOF'

# Mihomo 代理
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
export all_proxy="socks5://127.0.0.1:7890"
export no_proxy="localhost,127.0.0.1"
EOF

source ~/.bashrc
```

---

## 八、服务管理命令

```bash
sudo systemctl start mihomo@$USER     # 启动
sudo systemctl stop mihomo@$USER      # 停止
sudo systemctl restart mihomo@$USER   # 重启
systemctl status mihomo@$USER         # 状态
journalctl -u mihomo@$USER -f         # 日志
sudo systemctl enable mihomo@$USER    # 开机自启
sudo systemctl disable mihomo@$USER   # 取消自启
```

---

## 九、访问地址汇总

| 服务 | 地址 |
|------|------|
| HTTP 代理 | `http://127.0.0.1:7890` |
| SOCKS5 代理 | `socks5://127.0.0.1:7890` |
| Web 控制台 | `http://localhost:9090/ui` |
| API 地址 | `http://localhost:9090` |

**局域网访问：** `http://<服务器IP>:9090/ui`

---

## 十、常见问题排查

### 问题 1：节点全部超时/红色

**原因：** GLOBAL 选择器为 DIRECT

**解决：** 切换到代理节点（见第五步）

### 问题 2：DNS 解析失败

**日志：** `dns resolve failed: couldn't find ip`

**解决：**
1. 确保 `proxy-server-nameserver: system` 已配置
2. 添加 `nameserver-policy` 解析节点域名
3. 或使用 `./deploy.sh` 自动处理

### 问题 3：operation not permitted

**原因：** 服务缺少网络权限

**解决：** 确保服务模板包含 `CapabilityBoundingSet` 配置（见第二步）

### 问题 4：端口被占用

**解决：** 使用 `./deploy.sh` 自动分配可用端口，或手动修改配置文件中的端口号

---

## 十一、deploy.sh 参数说明

| 参数 | 说明 |
|------|------|
| `--sub "URL"` | 自动下载订阅配置 |
| `--sub=URL` | 同上，等号格式 |
| `SET_PROXY=y` | 自动添加代理环境变量到 ~/.bashrc |

**示例：**
```bash
# 自动下载订阅 + 设置环境变量
SET_PROXY=y ./deploy.sh --sub "https://your-sub-url"
```

---

## 参考链接

- [Mihomo](https://github.com/MetaCubeX/mihomo)
- [DNS Bug #1422](https://github.com/MetaCubeX/mihomo/issues/1422)
- [Zashboard UI](https://github.com/Zephyruso/zashboard)
