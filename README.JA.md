# HoRus Bootstrap (SREプライベートホームラボ基礎インフラプロビジョニングエンジン - 2026年中期)

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

このリポジトリ、**HoRus-Bootstrap**は、プライベートなSREホームラボクラスターの**初期オーケストレーション、トポロジ定義、および仮想化レイアウト**のために設計された、宣言型のInfrastructure-as-Code（IaC）プロビジョニングエンジンです。**Terraform**と最新の`bpg/proxmox`プロバイダーを使用し、3台の物理的なProxmox VEハイパーバイザー（`horus-pmx-srv01`、`horus-pmx-srv02`、`horus-pmx-srv03`）上で、特権のないLinuxコンテナ（LXC）と仮想マシン（KVM/VM）のデプロイを自動化します。

**HoRus-Control-Plane**リポジトリが起動後のOSセキュリティ強化、パッケージ設定（Podman、データベース）、およびアプリケーションのデプロイを担当するのに対し、**HoRus-Bootstrap**は、CPUコア、メモリ制限、ストレージマウント、ネットワークインターフェースバインディング、セキュリティゾーンの割り当てなど、基盤となる仮想ハードウェア構造を定義します。

---

## 🛠️ 主なアーキテクチャパターンと機能

### 1. 決定論的MACアドレス生成
DHCP競合を完全に排除し、重複するMACアドレスを防ぐために、システムはリソースの`vmid`に基づいてハードウェアMACアドレスを動的に算出します。変数から明示的なMACアドレスが提供されない場合、以下の決定論的パターンが適用されます。
```text
BC:24:11:00:[VMIDの百の位]:[VMIDの残り]
```
例：
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. インテリジェントなデータストアマトリックス
Proxmoxホストごとに物理ディスクスペースが異なります。Terraform構成は、モジュール内のローカルマッピングディクショナリ（`local.node_datastores`）を利用して、データストアターゲットを動的に解決します。
*   `horus-pmx-srv01` -> セカンダリボリュームを`"storage"`（1.7T HDD）または`"media"`（2.6T HDD）にマッピング。
*   `horus-pmx-srv02` -> データベース用高速SSDを`"data-pg"`（データベース用860G SSD）または`"data-ai"`（AIモデル用410G SSD）にマッピング。
*   `horus-pmx-srv03` -> バックアップパーティションを`"data"`（MinIO S3用430G HDD）にマッピング。

### 3. ランタイムでの機密情報注入
LXCおよびVM用のrootパスワードは、実行中にローカルファイル（`root_password.txt`）から動的に読み込まれます。このファイルは`.gitignore`で明示的に除外されているため、パスワードなどの機密情報がGitの履歴やリモート状態（State）ファイルに記録されることはありません。

### 4. VLANとネットワークセグメンテーション
仮想アダプターは、特定の`vlan_id`を指定してProxmoxブリッジ（`vmbr0`）にバインドされ、分離されたネットワークセキュリティドメインに配置されます。
*   **VLAN 10 (Management):** ホスト管理用インターフェース、Vault、Ansibleエンジン。
*   **VLAN 20 (DMZ / Public Routing):** リバースプロキシ、VPNトンネル。
*   **VLAN 30 (Services):** CI/CD、データベースクラスター、SSO認証（Authentik）、Gitea。
*   **VLAN 40 (Storage Network):** 高速レプリケーションおよびMinIO S3ストレージ。
*   **VLAN 50 (Observability / AIOps):** Prometheus、Grafana、Lokiログ、OpenTelemetry、AIOpsエンジン。

---

## 🖥️ クラスター構成とリソースマップ

仮想化リソースは、物理的なハイパーバイザー間で最適に分散され、高い効率とセキュリティ境界を維持します。

### 🚀 ホスト: `horus-pmx-srv01` (計算、ビルドパイプライン、メディアコア)
| VMID | サーバー名 | タイプ | vCPU | RAM | ストレージ / データストアマッピング | ネットワーク / システム役割 |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | VM | 2 | 4GB | Cloud-init テンプレート 9000 (Local-LVM) | Jenkins Masterビルド制御 |
| **102** | `horus-ai-srv01` | LXC | 4 | 4GB | 32G Root, Nvidia GPUパススルー | ネットワークAIバックエンド |
| **103** | `horus-ai-srv02` | LXC | 4 | 4GB | 32G Root + `cameras`データストア上の420Gマウント | コンピュータビジョン監視バックエンド |
| **104** | `horus-media-srv01` | LXC | 2 | 2GB | 16G Root + `storage`データストア上の1740Gマウント | CasaOS ファイル&メディアサーバー |
| **105** | `horus-media-srv02` | LXC | 4 | 4GB | 32G Root + `media`データストア上の2662Gマウント | JoyFilm サーバー (NVENCハードウェアエンコード) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4GB | 40G ルートディスク | Jenkins パイプライン実行用エージェント |
| **107** | `horus-gg-srv01` | LXC | 2 | 2GB | 20G ルートディスク | GitGuardian CLI / TruffleHog / Trivy スキャナー (分離) |

