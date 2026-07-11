# HoRus Bootstrap (SRE Home Lab Core Provisioning Engine - Mi-2026)

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

Ce dépôt, **HoRus-Bootstrap**, est le moteur de provisionnement déclaratif de type Infrastructure-as-Code (IaC) conçu pour **l'orchestration initiale, la définition de la topologie et la configuration de virtualisation** d'un laboratoire SRE privé. S'appuyant sur **Terraform** et le fournisseur moderne `bpg/proxmox`, il automatise le déploiement de conteneurs Linux non privilégiés (LXC) et de machines virtuelles (KVM/VM) sur trois hyperviseurs physiques Proxmox VE en grappe (`horus-pmx-srv01`, `horus-pmx-srv02`, `horus-pmx-srv03`).

Tandis que le dépôt **HoRus-Control-Plane** est chargé du durcissement du système d'exploitation post-démarrage, de la configuration des paquets (Podman, bases de données) et du déploiement des applications, **HoRus-Bootstrap** définit la structure matérielle virtuelle sous-jacente — allocation des cœurs de processeur, limites de mémoire, points de montage de stockage, liaisons d'interfaces réseau et zones de sécurité.

---

## 🛠️ Modèles architecturaux et caractéristiques clés

### 1. Adressage MAC déterministe
Pour éliminer les conflits d'attribution DHCP et éviter les adresses MAC en double, le système calcule dynamiquement les adresses matérielles en se basant sur l'identifiant de ressource `vmid` selon la formule suivante :
```text
BC:24:11:00:[Centaines du VMID]:[Reste du VMID]
```
Exemples :
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. Matrice intelligente de stockage (Datastore)
L'espace disque physique varie selon l'hôte Proxmox. La configuration Terraform utilise un dictionnaire de mappage local (`local.node_datastores`) pour résoudre dynamiquement les cibles de stockage :
*   `horus-pmx-srv01` -> Mappe les volumes secondaires vers `"storage"` (Disque dur 1.7T) ou `"media"` (Disque dur 2.6T).
*   `horus-pmx-srv02` -> Mappe les grappes SSD rapides vers `"data-pg"` (SSD 860G pour les bases de données) ou `"data-ai"` (SSD 410G pour les poids d'IA).
*   `horus-pmx-srv03` -> Mappe les partitions de sauvegarde vers `"data"` (Disque dur 430G pour le stockage objet MinIO S3).

### 3. Injection sécurisée des secrets d'exécution
Les mots de passe root pour les LXC et les machines virtuelles sont lus dynamiquement à partir d'un fichier d'espace de travail local (`root_password.txt`) pendant l'exécution. Comme ce fichier est exclu par `.gitignore`, les secrets ne touchent jamais l'historique git ou les fichiers d'état distants.

### 4. VLAN et segmentation réseau
Les adaptateurs virtuels sont directement liés aux ponts Linux Proxmox (`vmbr0`) avec des paramètres `vlan_id` spécifiques pour diriger les hôtes vers des domaines de sécurité isolés :
*   **VLAN 10 (Management):** Interfaces hôtes, Vault, moteur Ansible.
*   **VLAN 20 (DMZ / Routage public):** Proxys d'accès périmétriques, tunnels VPN.
*   **VLAN 30 (Services internes):** CI/CD, base de données, fournisseur d'identité SSO, Gitea.
*   **VLAN 40 (Réseau de stockage):** Réplication à grande vitesse et trafic de stockage S3.
*   **VLAN 50 (Observabilité / AIOps):** Prometheus, Grafana, journaux Loki, OpenTelemetry et moteurs AIOps.

---

## 🖥️ Topologie du cluster et allocation des ressources

Les ressources de virtualisation sont réparties sur les hyperviseurs physiques pour maximiser l'efficacité et garantir des limites parfaites de haute disponibilité.

### 🚀 Hôte : `horus-pmx-srv01` (Calcul, Pipelines, et Noyau Média)
| VMID | Nom | Type | vCPU | RAM | Mappages de stockage (Datastore) | Rôle / Fonction réseau |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | VM | 2 | 4Go | Modèle Cloud-init 9000 (Local-LVM) | Orchestration Jenkins Master |
| **102** | `horus-ai-srv01` | LXC | 4 | 4Go | 32G Root, Nvidia GPU Passthrough | Backend d'IA réseau |
| **103** | `horus-ai-srv02` | LXC | 4 | 4Go | 32G Root + 420G mappé sur `cameras` | Stockage vidéo de surveillance |
| **104** | `horus-media-srv01` | LXC | 2 | 2Go | 16G Root + 1740G mappé sur `storage` | Serveur de fichiers CasaOS |
| **105** | `horus-media-srv02` | LXC | 4 | 4Go | 32G Root + 2662G mappé sur `media` | Serveur JoyFilm (NVENC activé) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4Go | Disque racine 40G | Agent lourd Jenkins Pipeline |
| **107** | `horus-gg-srv01` | LXC | 2 | 2Go | Disque racine 20G | Scanner GitGuardian CLI / TruffleHog / Trivy (Isolé) |

### 🔒 Hôte : `horus-pmx-srv02` (Identité, Services de base, et SSD)
| VMID | Nom | Type | vCPU | RAM | Mappages de stockage (Datastore) | Rôle / Fonction réseau |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2Go | Disque racine 20G | Authentik IAM & Single Sign-On |
| **202** | `horus-git-srv01` | LXC | 2 | 2Go | Disque racine 20G | Dépôt de code privé Gitea |
| **203** | `horus-vlt-srv01` | VM | 2 | 2Go | Modèle Cloud-init 9000 (Mémoire verrouillée) | Secrets HashiCorp Vault |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1Go | Disque racine 15G | Documentation système Wiki.js |
| **205** | `horus-db-srv01` | LXC | 2 | 4Go | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) imbriqué | Base de données PostgreSQL 18 |
| **206** | `horus-reg-srv01` | LXC | 2 | 4Go | Disque racine 40G | Registre de conteneurs Harbor |
| **207** | `horus-ans-srv01` | LXC | 2 | 4Go | Disque racine 30G | Moteur d'automatisation Ansible |
| **208** | `horus-ai-srv03` | LXC | 4 | 8Go | 32G Root + 410G SSD mappé sur `data-ai` | Assistant d'IA (Moteur Mimir) |

