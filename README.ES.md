# HoRus Bootstrap (SRE Home Lab Core Provisioning Engine - Mediados de 2026)

🌐 **Translations / Переводы / Translaciones / Übersetzungen / Traductions / Tradução / 翻译 / 翻訳:**
*   **[English (Main)](README.md)**
*   **[Русский (Russian)](README.RU.md)**
*   **[Українська (Ukrainian)](README.UA.md)**
*   **[Deutsch (German)](README.DE.md)**
*   **[Français (French)](README.FR.md)**
*   **[Español (Spanish)](README.ES.md)**
*   **[Português (Portuguese)](README.PT.md)**
*   **[中文 (Chinese)](README.ZH.md)**
*   **[日本語 (Japanese)](README.JA.md)**

---

Este repositorio, **HoRus-Bootstrap**, es el motor de aprovisionamiento declarativo basado en Infrastructure-as-Code (IaC) diseñado para la **orquestación inicial, la definición de la topología y el diseño de la virtualización** de un Home Lab SRE privado. Construido utilizando **Terraform** y el proveedor moderno `bpg/proxmox`, automatiza el despliegue de contenedores Linux no privilegiados (LXC) y máquinas virtuales (KVM/VM) a través de tres hipervisores físicos Proxmox VE en clúster (`horus-pmx-srv01`, `horus-pmx-srv02`, `horus-pmx-srv03`).

Mientras que el repositorio **HoRus-Control-Plane** se encarga del endurecimiento del sistema operativo posterior al arranque, la instalación de paquetes (Podman, bases de datos) y el despliegue de aplicaciones, **HoRus-Bootstrap** define la estructura de hardware virtual subyacente—asignando núcleos de CPU, límites de memoria, montajes de almacenamiento, enlaces de interfaces de red y zonas de seguridad.

---

## 🛠️ Patrones arquitectónicos y características clave

### 1. Direccionamiento MAC determinista
Para eliminar los conflictos de asignación de DHCP y evitar direcciones MAC duplicadas, el sistema calcula las direcciones de hardware dinámicamente en función del identificador `vmid` utilizando la siguiente fórmula:
```text
BC:24:11:00:[Centenas del VMID]:[Resto del VMID]
```
Ejemplos:
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. Matriz inteligente de almacenamiento (Datastore)
El espacio de disco físico varía entre los hosts Proxmox. La configuración de Terraform utiliza un diccionario de mapeo local (`local.node_datastores`) para resolver dinámicamente los objetivos de almacenamiento:
*   `horus-pmx-srv01` -> Mapea volúmenes secundarios a `"storage"` (HDD de 1.7T) o `"media"` (HDD de 2.6T).
*   `horus-pmx-srv02` -> Mapea arreglos SSD rápidos a `"data-pg"` (SSD de 860G para bases de datos) o `"data-ai"` (SSD de 410G para pesos de IA).
*   `horus-pmx-srv03` -> Mapea particiones de respaldo a `"data"` (HDD de 430G para almacenamiento de objetos MinIO S3).

### 3. Inyección segura de secretos en tiempo de ejecución
Las contraseñas de root para LXC y VM se leen de forma dinámica desde un archivo de espacio de trabajo local (`root_password.txt`) durante la ejecución. Dado que este archivo se excluye explícitamente a través de `.gitignore`, los secretos nunca tocan el historial de git ni los archivos de estado remotos.

### 4. VLAN y segmentación de red
Los adaptadores virtuales se vinculan directamente a los puentes Linux Proxmox (`vmbr0`) con parámetros específicos de `vlan_id` para dirigir los hosts a dominios de seguridad broadcast aislados:
*   **VLAN 10 (Management):** Interfaces de host, Vault, motor Ansible.
*   **VLAN 20 (DMZ / Enrutamiento público):** Proxies de acceso perimetral, túneles VPN.
*   **VLAN 30 (Servicios internos):** CI/CD, bases de datos, proveedor de identidad SSO, Gitea.
*   **VLAN 40 (Red de almacenamiento):** Replicación a alta velocidad y tráfico de almacenamiento S3.
*   **VLAN 50 (Observabilidad / AIOps):** Prometheus, Grafana, registros de Loki, OpenTelemetry y motores de AIOps.

---

## 🖥️ Topología del clúster y asignación de recursos

Los recursos de virtualización se distribuyen entre los hipervisores físicos para maximizar la eficiencia y garantizar límites de alta disponibilidad perfectos.

