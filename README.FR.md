# HoRus-Bootstrap

Bootstrap Terraform du cluster HoRus Proxmox VE reconstruit sur quatre nœuds.
Le dépôt gère 28 workloads : 22 conteneurs LXC non privilégiés et 6 machines
virtuelles.

Référence complète : [README.md](README.md). Architecture détaillée :
[ARCHITECTURE.md](ARCHITECTURE.md). Topologie de référence :
[`topology.tf`](topology.tf).

Les adresses de management et des workloads, les CIDR et gateways VLAN, les endpoints NFS et les chemins physiques propres à l'environnement sont fournis uniquement via le fichier `terraform.tfvars` ignoré.

## État

Le desired state actuel est déployé et convergé. Après suppression de l'hôte
Ansible redondant et correction des VMID de Node02,
`terraform plan -parallelism=5` a retourné :

```text
No changes. Your infrastructure matches the configuration.
```

Le rollout v2.2.1 a retiré `horus-ans-srv01` et recréé uniquement les workloads
Node02 approuvés dont le VMID changeait. IAM est resté actif en VMID 206 ;
Golden 9000/9001 sont inchangés. Provider : `bpg/proxmox 0.115.0`.

HoRus-Basis configure les outils de contrôle Ansible sur le Jenkins agent
existant `horus-agent-srv01`.

## Architecture

`topology.tf` est la source unique des nœuds, VLAN, gateways, workloads et
affectations de stockage. Deux groupes de modules dynamiques en sont dérivés :

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

HoRus-Bootstrap/Terraform gère le lifecycle Proxmox, la topologie VM/LXC, les
storage attachments et les ressources d'infrastructure. HoRus-Basis/Ansible
gère le guest OS, les paquets et services. Argo CD est réservé au futur GitOps
Kubernetes ; il ne gère pas les VM/LXC Proxmox et n'est pas déployé.
`horus-work-srv01` est retiré ; KasmVNC et code-server ne sont pas des services
actifs. Le développement et la CAO restent sur le portable de l'opérateur.

## Cluster physique

| Nœud | Management | Matériel | Rôle |
|---|---|---|---|
| `horus-pmx-node01` | `private` | Xeon E3-1275v2, ~31 GiB RAM | Guardian/sécurité, CI, load balancing, média, worker Kubernetes |
| `horus-pmx-node02` | `private` | Xeon E3-1275v2, ~31 GiB RAM, RTX 3060 12 GB | Mimir AI, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | `private` | i7-3770K, ~15,6 GiB RAM | stockage, Golden factory, infrastructure centrale |
| `horus-pmx-node04` | `private` | i5-4210U, ~15,5 GiB RAM | observabilité, System Guardian |

Réseau de management : `private`, gateway `private`. Tous les
workloads utilisent `vmbr0`.

## Réseau

| VLAN | Nom | Sous-réseau | Gateway |
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

Kubernetes : Pod CIDR `private`, Service CIDR `private`.

## Inventaire des workloads

