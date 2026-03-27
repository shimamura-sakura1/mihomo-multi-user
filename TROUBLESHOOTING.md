# Mihomo 多用户部署问题排查报告

## 部署时间线

总耗时：约 1 小时

## 遇到的问题

### 问题 1：端口冲突（最先发现，但影响最大）

**现象：**
- mihomo 的 `mixed-port: 7890` 不生效
- 运行时配置显示 `mixed-port: 0`

**原因：**
- 用户的 SSH 转发已占用 7890 端口
- mihomo 无法绑定已占用的端口，导致 mixed-port 功能失效

**解决方案：**
```yaml
mixed-port: 7890  # 改为未占用端口
```

**排查命令：**
```bash
ss -tunl | grep 7890
```

---

### 问题 2：DNS 解析失败（最耗时）

**现象：**
```
dns resolve failed: couldn't find ip
```

**原因：**
- mihomo 存在 [Bug #1422](https://github.com/MetaCubeX/mihomo/issues/1422)
- `proxy-server-nameserver` 配置不生效
- 节点域名无法被解析

**尝试过的方案：**
1. 添加 `proxy-server-nameserver` → 无效（bug）
2. 添加 `fake-ip-filter` → 无效
3. 修改 `enhanced-mode: redir-host` → 无效
4. 添加 `respect-rules: false` → 无效
5. 使用学校 DNS 服务器 → 无效
6. 添加 `nameserver-policy` → 部分生效
7. 使用 `system` DNS → 最终解决

**最终解决方案：**
```yaml
dns:
  proxy-server-nameserver:
    - system
  nameserver-policy:
    "+.example.com":
    - <your-school-dns>
    - 223.5.5.5
```

---

### 问题 3：网络权限不足

**现象：**
```
connect failed: dial tcp <node-ip>:<node-port>: operation not permitted
```

**原因：**
- systemd 服务缺少网络操作权限
- 默认服务模板未包含 `CapabilityBoundingSet`

**解决方案：**
```bash
sudo systemctl edit mihomo@.service
```
添加：
```ini
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
```

---

### 问题 4：流量未走代理

**现象：**
- 代理端口正常监听
- 但 curl 测试无响应

**原因：**
- GLOBAL 选择器默认为 DIRECT
- 流量直接出站，未经过代理节点

**解决方案：**
在 Web UI 中将 GLOBAL 切换到代理节点，或：
```bash
curl -X PUT "http://localhost:9090/proxies/GLOBAL" \
  -H "Authorization: Bearer mihomo" \
  -H "Content-Type: application/json" \
  -d '{"name":"♻️ 故障切换"}'
```

---

## 根本原因分析

### 为什么花费这么久？

1. **端口冲突未优先排查**
   - 一开始看到 7890 监听就以为 mihomo 正常
   - 没有检查该端口是否真的是 mihomo 进程

2. **mihomo DNS Bug 不熟悉**
   - `proxy-server-nameserver` 是已知 bug
   - 多次尝试配置修改，但未找到正确组合
   - 应该先查阅 GitHub Issues

3. **日志信息误导**
   - 初期 DNS 解析失败，但错误信息不够明确
   - 直到权限问题解决后才暴露真正原因

### 教训总结

1. **优先检查端口占用**
   ```bash
   ss -tunlp | grep <端口>
   ```

2. **查阅已知 Bug**
   - GitHub Issues 是重要资源
   - 遇到诡异问题先搜索

3. **逐项排查**
   - 网络 → DNS → 权限 → 配置
   - 不要同时修改多个配置项

---

## 正确的部署流程

### 1. 检查端口
```bash
ss -tunl | grep -E "7890|9090"
```

### 2. 修改配置
```yaml
mixed-port: 7890  # 避免冲突
external-controller: "0.0.0.0:9090"
```

### 3. 配置 DNS
```yaml
dns:
  proxy-server-nameserver:
    - system
  nameserver-policy:
    "+.<节点域名后缀>":
    - <本地DNS>
```

### 4. 添加服务权限
```bash
sudo systemctl edit mihomo@.service
# 添加 CapabilityBoundingSet
```

### 5. 重启服务
```bash
sudo systemctl daemon-reload
sudo systemctl restart mihomo@$USER
```

### 6. 切换代理节点
在 Web UI 中将 GLOBAL 从 DIRECT 切换到代理节点

### 7. 验证
```bash
curl -x http://127.0.0.1:7890 https://www.google.com
```
