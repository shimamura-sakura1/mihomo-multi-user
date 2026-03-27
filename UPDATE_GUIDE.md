# Mihomo 订阅更新使用指南

## 脚本说明

`update_subscription.sh` - 极简订阅更新脚本，适用于定时任务 (cron)

**功能**:
- 自动下载订阅配置
- 强制保留本地端口设置（不随订阅变化）
- 热重载配置（无需重启服务）
- 自动获取当前用户
- 日志记录

## 使用方法

### 1. 手动更新

```bash
# 直接运行
~/mihomo-multi-user/update_subscription.sh

# 输出示例:
# [2026-03-27 17:30:01] 开始更新订阅...
# [2026-03-27 17:30:02] SUCCESS: 订阅更新完成，配置已热重载
```

### 2. 设置定时自动更新

#### 添加 cron 任务

```bash
crontab -e
```

#### 推荐配置

```bash
# 每天凌晨 3 点自动更新
0 3 * * * /home/lzy_2/mihomo-multi-user/update_subscription.sh

# 或者每 6 小时更新一次
0 */6 * * * /home/lzy_2/mihomo-multi-user/update_subscription.sh

# 或者每天凌晨 3 点，并将日志保存到独立文件
0 3 * * * /home/lzy_2/mihomo-multi-user/update_subscription.sh >> /tmp/mihomo_cron.log 2>&1
```

#### 查看定时任务

```bash
crontab -l
```

### 3. 查看更新日志

```bash
# 查看最新日志
tail ~/.config/clash/update.log

# 实时查看
tail -f ~/.config/clash/update.log

# 查看所有历史日志
cat ~/.config/clash/update.log
```

### 4. 测试更新是否成功

```bash
# 检查服务状态
systemctl status mihomo@$USER

# 查看节点列表（通过 API）
curl -s http://127.0.0.1:39841/proxies \
  -H "Authorization: Bearer mihomo" | jq '.proxies | keys'

# 或者直接打开 zashboard 查看节点
```

## 配置说明

脚本从 `~/.config/clash/.env` 读取以下配置：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `SUB_URL` | 订阅链接 | 必填 |
| `MIXED_PORT` | 代理端口 | 7890 |
| `EXTERNAL_PORT` | Web UI 端口 | 9090 |
| `SECRET` | API 密钥 | mihomo |

**修改订阅链接**:
```bash
# 编辑 .env 文件
vim ~/.config/clash/.env

# 修改 SUB_URL 行
SUB_URL=https://your-new-sub-url/clash
```

## 工作原理

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  下载订阅    │────▶│  替换端口设置 │────▶│  热重载配置  │
│  (curl)     │     │  (sed)       │     │  (API)      │
└─────────────┘     └──────────────┘     └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  服务不中断  │
                                        │  节点已更新  │
                                        └─────────────┘
```

## 常见问题

### Q: 更新后端口变了怎么办？
**A**: 脚本会自动强制替换为 .env 中配置的端口，无需担心。

### Q: 热重载失败会怎样？
**A**: 脚本会自动尝试重启服务，如果重启也失败会记录错误日志。

### Q: 如何手动恢复备份？
```bash
# 列出备份
ls -la ~/.config/clash/config.yaml.backup.* 2>/dev/null || echo "无备份"

# 恢复最近的备份
mv ~/.config/clash/config.yaml.backup.XXXX ~/.config/clash/config.yaml
sudo systemctl restart mihomo@$USER
```

### Q: cron 任务没有执行？
```bash
# 检查 cron 服务状态
sudo systemctl status cron

# 查看 cron 日志
grep CRON /var/log/syslog | tail -20

# 确保脚本有执行权限
chmod +x ~/mihomo-multi-user/update_subscription.sh
```

### Q: 如何立即强制更新？
```bash
~/mihomo-multi-user/update_subscription.sh
```

## 相关命令

```bash
# 查看服务状态
systemctl status mihomo@$USER

# 查看实时日志
journalctl -u mihomo@$USER -f

# 重启服务
sudo systemctl restart mihomo@$USER

# 停止服务
sudo systemctl stop mihomo@$USER
```
