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
| 生成用户配置文件 | 创建 `~/.config/clash/.env` 保存端口等信息 |
| 生成查询信息文件 | 创建 `~/.config/clash/query.txt` 包含所有访问地址和调试命令 |
| 自动切换代理 | 自动将 GLOBAL 切换到可用代理节点 |

### 一键部署示例

```bash
# 完整一键命令
./deploy.sh --sub "https://your-subscription-url"

# 输出示例：
# ✓ 服务模板已存在
# ✓ 目录创建完成: /home/user/.config/clash
# ! 端口 7890 被占用，代理端口自动分配: 27890
# ✓ 代理端口: 27890
# ✓ 控制台端口: 8305
# ✓ 订阅配置下载完成
# ✓ Web UI 下载完成
# ✓ 配置文件已修改
# ✓ 用户配置已保存到: /home/user/.config/clash/.env
# ✓ 已添加节点域名 DNS 策略: example.com
# ✓ 查询信息已保存到: /home/user/.config/clash/query.txt
# ✓ GLOBAL 已自动切换到: 🚀 节点选择
```

---

## 一、前置条件

- Linux 系统
- 已安装 mihomo：`/usr/bin/mihomo`
- 有订阅链接

---

## 二、用户配置文件

部署后生成以下文件：

### 2.1 环境配置文件 (`.env`)

`~/.config/clash/.env` 保存端口和订阅信息：

```bash
# ~/.config/clash/.env - 用户配置文件
MIXED_PORT=27890              # 代理端口
EXTERNAL_PORT=8305            # Web UI 控制台端口
SECRET=mihomo                 # Web UI 密钥
SUB_URL=https://...           # 订阅链接
NODE_DOMAIN=example.com       # 节点域名后缀（用于 DNS 策略）
HTTP_PROXY=http://127.0.0.1:27890
SOCKS5_PROXY=socks5://127.0.0.1:27890
```

**作用：**
- `update_subscription.sh` 读取此文件获取端口和订阅链接
- 更新订阅时保持端口不变

### 2.2 查询信息文件 (`query.txt`)

`~/.config/clash/query.txt` 包含所有部署信息和调试命令：

```bash
# 查看所有信息
cat ~/.config/clash/query.txt
```

**内容包括：**
- 端口信息（代理端口、Web UI 端口）
- Web UI 访问地址（本地和远程）
- 代理地址（HTTP/SOCKS5）
- 配置文件位置
- 调试命令（查看状态、日志、测试代理等）
- API 接口示例

---

## 三、安装服务模板（首次使用，需要 root）

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

## 四、手动部署步骤（可选）

如果不想使用一键脚本，可按以下步骤手动部署。

### 4.1 检查端口占用

```bash
ss -tunl | grep -E "7890|9090"
```

**如果端口被占用**，需要使用其他端口（如 27890、8305）。

### 4.2 创建目录结构

```bash
mkdir -p ~/.config/clash/resources/dist
```

### 4.3 下载配置文件

```bash
# 下载订阅配置
wget -O ~/.config/clash/config.yaml "你的订阅链接"

# 下载 Web UI
cd ~/.config/clash/resources
wget https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip
unzip dist.zip -d dist/
rm dist.zip
```

### 4.4 创建用户配置文件

```bash
cat > ~/.config/clash/.env <<EOF
# Mihomo 用户配置
MIXED_PORT=27890
EXTERNAL_PORT=8305
SECRET=mihomo
SUB_URL=你的订阅链接
NODE_DOMAIN=
EOF
```

### 4.5 修改配置文件

编辑 `~/.config/clash/config.yaml`，修改以下关键配置：

#### 端口配置

```yaml
mixed-port: 27890  # 避免冲突
external-controller: 0.0.0.0:8305
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

## 五、启动服务

```bash
# 启动
sudo systemctl start mihomo@$USER

# 开机自启
sudo systemctl enable mihomo@$USER

# 检查状态
systemctl status mihomo@$USER
```

---

## 六、切换代理节点（已自动处理）

**注意：** `deploy.sh` 已自动将 GLOBAL 切换到可用代理节点，通常无需手动操作。

如需手动切换：

1. 浏览器访问：`http://localhost:8305/ui/`
2. 密钥：`mihomo`
3. 找到 **GLOBAL** 选择器
4. 从 **DIRECT** 切换到代理节点（如"故障切换"）

### 方式二：命令行

```bash
# 读取端口
EXT_PORT=$(grep ^EXTERNAL_PORT= ~/.config/clash/.env | cut -d= -f2)

# 查看可用节点组
curl -s -H "Authorization: Bearer mihomo" http://localhost:$EXT_PORT/proxies | \
  python3 -c "import sys,json; d=json.load(sys.stdin); [print(k) for k in d['proxies'].keys()]" | head -20

# 切换到指定节点组
curl -X PUT "http://localhost:$EXT_PORT/proxies/GLOBAL" \
  -H "Authorization: Bearer mihomo" \
  -H "Content-Type: application/json" \
  -d '{"name":"♻️ 故障切换"}'
```

---

## 七、订阅更新

### 手动更新

```bash
# 更新当前用户
./update_subscription.sh

# 更新指定用户（需要 root）
./update_subscription.sh --user username

# 查看所有用户状态
./update_subscription.sh --status
```

