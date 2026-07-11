# HoRus Bootstrap (SRE Home Lab Core Provisioning Engine - Meados de 2026)

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

Este repositório, **HoRus-Bootstrap**, é o motor de provisionamento declarativo baseado em Infrastructure-as-Code (IaC) projetado para a **orquestração inicial, definição de topologia e design de virtualização** de um Home Lab SRE privado. Construído utilizando **Terraform** e o provedor moderno `bpg/proxmox`, ele automatiza o provisionamento de contêineres Linux não privilegiados (LXC) e máquinas virtuais (KVM/VM) através de três hipervisores físicos Proxmox VE em cluster (`horus-pmx-srv01`, `horus-pmx-srv02`, `horus-pmx-srv03`).

Enquanto o repositório **HoRus-Control-Plane** se encarrega do endurecimento do sistema operacional pós-inicialização, instalação de pacotes (Podman, bancos de dados) e deploy de aplicações, o **HoRus-Bootstrap** define a estrutura de hardware virtual subjacente — alocando núcleos de CPU, limites de memória, pontos de montagem de armazenamento, vinculações de interfaces de rede e zonas de segurança.

---

## 🛠️ Padrões Arquiteturais e Recursos Chave

### 1. Endereçamento MAC Determinístico
Para eliminar conflitos de alocação de DHCP e evitar endereços MAC duplicados, o sistema calcula os endereços de hardware de forma dinâmica com base no identificador `vmid` usando a seguinte fórmula:
```text
BC:24:11:00:[Centenas do VMID]:[Resto do VMID]
```
Exemplos:
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. Matriz Inteligente de Armazenamento (Datastore)
O espaço de disco físico varia entre os hosts Proxmox. A configuração do Terraform utiliza um dicionário de mapeamento local (`local.node_datastores`) para resolver dinamicamente os destinos de armazenamento:
*   `horus-pmx-srv01` -> Mapeia volumes secundários para `"storage"` (HDD de 1.7T) ou `"media"` (HDD de 2.6T).
*   `horus-pmx-srv02` -> Mapeia arrays SSD rápidos para `"data-pg"` (SSD de 860G para bancos de dados) ou `"data-ai"` (SSD de 410G para pesos de IA).
*   `horus-pmx-srv03` -> Mapeia partições de backup para `"data"` (HDD de 430G para armazenamento de objetos MinIO S3).

### 3. Injeção Segura de Segredos em Tempo de Execução (Runtime)
As senhas de root para LXC e VMs são lidas dinamicamente a partir de um arquivo de workspace local (`root_password.txt`) durante a execução. Como este arquivo é explicitamente ignorado através do `.gitignore`, os segredos nunca tocam o histórico do git ou os arquivos de estado remotos.

### 4. VLAN e Segmentação de Rede
Os adaptadores virtuais são vinculados diretamente às bridges Linux Proxmox (`vmbr0`) com parâmetros específicos de `vlan_id` para direcionar os hosts a domínios de segurança broadcast isolados:
*   **VLAN 10 (Management):** Interfaces de host, Vault, motor Ansible.
*   **VLAN 20 (DMZ / Roteamento público):** Proxies de acesso perimetral, túneis VPN.
*   **VLAN 30 (Serviços internos):** CI/CD, banco de dados, provedor de identidade SSO, Gitea.
*   **VLAN 40 (Rede de armazenamento):** Replicação de alta velocidade e tráfego de armazenamento S3.
*   **VLAN 50 (Observabilidade / AIOps):** Prometheus, Grafana, logs do Loki, OpenTelemetry e motores de AIOps.

---

## 🖥️ Topologia do Cluster e Alocação de Recursos

Os recursos de virtualização são distribuídos entre os hipervisores físicos para maximizar a eficiência e garantir limites perfeitos de alta disponibilidade.

