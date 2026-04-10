#!/usr/bin/env bash
#
# Mihomo 多用户环境一键部署脚本
# 适配 mihomo@.service 模板服务
#
# 使用方法:
#   ./deploy.sh              # 交互式部署
#   ./deploy.sh --sub "订阅链接"  # 自动下载订阅
#   SET_PROXY=y ./deploy.sh  # 自动设置代理环境变量
#

set -e

# ==================== 配置 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASH_DIR="$HOME/.config/clash"
RESOURCES_DIR="$CLASH_DIR/resources"
USER_ENV_FILE="$CLASH_DIR/.env"
UI_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"

# 默认端口范围
DEFAULT_MIXED_PORT=7890
DEFAULT_EXTERNAL_PORT=9090
MIN_PORT=10000
MAX_PORT=60000


# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}! $1${NC}"; }
info() { echo -e "${BLUE}→ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# ==================== 工具函数 ====================

# 检测端口是否被占用
is_port_used() {
    local port=$1
    ss -tunl 2>/dev/null | grep -qs ":${port}\b"
}

# 获取可用端口
get_available_port() {
    local port
    local attempts=0
    local max_attempts=100

    while [ $attempts -lt $max_attempts ]; do
        port=$(shuf -i ${MIN_PORT}-${MAX_PORT} -n 1)
        if ! is_port_used $port; then
            echo $port
            return 0
        fi
        ((attempts++))
    done

    # 如果随机失败，顺序查找
    for port in $(seq $MIN_PORT $MAX_PORT); do
        if ! is_port_used $port; then
            echo $port
            return 0
        fi
    done

    fail "无法找到可用端口"
}

# 智能分配端口
allocate_port() {
    local preferred_port=$1
    local port_name=$2

    # 先检查默认端口是否可用
    if ! is_port_used $preferred_port; then
        echo $preferred_port
        return 0
    fi

    # 默认端口被占用，分配新端口
    local new_port=$(get_available_port)
    echo -e "${YELLOW}! 端口 $preferred_port 被占用，${port_name}自动分配: $new_port${NC}" >&2
    echo $new_port
}

# 下载文件
download() {
    local url=$1
    local output=$2
    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout 30 "$url" -o "$output"
    elif command -v wget &>/dev/null; then
        wget -q --timeout=30 "$url" -O "$output"
    else
        fail "需要 curl 或 wget"
    fi
}

# 提取订阅配置中的节点域名后缀
extract_node_domain() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        # 从 server 字段提取域名后缀
        local domain=$(grep -m1 "server:" "$config_file" 2>/dev/null | awk '{print $2}' | grep -oE '\.[^.]+\.[^.]+$' | sed 's/^\.//')
        if [ -n "$domain" ]; then
            echo "$domain"
            return 0
        fi
    fi
    echo ""
}

# 获取服务器 IP
get_server_ip() {
    curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1"
}

# 生成用户级别的 .env 文件
generate_user_env() {
    local mixed_port=$1
    local ext_port=$2
    local node_domain=$3
    local sub_url=$4

    local server_ip=$(get_server_ip)

    cat > "$USER_ENV_FILE" <<EOF
# Mihomo 用户配置（自动生成）
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 代理端口
MIXED_PORT=$mixed_port

# Web UI 控制台端口
EXTERNAL_PORT=$ext_port

# Web UI 访问地址
WEBUI_URL=http://127.0.0.1:${ext_port}/ui/
WEBUI_URL_REMOTE=http://${server_ip}:${ext_port}/ui/

# Web UI 密钥
SECRET=mihomo

# 节点域名（用于 DNS 策略）
NODE_DOMAIN=${node_domain:-}

# 订阅链接
SUB_URL=${sub_url:-}

# 代理地址
HTTP_PROXY=http://127.0.0.1:$mixed_port
SOCKS5_PROXY=socks5://127.0.0.1:$mixed_port
EOF

    ok "用户配置已保存到: $USER_ENV_FILE"
}

