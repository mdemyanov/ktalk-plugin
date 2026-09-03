---
properties:
  - name: Тип контента
    value: [Архитектура]
  - name: Фаза
    value: [Pilot]
  - name: Статус
    value: [Draft]
  - name: Audience
    value: [Internal]
---

# Поставочная поверхность плагина и доставка релиза потребителю

**ADR:** `content/00-project/adr/ADR-025-release-delivery-surface.md`
**Requirement:** `content/30-requirements/2026-09-03-release-delivery-tails.md`
**Capability:** `openspec/specs/release-delivery-tails/spec.md`

## Context

ADR-025 решает семь вопросов поставочной поверхности плагина. Эта статья — реализационная
деталь: точные точки правки по файлам и строкам (замерено в этой сессии, не унаследовано),
брифы для Dev и DevOps, контракт для QA-author. Два свойства требования (делегирование
`project-curator`, проверка личности транскрипта, issue #5/#6) — предмет параллельного
ADR-026, не этой статьи.

## Components

| Компонент | Ответственность | Входы | Выходы | Зависимости |
|-----------|------------------|-------|--------|-------------|
| `.claude-plugin/plugin.json` | Источник версии релиза | правка Dev при релизе | `version`, читаемый `claude plugin tag` | — |
| `.claude-plugin/marketplace.json` | Манифест маркетплейса | правка Dev (Д2) | top-level `description` + запись `plugins[0]` | `claude plugin validate .` |
| `claude plugin tag` (внешний, платформа) | Формирует и создаёт релизный тег | `plugin.json`, запись маркетплейса | тег формы `ktalk--vX.Y.Z`, коммит-провенанс | git, согласие манифестов (встроенная проверка) |
| `README.md` §«Быстрый старт»/«Если что-то не работает» | Документирует путь установки/обновления, интерфейс токена | правка Dev (Д3, Д6) | текст для оператора | факт CLI-поверхности пакета |
| `references/ktalk-processor/*.md` (новое расположение) | Справочный материал `ktalk-processor`, не самостоятельная роль | правка Dev — перенос из `agents/references/` (Д5) | те же три файла, вне сканируемого каталога агентов | `agents/ktalk-processor.md` и внешние цитирующие файлы |
| `content/.doc-root.yaml`, `.nauta-gates.yaml` (комментарий) | Служебные метаданные дерева | правка Dev (Д6) | описание зависимости по роли, без retired-литерала | `compat.json` — авторитет имени |
| `.nauta-gates.yaml`: `projectGates`, `branchDiscipline` | Точка подключения проектных гейтов и профиля веток | правка Dev (Д7) | исполнение `check-plugin-composition.sh`/`check-prompt-language.sh` (`fast:`), `test-onboard.sh` (`full:`); `profile: single` | `scripts/check.sh` (носитель `nauta`, не редактируется) |
| `scripts/check-plugin-composition.sh`: функция `check()` | Ищет в дереве следы хозяина; сегодня не исключает `.git`-файл worktree и `.nauta-authority-observations.jsonl` | грep по дереву | `fail=1` при находке | требует точечного расширения `--exclude` до подключения в `projectGates` (см. «Находка при верификации») |

## Boundaries

- Дифф ограничен точками, названными по файлу и строке в разделах ниже; ни один файл вне
  этого списка не входит в область.
- Самообнаружение устаревания плагином не проектируется этой статьёй — ADR-025 Д4 отклоняет
  саму возможность в этом раунде; онбординг-скрипт не получает нового кода чтения
  `~/.claude/plugins/*`.
- Ре-синк базиса `nauta` не выполняется этой задачей (ADR-025 Д7) — точечный фикс
  `check-plugin-composition.sh` ниже не является ре-синком: правится файл, которым владеет
  этот репозиторий, не файл из `.nauta-scripts-basis.yaml`.
- Делегирование `project-curator` и проверка личности транскрипта — вне этой статьи, ADR-026.

## Точка правки: тег релиза (Д1 ADR-025)

Релизный рансбук (`content/70-operations/2026-08-31-package-rename-transition-release-runbook.md`,
шаг 5, «Обновить пин, версию плагина, отметить тег» — образец для будущих релизов) сегодня
использует `git tag v1.8.0`. Начиная со следующего релиза после этого решения, шаг заменяется
на:

```bash
claude plugin tag              # без --dry-run — создаёт и пушит тег
```

Живая проверка (2026-09-03, эта рабочая копия, `--dry-run --force` — только чтение, тег не
создан и не запушен):

```
$ claude plugin tag --dry-run --force
Plugin:  ktalk
Version: 1.9.0 (from plugin.json)
Marketplace entry: plugins[0] in .../.claude-plugin/marketplace.json
Tag:     ktalk--v1.9.0
✔ Dry run — would create tag ktalk--v1.9.0 at HEAD
  git tag -f -a ktalk--v1.9.0 -m "ktalk 1.9.0"
  git push --force origin refs/tags/ktalk--v1.9.0
```

Шесть существующих тегов (`git tag -l`: `v1.3.0`, `v1.5.0`, `v1.6.0`, `v1.7.0`, `v1.8.0`,
`v1.9.0`) не трогаются этим переходом — они остаются историческим следом прежней конвенции
(ADR-025 Д1). Следующий релиз плагина — первый, тегируемый новой командой.

## Точка правки: `description` маркетплейса (Д2 ADR-025)

```json
{
  "name": "ktalk-plugins",
  "owner": { "name": "mdemyanov" },
  "plugins": [ { "name": "ktalk", "source": "./", "description": "…" } ],
  "description": "<текст, отличный от description записи плагина>"
}
```

Живая проверка (2026-09-03, скретч-правка этой сессии, откачена, в рабочую копию не
закоммичена): добавление top-level `description` убирает предупреждение `claude plugin
validate .` полностью — было `⚠ Found 1 warning: description: No marketplace description
provided`, стало `✔ Validation passed` без предупреждений.

## Точка правки: путь обновления (Д3 ADR-025)

`README.md`, раздел «2. Поставьте плагин» (сегодня строка 30, только первая команда):

```
/plugin marketplace add https://doc-hub.gitlab.yandexcloud.net/tools-ai/ktalk-plugin.git
/plugin install ktalk@ktalk-plugins
```

Обновление уже установленной копии — **обе** команды, в этом порядке, плюс перезапуск:

```
claude plugin marketplace update ktalk-plugins   # обновляет локальный кэш маркетплейса
claude plugin update ktalk@ktalk-plugins         # переводит УЖЕ УСТАНОВЛЕННУЮ копию на новую версию
# затем — перезапустить сессию (платформа сообщает "Restart to apply changes")
```

Рядом — предложение о границе (текст, не код): «Плагин не может включить фоновое обновление
за вас — платформа не даёт издателю такого ключа. Обновление — ваше действие, эти две команды
— полный путь до него». Живые данные, на которые опирается формулировка: `~/.claude/plugins/
known_marketplaces.json` этой машины — 23 записи, ровно одна (`nsmp-plugins`) несёт
`"autoUpdate": true`; `claude plugin marketplace add --help` не перечисляет флага для этого
ключа (только `--scope`, `--sparse`).

## Точка правки: retired-имя и MCP-claim (Д6 ADR-025)

| Файл | Строка | Было | Становится |
|---|---|---|---|
| `content/.doc-root.yaml` | 10 | `...плагина ktalk (обёртка над ktalk-mcp)` | `...плагина ktalk (обёртка над отдельно устанавливаемым CLI-пакетом)` |
| `.nauta-gates.yaml` | 103 (комментарий) | `...прикладной код в отдельном пакете ktalk-mcp...` | `...прикладной код в отдельно устанавливаемом CLI-пакете...` |
| `README.md` | 50 | `файл подхватывают и CLI, и MCP-сервер` | `файл подхватывает CLI` (единственный интерфейс, `ktalk --help` не содержит `mcp`/`serve`) |

Строка `README.md:48` (`~/.config/ktalk-mcp/token`) не входит в эту таблицу — путь
конфигурации, не имя пакета, подтверждён `ktalk token status` буквально.

## Точка правки: перенос `agents/references/` (Д5 ADR-025)

Новое расположение: `references/ktalk-processor/two-pass-analysis.md`,
`references/ktalk-processor/protocol-template.md`,
`references/ktalk-processor/vault-update-and-report.md`.

**Внутри `agents/ktalk-processor.md`** — восемь ссылок приводятся к форме
`${CLAUDE_PLUGIN_ROOT}/references/ktalk-processor/<файл>.md`:

| Строка | Было | Становится |
|---|---|---|
| 47 | `` `references/two-pass-analysis.md` `` | `` `${CLAUDE_PLUGIN_ROOT}/references/ktalk-processor/two-pass-analysis.md` `` |
| 48 | `` `references/protocol-template.md` `` | `` `${CLAUDE_PLUGIN_ROOT}/references/ktalk-processor/protocol-template.md` `` |
| 49 | `` `references/vault-update-and-report.md` `` | `` `${CLAUDE_PLUGIN_ROOT}/references/ktalk-processor/vault-update-and-report.md` `` |
| 150 | `` `references/two-pass-analysis.md` `` | то же, полная форма |
| 188 | `` `references/two-pass-analysis.md` `` | то же |
| 222 | `` `references/protocol-template.md` `` | то же |
| 311 | `` `references/vault-update-and-report.md` `` | то же |
| 315 | `` `references/vault-update-and-report.md` `` | то же |

**Вне `agents/ktalk-processor.md`** — литеральный путь `agents/references/…` встречается ещё
в пяти файлах (полная сверка `grep -rn` по всем трём именам файлов в этой сессии, не только по
восьми ссылкам, названным требованием):

| Файл | Строки | Литерал |
|---|---|---|
| `skills/ktalk-eval/references/eval-rubric.md` | 95, 111 | `agents/references/protocol-template.md` |
| `skills/ktalk-registry/references/analysis-quality.md` | 81 | `agents/references/two-pass-analysis.md` |
| `skills/ktalk-registry/references/registry-format.md` | 153 | `agents/references/protocol-template.md` |
| `openspec/specs/meeting-analysis-quality-calibration/spec.md` | 6–7 | `agents/references/two-pass-analysis.md`, `agents/references/protocol-template.md` |
| `openspec/specs/prompt-language-boundary/spec.md` | 73 | `agents/references/protocol-template.md` |

Во всех пяти — путь без `${CLAUDE_PLUGIN_ROOT}`-префикса (репозиторно-корневой, прозаическая
цитата для читателя документа, не путь, резолвимый агентом в рантайме); правка — замена
подстроки `agents/references/` на `references/ktalk-processor/`, без изменения смысла
предложения.

**Не требует правки, но стоит упоминания:** `openspec/specs/prompt-language-boundary/spec.md`,
строка 30, перечисляет `agents/references/` как один из трёх видов каталога-источника
справочников наравне с `skills/*/references/` и `references/`. После переезда этот член
перечисления не соответствует ни одному реальному пути — не ложное утверждение (перечисление
условное, «если файл под этим каталогом»), а вакуумно-истинная, всегда пустая ветвь. Правка
не блокирующая; можно снять отдельным, не срочным проходом QA-author/SA при следующей правке
этой capability.

**Бесследные упоминания** (не путь, просто имя файла в прозе, не требуют правки):
`skills/ktalk-registry/_meta.md` строки 68, 71, 85.

## Находка при верификации: `check-plugin-composition.sh` ложно падает в worktree

При проверке Д7 (подключение `check-plugin-composition.sh` в `projectGates`) обнаружено два
независимых пробела в исключениях функции `check()` (`scripts/check-plugin-composition.sh`),
оба воспроизводятся только при исполнении из рабочей копии-worktree (`.git` там — файл-
указатель с абсолютным путём, не каталог; в обычном клоне `.git` — каталог, уже исключённый
`--exclude-dir=.git`):

```
$ bash scripts/check-plugin-composition.sh
FAIL: абсолютный путь домашнего каталога
./.git:1:gitdir: <абсолютный путь> /ktalk-plugin/.git/worktrees/<id>
```

`--exclude-dir=.git` матчит только КАТАЛОГИ; файл с именем `.git` под тот же флаг не подпадает.
Второй, независимый пробел (уже устранён удалением файла из рабочей копии на время
верификации, не правкой скрипта): untracked `.nauta-authority-observations.jsonl` (хук
`nauta`, «наблюдения второго контура», по собственному `.gitignore` `nauta 0.28.2` — «запись
сессии рабочей машины, не коммитится») тоже не входит в исключения и тоже воспроизводит ту же
находку по своему содержимому.

Оба пробела — не предмет ADR-025 по существу (они не про состав плагина), но становятся
блокирующими в тот момент, когда Д7 подключает этот скрипт в `projectGates`: без починки
гейт будет красным в каждом прогоне из worktree — стандартном режиме исполнения ролей этого
репозитория (`CLAUDE.md`, «Ты работаешь в изолированной рабочей копии» — общая инструкция
каждой роли). Красный гейт, который не отражает реального нарушения состава, обучает
игнорировать его быстрее, чем отсутствующий гейт — тот самый vacuous-класс дефекта, о котором
уже предупреждает `content/lessons-learned.md`.

**Требуется до или вместе с Д7** (companion, не ADR — правка кода): добавить в вызов `grep`
внутри `check()` два исключения дополнительно к уже существующим четырём:

```bash
--exclude=.git \
--exclude=.nauta-authority-observations.jsonl \
```

(файловая форма `--exclude`, не `--exclude-dir` — предмет здесь файлы, не каталоги).

## Точка правки: `.nauta-gates.yaml` (Д7 ADR-025)

Проверено вживую (скретч-правка этой сессии, применена, прогнана, откачена — `git diff
--stat` после отката пуст):

```yaml
projectGates:
  fast:
    - scripts/check-plugin-composition.sh
    - scripts/check-prompt-language.sh
  full:
    - scripts/test-onboard.sh

branchDiscipline:
  profile: single
```

`bash scripts/check.sh --fast` с этим блоком (после исправления двух `--exclude`, см. выше) —
исполняет оба `fast:`-гейта, печатает `projectGates: configured (2 позиций)`, профиль `single`
принят `check-branch-discipline.py` без ошибки. `bash scripts/check.sh --full` дополнительно
исполняет `test-onboard.sh` (замер — `PASS: 106 FAIL: 0`, ~33 с) один раз, не дважды (`fast:`-
записи не повторяются в `--full`, механизм `check.sh` это гарантирует).

## Integration points

| Точка | Протокол | Контракт | Auth | Rate limit | Обработка ошибок |
|-------|----------|----------|------|------------|-------------------|
| `plugin.json`/`marketplace.json` → `claude plugin tag` | подпроцесс `claude` | тег `<plugin>--v<version>`, встроенная сверка манифестов | локальный git push (доступ релиз-инженера) | — | несогласие манифестов — платформа отказывает до создания тега |
| README → оператор | текст, ручное исполнение двух команд | `marketplace update` → `plugin update` → рестарт | — | — | неполный путь — установленная версия не меняется, без сигнала (устраняется этим решением) |
| `agents/ktalk-processor.md` → `references/ktalk-processor/*.md` | статическая ссылка, `${CLAUDE_PLUGIN_ROOT}`-относительная | путь резолвится агентом в рантайме | — | — | нерезолвящийся путь — Read возвращает ошибку, агент не может продолжить шаг |
| `.nauta-gates.yaml` → `scripts/check.sh` (`projectGates`) | чтение конфигурации, исполнение по расширению (`.sh`/`.py`) | путь относительный от корня, без `..` | — | — | путь абсолютный/вне дерева/без расширения/не существует — ERROR, гейт не исполняется (носитель — `.nauta-gates.yaml`, не базис доставки) |

## NFR Mapping

| Requirement / Scenario | Как удовлетворяется |
|---|---|
| A release tag resolves in the form the platform expects | `claude plugin tag` — обязательный шаг вместо ручного `git tag`, начиная со следующего релиза (Д1) |
| The marketplace manifest declares a description | Top-level `description` в `.claude-plugin/marketplace.json`, отдельно от записи плагина (Д2) |
| The documented update path names every command it takes to move an installed plugin forward | README называет обе команды в порядке + перезапуск (Д3) |
| A file that is a reference, not an agent, is not registered as one — 2 сценария | Перенос трёх файлов из `agents/references/` в `references/ktalk-processor/`; все известные цитирующие пути поправлены тем же раундом (Д5) |
| Prompt-layer text and metadata do not name a retired package identity | `content/.doc-root.yaml`, `.nauta-gates.yaml` — retired-литерал заменён описанием по роли (Д6) |
| README's operational claims match the interface the package actually exposes | `README.md:50` называет только CLI, проверено `ktalk --help` (Д6) |
| The GO-criterion gates CLAUDE.md names are enforced automatically — 3 сценария | `projectGates` (`fast:`/`full:`), `branchDiscipline.profile: single` (Д7); базис `nauta` — отдельная задача, симптом отставания назван и устранён точечно |

## Brief for Dev

**Architecture:** этот файл **Requirement:**
`content/30-requirements/2026-09-03-release-delivery-tails.md` **Phase:** Pilot

**Implement:**
- `.claude-plugin/marketplace.json`: top-level `description` (Д2).
- `README.md`: раздел «2. Поставьте плагин» — обе команды обновления + перезапуск + фраза о
  границе (Д3); строка 50 — только CLI (Д6).
- `content/.doc-root.yaml:10`, `.nauta-gates.yaml:103` — retired-литерал → описание по роли
  (Д6, точная замена — таблица выше).
- Перенос трёх файлов `agents/references/*.md` → `references/ktalk-processor/*.md`; восемь
  ссылок `agents/ktalk-processor.md` → `${CLAUDE_PLUGIN_ROOT}`-форма; пять внешних файлов с
  литеральным путём `agents/references/…` (таблица выше) — замена подстроки (Д5).
- `scripts/check-prompt-language.sh`: две записи словаря `VERBATIM` (`agents/references/
  protocol-template.md`, `agents/references/vault-update-and-report.md`, строки 66, 71) →
  новый путь; словарь `files = sorted(...)` уже сканирует `references/` — нового каталога
  добавлять не нужно.
- `scripts/test-agreements-reconciliation.sh`: `VAULT_REF` (строка 23) и комментарий (строка
  6) → новый путь.
- `scripts/check-plugin-composition.sh`, функция `check()`: добавить `--exclude=.git` и
  `--exclude=.nauta-authority-observations.jsonl` к вызову `grep` — **до** или **вместе** с
  подключением этого скрипта в `projectGates`, иначе гейт красный в каждом worktree (см.
  «Находка при верификации»).
- `.nauta-gates.yaml`: блок `projectGates` (`fast:`/`full:`) и `branchDiscipline.profile:
  single` — точный YAML в разделе «Точка правки: `.nauta-gates.yaml`» выше, проверен вживую.
- Релизный рансбук будущего релиза (по образцу
  `content/70-operations/2026-08-31-package-rename-transition-release-runbook.md`, шаг 5) —
  `git tag vX.Y.Z` → `claude plugin tag` (Д1); это отдельный документ следующего релиза, не
  правка существующего (тот описывает уже состоявшийся релиз, тем же приёмом, что и его
  собственное решение не переписывать соседний runbook).

**Не в этом раунде:** правка `openspec/specs/prompt-language-boundary/spec.md:30` (вакуумная,
не срочная ветвь перечисления, см. выше) — можно оставить следующему проходу.

**Order:** `check-plugin-composition.sh` (два `--exclude`) → перенос `agents/references/*.md`
и правка всех цитирующих путей → `.nauta-gates.yaml` (`projectGates`, `branchDiscipline`) →
`marketplace.json`/`README.md`/`content/.doc-root.yaml`/`.nauta-gates.yaml` (текстовые правки)
→ `bash scripts/check.sh --full` целиком.

**Acceptance scenarios:** `A release tag resolves in the form the platform expects`; `The
marketplace manifest declares a description`; `The documented update path names every command
it takes to move an installed plugin forward`; `A reference file does not appear as an agent
in the session's tool list`; `Every agent-carrying file the platform validates still resolves
correctly`; `Repository metadata describing the plugin's dependency names no retired package`;
`README's token-file claim names only interfaces the package exposes`; `The composition and
language gates run as part of the automated check`; `The branch-naming discipline is judged,
not undetermined`; `The gate-delivery basis is not silently behind the installed tooling` — все
из `openspec/specs/release-delivery-tails/spec.md`.

## Brief for DevOps

**Architecture:** этот файл

**Prepare:**
- Следующий релизный рансбук — шаг тегирования заменяется на `claude plugin tag` (Д1); шесть
  существующих тегов не трогаются.
- Ре-синк базиса `nauta` (0.27.0 → 0.28.2, три новых гейта) — заводится отдельной задачей,
  не частью этого релиза; конкретный симптом отставания (`.gitignore` не несёт
  `.nauta-authority-observations.jsonl`) можно снять до полного ре-синка точечной правкой
  `.gitignore` этого репозитория (файл не входит в замороженный по sha256 список
  `.nauta-scripts-basis.yaml` — правка не является правкой чужой поставки).
- Мониторинг: нет новых сетевых сервисов; единственный новый наблюдаемый сигнал —
  `projectGates: configured (N позиций)` в выводе `check.sh`, норма — совпадение `N` с числом
  объявленных путей.

**NFRs from BA:** полнота документированного пути обновления (Д3); отсутствие retired-имени в
метаданных и README (Д6); автоматическое исполнение GO-критериев (Д7).

## Contract with QA-author

**Acceptance scenarios (полный список, кроме предмета ADR-026):**
- Scenario: The release tag matches the platform's dry-run form — из `### Requirement: A
  release tag resolves in the form the platform expects`
- Scenario: Marketplace validation reports no missing-description warning — из `###
  Requirement: The marketplace manifest declares a description`
- Scenario: The documented sequence moves an installed copy to the new version — из `###
  Requirement: The documented update path names every command it takes to move an installed
  plugin forward`
- Scenario: A reference file does not appear as an agent in the session's tool list — из `###
  Requirement: A file that is a reference, not an agent, is not registered as one`
- Scenario: Every agent-carrying file the platform validates still resolves correctly — там же
- Scenario: Repository metadata describing the plugin's dependency names no retired package —
  из `### Requirement: Prompt-layer text and metadata do not name a retired package identity`
- Scenario: README's token-file claim names only interfaces the package exposes — из `###
  Requirement: README's operational claims match the interface the package actually exposes`
- Scenario: The composition and language gates run as part of the automated check — из `###
  Requirement: The GO-criterion gates CLAUDE.md names are enforced automatically`
- Scenario: The branch-naming discipline is judged, not undetermined — там же
- Scenario: The gate-delivery basis is not silently behind the installed tooling — там же

**Architectural context for the tests:**
- Компоненты: `.claude-plugin/plugin.json`/`marketplace.json` (статические файлы, не код),
  `README.md` (текст), `agents/ktalk-processor.md` + `references/ktalk-processor/*.md`
  (перекрёстные ссылки), `content/.doc-root.yaml`/`.nauta-gates.yaml` (метаданные),
  `scripts/check-plugin-composition.sh`/`check-prompt-language.sh`/`test-onboard.sh` (гейты,
  исполняются через `.nauta-gates.yaml`/`projectGates`).
- Интеграции: `claude plugin` CLI (внешний, платформа) — тег и валидация манифеста; сеть не
  задействована ни в одном из этих сценариев (в отличие от `package-rename-transition`, где
  сетевой гейт был предметом отдельного сценария).
- Границы доверия: README/метаданные — текст для человека, не машинный вход; `plugin.json`/
  `marketplace.json` — вход внешнего инструмента платформы (`claude plugin tag`/`validate`),
  трастовая граница — согласие двух файлов друг с другом, проверяемое самим инструментом.

**Edge cases / boundary conditions:**
- Тег: сценарий проверяет СТРОКУ, которую печатает `claude plugin tag --dry-run`, не
  предположение о формате — тест обязан реально вызвать инструмент (или его стаб,
  воспроизводящий контракт), не сравнивать с захардкоженной строкой `ktalk--vX.Y.Z`
  независимо от `plugin.json`.
- Справочники-не-агенты: тест обязан проверить ОБЕ стороны — файл действительно вне
  `agents/` (или любого каталога, который сканируется как источник агентов), И ссылки на него
  всё ещё резолвятся (два разных отказа: «нет в списке агентов» ложноположительно проходит,
  если файл просто переименован в нерезолвящийся путь).
- Retired-имя: тест на «метаданные не называют retired-имя» не должен проверяться сравнением
  с ТЕКУЩИМ значением `compat.json` (тот же класс vacuous-теста, что урок 2026-09-01,
  QA-author, `ktalk-plugin-foz.17`, уже предупреждает) — мутировать `compat.json` на третье,
  синтетическое имя и убедиться, что проверяемый файл по-прежнему не содержит НИ retired, НИ
  синтетическое имя буквально (описание по роли не зависит от значения вовсе).
- GO-критерии автоматически: тест обязан провалиться, если `projectGates` объявлен, но путь
  гейта не существует, гейт исполняется, но `check.sh` не отражает его код возврата в своём
  итоговом коде — то есть подключение не декоративное (гейт значится в выводе), а
  действующее (падение гейта валит весь прогон).
- `branchDiscipline`: явно проверить оба значения перечисления (`single`, `team`) дают разный
  вердикт на одной и той же паре имён веток — не только то, что `single` объявлен.

**Test-pyramid recommendation:**

| Группа сценариев | Уровень | Обоснование |
|---|---|---|
| The release tag matches the platform's dry-run form | integration/e2e | реальный вызов `claude plugin tag --dry-run` или его точный контрактный стаб, не юнит над строкой |
| Marketplace validation reports no missing-description warning | integration | реальный вызов `claude plugin validate .` над фикстурой манифеста |
| The documented sequence moves an installed copy to the new version | вне автоматизируемого контракта этого дерева | обе команды — платформенные, состояние (`installed_plugins.json`) вне репозитория; проверяется ревью текста README против факта команд, не тестом кода |
| A reference file does not appear as an agent / ссылки резолвятся | unit (статическая проверка пути) + integration (`claude plugin tag --dry-run` не выдаёт предупреждение о файле как об агенте) | путь — файловая система, регистрация как агента — платформенное поведение, разные уровни |
| Repository metadata describing the plugin's dependency names no retired package | unit | grep/поиск по файлам, без подпроцессов |
| README's token-file claim names only interfaces the package exposes | unit | статическое чтение README + `ktalk --help` в CI-окружении с установленным CLI |
| The composition and language gates run as part of the automated check | integration | реальный прогон `check.sh --fast`/`--full` со стаб-деревом, проверка кода возврата и наличия строк-репортов обоих гейтов |
| The branch-naming discipline is judged, not undetermined | unit | `check-branch-discipline.py` уже принимает `--` аргументы напрямую, без сети |
| The gate-delivery basis is not silently behind the installed tooling | вне автоматизируемого контракта этого дерева | сравнение версий — процедурная проверка при апдейте `nauta`, не тест кода этого репозитория |