| Nœud | LXC | VM | Total |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`, 102 `horus-agent-srv01`, 104 `horus-ai-srv01`, 105 `horus-db-srv01`, 108 `horus-gg-srv01` | 103 `horus-jnk-srv01`, 106 `horus-media-srv01`, 107 `horus-k8sw-srv01` | 8 |
| Node02 | 201 `horus-ai-srv02`, 202 `horus-db-srv02`, 203 `horus-vec-srv01`, 204 `horus-cache-srv01`, 205 `horus-media-srv02`, 206 `horus-iam-srv01` | 207 `horus-k8sw-srv02`, 208 `horus-k8sc-srv01` | 8 |
| Node03 | 301 `horus-db-srv03`, 303 `horus-wiki-srv01`, 304 `horus-git-srv01`, 305 `horus-reg-srv01`, 306 `horus-vkj-srv01` | 302 `horus-vlt-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`, 402 `horus-pm-srv01`, 403 `horus-lok-srv01`, 404 `horus-otel-srv01`, 405 `horus-s3-srv01`, 406 `horus-ai-srv03` | — | 6 |
| **Total** | **22 LXC** | **6 VM** | **28** |

Le VMID 307 est réservé et n'est pas créé par Terraform. Registry est
défini comme `horus-reg-srv01`, VMID 305 (anciennement 306), sur
`horus-pmx-node03`, avec `10.10.1.36/24`, VLAN 101, root `local-lvm` et
stockage persistant `artifacts-data`. Le remplacement contrôlé est confirmé par
le plan actualisé convergé.

`horus-vkj-srv01` est le LXC Vikunja dédié sur Node03/VLAN 101. Terraform gère
le VMID 306, les ressources, le réseau, le placement et le montage privé
`infra-data`; HoRus-Basis/Ansible gère l'application et l'intégration DB03.

Node01 utilise les VMID 101-108. `horus-gg-srv01` (VMID 108, LXC, VLAN 150) est le scanner isolé GitGuardian CLI/ggshield, TruffleHog et Trivy. Terraform crée et place le LXC, déplace son rootfs vers `local-lvm`, le démarre et active `start_on_boot`; Ansible/service automation installe et configure les scanners, plannings, credentials et l'intégration CI. Node01 : 20 vCPU, 26 GiB RAM et 140 GiB de roots logiques sur 130.27 GiB physiques (thin provisioning ≈1.07x).

## Templates Golden

| VMID | Type | Emplacement | Taille de base |
|---:|---|---|---:|
| 9000 | VM Debian 13 | Node03 / `local-lvm` | 12 GiB |
| 9001 | LXC Debian 13 non privilégié | Node03 / `storage-infra` | 8 GiB |

Les deux templates sont des prérequis externes et ne sont pas gérés dans le
state Terraform.

### Cycle de vie VM

Les VM sont entièrement gérées par le provider : full clone de 9000, migration
native vers le nœud final, `local-lvm`, taille demandée, réseau/DNS,
`started=true` et `on_boot=true`. Aucun helper externe n'est utilisé.

### Cycle de vie LXC

Proxmox exige un stockage partagé pour un clone LXC entre nœuds :

```text
Golden 9001 / Node03 / storage-infra
  -> full clone sur le nœud final / storage-infra / arrêté
  -> pct move-volume sur le même nœud vers local-lvm
  -> agrandissement uniquement si nécessaire
  -> vérification identité, nœud, stockage, taille, mounts et réseau
  -> démarrage ; running + onboot=1
```

Le helper ne migre jamais un conteneur entre nœuds, ne réduit jamais un disque
et s'arrête en sécurité face à un état inattendu. La frontière contient
exactement `started`, `disk[0].datastore_id` et `disk[0].size`.

## Stockage et sécurité

Les données privées restent affectées à un seul service : Guardian sur Node01,
Mimir et AI sur Node02, infrastructure/Registry sur Node03 et logs MinIO sur
Node04. PostgreSQL 17 sur `horus-db-srv03` (VMID 301, Node03, VLAN 101)
conserve son root sur `local-lvm`. Terraform/provider alloue le volume
PostgreSQL sur `pg-local` et le monte dans `/srv/horus/infra/postgres` ;
`PGDATA` vaut `/srv/horus/infra/postgres/17/main`. Un volume séparé de 8 GiB
sur `storage-infra` est monté dans `/srv/horus/infra/backups`.

Le lifecycle de clone réserve l'index disque 0 sur `storage-infra` pour le
rootfs temporaire. Le backup utilise donc
`storage-infra:301/vm-301-disk-1.raw`. Guardian AI ne reçoit aucun fichier
PostgreSQL brut.

Le SSH root est désactivé dans les Golden guests. `abbenden-srv` utilise une
clé SSH et sudo avec mot de passe, sans `NOPASSWD` global. `jenkins-srv` ne
dispose pas d'un sudo étendu. Tous les LXC sont non privilégiés. Les secrets et
clés privées ne doivent jamais être commités.

## Exploitation

Premier bootstrap ou recréation massive de LXC :

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

Le CT source 9001 reçoit `lock: disk` pendant chaque clone. Les clones
simultanés depuis l'unique 9001 ne sont donc pas sûrs.

Exploitation normale après convergence :

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

Si le plan contient plusieurs créations/remplacements LXC, utiliser de nouveau
parallelism 1.

## Validation

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

Résultat actuel : 5 tests Terraform réussis, 0 échec ; 7 tests offline de
placement réussis. Travaux futurs : [BACKLOG.md](BACKLOG.md). Licence :
[Apache 2.0](LICENSE).