# 生成 query.txt 信息文件
generate_query_file() {
    local mixed_port=$1
    local ext_port=$2
    local config_file=$3
    local log_file="$CLASH_DIR/query.txt"
    local server_ip=$(get_server_ip)

    cat > "$log_file" <<EOF
========================================
Mihomo 服务配置信息
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
用户: $USER
========================================

【端口信息】
代理端口 (Mixed Port): $mixed_port
Web UI 端口 (External Controller): $ext_port

【Web UI 访问地址】
本地访问: http://127.0.0.1:$ext_port/ui/
远程访问: http://$server_ip:$ext_port/ui/
密钥 (Secret): mihomo

【代理地址】
HTTP 代理: http://127.0.0.1:$mixed_port
SOCKS5 代理: socks5://127.0.0.1:$mixed_port

【配置文件位置】
主配置: $config_file
用户环境变量: $USER_ENV_FILE
此文件: $log_file

【调试命令】
查看服务状态:
  systemctl status mihomo@$USER

查看日志:
  journalctl -u mihomo@$USER -f

测试代理:
  curl -x http://127.0.0.1:$mixed_port https://www.google.com

查看端口占用:
  ss -tunl | grep -E "$mixed_port|$ext_port"

重启服务:
  sudo systemctl restart mihomo@$USER

【API 接口】
获取代理组:
  curl -s -H "Authorization: Bearer mihomo" http://localhost:$ext_port/proxies | jq

切换 GLOBAL 代理:
  curl -X PUT http://localhost:$ext_port/proxies/GLOBAL \\
    -H "Authorization: Bearer mihomo" \\
    -H "Content-Type: application/json" \\
    -d '{"name":"🚀 节点选择"}'

========================================
EOF

    ok "查询信息已保存到: $log_file"
}

# 切换 GLOBAL 选择器到代理节点
switch_global_proxy() {
    local ext_port=$1
    local secret=$2
    local api_url="http://localhost:${ext_port}"

    # 获取可用代理组
    local proxy_groups=$(curl -s -H "Authorization: Bearer $secret" "${api_url}/proxies" 2>/dev/null)

    if [ -z "$proxy_groups" ]; then
        warn "无法连接到 API，跳过自动切换"
        return 1
    fi

    # 查找合适的代理组（优先选择故障切换/自动选择类型）
    local target_group=""
    for group in "♻️ 故障切换" "🚀 节点选择" "🚀 手动切换" "Proxy"; do
        if echo "$proxy_groups" | grep -q "\"$group\""; then
            target_group="$group"
            break
        fi
    done

    if [ -z "$target_group" ]; then
        warn "未找到合适的代理组，请手动在 UI 中切换"
        return 1
    fi

    # 切换 GLOBAL
    local result=$(curl -s -X PUT "${api_url}/proxies/GLOBAL" \
        -H "Authorization: Bearer $secret" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$target_group\"}" 2>/dev/null)

    if [ -n "$result" ] || curl -s -H "Authorization: Bearer $secret" "${api_url}/proxies/GLOBAL" 2>/dev/null | grep -q "$target_group"; then
        ok "GLOBAL 已自动切换到: $target_group"
        return 0
    else
        warn "自动切换失败，请手动在 UI 中切换"
        return 1
    fi
}

