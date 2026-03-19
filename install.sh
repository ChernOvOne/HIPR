#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  HIPR — установщик v3.0
#  https://github.com/ChernOvOne/HIPR
#
#  Одна команда:
#  bash <(curl -fsSL https://raw.githubusercontent.com/ChernOvOne/HIPR/main/install.sh)
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/ChernOvOne/HIPR/main"
HIDE_DIR="/opt/hipr"
HIDE_BIN="/usr/local/bin/hide"
CONFIG_FILE="$HIDE_DIR/config.env"
WEB_DIR="/var/www/hipr"
MTG_BIN="$HIDE_DIR/bin/mtg"
MTG_VER="2.1.7"
VERSION="3.0"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1;37m'
N='\033[0m';    BOLD='\033[1m'; DIM='\033[2m'

step()      { echo -e "\n${C}┌─${N} ${BOLD}$*${N}"; }
ok()        { echo -e "${C}│${N}  ${G}✓${N}  $*"; }
info()      { echo -e "${C}│${N}  ${Y}→${N}  $*"; }
done_step() { echo -e "${C}└─ ${G}готово${N}"; }
err()       { echo -e "\n${R}✗  ОШИБКА: $*${N}\n"; exit 1; }

# ── Баннер ────────────────────────────────────────────────────────────────
clear
echo -e "${C}${BOLD}"
cat << 'BANNER'
  ██╗  ██╗██╗██████╗ ██████╗
  ██║  ██║██║██╔══██╗██╔══██╗
  ███████║██║██████╔╝██████╔╝
  ██╔══██║██║██╔═══╝ ██╔══██╗
  ██║  ██║██║██║     ██║  ██║
  ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝  ╚═╝  v3.0
BANNER
echo -e "${N}"
echo -e "  ${DIM}Telegram MTProto прокси — невидимый для ТСПУ${N}"
echo -e "  ${DIM}https://github.com/ChernOvOne/HIPR${N}"
echo -e "\n${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"

# ── Проверки ──────────────────────────────────────────────────────────────
step "Проверка системы"

[[ $EUID -ne 0 ]] && err "Нужен root:  sudo bash install.sh"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  MTG_ARCH="amd64" ;;
  aarch64) MTG_ARCH="arm64" ;;
  armv7l)  MTG_ARCH="arm-7" ;;
  *) err "Неподдерживаемая архитектура: $ARCH" ;;
esac

ok "OS: $(lsb_release -sd 2>/dev/null || uname -s)"
ok "Архитектура: $ARCH"
ss -tlnp 2>/dev/null | grep -q ':443 ' && \
  info "Порт 443 занят — освободите перед установкой" || ok "Порт 443: свободен"
curl -sf --max-time 5 https://google.com > /dev/null 2>&1 || err "Нет интернета"
ok "Интернет: есть"
done_step

# ── Ввод параметров ───────────────────────────────────────────────────────
step "Параметры установки"
echo ""

while true; do
  read -rp "  ${W}Домен сервера${N} (напр. proxy.example.com): " DOMAIN
  [[ -n "${DOMAIN:-}" ]] && break
  echo -e "  ${R}Домен обязателен${N}"
done

while true; do
  read -rp "  ${W}Email${N} для Let's Encrypt: " LE_EMAIL
  [[ "${LE_EMAIL:-}" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
  echo -e "  ${R}Некорректный email${N}"
done

echo ""
echo -e "  ${W}Начальная тема сайта-обманки:${N}"
echo -e "  ${DIM}(меняется через hide → Темы)${N}\n"
echo -e "  ${W}[1]${N}  Блог разработчика"
echo -e "  ${W}[2]${N}  Страница фрилансера"
echo -e "  ${W}[3]${N}  «Скоро открытие»"
echo ""
read -rp "  Тема [1-3, Enter=1]: " THEME_CHOICE
case "${THEME_CHOICE:-1}" in
  2) INITIAL_THEME="freelancer" ;;
  3) INITIAL_THEME="coming-soon" ;;
  *) INITIAL_THEME="blog" ;;
esac

