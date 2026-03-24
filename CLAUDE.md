# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mihomo multi-user deployment toolkit for Linux. Uses systemd template service (`mihomo@.service`) to allow each user to run their own mihomo instance with isolated configuration.

## Service Template Pattern

`/etc/systemd/system/mihomo@.service` uses `%i` placeholder for username:
- Config directory: `/home/%i/.config/clash`
- Binary: `/usr/bin/mihomo` (system-installed)

**Required capabilities for TUN mode:**
```ini
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
```

## Directory Structure

**User config (after deployment):**
```
~/.config/clash/
├── config.yaml        # Subscription config
├── resources/dist/    # Web UI (zashboard)
```

## Critical Configuration Patterns

### DNS Configuration (fixes mihomo bug #1422)
```yaml
dns:
  enable: true
  respect-rules: false
  proxy-server-nameserver:
    - system
  nameserver-policy:
    "+.<node-domain-suffix>":
      - 223.5.5.5
```

Without this, node domain resolution fails with "couldn't find ip".

### Port Allocation
- Default ports (7890/9090) often conflict with SSH tunnels
- deploy.sh auto-allocates from 10000-60000 range if defaults are taken
- Check with: `ss -tunl | grep -E "7890|9090"`

## Common Commands

### Service Management
```bash
sudo systemctl start mihomo@$USER
sudo systemctl stop mihomo@$USER
sudo systemctl restart mihomo@$USER
systemctl status mihomo@$USER
journalctl -u mihomo@$USER -f
```

### Deployment
```bash
# One-click with subscription
./deploy.sh --sub "subscription-url"

# With proxy environment variables
SET_PROXY=y ./deploy.sh --sub "subscription-url"
```

### Testing
```bash
# Test proxy connectivity
curl -x http://127.0.0.1:<mixed-port> https://www.google.com

# Check external IP
curl -x http://127.0.0.1:<mixed-port> https://ipinfo.io/json
```

### Web UI Access
- Local: `http://127.0.0.1:<ext-port>/ui/`
- Remote: `http://<server-ip>:<ext-port>/ui/`
- Secret: `mihomo`

> Note: Trailing `/` is required in the URL.

### Switch Proxy Node
GLOBAL selector defaults to DIRECT. Switch via API:
```bash
curl -X PUT "http://localhost:<ext-port>/proxies/GLOBAL" \
  -H "Authorization: Bearer mihomo" \
  -H "Content-Type: application/json" \
  -d '{"name":"<proxy-group-name>"}'
```

## Known Issues

1. **DNS Resolution Failure**: mihomo bug #1422 - `proxy-server-nameserver` doesn't work. Must use `system` and `nameserver-policy`.

2. **Port Conflicts**: SSH tunnels often occupy 7890. Use deploy.sh auto-allocation or alternative ports (7890, 9090).

3. **Operation Not Permitted**: Missing capability bounding set in service template.

4. **Traffic Not Routing**: GLOBAL selector defaults to DIRECT - must manually switch to proxy node after deployment.