### 🚀 Host: `horus-pmx-srv01` (Cómputo, Pipelines de construcción y núcleo de medios)
| VMID | Nombre | Tipo | vCPU | RAM | Mapeos de almacenamiento (Datastore) | Red / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | VM | 2 | 4GB | Plantilla Cloud-init 9000 (Local-LVM) | Orquestación Jenkins Master |
| **102** | `horus-ai-srv01` | LXC | 4 | 4GB | 32G Root, Nvidia GPU Passthrough | Backend de IA de red |
| **103** | `horus-ai-srv02` | LXC | 4 | 4GB | 32G Root + 420G mapeado en el datastore `cameras` | Almacenamiento de video de cámaras de CV |
| **104** | `horus-media-srv01` | LXC | 2 | 2GB | 16G Root + 1740G mapeado en el datastore `storage` | Servidor de archivos CasaOS |
| **105** | `horus-media-srv02` | LXC | 4 | 4GB | 32G Root + 2662G mapeado en el datastore `media` | Servidor JoyFilm (NVENC habilitado) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4GB | Disco raíz de 40G | Agente de pipeline pesado de Jenkins |
| **107** | `horus-gg-srv01` | LXC | 2 | 2GB | Disco raíz de 20G | Escáner GitGuardian CLI / TruffleHog / Trivy (Aislado) |

### 🔒 Host: `horus-pmx-srv02` (Identidad, Servicios esenciales y SSD rápido)
| VMID | Nombre | Tipo | vCPU | RAM | Mapeos de almacenamiento (Datastore) | Red / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2GB | Disco raíz de 20G | Authentik IAM & Single Sign-On |
| **202** | `horus-git-srv01` | LXC | 2 | 2GB | Disco raíz de 20G | Repositorio privado Gitea |
| **203** | `horus-vlt-srv01` | VM | 2 | 2GB | Plantilla Cloud-init 9000 (Memoria bloqueada) | Secretos HashiCorp Vault |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1GB | Disco raíz de 15G | Documentación de Wiki.js |
| **205** | `horus-db-srv01` | LXC | 2 | 4GB | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) anidado | Clúster de bases de datos PostgreSQL 18 |
| **206** | `horus-reg-srv01` | LXC | 2 | 4GB | Disco raíz de 40G | Registro de contenedores Harbor |
| **207** | `horus-ans-srv01` | LXC | 2 | 4GB | Disco raíz de 30G | Motor de automatización Ansible |
| **208** | `horus-ai-srv03` | LXC | 4 | 8GB | 32G Root + 410G SSD mapeado en `data-ai` | Asistente de IA (Mimir Engine) |

### 📊 Host: `horus-pmx-srv03` (Observabilidad, Métricas y almacenamiento S3)
| VMID | Nombre | Tipo | vCPU | RAM | Mapeos de almacenamiento (Datastore) | Red / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1GB | Disco raíz de 10G | Visualizador de métricas Grafana |
| **302** | `horus-pm-srv01` | LXC | 2 | 2GB | Disco raíz de 15G | Hub de métricas Prometheus TSDB |
| **303** | `horus-lok-srv01` | LXC | 2 | 2GB | Disco raíz de 15G | Hub de logs Loki y Alertmanager |
| **304** | `horus-otel-srv01` | LXC | 1 | 1GB | Disco raíz de 5G | Hub de recopilación OpenTelemetry |
| **305** | `horus-s3-srv01` | LXC | 2 | 2GB | 40G Root + 430G HDD mapeado en `data` | Almacenamiento de objetos MinIO S3 |
| **306** | `horus-ai-ops01` | LXC | 4 | 4GB | Disco raíz de 32G | Motor de operaciones de IA (AIOps) |

---

## 📂 Estructura del repositorio

```text
HoRus-Bootstrap/
├── .gitignore                  # Excluye archivos de estado y variables locales
├── main.tf                     # Fichero de topología principal y definición de módulos
├── variables.tf                # Variables globales de Terraform
├── providers.tf                # Configuración del proveedor Proxmox VE (bpg/proxmox)
├── ARCHITECTURE.md             # Pasaporte arquitectónico (VLANs, mapa de nodos)
├── BACKLOG.md                  # Roadmap de desarrollo y tareas pendientes
├── LICENSE                     # Licencia del proyecto
├── modules/                    # Módulos de infraestructura reutilizables
│   ├── proxmox_lxc/            # Módulo para contenedores Linux no privilegiados (LXC)
│   │   ├── main.tf             # Definición de recursos LXC con cálculos dinámicos de MAC
│   │   └── variables.tf        # Variables de entrada específicas para LXC
│   └── proxmox_vm/             # Módulo para máquinas virtuales (KVM/VM)
│       ├── main.tf             # Definición de recursos VM basados en la plantilla 9000
│       └── variables.tf        # Variables de entrada específicas para VM
└── README.md                   # Documentación principal del repositorio
```

