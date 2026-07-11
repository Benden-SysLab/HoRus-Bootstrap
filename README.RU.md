# HoRus Bootstrap (Ядро развертывания домашней SRE-лаборатории — середина 2026 г.)

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

Репозиторий **HoRus-Bootstrap** представляет собой декларативный инструмент развертывания класса Infrastructure-as-Code (IaC). Он разработан для **первоначальной оркестрации, разметки топологии и конфигурации виртуальной инфраструктуры** частного домашнего кластера. С помощью **Terraform** и современного провайдера `bpg/proxmox` система автоматизирует создание непривилегированных контейнеров Linux (LXC) и виртуальных машин (KVM/VM) на трех физических гипервизорах Proxmox VE (`horus-pmx-srv01`, `horus-pmx-srv02`, `horus-pmx-srv03`).

В то время как репозиторий **HoRus-Control-Plane** отвечает за финальную настройку ОС, установку пакетов (Podman, СУБД) и развертывание приложений, **HoRus-Bootstrap** формирует базовый аппаратный каркас: выделяет ядра процессора, ограничивает оперативную память, подключает дисковые хранилища и настраивает сетевые интерфейсы в зонах безопасности.

---

## 🛠️ Основные архитектурные шаблоны и особенности

### 1. Детерминированное вычисление MAC-адресов
Для исключения конфликтов в DHCP-сервере и устранения риска дублирования MAC-адресов система динамически рассчитывает аппаратные адреса на основе идентификатора `vmid` по следующей формуле:
```text
BC:24:11:00:[сотни VMID]:[остаток VMID]
```
Примеры генерации:
*   `vmid = 101` (Jenkins Master) -> `BC:24:11:00:01:01`
*   `vmid = 203` (HashiCorp Vault) -> `BC:24:11:00:02:03`
*   `vmid = 305` (MinIO S3) -> `BC:24:11:00:03:05`

### 2. Динамическая матрица хранилищ (Datastore)
Конфигурация дисков на физических хостах различается. Скрипты Terraform используют внутренний словарь сопоставлений (`local.node_datastores`), чтобы распределять разделы по целевым накопителям:
*   `horus-pmx-srv01` -> Диски монтируются в `"storage"` (HDD 1.7T) или `"media"` (HDD 2.6T).
*   `horus-pmx-srv02` -> Базы данных распределяются на быстрые массивы SSD `"data-pg"` (СУБД, 860G) или `"data-ai"` (ИИ-веса, 410G).
*   `horus-pmx-srv03` -> Данные бакетов сохраняются в архивное хранилище `"data"` (HDD 430G).

### 3. Безопасное внедрение секретов во время выполнения (Runtime)
Пароли суперпользователя root для LXC и ВМ считываются «на лету» из локального файла проекта `root_password.txt`. Данный файл добавлен в список исключений `.gitignore`, поэтому секреты не попадают в историю коммитов и удаленное состояние Terraform.

### 4. Сетевая сегментация (VLAN)
Сетевые адаптеры виртуальных сред подключаются напрямую к сетевым мостам Proxmox (`vmbr0`) с указанием конкретных `vlan_id`, распределяя хосты по изолированным широковещательным доменам безопасности:
*   **VLAN 10 (Management):** Интерфейсы Proxmox, SSH-доступ хостов, Vault, Ansible.
*   **VLAN 20 (DMZ / Public):** Входная точка сети, внешние шлюзы VPN.
*   **VLAN 30 (Services):** Инфраструктурные сервисы, базы данных, медиа-ресурсы.
*   **VLAN 40 (Storage):** Трафик резервного копирования и S3-хранилища MinIO.
*   **VLAN 50 (Monitoring):** Метрики, логи, трассировки и ИИ-движки мониторинга.

---

## 🖥️ Карта распределения ресурсов и узлов

Ресурсы виртуализации сбалансированы по физическим хостам для обеспечения высокой производительности и минимизации накладных расходов.

### 🚀 Хост: `horus-pmx-srv01` (Вычисления, Тяжелый деплой, GPU + HDD)
| VMID | Имя узла | Тип | Процессор | Память | Разделы и точки монтирования (Datastore) | Роль в системе |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **101** | `horus-jnk-srv01` | ВМ | 2 | 4 ГБ | Шаблон Cloud-init 9000 (Local-LVM) | Jenkins Master (оркестрация) |
| **102** | `horus-ai-srv01` | LXC | 4 | 4 ГБ | 32G Root, Nvidia GPU Passthrough | Сетевой контроль и ИИ-бэкенд |
| **103** | `horus-ai-srv02` | LXC | 4 | 4 ГБ | 32G Root + 420G монтируется на датастор `cameras` | Камеры, компьютерное зрение |
| **104** | `horus-media-srv01` | LXC | 2 | 2 ГБ | 16G Root + 1740G монтируется на датастор `storage` | Файловый сервер CasaOS |
| **105** | `horus-media-srv02` | LXC | 4 | 4 ГБ | 32G Root + 2662G монтируется на датастор `media` | Медиасервер JoyFilm (NVENC) |
| **106** | `horus-agent-srv01` | LXC | 4 | 4 ГБ | Диск Root 40G | Тяжелый билд-агент Jenkins |
| **107** | `horus-gg-srv01` | LXC | 2 | 2 ГБ | Диск Root 20G | GitGuardian CLI / TruffleHog / Trivy сканер (Изолирован) |

