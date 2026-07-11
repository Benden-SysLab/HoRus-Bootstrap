# HoRus Bootstrap (SRE Home Lab Core Provisioning Engine - Mid 2026)

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

This repository, **HoRus-Bootstrap**, is the declarative Infrastructure-as-Code (IaC) provisioning engine designed for the **initial orchestration, topology definition, and virtualization layout** of a private Home Lab SRE cluster. Built using **Terraform** and the modern `bpg/proxmox` provider, it automates the deployment of unprivileged Linux Containers (LXC) and Virtual Machines (KVM/VM) across three clustered physical Proxmox VE hypervisors (`horus-pmx-srv01`, `horus-pmx-srv02`, `horus-pmx-srv03`).

While the **HoRus-Control-Plane** repository is responsible for post-boot operating system hardening, package setup (Podman, databases), and application deployment, **HoRus-Bootstrap** defines the underlying virtual hardware structure—allocating CPU cores, memory limits, storage mounts, network interface bindings, and security zones.

---

## 🛠️ Key Architectural Patterns & Features

### 1. Deterministic MAC Addressing (Conflict Prevention)
To eliminate DHCP allocation conflicts and prevent duplicate MAC addresses, the system computes the hardware addresses dynamically based on the resource `vmid`. If no explicit MAC address is provided via variables, it applies a deterministic hexadecimal pattern:
```text
BC:24:11:00:[VMID Hundreds]:[VMID Remainder]
```
For example:
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. Intelligent Storage/Datastore Matrix
Physical disk space differs across Proxmox hosts. The Terraform configuration utilizes a localized mapping dictionary (`local.node_datastores`) inside modules to resolve destination storage targets dynamically:
*   `horus-pmx-srv01` -> Maps secondary volumes to `"storage"` (1.7T HDD) or `"media"` (2.6T HDD).
*   `horus-pmx-srv02` -> Maps fast SSD arrays to `"data-pg"` (860G SSD for databases) or `"data-ai"` (410G SSD for AI weights).
*   `horus-pmx-srv03` -> Maps backup partitions to `"data"` (430G HDD for MinIO S3 bucket data).

### 3. Zero-Leak Runtime Secret Injection
The infrastructure isolates credentials strictly. Root passwords for LXCs and VMs are read dynamically from a local workspace file (`root_password.txt`) during execution. Because this file is explicitly ignored by `.gitignore`, secrets never touch git history or remote state files.

### 4. VLAN and Network Segmentation
Virtual adapters are bound directly to Proxmox Linux bridges (`vmbr0`) with specific `vlan_id` parameters to direct hosts into isolated broadcast security domains:
*   **VLAN 10 (Management):** Host interfaces, Vault, Ansible Engine.
*   **VLAN 20 (DMZ / Public Routing):** Perimeter access proxies, VPN tunnels.
*   **VLAN 30 (Internal Services):** CI/CD, database cluster, SSO Identity Provider, Gitea.
*   **VLAN 40 (Storage Network):** High-speed replication and S3 storage traffic.
*   **VLAN 50 (Observability / AIOps):** Prometheus, Grafana, Loki logs, OpenTelemetry, and AIOps engines.

---

## 🖥️ Cluster Layout & Resource Map

The infrastructure resources are distributed across the physical hypervisors to maximize efficiency and achieve perfect high-availability boundaries.

### 🚀 Host: `horus-pmx-srv01` (Compute, Build Pipelines, and Media Core)
| VMID | Name | Type | Vcpu | RAM | Storage / Datastore Mappings | Network / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | VM | 2 | 4GB | Cloud-init Template 9000 (Local-LVM) | Jenkins Master Orchestration |
| **102** | `horus-ai-srv01` | LXC | 4 | 4GB | 32G Root, Nvidia GPU Passthrough | Network AI Backend |
| **103** | `horus-ai-srv02` | LXC | 4 | 4GB | 32G Root + 420G mapped on `cameras` datastore | CV Cam Storage Backend |
| **104** | `horus-media-srv01` | LXC | 2 | 2GB | 16G Root + 1740G mapped on `storage` datastore | CasaOS Files & Media Server |
| **105** | `horus-media-srv02` | LXC | 4 | 4GB | 32G Root + 2662G mapped on `media` datastore | JoyFilm Server (NVENC enabled) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4GB | 40G Root Disk | Jenkins Heavy Pipeline Agent |
| **107** | `horus-gg-srv01` | LXC | 2 | 2GB | 20G Root Disk | GitGuardian CLI / TruffleHog / Trivy scanner (Isolated) |

### 🔒 Host: `horus-pmx-srv02` (Identity, Core Services, and Structured Storage)
| VMID | Name | Type | Vcpu | RAM | Storage / Datastore Mappings | Network / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2GB | 20G Root Disk | Authentik IAM & Single Sign-On |
| **202** | `horus-git-srv01` | LXC | 2 | 2GB | 20G Root Disk | Gitea Private Source Repository |
| **203** | `horus-vlt-srv01` | VM | 2 | 2GB | Cloud-init Template 9000 (Memory-Locked) | HashiCorp Vault Secrets |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1GB | 15G Root Disk | Wiki.js System Documentation |
| **205** | `horus-db-srv01` | LXC | 2 | 4GB | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) nested | PostgreSQL 18 Cluster Database |
| **206** | `horus-reg-srv01` | LXC | 2 | 4GB | 40G Root Disk | Harbor Container Registry |
| **207** | `horus-ans-srv01` | LXC | 2 | 4GB | 30G Root Disk | Ansible SRE Automation Engine |
| **208** | `horus-ai-srv03` | LXC | 4 | 8GB | 32G Root + 410G SSD mapped on `data-ai` | Heavy AI Assistant (Mimir Engine) |

