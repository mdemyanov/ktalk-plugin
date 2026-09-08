---
properties:
  - name: Тип контента
    value: [Исследование]
  - name: Фаза
    value: [Pilot]
  - name: Статус
    value: [Draft]
  - name: Audience
    value: [Internal]
---

# Авторизация в установленной ktalk-cli 2.1.0: источники токена, режимы операций, отказ без токена

**Опоры:** `references/onboarding.md`, `README.md`, `openspec/specs/plugin-onboarding-sanctioned-install/spec.md`

**Задача:** RES-001 эпика `ktalk-plugin-6sm`. Собрать факты об устройстве авторизации в
установленной копии `ktalk-cli` 2.1.0 — вход для BA-001 (требование «единственный режим
авторизации — токен браузерной сессии») и SA-001 (ADR-028). Требований и решений здесь нет.

**Источник:** установленный пакет `ktalk-cli 2.1.0` (`uv tool list`), исходники в venv
пакета — каталог `ktalk_cli/` внутри `site-packages` окружения, которым управляет `uv tool`
(путь машины-исполнителя не приводится — красная линия проекта против абсолютных путей
хозяина, `CLAUDE.md`). Каждый факт ниже подтверждён либо чтением кода (файл:строка внутри
пакета), либо командой с замаскированным выводом.

## Что уже измерено координатором (не перемерялось)

