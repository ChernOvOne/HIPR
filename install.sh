#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  HIPR — установщик v3.0
#  https://github.com/ChernOvOne/HIPR
#
#  Одна команда:
#  bash <(curl -fsSL https://raw.githubusercontent.com/ChernOvOne/HIPR/main/install.sh)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

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
warn()      { echo -e "${C}│${N}  ${R}✗${N}  $*"; }

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
  nginx libnginx-mod-stream certbot python3-certbot-nginx \
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

# ── Скачиваем hide с GitHub, темы встроены в скрипт ─────────────────────
step "Загрузка файлов"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$SCRIPT_DIR/hide" ]]; then
  info "Локальный репозиторий — копируем hide"
  cp "$SCRIPT_DIR/hide" "$HIDE_BIN"
  ok "hide скопирован локально"
else
  info "Скачиваем hide с GitHub..."
  curl -fsSL "$REPO_RAW/hide" -o "$HIDE_BIN" || err "Не удалось скачать hide"
  ok "hide скачан"
fi
chmod +x "$HIDE_BIN"

# Темы встроены прямо в установщик — не зависим от GitHub
info "Разворачиваем темы..."

mkdir -p "$HIDE_DIR/themes/blog"
cat > "$HIDE_DIR/themes/blog/theme.json" << 'BLOGTHEMEJSON'
{"name":"blog","description":"Блог разработчика DevNotes","author":"HIPR","version":"1.0","preview":"Технический блог: Linux, Go, DevOps","pages":["index.html","about.html"]}
BLOGTHEMEJSON
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

mkdir -p "$HIDE_DIR/themes/freelancer"
cat > "$HIDE_DIR/themes/freelancer/theme.json" << 'FREELANCERTHEMEJSON'
{"name":"freelancer","description":"Страница фрилансера","author":"HIPR","version":"1.0","preview":"Портфолио: веб, мобайл, API","pages":["index.html"]}
FREELANCERTHEMEJSON
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
      <div class="card">
        <div class="card-icon">🌐</div>
        <h3>Веб-приложения</h3>
        <p>SPA, лендинги, административные панели, корпоративные сайты</p>
        <div class="stack"><span class="tag">React</span><span class="tag">Next.js</span><span class="tag">TypeScript</span></div>
      </div>
      <div class="card">
        <div class="card-icon">📱</div>
        <h3>Мобильные приложения</h3>
        <p>Кроссплатформенные приложения под iOS и Android</p>
        <div class="stack"><span class="tag">Flutter</span><span class="tag">Dart</span><span class="tag">Firebase</span></div>
      </div>
      <div class="card">
        <div class="card-icon">⚙️</div>
        <h3>Бэкенд и API</h3>
        <p>REST/GraphQL API, микросервисы, интеграции с внешними сервисами</p>
        <div class="stack"><span class="tag">Node.js</span><span class="tag">PostgreSQL</span><span class="tag">Docker</span></div>
      </div>
    </div>
  </div>
</section>

<section id="projects">
  <div class="sec-inner">
    <div class="sec-title">Последние проекты</div>
    <div class="sec-sub">Некоторые из недавних работ</div>
    <div class="projects">
      <div class="proj">
        <div class="proj-img blue">📊</div>
        <div class="proj-body">
          <h3>Аналитическая платформа</h3>
          <p>Дашборд для мониторинга бизнес-метрик в реальном времени. React + D3.js + WebSocket</p>
        </div>
      </div>
      <div class="proj">
        <div class="proj-img green">🛒</div>
        <div class="proj-body">
          <h3>Мобильный маркетплейс</h3>
          <p>Flutter-приложение с каталогом, корзиной и оплатой. 10k+ установок</p>
        </div>
      </div>
      <div class="proj">
        <div class="proj-img orange">💬</div>
        <div class="proj-body">
          <h3>CRM для агентства</h3>
          <p>Система управления клиентами и сделками. Node.js + PostgreSQL + React</p>
        </div>
      </div>
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

