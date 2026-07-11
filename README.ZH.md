# HoRus Bootstrap (SRE 家庭实验室核心基础架构编排引擎 - 2026年中)

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

**HoRus-Bootstrap** 是一个基于声明式基础设施即代码（IaC）的配置引擎，专门用于私有 SRE 家庭实验室的**初始编排、拓扑定义和虚拟化布局**。该项目使用 **Terraform** 以及现代化的 `bpg/proxmox` 驱动，能够在三个物理 Proxmox VE 虚拟化管理平台（`horus-pmx-srv01`、`horus-pmx-srv02` 和 `horus-pmx-srv03`）上自动化部署无特权 Linux 容器（LXC）和全虚拟化虚拟机（KVM/VM）。

相比之下，**HoRus-Control-Plane** 仓库负责系统启动后的操作系统安全加固、软件包安装（Podman、数据库等）以及应用程序部署；而 **HoRus-Bootstrap** 则专门定义底层的虚拟硬件结构——分配 CPU 核心、配置内存限制、挂载物理存储盘、绑定网络接口以及划分安全域。

---

## 🛠️ 核心架构模式与特性

### 1. 确定性 MAC 地址分配（避免网络冲突）
为了彻底消除 DHCP 冲突并防止 MAC 地址重复，系统会根据资源的 `vmid` 动态计算网卡的物理 MAC 地址。如果在变量中没有显式提供 MAC 地址，系统将应用如下确定性十六进制计算公式：
```text
BC:24:11:00:[VMID 百位数]:[VMID 剩余数]
```
例如：
*   `vmid = 101` (Jenkins Master 虚拟机) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault 密码虚拟机) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3 容器) -> `BC:24:11:00:03:05`

### 2. 智能存储数据源矩阵（Datastore）
由于不同物理 Proxmox 节点上的物理磁盘空间各不相同，Terraform 配置在模块内部利用了局部映射字典 (`local.node_datastores`)，实现目标存储池的动态解析：
*   `horus-pmx-srv01` -> 辅助存储卷映射至 `"storage"` (1.7T HDD) 或 `"media"` (2.6T HDD)。
*   `horus-pmx-srv02` -> 数据库存储映射至高速 SSD 阵列 `"data-pg"` (数据库专用 860G SSD) 或 `"data-ai"` (AI模型权重专用 410G SSD)。
*   `horus-pmx-srv03` -> 备份分区映射至 `"data"` (MinIO S3 对象存储专用 430G HDD)。

### 3. 运行期零泄露机密注入
整个基础架构对凭据和密码的管理非常严格。LXC 容器和 VM 虚拟机的 root 密码将在运行期间从本地工作区文件（`root_password.txt`）中动态读取。由于该文件已在 `.gitignore` 中显式排除，敏感凭据绝对不会进入 Git 历史提交或远程状态（State）文件中。

### 4. VLAN 网络安全隔离
虚拟网卡直接绑定到 Proxmox Linux 网桥（`vmbr0`），并通过特定 `vlan_id` 参数将主机分流至互相隔离的广播安全域：
*   **VLAN 10 (Management 管理网):** PVE物理机接口、Vault、Ansible 自动化引擎。
*   **VLAN 20 (DMZ / 公网路由):** 边缘接入反向代理、VPN 隧道。
*   **VLAN 30 (Internal Services 内部服务):** CI/CD 流水线、数据库集群、SSO 统一身份提供商、Gitea。
*   **VLAN 40 (Storage Network 存储网):** 高速复制及 MinIO S3 存储网络。
*   **VLAN 50 (Observability / AIOps 监控运维):** Prometheus、Grafana、Loki 日志、OpenTelemetry 和 AIOps 智能诊断引擎。

---

## 🖥️ 实验室集群布局与资源分配表

虚拟化资源经过精心计算并分布在不同的物理虚拟化主机上，以在确保高效运算的同时，达成高可用的业务安全边界。

### 🚀 物理节点：`horus-pmx-srv01` (计算、流水线构建和媒体核心)
| VMID | 节点名称 | 类型 | 核心数 | 内存 | 存储 / 挂载映射 (Datastore) | 系统角色与网络分区 |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | VM | 2 | 4GB | Cloud-init 模板 9000 (Local-LVM) | Jenkins Master 自动化编排 |
| **102** | `horus-ai-srv01` | LXC | 4 | 4GB | 32G 系统盘, Nvidia GPU 直通挂载 | 网络 AI 智能后台 |
| **103** | `horus-ai-srv02` | LXC | 4 | 4GB | 32G 系统盘 + 挂载 `cameras` 存储池下的 420G 卷 | 摄像头计算机视觉处理后端 |
| **104** | `horus-media-srv01` | LXC | 2 | 2GB | 16G 系统盘 + 挂载 `storage` 存储池下的 1740G 卷 | CasaOS 文件和媒体服务中心 |
| **105** | `horus-media-srv02` | LXC | 4 | 4GB | 32G 系统盘 + 挂载 `media` 存储池下的 2662G 卷 | JoyFilm 媒体服务器 (支持 NVENC 硬解) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4GB | 40G 系统盘卷 | Jenkins 高负载构建执行节点 |
| **107** | `horus-gg-srv01` | LXC | 2 | 2GB | 20G 系统盘卷 | GitGuardian CLI / TruffleHog / Trivy 安全扫描器 (隔离) |