Живой замер 2026-09-07: `alive: true` без обеих переменных (файл токена перебивает
отсутствие окружения), `KTALK_PERSONAL_API_KEY` перебивает сессию с неточным сообщением
(issue [#11](https://github.com/mdemyanov/ktalk-cli/issues/11)), команды `doctor` в 2.1.0
нет, промт-слой сегодня называет оба режима равноправными (`references/onboarding.md:135-149`,
`README.md:133-142`, `openspec/specs/plugin-onboarding-sanctioned-install/spec.md:55-62`).

## 1. Источники токена и их приоритет

Подтверждено чтением `config.py:93-131` и `token_file.py:32-40`.

| Приоритет | Источник | Где читается | Комментарий |
|---|---|---|---|
| 1 (высший) | `KTALK_PERSONAL_API_KEY` (env либо `.env` в cwd) | `config.py:88`, `Settings.auth_mode` (`config.py:117-119`) | Пустая строка = «не задано» (`if self.ktalk_personal_api_key`) |
| 2 | `KTALK_SESSION_TOKEN` (env либо `.env`) | `config.py:89`, `Settings.auth_mode` (`config.py:120-121`) | Проверяется только если ключ пуст |
| 3 | Файл `ktalk-mcp/token` | `config.py:94-114` (`_fall_back_to_token_file`), путь строит `token_file.token_path()` | Подставляется model_validator'ом, только если **обе** переменные пусты — заданное окружение приоритетнее протухшего файла |
| — | Ничего не найдено | `config.py:122-126` | `KTalkConfigError`, текст называет обе переменные и `ktalk token set -` |

Путь файла токена (`token_file.py:32-40`) — своя мини-цепочка приоритета:
`KTALK_TOKEN_FILE` (полный путь, override) > `$XDG_CONFIG_HOME/ktalk-mcp/token` >
`~/.config/ktalk-mcp/token`. Каталог `ktalk-mcp/`, не `ktalk/` — рядом, но не там же, где
живёт санкция на запись (ADR-016), у неё другой владелец решения (`token_file.py:9-10`).

Права файла шире `0600` читаются как «файла нет» — `token_file.py:56-58`
(`stat.S_IMODE(...) & 0o077` → `None`), fail-closed, тот же барьер, что у санкции записи.
`.env`-файл читается pydantic-settings как источник **ниже** переменных окружения процесса
(`config.py:91`, `env_file=".env"`, `settings_customise_sources` не переопределён — действует
дефолтный порядок библиотеки: init > env > dotenv > default). [established]

**Приоритет целиком:** `KTALK_PERSONAL_API_KEY` (env/`.env`) → `KTALK_SESSION_TOKEN`
(env/`.env`) → файл `~/.config/ktalk-mcp/token` (или его override) → отказ.

## 2. Операции, требующие именно режима сессии

Таблица `OPERATION_PROFILES` (`endpoints.py:47-145`) — источник истины «операция × режим →
путь». Запись `None` для режима означает управляемый отказ до сети
(`OperationNotAvailableError`), не 401/403. Комментарий `client.py:117-121` называет их
явно: «все пять подтверждены только под session».

| Операция (внутреннее имя) | CLI-команда | `AuthMode.API_KEY` | Источник |
|---|---|---|---|
| `get_room` | `get-room` | `None` — недоступна | `endpoints.py:104-109` |
| `get_calendar` | `list-calendar` | `None` — недоступна | `endpoints.py:110-118` |
| `create_meeting` | `create-meeting-preview/-confirm` | `None` — недоступна | `endpoints.py:119-131` |
| `cancel_meeting` | `cancel-meeting-preview/-confirm` | `None` — недоступна | `endpoints.py:138-144` |
| `search_contacts` | `search-contacts` | `None` — недоступна | `endpoints.py:132-137` |

Отчёт боевой сессии называл только `list-calendar` — по коду список **полный и статичный**
(таблица не строится динамически): пять операций, пять CLI-команд. [established]

Симметрично: `list_archive` (`ktalk list-archive`) и `get_participants_report` (метод
клиента, ни в одну CLI-подкоманду не выведен — `grep` по `cli*.py` не находит его вызова
кроме `client.py:281-282`) требуют, наоборот, **только** `API_KEY` (`SESSION: None`,
`endpoints.py:78-83,98-103`) — зеркальная асимметрия важна для SA: не всё, что не session,
автоматически «работает под ключом сегодня».

## 3. Что произойдёт с каждым режимом при снятии личного ключа

Проверено чтением `client.py`, `auth.py`, `endpoints.py`; сетевых вызовов не делалось —
вывод целиком статический анализ веток.

**Останется живым без изменений** (у операции есть профиль `SESSION` либо она вообще не
идёт через `OPERATION_PROFILES`): `list_recordings`, `get_recording`, `get_transcript`,
`get_summary`, `get_summary_by_type`, `get_conference`, `get_room`, `get_calendar`,
`create_meeting`, `cancel_meeting`, `search_contacts`, `get_chat_messages` (путь строится
инлайн в `client._fetch_chat_messages`, `client.py:265-278`, не через таблицу),
`get_full_participants` (см. ниже — не дерево `OPERATION_PROFILES`).

**Станет мёртвым кодом (операция целиком недостижима под единственным оставшимся
режимом):**
- `list_archive` (CLI `list-archive`) — единственный профиль был `API_KEY`
  (`endpoints.py:78-83`); без ключа `_profile_for` всегда вернёт `None` и поднимет
  `OperationNotAvailableError` с текстом «доступна только в режиме персонального ключа».
- `get_participants_report` — тот же исход, но команда и без того не выведена в CLI
  (мёртвая точка входа уже сегодня, не только после удаления ключа).

**Смешанная ветка, требующая внимания SA** — `get_full_participants`
(`client.py:234-247`, CLI-команда `get-participants`): под `API_KEY` идёт по
пагинированному профилю (`full_participants_apikey`, `auth.py:240-256`); под `SESSION` —
**не через `OPERATION_PROFILES` вовсе**, а собирается из `get_recording` + `get_conference`
(оба живут под session) и помечает `incomplete`, если объединённый список короче
`participantsCount`. Удаление ключа не убивает операцию, но выключает её более полную,
не всегда достоверную ветку в пользу единственно оставшейся — session-ветки с явным
флагом неполноты. [established]

**Данные, а не поведение, тоже осиротеют:** записи `AuthMode.API_KEY` в
`OPERATION_PROFILES` (10 путей), ветка `AuthMode.API_KEY` в
`AuthContext.resolve`/`classify_response`/`get_auth_status`/`_auth_status_apikey`,
`SCOPE_LABELS` (используется только в 403-сообщении api-key-ветки, `auth.py:34-38,92-101`).
Это код, не данные пользователя — объём правки пакета, не входные для BA/SA.

## 4. Срок жизни сессионного токена

В коде **нет** ни одного поля, константы или обработчика, который знал бы срок действия
сессионного токена. `grep -in "ttl|expir|refresh"` по всему пакету находит только не
относящиеся к делу сущности: `CONFIRMATION_TTL` (`confirmation.py:27`, 10 минут — TTL
подтверждения записи, ADR другого назначения), `expires_at` санкции записи
(`write_sanction.py`), `anonymousAccessExpirationDate` тела встречи (`meeting_body.py`,
поле самого Толка, не токена), `expire_new()` реестра (`registry.py:546`, устаревание
записей реестра, не токена).

`AuthStatus.expired_at` для сессии **всегда `None`** — `client.py:325-333`
(`_auth_status_session`): единственный способ узнать «жив ли токен» — пробный сетевой
вызов `list_recordings(top=1)`; `KTalkAuthError` → `alive=False`, иначе `alive=True`.
Для api-key `expired_at` берётся из ответа сервера (`data.get("expiredAt")`,
`client.py:316`) — асимметрия по конструкции, не по недосмотру.

**Вывод:** срок жизни сессионного токена — целиком свойство контура (сервера Толка), CLI
его не знает и не может ни предсказать, ни продлить; узнаёт только реактивно, по первому
провалившемуся запросу. [established] Это и есть цена README-рекомендации «личный ключ для
постоянной работы»: сессия не имеет наблюдаемого TTL до отказа.

## 5. Поведение без единого токена

Живая проверка (`env -u KTALK_SESSION_TOKEN -u KTALK_PERSONAL_API_KEY -u KTALK_TOKEN_FILE
-u XDG_CONFIG_HOME HOME=<пустой временный каталог> ktalk ...`, каталог убран после
проверки):

| Команда | Код возврата | Текст | Куда |
|---|---|---|---|
| `auth-status --json` | 1 | `Не задана ни KTALK_PERSONAL_API_KEY, ни KTALK_SESSION_TOKEN. Укажите одну из переменных (см. README).` | stderr, `--json` проигнорирован (исключение до сериализации) |
| `list-recordings --json` | 1 | `Ошибка: Не задана ни KTALK_PERSONAL_API_KEY, ни KTALK_SESSION_TOKEN. Укажите одну из переменных (см. README).` | stderr, префикс `Ошибка:` — общий для `KTalkError`/`KTalkConfigError` |
| `token status` | 0 | `present: False — токен не записан (ktalk token set -)` | stdout — диагностика, отсутствие файла не ошибка |

Код `1` — не специализированный: `cli_sync.py:145-150` ловит `_AUTH_ERRORS = (KTalkError,
KTalkConfigError)` одним блоком и всегда возвращает `1`; отдельного кода для «нет ни одной
переменной и файла» не заведено (в отличие от `EXIT_SANCTION_EXPIRED = 41` у санкции записи
или `EXIT_BAD_ARGS = 2` у `token`-подкоманды). [established]

## Что не удалось установить

- **Поведение при живом сетевом 401/403 под каждым режимом** — таблица `classify_response`
  (`auth.py:74-113`) читана статически; ни один боевой отказ авторизации намеренно не
  вызывался (граница задачи — секретов и порчи токена не создавать).
- **Фактическая частота протухания сессии на этом контуре** (сколько часов/дней живёт
  токен в среднем) — не свойство кода, эмпирика контура, вне доступа этой задачи.
- **`get_participants_report` — почему нет CLI-обвязки**: код не отвечает, был ли это
  осознанный выбор (операция ещё не понадобилась) или недосмотр при выводе метода в
  команду; журнала решений пакета `ktalk-cli` здесь нет.

## Рекомендации для BA/SA

- **BA:** формулируя «единственный режим — session», учти зеркальную асимметрию из §2 —
  `list-archive` сегодня работает **только** под ключом; при переходе на единственный
  session-режим эта команда либо теряется, либо требует отдельного решения (в задаче
  не решается, это её материал).
- **BA:** различай в тексте требования «операция недоступна под этим режимом»
  (`OperationNotAvailableError`, управляемый отказ до сети) и «токен истёк»
  (`KTalkAuthError`, отказ сети) — код их уже различает, требование не должно их путать.
- **SA:** `get_full_participants` под session — не «то же самое, но хуже», а другая
  формула данных (дедуп двух источников + флаг `incomplete`) — учти при проектировании
  ADR-028, не как деградацию одного эндпоинта.
- **SA:** решение об отказе от api-key-режима означает удаление данных `OPERATION_PROFILES`
  и веток `classify_response`/`_auth_status_apikey`/`full_participants_apikey`/
  `SCOPE_LABELS` — это код пакета `ktalk-cli`, не промт-слоя; ADR должен явно назвать,
  что правка выходит за пределы дерева плагина (ADR-012).
- **SA:** отсутствие TTL у сессии (§4) — не то, что можно «починить» в промт-слое:
  единственный наблюдаемый сигнал смерти токена — реактивный 401 на первом вызове.
  Любое требование вида «предупреждать заранее» упирается в это ограничение контура.

## Источники

- [primary] `config.py` (Settings, `_fall_back_to_token_file`, `auth_mode`) — приоритет
  источников токена
- [primary] `token_file.py` (`token_path`, `read_token`, `write_token`) — путь и права
  файла токена
- [primary] `endpoints.py` (`OPERATION_PROFILES`, `OPERATION_LABELS`) — таблица операций
  по режиму
- [primary] `client.py` (`_profile_for`, `get_full_participants`, `_auth_status_session`,
  `_fetch_chat_messages`) — фактическое ветвление по режиму
- [primary] `auth.py` (`AuthContext.resolve`, `classify_response`, `full_participants_apikey`)
  — приоритет ключ/сессия и классификация отказов
- [primary] `cli_token.py`, `cli_sync.py` (`cmd_auth_status`) — коды возврата CLI
- [primary] живые команды `ktalk auth-status/list-recordings/token status` без токена
  (временный `HOME`, выведено выше) — подтверждение кода возврата и текста
- [secondary] `references/onboarding.md:135-149`, `README.md:133-142`,
  `openspec/specs/plugin-onboarding-sanctioned-install/spec.md:55-62` — текущее
  утверждение промт-слоя плагина (два равноправных режима), контекст для BA/SA, не факт
  о пакете