### 📊 Hôte : `horus-pmx-srv03` (Observabilité, Métriques, et Stockage S3)
| VMID | Nom | Type | vCPU | RAM | Mappages de stockage (Datastore) | Rôle / Fonction réseau |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1Go | Disque racine 10G | Visualisation des métriques Grafana |
| **302** | `horus-pm-srv01` | LXC | 2 | 2Go | Disque racine 15G | Hub de métriques Prometheus TSDB |
| **303** | `horus-lok-srv01` | LXC | 2 | 2Go | Disque racine 15G | Hub de journaux Loki & Alertmanager |
| **304** | `horus-otel-srv01` | LXC | 1 | 1Go | Disque racine 5G | Concentrateur OpenTelemetry |
| **305** | `horus-s3-srv01` | LXC | 2 | 2Go | 40G Root + 430G HDD mappé sur `data` | Stockage d'objets MinIO S3 |
| **306** | `horus-ai-ops01` | LXC | 4 | 4Go | Disque racine 32G | Moteur d'opérations d'IA (AIOps) |

---

## 📂 Structure du dépôt

```text
HoRus-Bootstrap/
├── .gitignore                  # Exclut les fichiers d'état et les mots de passe locaux
├── main.tf                     # Fichier principal de la topologie et des modules
├── variables.tf                # Variables globales de Terraform
├── providers.tf                # Configuration du fournisseur Proxmox VE (bpg/proxmox)
├── ARCHITECTURE.md             # Passeport architectural (VLANs, carte des nœuds)
├── BACKLOG.md                  # Feuille de route du développement
├── LICENSE                     # Licence du projet
├── modules/                    # Composants d'infrastructure réutilisables
│   ├── proxmox_lxc/            # Module pour les conteneurs Linux non privilégiés (LXC)
│   │   ├── main.tf             # Définition des ressources LXC avec calcul d'adresses MAC
│   │   └── variables.tf        # Variables d'entrée spécifiques aux LXC
│   └── proxmox_vm/             # Module pour les machines virtuelles (KVM/VM)
│       ├── main.tf             # Définition des ressources VM basées sur le modèle 9000
│       └── variables.tf        # Variables d'entrée spécifiques aux VM
└── README.md                   # Documentation principale du projet
```