mkdir -p "$HIDE_DIR/themes/coming-soon"
cat > "$HIDE_DIR/themes/coming-soon/theme.json" << 'COMINGTHEMEJSON'
{"name":"coming-soon","description":"Страница «Скоро открытие»","author":"HIPR","version":"1.0","preview":"Таймер обратного отсчёта, подписка на email","pages":["index.html"]}
COMINGTHEMEJSON
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
body{
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
  background:#0f0f1a;
  color:#fff;
  display:flex;
  flex-direction:column;
  align-items:center;
  justify-content:center;
  min-height:100vh;
  text-align:center;
  padding:2rem;
  overflow:hidden;
}
.bg{
  position:fixed;inset:0;z-index:0;
  background:radial-gradient(ellipse at 20% 50%,rgba(99,102,241,.15) 0%,transparent 60%),
             radial-gradient(ellipse at 80% 20%,rgba(168,85,247,.12) 0%,transparent 60%),
             radial-gradient(ellipse at 60% 80%,rgba(59,130,246,.1) 0%,transparent 60%);
}
.content{position:relative;z-index:1;max-width:560px;width:100%}
.logo{
  display:inline-flex;align-items:center;gap:.6rem;
  background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);
  padding:.5rem 1.25rem;border-radius:50px;margin-bottom:3rem;
  font-size:.85rem;font-weight:600;letter-spacing:.5px;color:rgba(255,255,255,.8)
}
.logo-dot{width:8px;height:8px;border-radius:50%;background:#6366f1;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.5;transform:scale(.8)}}
h1{
  font-size:clamp(2rem,5vw,3.25rem);font-weight:800;
  line-height:1.15;margin-bottom:1.25rem;
  background:linear-gradient(135deg,#fff 0%,rgba(255,255,255,.7) 100%);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text
}
.sub{color:rgba(255,255,255,.5);font-size:1.05rem;margin-bottom:3rem;line-height:1.6}
.counter{display:flex;justify-content:center;gap:1.5rem;margin-bottom:3rem;flex-wrap:wrap}
.count-item{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.08);
  border-radius:12px;padding:1.25rem 1.5rem;min-width:80px}
.count-num{font-size:2rem;font-weight:800;line-height:1;color:#a5b4fc}
.count-label{font-size:.7rem;color:rgba(255,255,255,.4);margin-top:.3rem;text-transform:uppercase;letter-spacing:.5px}
.form{display:flex;gap:.75rem;max-width:420px;margin:0 auto 1.5rem;flex-wrap:wrap;justify-content:center}
.input{
  flex:1;min-width:200px;padding:.8rem 1.25rem;border-radius:10px;
  border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.07);
  color:#fff;font-size:.9rem;outline:none;font-family:inherit
}
.input::placeholder{color:rgba(255,255,255,.35)}
.input:focus{border-color:rgba(99,102,241,.6);background:rgba(255,255,255,.1)}
.btn{
  padding:.8rem 1.75rem;border-radius:10px;border:none;
  background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;
  font-weight:700;font-size:.9rem;cursor:pointer;white-space:nowrap;font-family:inherit
}
.btn:hover{opacity:.9}
.hint{color:rgba(255,255,255,.3);font-size:.78rem}
.socials{display:flex;gap:1rem;justify-content:center;margin-top:3rem}
.soc{
  width:40px;height:40px;border-radius:10px;display:flex;align-items:center;justify-content:center;
  background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);
  color:rgba(255,255,255,.5);font-size:.9rem;transition:.2s
}
.soc:hover{background:rgba(255,255,255,.12);color:#fff}
</style>
</head>
<body>
<div class="bg"></div>
<div class="content">
  <div class="logo">
    <span class="logo-dot"></span>
    В разработке
  </div>
  <h1>Что-то крутое скоро появится</h1>
  <p class="sub">Мы работаем над чем-то особенным.<br>Подпишитесь — пришлём письмо в день запуска.</p>

  <div class="counter">
    <div class="count-item">
      <div class="count-num" id="days">14</div>
      <div class="count-label">Дней</div>
    </div>
    <div class="count-item">
      <div class="count-num" id="hours">08</div>
      <div class="count-label">Часов</div>
    </div>
    <div class="count-item">
      <div class="count-num" id="mins">23</div>
      <div class="count-label">Минут</div>
    </div>
    <div class="count-item">
      <div class="count-num" id="secs">41</div>
      <div class="count-label">Секунд</div>
    </div>
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

# Если локальный репозиторий содержит кастомные темы — добавляем их
if [[ -d "$SCRIPT_DIR/themes" ]]; then
  cp -rn "$SCRIPT_DIR/themes"/. "$HIDE_DIR/themes/" 2>/dev/null || true
  ok "Локальные темы добавлены"
fi

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
# ВАЖНО: фронтинг-домен должен быть ВНЕШНИМ сайтом (telegram.org).
# Если использовать собственный домен — mtg при каждом соединении будет
# пытаться подключиться к нему на порт 443, попадёт в nginx stream → себя же → петля.
info "Генерируем секрет FakeTLS (fronting: telegram.org)..."
MTG_SECRET=$("$MTG_BIN" generate-secret --hex "telegram.org" 2>/dev/null | tr -d '\n')

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

# Чистим остатки предыдущих (неудачных) запусков
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/hipr-ssl
rm -f /etc/nginx/sites-available/hipr-ssl
rm -f /etc/nginx/snippets/hipr-stream.conf
rm -f /etc/nginx/modules-enabled/60-mod-hipr-stream.conf
# Убираем include hipr-stream из nginx.conf если остался с прошлого раза
sed -i '/hipr-stream\.conf/d' /etc/nginx/nginx.conf
mkdir -p /var/www/certbot /etc/nginx/snippets

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
if nginx -t 2>/tmp/hipr-nginx-http.log; then
  systemctl restart nginx
  ok "nginx запущен (HTTP)"
else
  warn "nginx -t упал (HTTP конфиг) — детали:"
  cat /tmp/hipr-nginx-http.log >&2
  warn "Продолжаем установку, nginx нужно починить вручную после"
fi
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

    # nginx stream — слушает 443, проксирует TCP в mtg
    # libnginx-mod-stream уже установлен выше и сам создал load_module конфиг
    # Убеждаемся что модуль активен
    if ! dpkg -l libnginx-mod-stream 2>/dev/null | grep -q '^ii'; then
      info "libnginx-mod-stream не установлен — доустанавливаем..."
      apt-get install -y -qq libnginx-mod-stream 2>/dev/null
    fi

    mkdir -p /etc/nginx/snippets
    cat > /etc/nginx/snippets/hipr-stream.conf << 'STREAMEOF'
stream {
    upstream hipr_mtg {
        server 127.0.0.1:2398;
    }

    server {
        listen 443;
        listen [::]:443;
        proxy_pass hipr_mtg;
        proxy_timeout 10m;
        proxy_connect_timeout 10s;
    }
}
STREAMEOF

    # stream-блок должен быть на верхнем уровне nginx.conf — добавляем include
    # только если его там ещё нет
    if ! grep -q 'hipr-stream.conf' /etc/nginx/nginx.conf; then
      echo "include /etc/nginx/snippets/hipr-stream.conf;" >> /etc/nginx/nginx.conf
    fi
    ok "nginx stream настроен (порт 443 → mtg)"

    if nginx -t 2>/tmp/hipr-nginx-test.log; then
      systemctl reload nginx
      ok "nginx перезагружен"
    else
      warn "nginx -t упал — детали:"
      cat /tmp/hipr-nginx-test.log >&2
      warn "nginx не перезагружен. После установки: nginx -t && systemctl reload nginx"
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

# Не-MTProto соединения (браузер, active probe ТСПУ) → сайт-обманка
[proxy]
fallback = "127.0.0.1:8443"

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
touch "$HIDE_DIR/logs/mtg.log" "$HIDE_DIR/logs/mtg-error.log"

systemctl start hipr-mtg
sleep 2
if systemctl is-active --quiet hipr-mtg; then
  ok "hipr-mtg запущен"
else
  warn "hipr-mtg не запустился — проверьте: journalctl -u hipr-mtg -n 20"
  journalctl -u hipr-mtg -n 10 --no-pager 2>/dev/null || true
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

# ── Итоговая диагностика ──────────────────────────────────────────────────
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "  ${BOLD}Статус сервисов:${N}"
for svc in hipr-mtg nginx hipr-watchdog.timer; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "  ${G}✓${N}  $svc"
  else
    echo -e "  ${R}✗${N}  $svc ${DIM}(не запущен)${N}"
  fi
done
echo ""
echo -e "  ${BOLD}Порты:${N}"
ss -tlnp 2>/dev/null | grep -E ':443|:2398|:8443|:80' \
  | awk '{print "  " $1 " " $4}' || true
echo -e "${B}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