### 🚀 Host: `horus-pmx-srv01` (Computação, Pipelines de Build e Núcleo de Mídia)
| VMID | Nome | Tipo | vCPU | RAM | Mapeamentos de Armazenamento (Datastore) | Rede / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | VM | 2 | 4GB | Template Cloud-init 9000 (Local-LVM) | Orquestração Jenkins Master |
| **102** | `horus-ai-srv01` | LXC | 4 | 4GB | 32G Root, Nvidia GPU Passthrough | Backend de IA de rede |
| **103** | `horus-ai-srv02` | LXC | 4 | 4GB | 32G Root + 420G mapeado no datastore `cameras` | Armazenamento de vídeo de câmeras de CV |
| **104** | `horus-media-srv01` | LXC | 2 | 2GB | 16G Root + 1740G mapeado no datastore `storage` | Servidor de arquivos CasaOS |
| **105** | `horus-media-srv02` | LXC | 4 | 4GB | 32G Root + 2662G mapeado no datastore `media` | Servidor JoyFilm (NVENC habilitado) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4GB | Disco raiz de 40G | Agente de pipeline pesado do Jenkins |
| **107** | `horus-gg-srv01` | LXC | 2 | 2GB | Disco raiz de 20G | Scanner GitGuardian CLI / TruffleHog / Trivy (Isolado) |

### 🔒 Host: `horus-pmx-srv02` (Identidade, Serviços Essenciais e SSD rápido)
| VMID | Nome | Tipo | vCPU | RAM | Mapeamentos de Armazenamento (Datastore) | Rede / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2GB | Disco raiz de 20G | Authentik IAM & Single Sign-On |
| **202** | `horus-git-srv01` | LXC | 2 | 2GB | Disco raiz de 20G | Repositório privado Gitea |
| **203** | `horus-vlt-srv01` | VM | 2 | 2GB | Template Cloud-init 9000 (Memória bloqueada) | Segredos HashiCorp Vault |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1GB | Disco raiz de 15G | Documentação de Wiki.js |
| **205** | `horus-db-srv01` | LXC | 2 | 4GB | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) aninhado | Cluster de banco de dados PostgreSQL 18 |
| **206** | `horus-reg-srv01` | LXC | 2 | 4GB | Disco raiz de 40G | Registro de contêineres Harbor |
| **207** | `horus-ans-srv01` | LXC | 2 | 4GB | Disco raiz de 30G | Motor de automatização Ansible |
| **208** | `horus-ai-srv03` | LXC | 4 | 8GB | 32G Root + 410G SSD mapeado em `data-ai` | Assistente de IA (Mimir Engine) |

### 📊 Host: `horus-pmx-srv03` (Observabilidade, Métricas e armazenamento S3)
| VMID | Nome | Tipo | vCPU | RAM | Mapeamentos de Armazenamento (Datastore) | Rede / Roles |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1GB | Disco raiz de 10G | Visualizador de métricas Grafana |
| **302** | `horus-pm-srv01` | LXC | 2 | 2GB | Disco raiz de 15G | Hub de métricas Prometheus TSDB |
| **303** | `horus-lok-srv01` | LXC | 2 | 2GB | Disco raiz de 15G | Hub de logs Loki e Alertmanager |
| **304** | `horus-otel-srv01` | LXC | 1 | 1GB | Disco raiz de 5G | Hub de coleta OpenTelemetry |
| **305** | `horus-s3-srv01` | LXC | 2 | 2GB | 40G Root + 430G HDD mapeado em `data` | Armazenamento de objetos MinIO S3 |
| **306** | `horus-ai-ops01` | LXC | 4 | 4GB | Disco raiz de 32G | Motor de operações de IA (AIOps) |

---

## 📂 Estrutura do Repositório

```text
HoRus-Bootstrap/
├── .gitignore                  # Exclui arquivos de estado e variáveis locais
├── main.tf                     # Ficheiro de topologia principal e definição de módulos
├── variables.tf                # Variáveis globais do Terraform
├── providers.tf                # Configuração do provedor Proxmox VE (bpg/proxmox)
├── ARCHITECTURE.md             # Passaporte arquitetural (VLANs, mapa de nós)
├── BACKLOG.md                  # Roadmap de desenvolvimento e tarefas pendentes
├── LICENSE                     # Licença do projeto
├── modules/                    # Módulos de infraestrutura reutilizáveis
│   ├── proxmox_lxc/            # Módulo para contêineres Linux não privilegiados (LXC)
│   │   ├── main.tf             # Definição de recursos LXC com cálculos dinâmicos de MAC
│   │   └── variables.tf        # Variáveis de entrada específicas para LXC
│   └── proxmox_vm/             # Módulo para máquinas virtuais (KVM/VM)
│       ├── main.tf             # Definição de recursos VM baseados em template 9000
│       └── variables.tf        # Variáveis de entrada específicas para VM
└── README.md                   # Documentação principal do repositório
```

