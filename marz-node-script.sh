#!/bin/bash

clear
echo -e "\033[1;31m"
cat << "EOF"
 ▄▄▄▄   ██▓   ▄▄▄       ▄████ ▒█████ ▓█████▄ ▄▄▄      ██▀███ ▓█████ ███▄    █ 
▓█████▄▓██▒  ▒████▄    ██▒ ▀█▒██▒  ██▒██▀ ██▒████▄   ▓██ ▒ ██▓█   ▀ ██ ▀█   █ 
▒██▒ ▄█▒██░  ▒██  ▀█▄ ▒██░▄▄▄▒██░  ██░██   █▒██  ▀█▄ ▓██ ░▄█ ▒███  ▓██  ▀█ ██▒
▒██░█▀ ▒██░  ░██▄▄▄▄██░▓█  ██▒██   ██░▓█▄   ░██▄▄▄▄██▒██▀▀█▄ ▒▓█  ▄▓██▒  ▐▌██▒
░▓█  ▀█░██████▓█   ▓██░▒▓███▀░ ████▓▒░▒████▓ ▓█   ▓██░██▓ ▒██░▒████▒██░   ▓██░
░▒▓███▀░ ▒░▓  ▒▒   ▓▒█░░▒   ▒░ ▒░▒░▒░ ▒▒▓  ▒ ▒▒   ▓▒█░ ▒▓ ░▒▓░░ ▒░ ░ ▒░   ▒ ▒ 
▒░▒   ░░ ░ ▒  ░▒   ▒▒ ░ ░   ░  ░ ▒ ▒░ ░ ▒  ▒  ▒   ▒▒ ░ ░▒ ░ ▒░░ ░  ░ ░░   ░ ▒░
 ░    ░  ░ ░   ░   ▒  ░ ░   ░░ ░ ░ ▒  ░ ░  ░  ░   ▒    ░░   ░   ░     ░   ░ ░ 
 ░         ░  ░    ░  ░     ░    ░ ░    ░         ░  ░  ░       ░  ░        ░ 
      ░                               ░                                       
EOF
echo -e "\033[0m"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
debug() { echo -e "[DEBUG] $1"; }

# Функция ожидания освобождения блокировки APT
wait_for_apt_lock() {
    local max_wait=300  # 5 минут
    local wait_time=0
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
            error "Превышено время ожидания освобождения блокировки APT"
        fi
        
        warning "APT заблокирован другим процессом, ожидание... ($wait_time/$max_wait сек)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    # Дополнительная проверка других блокировок
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
            error "Превышено время ожидания освобождения блокировки APT"
        fi
        
        warning "Обнаружены дополнительные блокировки APT, ожидание... ($wait_time/$max_wait сек)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    log "Блокировки APT освобождены"
}

# ======================== Параметры ========================
read -p "Установить BBR и Xanmod Kernel? (y/n): " ans_bbr
if [[ $ans_bbr =~ ^[Yy] ]]; then
    INSTALL_BBR=true
else
    INSTALL_BBR=false
fi

read -p "Настроить SSH ключ? (y/n): " ans_sshkey
if [[ $ans_sshkey =~ ^[Yy] ]]; then
    INSTALL_SSH_KEY=true
else
    INSTALL_SSH_KEY=false
fi

if [[ $EUID -ne 0 ]]; then
   error "Этот скрипт должен быть запущен с правами root"
fi

log "==================== НАЧАЛО УСТАНОВКИ ===================="
log "Этап 0: Сбор необходимых данных..."

# Запрос SSH порта
while true; do
    read -p "Введите порт для SSH (по умолчанию 22): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; then
        break
    else
        warning "Некорректный порт. Введите число от 1 до 65535"
    fi
done

