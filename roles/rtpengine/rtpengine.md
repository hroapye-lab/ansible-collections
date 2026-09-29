# Context Handoff: rtpengine 原生部署集成

## 当前状态
- **实现已完成并通过语法检查**（截至本次更新）。
- 用户已明确否定 Docker/Compose 方案；不要把 rtpengine 放进 Kamailio 的 compose。
- 目标是为 Kamailio HA 双机加入 **原生 apt 安装的 rtpengine + systemd**，并通过外部 Redis 做 session 状态同步，使 keepalived VIP 切换后通话尽量不中断。

### 已落盘的文件
- 新增 `incus/roles/rtpengine/`：`defaults/main.yml`、`tasks/main.yml`、
  `templates/rtpengine.conf.j2`、`handlers/main.yml`。
- `incus/playbooks/kamailio.yml`：roles 中在 `docker-compose` 前加入 `rtpengine`；
  `compose_vars.rtpengine_sock` 未设置/为空时默认本机
  `udp:127.0.0.1:2223`（Kamailio 容器为 host 网络，与本机 rtpengine 共享 loopback）。
- `incus/inventory/hosts.yml`：删除旧 `kamailio_rtpengine_sock: udp:10.159.105.235:2233`；
  新增 Redis 外部连接变量（`rtpengine_redis_host/port/password`）、Sipwise 源开关
  （`rtpengine_use_sipwise_repo: true`）及可选覆盖项注释。

### Sipwise 源安装（已实现并真实验证）
- role 支持 `rtpengine_use_sipwise_repo: true`：自动下载/安装 Sipwise 仓库 keyring、
  写入 `/etc/apt/sources.list.d/sipwise-rtpengine.list`、强制刷新 apt 索引、
  包名自动切换为 `ngcp-rtpengine-*`（预检/版本断言/安装均用动态包名）。
- 已在两台目标机（Debian 12 bookworm）真实执行验证：
  `ngcp-rtpengine-daemon 12.5.1.2+0~mr12.5.1.2` 安装成功，服务 active；
  配置正确渲染（VIP interface、各自 listen-ng）。
- 本次验证以 `rtpengine_kernel_mode: auto` 跑通（/proc/rtpengine 缺失时降级
  `table=-1`）；该模式现为 role 默认，部署不再因宿主机未加载模块而卡住；
  宿主机加载 `nft_rtpengine` / `xt_RTPENGINE` 后重跑即自动切回内核转发
  （`table=0`），无需改配置。
- 已修复两个运行时问题：
  1. `regex_search(..., '\\1')` 回引在 ansible-core 2.21 的 AnsibleLexer 反斜杠
     翻倍下崩溃（`'NoneType' has no attribute 'group'`），改用纯字符串解析
     `select('search','Candidate:') + split(':')`。
  2. 同名 `register` 变量在任务被 skip 后会被重置为空 dict（2.21 行为变化），
     内核接口状态改为独立变量 `rtpengine_proc_exists` 记录与覆盖。

### 已验证
- `ansible-playbook --syntax-check playbooks/kamailio.yml` 通过
  （需在 `incus/` 下执行，并设置 `ANSIBLE_LOCAL_TEMP=/tmp/ansible-local`、
  `ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote`）。
- 已在真实目标机完整执行 rtpengine role（Sipwise 源）并确认：
  keyring 安装、sources.list 写入、包安装（`12.5.1.2`）、systemd 服务 active。
- Redis HA 连接已在真实环境启用并验证：
  - 服务端 `notify-keyspace-events AKE` 已确认开启（CONFIG GET 返回 AKE）；
  - ka01 配置 `redis = 10.159.105.37:6379/2`、`subscribe-keyspace = 3`，
    ka02 配置 `redis = 10.159.105.37:6379/3`、`subscribe-keyspace = 2`；
  - rtpengine 日志确认 `Connected to Redis ... in master mode` 与
    `Use Redis ... to subscribe to notifications`，无连接错误。