echo ""
echo -e "  ${W}Telegram-бот для уведомлений:${N} ${DIM}(необязательно)${N}"
echo -e "  ${DIM}Создайте бота через @BotFather, получите токен и chat_id${N}"
read -rp "  Bot Token (или Enter чтобы пропустить): " BOT_TOKEN
BOT_TOKEN="${BOT_TOKEN:-}"
BOT_CHAT_ID=""
if [[ -n "$BOT_TOKEN" ]]; then
  read -rp "  Chat ID: " BOT_CHAT_ID
fi

echo ""
echo -e "  ${DIM}─────────────────────────────────────────${N}"
ok "Домен:  $DOMAIN"
ok "Email:  $LE_EMAIL"
ok "Тема:   $INITIAL_THEME"
[[ -n "$BOT_TOKEN" ]] && ok "Бот:    настроен" || info "Бот:    пропущен"
echo -e "  ${DIM}─────────────────────────────────────────${N}\n"

read -rp "  Начать установку? [Y/n]: " CONFIRM
[[ "${CONFIRM,,}" == "n" ]] && { echo "  Отменено."; exit 0; }
done_step

# ── Пакеты ────────────────────────────────────────────────────────────────
step "Установка пакетов"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null
apt-get install -y -qq \
  nginx certbot python3-certbot-nginx \
  curl wget jq bc \
  net-tools netcat-openbsd \
  qrencode xxd openssl python3 \
  fail2ban ufw unzip 2>/dev/null
ok "Пакеты установлены"
done_step

# ── Директории и конфиг ───────────────────────────────────────────────────
step "Создание структуры"
mkdir -p "$HIDE_DIR"/{bin,logs,config,themes/custom}
mkdir -p "$WEB_DIR"
touch "$HIDE_DIR/logs/proxy.log" "$HIDE_DIR/logs/error.log" "$HIDE_DIR/logs/watchdog.log"

# Генерация секрета через mtg (после установки) — пока заглушка
MTG_SECRET_PLACEHOLDER="__MTG_SECRET__"

cat > "$CONFIG_FILE" << EOF
# HIPR v$VERSION — $(date -u +"%Y-%m-%d %H:%M UTC")
DOMAIN="$DOMAIN"
LE_EMAIL="$LE_EMAIL"
MTG_SECRET="$MTG_SECRET_PLACEHOLDER"
ACTIVE_DC="149.154.167.51"
BOT_TOKEN="$BOT_TOKEN"
BOT_CHAT_ID="$BOT_CHAT_ID"
MTG_PORT="2398"
VERSION="$VERSION"
INSTALL_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

ok "Конфиг: $CONFIG_FILE"
done_step

# ── Скачиваем файлы с GitHub ──────────────────────────────────────────────
step "Загрузка файлов"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$SCRIPT_DIR/hide" && -d "$SCRIPT_DIR/themes" ]]; then
  info "Локальный репозиторий — копируем"
  cp "$SCRIPT_DIR/hide" "$HIDE_BIN"
  cp -r "$SCRIPT_DIR/themes"/. "$HIDE_DIR/themes/"
  ok "Скопировано локально"
else
  info "Скачиваем с GitHub..."
  curl -fsSL "$REPO_RAW/hide" -o "$HIDE_BIN" || err "Не удалось скачать hide"
  ok "hide скачан"

  for theme in blog freelancer coming-soon; do
    mkdir -p "$HIDE_DIR/themes/$theme"
    for f in index.html theme.json about.html; do
      curl -fsSL "$REPO_RAW/themes/$theme/$f" \
        -o "$HIDE_DIR/themes/$theme/$f" 2>/dev/null || true
    done
    [[ -f "$HIDE_DIR/themes/$theme/index.html" ]] && ok "Тема: $theme"
  done
fi

chmod +x "$HIDE_BIN"
done_step

# ── Установка mtg ─────────────────────────────────────────────────────────
step "Установка mtg v$MTG_VER (9seconds/mtg)"

MTG_URL="https://github.com/9seconds/mtg/releases/download/v${MTG_VER}/mtg-${MTG_VER}-linux-${MTG_ARCH}.tar.gz"
info "Скачиваем mtg для $MTG_ARCH..."