# Запрос IP мастер-ноды
while true; do
    read -p "Введите IP адрес мастер-ноды: " MASTER_IP
    if [[ $MASTER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    else
        warning "Некорректный формат IP адреса. Попробуйте снова."
    fi
done

if $INSTALL_SSH_KEY; then
    while true; do
        log "Введите ваш публичный SSH ключ (должен начинаться с 'ssh-rsa' или 'ssh-ed25519'):"
        read SSH_KEY
        if [[ -z "$SSH_KEY" ]]; then
            warning "SSH ключ не может быть пустым."
        elif [[ "$SSH_KEY" =~ ^(ssh-rsa|ssh-ed25519)[[:space:]].*$ ]]; then
            break
        else
            warning "Некорректный формат SSH ключа."
        fi
    done
fi

while true; do
    read -p "Введите субдомен (например, us.domain.com): " SUBDOMAIN
    if [ -z "$SUBDOMAIN" ]; then
        warning "Субдомен не может быть пустым. Пожалуйста, введите значение."
    else
        break
    fi
done

while true; do
    read -p "Введите имя ноды (например, us-node-1): " NODE_NAME
    if [ -z "$NODE_NAME" ]; then
        warning "Имя ноды не может быть пустым. Пожалуйста, введите значение."
    else
        break
    fi
done

# Cloudflare настройки убраны - используем Caddy с автоматическими сертификатами

read -p "Введите порт для сервиса (по умолчанию 62050): " SERVICE_PORT
SERVICE_PORT=${SERVICE_PORT:-62050}
read -p "Введите порт для API (по умолчанию 62051): " API_PORT
API_PORT=${API_PORT:-62051}

# Запрос SSL сертификата
log "Введите SSL client сертификат (После Enter - Ctrl+D для завершения ввода):"
SSL_CERT=$(cat)
if [ -z "$SSL_CERT" ]; then
    error "SSL сертификат не может быть пустым."
fi

# Извлечение тела сертификата (без BEGIN/END)
CERT_BODY=$(echo "$SSL_CERT" | grep -v "BEGIN CERTIFICATE" | grep -v "END CERTIFICATE" | tr -d '\n')
if [[ ! $CERT_BODY =~ ^[A-Za-z0-9+/=]+$ ]]; then
    error "Некорректный формат сертификата. Пожалуйста, предоставьте валидный SSL сертификат."
fi

debug "Установлены следующие значения:"
debug "Субдомен: ${SUBDOMAIN}"
debug "Название ноды: ${NODE_NAME}"
debug "Service port: ${SERVICE_PORT}"
debug "API port: ${API_PORT}"

# ======================== Установка системных компонентов ========================
log "==================== СИСТЕМНЫЕ КОМПОНЕНТЫ ===================="
log "Этап 1: Установка системных компонентов..."

log "Шаг 1.0: Проверка блокировок APT..."
wait_for_apt_lock

log "Шаг 1.1: Обновление системы..."
apt update 2>&1 | while read -r line; do debug "$line"; done
apt upgrade -y 2>&1 | while read -r line; do debug "$line"; done || error "Ошибка при обновлении системы"

log "Шаг 1.2: Установка базовых пакетов..."
apt install -y curl wget git expect ufw openssl lsb-release ca-certificates gnupg2 ubuntu-keyring 2>&1 | while read -r line; do debug "$line"; done || error "Ошибка при установке базовых пакетов"

# ======================== Опциональная установка BBR ========================
if $INSTALL_BBR; then
    log "==================== УСТАНОВКА BBRv3 ===================="
    log "Шаг 1.3: Установка BBRv3..."
    debug "Загрузка скрипта BBRv3..."
    curl -s https://raw.githubusercontent.com/opiran-club/VPS-Optimizer/main/bbrv3.sh --ipv4 > bbrv3.sh || error "Ошибка при скачивании BBRv3"
    expect << 'EOF'
spawn bash bbrv3.sh
expect "Enter"
send "1\r"
expect "y/n"
send "y\r"
expect eof
EOF
    rm bbrv3.sh
else
    debug "Опциональная установка BBR пропущена."
fi

log "==================== УСТАНОВКА CADDY ===================="
log "Шаг 1.4: Установка Caddy..."

# Добавление официального репозитория Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update 2>&1 | while read -r line; do debug "$line"; done
apt install -y caddy || error "Ошибка при установке Caddy"

log "==================== НАСТРОЙКА CADDY ===================="
log "Настройка Caddyfile..."

# Создание Caddyfile на основе шаблона
cat > /etc/caddy/Caddyfile << CADDY_EOF
{
  https_port 4123
  default_bind 127.0.0.1
  servers {
    listener_wrappers {
      proxy_protocol {
        allow 127.0.0.1/32
      }
      tls
    }
  }
  auto_https disable_redirects
}

https://${SUBDOMAIN} {
  root * /var/www/${SUBDOMAIN}
  file_server
}

http://${SUBDOMAIN} {
  bind 0.0.0.0
  redir https://{host}{uri} permanent
}

