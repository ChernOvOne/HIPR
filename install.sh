#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  HIPR — установщик v4.0
#  https://github.com/ChernOvOne/HIPR
#
#  bash <(curl -fsSL https://raw.githubusercontent.com/ChernOvOne/HIPR/main/install.sh)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Версии ────────────────────────────────────────────────────────────────
VERSION="4.0"
MTG_VER="2.2.0"
DNSPROXY_VER="0.81.0"
GRAFANA_VER="11.6.1"  # Последняя стабильная ветка 11.x (LTS)

# ── Пути ──────────────────────────────────────────────────────────────────
HIDE_DIR="/opt/hipr"
HIDE_BIN="/usr/local/bin/hide"
CONFIG_FILE="$HIDE_DIR/config.env"
WEB_DIR="/var/www/hipr"
MTG_BIN="$HIDE_DIR/bin/mtg"
DNSPROXY_BIN="/usr/local/bin/dnsproxy"
REPO_RAW="https://raw.githubusercontent.com/ChernOvOne/HIPR/main"

# ── Цвета — используем $'...' чтобы работало везде включая read -rp ───────
R=$'\033[0;31m'
G=$'\033[0;32m'
Y=$'\033[1;33m'
B=$'\033[0;34m'
C=$'\033[0;36m'
W=$'\033[1;37m'
N=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'

step()      { echo -e "\n${C}┌─${N} ${BOLD}$*${N}"; }
ok()        { echo -e "${C}│${N}  ${G}✓${N}  $*"; }
info()      { echo -e "${C}│${N}  ${Y}→${N}  $*"; }
warn()      { echo -e "${C}│${N}  ${R}✗${N}  $*"; }
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
  ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝  ╚═╝  v4.0
BANNER
echo -e "${N}"
echo -e "  ${DIM}Telegram MTProto прокси — невидимый для ТСПУ${N}"
echo -e "  ${DIM}https://github.com/ChernOvOne/HIPR${N}"
echo -e "\n${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"

# ── Проверки ──────────────────────────────────────────────────────────────
step "Проверка системы"

[[ $EUID -ne 0 ]] && err "Нужен root: sudo bash install.sh"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  MTG_ARCH="amd64"; DNS_ARCH="linux-amd64"; GRAFANA_ARCH="amd64" ;;
  aarch64) MTG_ARCH="arm64"; DNS_ARCH="linux-arm64"; GRAFANA_ARCH="arm64" ;;
  armv7l)  MTG_ARCH="arm-7"; DNS_ARCH="linux-arm-7"; GRAFANA_ARCH="armv7" ;;
  *) err "Неподдерживаемая архитектура: $ARCH" ;;
esac

ok "OS: $(lsb_release -sd 2>/dev/null || uname -s)"
ok "Архитектура: $ARCH"
curl -sf --max-time 5 https://google.com > /dev/null 2>&1 || err "Нет интернета"
ok "Интернет: есть"
done_step

# ── Детект повторной установки ────────────────────────────────────────────
if [[ -f "$CONFIG_FILE" || -f "$HIDE_BIN" ]]; then
  echo -e "${Y}${BOLD}  ⚠️  Обнаружена существующая установка HIPR${N}\n"
  source "$CONFIG_FILE" 2>/dev/null || true
  [[ -n "${DOMAIN:-}" ]]  && echo -e "  ${DIM}Домен:   $DOMAIN${N}"
  [[ -n "${VERSION:-}" ]] && echo -e "  ${DIM}Версия:  $VERSION${N}"
  [[ -n "${MODE:-}" ]]    && echo -e "  ${DIM}Режим:   $MODE${N}"
  echo ""
  echo -e "  ${C}[1]${N}  🔄  Переустановить (очистить всё и установить заново)"
  echo -e "  ${C}[2]${N}  🚪  Отмена"
  echo ""
  read -rp "  Выберите: " REINSTALL_CHOICE

  if [[ "${REINSTALL_CHOICE}" != "1" ]]; then
    echo -e "\n  Отменено. Для управления используйте: ${W}hide${N}"
    exit 0
  fi

  echo ""
  read -rp "  💾 Сохранить бэкап перед удалением? [Y/n]: " DO_BACKUP
  if [[ "${DO_BACKUP,,}" != "n" ]]; then
    BAK_DIR="/root/hipr_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BAK_DIR"
    [[ -f "$CONFIG_FILE" ]]              && cp "$CONFIG_FILE" "$BAK_DIR/"
    [[ -d "$HIDE_DIR/config" ]]          && cp -r "$HIDE_DIR/config" "$BAK_DIR/"
    [[ -d "$HIDE_DIR/themes/custom" ]]   && cp -r "$HIDE_DIR/themes/custom" "$BAK_DIR/" 2>/dev/null || true
    cp -r /etc/letsencrypt/live "$BAK_DIR/letsencrypt" 2>/dev/null || true
    echo -e "  ${G}💾 Бэкап: $BAK_DIR${N}"
  fi

  echo -e "\n  ${Y}🗑️  Удаляем старую установку...${N}"
  systemctl stop hipr-mtg hipr-mtg@0 hipr-mtg@1 hipr-mtg@2 hipr-mtg@3 hipr-mtg@4 \
    hipr-watchdog.timer dnsproxy prometheus grafana-server 2>/dev/null || true
  systemctl disable hipr-mtg "hipr-mtg@{0..4}" hipr-watchdog.timer \
    hipr-watchdog dnsproxy prometheus grafana-server 2>/dev/null || true
  rm -f /etc/systemd/system/hipr-mtg.service
  rm -f /etc/systemd/system/hipr-mtg@.service
  rm -f /etc/systemd/system/hipr-watchdog.service
  rm -f /etc/systemd/system/hipr-watchdog.timer
  rm -f /etc/systemd/system/dnsproxy.service
  rm -f /etc/systemd/system/prometheus.service
  systemctl daemon-reload
  rm -f /etc/nginx/sites-enabled/hipr-{http,ssl,fallback,grafana}
  rm -f /etc/nginx/sites-available/hipr-{http,ssl,fallback,grafana}
  rm -f /etc/nginx/snippets/hipr-stream.conf
  rm -f /etc/nginx/modules-enabled/60-mod-hipr-stream.conf
  sed -i '/hipr-stream\.conf/d' /etc/nginx/nginx.conf 2>/dev/null || true
  nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  rm -rf /opt/hipr /var/www/hipr /usr/local/bin/hide
  rm -f /usr/local/bin/prometheus /usr/local/bin/promtool
  crontab -l 2>/dev/null | grep -v 'hipr\|certbot' | crontab - 2>/dev/null || true
  killall -9 mtg 2>/dev/null || true
  echo -e "  ${G}✅ Очищено — начинаем установку заново${N}\n"
  sleep 1
fi

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
echo -e "  ${W}Режим работы:${N}"
echo -e "  ${C}[1]${N}  🔒  Обычный    — 1 прокси, 1 SNI домен"
echo -e "  ${C}[2]${N}  🔀  Multi-fronting — до 5 прокси, разные SNI домены"
echo -e "      ${DIM}(рекомендуется для 50+ пользователей)${N}"
echo ""
read -rp "  Режим [1-2, Enter=1]: " MODE_CHOICE
case "${MODE_CHOICE:-1}" in
  2) MODE="multi" ;;
  *) MODE="single" ;;
esac

echo ""
# ── Выбор SNI доменов ─────────────────────────────────────────────────────
if [[ "$MODE" == "single" ]]; then
  echo -e "  ${W}SNI домен для FakeTLS маскировки:${N}"
  echo -e "  ${DIM}Трафик будет выглядеть как обращение к этому домену${N}"
  echo -e "  ${C}[1]${N}  microsoft.com   ${DIM}(рекомендуется)${N}"
  echo -e "  ${C}[2]${N}  avito.ru        ${DIM}(российский, надёжный)${N}"
  echo -e "  ${C}[3]${N}  ozon.ru         ${DIM}(российский, надёжный)${N}"
  echo -e "  ${C}[4]${N}  Свой домен"
  echo ""
  read -rp "  SNI домен [1-4, Enter=1]: " SNI_CHOICE
  case "${SNI_CHOICE:-1}" in
    2) SNI_DOMAINS=("avito.ru") ;;
    3) SNI_DOMAINS=("ozon.ru") ;;
    4) read -rp "  Введите домен: " CUSTOM_SNI
       SNI_DOMAINS=("${CUSTOM_SNI:-microsoft.com}") ;;
    *) SNI_DOMAINS=("microsoft.com") ;;
  esac
else
  echo -e "  ${W}SNI домены для Multi-fronting:${N}"
  echo -e "  ${DIM}Каждый домен = отдельный прокси инстанс${N}\n"
  echo -e "  ${C}[1]${N}  Дефолтный набор ${DIM}(microsoft.com + avito.ru + ozon.ru)${N}"
  echo -e "  ${C}[2]${N}  Настроить вручную"
  echo ""
  read -rp "  Выбор [1-2, Enter=1]: " MF_CHOICE

  if [[ "${MF_CHOICE:-1}" == "2" ]]; then
    SNI_DOMAINS=()
    echo -e "  ${DIM}Введите домены по одному (пустая строка — закончить, минимум 2):${N}"
    while true; do
      read -rp "  Домен $((${#SNI_DOMAINS[@]}+1)): " d
      [[ -z "$d" && ${#SNI_DOMAINS[@]} -ge 2 ]] && break
      [[ -z "$d" ]] && { echo -e "  ${R}Нужно минимум 2 домена${N}"; continue; }
      SNI_DOMAINS+=("$d")
      [[ ${#SNI_DOMAINS[@]} -ge 5 ]] && { echo -e "  ${DIM}Максимум 5 доменов${N}"; break; }
    done
  else
    SNI_DOMAINS=("microsoft.com" "avito.ru" "ozon.ru")
  fi
fi

echo ""
# ── Тема сайта-обманки ────────────────────────────────────────────────────
echo -e "  ${W}Тема сайта-обманки:${N}"
echo -e "  ${DIM}(меняется через hide → Темы)${N}\n"
echo -e "  ${C}[1]${N}  Блог разработчика"
echo -e "  ${C}[2]${N}  Страница фрилансера"
echo -e "  ${C}[3]${N}  «Скоро открытие»"
echo ""
read -rp "  Тема [1-3, Enter=1]: " THEME_CHOICE
case "${THEME_CHOICE:-1}" in
  2) INITIAL_THEME="freelancer" ;;
  3) INITIAL_THEME="coming-soon" ;;
  *) INITIAL_THEME="blog" ;;
esac

# ── Grafana ───────────────────────────────────────────────────────────────
echo ""
echo -e "  ${W}Установить Grafana дашборд?${N} ${DIM}(мониторинг и статистика)${N}"
echo -e "  ${C}[1]${N}  Да — путь ${DIM}https://$DOMAIN/grafana/${N}"
echo -e "  ${C}[2]${N}  Да — поддомен ${DIM}(нужна A-запись)${N}"
echo -e "  ${C}[3]${N}  Нет"
echo ""
read -rp "  Grafana [1-3, Enter=3]: " GRAFANA_CHOICE
case "${GRAFANA_CHOICE:-3}" in
  1) INSTALL_GRAFANA=true; GRAFANA_MODE="path"; GRAFANA_URL="https://$DOMAIN/grafana" ;;
  2) INSTALL_GRAFANA=true; GRAFANA_MODE="subdomain"
     read -rp "  Поддомен (напр. stat.$DOMAIN): " GRAFANA_DOMAIN
     GRAFANA_DOMAIN="${GRAFANA_DOMAIN:-stat.$DOMAIN}"
     GRAFANA_URL="https://$GRAFANA_DOMAIN" ;;
  *) INSTALL_GRAFANA=false; GRAFANA_URL="" ;;