- 在真实目标机（Debian 12 bookworm）用临时 playbook 验证候选版本解析：
  `apt-cache policy rtpengine-daemon` 输出
  `Candidate: 10.5.3.5-1+deb12u1`，解析表达式正确得到该版本号。
- Jinja2 双节点直渲验证：
  - ka01：`redis = 10.159.105.37:6379/2`、`subscribe-keyspace = 3`；
  - ka02：`redis = 10.159.105.37:6379/3`、`subscribe-keyspace = 2`；
  - 未设 sock 时回退 `udp:127.0.0.1:2223`；
    显式 sock 时保持外部值；Redis 密码渲染为 `pwd:s3cret@host:port/db`。
- `subscribe-keyspace` 分隔符已按官方文档核对：
  rtpengine 官方 man page / README 语法为
  `-k, --subscribe-keyspace=INT INT ...`（空格分隔的 keyspace 列表），
  模板使用空格分隔，不用分号。
- 内核转发模式逻辑：`required` 且 `/proc/rtpengine` 缺失时 fail，不静默降级；
  `auto`（默认）/`userspace` 降级 `table=-1`；role 不做 modprobe
  （容器内不能 DKMS，由宿主机手动加载模块）。
- 任务已精简：砍掉候选版本预检（apt-cache policy 解析）与 modprobe/复查链，
  只保留源安装、安装+版本断言、内核检查（stat→assert→转发表）、
  sysctl、配置、服务；幂等重跑验证全绿（ok=14, changed=0）。
- 部署/重启末尾会输出**实际转发模式提醒**：内核转发（table=0）或用户态
  （table=-1）；若为 auto 降级，会醒目提示宿主机加载模块后重跑即可切回。

## 用户确认的约束
1. **优先原生部署**：使用 apt 包和 systemd；利用内核模块转发优势。apt 版本过旧时应失败并提示换仓库/确认，不能默默改成 Docker。
2. **Redis 是外部服务**：只提供连接变量，不在本任务里部署 Redis。
3. **每个 Kamailio 节点各部署一个 rtpengine**：
   - 不直接绑定进 Kamailio compose；
   - Kamailio 若显式设置 `kamailio_rtpengine_sock`，使用外部值；
   - 若未设置或为空，默认使用本机 rtpengine：`udp:127.0.0.1:2223`。

## 当前环境要点
- 工作目录：`/root/ansible`
- 相关文件：
  - `incus/playbooks/kamailio.yml`
  - `incus/inventory/hosts.yml`
  - `incus/playbooks/templates/compose/kamailio/kamailio.cfg.j2`
  - `incus/roles/docker-compose/tasks/main.yml`
- Inventory 中 `containers` 组当前就是两个 Kamailio HA 节点：
  - `incus-ka01`: `10.159.105.92`, MASTER
  - `incus-ka02`: `10.159.105.45`, BACKUP
  - VIP: `10.159.105.200/24`
  - public advertise IP: `192.168.1.195`
- 当前 inventory 里有旧的：
  ```yaml
  kamailio_rtpengine_sock: udp:10.159.105.235:2233
  ```
  应删除或注释掉，改为可覆盖变量。

## 关键技术决策

### 部署方式
新增独立 role：

- `incus/roles/rtpengine/`
  - `defaults/main.yml`
  - `tasks/main.yml`
  - `templates/rtpengine.conf.j2`
  - `handlers/main.yml`

然后在 `incus/playbooks/kamailio.yml` 中调用：

```yaml
roles:
  - role: rtpengine
  - role: docker-compose
```

rtpengine role 需在 docker-compose 之前执行，确保 Kamailio 启动前本机 rtpengine 可用。

### 内核模块
- rtpengine 配置使用内核转发：
  - `/proc/rtpengine` 存在时使用 `table = 0`；
  - 不存在时默认（`auto`）降级用户态 `table = -1`；显式 `required` 才失败。