:4123 {
  tls internal
  respond 204
}

:80 {
  bind 0.0.0.0
  respond 204
}
CADDY_EOF

# Создание директории для веб-контента
mkdir -p /var/www/${SUBDOMAIN}
cat > /var/www/${SUBDOMAIN}/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nexacom | Secure Login</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #6366f1;
            --primary-hover: #4f46e5;
            --bg-dark: #0f172a;
            --card-bg: rgba(30, 41, 59, 0.7);
            --border: rgba(255, 255, 255, 0.1);
            --text-main: #f8fafc;
            --text-dim: #94a3b8;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Outfit', sans-serif;
            background-color: var(--bg-dark);
            background-image:
                radial-gradient(circle at 20% 20%, rgba(99, 102, 241, 0.15) 0%, transparent 40%),
                radial-gradient(circle at 80% 80%, rgba(79, 70, 229, 0.1) 0%, transparent 40%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--text-main);
            overflow: hidden;
        }

        .login-container {
            width: 100%;
            max-width: 420px;
            padding: 20px;
            animation: fadeInScale 0.8s ease-out;
        }

        @keyframes fadeInScale {
            from {
                opacity: 0;
                transform: scale(0.95) translateY(10px);
            }

            to {
                opacity: 1;
                transform: scale(1) translateY(0);
            }
        }

        .login-card {
            background: var(--card-bg);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--border);
            border-radius: 24px;
            padding: 40px;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            position: relative;
        }

        .logo {
            width: 48px;
            height: 48px;
            background: linear-gradient(135deg, var(--primary), #a855f7);
            border-radius: 12px;
            margin: 0 auto 24px;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 0 20px rgba(99, 102, 241, 0.3);
        }

        .logo svg {
            width: 28px;
            height: 28px;
            fill: white;
        }

        .header {
            text-align: center;
            margin-bottom: 32px;
        }

        .header h1 {
            font-weight: 600;
            font-size: 24px;
            margin-bottom: 8px;
            letter-spacing: -0.02em;
        }

        .header p {
            color: var(--text-dim);
            font-size: 14px;
        }

        .form-group {
            margin-bottom: 20px;
        }

        .form-group label {
            display: block;
            font-size: 13px;
            color: var(--text-dim);
            margin-bottom: 8px;
            margin-left: 4px;
        }

        .input-wrapper {
            position: relative;
        }

        input {
            width: 100%;
            background: rgba(15, 23, 42, 0.5);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 12px 16px;
            color: white;
            font-family: inherit;
            font-size: 15px;
            transition: all 0.2s ease;
            outline: none;
        }

        input:focus {
            border-color: var(--primary);
            box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.1);
            background: rgba(15, 23, 42, 0.8);
        }

        .error-message {
            background: rgba(239, 68, 68, 0.1);
            border: 1px solid rgba(239, 68, 68, 0.2);
            color: #f87171;
            padding: 12px;
            border-radius: 12px;
            font-size: 14px;
            margin-bottom: 20px;
            display: none;
            align-items: center;
            gap: 10px;
            animation: shake 0.5s cubic-bezier(.36, .07, .19, .97) both;
        }

        .error-message.show {
            display: flex;
        }

        @keyframes shake {

            10%,
            90% {
                transform: translate3d(-1px, 0, 0);
            }

            20%,
            80% {
                transform: translate3d(2px, 0, 0);
            }

            30%,
            50%,
            70% {
                transform: translate3d(-4px, 0, 0);
            }

            40%,
            60% {
                transform: translate3d(4px, 0, 0);
            }
        }

        .error-message svg {
            flex-shrink: 0;
        }

        .btn-login {
            width: 100%;
            background: var(--primary);
            color: white;
            border: none;
            border-radius: 12px;
            padding: 14px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s ease;
            margin-top: 10px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        }

        .btn-login:hover {
            background: var(--primary-hover);
            transform: translateY(-1px);
            box-shadow: 0 10px 15px -3px rgba(99, 102, 241, 0.4);
        }

        .btn-login:active {
            transform: translateY(0);
        }

        .footer {
            margin-top: 32px;
            text-align: center;
            border-top: 1px solid var(--border);
            padding-top: 24px;
        }

        .restricted-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: rgba(239, 68, 68, 0.1);
            color: #f87171;
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        .copyright {
            margin-top: 16px;
            font-size: 12px;
            color: var(--text-dim);
        }

        /* Subtle background animation */
        .bg-mesh {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            z-index: -1;
            opacity: 0.5;
        }
    </style>