esac

# ── Telegram бот ──────────────────────────────────────────────────────────
echo ""
echo -e "  ${W}Telegram-бот для уведомлений:${N} ${DIM}(необязательно)${N}"
echo -e "  ${DIM}Отчёты, алерты, статистика${N}"
read -rp "  Bot Token (или Enter пропустить): " BOT_TOKEN
BOT_TOKEN="${BOT_TOKEN:-}"
BOT_CHAT_ID=""
if [[ -n "$BOT_TOKEN" ]]; then
  read -rp "  Chat ID: " BOT_CHAT_ID
fi

# ── Итог ввода ────────────────────────────────────────────────────────────
echo ""
echo -e "  ${DIM}─────────────────────────────────────────${N}"
ok "Домен:   $DOMAIN"
ok "Email:   $LE_EMAIL"
ok "Режим:   $MODE"
ok "SNI:     ${SNI_DOMAINS[*]}"
ok "Тема:    $INITIAL_THEME"
[[ "$INSTALL_GRAFANA" == "true" ]] && ok "Grafana: $GRAFANA_URL" || info "Grafana: нет"
[[ -n "$BOT_TOKEN" ]] && ok "Бот:     настроен" || info "Бот:     пропущен"
echo -e "  ${DIM}─────────────────────────────────────────${N}\n"

read -rp "  Начать установку? [Y/n]: " CONFIRM
[[ "${CONFIRM,,}" == "n" ]] && { echo "  Отменено."; exit 0; }
done_step

# ── Пакеты ────────────────────────────────────────────────────────────────
step "Установка пакетов"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  nginx libnginx-mod-stream certbot python3-certbot-nginx \
  curl wget jq bc python3 \
  net-tools netcat-openbsd dnsutils \
  qrencode xxd openssl \
  fail2ban ufw unzip apt-transport-https software-properties-common gnupg 2>/dev/null
ok "Пакеты установлены"

# DNS фикс для российских VPS
if grep -q 'attempts:1' /etc/resolv.conf 2>/dev/null; then
  info "Обнаружен DNS attempts:1 — добавляем публичный резолвер"
  if ! grep -q '1\.1\.1\.1' /etc/resolv.conf; then
    sed -i '/^nameserver/i nameserver 1.1.1.1' /etc/resolv.conf
    awk '!seen[$0]++' /etc/resolv.conf > /tmp/resolv.tmp && mv /tmp/resolv.tmp /etc/resolv.conf
  fi
fi
ok "DNS настроен"
done_step

# ── BBR ───────────────────────────────────────────────────────────────────
step "Оптимизация сети (BBR + sysctl)"

# Определяем версию ядра и выбираем лучший доступный алгоритм
# BBRv3 вошёл в ядро начиная с 6.3 (в нём bbr обновлён до v3 без нового имени модуля)
# BBRv2 — только в патченых ядрах CachyOS/XanMod, в стандартных Ubuntu/Debian недоступен
# BBRv1 — доступен начиная с ядра 4.9
KERNEL_VER=$(uname -r | grep -oP '^\d+\.\d+' | head -1)
KERNEL_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VER" | cut -d. -f2)
BBR_LABEL=""

# Проверяем, какие алгоритмы фактически доступны в ядре
AVAIL_CC=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")

if echo "$AVAIL_CC" | grep -qw "bbr"; then
  # BBR доступен — определяем какой именно по версии ядра
  if (( KERNEL_MAJOR > 6 )) || (( KERNEL_MAJOR == 6 && KERNEL_MINOR >= 3 )); then
    BBR_LABEL="BBRv3 (ядро $KERNEL_VER)"
  elif (( KERNEL_MAJOR > 5 )) || (( KERNEL_MAJOR == 5 && KERNEL_MINOR >= 18 )); then
    BBR_LABEL="BBR (ядро $KERNEL_VER, ≈ v2/v3 черновик)"
  else
    BBR_LABEL="BBRv1 (ядро $KERNEL_VER)"
  fi
  modprobe tcp_bbr 2>/dev/null || true
  ok "Алгоритм: $BBR_LABEL"
else
  # BBR не скомпилирован — пробуем загрузить модуль
  if modprobe tcp_bbr 2>/dev/null; then
    BBR_LABEL="BBRv1 (ядро $KERNEL_VER, загружен модуль)"
    ok "Алгоритм: $BBR_LABEL"
  else
    BBR_LABEL="cubic"
    warn "BBR недоступен на ядре $KERNEL_VER — используем CUBIC"
    info "Для BBRv3: обновитесь до Ubuntu 24.04+ с ядром 6.3+"
  fi
fi

cat > /etc/sysctl.d/99-hipr.conf << SYSCTL
# HIPR — сетевые оптимизации для 100+ пользователей
# Ядро: $KERNEL_VER | Алгоритм: $BBR_LABEL

# Управление перегрузкой
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = $( [[ "$BBR_LABEL" != "cubic" ]] && echo "bbr" || echo "cubic" )

# Буферы
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Очередь соединений
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# TIME_WAIT
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Conntrack
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 300

# Файловые дескрипторы
fs.file-max = 1000000
SYSCTL

sysctl -p /etc/sysctl.d/99-hipr.conf > /dev/null 2>&1 || true

cat > /etc/security/limits.d/hipr.conf << 'LIMITS'
* soft nofile 1000000
* hard nofile 1000000
* soft nproc  65535
* hard nproc  65535
LIMITS

ok "sysctl оптимизирован"
done_step

# ── Директории ────────────────────────────────────────────────────────────
step "Создание структуры"
mkdir -p "$HIDE_DIR"/{bin,logs,config,themes/custom}
mkdir -p "$WEB_DIR"
touch "$HIDE_DIR/logs/watchdog.log" \
      "$HIDE_DIR/logs/nginx-access.log" \
      "$HIDE_DIR/logs/nginx-error.log"
ok "Директории созданы"
done_step

# ── dnsproxy ──────────────────────────────────────────────────────────────
step "Установка dnsproxy (локальный DoH)"

DNSPROXY_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/v${DNSPROXY_VER}/dnsproxy-${DNS_ARCH}-v${DNSPROXY_VER}.tar.gz"
info "Скачиваем dnsproxy v${DNSPROXY_VER}..."

if wget -q "$DNSPROXY_URL" -O /tmp/dnsproxy.tar.gz 2>/dev/null; then
  mkdir -p /tmp/dnsproxy-extract
  tar -xzf /tmp/dnsproxy.tar.gz -C /tmp/dnsproxy-extract/
  find /tmp/dnsproxy-extract -name "dnsproxy" -type f | head -1 | \
    xargs -I{} cp {} "$DNSPROXY_BIN"
  chmod +x "$DNSPROXY_BIN"
  rm -rf /tmp/dnsproxy.tar.gz /tmp/dnsproxy-extract
  ok "dnsproxy установлен: $($DNSPROXY_BIN --version 2>&1 | head -1)"
else
  err "Не удалось скачать dnsproxy"
fi

cat > /etc/systemd/system/dnsproxy.service << 'EOF'
[Unit]
Description=HIPR dnsproxy — локальный DoH сервер
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/dnsproxy \
  --listen=127.0.0.1 \
  --port=5053 \
  --https-port=5443 \
  --upstream=https://cloudflare-dns.com/dns-query \
  --upstream=https://dns.google/dns-query \
  --fallback=77.88.8.8 \
  --fallback=1.1.1.1 \
  --cache \
  --cache-size=4096
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dnsproxy 2>/dev/null
systemctl start dnsproxy
sleep 2

if systemctl is-active --quiet dnsproxy; then
  ok "dnsproxy запущен (DoH: 127.0.0.1:5053)"
  dig microsoft.com @127.0.0.1 -p 5053 +short +time=3 > /dev/null 2>&1 \
    && ok "DNS резолвинг работает" \
    || warn "DNS резолвинг не отвечает — проверьте позже"
else
  warn "dnsproxy не запустился — проверьте: journalctl -u dnsproxy -n 20"
fi
done_step

# ── Скачиваем hide с GitHub ───────────────────────────────────────────────
step "Загрузка hide"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$SCRIPT_DIR/hide" ]]; then
  cp "$SCRIPT_DIR/hide" "$HIDE_BIN"
  ok "hide скопирован локально"
else
  curl -fsSL "$REPO_RAW/hide" -o "$HIDE_BIN" || err "Не удалось скачать hide"
  ok "hide скачан"
fi
chmod +x "$HIDE_BIN"
done_step

# ── Установка mtg ─────────────────────────────────────────────────────────
step "Установка mtg v${MTG_VER}"

MTG_URL="https://github.com/9seconds/mtg/releases/download/v${MTG_VER}/mtg-${MTG_VER}-linux-${MTG_ARCH}.tar.gz"
info "Скачиваем mtg v${MTG_VER} для $MTG_ARCH..."

if wget -q "$MTG_URL" -O /tmp/mtg.tar.gz 2>/dev/null; then
  mkdir -p /tmp/mtg-extract
  tar -xzf /tmp/mtg.tar.gz -C /tmp/mtg-extract/
  find /tmp/mtg-extract -name "mtg" -type f | head -1 | \
    xargs -I{} cp {} "$MTG_BIN"
  rm -rf /tmp/mtg.tar.gz /tmp/mtg-extract
  chmod +x "$MTG_BIN"
  ok "mtg установлен: $($MTG_BIN --version 2>/dev/null | head -1)"
else
  err "Не удалось скачать mtg"
fi