if wget -q "$MTG_URL" -O /tmp/mtg.tar.gz 2>/dev/null; then
  tar -xzf /tmp/mtg.tar.gz -C /tmp/
  # mtg распаковывается в папку с именем
  find /tmp -name "mtg" -type f 2>/dev/null | head -1 | xargs -I{} cp {} "$MTG_BIN"
  rm -f /tmp/mtg.tar.gz
  chmod +x "$MTG_BIN"
  ok "mtg установлен: $($MTG_BIN --version 2>/dev/null | head -1)"
else
  # Fallback — скачиваем бинарник напрямую
  MTG_URL_DIRECT="https://github.com/9seconds/mtg/releases/download/v${MTG_VER}/mtg-linux-${MTG_ARCH}"
  curl -fsSL "$MTG_URL_DIRECT" -o "$MTG_BIN" 2>/dev/null || err "Не удалось скачать mtg"
  chmod +x "$MTG_BIN"
  ok "mtg установлен"
fi

# Генерируем секрет через mtg
info "Генерируем секрет FakeTLS для домена $DOMAIN..."
MTG_SECRET=$("$MTG_BIN" generate-secret --hex "$DOMAIN" 2>/dev/null | tr -d '\n')

if [[ -z "$MTG_SECRET" ]]; then
  # Fallback генерация если команда не сработала
  RAND_HEX=$(openssl rand -hex 16)
  DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
  MTG_SECRET="ee${RAND_HEX}${DOMAIN_HEX}"
  info "Секрет сгенерирован вручную"
fi

# Обновляем конфиг с реальным секретом
sed -i "s|MTG_SECRET=\"$MTG_SECRET_PLACEHOLDER\"|MTG_SECRET=\"$MTG_SECRET\"|" "$CONFIG_FILE"
ok "Секрет FakeTLS: ${MTG_SECRET:0:20}..."
done_step

# ── Начальная тема ────────────────────────────────────────────────────────
step "Разворачиваем тему: $INITIAL_THEME"

