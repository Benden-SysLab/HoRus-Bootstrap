# HoRus Bootstrap (Ядро розгортання домашньої SRE-лабораторії — середина 2026 р.)

🌐 **Translations / Переводи / Translaciones / Übersetzungen / Traductions / Tradução / 翻译 / 翻訳:**
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

Репозиторій **HoRus-Bootstrap** є декларативним інструментом розгортання класу Infrastructure-as-Code (IaC). Він розроблений для **первинної оркестрації, розмітки топології та конфігурації віртуальної інфраструктури** приватного домашнього кластера. За допомогою **Terraform** та сучасного провайдера `bpg/proxmox` система автоматизує створення непривілейованих контейнерів Linux (LXC) та віртуальних машин (KVM/VM) на трьох фізичних гіпервізорах Proxmox VE (`horus-pmx-srv01`, `horus-pmx-srv02`, `horus-pmx-srv03`).

У той час як репозиторій **HoRus-Control-Plane** відповідає за фінальне налаштування ОС, встановлення пакетів (Podman, СУБД) та розгортання застосунків, **HoRus-Bootstrap** формує базовий апаратний каркас: виділяє ядра процесора, обмежує оперативну пам'ять, підключає дискові сховища та налаштовує мережеві інтерфейси в зонах безпеки.

---

## 🛠️ Основні архітектурні шаблони та особливості

### 1. Детермінований розрахунок MAC-адрес
Для запобігання конфліктам у DHCP-сервері та усунення ризику дублювання MAC-адрес система динамічно розраховує апаратні адреси на основі ідентифікатора `vmid` за такою формулою:
```text
BC:24:11:00:[сотні VMID]:[залишок VMID]
```
Приклади генерації:
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. Динамічна матриця сховищ (Datastore)
Конфігурація дисків на фізичних хостах відрізняється. Скрипти Terraform використовують внутрішній словник співставлень (`local.node_datastores`), щоб розподіляти розділи по цільових накопичувачах:
*   `horus-pmx-srv01` -> Диски монтуються у `"storage"` (HDD 1.7T) або `"media"` (HDD 2.6T).
*   `horus-pmx-srv02` -> Бази даних розподіляються на швидкі масиви SSD `"data-pg"` (СУБД, 860G) або `"data-ai"` (ваги штучного інтелекту, 410G).
*   `horus-pmx-srv03` -> Дані бакетів зберігаються в архівне сховище `"data"` (HDD 430G).

### 3. Безпечне впровадження секретів під час виконання (Runtime)
Паролі суперкористувача root для LXC та ВМ зчитуються «на льоту» з локального файлу проекту `root_password.txt`. Цей файл додано до списку виключень `.gitignore`, тому секрети ніколи не потрапляють в історію комітів та віддалений стан Terraform.

### 4. Мережева сегментація (VLAN)
Мережеві адаптери віртуальних середовищ підключаються безпосередньо до мережевих мостів Proxmox (`vmbr0`) із зазначенням конкретних `vlan_id`, розподіляючи хости по ізольованих широкомовних доменах безпеки:
*   **VLAN 10 (Management):** Інтерфейси Proxmox, SSH-доступ хостів, Vault, Ansible.
*   **VLAN 20 (DMZ / Public):** Вхідна точка мережі, зовнішні шлюзи VPN.
*   **VLAN 30 (Services):** Інфраструктурні сервіси, бази даних, медіа-ресурси.
*   **VLAN 40 (Storage):** Трафік резервного копіювання та S3-сховища MinIO.
*   **VLAN 50 (Monitoring):** Метрики, логи, трасування та ІІ-движки моніторингу.

---

## 🖥️ Карта розподілу ресурсів та вузлів

Ресурси віртуалізації збалансовані по фізичних хостах для забезпечення високої продуктивності та мінімізації накладних витрат.