</head>

<body>
    <div class="login-container">
        <div class="login-card">
            <div class="logo">
                <svg viewBox="0 0 24 24">
                    <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"></path>
                </svg>
            </div>

            <div class="header">
                <h1>Nexacom Intranet</h1>
                <p>Closed Corporate Communication Network</p>
            </div>

            <form onsubmit="return false;">
                <div class="form-group">
                    <label for="employeeId">Employee Email or ID</label>
                    <div class="input-wrapper">
                        <input type="text" id="employeeId" placeholder="e.g. j.doe@corp.net" autocomplete="off">
                    </div>
                </div>

                <div class="form-group">
                    <label for="password">Security Password</label>
                    <div class="input-wrapper">
                        <input type="password" id="password" placeholder="••••••••">
                    </div>
                </div>

                <div class="error-message">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <circle cx="12" cy="12" r="10"></circle>
                        <line x1="12" y1="8" x2="12" y2="12"></line>
                        <line x1="12" y1="16" x2="12.01" y2="16"></line>
                    </svg>
                    <span>Invalid credentials. Access denied by security policy.</span>
                </div>

                <button class="btn-login" type="button" onclick="showError()">Authorize Access</button>
            </form>

            <script>
                function showError() {
                    const error = document.querySelector('.error-message');
                    error.classList.remove('show');
                    // Trigger reflow to restart animation
                    void error.offsetWidth;
                    error.classList.add('show');
                }
            </script>

            <div class="footer">
                <div class="restricted-badge">
                    <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path>
                    </svg>
                    Restricted Access
                </div>
                <div class="copyright">
                    &copy; 2026 Nexacom Technologies GMBH.<br>
                    Internal Use Only.
                </div>
            </div>
        </div>
    </div>
</body>

</html>
HTML_EOF

chown -R caddy:caddy /var/www/${SUBDOMAIN}
chmod -R 755 /var/www/${SUBDOMAIN}

# ======================== Предварительная установка Docker ========================
log "==================== УСТАНОВКА DOCKER ===================="
log "Этап 2: Предварительная установка Docker..."

# Проверка, установлен ли уже Docker
if ! command -v docker &> /dev/null; then
    log "Docker не найден, выполняется установка..."
    wait_for_apt_lock
    
    # Установка Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    chmod +x get-docker.sh
    ./get-docker.sh
    rm -f get-docker.sh
    
    # Запуск и включение Docker
    systemctl enable docker
    systemctl start docker
    
    # Проверка установки
    if ! systemctl is-active --quiet docker; then
        error "Не удалось запустить Docker сервис"
    fi
    
    log "Docker успешно установлен и запущен"
