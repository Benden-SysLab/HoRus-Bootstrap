# HoRus-Bootstrap

用于重建后的四节点 HoRus Proxmox VE 集群的 Terraform bootstrap。本仓库管理
28 个工作负载：21 个非特权 LXC 容器和 7 台虚拟机。

完整参考：[README.md](README.md)。详细架构：[ARCHITECTURE.md](ARCHITECTURE.md)。
权威拓扑：[`topology.tf`](topology.tf)。

## 状态

当前拓扑已成功部署并达到收敛状态。Bootstrap 完成后，
`terraform plan -parallelism=5` 返回：

```text
No changes. Your infrastructure matches the configuration.
```

Provider 固定为 `bpg/proxmox 0.115.0`。

## 架构

`topology.tf` 是节点、VLAN、gateway、工作负载和存储分配的唯一信息源，并生成
两个动态模块集合：

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform 管理基础设施标识和放置。后续 Ansible/服务层管理 guest 内的软件包、
服务、应用用户、数据权限和 guest-level NFS mount。

## 物理集群

| 节点 | Management | 硬件 | 主要角色 |
|---|---|---|---|
| `horus-pmx-node01` | `192.0.2.11` | Xeon E3-1275v2，约 31 GiB RAM | Guardian/security、CI、负载均衡、media、Kubernetes worker |
| `horus-pmx-node02` | `192.0.2.12` | Xeon E3-1275v2，约 31 GiB RAM，RTX 3060 12 GB | Mimir AI、Ansible、Authentik、Joyfilm、Kubernetes |
| `horus-pmx-node03` | `192.0.2.13` | i7-3770K，约 15.6 GiB RAM | storage、Golden factory、核心基础设施 |
| `horus-pmx-node04` | `192.0.2.14` | i5-4210U，约 15.5 GiB RAM | observability、System Guardian |

Management 网络为 `192.0.2.0/24`，gateway 为 `192.0.2.1`。所有工作负载
使用 `vmbr0`。

## 网络

| VLAN | 名称 | 子网 | Gateway |
|---:|---|---|---|
| 101 | INFRA | `198.51.100.0/28` | `198.51.100.1` |
| 110 | TRUSTED | `198.51.100.16/28` | `198.51.100.17` |
| 120 | IOT | `198.51.100.32/28` | `198.51.100.33` |
| 130 | QUARANTINE | `198.51.100.48/28` | `198.51.100.49` |
| 140 | STORAGE | `198.51.100.64/28` | `198.51.100.65` |
| 150 | OBS/SEC | `198.51.100.80/28` | `198.51.100.81` |
| 160 | AI | `198.51.100.96/28` | `198.51.100.97` |
| 170 | DMZ | `198.51.100.112/28` | `198.51.100.113` |
| 180 | K8S-LAB | `198.51.100.128/28` | `198.51.100.129` |

Kubernetes：Pod CIDR `198.51.100.0/24`，Service CIDR `203.0.113.0/24`。

## 工作负载清单

| 节点 | LXC | VM | 总数 |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`、102 `horus-agent-srv01`、104 `horus-ai-srv01`、105 `horus-db-srv01` | 103 `horus-jnk-srv01`、106 `horus-media-srv01`、107 `horus-k8sw-srv01` | 7 |
| Node02 | 201 `horus-ans-srv01`、202 `horus-ai-srv02`、203 `horus-db-srv02`、204 `horus-vec-srv01`、205 `horus-cache-srv01`、206 `horus-iam-srv01`、207 `horus-media-srv02` | 208 `horus-k8sw-srv02`、209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`、303 `horus-wiki-srv01`、304 `horus-git-srv01`、306 `horus-reg-srv01` | 302 `horus-vlt-srv01`、305 `horus-work-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`、402 `horus-pm-srv01`、403 `horus-lok-srv01`、404 `horus-otel-srv01`、405 `horus-s3-srv01`、406 `horus-ai-srv03` | — | 6 |
| **总计** | **21 LXC** | **7 VM** | **28** |

VMID 307 已保留，Terraform 不会创建它。

## Golden 模板

| VMID | 类型 | 位置 | 基准大小 |
|---:|---|---|---:|
| 9000 | Debian 13 VM | Node03 / `local-lvm` | 12 GiB |
| 9001 | Debian 13 非特权 LXC | Node03 / `storage-infra` | 8 GiB |

两个模板都是外部 prerequisites，不属于 Terraform state。

### VM 生命周期

VM 完全由 provider 管理：从 9000 full clone，原生迁移到最终节点，使用
`local-lvm` 和请求的磁盘大小，配置网络/DNS，并设置 `started=true` 和
`on_boot=true`。VM 不使用外部 placement helper。

### LXC 生命周期

Proxmox 的跨节点 LXC clone 要求 shared storage：

```text
Golden 9001 / Node03 / storage-infra
  -> 在最终节点 / storage-infra 上以 stopped 状态 full clone
  -> 在同一节点通过 pct move-volume 移动到 local-lvm
  -> 仅在需要时扩容
  -> 验证 identity、node、storage、size、mounts 和 network
  -> 启动；running + onboot=1
```

Helper 不执行跨节点迁移、不缩小磁盘，并在状态异常时安全失败。边界字段只有
`started`、`disk[0].datastore_id` 和 `disk[0].size`。

## 存储和安全

Private data 仅属于对应服务：Guardian 位于 Node01，Mimir 和 AI 位于 Node02，
infrastructure/Registry 位于 Node03，MinIO logs 位于 Node04。Shared media 和
artifacts 由后续 Ansible 在 guest 内配置 NFS。Guardian AI 不会获得原始
PostgreSQL 文件。

Golden guest 内已禁用 root SSH。`abbenden-srv` 使用 SSH key 和需要密码的
sudo，不配置广泛的 `NOPASSWD`。`jenkins-srv` 没有广泛 sudo 权限。所有 LXC
均为非特权容器。不得提交 credential 或 private key。

## 操作

首次 bootstrap 或批量重建 LXC：

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

每次 clone 时，源 CT 9001 都会获得 `lock: disk`；从唯一 9001 同时 clone
并不安全。

收敛后的正常操作：

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

如果 plan 包含多个 LXC create/replace，必须改用 parallelism 1。

## 验证

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

当前结果：5 个 Terraform tests 通过，0 个失败；7 个 offline placement tests
通过。未来工作见 [BACKLOG.md](BACKLOG.md)。许可证：[Apache 2.0](LICENSE)。
