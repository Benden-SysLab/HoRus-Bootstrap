# HoRus Bootstrap (SRE Home Lab Core Provisioning Engine - Mitte 2026)

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

Dieses Repository, **HoRus-Bootstrap**, ist die deklarative Infrastructure-as-Code (IaC) Bereitstellungs-Engine, die für die **initiale Orchestrierung, Topologiedefinition und das Virtualisierungs-Layout** eines privaten SRE Home Labs entwickelt wurde. Basierend auf **Terraform** und dem modernen Provider `bpg/proxmox` automatisiert es die Bereitstellung von unprivilegierten Linux-Containern (LXC) und virtuellen Maschinen (KVM/VM) auf drei geclusterten physischen Proxmox VE-Hypervisoren (`horus-pmx-srv01`, `horus-pmx-srv02`, `horus-pmx-srv03`).

Während das Repository **HoRus-Control-Plane** für die anschließende Betriebssystemhärtung, Paketinstallation (Podman, Datenbanken) und Anwendungsbereitstellung zuständig ist, definiert **HoRus-Bootstrap** die zugrunde liegende Hardwarestruktur – einschließlich Zuweisung von CPU-Kernen, Speichergrenzen, Storage-Mounts, Netzwerkschnittstellen und Sicherheitszonen.

---

## 🛠️ Wichtige Architekturmuster & Funktionen

### 1. Deterministische MAC-Adressierung
Zur Vermeidung von DHCP-Konflikten berechnet das System die Hardware-Adressen dynamisch auf der Grundlage der Ressourcen-ID (`vmid`). Wenn keine explizite MAC-Adresse übergeben wird, gilt folgende Formel:
```text
BC:24:11:00:[VMID Hunderter]:[VMID Rest]
```
Beispiele:
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. Intelligente Speicher- / Datastore-Matrix
Der physische Speicherplatz unterscheidet sich je nach Proxmox-Host. Die Terraform-Konfiguration verwendet eine lokale Zuordnungstabelle (`local.node_datastores`), um Speicherziele dynamisch aufzulösen:
*   `horus-pmx-srv01` -> Sekundäre Volumes zeigen auf `"storage"` (1.7T HDD) oder `"media"` (2.6T HDD).
*   `horus-pmx-srv02` -> Datenbanken werden auf schnellen SSD-Arrays `"data-pg"` (SSD 860G) oder `"data-ai"` (SSD 410G) abgelegt.
*   `horus-pmx-srv03` -> Backup-Partitionen verweisen auf `"data"` (430G HDD für S3 MinIO).

### 3. Sichere Laufzeit-Geheimnisinjektion
Root-Passwörter für LXCs und VMs werden zur Laufzeit dynamisch aus einer lokalen Datei (`root_password.txt`) eingelesen. Da diese Datei durch `.gitignore` ausgeschlossen ist, gelangen Geheimnisse niemals in den Git-Verlauf oder Remote-State-Dateien.

### 4. VLAN- und Netzwerksegmentierung
Virtuelle Netzwerkkarten werden direkt an Proxmox-Bridges (`vmbr0`) mit spezifischen `vlan_id`-Parametern gebunden, um die Hosts in isolierte Broadcast-Sicherheitsdomänen zu unterteilen:
*   **VLAN 10 (Management):** Host-Schnittstellen, Vault, Ansible Engine.
*   **VLAN 20 (DMZ / Öffentliches Routing):** Perimeter-Access-Proxies, VPN-Tunnel.
*   **VLAN 30 (Dienste):** CI/CD, Datenbankcluster, SSO-Identitätsanbieter, Gitea.
*   **VLAN 40 (Speichernetzwerk):** Replikation und S3-Speicherverkehr.
*   **VLAN 50 (Observability / AIOps):** Prometheus, Grafana, Loki-Protokolle, OpenTelemetry und AIOps-Engines.

---

## 🖥️ Cluster-Layout & Ressourcenkarte

Die Virtualisierungsressourcen sind auf die physischen Hypervisoren verteilt, um die Effizienz zu maximieren und perfekte Hochverfügbarkeitsgrenzen zu gewährleisten.