---

## 🚀 Guia de Execução e Despliegue (Multiplataforma)

Siga estas instruções para provisionar a infraestrutura do seu laboratório doméstico a partir de qualquer dispositivo sob qualquer sistema operacional.

### Pré-requisitos (Todas as plataformas)
1.  **Gerar Chaves SSH:** Crie suas credenciais administrativas no seu computador pessoal:
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Gerar Token de API do Proxmox:** Vá na UI do Proxmox VE (`Datacenter -> Permissions -> API Tokens`) e gere um token para o usuário `root@pam` com o nome `terraform`. Certifique-se de copiar o segredo!

---

### Instalação Passo a Passo

#### 🐧 1. Deploy a partir do GNU/Linux e macOS
Abra o seu terminal e execute os seguintes comandos:

*   **Instalar o Terraform:**
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

*   **Configurar variáveis locais e segredos:**
    ```bash
    # Criar o arquivo de senha root das VM/LXC (ignorado no git)
    echo "SuperSecretPass123!" > root_password.txt

    # Inicializar template de variáveis
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    Edite o `terraform.tfvars` no seu editor de texto preferido e insira suas credenciais:
    ```hcl
    pmx_api_url    = "https://<PROXMOX_IP>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=seu-segredo-uuid-token"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Inicializar e provisionar:**
    ```bash
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Deploy a partir do Windows (PowerShell ou CMD)
Abra o Windows Terminal (PowerShell) ou o Prompt de Comando (CMD) como Administrador:

*   **Instalar o Terraform:**
    ```powershell
    # Utilizando o gerenciador de pacotes Chocolatey
    choco install terraform -y

    # OU utilizando o Winget
    winget install HashiCorp.Terraform
    ```

*   **Configurar variáveis locais e segredos:**
    ```powershell
    # Criar o arquivo de senhas root na área de trabalho
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # Criar o arquivo de variáveis local
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    Abra o `terraform.tfvars` no Bloco de Notas ou VS Code e insira seus dados:
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=seu-segredo-uuid-token"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Inicializar e provisionar:**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. Deploy a partir do Windows Subsystem for Linux (WSL)
Se você preferir executar um ambiente Linux nativo dentro do Windows:

*   **Configurar o terminal do WSL:**
    Abra seu console de distribuição do WSL (ex: Ubuntu) e linke suas chaves SSH do Windows:
    ```bash
    ln -s /mnt/c/Users/<WindowsUsername>/.ssh ~/.ssh
    ```

*   **Seguir os passos de GNU/Linux e macOS:**
    Simplesmente copie e execute as instruções indicadas para **GNU/Linux e macOS** dentro de seu terminal WSL. O Terraform operará de maneira nativa dentro do WSL e efetuará as chamadas ao Proxmox através de sua rede local.

---

## 🔒 Práticas de Segurança e SRE Compliance

1.  **Segurança do arquivo de estado (State):**
    Os arquivos de estado do Terraform (`terraform.tfstate`) contêm senhas e tokens de API em texto plano. **Nunca envie-os para repositórios públicos.** Eles são excluídos automaticamente através do `.gitignore`. Em ambientes de produção, use um backend remoto seguro e criptografado (como GitLab Managed State, Consul ou S3 com SSE).
2.  **Contêineres não Privilegiados:**
    Todos os deploys de contêineres LXC são executados em modo não privilegiado (`unprivileged = true`). Isso garante que, se um serviço containerizado for comprometido, o atacante não poderá escalar privilégios no host bare-metal do Proxmox VE.
3.  **Isolamento Estrito de Memória RAM:**
    As máquinas virtuais críticas (Vault, Jenkins) são executadas em ambientes KVM com limites de hardware estritos e bloqueio de páginas de memória RAM, prevenindo leituras não autorizadas a partir de outros nós do hipervisor.

---

## 📄 Licença e propriedade

Este projeto está licenciado sob a **Apache License 2.0** - consulte o arquivo [LICENSE](LICENSE) para obter mais detalhes.

*   **Proprietário e titular do projeto:** Aleksei Savelev (pseudônimo **Alex Benden**)
*   **Empresa e marca do projeto:** Benden-SysLab
*   **Contato por e-mail:** bendenalex@gmail.com
*   **Suporte via Telegram:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