THEME_SRC="$HIDE_DIR/themes/$INITIAL_THEME"
if [[ -f "$THEME_SRC/index.html" ]]; then
  rm -rf "${WEB_DIR:?}"/*
  cp -r "$THEME_SRC"/. "$WEB_DIR/"
  ok "Тема скопирована"
else
  cat > "$WEB_DIR/index.html" << 'HTML'
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
<title>DevNotes</title></head><body><h1>DevNotes</h1><p>Блог о разработке.</p></body></html>
HTML
fi

printf 'User-agent: *\nDisallow: /\n' > "$WEB_DIR/robots.txt"
chown -R www-data:www-data "$WEB_DIR" 2>/dev/null || true
mkdir -p "$HIDE_DIR/config"
echo "$INITIAL_THEME" > "$HIDE_DIR/config/active_theme"
ok "Активная тема: $INITIAL_THEME"
done_step

# ── nginx ─────────────────────────────────────────────────────────────────
step "Настройка nginx"

rm -f /etc/nginx/sites-enabled/default
mkdir -p /var/www/certbot

# HTTP — только для certbot + редирект
cat > /etc/nginx/sites-available/hipr-http << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

    location / {
        root /var/www/hipr;
        index index.html;
        try_files $uri $uri/ =404;
    }
}
EOF

ln -sf /etc/nginx/sites-available/hipr-http /etc/nginx/sites-enabled/
nginx -t 2>/dev/null || err "Ошибка конфига nginx"
systemctl restart nginx
ok "nginx запущен (HTTP)"
done_step

# ── TLS сертификат ────────────────────────────────────────────────────────
step "TLS сертификат (Let's Encrypt)"

echo ""
MY_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "?")
info "Домен:      ${W}$DOMAIN${N}"
info "IP сервера: ${W}$MY_IP${N}"
info "A-запись $DOMAIN должна вести на $MY_IP"
echo ""
read -rp "  DNS настроен? [Y/n]: " DNS_OK

CERT_OK=false
if [[ "${DNS_OK,,}" != "n" ]]; then
  certbot certonly \
       --webroot -w /var/www/certbot \
       --non-interactive --agree-tos \
       --email "$LE_EMAIL" \
       -d "$DOMAIN" > /tmp/hipr-certbot.log 2>&1 && CERT_OK=true || true
  tail -5 /tmp/hipr-certbot.log

  if [[ "$CERT_OK" == "true" ]]; then
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    ok "Сертификат получен"

    # HTTPS + stream через nginx
    # nginx stream — роутинг по SNI: mtg или сайт
    cat > /etc/nginx/sites-available/hipr-ssl << EOF
# HTTPS сайт-обманка (для active probing ТСПУ и обычных браузеров)
server {
    listen 127.0.0.1:8443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     $CERT_PATH/fullchain.pem;
    ssl_certificate_key $CERT_PATH/privkey.pem;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling        on;
    ssl_stapling_verify on;

    root  /var/www/hipr;
    index index.html;

    add_header Server "nginx";
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / { try_files \$uri \$uri/ =404; }
    location ~* \.(css|js|png|jpg|svg|ico|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    error_page 404 /index.html;

    access_log $HIDE_DIR/logs/nginx-access.log;
    error_log  $HIDE_DIR/logs/nginx-error.log warn;
}
EOF

    ln -sf /etc/nginx/sites-available/hipr-ssl /etc/nginx/sites-enabled/

    # nginx stream — слушает порт 443, по первым байтам решает куда слать
    # Если клиент делает TLS к нашему домену → смотрим на порт назначения
    # mtg слушает на 127.0.0.1:2398 и сам обрабатывает TLS
    # Нам нужен HAProxy или stream-модуль для разделения

    # Проверяем есть ли stream модуль
    if nginx -V 2>&1 | grep -q 'stream'; then
      # Активируем stream-модуль если он динамический и ещё не загружен
      STREAM_MOD=""
      for _p in \
          /usr/lib/nginx/modules/ngx_stream_module.so \
          /usr/share/nginx/modules/ngx_stream_module.so; do
        [[ -f "$_p" ]] && { STREAM_MOD="$_p"; break; }
      done
      if [[ -n "$STREAM_MOD" ]]; then
        if ! grep -rl 'ngx_stream_module' /etc/nginx/modules-enabled/ 2>/dev/null | grep -q .; then
          echo "load_module $STREAM_MOD;" > /etc/nginx/modules-enabled/60-mod-hipr-stream.conf
          ok "Stream модуль активирован: $STREAM_MOD"
        else
          ok "Stream модуль уже загружен"
        fi
      fi
      cat > /etc/nginx/snippets/hipr-stream.conf << EOF
# stream блок для HIPR — роутинг порта 443
# mtg обрабатывает TLS сам, nginx только проксирует TCP
stream {
    upstream hipr_mtg {
        server 127.0.0.1:2398;
    }

    upstream hipr_web {
        server 127.0.0.1:8443;
    }

    # Все соединения на 443 → mtg
    # mtg сам определяет: это Telegram или браузер
    # Для браузеров mtg отдаёт 404 (или мы настроим fallback)
    server {
        listen 443;
        listen [::]:443;
        proxy_pass hipr_mtg;
        proxy_timeout 10m;
        proxy_connect_timeout 10s;
    }
}
EOF
      # Включаем stream в nginx.conf если не включён
      if ! grep -q 'include /etc/nginx/snippets/hipr-stream.conf' /etc/nginx/nginx.conf; then
        echo "include /etc/nginx/snippets/hipr-stream.conf;" >> /etc/nginx/nginx.conf
      fi
      ok "nginx stream настроен (порт 443 → mtg)"
    else
      info "nginx stream модуль не найден — используем HAProxy"
      # Устанавливаем HAProxy для разделения трафика
      apt-get install -y -qq haproxy 2>/dev/null

      cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    maxconn 50000
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    timeout connect 10s
    timeout client  5m
    timeout server  5m
    option tcplog

frontend ft_https
    bind *:443
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }

    # mtg обрабатывает всё — он сам знает что делать с TLS
    default_backend bk_mtg

backend bk_mtg
    server mtg 127.0.0.1:2398 check

backend bk_web
    server nginx 127.0.0.1:8443 check
EOF

      systemctl enable haproxy 2>/dev/null
      systemctl restart haproxy
      ok "HAProxy настроен (порт 443 → mtg)"
    fi

    if nginx -t 2>/tmp/hipr-nginx-test.log; then
      systemctl reload nginx
      ok "nginx перезагружен"
    else
      info "Ошибка конфигурации nginx — детали:"
      cat /tmp/hipr-nginx-test.log >&2
      err "nginx -t упал. Исправьте и запустите: nginx -t && systemctl reload nginx"
    fi

    # Авто-обновление
    (crontab -l 2>/dev/null | grep -v certbot
     echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
    ok "Авто-обновление сертификата (cron 3:00)"
  else
    info "Certbot не смог получить сертификат"
    info "После DNS: hide → Настройки → Получить сертификат"
  fi
else
  info "Пропущено. После DNS: hide → Настройки → Получить сертификат"
fi
done_step

# ── mtg конфиг и сервис ───────────────────────────────────────────────────
step "Настройка mtg как systemd сервиса"

source "$CONFIG_FILE"

# Конфиг для mtg v2
cat > "$HIDE_DIR/config/mtg.toml" << EOF
# HIPR — mtg конфигурация
# Документация: https://github.com/9seconds/mtg

secret = "$MTG_SECRET"

bind-to = "127.0.0.1:$MTG_PORT"

# Telegram DC — меняется через hide → Настройки → Сменить DC
[upstream]
prefer-ip = "prefer-ipv4"
EOF

# Systemd сервис для mtg
cat > /etc/systemd/system/hipr-mtg.service << EOF
[Unit]
Description=HIPR — mtg MTProto Proxy
Documentation=https://github.com/ChernOvOne/HIPR
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
WorkingDirectory=$HIDE_DIR

ExecStart=$MTG_BIN run $HIDE_DIR/config/mtg.toml
ExecReload=/bin/kill -HUP \$MAINPID

Restart=always
RestartSec=5
StartLimitBurst=5
StartLimitInterval=60

StandardOutput=append:$HIDE_DIR/logs/mtg.log
StandardError=append:$HIDE_DIR/logs/mtg-error.log

LimitNOFILE=65536
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hipr-mtg 2>/dev/null

if [[ "$CERT_OK" == "true" ]]; then
  systemctl start hipr-mtg && sleep 2
  if systemctl is-active --quiet hipr-mtg; then
    ok "hipr-mtg запущен"
  else
    info "Сервис не запустился — проверьте: journalctl -u hipr-mtg -n 20"
  fi
else
  info "mtg будет запущен после получения сертификата"
fi
done_step

# ── Watchdog ──────────────────────────────────────────────────────────────
step "Установка watchdog (авто-смена DC)"

cat > "$HIDE_DIR/bin/watchdog.sh" << 'WATCHDOG'
#!/bin/bash
# HIPR Watchdog — следит за доступностью Telegram DC
# Запускается каждые 60 секунд через systemd timer

CONFIG="/opt/hipr/config.env"
LOG="/opt/hipr/logs/watchdog.log"
[[ -f "$CONFIG" ]] && source "$CONFIG"

DCS=(
  "149.154.175.50"
  "149.154.167.51"
  "149.154.175.100"
  "149.154.167.91"
  "91.108.56.130"
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

notify() {
  local msg="$1"
  if [[ -n "${BOT_TOKEN:-}" && -n "${BOT_CHAT_ID:-}" ]]; then
    curl -s --max-time 10 \
      "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d "chat_id=${BOT_CHAT_ID}" \
      -d "text=🔔 HIPR: ${msg}" \
      -d "parse_mode=HTML" > /dev/null 2>&1 || true
  fi
}

check_dc() {
  local ip="$1"
  timeout 5 bash -c "echo '' > /dev/tcp/$ip/443" 2>/dev/null
}

# Проверяем текущий DC
if ! check_dc "${ACTIVE_DC:-149.154.167.51}"; then
  log "WARN: DC ${ACTIVE_DC} недоступен — ищем замену"

  for dc in "${DCS[@]}"; do
    [[ "$dc" == "${ACTIVE_DC:-}" ]] && continue
    if check_dc "$dc"; then
      log "INFO: Переключаемся на DC $dc"

      # Обновляем конфиг
      sed -i "s/ACTIVE_DC=.*/ACTIVE_DC=\"$dc\"/" "$CONFIG"

      # Обновляем mtg.toml — mtg сам определяет DC по IP Telegram
      # Перезапускаем сервис
      systemctl restart hipr-mtg 2>/dev/null || true

      notify "DC переключён: ${ACTIVE_DC} → ${dc}"
      log "INFO: Успешно переключились на $dc"
      exit 0
    fi
  done

  log "ERROR: Все DC недоступны!"
  notify "⚠️ Все Telegram DC недоступны! Проверьте сервер."