### 🚀 Host: `horus-pmx-srv01` (Compute, Build-Pipelines, Media Core)
| VMID | Name | Typ | vCPU | RAM | Storage / Datastore Mappings | Netzwerk / Rollen |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | VM | 2 | 4GB | Cloud-init Template 9000 (Local-LVM) | Jenkins Master Orchestrierung |
| **102** | `horus-ai-srv01` | LXC | 4 | 4GB | 32G Root, Nvidia GPU Passthrough | Netzwerk KI Backend |
| **103** | `horus-ai-srv02` | LXC | 4 | 4GB | 32G Root + 420G gemountet auf `cameras` | Kamera-Überwachungsspeicher |
| **104** | `horus-media-srv01` | LXC | 2 | 2GB | 16G Root + 1740G gemountet auf `storage` | CasaOS-Dateiserver |
| **105** | `horus-media-srv02` | LXC | 4 | 4GB | 32G Root + 2662G gemountet auf `media` | JoyFilm-Server (mit NVENC) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4GB | 40G Root-Disk | Jenkins Pipeline-Agent |
| **107** | `horus-gg-srv01` | LXC | 2 | 2GB | 20G Root-Disk | GitGuardian CLI / TruffleHog / Trivy Scanner (Isoliert) |

### 🔒 Host: `horus-pmx-srv02` (Identity, Core Services, SSD-Daten)
| VMID | Name | Typ | vCPU | RAM | Storage / Datastore Mappings | Netzwerk / Rollen |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2GB | 20G Root-Disk | Authentik IAM & Single Sign-On |
| **202** | `horus-git-srv01` | LXC | 2 | 2GB | 20G Root-Disk | Gitea Private Code-Repository |
| **203** | `horus-vlt-srv01` | VM | 2 | 2GB | Cloud-init Template 9000 (Memory-Locked) | HashiCorp Vault Secrets |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1GB | 15G Root-Disk | Wiki.js Systemdokumentation |
| **205** | `horus-db-srv01` | LXC | 2 | 4GB | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) geschachtelt | PostgreSQL 18 Datenbankcluster |
| **206** | `horus-reg-srv01` | LXC | 2 | 4GB | 40G Root-Disk | Harbor Container Registry |
| **207** | `horus-ans-srv01` | LXC | 2 | 4GB | 30G Root-Disk | Ansible SRE Automatisierung |
| **208** | `horus-ai-srv03` | LXC | 4 | 8GB | 32G Root + 410G SSD gemountet auf `data-ai` | KI-Assistent (Mimir-Engine) |

### 📊 Host: `horus-pmx-srv03` (Observability, Metrics, S3 Storage)
| VMID | Name | Typ | vCPU | RAM | Storage / Datastore Mappings | Netzwerk / Rollen |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1GB | 10G Root-Disk | Grafana Metrik-Visualisierung |
| **302** | `horus-pm-srv01` | LXC | 2 | 2GB | 15G Root-Disk | Prometheus Metrik-Zentrale |
| **303** | `horus-lok-srv01` | LXC | 2 | 2GB | 15G Root-Disk | Loki & Alertmanager Log-Zentrale |
| **304** | `horus-otel-srv01` | LXC | 1 | 1GB | 5G Root-Disk | OpenTelemetry Collector Hub |
| **305** | `horus-s3-srv01` | LXC | 2 | 2GB | 40G Root + 430G HDD gemountet auf `data` | MinIO S3 Objektspeicher |
| **306** | `horus-ai-ops01` | LXC | 4 | 4GB | 32G Root-Disk | AI Operations Engine (AIOps) |

---

## 📂 Repository-Struktur

```text
HoRus-Bootstrap/
├── .gitignore                  # Schließt State-Dateien und lokale Passwörter aus
├── main.tf                     # Haupt-Topologiedatei und Modulinstanzen
├── variables.tf                # Globale Terraform-Variablen
├── providers.tf                # Proxmox VE-Providerkonfiguration (bpg/proxmox)
├── ARCHITECTURE.md             # Architektur-Handbuch (VLANs, Knotenkarte)
├── BACKLOG.md                  # Roadmap und offene Aufgaben
├── LICENSE                     # Projektlizenz
├── modules/                    # Wiederverwendbare Bausteine
│   ├── proxmox_lxc/            # Modul für unprivilegierte Linux-Container (LXC)
│   │   ├── main.tf             # LXC-Ressourcendefinition mit dynamischer MAC-Berechnung
│   │   └── variables.tf        # LXC-spezifische Eingabevariablen
│   └── proxmox_vm/             # Modul für virtuelle Maschinen (KVM/VM)
│       ├── main.tf             # VM-Ressourcendefinition auf Basis von Template 9000
│       └── variables.tf        # VM-spezifische Eingabevariablen
└── README.md                   # Hauptdokumentation
```