else
    log "Docker уже установлен"
    
    # Убедимся, что Docker запущен
    if ! systemctl is-active --quiet docker; then
        log "Запуск Docker сервиса..."
        systemctl start docker
    fi
fi

# ======================== Установка Marzban Node ========================
log "==================== УСТАНОВКА MARZBAN NODE ===================="
log "Этап 3: Установка Marzban Node..."
curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban-node.sh > marzban-node.sh
chmod +x marzban-node.sh

expect << EOF
spawn ./marzban-node.sh @ install --name ${NODE_NAME}
expect "Please paste the content of the Client Certificate"
send -- "-----BEGIN CERTIFICATE-----\n"
send -- "${CERT_BODY}\n"
send -- "-----END CERTIFICATE-----\n\n"
expect "Do you want to use REST protocol?"
send -- "y\n"
expect "Enter the SERVICE_PORT"
send -- "${SERVICE_PORT}\n"
expect "Enter the XRAY_API_PORT"
send -- "${API_PORT}\n"
expect eof
EOF

rm -f marzban-node.sh

log "Ожидание завершения установки Marzban Node..."
# Даем время установке завершиться
sleep 15

# Убедимся, что Docker сервис запущен и работает
log "Финальная проверка Docker сервиса..."
if ! systemctl is-active --quiet docker; then
    warning "Docker сервис не активен, попытка запуска..."
    systemctl start docker
    sleep 5
    
    if ! systemctl is-active --quiet docker; then
        error "Критическая ошибка: не удалось запустить Docker сервис"
    fi
fi

# Проверка, что команда docker работает
if ! docker --version >/dev/null 2>&1; then
    error "Docker установлен, но команда docker не работает"
fi

log "Docker сервис работает корректно"

mkdir -p /var/lib/marzban/log
touch /var/lib/marzban/log/access.log
chmod 755 /var/lib/marzban/log
chmod 644 /var/lib/marzban/log/access.log

# Проверка различных возможных расположений docker-compose.yml
DOCKER_COMPOSE_FILE=""
POSSIBLE_LOCATIONS=(
    "/opt/${NODE_NAME}/docker-compose.yml"
    "/opt/marzban-node/docker-compose.yml"
    "/opt/marzban-node-${NODE_NAME}/docker-compose.yml"
    "/root/marzban-node/docker-compose.yml"
    "/root/${NODE_NAME}/docker-compose.yml"
)

debug "Поиск docker-compose.yml в следующих местах:"
for location in "${POSSIBLE_LOCATIONS[@]}"; do
    debug "Проверка: $location"
    if [[ -f "$location" ]]; then
        DOCKER_COMPOSE_FILE="$location"
        debug "Найден docker-compose.yml: $location"
        break
    fi
done

# Если не найден в предопределенных местах, попробуем найти через find
if [[ -z "$DOCKER_COMPOSE_FILE" ]]; then
    debug "Поиск docker-compose.yml через find..."
    FOUND_FILES=$(find /opt /root -name "docker-compose.yml" -type f 2>/dev/null | head -5)
    if [[ -n "$FOUND_FILES" ]]; then
        debug "Найденные docker-compose.yml файлы:"
        echo "$FOUND_FILES" | while read -r file; do
            debug "  - $file"
        done
        DOCKER_COMPOSE_FILE=$(echo "$FOUND_FILES" | head -1)
        debug "Используется первый найденный: $DOCKER_COMPOSE_FILE"
    fi
fi