### 🚀 Хост: `horus-pmx-srv01` (Обчислення, Важкий деплой, GPU + HDD)
| VMID | Ім'я вузла | Тип | Процесор | Пам'ять | Розділи та точки монтування (Datastore) | Роль у системі |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | ВМ | 2 | 4 ГБ | Шаблон Cloud-init 9000 (Local-LVM) | Jenkins Master (оркестрація) |
| **102** | `horus-ai-srv01` | LXC | 4 | 4 ГБ | 32G Root, Nvidia GPU Passthrough | Мережевий контроль та штучний інтелект |
| **103** | `horus-ai-srv02` | LXC | 4 | 4 ГБ | 32G Root + 420G монтується на датастор `cameras` | Камери, комп'ютерний зір |
| **104** | `horus-media-srv01` | LXC | 2 | 2 ГБ | 16G Root + 1740G монтується на датастор `storage` | Файловий сервер CasaOS |
| **105** | `horus-media-srv02` | LXC | 4 | 4 ГБ | 32G Root + 2662G монтується на датастор `media` | Медіасервер JoyFilm (NVENC) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4 ГБ | Диск Root 40G | Важкий білд-агент Jenkins |
| **107** | `horus-gg-srv01` | LXC | 2 | 2 ГБ | Диск Root 20G | GitGuardian CLI / TruffleHog / Trivy сканер (Ізольований) |

### 🔒 Хост: `horus-pmx-srv02` (Інфраструктурне ядро, IAM, Дані на SSD)
| VMID | Ім'я вузла | Тип | Процесор | Пам'ять | Розділи та точки монтування (Datastore) | Роль у системі |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2 ГБ | Диск Root 20G | SSO-авторизація (Authentik) |
| **202** | `horus-git-srv01` | LXC | 2 | 2 ГБ | Диск Root 20G | Gitea (Локальний Git-репозиторій) |
| **203** | `horus-vlt-srv01` | ВМ | 2 | 2 ГБ | Шаблон Cloud-init 9000 (Ізольована пам'ять) | Сховище секретів Vault |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1 ГБ | Диск Root 15G | Wiki.js (База знань) |
| **205** | `horus-db-srv01` | LXC | 2 | 4 ГБ | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) вкладені | Виділений PostgreSQL 18 |
| **206** | `horus-reg-srv01` | LXC | 2 | 4 ГБ | Диск Root 40G | Harbor Container Registry |
| **207** | `horus-ans-srv01` | LXC | 2 | 4 ГБ | Диск Root 30G | Локальний движок Ansible |
| **208** | `horus-ai-srv03` | LXC | 4 | 8 ГБ | 32G Root + 410G SSD монтується на `data-ai` | ІІ-асистент (Мімір) |

### 📊 Хост: `horus-pmx-srv03` (Мікросервісний стек спостережуваності та S3)
| VMID | Ім'я вузла | Тип | Процесор | Пам'ять | Розділи та точки монтування (Datastore) | Роль у системі |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1 ГБ | Диск Root 10G | Grafana (Візуалізація метрик) |
| **302** | `horus-pm-srv01` | LXC | 2 | 2 ГБ | Диск Root 15G | Prometheus (Збір метрик) |
| **303** | `horus-lok-srv01` | LXC | 2 | 2 ГБ | Диск Root 15G | Loki + Alertmanager (Логи) |
| **304** | `horus-otel-srv01` | LXC | 1 | 1 ГБ | Диск Root 5G | OpenTelemetry Collector |
| **305** | `horus-s3-srv01` | LXC | 2 | 2 ГБ | 40G Root + 430G HDD монтується на датастор `data` | Локальне S3-сховище MinIO |
| **306** | `horus-ai-ops01` | LXC | 4 | 4 ГБ | Диск Root 32G | AI Operations Engine (AIOps) |

---

## 📂 Структура репозиторію

```text
HoRus-Bootstrap/
├── .gitignore                  # Виключення (стан, паролі, змінні)
├── main.tf                     # Головний файл топології та виклику модулів
├── variables.tf                # Глобальні змінні Terraform
├── providers.tf                # Налаштування провайдера Proxmox VE (bpg/proxmox)
├── ARCHITECTURE.md             # Паспорт архітектури (VLAN, хости, мапінг)
├── BACKLOG.md                  # Список завдань та планів розвитку
├── LICENSE                     # Ліцензія проекту
├── modules/                    # Інфраструктурні модулі для перевикористання
│   ├── proxmox_lxc/            # Модуль непривілейованих контейнерів LXC
│   │   ├── main.tf             # Опис LXC ресурсів та розрахунок MAC-адреси
│   │   └── variables.tf        # Вхідні параметри для LXC
│   └── proxmox_vm/             # Модуль віртуальних машин KVM
│       ├── main.tf             # Опис ресурсів ВМ на базі шаблону 9000
│       └── variables.tf        # Вхідні параметри для ВМ
└── README.md                   # Основна документація проекту
```