- 由于目标是 Incus 容器，**不能在容器里 DKMS 编译内核模块**：
  - role 只检查 `/proc/rtpengine`，不做 modprobe；
  - Incus 宿主机需要加载 `nft_rtpengine` / `xt_RTPENGINE`。
- 可用变量：
  ```yaml
  rtpengine_kernel_mode: auto        # auto（默认）| required | userspace
  rtpengine_kernel_table: 0
  ```

### apt 版本控制
- 默认要求 `rtpengine-daemon >= 10.5`（对齐 Debian bookworm 官方源；
  bookworm 安全修复版为 `10.5.3.5-1+deb12u1`，DLA-4691-1）。
- 本方案所需功能（NG 控制 + Redis keyspace HA）10.5 已全部支持；
  Ubuntu noble 11.5.x、Debian trixie 12.x 更新但非必需。
- 若版本过低且 `rtpengine_allow_old_apt: false`，role 应 fail，不自动切换部署方式。

### Redis HA 设计
- 两个 rtpengine 连接 **同一个 Redis 服务**，但使用不同 Redis DB，并互相订阅。
- 不要让两个 rtpengine 写同一个 DB；这符合 rtpengine 官方 Redis keyspace HA 模式。
- 示例：
  - ka01：`redis=<host>:6379/2`, `subscribe-keyspace=3`
  - ka02：`redis=<host>:6379/3`, `subscribe-keyspace=2`
- Redis 服务端必须开启：
  ```conf
  notify-keyspace-events AKE
  ```
- Redis 连接变量应由 inventory 提供，不在 role 中写死：
  ```yaml
  rtpengine_redis_host: "10.159.105.37"
  rtpengine_redis_port: 6379
  rtpengine_redis_password: ""
  ```

### Redis 启用配置（当前 inventory 已填真实连接）
**服务端（外部 Redis，需手动配置一次）**：
```bash
# 运行时立即生效（重启 Redis 前有效）
redis-cli -h 10.159.105.37 -p 6379 CONFIG SET notify-keyspace-events AKE

# 持久化：把运行时设置写回 redis.conf（或编辑 /etc/redis/redis.conf
# 加 notify-keyspace-events AKE 后重启 redis）
redis-cli -h 10.159.105.37 -p 6379 CONFIG REWRITE

# 验证
redis-cli -h 10.159.105.37 -p 6379 CONFIG GET notify-keyspace-events   # 返回 AKE
```

**Ansible 侧（已生效）**：`rtpengine_redis_host: 10.159.105.37`、
端口 6379、无密码（已实测 PING 可达）。重跑 playbook 后
`/etc/rtpengine/rtpengine.conf` 会生成：
- ka01：`redis = 10.159.105.37:6379/2`、`subscribe-keyspace = 3`
- ka02：`redis = 10.159.105.37:6379/3`、`subscribe-keyspace = 2`

DB 2/3 当前为空（已探测 DBSIZE=0），可安全分配；若 Redis 后续启用了密码，
填 `rtpengine_redis_password` 即可（渲染为 `pwd:<密码>@host:port/db`）。

## 建议变量结构

```yaml
---
# Kamailio 容器为 host 网络，与本机 rtpengine 共享 loopback；NG 控制口默认回环
rtpengine_listen_ip: "127.0.0.1"
rtpengine_listen_port: 2223
rtpengine_cli_port: 2224

rtpengine_media_ip: "{{ kamailio_keepalived_vip | default('', true) }}"
rtpengine_advertise_ip: "{{ kamailio_listen_public_ip | default(rtpengine_media_ip, true) }}"
rtpengine_interface_name: ka

rtpengine_kernel_mode: auto
rtpengine_kernel_table: 0

rtpengine_min_daemon_version: "10.5"
rtpengine_allow_old_apt: false

rtpengine_packages:
  - rtpengine-daemon
  - rtpengine-utils

rtpengine_service_name: ngcp-rtpengine-daemon
rtpengine_config_file: /etc/rtpengine/rtpengine.conf

rtpengine_port_min: 30000
rtpengine_port_max: 39999
rtpengine_timeout: 60
rtpengine_silent_timeout: 3600
rtpengine_final_timeout: 10800
rtpengine_delete_delay: 0

rtpengine_redis_host: ""
rtpengine_redis_port: 6379
rtpengine_redis_password: ""

rtpengine_redis_nodes: "{{ groups['containers'] | default([inventory_hostname]) }}"
rtpengine_redis_db_base: 2
rtpengine_redis_db: >-
  {{ rtpengine_redis_db_base + rtpengine_redis_nodes.index(inventory_hostname) }}

rtpengine_redis_subscribe_keyspaces: >-
  {{ rtpengine_redis_nodes
     | reject('equalto', inventory_hostname)
     | map('extract', hostvars, 'rtpengine_redis_db')
     | list
     | join(';') }}
```