else
  log "OK: DC ${ACTIVE_DC} доступен"
fi

# Проверяем что mtg жив
if ! systemctl is-active --quiet hipr-mtg 2>/dev/null; then
  log "WARN: hipr-mtg не запущен — перезапускаем"
  systemctl start hipr-mtg 2>/dev/null || true
  notify "⚠️ mtg был остановлен — перезапущен автоматически"
fi
WATCHDOG

chmod +x "$HIDE_DIR/bin/watchdog.sh"

# Systemd timer для watchdog
cat > /etc/systemd/system/hipr-watchdog.service << EOF
[Unit]
Description=HIPR Watchdog — проверка DC и перезапуск
After=hipr-mtg.service

[Service]
Type=oneshot
ExecStart=$HIDE_DIR/bin/watchdog.sh
StandardOutput=append:$HIDE_DIR/logs/watchdog.log
StandardError=append:$HIDE_DIR/logs/watchdog.log
EOF

cat > /etc/systemd/system/hipr-watchdog.timer << EOF
[Unit]
Description=HIPR Watchdog timer
Requires=hipr-watchdog.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=60s
Unit=hipr-watchdog.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable hipr-watchdog.timer 2>/dev/null
systemctl start hipr-watchdog.timer 2>/dev/null
ok "Watchdog запущен (каждые 60 секунд)"
done_step