---

## 🚀 Інструкція з розгортання на будь-якій ОС

Ви можете запустити процес розгортання зі свого робочого комп'ютера під керуванням будь-якої сучасної ОС.

### Підготовчі кроки (для всіх систем)
1.  **Створення SSH-ключів:** Згенеруйте пару ключів для доступу на своїй машині:
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Випуск API токена Proxmox:** Перейдіть у веб-інтерфейс Proxmox VE (`Datacenter -> Permissions -> API Tokens`), згенеруйте токен для користувача `root@pam` з ім'ям `terraform` та збережіть його секретну частину.

---

### Покроковий деплой по операційних системах

#### 🐧 1. Розгортання в ОС GNU/Linux та macOS
Відкрийте термінал та виконайте такі дії:

*   **Встановлення Terraform:**
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

*   **Налаштування змінних середовища та секретів:**
    ```bash
    # Створюємо файл із паролем суперкористувача (ігнорується в Git)
    echo "SuperSecretPass123!" > root_password.txt

    # Копіюємо шаблон змінних
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    Заповніть файл `terraform.tfvars` параметрами своєї мережі:
    ```hcl
    pmx_api_url    = "https://<IP_АДРЕС_PROXMOX>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=твій-секрет-токена"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Запуск ініціалізації та накату:**
    ```bash
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Розгортання у Windows (CMD або PowerShell)
Запустіть консоль PowerShell або Командний рядок від імені Адміністратора:

*   **Встановлення Terraform:**
    ```powershell
    # За допомогою менеджера пакетів Chocolatey
    choco install terraform -y

    # Або за допомогою Winget
    winget install HashiCorp.Terraform
    ```

*   **Налаштування змінних середовища та секретів:**
    ```powershell
    # Створюємо пароль root у корені проекту
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # Створюємо файл налаштувань
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    Відкрийте `terraform.tfvars` у Блокноті (або VS Code) та внесіть конфігураційні дані:
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=твій-секрет-токена"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Запуск команд:**
    ```powershell
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🐋 3. Розгортання за допомогою Windows Subsystem for Linux (WSL)
Якщо ви хочете використовувати рідне середовище Linux на Windows-комп'ютері:

*   **Налаштування інтеграції WSL:**
    Запустіть свій дистрибутив WSL (наприклад, Ubuntu) та зв'яжіть SSH-ключі Windows:
    ```bash
    # Посилання на ключі Windows (за їх наявності)
    ln -s /mnt/c/Users/<Ім'яКористувачаWindows>/.ssh ~/.ssh
    ```

*   **Виконання інструкцій:**
    Просто скопіюйте та запустіть команди з розділу **GNU/Linux та macOS** вище в консолі WSL. Terraform безперешкодно виконає виклики API Proxmox по внутрішній віртуальній мережі.

---

## 🔒 Безпека та відповідність SRE-практикам

1.  **Ізоляція файлів стану (State):**
    Файл `terraform.tfstate` зберігає системні токени та паролі у відкритому вигляді. **Ніколи не коммітьте його в Git!** Він надійно заблокований через `.gitignore`. У продуктових ландшафтах рекомендується використовувати захищені віддалені бекенди (Gitlab Managed State, HashiCorp Consul або S3 з SSE-шифруванням).
2.  **Непривілейовані середовища (Unprivileged LXC):**
    Контейнери запускаються в непривілейованому режимі (`unprivileged = true`), запобігаючи можливості компрометації хост-системи Proxmox VE при зломі окремих застосунків.
3.  **Ізоляція оперативної пам'яті ВМ:**
    Віртуальні машини для Jenkins та Vault використовують апаратну віртуалізацію та строгі ліміти, гарантуючи захист критично важливих секретів від атак з боку інших вузлів кластера.

---

## 📄 Ліцензія та права власності

Цей проєкт розповсюджується під ліцензією **Apache License 2.0** — детальніше див. у файлі [LICENSE](LICENSE).

*   **Власник та власник проєкту:** Олексій Савельєв (псевдонім **Alex Benden**)
*   **Компанія та бренд проєкту:** Benden-SysLab
*   **Електронна пошта:** bendenalex@gmail.com
*   **Telegram:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

