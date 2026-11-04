# hroapy.misc.wireguard

通用系统级 WireGuard peer 角色。角色只负责宿主机运行时、配置落盘和 systemd 服务，不负责
wg-portal API、peer 生命周期或防火墙规则。

## 要求

- systemd Linux
- root 或可用的 become 权限
- 运行内核提供 WireGuard 模块

标准包安装：

- Debian/Ubuntu：安装 `wireguard` 元包
- Fedora：安装 `wireguard-tools`
- Enterprise Linux：配置 EPEL 和 ELRepo，安装 `wireguard-tools` 与 `kmod-wireguard`
- SUSE/Arch：安装 `wireguard-tools`
- 其他系统族不在当前支持范围

## 最小配置

共享值和每主机私有值分开提供。共享值通常放在 group vars：

```yaml
wireguard_interface: wg0
wireguard_mtu: 1420
wireguard_persistent_keepalive: 25
wireguard_dns: []
```

每主机配置示例：

```yaml
wireguard_addresses:
  - 10.250.0.27/32
wireguard_private_key: !vault |
  <encrypted>

wireguard_peers:
  - public_key: <peer-public-key>
    endpoint: vpn.example.com:51820
    allowed_ips:
      - 10.250.0.0/24
    persistent_keepalive: 25
```

Peer 可选字段：

- `endpoint`
- `preshared_key`
- `persistent_keepalive`

## 行为

1. 按系统族安装标准 WireGuard 包。
2. 渲染 `/etc/wireguard/{{ wireguard_interface }}.conf`，权限 `0600`。
3. 模板写入前通过 `wg-quick strip` 校验配置。
4. 管理 `wg-quick@{{ wireguard_interface }}.service`。
5. 配置变化时重启服务，并验证接口存在。

Debian/Ubuntu 的 `wireguard` 元包负责模块依赖。其他系统要求运行内核提供
WireGuard 模块；role 不探测、不手动加载，也不安装宽泛内核包。模块缺失时
`wg-quick@` 启动自然失败。

角色不管理 `AllowedIPs` 的本机路由策略，也不会把 WireGuard 规则写入 iptables。防火墙应继续
由系统初始化角色或独立的防火墙角色负责。