# 修改配置文件端口和DNS
patch_config() {
    local config_file=$1
    local mixed_port=$2
    local ext_port=$3
    local node_domain=$4

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # 备份原配置
    cp "$config_file" "${config_file}.bak"

    # 使用 awk 修改端口和添加字段（更可靠）
    awk -v mixed="$mixed_port" -v ext="$ext_port" -v ui="$RESOURCES_DIR/dist" '
    /^mixed-port:/ { $2 = mixed }
    /^external-controller:/ {
        $2 = "127.0.0.1:" ext
        print
        # 立即在下一行插入 external-ui（如果需要）
        if (!ext_ui_added && ui != "") {
            print "external-ui: " ui
            ext_ui_added = 1
        }
        next
    }
    /^external-ui:/ {
        $2 = ui
        ext_ui_added = 1
    }
    /^secret:/ { $0 = "secret: \"mihomo\"" }
    { print }
    END {
        # 如果 external-ui 没有被添加且 external-controller 存在，在文件末尾添加
        if (!ext_ui_added && ext != "") {
            print "external-ui: " ui
        }
    }
    ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

    # 添加 nameserver-policy（如果有节点域名）
    if [ -n "$node_domain" ]; then
        # 检查是否已有 nameserver-policy
        if ! grep -q "nameserver-policy:" "$config_file"; then
            # 在 dns 块末尾添加 nameserver-policy
            awk -v domain="$node_domain" '
                /^dns:/ { in_dns=1 }
                in_dns && /^[a-z]/ && !/^(dns|enable|respect|listen|default|proxy|enhanced|nameserver)/ { in_dns=0 }
                in_dns && /^enhanced-mode:/ {
                    print
                    print "  nameserver-policy:"
                    print "    \"+." domain "\":"
                    print "      - 223.5.5.5"
                    next
                }
                { print }
            ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
        fi
        ok "已添加节点域名 DNS 策略: $node_domain"
    fi

    ok "配置文件已修改"
}

# ==================== 主流程 ====================

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Mihomo 多用户环境一键部署           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    # 解析参数
    local SUB_URL=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sub=*)
                SUB_URL="${1#*=}"
                shift
                ;;
            --sub)
                shift
                SUB_URL="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # 1. 检查服务模板
    info "检查 mihomo@.service 服务模板..."
    if [ ! -f "/etc/systemd/system/mihomo@.service" ]; then
        fail "mihomo@.service 服务模板不存在，请先安装：
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
  sudo systemctl daemon-reload"
    else
        ok "服务模板已存在"
    fi

    # 2. 创建目录结构
    info "创建目录结构..."
    mkdir -p "$RESOURCES_DIR/dist"
    ok "目录创建完成: $CLASH_DIR"

    # 3. 分配端口
    info "检测可用端口..."
    MIXED_PORT=$(allocate_port $DEFAULT_MIXED_PORT "代理端口")
    EXT_PORT=$(allocate_port $DEFAULT_EXTERNAL_PORT "控制台端口")
    ok "代理端口: $MIXED_PORT"
    ok "控制台端口: $EXT_PORT"

    # 4. 下载订阅配置
    local config_file="$CLASH_DIR/config.yaml"
    if [ -n "$SUB_URL" ]; then
        info "下载订阅配置..."
        if download "$SUB_URL" "$config_file"; then
            ok "订阅配置下载完成"
        else
            fail "订阅配置下载失败"
        fi
    elif [ ! -f "$config_file" ] || [ ! -s "$config_file" ]; then
        warn "未找到订阅配置，请稍后手动添加："
        echo "  wget -O $config_file \"你的订阅链接\""
        touch "$config_file"
    fi

    # 5. 下载 Web UI
    info "下载 Web UI..."
    if [ -f "$RESOURCES_DIR/dist/index.html" ]; then
        warn "Web UI 已存在，跳过"
    else
        local tmp_zip="/tmp/mihomo-ui-$$.zip"
        if download "$UI_URL" "$tmp_zip"; then
            unzip -q "$tmp_zip" -d "$RESOURCES_DIR/dist/"
            # 修正嵌套目录
            if [ -d "$RESOURCES_DIR/dist/dist" ]; then
                mv "$RESOURCES_DIR/dist/dist/"* "$RESOURCES_DIR/dist/" 2>/dev/null || true
                rmdir "$RESOURCES_DIR/dist/dist" 2>/dev/null || true
            fi
            rm -f "$tmp_zip"
            ok "Web UI 下载完成"
        else
            warn "Web UI 下载失败，请手动下载"
            echo "  下载地址: $UI_URL"
            echo "  解压到: $RESOURCES_DIR/dist/"
        fi
    fi

    # 6. 提取节点域名并修改配置
    info "修改配置文件..."
    NODE_DOMAIN=$(extract_node_domain "$config_file")
    if [ -n "$NODE_DOMAIN" ]; then
        info "检测到节点域名后缀: $NODE_DOMAIN"
    fi

    if [ -f "$config_file" ] && [ -s "$config_file" ]; then
        patch_config "$config_file" "$MIXED_PORT" "$EXT_PORT" "$NODE_DOMAIN"
    fi

    # 7. 生成用户 .env 配置
    info "生成用户配置文件..."
    generate_user_env "$MIXED_PORT" "$EXT_PORT" "$NODE_DOMAIN" "$SUB_URL"

    # 8. 设置代理环境变量
    if [ "$SET_PROXY" = "y" ] || [ "$SET_PROXY" = "yes" ]; then
        if ! grep -q "http_proxy.*$MIXED_PORT" "$HOME/.bashrc" 2>/dev/null; then
            cat >> "$HOME/.bashrc" <<EOF