### 🔒 物理节点：`horus-pmx-srv02` (身份认证、核心服务及 SSD 快速存储盘)
| VMID | 节点名称 | 类型 | 核心数 | 内存 | 存储 / 挂载映射 (Datastore) | 系统角色与网络分区 |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2GB | 20G 系统盘卷 | Authentik IAM & 统一单点登录服务 |
| **202** | `horus-git-srv01` | LXC | 2 | 2GB | 20G 系统盘卷 | Gitea 内部私有代码版本控制库 |
| **203** | `horus-vlt-srv01` | VM | 2 | 2GB | Cloud-init 模板 9000 (启用内存锁定保护) | HashiCorp Vault 密码安全保险箱 |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1GB | 15G 系统盘卷 | Wiki.js 系统和架构文档库 |
| **205** | `horus-db-srv01` | LXC | 2 | 4GB | 30G 系统盘 + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) 嵌套挂载 | PostgreSQL 18 核心高可用数据库集群 |
| **206** | `horus-reg-srv01` | LXC | 2 | 4GB | 40G 系统盘卷 | Harbor 私有容器镜像仓库 |
| **207** | `horus-ans-srv01` | LXC | 2 | 4GB | 30G 系统盘卷 | Ansible SRE 自动化执行引擎节点 |
| **208** | `horus-ai-srv03` | LXC | 4 | 8GB | 32G 系统盘 + 挂载 `data-ai` 下的 410G SSD | 轻量模型推理助手 (Mimir MML) |

### 📊 物理节点：`horus-pmx-srv03` (可观测性监控、指标分析和 S3 对象存储)
| VMID | 节点名称 | 类型 | 核心数 | 内存 | 存储 / 挂载映射 (Datastore) | 系统角色与网络分区 |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1GB | 10G 系统盘卷 | Grafana 运维数据仪表盘 |
| **302** | `horus-pm-srv01` | LXC | 2 | 2GB | 15G 系统盘卷 | Prometheus 时序数据存储网关 |
| **303** | `horus-lok-srv01` | LXC | 2 | 2GB | 15G 系统盘卷 | Loki 日志分析 & Alertmanager 告警路由 |
| **304** | `horus-otel-srv01` | LXC | 1 | 1GB | 5G 系统盘卷 | OpenTelemetry 链路数据收集分配器 |
| **305** | `horus-s3-srv01` | LXC | 2 | 2GB | 40G 系统盘 + 挂载 `data` 下的 430G HDD | MinIO S3 本地高吞吐对象存储 |
| **306** | `horus-ai-ops01` | LXC | 4 | 4GB | 32G 系统盘卷 | AI Operations 运维异常自动诊断引擎 (AIOps) |

---

## 📂 仓库代码结构

```text
HoRus-Bootstrap/
├── .gitignore                  # 忽略临时状态文件、密钥以及本地配置文件
├── main.tf                     # 核心拓扑规划与各应用模块实例化配置
├── variables.tf                # 全局 Terraform 输入变量声明
├── providers.tf                # Proxmox VE 驱动配置 (bpg/proxmox 供应商)
├── ARCHITECTURE.md             # 集群架构护照白皮书 (VLAN 隔离、物理节点规划)
├── BACKLOG.md                  # 开发线路图以及未完成的任务清单
├── LICENSE                     # 项目许可证说明
├── modules/                    # 可复用基础架构构建块
│   ├── proxmox_lxc/            # 无特权 Linux 容器模块 (LXC)
│   │   ├── main.tf             # LXC 资源定义，内置动态 MAC、磁盘配额公式
│   │   └── variables.tf        # LXC 专用输入参数定义
│   └── proxmox_vm/             # KVM 全虚拟化虚拟机模块 (VM)
│       ├── main.tf             # 虚拟机资源声明，使用云初始化模版 9000
│       └── variables.tf        # 虚拟机专用输入参数定义
└── README.md                   # 核心基础框架使用手册
```

---

## 🚀 多操作系统快速额定部署指南 (Cross-Platform)

遵循以下各平台对应的指令，在您的个人客户端设备上快速启动这一 SRE 基础设施编排。