if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
    debug "Настройка монтирования логов в $DOCKER_COMPOSE_FILE"
    COMPOSE_DIR=$(dirname "$DOCKER_COMPOSE_FILE")
    
    # Проверим, есть ли уже монтирование логов
    if ! grep -q "/var/lib/marzban/log" "$DOCKER_COMPOSE_FILE"; then
        sed -i '/volumes:/a\      - /var/lib/marzban/log:/var/lib/marzban/log' "$DOCKER_COMPOSE_FILE"
        debug "Добавлено монтирование логов"
    else
        debug "Монтирование логов уже настроено"
    fi
    
    cd "$COMPOSE_DIR"
    debug "Перезапуск Docker Compose в директории: $COMPOSE_DIR"
    
    # Более надежная остановка контейнеров
    docker compose down 2>/dev/null || true
    sleep 3
    
    # Запуск с повторной попыткой в случае неудачи
    if ! docker compose up -d; then
        warning "Первая попытка запуска не удалась, повторная попытка через 5 секунд..."
        sleep 5
        docker compose up -d
    fi
    
    # Проверка статуса контейнеров
    sleep 5
    log "Статус контейнеров Marzban Node:"
    docker compose ps | while read -r line; do debug "  $line"; done
else
    warning "Файл docker-compose.yml не найден ни в одном из ожидаемых мест, пропуск настройки монтирования логов."
    debug "Список содержимого /opt:"
    ls -la /opt/ 2>/dev/null | while read -r line; do debug "  $line"; done
    debug "Список содержимого /root:"
    ls -la /root/ 2>/dev/null | while read -r line; do debug "  $line"; done
fi

# ======================== Финальные проверки и настройки ========================
log "==================== ФИНАЛЬНЫЕ ПРОВЕРКИ ===================="
log "Проверка конфигурации Caddy..."
caddy validate --config /etc/caddy/Caddyfile 2>&1 | while read -r line; do debug "$line"; done || error "Ошибка в конфигурации Caddy"

systemctl enable caddy 2>&1 | while read -r line; do debug "$line"; done
systemctl start caddy 2>&1 | while read -r line; do debug "$line"; done
if ! systemctl is-active --quiet caddy; then
    error "Не удалось запустить Caddy"
fi

log "Настройка UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow ${SSH_PORT}/tcp
ufw allow from ${MASTER_IP}
echo "y" | ufw enable
ufw status verbose || error "Ошибка при настройке UFW"

log "Настройка SSH..."
if $INSTALL_SSH_KEY; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    cat > /root/.ssh/authorized_keys << KEYS_EOF
${SSH_KEY}
KEYS_EOF

    # Настройка базового конфига SSH
    cat > /etc/ssh/sshd_config << SSH_EOF
Port ${SSH_PORT}
Protocol 2
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 60
AllowUsers root
SSH_EOF

    systemctl restart ssh
    if ! systemctl is-active --quiet ssh; then
        error "Не удалось запустить SSH"
    fi
fi

# ======================== Установка Cloudflare WARP ========================
log "==================== УСТАНОВКА CLOUDFLARE WARP ===================="
log "Этап 5: Установка Cloudflare WARP..."

wait_for_apt_lock

curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

apt update 2>&1 | while read -r line; do debug "$line"; done
apt install cloudflare-warp -y 2>&1 | while read -r line; do debug "$line"; done || error "Ошибка при установке Cloudflare WARP"

log "Настройка WARP..."
warp-cli registration new || warning "Регистрация WARP могла не завершиться"
warp-cli mode proxy
warp-cli proxy port 40000
warp-cli connect

if warp-cli status | grep -q "Connected"; then
    log "Cloudflare WARP успешно подключен (proxy на порту 40000)"
else
    warning "WARP установлен, но подключение может потребовать дополнительной настройки"
fi

log "Установка успешно завершена!"
debug "Все компоненты установлены и настроены"
read -p "Перезагрузить систему сейчас? (y/n): " reboot_now
if [[ $reboot_now == "y" ]]; then
    debug "Выполняется перезагрузка системы..."
    reboot
fi