# Mihomo 代理环境变量
export http_proxy="http://127.0.0.1:$MIXED_PORT"
export https_proxy="http://127.0.0.1:$MIXED_PORT"
export all_proxy="socks5://127.0.0.1:$MIXED_PORT"
export no_proxy="localhost,127.0.0.1"
EOF
            ok "代理环境变量已添加到 ~/.bashrc"
            info "运行 source ~/.bashrc 生效"
        fi
    fi

    # 9. 启动服务
    info "启动 mihomo 服务..."
    if systemctl is-active --quiet "mihomo@$USER" 2>/dev/null; then
        ok "服务已在运行"
    else
        # 先检测是否需要 sudo 密码
        if sudo -n systemctl start "mihomo@$USER" >/dev/null 2>&1; then
            ok "服务启动成功"
            sleep 2
        elif sudo -n true 2>&1 | grep -q "password"; then
            warn "需要 sudo 密码，请手动执行: sudo systemctl start mihomo@\$USER"
        else
            fail "服务启动失败，请检查配置"
        fi
    fi

    # 10. 设置开机自启
    info "设置开机自启..."
    if systemctl is-enabled --quiet "mihomo@$USER" 2>/dev/null; then
        ok "开机自启已设置"
    else
        if sudo systemctl enable "mihomo@$USER" 2>/dev/null; then
            ok "开机自启设置成功"
        else
            warn "开机自启设置失败，请手动执行: sudo systemctl enable mihomo@\$USER"
        fi
    fi

    # 11. 生成 query.txt 信息文件
    info "生成查询信息文件..."
    generate_query_file "$MIXED_PORT" "$EXT_PORT" "$config_file"
    info "自动切换代理节点..."
    sleep 1  # 等待 API 就绪
    switch_global_proxy "$EXT_PORT" "mihomo"

    # 获取服务器 IP 用于显示
    local SERVER_IP=$(get_server_ip)

    # 12. 完成
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            部署完成!                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}▶ Web UI 地址:${NC}"
    echo "  本地访问: http://127.0.0.1:$EXT_PORT/ui/"
    echo "  远程访问: http://$SERVER_IP:$EXT_PORT/ui/"
    echo "  密钥: mihomo"
    echo ""
    echo -e "${BLUE}▶ 代理地址:${NC}"
    echo "  HTTP/SOCKS5: http://127.0.0.1:$MIXED_PORT"
    echo ""
    echo -e "${BLUE}▶ 配置文件:${NC}"
    echo "  用户配置: $USER_ENV_FILE"
    echo "  主配置: $config_file"
    echo "  查询信息: $CLASH_DIR/query.txt"
    echo ""
    echo -e "${BLUE}▶ 使用方法:${NC}"
    echo "  查看所有信息: cat $CLASH_DIR/query.txt"
    echo "  设置代理环境变量："
    echo "    export http_proxy=\"http://127.0.0.1:$MIXED_PORT\""
    echo "    export https_proxy=\"http://127.0.0.1:$MIXED_PORT\""
    echo ""
    echo "  验证代理："
    echo "    curl -x http://127.0.0.1:$MIXED_PORT https://www.google.com"
    echo ""
    echo "  更新订阅："
    echo "    $SCRIPT_DIR/update_subscription.sh"
    echo ""
}

main "$@"
