# HoRus-Bootstrap

再構築された4ノード構成の HoRus Proxmox VE クラスター向け Terraform
ブートストラップです。このリポジトリは、21個の非特権 LXC コンテナーと
7台の仮想マシン、合計28ワークロードを管理します。

完全なリファレンス: [README.md](README.md)。詳細設計:
[ARCHITECTURE.md](ARCHITECTURE.md)。正規のトポロジー:
[`topology.tf`](topology.tf)。

環境固有の management/workload アドレス、VLAN CIDR と gateway、NFS endpoint、物理パスは、ignore 対象の `terraform.tfvars` からのみ供給されます。

## ステータス

現在のトポロジーはデプロイ済みで、収束を確認しています。ブートストラップ
完了後の `terraform plan -parallelism=5` の結果は次のとおりです。

```text
No changes. Your infrastructure matches the configuration.
```

Provider は `bpg/proxmox 0.115.0` に固定されています。

## アーキテクチャ

`topology.tf` がノード、VLAN、gateway、ワークロード、ストレージ割り当ての
唯一の情報源です。そこから2つの動的モジュール群を生成します。

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform はインフラの識別情報と配置を管理します。パッケージ、サービス、
アプリケーションユーザー、guest 内のデータ所有権、guest-level NFS mount は
後続の Ansible/サービス層が管理します。

## 物理クラスター

| ノード | Management | ハードウェア | 主な役割 |
|---|---|---|---|
| `horus-pmx-node01` | `private` | Xeon E3-1275v2、約31 GiB RAM | Guardian/security、CI、負荷分散、media、Kubernetes worker |
| `horus-pmx-node02` | `private` | Xeon E3-1275v2、約31 GiB RAM、RTX 3060 12 GB | Mimir AI、Ansible、Authentik、Joyfilm、Kubernetes |
| `horus-pmx-node03` | `private` | i7-3770K、約15.6 GiB RAM | storage、Golden factory、基盤サービス |
| `horus-pmx-node04` | `private` | i5-4210U、約15.5 GiB RAM | observability、System Guardian |

Management ネットワークは `private`、gateway は `private` です。
全ワークロードが `vmbr0` を使用します。

## ネットワーク

| VLAN | 名前 | サブネット | Gateway |
|---:|---|---|---|
| 101 | INFRA | `private` | `private` |
| 110 | TRUSTED | `private` | `private` |
| 120 | IOT | `private` | `private` |
| 130 | QUARANTINE | `private` | `private` |
| 140 | STORAGE | `private` | `private` |
| 150 | OBS/SEC | `private` | `private` |
| 160 | AI | `private` | `private` |
| 170 | DMZ | `private` | `private` |
| 180 | K8S-LAB | `private` | `private` |

Kubernetes: Pod CIDR `private`、Service CIDR `private`。

## ワークロード一覧

| ノード | LXC | VM | 合計 |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`、102 `horus-agent-srv01`、104 `horus-ai-srv01`、105 `horus-db-srv01` | 103 `horus-jnk-srv01`、106 `horus-media-srv01`、107 `horus-k8sw-srv01` | 7 |
| Node02 | 201 `horus-ans-srv01`、202 `horus-ai-srv02`、203 `horus-db-srv02`、204 `horus-vec-srv01`、205 `horus-cache-srv01`、206 `horus-iam-srv01`、207 `horus-media-srv02` | 208 `horus-k8sw-srv02`、209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`、303 `horus-wiki-srv01`、304 `horus-git-srv01`、306 `horus-reg-srv01` | 302 `horus-vlt-srv01`、305 `horus-work-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`、402 `horus-pm-srv01`、403 `horus-lok-srv01`、404 `horus-otel-srv01`、405 `horus-s3-srv01`、406 `horus-ai-srv03` | — | 6 |
| **合計** | **21 LXC** | **7 VM** | **28** |

VMID 307 は予約済みで、Terraform は作成しません。

## Golden テンプレート

| VMID | 種別 | 配置 | 基準サイズ |
|---:|---|---|---:|
| 9000 | Debian 13 VM | Node03 / `local-lvm` | 12 GiB |
| 9001 | Debian 13 非特権 LXC | Node03 / `storage-infra` | 8 GiB |

どちらも外部 prerequisite であり、Terraform state の管理対象外です。

### VM ライフサイクル

VM は provider のみで管理します。9000 の full clone、最終ノードへの native
migration、`local-lvm`、要求ディスクサイズ、ネットワーク/DNS、
`started=true`、`on_boot=true` を適用します。VM 用の外部 helper はありません。

### LXC ライフサイクル

Proxmox のノード間 LXC clone には shared storage が必要です。

```text
Golden 9001 / Node03 / storage-infra
  -> 最終ノード / storage-infra へ stopped 状態で full clone
  -> 同一ノードで pct move-volume により local-lvm へ移動
  -> 必要な場合だけ拡張
  -> identity、node、storage、size、mounts、network を検証
  -> start; running + onboot=1
```

Helper はノード間 migration を行わず、ディスクを縮小せず、想定外の状態では
安全に停止します。境界となるフィールドは `started`、
`disk[0].datastore_id`、`disk[0].size` の3つだけです。

## ストレージとセキュリティ

Private data は単一サービスに帰属します。Guardian は Node01、Mimir と AI は
Node02、infrastructure/Registry は Node03、MinIO logs は Node04 です。Shared
media と artifacts の guest-level NFS は後続の Ansible が設定します。
Guardian AI に PostgreSQL の raw files は渡しません。

Golden guest では root SSH を無効化しています。`abbenden-srv` は SSH key と
パスワード付き sudo を使用し、包括的な `NOPASSWD` はありません。
`jenkins-srv` に広範な sudo 権限はありません。全 LXC は非特権です。
credential や private key を commit してはいけません。

## 運用

初回 bootstrap または LXC の一括再作成:

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

Clone 中は source CT 9001 に `lock: disk` が設定されるため、単一の 9001 からの
同時 clone は安全ではありません。

収束後の通常運用:

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

Plan に複数の LXC create/replace が含まれる場合は parallelism 1 を使用します。

## 検証

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

現在の結果: Terraform test は5件成功、0件失敗。Offline placement test は
7件成功。今後の作業: [BACKLOG.md](BACKLOG.md)。ライセンス:
[Apache 2.0](LICENSE)。