# Создаём пользователя mtgproxy
id mtgproxy &>/dev/null || useradd --system --no-create-home --shell /bin/false mtgproxy
done_step

# ── Генерация секретов и конфигов ─────────────────────────────────────────
step "Генерация секретов MTProto"

declare -a MTG_SECRETS=()
declare -a MTG_PORTS=()
declare -a MTG_PROM_PORTS=()

BASE_PORT=2398
BASE_PROM=3129

for i in "${!SNI_DOMAINS[@]}"; do
  local_sni="${SNI_DOMAINS[$i]}"
  local_port=$((BASE_PORT + i))
  local_prom=$((BASE_PROM + i))
  local_secret=$("$MTG_BIN" generate-secret --hex "$local_sni" 2>/dev/null | tr -d '\n')

  # Fallback генерация если mtg generate-secret не сработал
  if [[ -z "$local_secret" ]]; then
    rh=$(openssl rand -hex 16)
    dh=$(echo -n "$local_sni" | xxd -p | tr -d '\n')
    local_secret="ee${rh}${dh}"
  fi

  MTG_SECRETS+=("$local_secret")
  MTG_PORTS+=("$local_port")
  MTG_PROM_PORTS+=("$local_prom")

  ok "SNI: $local_sni → порт $local_port → секрет ${local_secret:0:20}..."

  # Создаём лог файлы
  touch "$HIDE_DIR/logs/mtg${i}.log" "$HIDE_DIR/logs/mtg${i}-error.log"
  chown mtgproxy:mtgproxy "$HIDE_DIR/logs/mtg${i}.log" \
                           "$HIDE_DIR/logs/mtg${i}-error.log"

  # Конфиг mtg
  mkdir -p "$HIDE_DIR/config"
  cat > "$HIDE_DIR/config/mtg${i}.toml" << EOF
# HIPR — mtg инстанс $i (SNI: $local_sni)
secret = "$local_secret"
bind-to = "127.0.0.1:$local_port"

[network]
  dns = "https://cloudflare-dns.com/dns-query"

[defense.anti-replay]
enabled = true
max-size = "1mib"

[defense.doppelganger]
urls = [
  "https://$local_sni/",
  "https://$local_sni"
]

[stats.prometheus]
enabled = true
bind-to = "127.0.0.1:$local_prom"
http-path = "/metrics"
metric-prefix = "mtg"

[upstream]
prefer-ip = "prefer-ipv4"
EOF

done

done_step

# ── Systemd сервисы mtg ───────────────────────────────────────────────────
step "Systemd сервисы mtg"

if [[ "$MODE" == "single" ]]; then
  cat > /etc/systemd/system/hipr-mtg.service << EOF
[Unit]
Description=HIPR mtg MTProto Proxy (SNI: ${SNI_DOMAINS[0]})
After=network-online.target dnsproxy.service
Wants=network-online.target

[Service]
Type=simple
User=mtgproxy
WorkingDirectory=$HIDE_DIR
ExecStart=$MTG_BIN run $HIDE_DIR/config/mtg0.toml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitInterval=60
StandardOutput=append:$HIDE_DIR/logs/mtg0.log
StandardError=append:$HIDE_DIR/logs/mtg0-error.log
LimitNOFILE=1000000
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
  ok "Сервис hipr-mtg создан"

else
  # Шаблонный сервис для Multi-fronting — %i это индекс (0,1,2...)
  cat > /etc/systemd/system/hipr-mtg@.service << EOF
[Unit]
Description=HIPR mtg MTProto Proxy инстанс %i
After=network-online.target dnsproxy.service
Wants=network-online.target

[Service]
Type=simple
User=mtgproxy
WorkingDirectory=$HIDE_DIR
ExecStart=$MTG_BIN run $HIDE_DIR/config/mtg%i.toml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitInterval=60
StandardOutput=append:$HIDE_DIR/logs/mtg%i.log
StandardError=append:$HIDE_DIR/logs/mtg%i-error.log
LimitNOFILE=1000000
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
  ok "Шаблон hipr-mtg@ создан"
fi

systemctl daemon-reload

# Запускаем инстансы
if [[ "$MODE" == "single" ]]; then
  systemctl enable hipr-mtg 2>/dev/null
  systemctl start hipr-mtg
  sleep 2
  systemctl is-active --quiet hipr-mtg \
    && ok "hipr-mtg запущен" \
    || warn "hipr-mtg не запустился — проверьте: journalctl -u hipr-mtg -n 20"
else
  for i in "${!SNI_DOMAINS[@]}"; do
    systemctl enable "hipr-mtg@${i}" 2>/dev/null
    systemctl start "hipr-mtg@${i}"
    sleep 1
    systemctl is-active --quiet "hipr-mtg@${i}" \
      && ok "hipr-mtg@${i} запущен (${SNI_DOMAINS[$i]})" \
      || warn "hipr-mtg@${i} не запустился — journalctl -u hipr-mtg@${i} -n 20"
  done
fi

done_step

# ── Сохраняем конфиг ──────────────────────────────────────────────────────
step "Сохранение конфигурации"

SNI_DOMAINS_STR=$(IFS='|'; echo "${SNI_DOMAINS[*]}")
MTG_SECRETS_STR=$(IFS='|'; echo "${MTG_SECRETS[*]}")
MTG_PORTS_STR=$(IFS='|'; echo "${MTG_PORTS[*]}")
MTG_PROM_PORTS_STR=$(IFS='|'; echo "${MTG_PROM_PORTS[*]}")

cat > "$CONFIG_FILE" << EOF
# HIPR v${VERSION} — $(date -u +"%Y-%m-%d %H:%M UTC")
DOMAIN="$DOMAIN"
LE_EMAIL="$LE_EMAIL"
MODE="$MODE"
ACTIVE_DC="149.154.167.51"
BOT_TOKEN="$BOT_TOKEN"
BOT_CHAT_ID="$BOT_CHAT_ID"
INSTALL_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VERSION="$VERSION"
INSTALL_GRAFANA="$INSTALL_GRAFANA"
GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_MODE="${GRAFANA_MODE:-}"

# SNI домены и секреты (разделитель |)
SNI_DOMAINS="$SNI_DOMAINS_STR"
MTG_SECRETS="$MTG_SECRETS_STR"
MTG_PORTS="$MTG_PORTS_STR"
MTG_PROM_PORTS="$MTG_PROM_PORTS_STR"

# Compat: первый инстанс как основной
MTG_SECRET="${MTG_SECRETS[0]}"
MTG_PORT="${MTG_PORTS[0]}"
EOF

ok "Конфиг сохранён: $CONFIG_FILE"
done_step

# ── Темы ──────────────────────────────────────────────────────────────────
step "Разворачиваем темы"

mkdir -p "$HIDE_DIR/themes"/{blog,freelancer,coming-soon}