## 配置模板核心

`/etc/rtpengine/rtpengine.conf` 应类似：

```ini
[rtpengine]
interface = {{ rtpengine_interface_name }}/{{ rtpengine_media_ip }}!{{ rtpengine_advertise_ip }}
listen-ng = {{ rtpengine_listen_ip }}:{{ rtpengine_listen_port }}
listen-cli = 127.0.0.1:{{ rtpengine_cli_port }}

port-min = {{ rtpengine_port_min }}
port-max = {{ rtpengine_port_max }}

timeout = {{ rtpengine_timeout }}
silent-timeout = {{ rtpengine_silent_timeout }}
final-timeout = {{ rtpengine_final_timeout }}
delete-delay = {{ rtpengine_delete_delay }}

redis = {{ rtpengine_redis_auth }}{{ rtpengine_redis_host }}:{{ rtpengine_redis_port }}/{{ rtpengine_redis_db }}
subscribe-keyspace = {{ rtpengine_redis_subscribe_keyspaces }}
redis-expires = 86400
redis-connect-timeout = 1000
```

若使用内核模式，配置中包含：

```ini
table = 0
```

若 userspace：

```ini
table = -1
```

不建议额外硬编码 `nftables-chain`，除非明确需要；rtpengine 默认会管理自己的规则。

## Kamailio 集成

`kamailio.yml` 中 `compose_vars.rtpengine_sock` 改为：

```yaml
rtpengine_sock: >-
  {{ kamailio_rtpengine_sock
     | default('udp:127.0.0.1:' ~ (kamailio_rtpengine_port | default(2223)), true) }}
```

要点：

- `default(..., true)` 很重要，否则空字符串不会回退到本机 rtpengine。
- 如果 inventory 仍保留旧的外部地址 `udp:10.159.105.235:2233`，会继续被使用；应删除或注释。

## 运行前检查清单
1. 目标机 apt 源中 `rtpengine-daemon` 候选版本需 >= 10.5
   （Debian bookworm 10.5.x、Ubuntu noble 11.5.x、Debian trixie 12.x 均可用）。
   版本不足时 role 会 fail 并提示，可显式 `rtpengine_allow_old_apt: true` 接受。

## bookworm 更新版 deb 来源（已核实）
- Debian 官方 `bookworm-backports`：**无** rtpengine 包（已核对官方 Packages 索引）。
- Sipwise 官方 apt 仓库 `https://deb.sipwise.com/spce/`（推荐，Webitel 生产文档同款用法）：
  - `mr11.5.1`：`ngcp-rtpengine-daemon 11.5.1.53`（bookworm ✓）
  - `mr12.5.1`：`ngcp-rtpengine-daemon 12.5.1.2`（bookworm ✓，推荐）
  - `mr13.x` / `mr14.x`：不支持 bookworm（需 trixie 及以上）
  - 依赖（libavcodec59 / libssl3 / libmariadb3 / libnftnl11 / liburing2 等）
    均可由 bookworm 主源满足；包内配置路径 `/etc/rtpengine/rtpengine.conf`、
    systemd 服务名 `ngcp-rtpengine-daemon` 与 role 默认一致。
  - 启用步骤：
    ```bash
    wget https://deb.sipwise.com/spce/keyring/ngcp-archive-keyring_mr12.5.1.deb
    dpkg -i ngcp-archive-keyring_mr12.5.1.deb
    echo "deb https://deb.sipwise.com/spce/mr12.5.1 bookworm main" \
      > /etc/apt/sources.list.d/sipwise-rtpengine.list
    apt update
    ```
  - 包名是 `ngcp-rtpengine-daemon`，inventory 覆盖：
    ```yaml
    rtpengine_packages:
      - ngcp-rtpengine-daemon
      # - ngcp-rtpengine-utils
    ```
