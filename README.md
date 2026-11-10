# hroapy.misc

整合 `/root/ansible` 下 `incus` / `init` / `kamailio` 等项目零散 role 的共享集合。

- collection 为唯一真源（方案 A）：role 的后续维护都在本目录进行。

## 角色

| FQCN | 说明 |
| --- | --- |
| `hroapy.misc.docker` | 配置 apt 源并安装 Docker |
| `hroapy.misc.ssh` | 分发 SSH 公钥 |
| `hroapy.misc.zed` | 分发 Zed remote server |
| `hroapy.misc.init` | 主机基础初始化（包 / 主机名 / iptables / 磁盘 / 内核） |
| `hroapy.misc.deploy_compose` | 部署 Docker Compose 应用（源为本地路径或压缩包 URL，模板按 profile 选） |
| `hroapy.misc.git_sync` | 拉取 git 指定 ref 的某个子目录，同步到目的目录 |
| `hroapy.misc.acme_cert` | ACME（HTTP-01）签发证书 |
| `hroapy.misc.rtpengine` | 安装 / 配置 rtpengine |
| `hroapy.misc.wireguard` | 安装、配置并管理 systemd WireGuard peer |

## Compose XML 修改

`hroapy.misc.deploy_compose` 支持用 `compose_xml_patches` 按 XPath 修改 XML。路径相对于 `compose_dir`：

```yaml
compose_xml_patches:
  - path: app/conf/logfile.conf.xml
    xpath: /configuration/settings/param[@name='rollover']
    attribute: value
    value: "104857600"
```

支持 `state: present|absent` 和 `create_if_missing`，默认不创建不存在的节点；目标文件不存在时跳过该项。目标机需要安装 `lxml`，Debian/Ubuntu 对应 `python3-lxml`。

## Compose 构建与仅输出文件

`hroapy.misc.deploy_compose` 默认沿用现有部署流程。以下变量可按需覆盖：

```yaml
# 启动前强制执行 docker compose build
compose_force_build: true

# 只推送并生成项目文件，不进入 up/restart 阶段
compose_skip_up: true
```

## 分发与安装

以 git 仓库分发，消费方不直接读取本地文件。

消费方 `requirements.yml`：

```yaml
collections:
  - name: <git-url>
    type: git
    version: v1.0.0
```

自测：把集合装到运行 ansible 的环境的集合路径，用该环境验证：

```bash
ansible-galaxy collection install <collection-dir>
ansible-playbook --syntax-check <smoke.yml>
```
