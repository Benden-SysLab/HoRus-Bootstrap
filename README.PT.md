# HoRus-Bootstrap

Bootstrap Terraform para o cluster HoRus Proxmox VE reconstruído com quatro
nós. O repositório gerencia 28 workloads: 21 contêineres LXC não privilegiados
e 7 máquinas virtuais.

Referência completa: [README.md](README.md). Arquitetura detalhada:
[ARCHITECTURE.md](ARCHITECTURE.md). Topologia autoritativa:
[`topology.tf`](topology.tf).

## Estado

A topologia atual foi implantada e está convergida. Após o bootstrap,
`terraform plan -parallelism=5` retornou:

```text
No changes. Your infrastructure matches the configuration.
```

Provider fixado: `bpg/proxmox 0.115.0`.

## Arquitetura

`topology.tf` é a única fonte para nós, VLANs, gateways, workloads e
armazenamento. Dois grupos dinâmicos de módulos são derivados dela:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform gerencia identidade e posicionamento da infraestrutura. Ansible e a
camada posterior de serviços gerenciam pacotes, serviços, usuários, permissões
de dados nos guests e mounts NFS dentro dos guests.

## Cluster físico

| Nó | Management | Hardware | Função |
|---|---|---|---|
| `horus-pmx-node01` | `192.0.2.11` | Xeon E3-1275v2, ~31 GiB RAM | Guardian/segurança, CI, balanceamento, mídia, worker Kubernetes |
| `horus-pmx-node02` | `192.0.2.12` | Xeon E3-1275v2, ~31 GiB RAM, RTX 3060 12 GB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | `192.0.2.13` | i7-3770K, ~15,6 GiB RAM | storage, Golden factory, infraestrutura central |
| `horus-pmx-node04` | `192.0.2.14` | i5-4210U, ~15,5 GiB RAM | observabilidade, System Guardian |

Rede de management: `192.0.2.0/24`, gateway `192.0.2.1`. Todos os workloads
usam `vmbr0`.

## Rede

| VLAN | Nome | Sub-rede | Gateway |
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

Kubernetes: Pod CIDR `198.51.100.0/24`, Service CIDR `203.0.113.0/24`.

## Inventário de workloads

| Nó | LXC | VM | Total |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`, 102 `horus-agent-srv01`, 104 `horus-ai-srv01`, 105 `horus-db-srv01` | 103 `horus-jnk-srv01`, 106 `horus-media-srv01`, 107 `horus-k8sw-srv01` | 7 |
| Node02 | 201 `horus-ans-srv01`, 202 `horus-ai-srv02`, 203 `horus-db-srv02`, 204 `horus-vec-srv01`, 205 `horus-cache-srv01`, 206 `horus-iam-srv01`, 207 `horus-media-srv02` | 208 `horus-k8sw-srv02`, 209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`, 303 `horus-wiki-srv01`, 304 `horus-git-srv01`, 306 `horus-reg-srv01` | 302 `horus-vlt-srv01`, 305 `horus-work-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`, 402 `horus-pm-srv01`, 403 `horus-lok-srv01`, 404 `horus-otel-srv01`, 405 `horus-s3-srv01`, 406 `horus-ai-srv03` | — | 6 |
| **Total** | **21 LXC** | **7 VM** | **28** |

O VMID 307 está reservado e não é criado pelo Terraform.

## Templates Golden

| VMID | Tipo | Localização | Tamanho base |
|---:|---|---|---:|
| 9000 | VM Debian 13 | Node03 / `local-lvm` | 12 GiB |
| 9001 | LXC Debian 13 não privilegiado | Node03 / `storage-infra` | 8 GiB |

Os dois templates são pré-requisitos externos e não pertencem ao state do
Terraform.

### Ciclo de vida de VM

As VMs usam apenas o provider: full clone de 9000, migração nativa para o nó
final, `local-lvm`, tamanho solicitado, rede/DNS, `started=true` e
`on_boot=true`. Não há helper externo para VMs.

### Ciclo de vida de LXC

O Proxmox exige storage compartilhado para clone LXC entre nós:

```text
Golden 9001 / Node03 / storage-infra
  -> full clone no nó final / storage-infra / parado
  -> pct move-volume no mesmo nó para local-lvm
  -> ampliar somente quando necessário
  -> verificar identidade, nó, storage, tamanho, mounts e rede
  -> iniciar; running + onboot=1
```

O helper não migra contêineres entre nós, nunca reduz discos e falha de forma
segura diante de estado inesperado. A fronteira contém exatamente `started`,
`disk[0].datastore_id` e `disk[0].size`.

## Storage e segurança

Dados privados pertencem a um único serviço: Guardian no Node01, Mimir e AI no
Node02, infraestrutura/Registry no Node03 e logs do MinIO no Node04. Mídia e
artifacts compartilhados serão configurados depois como NFS dentro dos guests
pelo Ansible. Guardian AI não recebe arquivos PostgreSQL brutos.

SSH root está desabilitado nos Golden guests. `abbenden-srv` usa chave SSH e
sudo com senha, sem `NOPASSWD` amplo. `jenkins-srv` não possui sudo amplo.
Todos os LXC são não privilegiados. Credenciais e chaves privadas nunca devem
ser commitadas.

## Operação

Primeiro bootstrap ou recriação em massa de LXC:

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

O CT 9001 recebe `lock: disk` durante cada clone; clones simultâneos do único
9001 não são seguros.

Operação normal convergida:

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

Se o plano contiver vários create/replace de LXC, use parallelism 1.

## Validação

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

Resultado atual: 5 testes Terraform aprovados, 0 falhas; 7 testes offline de
placement aprovados. Trabalho futuro: [BACKLOG.md](BACKLOG.md). Licença:
[Apache 2.0](LICENSE).