cat > "$HIDE_DIR/themes/blog/theme.json" << 'TJSON'
{"name":"blog","description":"Блог разработчика DevNotes","author":"HIPR","version":"1.0","preview":"Технический блог: Linux, Go, DevOps","pages":["index.html","about.html"]}
TJSON
cat > "$HIDE_DIR/themes/blog/index.html" << 'BLOGEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Заметки о разработке, Linux и DevOps">
<title>DevNotes — заметки разработчика</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f5f5f5;color:#222;line-height:1.7}
a{color:#0066cc;text-decoration:none}a:hover{text-decoration:underline}
header{background:#fff;border-bottom:1px solid #e0e0e0;position:sticky;top:0;z-index:10}
.nav{max-width:880px;margin:0 auto;display:flex;align-items:center;justify-content:space-between;height:54px;padding:0 1.5rem}
.logo{font-weight:700;font-size:1.05rem;color:#111}.logo span{color:#0066cc}
nav{display:flex;gap:1.5rem}nav a{color:#555;font-size:.875rem;font-weight:500}nav a:hover{color:#111;text-decoration:none}
.hero{background:#fff;border-bottom:1px solid #e0e0e0;padding:2.5rem 1.5rem}
.hero-inner{max-width:880px;margin:0 auto}
.hero h1{font-size:1.75rem;font-weight:700;margin-bottom:.4rem;letter-spacing:-.5px}
.hero p{color:#666;font-size:1rem}
main{max-width:880px;margin:0 auto;padding:2rem 1.5rem}
.layout{display:grid;grid-template-columns:1fr 280px;gap:2rem}
@media(max-width:680px){.layout{grid-template-columns:1fr}}
.posts{display:flex;flex-direction:column;gap:1.25rem}
article{background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:1.5rem;transition:border-color .15s}
article:hover{border-color:#bbb}
.meta{font-size:.78rem;color:#999;margin-bottom:.5rem;display:flex;gap:.75rem;align-items:center}
.cat{background:#f0f4ff;color:#0055bb;padding:2px 8px;border-radius:4px;font-size:.72rem;font-weight:600}
article h2{font-size:1.05rem;font-weight:600;margin-bottom:.5rem;line-height:1.4}
article h2 a{color:#111}article h2 a:hover{color:#0066cc;text-decoration:none}
article p{font-size:.875rem;color:#666;line-height:1.6}
.tags{display:flex;gap:.4rem;flex-wrap:wrap;margin-top:.85rem}
.tag{background:#f5f5f5;color:#555;font-size:.72rem;padding:2px 8px;border-radius:4px;border:1px solid #e5e5e5}
.sidebar{display:flex;flex-direction:column;gap:1.25rem}
.widget{background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:1.25rem}
.widget h3{font-size:.85rem;font-weight:700;color:#333;text-transform:uppercase;letter-spacing:.5px;margin-bottom:.85rem;padding-bottom:.6rem;border-bottom:1px solid #f0f0f0}
.widget ul{list-style:none}.widget ul li{padding:.3rem 0;font-size:.875rem;border-bottom:1px solid #f8f8f8}
.widget ul li:last-child{border:none}
.about-text{font-size:.85rem;color:#666;line-height:1.6}
footer{text-align:center;padding:2rem;color:#aaa;font-size:.78rem;border-top:1px solid #e0e0e0;margin-top:1rem;background:#fff}
</style>
</head>
<body>
<header>
  <div class="nav">
    <div class="logo">Dev<span>Notes</span></div>
    <nav><a href="/">Главная</a><a href="/about.html">Обо мне</a></nav>
  </div>
</header>
<div class="hero"><div class="hero-inner">
  <h1>Заметки о разработке</h1>
  <p>Linux, сети, Go и всё что между ними</p>
</div></div>
<main><div class="layout">
  <div class="posts">
    <article>
      <div class="meta"><span>14 ноября 2024</span><span>·</span><span>9 мин</span><span class="cat">DevOps</span></div>
      <h2><a href="#">Настройка nginx как reverse proxy: полный разбор</a></h2>
      <p>Конфигурация nginx для проксирования, SSL termination, кеширование upstream-ответов и типичные ошибки в продакшне которые я видел чаще всего.</p>
      <div class="tags"><span class="tag">nginx</span><span class="tag">linux</span><span class="tag">ssl</span></div>
    </article>
    <article>
      <div class="meta"><span>29 октября 2024</span><span>·</span><span>6 мин</span><span class="cat">Go</span></div>
      <h2><a href="#">Go для системных задач: личный опыт после Python</a></h2>
      <p>Три года писал всё на Python — скрипты, утилиты, небольшие сервисы. Попробовал Go и теперь понимаю где что реально лучше.</p>
      <div class="tags"><span class="tag">golang</span><span class="tag">python</span><span class="tag">cli</span></div>
    </article>
    <article>
      <div class="meta"><span>7 октября 2024</span><span>·</span><span>13 мин</span><span class="cat">Security</span></div>
      <h2><a href="#">TLS 1.3: что изменилось и как правильно настроить сервер</a></h2>
      <p>Разбираем новый handshake, отказ от RSA key exchange, 0-RTT и почему правильная настройка шифров важнее чем кажется.</p>
      <div class="tags"><span class="tag">tls</span><span class="tag">security</span><span class="tag">nginx</span></div>
    </article>
    <article>
      <div class="meta"><span>20 сентября 2024</span><span>·</span><span>7 мин</span><span class="cat">Linux</span></div>
      <h2><a href="#">systemd юниты: всё что нужно для повседневной работы</a></h2>
      <p>Написание unit-файлов, зависимости между сервисами, автозапуск, ограничение ресурсов и почему journalctl лучше tail -f.</p>
      <div class="tags"><span class="tag">systemd</span><span class="tag">linux</span></div>
    </article>
    <article>
      <div class="meta"><span>3 сентября 2024</span><span>·</span><span>5 мин</span><span class="cat">Networking</span></div>
      <h2><a href="#">iptables vs nftables: что выбрать в 2024</a></h2>
      <p>Сравниваю синтаксис, производительность и удобство. Для новых серверов уже нет причин оставаться на iptables.</p>
      <div class="tags"><span class="tag">networking</span><span class="tag">firewall</span><span class="tag">linux</span></div>
    </article>
  </div>
  <aside class="sidebar">
    <div class="widget">
      <h3>Об авторе</h3>
      <p class="about-text">Бэкенд разработчик, пишу про Linux и сети. Блог — личный архив заметок.</p>
    </div>
    <div class="widget">
      <h3>Темы</h3>
      <ul>
        <li><a href="#">Linux &amp; sysadmin</a></li>
        <li><a href="#">Go / Golang</a></li>
        <li><a href="#">nginx &amp; веб</a></li>
        <li><a href="#">Безопасность</a></li>
        <li><a href="#">Сети</a></li>
        <li><a href="#">DevOps</a></li>
      </ul>
    </div>
  </aside>
</div></main>
<footer>© 2024 DevNotes · Сделано с кофе и vim</footer>
</body></html>
BLOGEOF

cat > "$HIDE_DIR/themes/blog/about.html" << 'BLOGABOUTEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Обо мне — DevNotes</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f5f5f5;color:#222;line-height:1.7}
a{color:#0066cc;text-decoration:none}a:hover{text-decoration:underline}
header{background:#fff;border-bottom:1px solid #e0e0e0;position:sticky;top:0;z-index:10}
.nav{max-width:880px;margin:0 auto;display:flex;align-items:center;justify-content:space-between;height:54px;padding:0 1.5rem}
.logo{font-weight:700;font-size:1.05rem;color:#111}.logo span{color:#0066cc}
nav{display:flex;gap:1.5rem}nav a{color:#555;font-size:.875rem;font-weight:500}
.hero{background:#fff;border-bottom:1px solid #e0e0e0;padding:2.5rem 1.5rem}
.hero-inner{max-width:880px;margin:0 auto}
.hero h1{font-size:1.75rem;font-weight:700;margin-bottom:.4rem}
.hero p{color:#666}
main{max-width:680px;margin:2rem auto;padding:0 1.5rem}
.card{background:#fff;border:1px solid #e0e0e0;border-radius:8px;padding:2rem;margin-bottom:1.5rem}
.card h2{font-size:1.1rem;font-weight:700;margin-bottom:1rem;color:#111}
.card p{color:#555;font-size:.9rem;margin-bottom:.75rem}
.stack{display:flex;flex-wrap:wrap;gap:.4rem;margin-top:.75rem}
.tag{background:#f0f4ff;color:#0055bb;padding:3px 10px;border-radius:4px;font-size:.75rem;font-weight:600}
footer{text-align:center;padding:2rem;color:#aaa;font-size:.78rem;border-top:1px solid #e0e0e0;background:#fff;margin-top:1rem}
</style>
</head>
<body>
<header>
  <div class="nav">
    <div class="logo">Dev<span>Notes</span></div>
    <nav><a href="/">Главная</a><a href="/about.html">Обо мне</a></nav>
  </div>
</header>
<div class="hero"><div class="hero-inner">
  <h1>Обо мне</h1>
  <p>Бэкенд разработчик, люблю Linux и инфраструктуру</p>
</div></div>
<main>
  <div class="card">
    <h2>Кто я</h2>
    <p>Пишу бэкенд уже 6 лет. Начинал с Python, последние три года активно использую Go для системных задач и сервисов.</p>
    <p>Этот блог — личный архив заметок. Пишу когда решаю интересную задачу и хочу зафиксировать подход.</p>
  </div>
  <div class="card">
    <h2>Стек</h2>
    <div class="stack">
      <span class="tag">Go</span><span class="tag">Python</span><span class="tag">Linux</span>
      <span class="tag">nginx</span><span class="tag">PostgreSQL</span><span class="tag">Docker</span>
      <span class="tag">systemd</span><span class="tag">nftables</span>
    </div>
  </div>
  <div class="card">
    <h2>Контакт</h2>
    <p>GitHub: <a href="#">github.com/devnotes</a></p>
    <p>Email: dev@example.com</p>
  </div>
</main>
<footer>© 2024 DevNotes · Сделано с кофе и vim</footer>
</body></html>
BLOGABOUTEOF
ok "Тема: blog"

cat > "$HIDE_DIR/themes/freelancer/theme.json" << 'TJSON'
{"name":"freelancer","description":"Страница фрилансера","author":"HIPR","version":"1.0","preview":"Портфолио: веб, мобайл, API","pages":["index.html"]}
TJSON
cat > "$HIDE_DIR/themes/freelancer/index.html" << 'FREELANCEREOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Фриланс разработчик — веб и мобильные приложения">
<title>Алексей Соколов — Разработчик</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#1a1a2e;line-height:1.6;background:#f8f9ff}
a{color:#4361ee;text-decoration:none}a:hover{text-decoration:underline}
header{background:#fff;border-bottom:1px solid #e8eaf6;padding:0 2rem;position:sticky;top:0;z-index:10}
.nav{max-width:960px;margin:0 auto;display:flex;align-items:center;justify-content:space-between;height:60px}
.logo{font-weight:800;font-size:1.1rem;letter-spacing:-.5px}
nav a{margin-left:2rem;color:#555;font-size:.875rem;font-weight:500}
.hero{background:linear-gradient(135deg,#4361ee 0%,#3a0ca3 100%);color:#fff;padding:5rem 2rem;text-align:center}
.hero-inner{max-width:680px;margin:0 auto}
.badge{display:inline-block;background:rgba(255,255,255,.2);padding:4px 14px;border-radius:20px;font-size:.78rem;font-weight:600;letter-spacing:.5px;margin-bottom:1.5rem}
.hero h1{font-size:2.5rem;font-weight:800;margin-bottom:1rem;line-height:1.2}
.hero p{font-size:1.1rem;opacity:.9;margin-bottom:2rem}
.btns{display:flex;gap:1rem;justify-content:center;flex-wrap:wrap}
.btn{padding:.75rem 2rem;border-radius:8px;font-weight:600;font-size:.9rem;cursor:pointer}
.btn-white{background:#fff;color:#4361ee}
.btn-outline{background:transparent;color:#fff;border:2px solid rgba(255,255,255,.6)}
section{padding:4rem 2rem}
.sec-inner{max-width:960px;margin:0 auto}
.sec-title{font-size:1.5rem;font-weight:800;margin-bottom:.5rem}
.sec-sub{color:#666;margin-bottom:2.5rem}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:1.5rem}
.card{background:#fff;border-radius:12px;padding:1.75rem;border:1px solid #e8eaf6;transition:box-shadow .2s}
.card:hover{box-shadow:0 4px 20px rgba(67,97,238,.1)}
.card-icon{font-size:2rem;margin-bottom:1rem}
.card h3{font-size:1rem;font-weight:700;margin-bottom:.5rem}
.card p{font-size:.875rem;color:#666}
.stack{display:flex;flex-wrap:wrap;gap:.5rem;margin-top:1rem}
.tag{background:#f0f3ff;color:#4361ee;padding:3px 10px;border-radius:6px;font-size:.75rem;font-weight:600}
.projects{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:1.5rem}
.proj{background:#fff;border-radius:12px;border:1px solid #e8eaf6;overflow:hidden}
.proj-img{height:160px;display:flex;align-items:center;justify-content:center;font-size:3rem}
.proj-img.blue{background:linear-gradient(135deg,#667eea,#764ba2)}
.proj-img.green{background:linear-gradient(135deg,#43e97b,#38f9d7)}
.proj-img.orange{background:linear-gradient(135deg,#f093fb,#f5576c)}
.proj-body{padding:1.25rem}
.proj-body h3{font-weight:700;margin-bottom:.4rem}
.proj-body p{font-size:.85rem;color:#666}
.contact-bg{background:#1a1a2e;color:#fff;text-align:center}
.contact-bg .sec-sub{color:rgba(255,255,255,.6)}
.input{width:100%;padding:.75rem 1rem;border-radius:8px;border:1px solid #e8eaf6;font-size:.9rem;margin-bottom:1rem;font-family:inherit}
.form-grid{display:grid;grid-template-columns:1fr 1fr;gap:1rem;max-width:560px;margin:0 auto}
@media(max-width:600px){.form-grid{grid-template-columns:1fr}.hero h1{font-size:1.8rem}}
footer{text-align:center;padding:1.5rem;background:#111;color:#555;font-size:.78rem}
</style>
</head>
<body>
<header>
  <div class="nav">
    <div class="logo">Алексей<span style="color:#4361ee">.</span>dev</div>
    <nav>
      <a href="#services">Услуги</a>
      <a href="#projects">Проекты</a>
      <a href="#contact">Контакт</a>
    </nav>
  </div>
</header>
<div class="hero">
  <div class="hero-inner">
    <div class="badge">✦ Доступен для новых проектов</div>
    <h1>Разрабатываю веб-сервисы и мобильные приложения</h1>
    <p>5 лет опыта · 40+ завершённых проектов · React, Node.js, Flutter</p>
    <div class="btns">
      <a href="#contact" class="btn btn-white">Обсудить проект</a>
      <a href="#projects" class="btn btn-outline">Посмотреть работы</a>
    </div>
  </div>
</div>
<section id="services" style="background:#fff">
  <div class="sec-inner">
    <div class="sec-title">Чем могу помочь</div>
    <div class="sec-sub">Полный цикл разработки от идеи до продакшна</div>
    <div class="cards">
      <div class="card"><div class="card-icon">🌐</div><h3>Веб-приложения</h3><p>SPA, лендинги, административные панели, корпоративные сайты</p><div class="stack"><span class="tag">React</span><span class="tag">Next.js</span><span class="tag">TypeScript</span></div></div>
      <div class="card"><div class="card-icon">📱</div><h3>Мобильные приложения</h3><p>Кроссплатформенные приложения под iOS и Android</p><div class="stack"><span class="tag">Flutter</span><span class="tag">Dart</span><span class="tag">Firebase</span></div></div>
      <div class="card"><div class="card-icon">⚙️</div><h3>Бэкенд и API</h3><p>REST/GraphQL API, микросервисы, интеграции с внешними сервисами</p><div class="stack"><span class="tag">Node.js</span><span class="tag">PostgreSQL</span><span class="tag">Docker</span></div></div>
    </div>
  </div>
</section>
<section id="projects">
  <div class="sec-inner">
    <div class="sec-title">Последние проекты</div>
    <div class="sec-sub">Некоторые из недавних работ</div>
    <div class="projects">
      <div class="proj"><div class="proj-img blue">📊</div><div class="proj-body"><h3>Аналитическая платформа</h3><p>Дашборд для мониторинга бизнес-метрик в реальном времени. React + D3.js + WebSocket</p></div></div>
      <div class="proj"><div class="proj-img green">🛒</div><div class="proj-body"><h3>Мобильный маркетплейс</h3><p>Flutter-приложение с каталогом, корзиной и оплатой. 10k+ установок</p></div></div>
      <div class="proj"><div class="proj-img orange">💬</div><div class="proj-body"><h3>CRM для агентства</h3><p>Система управления клиентами и сделками. Node.js + PostgreSQL + React</p></div></div>
    </div>
  </div>
</section>
<section id="contact" class="contact-bg">
  <div class="sec-inner">
    <div class="sec-title">Свяжитесь со мной</div>
    <div class="sec-sub">Расскажите о вашем проекте — отвечу в течение 24 часов</div>
    <div style="max-width:560px;margin:0 auto">
      <div class="form-grid">
        <input class="input" placeholder="Ваше имя" type="text">
        <input class="input" placeholder="Email" type="email">
      </div>
      <input class="input" placeholder="Тема" type="text" style="display:block;max-width:560px;margin:0 auto 1rem">
      <textarea class="input" rows="4" placeholder="Расскажите о проекте..." style="display:block;max-width:560px;margin:0 auto 1rem;resize:vertical"></textarea>
      <div style="text-align:center"><button class="btn btn-white" style="background:#4361ee;color:#fff">Отправить сообщение</button></div>
    </div>
  </div>
</section>
<footer>© 2024 alexei.dev · Все права защищены</footer>
</body></html>
FREELANCEREOF
ok "Тема: freelancer"

cat > "$HIDE_DIR/themes/coming-soon/theme.json" << 'TJSON'
{"name":"coming-soon","description":"Скоро открытие","author":"HIPR","version":"1.0","preview":"Таймер обратного отсчёта","pages":["index.html"]}
TJSON
cat > "$HIDE_DIR/themes/coming-soon/index.html" << 'COMINGEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Скоро открытие — подпишитесь чтобы узнать первым">
<title>Скоро открытие</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0f0f1a;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:2rem;overflow:hidden}
.bg{position:fixed;inset:0;z-index:0;background:radial-gradient(ellipse at 20% 50%,rgba(99,102,241,.15) 0%,transparent 60%),radial-gradient(ellipse at 80% 20%,rgba(168,85,247,.12) 0%,transparent 60%),radial-gradient(ellipse at 60% 80%,rgba(59,130,246,.1) 0%,transparent 60%)}
.content{position:relative;z-index:1;max-width:560px;width:100%}
.logo{display:inline-flex;align-items:center;gap:.6rem;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);padding:.5rem 1.25rem;border-radius:50px;margin-bottom:3rem;font-size:.85rem;font-weight:600;letter-spacing:.5px;color:rgba(255,255,255,.8)}
.logo-dot{width:8px;height:8px;border-radius:50%;background:#6366f1;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.5;transform:scale(.8)}}
h1{font-size:clamp(2rem,5vw,3.25rem);font-weight:800;line-height:1.15;margin-bottom:1.25rem;background:linear-gradient(135deg,#fff 0%,rgba(255,255,255,.7) 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.sub{color:rgba(255,255,255,.5);font-size:1.05rem;margin-bottom:3rem;line-height:1.6}
.counter{display:flex;justify-content:center;gap:1.5rem;margin-bottom:3rem;flex-wrap:wrap}
.count-item{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08);border-radius:12px;padding:1.25rem 1.5rem;min-width:80px}
.count-num{font-size:2rem;font-weight:800;line-height:1;color:#a5b4fc}
.count-label{font-size:.7rem;color:rgba(255,255,255,.4);margin-top:.3rem;text-transform:uppercase;letter-spacing:.5px}
.form{display:flex;gap:.75rem;max-width:420px;margin:0 auto 1.5rem;flex-wrap:wrap;justify-content:center}
.input{flex:1;min-width:200px;padding:.8rem 1.25rem;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.07);color:#fff;font-size:.9rem;outline:none;font-family:inherit}
.input::placeholder{color:rgba(255,255,255,.35)}
.input:focus{border-color:rgba(99,102,241,.6);background:rgba(255,255,255,.1)}
.btn{padding:.8rem 1.75rem;border-radius:10px;border:none;background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;font-weight:700;font-size:.9rem;cursor:pointer;white-space:nowrap;font-family:inherit}
.btn:hover{opacity:.9}
.hint{color:rgba(255,255,255,.3);font-size:.78rem}
.socials{display:flex;gap:1rem;justify-content:center;margin-top:3rem}
.soc{width:40px;height:40px;border-radius:10px;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);color:rgba(255,255,255,.5);font-size:.9rem;transition:.2s}
.soc:hover{background:rgba(255,255,255,.12);color:#fff}
</style>
</head>
<body>
<div class="bg"></div>
<div class="content">
  <div class="logo"><span class="logo-dot"></span>В разработке</div>
  <h1>Что-то крутое скоро появится</h1>
  <p class="sub">Мы работаем над чем-то особенным.<br>Подпишитесь — пришлём письмо в день запуска.</p>
  <div class="counter">
    <div class="count-item"><div class="count-num" id="days">14</div><div class="count-label">Дней</div></div>
    <div class="count-item"><div class="count-num" id="hours">08</div><div class="count-label">Часов</div></div>
    <div class="count-item"><div class="count-num" id="mins">23</div><div class="count-label">Минут</div></div>
    <div class="count-item"><div class="count-num" id="secs">41</div><div class="count-label">Секунд</div></div>
  </div>
  <div class="form">
    <input class="input" type="email" placeholder="Ваш email">
    <button class="btn">Уведомить меня</button>
  </div>
  <p class="hint">Никакого спама. Только одно письмо в день запуска.</p>
  <div class="socials">
    <a href="#" class="soc">TG</a>
    <a href="#" class="soc">GH</a>
    <a href="#" class="soc">TW</a>
  </div>
</div>
<script>
  const launch = new Date(Date.now() + 14*24*60*60*1000);
  function tick(){
    const d = launch - Date.now();
    if(d < 0) return;
    document.getElementById('days').textContent  = String(Math.floor(d/864e5)).padStart(2,'0');
    document.getElementById('hours').textContent = String(Math.floor(d%864e5/36e5)).padStart(2,'0');
    document.getElementById('mins').textContent  = String(Math.floor(d%36e5/6e4)).padStart(2,'0');
    document.getElementById('secs').textContent  = String(Math.floor(d%6e4/1e3)).padStart(2,'0');
  }
  tick(); setInterval(tick,1000);
</script>
</body></html>
COMINGEOF
ok "Тема: coming-soon"

# Копируем начальную тему
THEME_SRC="$HIDE_DIR/themes/$INITIAL_THEME"
rm -rf "${WEB_DIR:?}"/*
cp -r "$THEME_SRC"/. "$WEB_DIR/"
printf 'User-agent: *\nDisallow: /\n' > "$WEB_DIR/robots.txt"
chown -R www-data:www-data "$WEB_DIR" 2>/dev/null || true
echo "$INITIAL_THEME" > "$HIDE_DIR/config/active_theme"
ok "Активная тема: $INITIAL_THEME"
done_step

# ── nginx ─────────────────────────────────────────────────────────────────
step "Настройка nginx"

rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/hipr-{ssl,fallback}
rm -f /etc/nginx/sites-available/hipr-{ssl,fallback}
rm -f /etc/nginx/snippets/hipr-stream.conf
rm -f /etc/nginx/modules-enabled/60-mod-hipr-stream.conf
sed -i '/hipr-stream\.conf/d' /etc/nginx/nginx.conf
mkdir -p /var/www/certbot /etc/nginx/snippets

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

if nginx -t 2>/tmp/hipr-nginx-http.log; then
  systemctl restart nginx
  ok "nginx запущен (HTTP)"
else
  warn "nginx -t упал:"
  cat /tmp/hipr-nginx-http.log >&2
  warn "Продолжаем — исправьте nginx вручную после установки"
fi
done_step

# ── TLS сертификат ────────────────────────────────────────────────────────
step "TLS сертификат (Let's Encrypt)"

echo ""
MY_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "?")
info "Домен:      ${W}$DOMAIN${N}"
info "IP сервера: ${W}$MY_IP${N}"
info "A-запись $DOMAIN → $MY_IP должна быть настроена"
echo ""
read -rp "  DNS настроен? [Y/n]: " DNS_OK

CERT_OK=false
CERT_DOMAINS="-d $DOMAIN"

if [[ "${GRAFANA_MODE:-}" == "subdomain" ]]; then
  info "Домен Grafana:  ${W}$GRAFANA_DOMAIN${N}"
  info "A-запись $GRAFANA_DOMAIN → $MY_IP тоже нужна"
  CERT_DOMAINS="-d $DOMAIN -d $GRAFANA_DOMAIN"
fi

if [[ "${DNS_OK,,}" != "n" ]]; then
  certbot certonly \
    --webroot -w /var/www/certbot \
    --non-interactive --agree-tos \
    --email "$LE_EMAIL" \
    $CERT_DOMAINS > /tmp/hipr-certbot.log 2>&1 && CERT_OK=true || true
  tail -5 /tmp/hipr-certbot.log

  if [[ "$CERT_OK" == "true" ]]; then
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    ok "Сертификат получен"

    cat > /etc/nginx/conf.d/hipr-logformat.conf << 'EOF'
log_format hipr_detailed '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         '$request_time $ssl_protocol';
EOF

    cat > /etc/nginx/sites-available/hipr-ssl << EOF
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

    root  $WEB_DIR;
    index index.html;

    add_header Server "nginx";
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Content-Type-Options "nosniff" always;

    access_log $HIDE_DIR/logs/nginx-access.log hipr_detailed;
    error_log  $HIDE_DIR/logs/nginx-error.log warn;

    location / {
        try_files \$uri \$uri/ =404;
    }

    error_page 404 /index.html;
}
EOF

    ln -sf /etc/nginx/sites-available/hipr-ssl /etc/nginx/sites-enabled/

    # Строим nginx stream SNI карту
    STREAM_MAP=""
    for i in "${!SNI_DOMAINS[@]}"; do
      STREAM_MAP="${STREAM_MAP}        ${SNI_DOMAINS[$i]}   127.0.0.1:${MTG_PORTS[$i]};\n"
    done

    dpkg -l libnginx-mod-stream 2>/dev/null | grep -q '^ii' || \
      apt-get install -y -qq libnginx-mod-stream 2>/dev/null

    cat > /etc/nginx/snippets/hipr-stream.conf << EOF
stream {
    map \$ssl_preread_server_name \$hipr_backend {
$(echo -e "$STREAM_MAP")        default         127.0.0.1:8443;
    }

    server {
        listen 443;
        listen [::]:443;
        proxy_pass            \$hipr_backend;
        ssl_preread           on;
        proxy_timeout         10m;
        proxy_connect_timeout 10s;
    }
}
EOF

    if ! grep -q 'hipr-stream.conf' /etc/nginx/nginx.conf; then
      echo "include /etc/nginx/snippets/hipr-stream.conf;" >> /etc/nginx/nginx.conf
    fi
    ok "nginx stream настроен (SNI роутинг: ${SNI_DOMAINS[*]})"

    if nginx -t 2>/tmp/hipr-nginx-test.log; then
      systemctl reload nginx
      ok "nginx перезагружен"
    else
      warn "nginx -t упал:"
      cat /tmp/hipr-nginx-test.log >&2
    fi

    (crontab -l 2>/dev/null | grep -v certbot
     echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
    ok "Авто-обновление сертификата (cron 3:00)"

  else
    warn "Certbot не смог получить сертификат"
    info "После DNS: hide → [6] Настройки → Обновить TLS сертификат"
  fi
else
  info "Пропущено. После DNS: hide → [6] Настройки → Обновить TLS сертификат"
fi
done_step

# ── Grafana + Prometheus ───────────────────────────────────────────────────
if [[ "$INSTALL_GRAFANA" == "true" ]]; then
  step "Установка Prometheus + Grafana"

  # ── Prometheus ──────────────────────────────────────────────────────────
  PROM_ARCH="${MTG_ARCH}"

  info "Определяем последнюю версию Prometheus..."
  PROM_VER=$(curl -sf --max-time 10 \
    "https://api.github.com/repos/prometheus/prometheus/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" \
    2>/dev/null || echo "2.51.0")

  info "Prometheus v$PROM_VER ($PROM_ARCH)..."
  PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-${PROM_ARCH}.tar.gz"

  PROM_OK=false
  if wget -q "$PROM_URL" -O /tmp/prometheus.tar.gz 2>/dev/null; then
    useradd --system --no-create-home --shell /bin/false prometheus 2>/dev/null || true
    mkdir -p /etc/prometheus /var/lib/prometheus

    mkdir -p /tmp/prometheus-extract
    tar -xzf /tmp/prometheus.tar.gz -C /tmp/prometheus-extract/
    find /tmp/prometheus-extract -name "prometheus" -type f | head -1 | \
      xargs -I{} cp {} /usr/local/bin/prometheus
    find /tmp/prometheus-extract -name "promtool" -type f | head -1 | \
      xargs -I{} cp {} /usr/local/bin/promtool
    chmod +x /usr/local/bin/prometheus /usr/local/bin/promtool
    rm -rf /tmp/prometheus.tar.gz /tmp/prometheus-extract

    # Конфиг YAML — каждый target получает метку sni для читаемых имён в Grafana
    {
      echo "global:"
      echo "  scrape_interval: 15s"
      echo "  evaluation_interval: 15s"
      echo ""
      echo "scrape_configs:"
      echo "  - job_name: 'hipr_mtg'"
      echo "    static_configs:"
      for i in "${!MTG_PROM_PORTS[@]}"; do
        echo "      - targets: ['127.0.0.1:${MTG_PROM_PORTS[$i]}']"
        echo "        labels:"
        echo "          sni: '${SNI_DOMAINS[$i]}'"
      done
      echo "    relabel_configs:"
      echo "      - source_labels: [sni]"
      echo "        target_label: instance"
    } > /etc/prometheus/prometheus.yml

    # Проверяем что YAML валидный
    if /usr/local/bin/promtool check config /etc/prometheus/prometheus.yml > /dev/null 2>&1; then
      ok "prometheus.yml валидный"
    else
      warn "prometheus.yml невалидный — пересоздаём минимальный конфиг"
      cat > /etc/prometheus/prometheus.yml << 'PMINYML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'hipr_mtg'
    static_configs:
      - targets: ['127.0.0.1:3129']
PMINYML
    fi

    cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.listen-address=127.0.0.1:9090 \
  --log.level=warn
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Права — критично, без этого prometheus не стартует
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
    chmod 755 /etc/prometheus /var/lib/prometheus
    chmod 644 /etc/prometheus/prometheus.yml

    systemctl daemon-reload
    systemctl enable prometheus 2>/dev/null
    systemctl start prometheus
    sleep 3

    if systemctl is-active --quiet prometheus; then
      ok "Prometheus запущен (127.0.0.1:9090)"
      PROM_OK=true
    else
      warn "Prometheus не запустился"
      # Диагностика
      PROM_ERR=$(journalctl -u prometheus -n 5 --no-pager 2>/dev/null | tail -3)
      warn "Лог: $PROM_ERR"
    fi
  else
    warn "Не удалось скачать Prometheus — пропускаем"
  fi

  # ── Grafana ─────────────────────────────────────────────────────────────
  info "Grafana — пробуем установить..."
  GRAFANA_OK=false

  # Определяем архитектуру для deb имени файла
  case "$MTG_ARCH" in
    amd64)  GRAFANA_ARCH_DEB="amd64" ;;
    arm64)  GRAFANA_ARCH_DEB="arm64" ;;
    arm-7)  GRAFANA_ARCH_DEB="armhf" ;;
    *)      GRAFANA_ARCH_DEB="amd64" ;;
  esac

  # Метод 1: APT-репозиторий Grafana (может быть заблокирован с РФ-IP)
  info "Метод 1: apt.grafana.com (официальный репозиторий)..."
  mkdir -p /etc/apt/keyrings
  if curl -fsSL --max-time 15 https://apt.grafana.com/gpg.key \
       -o /tmp/grafana.gpg 2>/dev/null \
     && gpg --dearmor < /tmp/grafana.gpg > /etc/apt/keyrings/grafana.gpg 2>/dev/null; then
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
      > /etc/apt/sources.list.d/grafana.list
    if apt-get update -qq 2>/dev/null \
       && apt-get install -y -qq grafana 2>/dev/null; then
      GRAFANA_OK=true
      ok "Grafana установлена через APT"
    fi
  fi
  rm -f /tmp/grafana.gpg

  # Метод 2: dl.grafana.com — официальный CDN Grafana Labs (не GitHub!)
  # GitHub Releases у Grafana содержит только исходники, .deb там нет
  if [[ "$GRAFANA_OK" == "false" ]]; then
    warn "APT-репозиторий недоступен (вероятно 403 с РФ-IP)"
    info "Метод 2: dl.grafana.com (официальный CDN, OSS edition)..."

    # Пробуем получить актуальную версию через API
    GRAFANA_DL_VER=$(curl -sf --max-time 10 \
      "https://grafana.com/api/grafana/versions/stable" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" \
      2>/dev/null || echo "")
    # Fallback на захардкоженную версию если API недоступен
    [[ -z "$GRAFANA_DL_VER" ]] && GRAFANA_DL_VER="${GRAFANA_VER}"

    info "Версия: $GRAFANA_DL_VER, архитектура: $GRAFANA_ARCH_DEB"

    # Зависимости для .deb
    apt-get install -y -qq adduser libfontconfig1 musl 2>/dev/null || \
      apt-get install -y -qq adduser libfontconfig1 2>/dev/null || true

    GRAFANA_DEB_URL="https://dl.grafana.com/oss/release/grafana_${GRAFANA_DL_VER}_${GRAFANA_ARCH_DEB}.deb"
    info "URL: $GRAFANA_DEB_URL"

    if wget -q --show-progress "$GRAFANA_DEB_URL" -O /tmp/grafana.deb 2>&1 | \
         grep -v "^$" | tail -2; then
      if [[ -f /tmp/grafana.deb && $(stat -c%s /tmp/grafana.deb 2>/dev/null) -gt 10000 ]]; then
        if dpkg -i /tmp/grafana.deb 2>/dev/null; then
          apt-get install -f -y -qq 2>/dev/null || true
          GRAFANA_OK=true
          ok "Grafana $GRAFANA_DL_VER установлена через dl.grafana.com"
        else
          warn "dpkg -i завершился с ошибкой"
          apt-get install -f -y -qq 2>/dev/null || true
          [[ -f /etc/grafana/grafana.ini ]] && GRAFANA_OK=true
        fi
      else
        warn "Скачанный файл пустой или слишком маленький"
      fi
      rm -f /tmp/grafana.deb
    else
      warn "wget не смог скачать .deb с dl.grafana.com"
      info "Проверьте вручную: curl -I '$GRAFANA_DEB_URL'"
    fi
  fi

  if [[ "$GRAFANA_OK" == "false" || ! -f /etc/grafana/grafana.ini ]]; then
    warn "Grafana не установилась — пропускаем"
    warn "Установить вручную:"
    warn "  wget https://dl.grafana.com/oss/release/grafana_${GRAFANA_VER}_${GRAFANA_ARCH_DEB}.deb"
    warn "  dpkg -i grafana_${GRAFANA_VER}_${GRAFANA_ARCH_DEB}.deb"
    INSTALL_GRAFANA=false
    sed -i 's/INSTALL_GRAFANA=.*/INSTALL_GRAFANA="false"/' "$CONFIG_FILE"
  else
    ok "Grafana установлена"

    GRAFANA_PASS=$(openssl rand -base64 12 | tr -d '/+=' | head -c 12)
    GRAFANA_PASS="${GRAFANA_PASS}1!"

    # grafana.ini — domain обязателен для корректного редиректа
    if [[ "$GRAFANA_MODE" == "path" ]]; then
      GF_ROOT_URL="https://$DOMAIN/grafana/"
      GF_SERVE_SUBPATH="true"
      GF_DOMAIN="$DOMAIN"
    else
      GF_ROOT_URL="https://$GRAFANA_DOMAIN/"
      GF_SERVE_SUBPATH="false"
      GF_DOMAIN="$GRAFANA_DOMAIN"
    fi

    cat > /etc/grafana/grafana.ini << EOF
[server]
http_addr = 127.0.0.1
http_port = 3000
domain = $GF_DOMAIN
root_url = $GF_ROOT_URL
serve_from_sub_path = $GF_SERVE_SUBPATH

[security]
admin_user = admin
admin_password = $GRAFANA_PASS

[auth.anonymous]
enabled = false

[analytics]
reporting_enabled = false
check_for_updates = false
EOF

    systemctl daemon-reload
    systemctl enable grafana-server 2>/dev/null
    systemctl start grafana-server
    sleep 5
    systemctl is-active --quiet grafana-server \
      && ok "Grafana запущена (127.0.0.1:3000)" \
      || warn "Grafana не запустилась — journalctl -u grafana-server -n 20"

    # ── nginx для Grafana ────────────────────────────────────────────────
    if [[ "$CERT_OK" == "true" ]]; then
      if [[ "$GRAFANA_MODE" == "path" ]]; then
        # Вставляем ^~ location ПЕРЕД location / — важен порядок
        # ^~ даёт приоритет над regex и не даёт location / перехватить /grafana/*
        sed -i 's|    location / {|    # Grafana — ^~ приоритет над regex location\n    location ^~ /grafana/ {\n        proxy_pass         http://127.0.0.1:3000;\n        proxy_set_header   Host $host;\n        proxy_set_header   X-Real-IP $remote_addr;\n        proxy_set_header   X-Forwarded-Proto $scheme;\n        proxy_set_header   X-Forwarded-Host $host;\n    }\n\n    location / {|' \
          /etc/nginx/sites-available/hipr-ssl
        ok "nginx: location ^~ /grafana/ добавлен"

      else
        # Поддомен — отдельный server блок на порту 8444
        # root_url без /grafana/ — Grafana работает в корне поддомена
        GRAFANA_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
        cat > /etc/nginx/sites-available/hipr-grafana << EOF
server {
    listen 127.0.0.1:8444 ssl http2;
    server_name $GRAFANA_DOMAIN;

    ssl_certificate     $GRAFANA_CERT_PATH/fullchain.pem;
    ssl_certificate_key $GRAFANA_CERT_PATH/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   X-Forwarded-Host \$host;
    }
}
EOF
        ln -sf /etc/nginx/sites-available/hipr-grafana /etc/nginx/sites-enabled/

        # Добавляем поддомен в SNI stream роутинг
        sed -i "/$GRAFANA_DOMAIN/d" /etc/nginx/snippets/hipr-stream.conf
        sed -i "s/        default         127.0.0.1:8443;/        $GRAFANA_DOMAIN   127.0.0.1:8444;\n        default         127.0.0.1:8443;/" \
          /etc/nginx/snippets/hipr-stream.conf
        ok "nginx: поддомен $GRAFANA_DOMAIN настроен"
      fi

      nginx -t 2>/dev/null && systemctl reload nginx && ok "nginx перезагружен"
    fi

    # ── Авто-импорт дашборда через Grafana API ───────────────────────────
    info "Импортируем дашборд HIPR..."
    sleep 3  # ждём пока Grafana полностью поднимется

    # Строим список targets для Prometheus панелей
    PROM_TARGETS_JSON=""
    for port in "${MTG_PROM_PORTS[@]}"; do
      PROM_TARGETS_JSON="${PROM_TARGETS_JSON}\"127.0.0.1:${port}\","
    done
    PROM_TARGETS_JSON="[${PROM_TARGETS_JSON%,}]"

    # Добавляем Prometheus datasource
    curl -sf --max-time 10 \
      -X POST http://127.0.0.1:3000/api/datasources \
      -H "Content-Type: application/json" \
      -u "admin:${GRAFANA_PASS}" \
      -d '{"name":"HIPR","type":"prometheus","url":"http://127.0.0.1:9090","access":"proxy","isDefault":true}' \
      > /dev/null 2>&1 && ok "Datasource HIPR добавлен" || info "Datasource — настройте вручную"

    # Импортируем дашборд
    DASH_JSON=$(cat << 'DASHJSON'
{"dashboard":{"title":"HIPR MTProxy","uid":"hipr-mtg","timezone":"browser","refresh":"10s","time":{"from":"now-1h","to":"now"},"panels":[{"id":1,"title":"TCP соединений","type":"stat","gridPos":{"x":0,"y":0,"w":6,"h":4},"datasource":"HIPR","targets":[{"expr":"sum(mtg_client_connections)","legendFormat":"соединений"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"fixed","fixedColor":"green"}}}},{"id":2,"title":"~Реальных пользователей","type":"stat","gridPos":{"x":6,"y":0,"w":6,"h":4},"datasource":"HIPR","targets":[{"expr":"ceil(sum(mtg_client_connections) / 4)","legendFormat":"юзеров"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"fixed","fixedColor":"blue"}}}},{"id":3,"title":"Соединений к Telegram","type":"stat","gridPos":{"x":12,"y":0,"w":6,"h":4},"datasource":"HIPR","targets":[{"expr":"sum(mtg_telegram_connections)","legendFormat":"к TG"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"fixed","fixedColor":"orange"}}}},{"id":4,"title":"Replay атак","type":"stat","gridPos":{"x":18,"y":0,"w":6,"h":4},"datasource":"HIPR","targets":[{"expr":"sum(mtg_replay_attacks)","legendFormat":"атак"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"thresholds"},"thresholds":{"steps":[{"color":"green","value":0},{"color":"red","value":1}]}}}},{"id":5,"title":"Соединения по времени","type":"timeseries","gridPos":{"x":0,"y":4,"w":24,"h":8},"datasource":"HIPR","targets":[{"expr":"sum(mtg_client_connections)","legendFormat":"TCP соединений"},{"expr":"ceil(sum(mtg_client_connections)/4)","legendFormat":"~пользователей"}],"fieldConfig":{"defaults":{"custom":{"lineWidth":2}}}},{"id":6,"title":"Трафик","type":"timeseries","gridPos":{"x":0,"y":12,"w":12,"h":8},"datasource":"HIPR","targets":[{"expr":"sum(rate(mtg_telegram_traffic[2m]))","legendFormat":"байт/сек"}],"fieldConfig":{"defaults":{"unit":"binBps","custom":{"lineWidth":2}}}},{"id":7,"title":"FakeTLS handshakes","type":"timeseries","gridPos":{"x":12,"y":12,"w":12,"h":8},"datasource":"HIPR","targets":[{"expr":"sum(rate(mtg_domain_fronting[2m]))","legendFormat":"{{instance}}"}],"fieldConfig":{"defaults":{"custom":{"lineWidth":2}}}},{"id":8,"title":"Соединения по инстансам","type":"bargauge","gridPos":{"x":0,"y":20,"w":24,"h":6},"datasource":"HIPR","targets":[{"expr":"mtg_client_connections","legendFormat":"{{instance}}"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"orientation":"horizontal","displayMode":"gradient"}}]},"overwrite":true,"folderId":0}
DASHJSON
)
    curl -sf --max-time 10 \
      -X POST http://127.0.0.1:3000/api/dashboards/import \
      -H "Content-Type: application/json" \
      -u "admin:${GRAFANA_PASS}" \
      -d "$DASH_JSON" \
      > /dev/null 2>&1 && ok "Дашборд HIPR импортирован" || info "Дашборд — импортируйте вручную (инструкция в README)"

    echo "GRAFANA_PASS=\"$GRAFANA_PASS\"" >> "$CONFIG_FILE"
    ok "Grafana пароль: $GRAFANA_PASS"
    ok "Grafana URL: $GF_ROOT_URL"
  fi
  done_step
fi

# ── Watchdog ──────────────────────────────────────────────────────────────
step "Watchdog"

cat > "$HIDE_DIR/bin/watchdog.sh" << 'WATCHDOG'
#!/bin/bash
# HIPR Watchdog v4.0

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

log()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }
notify() {
  local msg="$1"
  [[ -n "${BOT_TOKEN:-}" && -n "${BOT_CHAT_ID:-}" ]] || return
  curl -s --max-time 10 \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${BOT_CHAT_ID}" \
    -d "text=🔔 HIPR: ${msg}" \
    -d "parse_mode=HTML" > /dev/null 2>&1 || true
}

check_dc() {
  timeout 5 bash -c "echo '' > /dev/tcp/$1/443" 2>/dev/null
}

# ── Проверка DC ────────────────────────────────────────────────────────────
if ! check_dc "${ACTIVE_DC:-149.154.167.51}"; then
  log "WARN: DC ${ACTIVE_DC} недоступен"
  for dc in "${DCS[@]}"; do
    [[ "$dc" == "${ACTIVE_DC:-}" ]] && continue
    if check_dc "$dc"; then
      log "INFO: Переключаемся на $dc"
      sed -i "s/ACTIVE_DC=.*/ACTIVE_DC=\"$dc\"/" "$CONFIG"
      if [[ "${MODE:-single}" == "multi" ]]; then
        for i in 0 1 2 3 4; do
          systemctl is-active --quiet "hipr-mtg@${i}" 2>/dev/null && \
            systemctl restart "hipr-mtg@${i}" 2>/dev/null || true
        done
      else
        systemctl restart hipr-mtg 2>/dev/null || true
      fi
      notify "📡 DC переключён: ${ACTIVE_DC} → ${dc}"
      exit 0
    fi
  done
  log "ERROR: Все DC недоступны!"
  notify "⚠️ Все Telegram DC недоступны!"
else
  log "OK: DC ${ACTIVE_DC} доступен"
fi

# ── Проверка сервисов ─────────────────────────────────────────────────────
if [[ "${MODE:-single}" == "multi" ]]; then
  for i in 0 1 2 3 4; do
    if systemctl is-enabled --quiet "hipr-mtg@${i}" 2>/dev/null; then
      if ! systemctl is-active --quiet "hipr-mtg@${i}" 2>/dev/null; then
        log "WARN: hipr-mtg@${i} не запущен — перезапускаем"
        systemctl start "hipr-mtg@${i}" 2>/dev/null || true
        notify "⚠️ mtg@${i} перезапущен автоматически"
      fi
    fi
  done
else
  if ! systemctl is-active --quiet hipr-mtg 2>/dev/null; then
    log "WARN: hipr-mtg не запущен — перезапускаем"
    systemctl start hipr-mtg 2>/dev/null || true
    notify "⚠️ mtg перезапущен автоматически"
  fi
fi

# ── Детект active probing ─────────────────────────────────────────────────
NGINX_LOG="/opt/hipr/logs/nginx-access.log"
PROBE_LOG="/opt/hipr/logs/probing.log"

if [[ -f "$NGINX_LOG" ]]; then
  RECENT=$(awk -v d="$(date -d '5 minutes ago' '+%d/%b/%Y:%H:%M' 2>/dev/null || date -v-5M '+%d/%b/%Y:%H:%M' 2>/dev/null)" \
    '$0 > d' "$NGINX_LOG" 2>/dev/null | tail -200)

  SUSPICIOUS=$(echo "$RECENT" | awk '{print $1}' | sort | uniq -c | sort -rn | \
    awk '$1 > 20 {print $1, $2}' 2>/dev/null)

  if [[ -n "$SUSPICIOUS" ]]; then
    log "WARN: Подозрительная активность: $SUSPICIOUS"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PROBE: $SUSPICIOUS" >> "$PROBE_LOG"
    notify "🔍 Возможный active probing: $SUSPICIOUS"
  fi

  PROM_PORTS_LIST="${MTG_PROM_PORTS:-3129}"
  IFS='|' read -ra PPORTS <<< "$PROM_PORTS_LIST"
  for port in "${PPORTS[@]}"; do
    REPLAYS=$(curl -sf --max-time 2 "http://127.0.0.1:${port}/metrics" 2>/dev/null | \
      grep '^mtg_replay_attacks ' | awk '{print int($2)}')
    if [[ -n "$REPLAYS" && "$REPLAYS" -gt 5 ]]; then
      log "WARN: Replay атак на порту $port: $REPLAYS"
      notify "🛡️ Обнаружены replay атаки ($REPLAYS) — возможно active probing ТСПУ"
    fi
  done
fi
WATCHDOG

chmod +x "$HIDE_DIR/bin/watchdog.sh"

cat > /etc/systemd/system/hipr-watchdog.service << EOF
[Unit]
Description=HIPR Watchdog
After=network.target

[Service]
Type=oneshot
ExecStart=$HIDE_DIR/bin/watchdog.sh
StandardOutput=append:$HIDE_DIR/logs/watchdog.log
StandardError=append:$HIDE_DIR/logs/watchdog.log
EOF

cat > /etc/systemd/system/hipr-watchdog.timer << 'EOF'
[Unit]
Description=HIPR Watchdog timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=hipr-watchdog.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable hipr-watchdog.timer 2>/dev/null
systemctl start hipr-watchdog.timer 2>/dev/null
ok "Watchdog запущен (каждые 5 минут)"
done_step

# ── Ежедневный отчёт в бот ────────────────────────────────────────────────
if [[ -n "$BOT_TOKEN" ]]; then
  step "Ежедневный отчёт в Telegram"

  cat > "$HIDE_DIR/bin/daily-report.sh" << 'REPORT'
#!/bin/bash
CONFIG="/opt/hipr/config.env"
[[ -f "$CONFIG" ]] && source "$CONFIG"
[[ -z "${BOT_TOKEN:-}" || -z "${BOT_CHAT_ID:-}" ]] && exit 0

IFS='|' read -ra PPORTS <<< "${MTG_PROM_PORTS:-3129}"
IFS='|' read -ra SNIS   <<< "${SNI_DOMAINS:-microsoft.com}"

TOTAL_ACTIVE=0; TOTAL_TG=0; TOTAL_BYTES=0; TOTAL_REPLAYS=0
INST_LINES=""

for i in "${!PPORTS[@]}"; do
  port="${PPORTS[$i]}"
  sni="${SNIS[$i]:-?}"
  metrics=$(curl -sf --max-time 3 "http://127.0.0.1:${port}/metrics" 2>/dev/null)
  [[ -z "$metrics" ]] && continue

  active=$(echo "$metrics" | grep '^mtg_client_connections{' | awk '{sum+=$2} END{print int(sum)}')
  tg=$(echo "$metrics" | grep '^mtg_telegram_connections{' | awk '{sum+=$2} END{print int(sum)}')
  bytes=$(echo "$metrics" | grep '^mtg_telegram_traffic{' | awk '{sum+=$2} END{print int(sum)}')
  replays=$(echo "$metrics" | grep '^mtg_replay_attacks ' | awk '{print int($2)}')

  TOTAL_ACTIVE=$((TOTAL_ACTIVE + ${active:-0}))
  TOTAL_TG=$((TOTAL_TG + ${tg:-0}))
  TOTAL_BYTES=$((TOTAL_BYTES + ${bytes:-0}))
  TOTAL_REPLAYS=$((TOTAL_REPLAYS + ${replays:-0}))
  INST_LINES="${INST_LINES}  • ${sni}: ${active:-0} акт / $(echo "${bytes:-0}" | \
    python3 -c 'import sys; b=int(sys.stdin.read().strip() or 0); print(f"{b/1048576:.1f}MB")' 2>/dev/null || echo "—")\n"
done

fmt_bytes() {
  python3 -c "
b=$1
if b > 1073741824: print(f'{b/1073741824:.1f} GB')
elif b > 1048576: print(f'{b/1048576:.1f} MB')
else: print(f'{b/1024:.1f} KB')
" 2>/dev/null || echo "${1}B"
}

MSG="📊 <b>HIPR дневной отчёт</b>
$(date '+%d.%m.%Y')

🟢 Активных соединений: <b>${TOTAL_ACTIVE}</b>
📡 Подключений к Telegram: <b>${TOTAL_TG}</b>
📦 Трафик: <b>$(fmt_bytes $TOTAL_BYTES)</b>
🛡️ Replay атак: <b>${TOTAL_REPLAYS}</b>

🌐 Домен: ${DOMAIN}
📡 DC: ${ACTIVE_DC}

$(echo -e "$INST_LINES")"

curl -s --max-time 10 \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${BOT_CHAT_ID}" \
  --data-urlencode "text=${MSG}" \
  -d "parse_mode=HTML" > /dev/null 2>&1 || true
REPORT

  chmod +x "$HIDE_DIR/bin/daily-report.sh"

  (crontab -l 2>/dev/null | grep -v 'daily-report'
   echo "0 17 * * * $HIDE_DIR/bin/daily-report.sh") | crontab -

  ok "Ежедневный отчёт в 20:00 МСК"
  done_step
fi

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
ufw default deny incoming  > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow ssh    > /dev/null 2>&1
ufw allow 80/tcp  > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
ok "ufw настроен"
done_step

# ── Финальный вывод ───────────────────────────────────────────────────────
source "$CONFIG_FILE"

echo ""
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}${BOLD}  ✅  HIPR v${VERSION} успешно установлен!${N}"
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  ${BOLD}Режим: ${C}$MODE${N}"
echo ""
echo -e "  ${BOLD}Ссылки для Telegram:${N}\n"

IFS='|' read -ra _SNIS    <<< "$SNI_DOMAINS"
IFS='|' read -ra _SECRETS <<< "$MTG_SECRETS"

for i in "${!_SNIS[@]}"; do
  sni="${_SNIS[$i]}"
  secret="${_SECRETS[$i]}"
  tg_link="tg://proxy?server=${DOMAIN}&port=443&secret=${secret}"
  echo -e "  ${DIM}[$((i+1))] SNI: $sni${N}"
  echo -e "  ${C}${tg_link}${N}"
  echo ""
done

if command -v qrencode &>/dev/null && [[ ${#_SNIS[@]} -eq 1 ]]; then
  ht_link="https://t.me/proxy?server=${DOMAIN}&port=443&secret=${_SECRETS[0]}"
  echo -e "  ${BOLD}📱 QR-код:${N}\n"
  qrencode -t ANSIUTF8 -l M "$ht_link" 2>/dev/null | sed 's/^/  /'
  echo ""
fi

echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "  ${W}hide${N}  — открыть меню управления"
[[ "${INSTALL_GRAFANA:-false}" == "true" && -n "${GRAFANA_PASS:-}" ]] && \
  echo -e "  ${W}Grafana${N}: $GRAFANA_URL  логин: admin / $GRAFANA_PASS"
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

echo -e "  ${BOLD}Статус сервисов:${N}"
for svc in nginx dnsproxy hipr-watchdog.timer; do
  systemctl is-active --quiet "$svc" 2>/dev/null \
    && echo -e "  ${G}✓${N}  $svc" || echo -e "  ${R}✗${N}  $svc"
done

IFS='|' read -ra _SNIS_CHK <<< "$SNI_DOMAINS"
if [[ "$MODE" == "single" ]]; then
  systemctl is-active --quiet hipr-mtg 2>/dev/null \
    && echo -e "  ${G}✓${N}  hipr-mtg" || echo -e "  ${R}✗${N}  hipr-mtg"
else
  for i in "${!_SNIS_CHK[@]}"; do
    systemctl is-active --quiet "hipr-mtg@${i}" 2>/dev/null \
      && echo -e "  ${G}✓${N}  hipr-mtg@${i} (${_SNIS_CHK[$i]})" \
      || echo -e "  ${R}✗${N}  hipr-mtg@${i}"
  done
fi

[[ "${INSTALL_GRAFANA:-false}" == "true" ]] && \
  systemctl is-active --quiet prometheus 2>/dev/null \
    && echo -e "  ${G}✓${N}  prometheus" || echo -e "  ${R}✗${N}  prometheus"

echo ""
