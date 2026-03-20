# HIPR — Hidden Proxy v4.0

**Telegram MTProto прокси с FakeTLS маскировкой — невидимый для ТСПУ**

Трафик выглядит как обычный HTTPS к легитимным сайтам (microsoft.com, avito.ru и др.). Приватный VPS с HIPR значительно надёжнее публичных прокси.

```
bash <(curl -fsSL https://raw.githubusercontent.com/ChernOvOne/HIPR/main/install.sh)
```

---

## Возможности

- **FakeTLS маскировка** — трафик неотличим от HTTPS к выбранному SNI домену
- **Multi-fronting режим** — до 5 независимых прокси-инстансов с разными SNI
- **SNI роутинг** через nginx stream — один порт 443 для всего
- **Сайт-обманка** — 3 темы (блог, фриланс, coming soon), легко менять
- **Мониторинг** — Prometheus + Grafana дашборд с реальной статистикой
- **Watchdog** — автоматическое переключение Telegram DC, детект active probing
- **Telegram-бот** — ежедневные отчёты и алерты
- **BBR/BBRv3** — автоматический выбор лучшего TCP алгоритма по версии ядра
- **DoH** — локальный DNS-over-HTTPS через dnsproxy

---

## Требования

- Ubuntu 20.04 / 22.04 / 24.04 (рекомендуется 24.04)
- VPS за пределами РФ
- Домен с A-записью указывающей на сервер
- Порты 80, 443 свободны

---

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ChernOvOne/HIPR/main/install.sh)
```

Установщик спросит:
- Домен сервера
- Email для Let's Encrypt
- Режим (обычный / multi-fronting)
- SNI домен(ы) для маскировки
- Тему сайта-обманки
- Установить ли Grafana
- Telegram-бот (опционально)

После установки ссылки для Telegram выводятся прямо в терминале с QR-кодом.

---

## Управление

```bash
hide                  # интерактивное меню
hide status           # статус всех сервисов
hide links            # все ссылки tg://
hide link             # первая ссылка
hide sni              # список SNI доменов
hide logs             # live лог mtg
hide restart          # перезапустить всё
hide watchdog         # запустить watchdog вручную
hide report           # отправить отчёт в бот
hide optimize         # меню оптимизации сети
hide uninstall        # удалить HIPR
```

---

## Структура

```
/opt/hipr/
├── bin/
│   ├── mtg              # MTProto прокси
│   ├── watchdog.sh      # watchdog скрипт
│   └── daily-report.sh  # ежедневный отчёт в бот
├── config/
│   ├── mtg0.toml        # конфиг первого инстанса
│   ├── mtg1.toml        # и так далее для multi
│   └── active_theme     # активная тема
├── logs/                # все логи
├── themes/              # встроенные и пользовательские темы
└── config.env           # основной конфиг HIPR

/usr/local/bin/hide      # CLI менеджер
/var/www/hipr/           # файлы сайта-обманки
```

---

## Grafana мониторинг

Grafana устанавливается опционально во время `install.sh`. Дашборд и datasource Prometheus импортируются автоматически.

### Режимы установки

**Режим path** — Grafana доступна по пути основного домена:
```
https://ваш-домен.com/grafana/
```

**Режим поддомена** — Grafana на отдельном поддомене:
```
https://stat.ваш-домен.com/
```
Для этого режима нужна отдельная A-запись на тот же IP.

### Если Grafana не открылась после установки

Используйте встроенный фикс:
```
hide → [6] Настройки → [7] Починить nginx → Grafana
```

### Ручная настройка (если нужно)

**1. Добавить datasource Prometheus**

Grafana → Connections → Data sources → Add → Prometheus

URL: `http://127.0.0.1:9090` → Save & test

**2. Импортировать дашборд**

Grafana → Dashboards → Import → вставьте JSON ниже → Import