# ── fail2ban + ufw ────────────────────────────────────────────────────────
step "Безопасность"

cat > /etc/fail2ban/jail.d/hipr.conf << 'F2B'
[sshd]
enabled  = true
maxretry = 5
bantime  = 3600
findtime = 600
F2B

systemctl enable fail2ban 2>/dev/null
systemctl restart fail2ban 2>/dev/null
ok "fail2ban настроен"

ufw --force reset    > /dev/null 2>&1
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow ssh  > /dev/null 2>&1
ufw allow 80/tcp  > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
ok "ufw: разрешены SSH, 80, 443"
done_step

# ── Итог ──────────────────────────────────────────────────────────────────
source "$CONFIG_FILE"

TG_LINK="tg://proxy?server=${DOMAIN}&port=443&secret=${MTG_SECRET}"
HTTPS_LINK="https://t.me/proxy?server=${DOMAIN}&port=443&secret=${MTG_SECRET}"

echo ""
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}${BOLD}  ✓  HIPR v$VERSION успешно установлен!${N}"
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  ${BOLD}Компоненты:${N}"
echo -e "  ${G}✓${N}  mtg v$MTG_VER (FakeTLS обфускация)"
echo -e "  ${G}✓${N}  nginx + TLS (Let's Encrypt)"
echo -e "  ${G}✓${N}  Сайт-обманка: $INITIAL_THEME"
echo -e "  ${G}✓${N}  Watchdog (авто-смена DC, каждые 60с)"
echo -e "  ${G}✓${N}  fail2ban + ufw"
echo -e "  ${G}✓${N}  Команда: hide"
echo ""
echo -e "  ${BOLD}Ссылка для Telegram:${N}"
echo ""
echo -e "  ${C}${TG_LINK}${N}"
echo ""
echo -e "  ${DIM}Или через браузер:${N}"
echo -e "  ${Y}${HTTPS_LINK}${N}"
echo ""

if command -v qrencode &>/dev/null; then
  echo -e "  ${BOLD}QR-код:${N}\n"
  qrencode -t ANSIUTF8 -l M "$HTTPS_LINK" 2>/dev/null | sed 's/^/  /'
  echo ""
fi

echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "  ${W}hide${N}  — открыть меню управления"
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

if [[ "$CERT_OK" == "false" ]]; then
  echo -e "  ${Y}${BOLD}Осталось: настройте DNS${N}"
  echo -e "  A-запись: ${W}$DOMAIN${N} → ${W}${MY_IP:-IP-сервера}${N}"
  echo -e "  Потом:    ${W}hide${N} → Настройки → Получить сертификат"
  echo ""
fi