### 🔒 ホスト: `horus-pmx-srv02` (アイデンティティ、主要サービス、SSDデータストア)
| VMID | サーバー名 | タイプ | vCPU | RAM | ストレージ / データストアマッピング | ネットワーク / システム役割 |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2GB | 20G ルートディスク | Authentik SSO シングルサインオン |
| **202** | `horus-git-srv01` | LXC | 2 | 2GB | 20G ルートディスク | Gitea 自社ホストGitリポジトリ |
| **203** | `horus-vlt-srv01` | VM | 2 | 2GB | Cloud-init テンプレート 9000 (メモリロック保護) | HashiCorp Vault 鍵・シークレット管理 |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1GB | 15G ルートディスク | Wiki.js システムナレッジベース |
| **205** | `horus-db-srv01` | LXC | 2 | 4GB | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) 入れ子マウント | PostgreSQL 18 クラスタデータベース |
| **206** | `horus-reg-srv01` | LXC | 2 | 4GB | 40G ルートディスク | Harbor コンテナレジストリ |
| **207** | `horus-ans-srv01` | LXC | 2 | 4GB | 30G ルートディスク | Ansible 自動化制御ノード |
| **208** | `horus-ai-srv03` | LXC | 4 | 8GB | 32G Root + `data-ai` SSD上の410Gマウント | AIアシスタント (Mimir Engine) |

### 📊 ホスト: `horus-pmx-srv03` (可観測性、メトリクス、S3オブジェクトストレージ)
| VMID | サーバー名 | タイプ | vCPU | RAM | ストレージ / データストアマッピング | ネットワーク / システム役割 |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1GB | 10G ルートディスク | Grafana メトリクス・ログ可視化 |
| **302** | `horus-pm-srv01` | LXC | 2 | 2GB | 15G ルートディスク | Prometheus メトリクス監視ハブ |
| **303** | `horus-lok-srv01` | LXC | 2 | 2GB | 15G ルートディスク | Loki & Alertmanager ログ中央ハブ |
| **304** | `horus-otel-srv01` | LXC | 1 | 1GB | 5G ルートディスク | OpenTelemetry コレクターハブ |
| **305** | `horus-s3-srv01` | LXC | 2 | 2GB | 40G Root + `data` HDD上の430Gマウント | MinIO S3 オブジェクトストレージ |
| **306** | `horus-ai-ops01` | LXC | 4 | 4GB | 32G ルートディスク | AI Operations Engine (AIOps 障害検知) |

---

## 📂 リポジトリ構造

```text
HoRus-Bootstrap/
├── .gitignore                  # パスワード、ステートファイル、ローカル変数をGitから除外
├── main.tf                     # メインのトポロジーおよびモジュール呼び出し定義
├── variables.tf                # グローバルTerraform変数
├── providers.tf                # Proxmox VEプロバイダー設定 (bpg/proxmox)
├── ARCHITECTURE.md             # アーキテクチャパスポート (VLAN、ノードマップ)
├── BACKLOG.md                  # ロードマップと今後の開発タスク
├── LICENSE                     # プロジェクトライセンス
├── modules/                    # 再利用可能なインフラストラクチャモジュール
│   ├── proxmox_lxc/            # 特権なし Linuxコンテナ (LXC) 用モジュール
│   │   ├── main.tf             # MACアドレス動的計算とLXCリソース定義
│   │   └── variables.tf        # LXC専用入力変数
│   └── proxmox_vm/             # 仮想マシン (KVM/VM) 用モジュール
│       ├── main.tf             # テンプレート9000に基づくVMリソース定義
│       └── variables.tf        # VM専用入力変数
└── README.md                   # メインシステムドキュメント
```

---

## 🚀 実行＆デプロイガイド (マルチプラットフォーム対応)

お使いのパーソナルPCのOS（Linux、macOS、Windows）に合わせて、以下の手順でインフラ構築を行えます。

