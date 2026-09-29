# rtpengine role（调用方说明）

原生部署 rtpengine，每 Kamailio HA 节点一个实例。安装方式用布尔开关：

- `rtpengine_source_build: false`（默认）：从系统仓库 / 第三方仓库安装；
- `rtpengine_source_build: true`：从上游 git 源码安装。
  源码内部再用 `rtpengine_dpkg_build` 切换：
  - `false`（默认，direct）：clone 后 make 直接编译 daemon + 内核模块；
  - `true`（dpkg）：clone 后走上游官方 debian/ 打包（`dpkg-buildpackage`），
    安装官方生成的 `ngcp-rtpengine-daemon / -utils / -kernel-dkms` deb。

内核模块策略统一由 `rtpengine_source_kernel_policy` 控制
（auto 默认 / always / never），且仅当 `rtpengine_kernel_mode != userspace` 时生效。
转发回退由 daemon 自身保证（已按 mr12.5.1.2 源码核实）：配置 `table = 0` 时，
内核模块不可用则自动按用户态继续运行，除非 `kernel_mode: required`
（此时配置 `no-fallback = true`，模块不可用 daemon 拒绝启动）。
role 不再预检 /proc、不再做加载尝试。
模块只在 source 模式处理：direct 按 policy 尝试/强制编译；dpkg 仅
`policy=always` 时安装官方 kernel-dkms deb。内核头按声明安装
（`rtpengine_kernel_headers_pkg`），版本匹配交给 apt 与编译工具，role 不查询内核版本。

## 变量表

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `rtpengine_source_build` | false | false=apt 仓库包；true=上游源码 |
| `rtpengine_dpkg_build` | false | 仅 source_build=true 生效：false=direct（直接 make）；true=dpkg（官方打包） |
| `rtpengine_source_kernel_policy` | auto | direct：auto=尝试编译失败不阻断，always=失败即 fail；dpkg：仅 always 安装 kernel-dkms deb；never=不装模块 |
| `rtpengine_kernel_headers_pkg` | "" | 按声明安装的内核头元包（Debian: linux-headers-amd64；Ubuntu: linux-headers-generic） |
| `rtpengine_kernel_mode` | auto | auto=table 0 + daemon 自动回退；required=table 0 + no-fallback；userspace=table -1 |
| `rtpengine_exact_version` | false | apt 版本策略：false=装仓库候选版本；true=钉 `rtpengine_target_version` |
| `rtpengine_target_version` | "" | apt exact 的目标完整版本号，如 `11.5.1.53+0~mr11.5.1.53` |
| `rtpengine_allow_downgrade` | false | apt exact 且目标低于已装版本时必须 true |
| `rtpengine_use_3rd_repo` | false | 是否配置第三方 apt 源（Sipwise / PPA 等） |
| `rtpengine_3rd_repo_mr` | mr11.5.1 | Debian/Sipwise 路径的 MR 版本，建议调用方显式钉住 |
| `rtpengine_3rd_repo_url` | Debian: `https://deb.sipwise.com/spce/<mr>`；Ubuntu: `https://ppa.launchpadcontent.net/davidlublink/rtpengine/ubuntu` | 第三方源地址。Ubuntu 必须是真实 https 地址（`ppa:user/name` 是 add-apt-repository 语法糖，写进 sources.list 会被 apt 判为非法行） |
| `rtpengine_3rd_repo_dist` | `ansible_facts['distribution_release']`（兜底 bookworm） | 写入 sources.list 的 suite/codename |
| `rtpengine_3rd_repo_keyring_url` | Debian: ngcp-archive-keyring deb；Ubuntu: "" | Debian 的密钥 deb 包；Ubuntu 走下面的 armored 公钥链路 |
| `rtpengine_3rd_repo_key_url` | Debian: ""；Ubuntu: keyserver.ubuntu.com 查询地址 | PPA armored 公钥下载地址 |
| `rtpengine_3rd_repo_keyring_path` | Debian: ""；Ubuntu: /etc/apt/keyrings/davidlublink-rtpengine.gpg | dearmor 后的 keyring 路径；非空会启用导入并让 sources 行带 `[signed-by=]` |
| `rtpengine_require_mr_match` | true | 安装后校验已装版本属于配置 MR |
| `rtpengine_packages` | [rtpengine-daemon, rtpengine-utils] | 软件包列表，按实际源覆盖（Sipwise/PPA 用 ngcp-rtpengine-*） |
| `rtpengine_kernel_packages` | [xtables-addons-dkms, xtables-addons-common] | 内核模块包（Sipwise/PPA 用 ngcp-rtpengine-kernel-dkms） |
| `rtpengine_source_repo` | sipwise/rtpengine | 源码仓库 |
| `rtpengine_source_ref` | mr12.5.1.2 | git tag/branch；换 MR 用对应 tag（如 mr11.5.1.53）并核对依赖 |
| `rtpengine_source_build_dir` | /usr/local/src/rtpengine | 源码检出/构建目录 |
| `rtpengine_source_install_dir` | /opt/rtpengine | direct 模式 daemon 安装目录 |
| `rtpengine_source_build_deps` | bookworm 依赖集 | direct 模式 daemon 编译依赖 |
| `rtpengine_source_pkg_tools` | 打包工具集 | dpkg 模式工具（mk-build-deps/dpkg-buildpackage 链路） |
| `rtpengine_source_build_profiles` | no-transcoding 等 | dpkg 模式传给构建的 DEB_BUILD_PROFILES |

