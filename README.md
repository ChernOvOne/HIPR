# HIPR

Telegram MTProto прокси — невидимый для ТСПУ.

**Как это работает:** сервер выглядит как обычный HTTPS-сайт. При активной проверке ТСПУ получает настоящий HTML. Telegram-трафик идёт внутри TLS через [mtg](https://github.com/9seconds/mtg) с FakeTLS обфускацией. Watchdog каждые 60 секунд проверяет доступность DC и автоматически переключается при блокировке.

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ChernOvOne/HIPR/main/install.sh)
```

Или из клона:

```bash
git clone https://github.com/ChernOvOne/HIPR
cd HIPR
sudo bash install.sh
```

**Требования:** Ubuntu 20.04+ / Debian 11+, домен с A-записью на сервер, порт 443 свободен, root.

## Архитектура

```
Интернет → порт 443
              │
           HAProxy / nginx stream
              │
     ┌────────┴────────┐
     │                 │
  Браузер/ТСПУ      Telegram
  ↓                  ↓
  nginx:8443         mtg:2398
  сайт-обманка       FakeTLS → Telegram DC
```

## Управление

```bash
hide              # интерактивное меню
hide status       # быстрый статус
hide logs         # live лог mtg
hide link         # ссылка tg://
hide qr           # QR-код в терминале
hide theme        # активная тема
hide restart      # перезапустить всё
hide watchdog     # запустить watchdog вручную
```

## Темы сайта-обманки

Три встроенных темы, смена за 3 секунды:

```
hide → [3] Темы сайта-обманки → [1] Выбрать
```

Добавить свою тему — папка с `index.html` в `/opt/hipr/themes/custom/`
или через меню hide. Подробнее: [themes/README.md](themes/README.md)

## Компоненты

| Компонент | Назначение |
|---|---|
| `install.sh` | Установщик — запустить один раз |
| `hide` | CLI меню управления |
| `mtg` | MTProto обфускация (FakeTLS) |
| `watchdog.sh` | Авто-смена DC при блокировке |
| `themes/` | Сайты-обманки |

## Структура репозитория

```
HIPR/
├── install.sh
├── hide
├── README.md
└── themes/
    ├── README.md
    ├── blog/
    ├── freelancer/
    └── coming-soon/
```

## Лицензия

MIT