---

## 🚀 Guide d'exécution et de déploiement (Multi-Plateforme)

Suivez ces instructions pour provisionner l'infrastructure de votre laboratoire à partir de n'importe quel appareil sous n'importe quel système d'exploitation.

### Prérequis (Toutes plateformes)
1.  **Générer les clés SSH :**
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Créer un jeton d'API Proxmox :** Allez dans l'interface Web de Proxmox VE (`Centre de données -> Autorisations -> Jetons d'API`) et générez un jeton pour l'utilisateur `root@pam` nommé `terraform`. Veillez à copier la clé secrète !

---

### Déploiement étape par étape

#### 🐧 1. Déploiement depuis GNU/Linux & macOS
Ouvrez votre terminal et exécutez les commandes suivantes :

*   **Installer Terraform :**
    *   *Debian/Ubuntu :*
        ```bash
        sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update && sudo apt-get install terraform
        ```
    *   *macOS (Homebrew) :*
        ```bash
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
        ```

*   **Configurer les variables locales et secrets :**
    ```bash
    # Créer le fichier de mot de passe root (ignoré par Git)
    echo "SuperSecretPass123!" > root_password.txt

    # Copier le fichier de variables exemple
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    Modifiez le fichier `terraform.tfvars` avec vos informations réseau :
    ```hcl
    pmx_api_url    = "https://<IP_PROXMOX>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=votre-token-secret"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Initialiser et Déployer :**
    ```bash
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Déploiement depuis Windows (CMD ou PowerShell)
Ouvrez PowerShell ou l'invite de commande (CMD) en tant qu'administrateur :

*   **Installer Terraform :**
    ```powershell
    # Via le gestionnaire de paquets Chocolatey
    choco install terraform -y

    # OU via Winget
    winget install HashiCorp.Terraform
    ```

*   **Configurer les variables locales et secrets :**
    ```powershell
    # Créer le fichier de mot de passe root dans l'espace de travail
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # Créer le fichier de variables
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    Ouvrez `terraform.tfvars` dans le Bloc-notes (ou VS Code) et entrez vos données :
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=votre-token-secret"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Initialiser et Déployer :**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. Déploiement depuis Windows Subsystem for Linux (WSL)
Si vous préférez exécuter un environnement Linux natif dans Windows :

*   **Configurer le terminal WSL :**
    Ouvrez votre console WSL (ex. Ubuntu) et liez vos clés SSH de l'hôte Windows :
    ```bash
    ln -s /mnt/c/Users/<WindowsUsername>/.ssh ~/.ssh
    ```

*   **Suivre le flux GNU/Linux :**
    Exécutez simplement les commandes de la section **GNU/Linux & macOS** dans la console WSL. Terraform fonctionnera à l'intérieur de WSL et appellera le cluster Proxmox via le réseau ponté local.

---

## 🔒 Pratiques de sécurité et conformité SRE

1.  **Sécurité du fichier d'état (State) :**
    Le fichier d'état `terraform.tfstate` contient des jetons et mots de passe système en clair. **Ne le commitez jamais !** Il est exclu via `.gitignore`. Pour les déploiements de production, utilisez un backend distant sécurisé (comme GitLab Managed State, HashiCorp Consul ou S3 avec chiffrement SSE).
2.  **Conteneurs non privilégiés (LXC) :**
    Tous les conteneurs LXC s'exécutent en mode non privilégié (`unprivileged = true`). Ainsi, si un attaquant compromet un service conteneurisé, il ne peut pas obtenir les privilèges root sur l'hyperviseur Proxmox physique.
3.  **Isolation de la mémoire vive :**
    Les serveurs virtuels sensibles (Vault, Jenkins) fonctionnent comme des machines virtuelles KVM dédiées avec des limites RAM strictes et verrouillées en mémoire physique pour empêcher l'extraction de secrets par d'autres instances co-hébergées.

---

## 📄 Licence et propriété

Ce projet est sous licence **Apache License 2.0** - voir le fichier [LICENSE](LICENSE) pour plus de détails.

*   **Propriétaire et créateur du projet:** Aleksei Savelev (alias **Alex Benden**)
*   **Entreprise et marque du projet:** Benden-SysLab
*   **Contact e-mail:** bendenalex@gmail.com
*   **Support Telegram:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