---

## 🚀 Ausführungs- & Bereitstellungshandbuch (Cross-Platform)

Folgen Sie diesen Anweisungen, um die Infrastruktur Ihres Home Labs von jedem Gerät und unter jedem Betriebssystem aus bereitzustellen.

### Voraussetzungen (Alle Plattformen)
1.  **SSH-Schlüssel generieren:**
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Proxmox API-Token erstellen:** Gehen Sie im Proxmox VE Web-UI auf `Rechenzentrum -> Berechtigungen -> API-Token` und erstellen Sie einen Token für `root@pam` mit dem Namen `terraform`. Kopieren Sie den Secret-Schlüssel!

---

### Schritt-für-Schritt-Anleitung

#### 🐧 1. Bereitstellung unter GNU/Linux & macOS
Öffnen Sie Ihr Terminal und führen Sie folgende Befehle aus:

*   **Terraform installieren:**
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

*   **Geheimnisse & Variablen einrichten:**
    ```bash
    # Root-Passwort-Datei für LXCs/VMs erstellen (Git-ignored)
    echo "SuperSecretPass123!" > root_password.txt

    # Variable-Datei kopieren
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    Bearbeiten Sie `terraform.tfvars` und tragen Sie Ihre Werte ein:
    ```hcl
    pmx_api_url    = "https://<PROXMOX_IP>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=ihr-token-secret"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Initialisieren & Bereitstellen:**
    ```bash
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Bereitstellung unter Windows (CMD oder PowerShell)
Öffnen Sie die Windows-Eingabeaufforderung (CMD) oder PowerShell als Administrator:

*   **Terraform installieren:**
    ```powershell
    # Über den Paketmanager Chocolatey
    choco install terraform -y

    # ODER über Winget
    winget install HashiCorp.Terraform
    ```

*   **Geheimnisse & Variablen einrichten:**
    ```powershell
    # Passwortdatei im Workspace erstellen
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # Neue Variablen-Datei anlegen
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    Öffnen Sie `terraform.tfvars` im Editor und tragen Sie Ihre Daten ein:
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=ihr-token-secret"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Ausführen:**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. Bereitstellung unter Windows Subsystem for Linux (WSL)
Falls Sie eine native Linux-Umgebung innerhalb von Windows bevorzugen:

*   **WSL-Terminal einrichten:**
    Starten Sie Ihre WSL-Konsole (z.B. Ubuntu) und verknüpfen Sie Ihren Windows-SSH-Ordner:
    ```bash
    ln -s /mnt/c/Users/<WindowsUsername>/.ssh ~/.ssh
    ```

*   **Linux-Anleitung befolgen:**
    Führen Sie die Befehle aus dem Abschnitt **GNU/Linux & macOS** direkt in Ihrer WSL-Konsole aus. Terraform läuft unter WSL und spricht den Proxmox-Cluster über Ihre Netzwerkbrücke an.

---

## 🔒 Sicherheitsrichtlinien & SRE-Konformität

1.  **State-Datei-Sicherheit:**
    Terraform State-Dateien (`terraform.tfstate`) enthalten sensible Daten im Klartext. **Niemals in Git einchecken!** Sie sind über `.gitignore` ausgeschlossen. Für produktive Szenarien wird ein verschlüsseltes Remote-Backend empfohlen (z.B. GitLab Managed State, Consul oder S3 mit SSE).
2.  **Unprivilegierter LXC-Modus:**
    Alle Container laufen im unprivilegierten Modus (`unprivileged = true`). Sollte ein Dienst kompromittiert werden, erhält der Angreifer keinen Root-Zugriff auf den Bare-Metal-Hypervisor.
3.  **Speicher-Isolierung für kritische VMs:**
    Sicherheitskritische VMs (Vault, Jenkins) laufen als KVM-Instanzen mit fest zugewiesenem, hardwareverschlüsseltem RAM-Bereich, um ein unbefugtes Auslesen durch Nachbarinstanzen zu verhindern.

---

## 📄 Lizenz & Eigentum

Dieses Projekt ist unter der **Apache-Lizenz 2.0** lizenziert – siehe die Datei [LICENSE](LICENSE) für Details.

*   **Projekteigentümer & Inhaber:** Aleksei Savelev (Pseudonym **Alex Benden**)
*   **Unternehmen & Projektmarke:** Benden-SysLab
*   **E-Mail-Kontakt:** bendenalex@gmail.com
*   **Telegram-Support:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