- `kamailio.sipwise.com` 的 Jenkins 产物有标准命名 `rtpengine_11.5.1.34+bpo12`
  等 deb，但属 CI 产物页而非稳定 apt 源，不建议接入。

### Ubuntu PPA（已核实）
- 真实地址是 `https://ppa.launchpadcontent.net/davidlublink/rtpengine/ubuntu`；
  `ppa:davidlublink/rtpengine` 只是 `add-apt-repository` 的输入语法，直接写进
  sources.list 会被 apt 判为非法行（role 的旧默认值已按此修正）。
- 该 PPA 已发布的 suite 只有 `focal` / `jammy`（`jammy` 最后构建于 2023-12-12），
  包为 `ngcp-rtpengine-daemon 11.5.1.15+0~mr11.5.1.15+omnivigil1`，
  滞后于 Sipwise（`mr12.5.1` 已是 12.5.1.2）。另有一个
  `davidlublink/rtpengine-stable`，只有 focal/devel 且停在 2021，不建议使用。
- 签名公钥指纹 `24376EF97E6A3E3FAFD192836A7C036BF886C41B`（两个 PPA 同钥）。
  role 从 keyserver.ubuntu.com 取回 armored 公钥并 dearmor 到
  `/etc/apt/keyrings/davidlublink-rtpengine.gpg`，sources 行带 `[signed-by=...]`。
- 手工等价步骤：
  ```bash
  curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x24376EF97E6A3E3FAFD192836A7C036BF886C41B&options=mr" \
    | gpg --dearmor | sudo tee /etc/apt/keyrings/davidlublink-rtpengine.gpg >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/davidlublink-rtpengine.gpg] https://ppa.launchpadcontent.net/davidlublink/rtpengine/ubuntu jammy main" \
    | sudo tee /etc/apt/sources.list.d/rtpengine-3rd-repo.list
  apt update
  ```
2. 默认 `auto`：宿主机加载 `nft_rtpengine` / `xt_RTPENGINE` 后容器内出现
   `/proc/rtpengine`，自动使用内核转发（`table=0`）；未加载则降级用户态
   （`table=-1`）。容器内不能 DKMS（role 不做 modprobe）；
   如要求"缺失即失败"可显式设 `rtpengine_kernel_mode: required`。
3. 外部 Redis 需开启 `notify-keyspace-events AKE`，且 DB 2/3（或按
   `rtpengine_redis_db_base` 分配）可用；未就绪前保持
   `rtpengine_redis_host: ""` 即可不启用 Redis 同步。
4. 完整执行 playbook：
   ```bash
   cd /root/ansible/kamailio
   ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
     .venv/bin/ansible-playbook playbooks/kamailio.yml
   ```

## 重要提醒
- 不要重新引入 Docker/Compose 部署方案。
- 不要把 rtpengine service 加进 `files/compose/kamailio/compose.yaml`。
- 不要把两个 rtpengine 配成同一个 Redis DB；正确模式是同一 Redis 服务、不同 DB、互相订阅。
- 配置里包含 Redis 密码时，建议 `/etc/rtpengine/rtpengine.conf` 权限为 `0640 root:rtpengine`。
- Redis 外部服务需提前开启 `notify-keyspace-events AKE`。