`rtpengine_service_name` 自动取值：source+direct=`rtpengine-source`；其余跟随 daemon 包名。

## 行为矩阵

| 场景 | 结果 |
| --- | --- |
| apt，版本与配置 MR 一致 | no-op，断言通过 |
| apt，MR 更高 | 自动升级 |
| apt，MR 更低（默认） | 不降级，MR 断言 fail 并提示 exact_version+allow_downgrade |
| apt exact 降级 | 显式降级（需 allow_downgrade） |
| source+direct 首次 | 装依赖→make daemon→按 policy 编译/安装内核模块→启用 rtpengine-source |
| source+direct，auto | 尝试编译模块，失败不阻断（daemon 回退用户态） |
| source+direct，always | 安装声明内核头后编译，失败即 fail |
| source+dpkg 首次 | 装打包工具→mk-build-deps→dpkg-buildpackage→安装 daemon/utils deb（kernel-dkms deb 仅 always 安装） |
| source+dpkg 重复运行 | build-info 与已装版本一致时跳过打包 |
| userspace / never | 一律不编译、不安装内核模块 |
| 模块不可用 + kernel_mode=auto | daemon 自动回退用户态，服务保持 active |
| 模块不可用 + kernel_mode=required | daemon 带 no-fallback 启动失败 |
| direct ↔ dpkg 切换 | 自动停用并删除另一侧自定义 unit；deb 包侧需按提示手动卸载 |

## 调用方示例

apt + 第三方源（Sipwise，Debian 生产默认）：

```yaml
rtpengine_source_build: false
rtpengine_use_3rd_repo: true
rtpengine_3rd_repo_mr: mr12.5.1
rtpengine_packages:
  - ngcp-rtpengine-daemon
  - ngcp-rtpengine-utils
rtpengine_kernel_packages:
  - ngcp-rtpengine-kernel-dkms
  - ngcp-rtpengine-iptables
```

apt + 第三方源（Ubuntu PPA）：

```yaml
rtpengine_source_build: false
rtpengine_use_3rd_repo: true
rtpengine_3rd_repo_dist: "{{ ansible_facts['distribution_release'] }}"
# rtpengine_3rd_repo_url / _key_url / _keyring_path
# 默认已指向 Launchpad PPA（https://ppa.launchpadcontent.net/davidlublink/rtpengine/ubuntu），
# 密钥从 keyserver 取回并 dearmor 到 /etc/apt/keyrings，一般无需覆盖。
# 注意：该 PPA 只有 focal/jammy（jammy 最后构建 2023-12），别的 codename 会在 apt update 阶段报错。
rtpengine_packages:
  - ngcp-rtpengine-daemon
  - ngcp-rtpengine-utils
rtpengine_kernel_packages:
  - ngcp-rtpengine-kernel-dkms
  - ngcp-rtpengine-iptables
```

apt + 系统源（Debian bookworm 原生）：

```yaml
rtpengine_source_build: false
rtpengine_use_3rd_repo: false
# rtpengine_packages 和 rtpengine_kernel_packages 使用默认值
```

