# git_sync

拉取 git 仓库**指定 ref** 的**某个子目录**，同步到**目的目录**。

- **只做"取素材 + 落盘"**：不启动服务、不渲染模板，落盘后要做什么由调用方决定
  （例如交给 `hroapy.misc.deploy_compose` 起容器）。
- **克隆在控制机**：目标机不需要装 git，也不需要能访问仓库；控制机按
  `repo#ref` 缓存检出结果，同一键复用。
- **目录 = 仓库里的子目录**：`git_sync_subdir` 指定，留空则同步整个仓库根。

## 流程

| # | 步骤 | 在哪 | 说明 |
| --- | --- | --- | --- |
| 1 | 校验 `git_sync_repo` / `git_sync_dest` | – | 缺失直接报错 |
| 2 | 解析缓存目录 | – | `{{ git_sync_cache_dir }}/sha1(repo#ref)` |
| 3 | 克隆/检出指定 ref | 控制机 | `ansible.builtin.git`，`depth` 由 `git_sync_depth` 控制 |
| 4 | 校验子目录存在 | 控制机 | 不存在时报错并提示 ref 与子目录名 |
| 5 | 推送到目的目录 | 目标机 | `copy`（默认）或 `sync` |

## 变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `git_sync_repo` | `''` | **必填**，仓库地址（https / ssh） |
| `git_sync_dest` | `''` | **必填**，目标机上的目的目录，不存在时创建 |
| `git_sync_ref` | `''` | 分支 / tag / commit sha；留空 = 远程默认分支 |
| `git_sync_subdir` | `''` | 仓库内子目录（可多级）；留空 = 仓库根 |
| `git_sync_depth` | `1` | 浅克隆深度；`0` = 全量克隆 |
| `git_sync_key_file` | `''` | ssh 私钥在控制机的路径（留空用 ssh-agent / 默认密钥） |
| `git_sync_accept_hostkey` | `false` | ssh 是否自动接受未知 host key |
| `git_sync_cache_dir` | `/tmp/ansible-git-sync` | 控制机缓存根目录 |
| `git_sync_push_method` | `copy` | `copy`（逐文件，保留源权限）或 `sync`（rsync） |
| `git_sync_sync_exclude` | `[]` | `sync` 的 rsync 排除模式（任意层级匹配） |
| `git_sync_sync_delete` | `false` | `sync` 是否删除目的目录中源端已不存在的文件 |

角色执行后导出两个结果变量：`git_sync_revision`（实际检出的 commit sha）和
`git_sync_changed`（本次是否有文件变化，可用于触发重启）。

## 示例

同步仓库里 `deploy/compose/cc` 这个目录到目标机 `/opt/compose/cc`：

```yaml
- name: 同步 compose 素材
  ansible.builtin.include_role:
    name: hroapy.misc.git_sync
  vars:
    git_sync_repo: git@codehub.example.com:ops/self-hosted-scripts.git
    git_sync_ref: v1.2.0                       # 分支 / tag / sha
    git_sync_subdir: deploy/compose/cc
    git_sync_dest: /opt/compose/cc
    git_sync_key_file: ~/.ssh/id_deploy
```

前面的检出结果可以直接喂给 `deploy_compose`（把目的目录当源目录用）：

```yaml
- name: 同步素材
  ansible.builtin.include_role:
    name: hroapy.misc.git_sync
  vars:
    git_sync_repo: "{{ cc_git_repo }}"
    git_sync_ref: "{{ cc_git_ref }}"
    git_sync_subdir: deploy/compose/cc
    git_sync_dest: "{{ git_sync_cache_dir }}/cc"

- name: 部署 compose
  ansible.builtin.include_role:
    name: hroapy.misc.deploy_compose
  vars:
    compose_src: "{{ git_sync_cache_dir }}/cc"
    compose_dir: /opt/compose/cc
```

## 注意

- **`sync` 方式需要目标机有 rsync**（`copy` 不需要，默认就是 `copy`）。
- **`copy` 不镜像**：源端删掉的文件不会从目的目录消失，历史遗留文件会留下；
  需要严格镜像就用 `git_sync_push_method: sync` + `git_sync_sync_delete: true`。
- **同步仓库根会带上 `.git`**：`git_sync_subdir` 留空且用 `copy` 时 `.git` 一并推送。
  只想要内容就用子目录，或 `sync` + `git_sync_sync_exclude: ['.git']`。
- **`git_sync_depth: 1` 只支持分支 / tag**；`git_sync_ref` 用裸 commit sha 时要设
  `git_sync_depth: 0`，否则浅克隆取不到该 sha。
- 控制机缓存不自动清理（与 `deploy_compose` 的压缩包缓存一致）；需要时手动删
  `git_sync_cache_dir` 下的 `sha1` 目录。