```json
{"dashboard":{"title":"HIPR MTProxy","uid":"hipr-mtg","timezone":"browser","refresh":"10s","time":{"from":"now-1h","to":"now"},"panels":[{"id":1,"title":"TCP соединений","type":"stat","gridPos":{"x":0,"y":0,"w":6,"h":4},"datasource":"Prometheus","targets":[{"expr":"sum(mtg_client_connections)","legendFormat":"соединений"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"fixed","fixedColor":"green"}}}},{"id":2,"title":"~Реальных пользователей","type":"stat","gridPos":{"x":6,"y":0,"w":6,"h":4},"datasource":"Prometheus","targets":[{"expr":"ceil(sum(mtg_client_connections) / 4)","legendFormat":"юзеров"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"fixed","fixedColor":"blue"}}}},{"id":3,"title":"Соединений к Telegram","type":"stat","gridPos":{"x":12,"y":0,"w":6,"h":4},"datasource":"Prometheus","targets":[{"expr":"sum(mtg_telegram_connections)","legendFormat":"к TG"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"fixed","fixedColor":"orange"}}}},{"id":4,"title":"Replay атак","type":"stat","gridPos":{"x":18,"y":0,"w":6,"h":4},"datasource":"Prometheus","targets":[{"expr":"sum(mtg_replay_attacks)","legendFormat":"атак"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"colorMode":"background","graphMode":"none"},"fieldConfig":{"defaults":{"color":{"mode":"thresholds"},"thresholds":{"steps":[{"color":"green","value":0},{"color":"red","value":1}]}}}},{"id":5,"title":"Соединения по времени","type":"timeseries","gridPos":{"x":0,"y":4,"w":24,"h":8},"datasource":"Prometheus","targets":[{"expr":"sum(mtg_client_connections)","legendFormat":"TCP соединений"},{"expr":"ceil(sum(mtg_client_connections)/4)","legendFormat":"~пользователей"}],"fieldConfig":{"defaults":{"custom":{"lineWidth":2}}}},{"id":6,"title":"Трафик","type":"timeseries","gridPos":{"x":0,"y":12,"w":12,"h":8},"datasource":"Prometheus","targets":[{"expr":"rate(sum(mtg_telegram_traffic)[2m])","legendFormat":"байт/сек"}],"fieldConfig":{"defaults":{"unit":"binBps","custom":{"lineWidth":2}}}},{"id":7,"title":"FakeTLS handshakes","type":"timeseries","gridPos":{"x":12,"y":12,"w":12,"h":8},"datasource":"Prometheus","targets":[{"expr":"rate(mtg_domain_fronting[2m])","legendFormat":"{{instance}}"}],"fieldConfig":{"defaults":{"custom":{"lineWidth":2}}}},{"id":8,"title":"Соединения по инстансам","type":"bargauge","gridPos":{"x":0,"y":20,"w":24,"h":6},"datasource":"Prometheus","targets":[{"expr":"mtg_client_connections","legendFormat":"{{instance}}"}],"options":{"reduceOptions":{"calcs":["lastNotNull"]},"orientation":"horizontal","displayMode":"gradient"}}]},"overwrite":true,"folderId":0}
```

### Что показывает дашборд

| Панель | Описание |
|--------|----------|
| TCP соединений | Активные соединения через прокси |
| ~Реальных пользователей | Оценка (TCP ÷ 4, Telegram держит 3–8 conn/юзер) |
| Соединений к Telegram | Активные соединения до DC Telegram |
| Replay атак | Счётчик попыток active probing (ТСПУ) |
| Соединения по времени | График за выбранный период |
| Трафик | Скорость передачи данных байт/сек |
| FakeTLS handshakes | Количество FakeTLS соединений |
| По инстансам | Разбивка по SNI доменам (для multi режима) |

Данные обновляются каждые **10 секунд** автоматически.

---

## Темы сайта-обманки

Управление через `hide → [3] Темы`:

| Тема | Описание |
|------|----------|
| `blog` | Блог разработчика DevNotes |
| `freelancer` | Страница фрилансера |
| `coming-soon` | «Скоро открытие» с таймером |

Можно добавить свою тему (папку с `index.html`) или скачать с GitHub.

---

## Multi-fronting режим

Создаёт до 5 независимых mtg-инстансов с разными SNI доменами. Каждый инстанс получает свою ссылку `tg://`.

Управление через `hide → [6] Настройки → [1] Управление Multi-fronting`:
- Сменить SNI конкретного инстанса
- Добавить инстанс
- Удалить инстанс
- Ротировать все SNI сразу

---

## Watchdog

Запускается каждые 5 минут через systemd timer. Выполняет:

- Проверку доступности активного Telegram DC
- Автоматическое переключение на другой DC при недоступности
- Проверку что все mtg-инстансы запущены, перезапуск при падении
- Детект active probing по nginx логам и метрикам replay атак
- Уведомления в Telegram-бот при событиях

---

## Обновление компонентов

```
hide → [7] Обновление
```

- mtg — обновляется до последней версии с GitHub
- hide — обновляется с GitHub
- dnsproxy — обновляется с GitHub

---

## FAQ

**Почему один пользователь показывает 3–8 соединений?**
Telegram открывает несколько параллельных TCP-соединений на клиента — для сообщений, медиа, фонового синка. Это нормально. В статистике `hide` и Grafana показывается оценка реальных юзеров (`÷ 4`).

**Какой SNI домен выбрать?**
`microsoft.com` — рекомендуется для международных VPS. `avito.ru`, `ozon.ru`, `wildberries.ru` — для российских VPS, трафик к ним не вызывает подозрений.

**BBR или BBRv3?**
HIPR автоматически определяет версию ядра и включает лучший доступный алгоритм. BBRv3 доступен на ядре 6.3+. Ubuntu 24.04 с HWE ядром поставляет BBRv3 из коробки.

**Grafana не загружает JS/CSS файлы?**
Убедитесь что в nginx нет `location ~* \.(js|css|...)$` — он перехватывает статику Grafana. HIPR v4.0 не создаёт такой location. Используйте `hide → [6] → [7]` для автоматического исправления.

---

## Лицензия

MIT