apt 显式降级（停机窗口操作）：

```yaml
rtpengine_exact_version: true
rtpengine_target_version: "11.5.1.53+0~mr11.5.1.53"
rtpengine_allow_downgrade: true
```

源码 direct（默认开关）：

```yaml
rtpengine_source_build: true
rtpengine_dpkg_build: false
rtpengine_source_ref: mr12.5.1.2
rtpengine_source_kernel_policy: always   # 或 auto/never
rtpengine_kernel_headers_pkg: linux-headers-amd64   # 可选（主机已装头可不设）
```

源码 dpkg（官方打包）：

```yaml
rtpengine_source_build: true
rtpengine_dpkg_build: true
rtpengine_source_ref: mr12.5.1.2
rtpengine_source_kernel_policy: always   # dpkg 仅 always 会装 kernel-dkms deb
rtpengine_kernel_headers_pkg: linux-headers-amd64
```

## 修改后的执行流程

统一前置（先语法检查、再单机预演）：

```bash
cd /root/ansible/kamailio
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
  /root/ansible/.venv/bin/ansible-playbook playbooks/kamailio.yml --syntax-check

ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
  /root/ansible/.venv/bin/ansible-playbook playbooks/kamailio.yml --limit <主机> --check --diff
```

流程 A（apt）：设置好包源/MR 变量后正式执行；结果按行为矩阵对号入座；
验证 `apt-cache policy <daemon包名>`、`dpkg -l | grep rtpengine`、
`systemctl status <daemon包名>`。

流程 B（source+direct）：设置 source/direct/ref/kernel_policy（auto 可同时声明
headers 元包以尽量成功编译）后正式执行；
验证 `cat /etc/rtpengine/build-info`（build_method=direct）、
`/opt/rtpengine/rtpengine --version`（或进程）、
`systemctl status rtpengine-source`；有内核头并编译模块时另验证
`ls /lib/modules/$(uname -r)/updates/xt_RTPENGINE.ko`（是否使用由 daemon 决定）。

流程 C（source+dpkg）：设置 source/dpkg/ref；policy=always 且主机缺头文件时
声明 `rtpengine_kernel_headers_pkg`，再正式执行（首次会安装较多 Build-Depends
并完整打包，耗时数分钟到更久）；验证
`cat /etc/rtpengine/build-info`（build_method=dpkg）、
`dpkg -l | grep ngcp-rtpengine`、`systemctl status ngcp-rtpengine-daemon`；
kernel-dkms 安装成功时 `dkms status` 应有对应模块。

三种流程完成后都要核对 daemon 日志 Redis connected、Kamailio `rtpengine_show`
正常并放通测试呼叫。切换安装方式前，先停用/卸载另一侧服务与产物
（见"其它行为说明"）。

## 其它行为说明

- direct 与 dpkg 切换：从 dpkg/apt 切到 direct 前，
  `systemctl disable --now <daemon包名>` 并 `dpkg -r <daemon包名>`
  （会提示是否保留配置文件）；从 direct 切走时 role 会自动停用并删除
  `rtpengine-source` 单元，残留 `/opt/rtpengine` 可手动删除。
- direct 模式产物不受 dpkg 管理；dpkg 模式产物受 dpkg 管理、与第三方源
  同名同版本时可直接覆盖，跨仓库/跨版本切换需显式处理，避免误降级。
- dpkg 模式会安装 Build-Depends（bookworm 下含 ffmpeg 开发包等，体积大），
  这是官方打包的正常开销；换 MR/发行版时按上游 debian/control 调整
  `rtpengine_source_build_profiles` 与工具清单。
- `allow_downgrade` 需要支持该参数的 ansible-core apt 模块
  （本项目 ansible-core 2.21 已支持）。
- 二选一参数均为布尔开关（`source_build` / `dpkg_build` / `exact_version`）；
  `kernel_mode`、`kernel_policy` 取值非法时按默认 auto 处理，不做断言。
- 内核头不做版本查询：按发行版声明元包（Debian `linux-headers-amd64`、
  Ubuntu `linux-headers-generic`），apt 自动跟随内核版本，编译工具负责匹配。
- `auto` 下模块不可用/编译失败不影响服务：daemon 直接以用户态运行；
  `required` 或 `policy=always` 才要求模块可用并显式失败。