### 🔒 Хост: `horus-pmx-srv02` (Инфраструктурное ядро, IAM, Данные на SSD)
| VMID | Имя узла | Тип | Процессор | Память | Разделы и точки монтирования (Datastore) | Роль в системе |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **201** | `horus-iam-srv01` | LXC | 2 | 2 ГБ | Диск Root 20G | SSO-авторизация (Authentik) |
| **202** | `horus-git-srv01` | LXC | 2 | 2 ГБ | Диск Root 20G | Gitea (Локальный Git-репозиторий) |
| **203** | `horus-vlt-srv01` | ВМ | 2 | 2 ГБ | Шаблон Cloud-init 9000 (Изолированная память) | Хранилище секретов Vault |
| **204** | `horus-wiki-srv01` | LXC | 1 | 1 ГБ | Диск Root 15G | Wiki.js (База знаний) |
| **205** | `horus-db-srv01` | LXC | 2 | 4 ГБ | 30G Root + 860G HDD (`data-pg`) + 10G SSD (`data-ai`) вложенные | Выделенный PostgreSQL 18 |
| **206** | `horus-reg-srv01` | LXC | 2 | 4 ГБ | Диск Root 40G | Harbor Container Registry |
| **207** | `horus-ans-srv01` | LXC | 2 | 4 ГБ | Диск Root 30G | Локальный движок Ansible |
| **208** | `horus-ai-srv03` | LXC | 4 | 8 ГБ | 32G Root + 410G SSD монтируется на `data-ai` | ИИ-ассистент (Мимир) |

### 📊 Хост: `horus-pmx-srv03` (Микросервисный стек наблюдаемости и S3)
| VMID | Имя узла | Тип | Процессор | Память | Разделы и точки монтирования (Datastore) | Роль в системе |
| :--- | :--- | :---: | :---: | :---: | :--- | :--- |
| **301** | `horus-grf-srv01` | LXC | 1 | 1 ГБ | Диск Root 10G | Grafana (Визуализация метрик) |
| **302** | `horus-pm-srv01` | LXC | 2 | 2 ГБ | Диск Root 15G | Prometheus (Сбор метрик) |
| **303** | `horus-lok-srv01` | LXC | 2 | 2 ГБ | Диск Root 15G | Loki + Alertmanager (Логи) |
| **304** | `horus-otel-srv01` | LXC | 1 | 1 ГБ | Диск Root 5G | OpenTelemetry Collector |
| **305** | `horus-s3-srv01` | LXC | 2 | 2 ГБ | 40G Root + 430G HDD монтируется на датастор `data` | Локальное S3-хранилище MinIO |
| **306** | `horus-ai-ops01` | LXC | 4 | 4 ГБ | Диск Root 32G | AI Operations Engine (AIOps) |

---

## 📂 Структура репозитория

```text
HoRus-Bootstrap/
├── .gitignore                  # Исключения (состояние, пароли, переменные)
├── main.tf                     # Главный файл топологии и вызова модулей
├── variables.tf                # Глобальные переменные Terraform
├── providers.tf                # Настройка провайдера Proxmox VE (bpg/proxmox)
├── ARCHITECTURE.md             # Паспорт архитектуры (VLAN, хосты, маппинг)
├── BACKLOG.md                  # Список задач и планов по развитию
├── LICENSE                     # Лицензия проекта
├── modules/                    # Переиспользуемые инфраструктурные модули
│   ├── proxmox_lxc/            # Модуль непривилегированных контейнеров LXC
│   │   ├── main.tf             # Описание LXC ресурсов и расчет MAC-адреса
│   │   └── variables.tf        # Входные параметры для LXC
│   └── proxmox_vm/             # Модуль виртуальных машин KVM
│       ├── main.tf             # Описание ресурсов ВМ на базе шаблона 9000
│       └── variables.tf        # Входные параметры для ВМ
└── README.md                   # Основная документация проекта
```

---

## 🚀 Руководство по развертыванию на любой ОС

