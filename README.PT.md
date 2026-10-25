# HoRus-Bootstrap

Bootstrap Terraform para o cluster HoRus Proxmox VE reconstruído com quatro
nós. O repositório gerencia 29 workloads: 23 contêineres LXC não privilegiados
e 6 máquinas virtuais.

Referência completa: [README.md](README.md). Arquitetura detalhada:
[ARCHITECTURE.md](ARCHITECTURE.md). Topologia autoritativa:
[`topology.tf`](topology.tf).

Endereços de management e workloads, CIDRs e gateways de VLAN, endpoints NFS e caminhos físicos específicos do ambiente são fornecidos somente pelo `terraform.tfvars` ignorado.

## Estado

O desired state atual está implantado e convergido. Após a recuperação de
storage do DB03, `terraform plan -parallelism=5` retornou:

```text
No changes. Your infrastructure matches the configuration.
```

O apply controlado substituiu apenas o LXC DB03 vazio e seu placement helper;
VM 302 e todos os demais workloads permaneceram inalterados. Provider fixado:
`bpg/proxmox 0.115.0`.

## Arquitetura

`topology.tf` é a única fonte para nós, VLANs, gateways, workloads e
armazenamento. Dois grupos dinâmicos de módulos são derivados dela:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

HoRus-Bootstrap/Terraform gerencia o lifecycle Proxmox, a topologia VM/LXC,
storage attachments e recursos de infraestrutura. HoRus-Basis/Ansible gerencia
guest OS, pacotes e serviços. Argo CD fica reservado ao futuro GitOps de
Kubernetes; não gerencia VM/LXC Proxmox e não está implantado.
`horus-work-srv01` foi retirado; KasmVNC e code-server não são serviços ativos.
Desenvolvimento e CAD permanecem no laptop pessoal do operador.

## Cluster físico

| Nó | Management | Hardware | Função |
|---|---|---|---|
| `horus-pmx-node01` | `private` | Xeon E3-1275v2, ~31 GiB RAM | Guardian/segurança, CI, balanceamento, mídia, worker Kubernetes |
| `horus-pmx-node02` | `private` | Xeon E3-1275v2, ~31 GiB RAM, RTX 3060 12 GB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | `private` | i7-3770K, ~15,6 GiB RAM | storage, Golden factory, infraestrutura central |
| `horus-pmx-node04` | `private` | i5-4210U, ~15,5 GiB RAM | observabilidade, System Guardian |

Rede de management: `private`, gateway `private`. Todos os workloads
usam `vmbr0`.

## Rede

| VLAN | Nome | Sub-rede | Gateway |
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

Kubernetes: Pod CIDR `private`, Service CIDR `private`.

## Inventário de workloads

| Nó | LXC | VM | Total |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`, 102 `horus-agent-srv01`, 104 `horus-ai-srv01`, 105 `horus-db-srv01`, 108 `horus-gg-srv01` | 103 `horus-jnk-srv01`, 106 `horus-media-srv01`, 107 `horus-k8sw-srv01` | 8 |
| Node02 | 201 `horus-ans-srv01`, 202 `horus-ai-srv02`, 203 `horus-db-srv02`, 204 `horus-vec-srv01`, 205 `horus-cache-srv01`, 206 `horus-iam-srv01`, 207 `horus-media-srv02` | 208 `horus-k8sw-srv02`, 209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`, 303 `horus-wiki-srv01`, 304 `horus-git-srv01`, 305 `horus-reg-srv01`, 306 `horus-vkj-srv01` | 302 `horus-vlt-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`, 402 `horus-pm-srv01`, 403 `horus-lok-srv01`, 404 `horus-otel-srv01`, 405 `horus-s3-srv01`, 406 `horus-ai-srv03` | — | 6 |
| **Total** | **23 LXC** | **6 VM** | **29** |

O VMID 307 está reservado e não é criado pelo Terraform. Registry é
definido como `horus-reg-srv01`, VMID 305 (antes 306), no
`horus-pmx-node03`, com `10.10.1.36/24`, VLAN 101, root `local-lvm` e
persistência `artifacts-data`. A substituição controlada foi confirmada pelo
plan atualizado convergido.

`horus-vkj-srv01` é o LXC dedicado do Vikunja no Node03/VLAN 101. Terraform
gerencia VMID 306, recursos, rede, placement e o mount privado `infra-data`;
HoRus-Basis/Ansible gerencia a aplicação e a integração com DB03.

Node01 usa VMIDs 101-108. `horus-gg-srv01` (VMID 108, LXC, VLAN 150) é o scanner isolado de GitGuardian CLI/ggshield, TruffleHog e Trivy. Terraform cria e posiciona o LXC, move o rootfs para `local-lvm`, inicia e ativa `start_on_boot`; Ansible/service automation instala e configura scanners, agenda, credenciais e integração CI. Node01: 20 vCPU, 26 GiB RAM e 140 GiB de roots lógicos sobre 130.27 GiB físicos (thin provisioning ≈1.07x).

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
Node02, infraestrutura/Registry no Node03 e logs do MinIO no Node04. PostgreSQL
17 no `horus-db-srv03` (VMID 301, Node03, VLAN 101) mantém o root em
`local-lvm`. Terraform/provider aloca o volume PostgreSQL em `pg-local` e o
monta em `/srv/horus/infra/postgres`; `PGDATA` é
`/srv/horus/infra/postgres/17/main`. Um volume separado de 8 GiB em
`storage-infra` é montado em `/srv/horus/infra/backups`.

O lifecycle de clone reserva o índice de disco 0 em `storage-infra` para o
rootfs temporário. Por isso o backup usa
`storage-infra:301/vm-301-disk-1.raw`. Guardian AI não recebe arquivos
PostgreSQL brutos.

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
