#!/usr/bin/env bash
# 多用户 Mihomo 配置初始化脚本

set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
source "$PROJECT_DIR/.env"

CLASH_DIR="${CLASH_USER_DIR/#\~/$HOME}"
RESOURCES_DIR="$CLASH_DIR/resources"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}! $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# 检测端口冲突并分配新端口
detect_port() {
    local port=$1
    if ss -tunl 2>/dev/null | grep -qs ":${port}\b"; then
        return 1  # 端口被占用
    fi
    return 0
}

get_random_port() {
    shuf -i 1024-65535 -n 1
}

# 主流程
main() {
    echo "=== Mihomo 多用户配置初始化 ==="
    echo ""

    # 创建目录结构
    ok "创建目录结构: $CLASH_DIR"
    mkdir -p "$RESOURCES_DIR/dist"

    # 复制 mixin.yaml
    if [ ! -f "$RESOURCES_DIR/mixin.yaml" ]; then
        ok "创建 mixin.yaml"
        cp "$PROJECT_DIR/resources/mixin.yaml" "$RESOURCES_DIR/mixin.yaml"

        # 检测端口冲突
        if ! detect_port $DEFAULT_MIXED_PORT; then
            local new_port=$(get_random_port)
            warn "端口 $DEFAULT_MIXED_PORT 被占用，随机分配: $new_port"
            sed -i "s/mixed-port: $DEFAULT_MIXED_PORT/mixed-port: $new_port/" "$RESOURCES_DIR/mixin.yaml"
        fi

        if ! detect_port $DEFAULT_EXTERNAL_PORT; then
            local new_port=$(get_random_port)
            warn "端口 $DEFAULT_EXTERNAL_PORT 被占用，随机分配: $new_port"
            sed -i "s/9090/$new_port/" "$RESOURCES_DIR/mixin.yaml"
        fi
    else
        warn "mixin.yaml 已存在，跳过"
    fi

    # 下载 Web UI
    if [ ! -f "$RESOURCES_DIR/dist/index.html" ]; then
        ok "下载 Web UI..."
        local tmp_zip="/tmp/dist-$$.zip"
        if wget -q "$URL_CLASH_UI" -O "$tmp_zip"; then
            unzip -q "$tmp_zip" -d "$RESOURCES_DIR/dist/"
            rm "$tmp_zip"
            ok "Web UI 下载完成"
        else
            fail "Web UI 下载失败，请检查网络"
        fi
    else
        warn "Web UI 已存在，跳过"
    fi

    # 创建空的配置文件
    touch "$RESOURCES_DIR/config.yaml"
    touch "$RESOURCES_DIR/runtime.yaml"

    echo ""
    ok "配置完成！"
    echo ""
    echo "下一步："
    echo "  1. 添加订阅: 编辑 $RESOURCES_DIR/config.yaml"
    echo "  2. 启动服务: sudo systemctl start mihomo@\$USER"
    echo ""
    echo "Web UI 访问地址："
    echo "  本地: http://127.0.0.1:9090/ui/"
    echo "  远程: http://<服务器IP>:9090/ui/"
}

main "$@"
