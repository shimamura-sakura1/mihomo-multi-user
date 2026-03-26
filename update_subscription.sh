#!/usr/bin/env bash
#
# Mihomo 订阅自动更新脚本
# 支持多用户配置，自动备份、更新、重启服务
#
# 使用方法:
#   ./update_subscription.sh                    # 交互式更新
#   ./update_subscription.sh --auto             # 自动模式（用于定时任务）
#   ./update_subscription.sh --user username    # 指定用户更新
#

set -e

# ==================== 配置 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
LOG_FILE="$SCRIPT_DIR/logs/update.log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}! $1${NC}"; }
info() { echo -e "${BLUE}→ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo -e "$msg"
}

# ==================== 工具函数 ====================

# 初始化目录
init_dirs() {
    mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"
}

# 下载文件
download() {
    local url=$1
    local output=$2
    local timeout=${3:-60}

    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout "$timeout" --max-time "$((timeout * 2))" "$url" -o "$output" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -q --timeout="$timeout" "$url" -O "$output" 2>/dev/null
    else
        return 1
    fi
}

# 验证配置文件
validate_config() {
    local config_file=$1

    # 检查文件是否存在且非空
    if [[ ! -f "$config_file" ]] || [[ ! -s "$config_file" ]]; then
        return 1
    fi

    # 检查是否为有效的 YAML
    if command -v python3 &>/dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null || return 1
    fi

    # 检查必需的字段
    if ! grep -qE "^(proxies|proxy-providers):" "$config_file" 2>/dev/null; then
        return 1
    fi

    return 0
}

# 备份配置
backup_config() {
    local config_file=$1
    local user=$2

    if [[ -f "$config_file" ]]; then
        local backup_name="config_${user}_$(date +%Y%m%d_%H%M%S).yaml"
        cp "$config_file" "$BACKUP_DIR/$backup_name"
        log "已备份配置: $backup_name"

        # 只保留最近 10 个备份
        ls -t "$BACKUP_DIR"/config_${user}_*.yaml 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    fi
}

