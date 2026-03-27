#!/bin/bash
#
# Mihomo 订阅更新脚本 - 适用于定时任务 (cron)
# 功能: 自动下载订阅、保留端口设置、热重载配置
#

set -e

# 自动获取当前用户
USER="${SUDO_USER:-$USER}"
if [ "$USER" = "root" ] && [ -n "$HOME" ]; then
    USER=$(basename "$HOME")
fi

CONFIG_DIR="/home/$USER/.config/clash"
ENV_FILE="$CONFIG_DIR/.env"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
TEMP_FILE="/tmp/mihomo_update_${USER}_$$.yaml"
LOG_FILE="$CONFIG_DIR/update.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查环境
if [ ! -f "$ENV_FILE" ]; then
    log "ERROR: 未找到 .env 文件: $ENV_FILE"
    exit 1
fi

# 从 .env 读取配置
SUB_URL=$(grep "^SUB_URL=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
MIXED_PORT=$(grep "^MIXED_PORT=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "7890")
EXT_PORT=$(grep "^EXTERNAL_PORT=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "9090")
SECRET=$(grep "^SECRET=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "mihomo")

if [ -z "$SUB_URL" ]; then
    log "ERROR: 未找到 SUB_URL 配置"
    exit 1
fi

log "开始更新订阅..."

# 下载订阅
if ! curl -fsSL --connect-timeout 30 --max-time 60 "$SUB_URL" -o "$TEMP_FILE" 2>/dev/null; then
    log "ERROR: 订阅下载失败"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 验证下载内容
if [ ! -s "$TEMP_FILE" ]; then
    log "ERROR: 下载内容为空"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 强制替换端口设置（保留用户配置）
sed -i "s/^mixed-port:.*/mixed-port: $MIXED_PORT/" "$TEMP_FILE"
sed -i "s/^external-controller:.*/external-controller: 0.0.0.0:$EXT_PORT/" "$TEMP_FILE"
sed -i "s/^secret:.*/secret: \"$SECRET\"/" "$TEMP_FILE"
sed -i "s|^external-ui:.*|external-ui: $CONFIG_DIR/resources/dist|" "$TEMP_FILE"

# 应用配置
mv "$TEMP_FILE" "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"

# 热重载配置
if curl -s -X PUT "http://127.0.0.1:$EXT_PORT/configs" \
    -H "Authorization: Bearer $SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"path\":\"$CONFIG_FILE\"}" >/dev/null 2>&1; then
    log "SUCCESS: 订阅更新完成，配置已热重载"
else
    log "WARN: 热重载失败，尝试重启服务..."
    if sudo systemctl restart "mihomo@$USER" 2>/dev/null; then
        log "SUCCESS: 服务已重启"
    else
        log "ERROR: 服务重启失败"
        exit 1
    fi
fi

exit 0
