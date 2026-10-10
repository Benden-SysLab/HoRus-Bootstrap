# HoRus-Bootstrap

Bootstrap Terraform du cluster HoRus Proxmox VE reconstruit sur quatre nœuds.
Le dépôt gère 29 workloads : 22 conteneurs LXC non privilégiés et 7 machines
virtuelles.

Référence complète : [README.md](README.md). Architecture détaillée :
[ARCHITECTURE.md](ARCHITECTURE.md). Topologie de référence :
[`topology.tf`](topology.tf).

Les adresses de management et des workloads, les CIDR et gateways VLAN, les endpoints NFS et les chemins physiques propres à l'environnement sont fournis uniquement via le fichier `terraform.tfvars` ignoré.

## État

La topologie actuelle a été déployée et converge correctement. Après le
bootstrap, `terraform plan -parallelism=5` a retourné :

```text
No changes. Your infrastructure matches the configuration.
```

Provider utilisé : `bpg/proxmox 0.115.0`.

## Architecture

`topology.tf` est la source unique des nœuds, VLAN, gateways, workloads et
affectations de stockage. Deux groupes de modules dynamiques en sont dérivés :

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform gère l'identité et le placement de l'infrastructure. Ansible et la
couche de services ultérieure gèrent les paquets, services, utilisateurs,
droits des données dans les guests et montages NFS dans les guests.

## Cluster physique

| Nœud | Management | Matériel | Rôle |
|---|---|---|---|
| `horus-pmx-node01` | `private` | Xeon E3-1275v2, ~31 GiB RAM | Guardian/sécurité, CI, load balancing, média, worker Kubernetes |
| `horus-pmx-node02` | `private` | Xeon E3-1275v2, ~31 GiB RAM, RTX 3060 12 GB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes |
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
| Node02 | 201 `horus-ans-srv01`, 202 `horus-ai-srv02`, 203 `horus-db-srv02`, 204 `horus-vec-srv01`, 205 `horus-cache-srv01`, 206 `horus-iam-srv01`, 207 `horus-media-srv02` | 208 `horus-k8sw-srv02`, 209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`, 303 `horus-wiki-srv01`, 304 `horus-git-srv01`, 306 `horus-reg-srv01` | 302 `horus-vlt-srv01`, 305 `horus-work-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`, 402 `horus-pm-srv01`, 403 `horus-lok-srv01`, 404 `horus-otel-srv01`, 405 `horus-s3-srv01`, 406 `horus-ai-srv03` | — | 6 |
| **Total** | **22 LXC** | **7 VM** | **29** |

Le VMID 307 est réservé et n'est pas créé par Terraform.

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
Node04. Les médias et artifacts partagés seront montés dans les guests par
Ansible. Guardian AI ne reçoit aucun fichier PostgreSQL brut.

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