**更新流程：**
1. 从 `~/.config/clash/.env` 读取端口配置
2. 下载新订阅
3. 备份旧配置（保留最近 10 个）
4. 保持端口不变，更新配置
5. 重启服务
6. 自动切换 GLOBAL

### 定时自动更新

```bash
# 添加 crontab 任务（每天凌晨 4 点更新）
(crontab -l 2>/dev/null; echo "0 4 * * * $(pwd)/update_subscription.sh --auto") | crontab -

# 或者使用 systemd timer
sudo tee /etc/systemd/system/mihomo-update.timer <<'EOF'
[Unit]
Description=Daily mihomo subscription update

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo tee /etc/systemd/system/mihomo-update.service <<'EOF'
[Unit]
Description=Mihomo subscription update

[Service]
Type=oneshot
ExecStart=/path/to/update_subscription.sh --auto
EOF

sudo systemctl daemon-reload
sudo systemctl enable mihomo-update.timer
```

---

## 八、验证代理

```bash
# 读取端口
MIXED_PORT=$(grep ^MIXED_PORT= ~/.config/clash/.env | cut -d= -f2)

# 测试 Google
curl -x http://127.0.0.1:$MIXED_PORT https://www.google.com

# 测试 YouTube
curl -x http://127.0.0.1:$MIXED_PORT https://www.youtube.com

# 查看代理 IP
curl -x http://127.0.0.1:$MIXED_PORT https://ipinfo.io/json
```

---

## 九、设置环境变量

### 临时设置

```bash
# 从配置文件读取端口
source ~/.config/clash/.env

export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTP_PROXY"
export all_proxy="$SOCKS5_PROXY"
export no_proxy="localhost,127.0.0.1"
```

### 永久设置

```bash
# 读取端口
MIXED_PORT=$(grep ^MIXED_PORT= ~/.config/clash/.env | cut -d= -f2)

cat >> ~/.bashrc << EOF

# Mihomo 代理
export http_proxy="http://127.0.0.1:$MIXED_PORT"
export https_proxy="http://127.0.0.1:$MIXED_PORT"
export all_proxy="socks5://127.0.0.1:$MIXED_PORT"
export no_proxy="localhost,127.0.0.1"
EOF

source ~/.bashrc
```

---

## 十、服务管理命令

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

## 十一、访问地址汇总

**快速查看：** `cat ~/.config/clash/query.txt`

从 `~/.config/clash/.env` 读取端口：

```bash
MIXED_PORT=$(grep ^MIXED_PORT= ~/.config/clash/.env | cut -d= -f2)
EXT_PORT=$(grep ^EXTERNAL_PORT= ~/.config/clash/.env | cut -d= -f2)
```

| 服务 | 地址 |
|------|------|
| HTTP 代理 | `http://127.0.0.1:<MIXED_PORT>` |
| SOCKS5 代理 | `socks5://127.0.0.1:<MIXED_PORT>` |
| Web 控制台 | `http://localhost:<EXTERNAL_PORT>/ui/` |
| API 地址 | `http://localhost:<EXTERNAL_PORT>` |

**局域网访问：** `http://<服务器IP>:<EXTERNAL_PORT>/ui/`

---

## 十二、常见问题排查

### 问题 1：节点全部超时/红色

**原因：** GLOBAL 选择器为 DIRECT（deploy.sh 已自动切换，如仍有问题请手动检查）

**解决：** 切换到代理节点（见第六步）

### 问题 2：DNS 解析失败

**日志：** `dns resolve failed: couldn't find ip`

**解决：**
1. 确保 `proxy-server-nameserver: system` 已配置（deploy.sh 自动处理）
2. 添加 `nameserver-policy` 解析节点域名（deploy.sh 自动处理）
3. 或使用 `./deploy.sh` 重新部署

### 问题 3：operation not permitted

**原因：** 服务缺少网络权限

**解决：** 确保服务模板包含 `CapabilityBoundingSet` 配置（见第三步）

### 问题 4：端口被占用

**解决：** 使用 `./deploy.sh` 自动分配可用端口，或手动修改配置文件中的端口号

### 问题 5：更新订阅后端口变了

**原因：** 缺少 `~/.config/clash/.env` 文件

**解决：**
```bash
# 创建用户配置文件
cat > ~/.config/clash/.env <<EOF
MIXED_PORT=你的代理端口
EXTERNAL_PORT=你的控制台端口
SECRET=mihomo
SUB_URL=你的订阅链接
EOF
```

---

## 十三、脚本参数说明

### deploy.sh

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

### update_subscription.sh

| 参数 | 说明 |
|------|------|
| `--auto` | 自动模式（无交互，适合定时任务） |
| `--user USER` | 指定用户更新 |
| `--status` | 显示所有用户状态 |
| `--help` | 显示帮助信息 |

**示例：**
```bash
# 定时任务
./update_subscription.sh --auto

# 查看状态
./update_subscription.sh --status
```

---

## 参考链接

- [Mihomo](https://github.com/MetaCubeX/mihomo)
- [DNS Bug #1422](https://github.com/MetaCubeX/mihomo/issues/1422)
- [Zashboard UI](https://github.com/Zephyruso/zashboard)