### 前期基础准备（所有平台通用）
1.  **生成管理 SSH 密钥对：**
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **生成 Proxmox API 令牌：** 访问您的 Proxmox VE Web 控制台（`Datacenter 数据中心 -> Permissions 权限 -> API Tokens API令牌`），为 `root@pam` 生成一个名为 `terraform` 的令牌。请务必拷贝并记录下最终生成的令牌密钥！

---

### 分系统部署详细说明

#### 🐧 1. 在 GNU/Linux 和 macOS 系统下部署
打开您的系统终端控制台，依次执行以下命令：

*   **安装 Terraform：**
    *   *Debian/Ubuntu 体系 :*
        ```bash
        sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update && sudo apt-get install terraform
        ```
    *   *macOS (使用 Homebrew 包管理器) :*
        ```bash
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
        ```

*   **配置敏感凭据与本地变量参数：**
    ```bash
    # 创建虚拟机的默认 root 管理密码 (此文件在 Git 忽略列表内)
    echo "SuperSecretPass123!" > root_password.txt

    # 生成变量配置文件
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    使用文本编辑器（例如 `nano` 或 `vim`）修改 `terraform.tfvars`，填入您的真实集群数据：
    ```hcl
    pmx_api_url    = "https://<PROXMOX_PVE主机IP>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=您的API令牌UUID机密内容"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **初始化并执行部署：**
    ```bash
    # 自动下载供应商所需的驱动库
    terraform init

    # 进行编排前的配置校对与模拟预演
    terraform plan

    # 将基础设施直接下发部署到 ProxmoxVE 集群
    terraform apply -auto-approve
    ```

---

#### 🪟 2. 在 Windows 宿主机下部署 (使用 CMD 或 PowerShell)
以管理员身份启动 Windows Terminal (PowerShell) 或传统的命令提示符 (CMD) 控制台：

*   **安装 Terraform：**
    ```powershell
    # 使用 Chocolatey 包管理器快速安装
    choco install terraform -y

    # 或者使用 Windows 自带的 Winget
    winget install HashiCorp.Terraform
    ```

*   **配置敏感凭据与本地变量参数：**
    ```powershell
    # 写入虚拟机密码文件至工作空间中
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # 创建变量配置变量
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    在 Notepad 记事本或者 VS Code 编辑器中打开 `terraform.tfvars`，在其中填充如下基础参数：
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=您的API令牌UUID机密内容"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **初始化并执行部署：**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. 在 Windows 适用于 Linux 的子系统 (WSL) 内部署
如果您希望在 Windows 主机上保留并使用纯粹的原生 Linux 系统交互体验：

*   **配置 WSL 终端环境：**
    启动您的 WSL 容器发行版（例如 Ubuntu），将 Windows 下现成的 SSH 文件夹挂载过来：
    ```bash
    # 如果管理密钥文件存放在 Windows 目录下，建立对应符号链接
    ln -s /mnt/c/Users/<Windows用户名称>/.ssh ~/.ssh
    ```

*   **参照执行 Linux 终端流程：**
    直接在 WSL 窗口控制台内复制并运行本指南上方的 **GNU/Linux 和 macOS** 体系部署指令。Terraform 将完美运行于 WSL 内部，并通过本地虚拟网桥向 ProxmoxVE 集群发出控制指令。

---

## 🔒 生产级安全实践与 SRE 符合度

1.  **Terraform 状态文件保密：**
    Terraform 的状态管理文件 (`terraform.tfstate`) 在设计上包含明文敏感数据和密钥，**严禁将其推送到任何 Git 代码库中！** 本项目已在 `.gitignore` 内进行了过滤。在生产级架构中，推荐将其存储到受加密保护的远程后端（例如 GitLab 托管状态存储、HashiCorp Consul，或启用 SSE 加密保护的 S3 对象 bucket 中）。
2.  **默认启用无特权容器技术：**
    所有 LXC 实例的实例化声明中都强制附加了 `unprivileged = true`，从而确保即使某个容器内的微服务不幸被突破，攻击者也绝对无法通过底层内核逃逸技术危害 Proxmox 宿主物理机。
3.  **内存物理隔离防护：**
    对于存储敏感核心数据的 Jenkins 虚拟机和 Vault 秘密虚拟机，资源池声明完全建立在专属的 KVM 虚拟机体系上，配置物理内存锁定。即使同物理机上有其他容器崩溃或受损，它们也完全无法越权读取或篡改这两台重要设备的内存参数。

---

## 📄 许可证与所有权

本项目采用 **Apache License 2.0** 许可证进行授权 - 详情请参阅 [LICENSE](LICENSE) 文件。

*   **项目所有者与产权人：** Aleksei Savelev (别名 **Alex Benden**)
*   **公司与项目品牌：** Benden-SysLab
*   **电子邮件联系方式：** bendenalex@gmail.com
*   **Telegram 支持群组/联系人：** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

