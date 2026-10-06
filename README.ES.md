# HoRus-Bootstrap

Bootstrap con Terraform para el clúster HoRus Proxmox VE reconstruido de cuatro
nodos. El repositorio administra 28 cargas: 21 contenedores LXC sin privilegios
y 7 máquinas virtuales.

Referencia completa: [README.md](README.md). Diseño detallado:
[ARCHITECTURE.md](ARCHITECTURE.md). Topología autoritativa:
[`topology.tf`](topology.tf).

## Estado

La topología actual fue desplegada correctamente y está convergida. Después del
bootstrap, `terraform plan -parallelism=5` devolvió:

```text
No changes. Your infrastructure matches the configuration.
```

Proveedor fijado: `bpg/proxmox 0.115.0`.

## Arquitectura

`topology.tf` es la única fuente para nodos, VLAN, gateways, cargas y
almacenamiento. A partir de ella se generan dos grupos dinámicos:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform administra identidad y ubicación de infraestructura. Ansible y la
capa posterior de servicios administran paquetes, servicios, usuarios,
permisos de datos dentro de los guests y montajes NFS dentro de los guests.

## Clúster físico

| Nodo | Gestión | Hardware | Función |
|---|---|---|---|
| `horus-pmx-node01` | `192.0.2.11` | Xeon E3-1275v2, ~31 GiB RAM | Guardian/seguridad, CI, balanceo, media, worker Kubernetes |
| `horus-pmx-node02` | `192.0.2.12` | Xeon E3-1275v2, ~31 GiB RAM, RTX 3060 12 GB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | `192.0.2.13` | i7-3770K, ~15,6 GiB RAM | almacenamiento, fábrica Golden, infraestructura central |
| `horus-pmx-node04` | `192.0.2.14` | i5-4210U, ~15,5 GiB RAM | observabilidad, System Guardian |

Red de gestión: `192.0.2.0/24`, gateway `192.0.2.1`. Todas las cargas usan
`vmbr0`.

## Red

| VLAN | Nombre | Subred | Gateway |
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

## Inventario de cargas

| Nodo | LXC | VM | Total |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`, 102 `horus-agent-srv01`, 104 `horus-ai-srv01`, 105 `horus-db-srv01` | 103 `horus-jnk-srv01`, 106 `horus-media-srv01`, 107 `horus-k8sw-srv01` | 7 |
| Node02 | 201 `horus-ans-srv01`, 202 `horus-ai-srv02`, 203 `horus-db-srv02`, 204 `horus-vec-srv01`, 205 `horus-cache-srv01`, 206 `horus-iam-srv01`, 207 `horus-media-srv02` | 208 `horus-k8sw-srv02`, 209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`, 303 `horus-wiki-srv01`, 304 `horus-git-srv01`, 306 `horus-reg-srv01` | 302 `horus-vlt-srv01`, 305 `horus-work-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`, 402 `horus-pm-srv01`, 403 `horus-lok-srv01`, 404 `horus-otel-srv01`, 405 `horus-s3-srv01`, 406 `horus-ai-srv03` | — | 6 |
| **Total** | **21 LXC** | **7 VM** | **28** |

VMID 307 está reservado y Terraform no lo crea.

## Plantillas Golden

| VMID | Tipo | Ubicación | Tamaño base |
|---:|---|---|---:|
| 9000 | VM Debian 13 | Node03 / `local-lvm` | 12 GiB |
| 9001 | LXC Debian 13 sin privilegios | Node03 / `storage-infra` | 8 GiB |

Ambas plantillas son requisitos externos y no forman parte del state de
Terraform.

### Ciclo de vida de VM

Las VM usan solamente el provider: full clone de 9000, migración nativa al nodo
final, `local-lvm`, tamaño solicitado, red/DNS, `started=true` y
`on_boot=true`. No existe helper externo para las VM.

### Ciclo de vida de LXC

Proxmox exige almacenamiento compartido para un clone LXC entre nodos:

```text
Golden 9001 / Node03 / storage-infra
  -> full clone en el nodo final / storage-infra / detenido
  -> pct move-volume en el mismo nodo hacia local-lvm
  -> ampliar solamente si es necesario
  -> verificar identidad, nodo, storage, tamaño, mounts y red
  -> iniciar; running + onboot=1
```

El helper no migra contenedores entre nodos, nunca reduce discos y falla de
forma segura ante un estado inesperado. La frontera contiene exactamente
`started`, `disk[0].datastore_id` y `disk[0].size`.

## Almacenamiento y seguridad

Los datos privados pertenecen a un único servicio: Guardian en Node01, Mimir y
AI en Node02, infraestructura/Registry en Node03 y MinIO logs en Node04. Media
y artifacts compartidos se configuran posteriormente como NFS dentro de los
guests mediante Ansible. Guardian AI no recibe archivos PostgreSQL sin procesar.

El acceso SSH de root está deshabilitado dentro de los Golden guests.
`abbenden-srv` usa clave SSH y sudo con contraseña, sin `NOPASSWD` global.
`jenkins-srv` no posee sudo amplio. Todos los LXC son sin privilegios. Nunca se
deben guardar credenciales ni claves privadas en el repositorio.

## Operación

Primer bootstrap o recreación masiva de LXC:

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

El CT 9001 recibe `lock: disk` durante cada clone; los clones simultáneos desde
la única plantilla 9001 no son seguros.

Operación normal convergida:

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

Si el plan contiene varios create/replace de LXC, debe usarse parallelism 1.

## Validación

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

Resultado actual: 5 pruebas Terraform aprobadas, 0 fallidas; 7 pruebas offline
de placement aprobadas. Trabajo futuro: [BACKLOG.md](BACKLOG.md). Licencia:
[Apache 2.0](LICENSE).