### 事前準備 (全プラットフォーム共通)
1.  **管理用SSHキーの生成:**
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Proxmox APIトークンの発行:** Proxmox VEのウェブ管理画面にログインし、`データセンター -> アクセス制御 -> APIトークン` から `root@pam` 用に名前 `terraform` でトークンを作成し、シークレットトークンをコピーして保存してください。

---

### ステップ・バイ・ステップ導入手順

#### 🐧 1. GNU/Linux & macOS からのデプロイ
ターミナルを開き、以下のコマンドを実行します。

*   **Terraformのインストール:**
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

*   **秘密鍵と変数の設定:**
    ```bash
    # LXC/VM用rootパスワードファイルの作成 (Git無視対象)
    echo "SuperSecretPass123!" > root_password.txt

    # 変数テンプレートファイルのコピー
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    `terraform.tfvars` をお好みのエディタ（`nano` や `vim` など）で編集し、実際のネットワーク環境に合わせて以下を入力します。
    ```hcl
    pmx_api_url    = "https://<PROXMOX_IP>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=あなたのトークンUUIDシークレット"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **実行:**
    ```bash
    # プロバイダーのダウンロードと環境設定
    terraform init

    # 事前確認 (ドライラン)
    terraform plan

    # Proxmox VEへの変更適用
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Windows (PowerShell または CMD) からのデプロイ
管理者としてPowerShellまたはコマンドプロンプトを開きます。

*   **Terraformのインストール:**
    ```powershell
    # Chocolateyパッケージマネージャーを使用する場合
    choco install terraform -y

    # または Winget を使用する場合
    winget install HashiCorp.Terraform
    ```

*   **秘密鍵と変数の設定:**
    ```powershell
    # ワークスペース内にroot用パスワードファイルを作成
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # 新しい変数ファイルを初期作成
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    `terraform.tfvars` をメモ帳やVS Codeなどで開き、以下の接続情報を入力します。
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=あなたのトークンUUIDシークレット"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **実行:**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. WSL (Windows Subsystem for Linux) からのデプロイ
Windows上で動作するLinux環境をお好みの場合：

*   **WSLの接続設定:**
    WSLターミナル（例：Ubuntu）を開き、WindowsホストのSSHキーフォルダとシンボリックリンクを作成します。
    ```bash
    # WindowsホストにSSHキーが存在する場合
    ln -s /mnt/c/Users/<Windowsユーザー名>/.ssh ~/.ssh
    ```

*   **Linuxデプロイの流れに従う:**
    上記の **GNU/Linux & macOS** セクションに記載されているステップバイステップコマンドを、WSLターミナルから直接実行します。TerraformはWSL環境で透過的に動作し、ローカルブリッジ経由でProxmoxクラスターのAPIを呼び出します。

---

## 🔒 セキュリティプラクティスとSREコンプライアンス

1.  **ステートファイルの保護:**
    Terraformの状態管理ファイル（`terraform.tfstate`）には、暗号化されていないシークレットやトークンがそのまま含まれます。**Gitには絶対にコミットしないでください。** このリポジトリでは`.gitignore`により除外されています。本番環境では、暗号化されたリモートバックエンド（GitLab Managed State、HashiCorp Consul、あるいはSSEを有効化したS3バケットなど）の使用を強く推奨します。
2.  **特権なしLXCの使用:**
    作成されるコンテナ（LXC）はすべて非特権コンテナとして定義されます（`unprivileged = true`）。これにより、万が一特定のアプリケーションがセキュリティ侵害を受けた場合でも、ホストマシン（Proxmox VE）のルート権限を奪取されるのを防ぐことができます。
3.  **仮想マシンのメモリ空間分離:**
    Jenkins MasterやVaultなどの重要ノードは、専用のKVM仮想マシン上でハードウェア仮想化保護を受け、物理メモリ領域を固定して動作するため、クラスター内の他のノードからメモリ空間が不正に読み取られるのを完全に防止します。

---

## 📄 ライセンスと所有権

このプロジェクトは **Apache License 2.0** のもとでライセンスされています。詳細は [LICENSE](LICENSE) ファイルを参照してください。

*   **プロジェクト所有者兼権利者:** Aleksei Savelev (エイリアス **Alex Benden**)
*   **会社名およびプロジェクトブランド:** Benden-SysLab
*   **メールアドレス:** bendenalex@gmail.com
*   **Telegram サポート:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