Вы можете запустить процесс развертывания со своего рабочего компьютера под управлением любой современной ОС.

### Подготовительные шаги (для всех систем)
1.  **Создание SSH-ключей:** Сгенерируйте пару ключей для доступа на своей машине:
    ```bash
    ssh-keygen -t ed25519 -C "admin@horus-cluster" -f ~/.ssh/id_ed25519_horus
    ```
2.  **Выпуск API токена Proxmox:** Перейдите в веб-интерфейс Proxmox VE (`Datacenter -> Permissions -> API Tokens`), сгенерируйте токен для пользователя `root@pam` с именем `terraform` и сохраните его секретную часть.

---

### Пошаговый деплой по операционным системам

#### 🐧 1. Развертывание в ОС GNU/Linux и macOS
Откройте терминал и выполните следующие действия:

*   **Установка Terraform:**
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

*   **Настройка переменных среды и секретов:**
    ```bash
    # Создаем файл с паролем суперпользователя (игнорируется в Git)
    echo "SuperSecretPass123!" > root_password.txt

    # Копируем шаблон переменных
    cp -n terraform.tfvars.example terraform.tfvars || touch terraform.tfvars
    ```
    Заполните файл `terraform.tfvars` параметрами своей сети:
    ```hcl
    pmx_api_url    = "https://<IP_АДРЕС_PROXMOX>:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=твой-секрет-токена"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    gateway_ip     = "192.168.1.1"
    dns_servers    = ["192.168.1.1", "8.8.8.8"]
    ```

*   **Запуск инициализации и наката:**
    ```bash
    terraform init
    terraform plan
    terraform apply -auto-approve
    ```

---

#### 🪟 2. Развертывание в Windows (CMD или PowerShell)
Запустите консоль PowerShell или Командную строку от имени Администратора:

*   **Установка Terraform:**
    ```powershell
    # С помощью диспетчера пакетов Chocolatey
    choco install terraform -y

    # Или с помощью Winget
    winget install HashiCorp.Terraform
    ```

*   **Настройка переменных среды и секретов:**
    ```powershell
    # Создаем пароль root в корне проекта
    Set-Content -Path .\root_password.txt -Value "SuperSecretPass123!"

    # Создаем файл настроек
    New-Item -Path .\terraform.tfvars -ItemType File -Force
    ```
    Откройте `terraform.tfvars` в Блокноте (или VS Code) и внесите конфигурационные данные:
    ```hcl
    pmx_api_url    = "https://192.168.1.211:8006/api2/json"
    pmx_api_token  = "root@pam!terraform=твой-секрет-токена"
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

#### 🐋 3. Развертывание с помощью Windows Subsystem for Linux (WSL)
Если вы хотите использовать родную среду Linux на Windows-компьютере:

*   **Настройка интеграции WSL:**
    Запустите свой дистрибутив WSL (например, Ubuntu) и свяжите SSH-ключи Windows:
    ```bash
    # Ссылка на ключи Windows (при их наличии)
    ln -s /mnt/c/Users/<ИмяПользователяWindows>/.ssh ~/.ssh
    ```

*   **Выполнение инструкций:**
    Просто скопируйте и запустите команды из раздела **GNU/Linux и macOS** выше в консоли WSL. Terraform беспрепятственно выполнит вызовы API Proxmox по внутренней виртуальной сети.

---

## 🔒 Безопасность и соответствие SRE-практикам

1.  **Изоляция файлов состояния (State):**
    Файл `terraform.tfstate` хранит системные токены и пароли в открытом виде. **Никогда не коммитьте его в Git!** Он надежно заблокирован через `.gitignore`. В продуктовых ландшафтах рекомендуется использовать защищенные удаленные бэкенды (Gitlab Managed State, HashiCorp Consul или S3 с SSE-шифрованием).
2.  **Непривилегированные среды (Unprivileged LXC):**
    Контейнеры запускаются в непривилегированном режиме (`unprivileged = true`), предотвращая возможность компрометации хост-системы Proxmox VE при взломе отдельных приложений.
3.  **Изоляция оперативной памяти ВМ:**
    Виртуальные машины для Jenkins и Vault используют аппаратную виртуализацию и строгие лимиты, гарантируя защиту критически важных секретов от атак со стороны других узлов кластера.

---

## 📄 Лицензия и права собственности

Этот проект распространяется под лицензией **Apache License 2.0** — подробности см. в файле [LICENSE](LICENSE).

*   **Владелец и собственник проекта:** Алексей Савельев (псевдоним **Alex Benden**)
*   **Компания и бренд проекта:** Benden-SysLab
*   **Электронная почта:** bendenalex@gmail.com
*   **Telegram:** [https://t.me/Alex_Benden](https://t.me/Alex_Benden)