# 从用户 .env 文件读取配置
load_user_env() {
    local user=$1
    local user_dir="/home/$user/.config/clash"
    local env_file="$user_dir/.env"

    # 声明全局变量
    USER_MIXED_PORT=""
    USER_EXTERNAL_PORT=""
    USER_SECRET=""
    USER_SUB_URL=""
    USER_NODE_DOMAIN=""

    if [[ -f "$env_file" ]]; then
        # 读取配置
        USER_MIXED_PORT=$(grep "^MIXED_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        USER_EXTERNAL_PORT=$(grep "^EXTERNAL_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        USER_SECRET=$(grep "^SECRET=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        USER_SUB_URL=$(grep "^SUB_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
        USER_NODE_DOMAIN=$(grep "^NODE_DOMAIN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        return 0
    fi
    return 1
}

# 获取订阅链接（多种来源）
get_subscription_url() {
    local user=$1
    local user_dir="/home/$user/.config/clash"

    # 1. 优先从用户 .env 读取
    if [[ -n "$USER_SUB_URL" ]]; then
        echo "$USER_SUB_URL"
        return 0
    fi

    # 2. 检查项目目录的 .env.local 中的 SUB_URL_用户名
    local env_local="$SCRIPT_DIR/.env.local"
    if [[ -f "$env_local" ]]; then
        local url=$(grep "^SUB_URL_${user^^}=" "$env_local" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
        [[ -n "$url" ]] && echo "$url" && return 0
    fi

    # 3. 检查项目目录的 .env 中的订阅链接
    local env_file="$SCRIPT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        local url=$(grep "^SUB_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
        [[ -n "$url" ]] && echo "$url" && return 0
    fi

    # 4. 检查 profiles.yaml
    local profiles_file="$user_dir/resources/profiles.yaml"
    if [[ -f "$profiles_file" ]]; then
        local url=$(grep -E "^\s*url:" "$profiles_file" 2>/dev/null | head -1 | awk '{print $2}')
        [[ -n "$url" ]] && echo "$url" && return 0
    fi

    return 1
}

# 提取节点域名后缀
extract_node_domain() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        local domain=$(grep -m1 "server:" "$config_file" 2>/dev/null | awk '{print $2}' | grep -oE '\.[^.]+\.[^.]+$' | sed 's/^\.//')
        if [ -n "$domain" ]; then
            echo "$domain"
            return 0
        fi
    fi
    echo ""
}

# 更新订阅
update_subscription() {
    local user=$1
    local auto_mode=$2
    local user_dir="/home/$user/.config/clash"
    local config_file="$user_dir/config.yaml"
    local temp_config="/tmp/mihomo_config_${user}_$$.yaml"

    log "开始更新用户 $user 的订阅..."

    # 加载用户配置
    if ! load_user_env "$user"; then
        warn "未找到用户配置文件: $user_dir/.env"
    fi

    # 获取订阅链接
    local sub_url
    sub_url=$(get_subscription_url "$user")
    if [ -z "$sub_url" ]; then
        fail "无法找到用户 $user 的订阅链接"
        return 1
    fi

    info "订阅链接: ${sub_url:0:50}..."

    # 下载新配置
    info "下载订阅配置..."
    if ! download "$sub_url" "$temp_config" 60; then
        rm -f "$temp_config"
        fail "订阅下载失败"
        return 1
    fi

    # 验证配置
    info "验证配置..."
    if ! validate_config "$temp_config"; then
        rm -f "$temp_config"
        fail "下载的配置文件无效"
        return 1
    fi

    # 备份旧配置
    backup_config "$config_file" "$user"

    # 获取端口配置（优先使用 .env 中的配置）
    local mixed_port="${USER_MIXED_PORT:-7890}"
    local ext_port="${USER_EXTERNAL_PORT:-9090}"
    local secret="${USER_SECRET:-mihomo}"

    # 如果 .env 中没有端口配置，从旧配置文件提取
    if [[ -z "$USER_MIXED_PORT" ]] && [[ -f "$config_file" ]]; then
        mixed_port=$(grep "^mixed-port:" "$config_file" 2>/dev/null | awk '{print $2}' || echo "7890")
        ext_port=$(grep "external-controller:" "$config_file" 2>/dev/null | sed 's/.*://' | tr -d ' ' || echo "9090")
        secret=$(grep "^secret:" "$config_file" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "mihomo")
    fi

    # 提取节点域名
    local new_node_domain=$(extract_node_domain "$temp_config")
    if [ -z "$new_node_domain" ]; then
        new_node_domain="${USER_NODE_DOMAIN:-}"
    fi

    # 修改新配置的端口
    sed -i "s/mixed-port: [0-9][0-9]*/mixed-port: $mixed_port/" "$temp_config"
    sed -i "s|external-controller: [^ ]*|external-controller: 0.0.0.0:$ext_port|" "$temp_config"

    # 添加或更新 secret
    if ! grep -q "^secret:" "$temp_config"; then
        sed -i "/^external-controller:/a secret: \"$secret\"" "$temp_config"
    else
        sed -i "s/^secret:.*/secret: \"$secret\"/" "$temp_config"
    fi

    # 添加 external-ui
    local res_dir="$user_dir/resources"
    if ! grep -q "^external-ui:" "$temp_config"; then
        sed -i "/^external-controller:/a external-ui: $res_dir/dist" "$temp_config"
    else
        sed -i "s|^external-ui:.*|external-ui: $res_dir/dist|" "$temp_config"
    fi

    # 添加 DNS 配置（修复 mihomo bug #1422）
    if ! grep -q "^dns:" "$temp_config"; then
        cat >> "$temp_config" <<EOF

dns:
  enable: true
  respect-rules: false
  listen: 0.0.0.0:1053
  default-nameserver:
    - 223.5.5.5
  proxy-server-nameserver:
    - system
  enhanced-mode: redir-host
EOF
    fi

    # 添加 nameserver-policy（如果有节点域名且不存在）
    if [ -n "$new_node_domain" ] && ! grep -q "nameserver-policy:" "$temp_config"; then
        # 使用 awk 在 dns 块中添加 nameserver-policy
        awk -v domain="$new_node_domain" '
            /^dns:/ { in_dns=1 }
            in_dns && /^enhanced-mode:/ {
                print
                print "  nameserver-policy:"
                print "    \"+." domain "\":"
                print "      - 223.5.5.5"
                next
            }
            { print }
        ' "$temp_config" > "$temp_config.tmp" && mv "$temp_config.tmp" "$temp_config"
    fi

    # 应用新配置
    mv "$temp_config" "$config_file"
    chown "$user:$user" "$config_file" 2>/dev/null || true
    chmod 644 "$config_file"

    # 更新用户 .env 中的节点域名
    if [ -n "$new_node_domain" ] && [ -f "$user_dir/.env" ]; then
        if grep -q "^NODE_DOMAIN=" "$user_dir/.env"; then
            sed -i "s|^NODE_DOMAIN=.*|NODE_DOMAIN=$new_node_domain|" "$user_dir/.env"
        else
            echo "NODE_DOMAIN=$new_node_domain" >> "$user_dir/.env"
        fi
    fi

    ok "配置更新成功"

    # 重启服务
    info "重启 mihomo@$user 服务..."
    if sudo systemctl restart "mihomo@$user" 2>/dev/null; then
        sleep 2
        if systemctl is-active --quiet "mihomo@$user" 2>/dev/null; then
            ok "服务重启成功"
        else
            warn "服务可能未正常启动，请检查日志: journalctl -u mihomo@$user -n 50"
        fi
    else
        warn "服务重启失败，请手动重启: sudo systemctl restart mihomo@$user"
    fi

    # 自动切换 GLOBAL（非自动模式下）
    if [[ "$auto_mode" != "true" ]]; then
        sleep 1
        auto_switch_global "$ext_port" "$secret"
    fi

    log "用户 $user 订阅更新完成"
    return 0
}

# 自动切换 GLOBAL 到代理节点
auto_switch_global() {
    local ext_port=$1
    local secret=$2
    local api_url="http://localhost:${ext_port}"

    info "尝试自动切换 GLOBAL..."

    # 获取可用代理组
    local proxy_groups
    proxy_groups=$(curl -s -H "Authorization: Bearer $secret" "${api_url}/proxies" 2>/dev/null) || {
        warn "无法连接到 API"
        return 1
    }

    # 查找合适的代理组
    local target_group=""
    for group in "♻️ 故障切换" "🚀 节点选择" "🚀 手动切换" "Proxy" "自动选择"; do
        if echo "$proxy_groups" | grep -q "\"$group\""; then
            target_group="$group"
            break
        fi
    done

    if [[ -z "$target_group" ]]; then
        warn "未找到合适的代理组，请手动在 UI 中切换"
        return 1
    fi

    # 切换 GLOBAL
    local result
    result=$(curl -s -X PUT "${api_url}/proxies/GLOBAL" \
        -H "Authorization: Bearer $secret" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$target_group\"}" 2>/dev/null)

    ok "GLOBAL 已切换到: $target_group"
    return 0
}

# 获取所有配置过的用户
get_configured_users() {
    local users=()

    # 1. 从用户目录获取（检查 ~/.config/clash/.env）
    for user_dir in /home/*/.config/clash; do
        if [[ -d "$user_dir" ]] && [[ -f "$user_dir/.env" ]]; then
            local user=$(basename "$(dirname "$user_dir")")
            users+=("$user")
        fi
    done

    # 2. 从 systemd 服务状态获取活跃的用户
    while IFS= read -r service; do
        if [[ "$service" =~ mihomo@(.+)\.service ]]; then
            local user="${BASH_REMATCH[1]}"
            [[ ! " ${users[@]} " =~ " $user " ]] && users+=("$user")
        fi
    done < <(systemctl list-units --type=service --state=running 2>/dev/null | grep -oP 'mihomo@\K[^.]+' || true)

    # 去重并输出
    printf '%s\n' "${users[@]}" | sort -u
}

# 显示状态
show_status() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Mihomo 订阅更新状态             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    local users=($(get_configured_users))

    if [[ ${#users[@]} -eq 0 ]]; then
        warn "未找到配置的用户"
        return 1
    fi

    for user in "${users[@]}"; do
        local user_dir="/home/$user/.config/clash"
        local config_file="$user_dir/config.yaml"
        local env_file="$user_dir/.env"
        local service_status="未运行"

        if systemctl is-active --quiet "mihomo@$user" 2>/dev/null; then
            service_status="${GREEN}运行中${NC}"
        elif systemctl is-failed --quiet "mihomo@$user" 2>/dev/null; then
            service_status="${RED}失败${NC}"
        fi

        local config_time=""
        if [[ -f "$config_file" ]]; then
            config_time=$(stat -c %y "$config_file" 2>/dev/null | cut -d'.' -f1)
        fi

        # 读取端口信息
        local mixed_port="?"
        local ext_port="?"
        if [[ -f "$env_file" ]]; then
            mixed_port=$(grep "^MIXED_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "?")
            ext_port=$(grep "^EXTERNAL_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "?")
        fi

        echo -e "用户: ${BLUE}$user${NC}"
        echo -e "  服务状态: $service_status"
        echo -e "  代理端口: $mixed_port"
        echo -e "  控制台端口: $ext_port"
        echo -e "  配置时间: ${config_time:-未找到}"
        echo ""
    done
}

# ==================== 主流程 ====================

main() {
    local auto_mode="false"
    local target_user=""
    local show_status_only="false"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                auto_mode="true"
                shift
                ;;
            --user)
                target_user="$2"
                shift 2
                ;;
            --status)
                show_status_only="true"
                shift
                ;;
            --help|-h)
                echo "Mihomo 订阅自动更新脚本"
                echo ""
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --auto          自动模式（无交互，适合定时任务）"
                echo "  --user USER     指定用户更新"
                echo "  --status        显示状态"
                echo "  --help          显示帮助"
                echo ""
                echo "配置订阅链接:"
                echo "  在部署时会自动保存到 ~/.config/clash/.env"
                echo "  或手动编辑: ~/.config/clash/.env 中的 SUB_URL"
                echo ""
                exit 0
                ;;
            *)
                warn "未知参数: $1"
                shift
                ;;
        esac
    done

    # 初始化
    init_dirs

    # 显示状态
    if [[ "$show_status_only" == "true" ]]; then
        show_status
        exit 0
    fi

    # 确定要更新的用户
    local users=()
    if [[ -n "$target_user" ]]; then
        users=("$target_user")
    else
        mapfile -t users < <(get_configured_users)
    fi

    if [[ ${#users[@]} -eq 0 ]]; then
        fail "未找到配置的用户"
        exit 1
    fi

    # 执行更新
    local success=0
    local failed=0

    for user in "${users[@]}"; do
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        log "处理用户: $user"

        if update_subscription "$user" "$auto_mode"; then
            ((success++))
        else
            ((failed++))
        fi
    done

    # 总结
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            更新完成                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    ok "成功: $success"
    [[ $failed -gt 0 ]] && fail "失败: $failed"

    exit $((failed > 0 ? 1 : 0))
}

main "$@"
