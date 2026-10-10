# HoRus-Bootstrap

Terraform-Bootstrap für den neu aufgebauten HoRus-Proxmox-VE-Cluster mit vier
Knoten. Das Repository verwaltet 29 Workloads: 22 unprivilegierte
LXC-Container und 7 virtuelle Maschinen.

Vollständige Referenz: [README.md](README.md). Architekturdetails:
[ARCHITECTURE.md](ARCHITECTURE.md). Maßgebliche Topologie:
[`topology.tf`](topology.tf).

Umgebungsspezifische Management-/Workload-Adressen, VLAN-CIDRs und Gateways, NFS-Endpunkte sowie physische Pfade werden ausschließlich über die ignorierte `terraform.tfvars` bereitgestellt.

## Status

Die aktuelle Topologie wurde erfolgreich ausgerollt und ist konvergiert. Der
abschließende Befehl `terraform plan -parallelism=5` meldete:

```text
No changes. Your infrastructure matches the configuration.
```

Verwendeter Provider: `bpg/proxmox 0.115.0`.

## Architektur

`topology.tf` ist die einzige Quelle für Knoten, VLANs, Gateways, Workloads und
Storage-Zuordnungen. Daraus werden zwei dynamische Modulgruppen erzeugt:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform verwaltet Identität und Infrastrukturplatzierung. Ansible bzw. die
spätere Service-Schicht verwaltet Pakete, Dienste, Benutzer, Datenrechte im Gast
und NFS-Mounts innerhalb der Gäste.

## Physischer Cluster

| Knoten | Management | Hardware | Rolle |
|---|---|---|---|
| `horus-pmx-node01` | `private` | Xeon E3-1275v2, ~31 GiB RAM | Guardian/Security, CI, Load Balancing, Media, Kubernetes Worker |
| `horus-pmx-node02` | `private` | Xeon E3-1275v2, ~31 GiB RAM, RTX 3060 12 GB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | `private` | i7-3770K, ~15,6 GiB RAM | Storage, Golden Factory, Kerninfrastruktur |
| `horus-pmx-node04` | `private` | i5-4210U, ~15,5 GiB RAM | Observability, System Guardian |

Management-Netz: `private`, Gateway `private`. Alle Workloads nutzen
`vmbr0`.

## Netzwerk

| VLAN | Name | Netz | Gateway |
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

## Workload-Inventar

| Knoten | LXC | VM | Gesamt |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`, 102 `horus-agent-srv01`, 104 `horus-ai-srv01`, 105 `horus-db-srv01`, 108 `horus-gg-srv01` | 103 `horus-jnk-srv01`, 106 `horus-media-srv01`, 107 `horus-k8sw-srv01` | 8 |
| Node02 | 201 `horus-ans-srv01`, 202 `horus-ai-srv02`, 203 `horus-db-srv02`, 204 `horus-vec-srv01`, 205 `horus-cache-srv01`, 206 `horus-iam-srv01`, 207 `horus-media-srv02` | 208 `horus-k8sw-srv02`, 209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`, 303 `horus-wiki-srv01`, 304 `horus-git-srv01`, 306 `horus-reg-srv01` | 302 `horus-vlt-srv01`, 305 `horus-work-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`, 402 `horus-pm-srv01`, 403 `horus-lok-srv01`, 404 `horus-otel-srv01`, 405 `horus-s3-srv01`, 406 `horus-ai-srv03` | — | 6 |
| **Gesamt** | **22 LXC** | **7 VM** | **29** |

VMID 307 ist reserviert und wird nicht erstellt.

Node01 nutzt VMIDs 101-108. `horus-gg-srv01` (VMID 108, LXC, VLAN 150) ist der isolierte GitGuardian CLI/ggshield-, TruffleHog- und Trivy-Scanner. Terraform erstellt und platziert den LXC, verschiebt das rootfs nach `local-lvm`, startet ihn und setzt `start_on_boot`; Ansible/service automation installiert und konfiguriert Scanner, Zeitpläne, Credentials und CI-Integration. Node01: 20 vCPU, 26 GiB RAM, 140 GiB logische Roots auf 130.27 GiB physischem `local-lvm` (ca. 1.07x Thin-Provisioning).

## Golden Templates

| VMID | Typ | Standort | Basisgröße |
|---:|---|---|---:|
| 9000 | Debian 13 VM | Node03 / `local-lvm` | 12 GiB |
| 9001 | Debian 13 LXC, unprivilegiert | Node03 / `storage-infra` | 8 GiB |

Beide Templates sind externe Voraussetzungen und gehören nicht zum
Terraform-State.

### VM-Lebenszyklus

VMs werden vollständig durch den Provider verwaltet: Full Clone von 9000,
native Migration zum Zielknoten, finales `local-lvm`, gewünschte Disk-Größe,
Netzwerk/DNS sowie `started=true` und `on_boot=true`. Für VMs gibt es keinen
externen Placement-Helper.

### LXC-Lebenszyklus

Proxmox erlaubt Cross-Node-LXC-Clones nur auf Shared Storage. Deshalb gilt:

```text
Golden 9001 / Node03 / storage-infra
  -> Full Clone auf dem finalen Knoten / storage-infra / gestoppt
  -> same-node pct move-volume nach local-lvm
  -> nur bei Bedarf vergrößern
  -> Identität, Knoten, Storage, Größe, Mounts und Netzwerk prüfen
  -> starten; running + onboot=1
```

Der Helper führt keine Cross-Node-Migration durch, verkleinert niemals Disks
und bricht bei unerwartetem Zustand sicher ab. Genau drei Felder bilden die
Provider-Grenze: `started`, `disk[0].datastore_id` und `disk[0].size`.

## Storage und Sicherheit

Private Zustände bleiben beim jeweiligen Dienst: Guardian auf Node01, Mimir und
AI-Daten auf Node02, Infrastruktur/Registry auf Node03 und MinIO-Logs auf
Node04. Shared Media und Build-Artefakte werden erst später als guest-level NFS
durch Ansible konfiguriert. Guardian AI erhält keine rohen PostgreSQL-Dateien.

Root-SSH ist in den Golden-Gästen deaktiviert. `abbenden-srv` verwendet einen
SSH-Key und passwortgeschütztes sudo ohne pauschales `NOPASSWD`.
`jenkins-srv` besitzt keinen breiten sudo-Zugriff. Alle LXC sind
unprivilegiert. Zugangsdaten und private Schlüssel dürfen nicht committed
werden.

## Betrieb

Erster Bootstrap oder massenhafte LXC-Neuerstellung:

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

Der Quell-CT 9001 erhält während eines Clones `lock: disk`. Parallele Clones aus
dem einzigen 9001 sind daher unsicher.

Normaler konvergierter Betrieb:

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

Bei mehreren LXC-Create/Replace-Aktionen im Plan muss wieder Parallelism 1
verwendet werden.

## Validierung

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

Aktuelles Ergebnis: 5 Terraform-Tests bestanden, 0 fehlgeschlagen; 7 Offline-
Placement-Tests bestanden. Bekannte Einschränkungen und zukünftige Arbeiten
stehen in [BACKLOG.md](BACKLOG.md). Lizenz: [Apache 2.0](LICENSE).