---

## 🚀 Guía de ejecución y despliegue (Multiplataforma)

Siga estas instrucciones para aprovisionar la infraestructura de su laboratorio doméstico desde cualquier dispositivo bajo cualquier sistema operativo.

### Requisitos previos (Todas las plataformas)
1.  **Generar claves SSH:** Cree sus credenciales administrativas en su equipo personal:
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Generar token de API de Proxmox:** Vaya a la UI de Proxmox VE (`Datacenter -> Permissions -> API Tokens`) y genere un token para el usuario `root@pam` con el nombre `terraform`. ¡Asegúrese de copiar el secreto!

---

### Instalación paso a paso

#### 🐧 1. Despliegue desde GNU/Linux y macOS
Abra su terminal y ejecute los siguientes comandos:

*   **Instalar Terraform:**
    *   *Debian/Ubuntu:*
        ```bash
        sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update && sudo apt-get install terraform
        ```
    *   *macOS (Homebrew):*
        ```bash
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
        ```

*   **Configurar variables locales y secretos:**
    ```bash
    # Crear el archivo de contraseña root de las VM/LXC (ignorado en git)
    echo "SuperSecretPass123!" > root_password.txt

    # Inicializar plantilla de variables
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    Edite `terraform.tfvars` en su editor de texto favorito e introduzca sus credenciales:
    ```hcl
    pmx_api_url    = "https://<PROXMOX_IP>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=tu-secreto-uuid-token"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Inicializar y desplegar:**
    ```bash
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Despliegue desde Windows (PowerShell o CMD)
Abra Windows Terminal (PowerShell) o el Símbolo del sistema (CMD) como Administrador:

*   **Instalar Terraform:**
    ```powershell
    # Utilizando el gestor de paquetes Chocolatey
    choco install terraform -y

    # O utilizando Winget
    winget install HashiCorp.Terraform
    ```

*   **Configurar variables locales y secretos:**
    ```powershell
    # Crear el archivo de contraseñas root en el área de trabajo
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # Crear el archivo de variables local
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    Abra `terraform.tfvars` en el Bloc de notas o VS Code e introduzca sus datos:
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=tu-secreto-uuid-token"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Inicializar y desplegar:**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. Despliegue desde Windows Subsystem for Linux (WSL)
Si prefiere ejecutar un entorno Linux nativo dentro de Windows:

*   **Configurar el terminal de WSL:**
    Abra su consola de distribución de WSL (p. ej., Ubuntu) y enlace sus llaves SSH de Windows:
    ```bash
    ln -s /mnt/c/Users/<WindowsUsername>/.ssh ~/.ssh
    ```

*   **Seguir los pasos de GNU/Linux y macOS:**
    Simplemente copie y ejecute las instrucciones indicadas para **GNU/Linux y macOS** dentro de su terminal WSL. Terraform operará de manera nativa dentro de WSL y realizará las llamadas a Proxmox a través de su red local.

---

## 🔒 Prácticas de seguridad y cumplimiento SRE

1.  **Seguridad del archivo de estado (State):**
    Los archivos de estado de Terraform (`terraform.tfstate`) contienen credenciales y tokens de API en texto plano. **Nunca los suba a repositorios públicos.** Se excluyen automáticamente mediante `.gitignore`. En entornos de producción, use un backend remoto seguro y cifrado (como GitLab Managed State, Consul o S3 con SSE).
2.  **Contenedores no privilegiados:**
    Todos los despliegues de contenedores LXC se ejecutan en modo no privilegiado (`unprivileged = true`). Esto garantiza que si un servicio contenedorizado es comprometido, el atacante no podrá escalar privilegios en el host de metal desnudo Proxmox VE.
3.  **Aislamiento estricto de memoria RAM:**
    Las máquinas virtuales críticas (Vault, Jenkins) se ejecutan en entornos KVM con límites de hardware estrictos y bloqueo de páginas de memoria RAM, previniendo lecturas no autorizadas desde otros nodos del hipervisor.

---

## 📄 Licencia y propiedad

Este proyecto está bajo la licencia **Apache License 2.0** - consulte el archivo [LICENSE](LICENSE) para obtener más detalles.

*   **Dueño y propietario del proyecto:** Aleksei Savelev (alias **Alex Benden**)
*   **Empresa y marca del proyecto:** Benden-SysLab
*   **Contacto por correo electrónico:** bendenalex@gmail.com
*   **Soporte de Telegram:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