### 📊 Host: `horus-pmx-srv03` (Observability, Metrics, and Object Storage)
| VMID | Name | Type | Vcpu | RAM | Storage / Datastore Mappings | Network / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1GB | 10G Root Disk | Grafana Metric Visualizers |
| **302** | `horus-pm-srv01` | LXC | 2 | 2GB | 15G Root Disk | Prometheus TSDB Metrics Hub |
| **303** | `horus-lok-srv01` | LXC | 2 | 2GB | 15G Root Disk | Loki & Alertmanager Cluster Log Hub |
| **304** | `horus-otel-srv01` | LXC | 1 | 1GB | 5G Root Disk | OpenTelemetry Collector Hub |
| **305** | `horus-s3-srv01` | LXC | 2 | 2GB | 40G Root + 430G HDD mapped on `data` datastore | MinIO S3 Scalable Object Storage |
| **306** | `horus-ai-srv04` | LXC | 4 | 4GB | 32G Root Disk | AI Operations Engine (AIOps Engine) |

---

## 📂 Repository Structure

```text
HoRus-Bootstrap/
├── .gitignore                  # Excludes passwords, state files, and local variables
├── main.tf                     # Main cluster topology and module definitions
├── variables.tf                # Global Terraform variables
├── providers.tf                # Proxmox VE provider configuration (bpg/proxmox)
├── ARCHITECTURE.md             # Cluster Architectural Passport (VLANs, Node map)
├── BACKLOG.md                  # Development roadmap and outstanding tasks
├── LICENSE                     # Project license
├── modules/                    # Reusable infrastructure blocks
│   ├── proxmox_lxc/            # Module for unprivileged Linux Containers (LXC)
│   │   ├── main.tf             # LXC resource definition with dynamic disk and MAC calculations
│   │   └── variables.tf        # LXC-specific input variables
│   └── proxmox_vm/             # Module for Full Virtual Machines (KVM/VM)
│       ├── main.tf             # VM resource definition using cloud-init template 9000
│       └── variables.tf        # VM-specific input variables
└── README.md                   # Core project documentation
```

---

## 🚀 Execution & Deployment Guide (Cross-Platform)

Follow these instructions to provision the infrastructure of your home lab from any device under any operating system.

### Prerequisites (All Platforms)
1.  **Generate SSH Keys:** Create your administration credentials on your personal computer:
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Generate Proxmox API Token:** Go to your Proxmox VE UI (`Datacenter -> Permissions -> API Tokens`) and generate a token for user `root@pam` with name `terraform`. Make sure to copy the secret!

---

### Step-by-Step Installation

#### 🐧 1. Deployment from GNU/Linux & macOS
Open your terminal and execute the following commands:

*   **Install Terraform:**
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

*   **Setup Secrets & Variables:**
    ```bash
    # Create the root password file for containers and VMs (Git-ignored)
    echo "SuperSecretPass123!" > root_password.txt

    # Initialize variables template
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    Edit `terraform.tfvars` with your text editor (e.g., `nano` or `vim`) and add:
    ```hcl
    pmx_api_url    = "https://<PROXMOX_IP>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=your-token-uuid-secret"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Initialize & Deploy:**
    ```bash
    # Download providers and configure environment
    terraform init

    # Dry-run execution review
    terraform plan

    # Apply configuration to Proxmox VE
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Deployment from Windows (CMD or PowerShell)
Open standard CMD or Windows Terminal (PowerShell) as Administrator:

*   **Install Terraform:**
    ```powershell
    # Using Chocolatey package manager
    choco install terraform -y

    # OR using Winget
    winget install HashiCorp.Terraform
    ```

*   **Setup Secrets & Variables:**
    ```powershell
    # Create password file inside workspace
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # Create local variables file
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    Open `terraform.tfvars` in Notepad or VS Code and enter your credentials:
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=your-token-uuid-secret"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Initialize & Deploy:**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. Deployment from Windows Subsystem for Linux (WSL)
If you prefer running a native Linux environment inside Windows:

*   **Configure WSL Terminal:**
    Install and open your Ubuntu/Debian WSL distribution, then map your Windows SSH directory:
    ```bash
    # Link administrative SSH directory (if keys reside on Windows host)
    ln -s /mnt/c/Users/<WindowsUsername>/.ssh ~/.ssh
    ```

*   **Follow the GNU/Linux deployment flow:**
    Copy and run the **GNU/Linux & macOS** step-by-step commands listed above inside the WSL console. Terraform will run inside WSL and call the Proxmox cluster over your local bridge network transparently.

---

## 🔒 Security Practices & Compliance

1.  **State File Security:**
    Terraform state files (`terraform.tfstate`) contain raw passwords, system properties, and API tokens. **Never commit them to version control.** They are excluded via `.gitignore`. For production environments, utilize an encrypted remote backend (e.g., Gitlab Managed State, HashiCorp Consul, or S3 with SSE).
2.  **Unprivileged LXC Layout:**
    All LXC deployments run inside unprivileged containers (`unprivileged = true`), guaranteeing that if a malicious process breaks out of a containerized service, it cannot acquire root privileges on the underlying bare-metal Proxmox hypervisor.
3.  **Encrypted KVM Memory Range:**
    The Jenkins and Vault virtual machines run on dedicated Virtual Machines with hardware-backed virtualization protections, which prevents other sibling nodes from reading or altering secure runtime parameters.

---

## 📄 License & Ownership

This project is licensed under the **Apache License 2.0** - see the [LICENSE](LICENSE) file for details.

*   **Project Owner & Proprietor:** Aleksei Savelev (alias **Alex Benden**)
*   **Company & Project Brand:** Benden-SysLab
*   **Email Contact:** bendenalex@gmail.com
*   **Telegram Support:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

