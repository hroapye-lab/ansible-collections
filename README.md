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
| `hroapy.misc.compose` | 部署 Docker Compose 应用 |
| `hroapy.misc.acme_cert` | ACME（HTTP-01）签发证书 |
| `hroapy.misc.rtpengine` | 安装 / 配置 rtpengine |

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
