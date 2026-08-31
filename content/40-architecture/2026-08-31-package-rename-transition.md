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

# Переход `ktalk-mcp` → `ktalk-cli`: схема идентичности пакета, коллизия слота, откат

**ADR:** `content/00-project/adr/ADR-024-package-rename-transition.md`
**Requirement:** `content/30-requirements/2026-08-31-package-rename-transition.md`
**Capability:** `openspec/specs/package-rename-transition/spec.md`

## Context

ADR-024 решает пять архитектурных вопросов перехода. Эта статья — реализационная деталь:
точная схема `compat.json`, расширение функций `scripts/ktalk-onboard.sh` (с номерами строк
сегодняшнего кода), форма коллизии слота, схема отката с учётом кода 127, и контракты для
Dev, DevOps, QA-author. Механика переименования модулей внутри пакета (`ktalk_mcp` →
`ktalk_cli`, снятие `fastmcp`) — дерево пакета, собственный SA-процесс там же, здесь только
упомянута как зависимость.

## Components

| Компонент | Ответственность | Входы | Выходы | Зависимости |
|-----------|------------------|-------|--------|-------------|
| `compat.json` | Источник контракта идентичности пакета: имя + версия | правка Dev/DevOps при релизе, меняющем идентичность | ключи `package_name`, `package_version` | читается `pin_name()`/`pin_version()` |
| `ktalk-onboard.sh`: `pin_name()` (новая) / `pin_version()` (переименованный ключ) | Читают пин из `compat.json` | `compat.json` | имя пакета и версия либо отказ (`E_INTERNAL=20`) | grep/sed, не JSON-парсер — не меняется |
| `ktalk-onboard.sh`: `installed_identity()` (расширение `installed_version()`) | Определяет фактически установленный пакет и версию | `ktalk --version` (оба токена), fallback — `uv tool list` по конечному списку имён | пара (имя, версия), либо признак «оба зарегистрированы» | список известных идентичностей `{ktalk-mcp, ktalk-cli}` |
| `ktalk-onboard.sh`: `cmd_check`/`finish_install` | Сравнивают имя и версию раздельно | `pin_name`/`pin_version`, `installed_identity` | коды `0/10/11/12/13(new)/20` | `identity_eq` (новая) отдельно от `version_eq` (не меняется) |
| `ktalk-onboard.sh`: `cmd_install`, `remedy_cmd_text`/`remedy_cmd_array` | Строят и исполняют ремонт без `--force`; распознают отказ `uv` при коллизии слота | `pin_name` (не литерал), санкция | коды включая `34(new)` — коллизия | `run_install`/`run_clean` — не меняются |
| Ручной override (вне скрипта) | Оператор сам набирает `uv tool install <pkg>==<pin> --force` | — | — | не вызывается ни одной функцией скрипта, ни при какой санкции |
| Пред-релизный гейт (расширение AC-9 `cli-only-boundary`) | Тот же принцип, применённый к каналу `ktalk-cli` | `compat.json`, индекс пакета | блокирующий код | сетевой запрос, вне `check-plugin-composition.sh` |

## Boundaries

- Дифф ограничен теми же шестью точками, что называет требование: `compat.json`,
  `README.md`, `references/onboarding.md`, `scripts/ktalk-onboard.sh`,
  `scripts/test-onboard.sh`, текст имени пакета в `.claude-plugin/plugin.json`. Ни один файл
  `skills/`, `agents/`, `commands/` не входит в этот дифф.
- Скрипт никогда не добавляет `--force` сам — ни в обычном install, ни под `allow_update`, ни
  в ветке коллизии. Единственное место `--force` в этой архитектуре — ручной шаг отката
  (Д4 ADR-024), набираемый оператором, не предлагаемый и не исполняемый автоматизацией.
- Версия-указатель `ktalk-mcp` не получает отдельной логики: любая `ktalk-mcp` равно
  `wrong_package` относительно пина на `ktalk-cli` (Д5 ADR-024).
- Не проверяет цепочку поставки по хэшам — унаследованный вывод из области `cli-only-boundary`
  и `package-rename-transition`.
- Не проектирует код `--version` пакета `ktalk-cli` — дерево пакета, SA-002; здесь фиксируется
  только контракт формата (см. «Точка правки: формат `--version`» ниже).

## Data flow

1. `pin_name()`/`pin_version()` читают `compat.json` → пара (имя, версия) либо `E_INTERNAL=20`,
   если отсутствует хоть одно поле — fail closed, тот же принцип, что уже применён к
   отсутствующему ключу версии.
2. `installed_identity()`:
   - `command -v ktalk` не резолвится → `missing_cli` (`E_MISSING_CLI=10`), без изменений.
   - `ktalk --version` разбирается на два токена: первый — литерал имени дистрибутива (сегодня
     `ktalk-mcp`, вывод которого уже содержит его — `ktalk_mcp/cli.py:381`, дерево пакета,
     прочитано, не изменено), второй/остаток — номер версии тем же регэкспом, что и сегодня.
   - Если первый токен не распознан как имя из известного списка — резервный путь: построчный
     грep `uv tool list` по **обоим** известным именам (`^ktalk-mcp[[:space:]]`,
     `^ktalk-cli[[:space:]]`). Если совпали обе строки — не отказ сам по себе, а диагностический
     признак `registered_both` в JSON-выводе (коллизия уже случилась ранее, вероятно, через
     ручной `--force`).
3. Сравнение раздельно по осям:
   - имя не совпадает с пином → **новый статус `wrong_package`**, код `E_WRONG_PACKAGE=13`
     (группа кодов `check`, следом за `12`); сообщение называет оба имени, не предлагает
     `--force`.
   - имя совпадает, версия — нет → `outdated` (`E_OUTDATED=11`), без изменений.
   - обе оси совпали → `ok`.
4. `cmd_install`: если команда уже существует и указывает на **другой** пакет — та же ветка,
   что сегодня трактует «команда существует» как мутацию существующего состояния (ADR-022 Д2);
   санкция `allow_update`, без нового ключа. Ремонт всегда без `--force`. Если `uv` сам
   отказывает текстом `Executable already exists` (замер BA, код 2) — распознаётся грепом по
   захваченному `RI_OUT`, репортится **новый статус `slot_collision`**,
   код `E_SLOT_COLLISION=34` (группа кодов `install`, после `33`), а не общий
   `install_failed=31`; сообщение называет оба пакета и явно говорит, что принудительная замена
   не выполняется автоматически.
5. После ручного override (оператор сам выполнил `--force`) — следующий `check` заново вызывает
   `installed_identity()`: теперь `ktalk --version` называет имя второго пакета, `cmd_check`
   печатает именно его как активного, не «оба» и не молчание — обязательный AC (сценарий
   «An overridden takeover leaves a diagnosable trail»).
6. После `uv tool uninstall` пакета, чей бинарник был жив (третья строка таблицы BA) —
   `command -v ktalk` перестаёт резолвиться (файл стёрт), и это уже сегодня первый гейт
   `cmd_check`, до любого обращения к `uv tool list` — путь возвращает `missing_cli`, не
   «совместим», даже если `uv tool list` продолжает числить второй, недействующий пакет
   владельцем. Дизайн подтверждает существующий порядок гейтов, не меняет его.

## Синтаксис пина в `compat.json`

Ключ `ktalk_mcp_version` **заменяется** парой `package_name`/`package_version` — не
дополняется третьим ключом:

```json
{
  "package_name": "ktalk-cli",
  "package_version": "1.0.0"
}
```

Оба поля обязательны одновременно — отсутствие любого из двух означает `E_INTERNAL=20`, тем же
образом, каким сегодня трактуется отсутствие единственного ключа версии (не молчаливый
дефолт — «нечего сравнивать»).

## Точка правки: литералы `"ktalk-mcp"` внутри функций

Три места сегодняшнего `scripts/ktalk-onboard.sh` зашивают имя пакета **текстом внутри
функции**, не параметром — эти литералы обязаны стать `$(pin_name)` (для команды ремонта и
человекочитаемых сообщений о ПИНЕ) или значением, возвращённым `installed_identity()` (для
сообщений об УЖЕ УСТАНОВЛЕННОМ пакете):

- `remedy_cmd_text()` (`:37`) — `printf 'uv tool install ktalk-mcp==%s' "$1"` →
  имя пакета вторым параметром или через `pin_name()` внутри функции.
- `remedy_cmd_array()` (`:41`) — `REMEDY_CMD=(uv tool install "ktalk-mcp==$1")` — тот же приём.
- `installed_version()` резервный путь (`:57`) —
  `grep -E '^ktalk-mcp[[:space:]]'` → перебор конечного списка известных имён, не один литерал.
- Сообщения `cmd_check`/`cmd_install`/`finish_install` (`:137, :147, :337, :359`) —
  «Пакет ktalk-mcp … установлен/не установлен» → имя пакета подставляется, не пишется текстом.

Без этой правки плагин после релиза на `ktalk-cli` продолжит печатать и исполнять команды с
именем пакета, который выведен из обращения — регресс, который ни один существующий тест не
ловит, потому что сегодняшний `test-onboard.sh` фикстурит `compat.json` с единственным именем
и не проверяет, что текст команды ремонта СЛЕДУЕТ за именем из файла, а не за жёстким
литералом кода.

## Точка правки: формат `--version` (кросс-репо зависимость)

Детекция идентичности опирается на факт, уже верный для `ktalk-mcp` (прочитано, не изменено
этой задачей): `ktalk --version` печатает `"<имя-дистрибутива> <версия>"`, не голую версию.
Контракт для пакета `ktalk-cli` (дерево пакета, SA-002/Dev того репозитория): `--version`
обязан сохранить тот же формат — первый токен: `ktalk-cli`, второй: semver. Если это условие
не будет выполнено, детекция вырождается в резервный путь через `uv tool list` целиком —
работоспособный, но менее надёжный (наблюдение BA: `uv tool list` не отражает, кто реально
исполняется, после принудительной замены). Явно координируется с SA-002, не додумывается
здесь.

## Форма коллизии слота

Коллизия не предотвращается заранее опросом `uv tool list` (список подтверждённо ненадёжен
как источник истины после `--force` — замер BA, наблюдение 2). Вместо предварительной
проверки скрипт **пытается** обычный (без `--force`) `uv tool install` и разбирает **реальный**
отказ `uv`, если он случился — это то же самое поведение, что `uv` уже даёт бесплатно
(BA, наблюдение 1: «громкий отказ, ноль потери данных»), только атрибутированное отдельным
статусом, а не проваленное как generic `install_failed`.

Отклонено (не в ADR, деталь реализации): пред-проверка через `uv tool list` перед попыткой
install — отклонена тем же основанием, что и в ADR-024 Д4 для отката: список ненадёжен именно
в состоянии, которое эта проверка должна поймать.

## Схема отката (Brief for DevOps, детализация Д4 ADR-024)

Применяется, когда плагин откатывается на релиз, чей `compat.json` называет `ktalk-mcp`
(предыдущую идентичность), а машина оператора уже прошла переход на `ktalk-cli` — или
наоборот, когда операция `--force` применена неудачно и требуется вернуться к прежней
идентичности.

1. `uv tool install <target-package>==<target-pin> --force` — целевая идентичность
   переустанавливается явно и принудительно. Не выполнять `uv tool uninstall
   <текущий-пакет>` первым шагом — это стирает файл без отката ко второму (замер BA,
   наблюдение 3, воспроизводимый код 127).
2. Подтвердить результат живым разрешением: `command -v ktalk` резолвится, и
   `ktalk --version` называет `<target-package>` первым токеном и `<target-pin>` вторым.
   Не подтверждать через `uv tool list` — список не гарантирует отражать текущего
   исполнителя.
3. Только после подтверждённого шага 2 — `uv tool uninstall <оставленный-пакет>`, снятие
   зависшей регистрации. Раньше шага 1 не выполняется.

## Retirement `cli-only-boundary`: Requirement «Default install excludes the MCP-only dependency»

Решение SA-002 в дереве пакета — снять `fastmcp` из `dependencies` целиком (без extra, без
MCP-точки входа `server.py`, без выделенного набора MCP-тестов, 12 функций в 7 файлах) — делает
предпосылку этой Requirement (`openspec/specs/cli-only-boundary/spec.md`, capability, принятая
ADR-022) неверной не временно, а насовсем. ADR-024 Д6 фиксирует решение (retired-в-спеке,
partial supersede ADR-022); эта секция — полная карта и синхронизация companion-статьи ADR-022.

| Сценарий Requirement | Почему больше не исполним |
|---|---|
| CLI runs without the MCP-only dependency | Тривиально истинен (зависимости, которую можно исключить, больше нет вовсе) — проверять нечего, состояние «есть/нет extra» не существует |
| The MCP entry point is launched without the MCP-only dependency | Точки входа `ktalk-mcp = "ktalk_mcp.server:main"` не существует — сценарий не запускается ни на каком дереве |
| Contributor test run is unaffected | Фактически ложен: MCP-тесты не «работают как прежде» — они удалены вместе со слоем |
| Default install completes within an interactive timeout | Теряет сравнительную базу: нет более «полного набора зависимостей» с `fastmcp`, с которым сравнивался таймаут |

**Правка `openspec/specs/cli-only-boundary/spec.md`** (это дерево, выполнена этой задачей):
текст Requirement и все четыре `#### Scenario:` оставлены дословно (исторический след решения,
приём ADR-023 Д1); добавлена датированная пометка `> **Retired (2026-08-31, …)**` сразу после
вводного абзаца Requirement, и короткое примечание в `## Purpose` спеки. Две другие Requirement
capability («declares no MCP interface surface», «pins an exact package version») не тронуты
буквально ни одной строкой.

**Синхронизация companion-статьи ADR-022** (`content/40-architecture/2026-08-31-cli-only-boundary.md`,
это дерево, правка этой задачей): строка «Default install excludes MCP-only dependency — все 4
сценария» таблицы `NFR Mapping` и строка «4 сценария extra `fastmcp` (дерево пакета)» таблицы
`Contract with QA-author` → `Test-pyramid recommendation` получают приписку `retired
(package-rename-transition, ADR-024 Д6)` — без удаления самой строки, тем же приёмом.

**Что не тронуто и почему.** Требование BA `content/30-requirements/2026-08-31-cli-only-boundary.md`
и его тест-дизайн `content/30-requirements/2026-08-31-cli-only-boundary/at-design.md` уже сегодня
маркируют AC-1…AC-4 как «внешний» (тестируются в дереве пакета, не здесь) — ни одно утверждение
про ЭТО дерево там не стало ложным. Править текст требования — мандат BA, править тест-дизайн —
мандат QA-author; эта задача (SA) оставляет за собой только капабилити-спеку и её companion-пару,
не переписывает соседние роли. Синхронизация формулировки требования под факт полного удаления —
задача следующего раунда BA/QA-author, не blocking для зелёного дерева сегодня.

## Integration points

| Точка | Протокол | Контракт | Auth | Rate limit | Обработка ошибок |
|-------|----------|----------|------|------------|-------------------|
| `compat.json` → `ktalk-onboard.sh` | чтение файла, grep/sed | ключи `package_name` + `package_version`, оба обязательны | — | — | отсутствие любого ключа → `E_INTERNAL=20` |
| `ktalk-onboard.sh` → `ktalk --version` | подпроцесс, stdout | первый токен — имя дистрибутива, второй — semver (кросс-репо контракт выше) | — | — | нераспознанный формат → резервный путь через `uv tool list` |
| `ktalk-onboard.sh` → `uv tool install <pkg>==<pin>` (без `--force`) | подпроцесс, stdout/stderr захвачены | код 2 + `Executable already exists` — коллизия слота, распознаётся текстом | секреты KTalk сняты (`run_clean`, не меняется) | `KTALK_ONBOARD_RETRY_DELAY` (не меняется) | `E_SLOT_COLLISION=34`, состояние машины не меняется |
| Оператор → ручной `--force` (вне сканированного скриптом пути) | TTY, руки оператора | не вызывается скриптом ни при какой санкции | — | — | диагностируется СЛЕДУЮЩИМ запуском `check`, не самим действием |
| Пред-релизный гейт → индекс `ktalk-cli` | сетевой запрос | тот же принцип AC-9 `cli-only-boundary`, применённый к новому имени пакета | вне этой статьи | вне этой статьи | ненулевой код блокирует релиз плагина |

## NFR Mapping

| Requirement / Scenario | Как удовлетворяется |
|---|---|
| Prompt-layer text is unaffected by the rename | Дифф ограничен шестью точками (раздел «Boundaries»); проверяется диффом при релизе, не новым гейтом — тот же принцип, что уже применён `cli-only-boundary` |
| The plugin is not released ahead of ktalk-cli's first publication | Расширение пред-релизного гейта AC-9 (`cli-only-boundary` companion) на канал `ktalk-cli` — тот же механизм, другое имя пакета |
| An operator installs or already has the final ktalk-mcp version | Скрипт трактует любую `ktalk-mcp` как `wrong_package` (Д5 ADR-024); сам текст депрекации — канал пакета, вне этого дерева |
| A command-name collision is surfaced explicitly — 3 сценария | `wrong_package`/`slot_collision` статусы и коды (раздел «Data flow» п.3–6); ручной `--force` никогда не исполняется скриптом |
| Neither package is published without a prior sanction | Процедурный контроль (датированная инструкция владельца) — в этом дереве нет CI-пайплайна публикации, автоматического гейта не заводится; см. «Brief for DevOps» |

## Brief for Dev

**Architecture:** этот файл **Requirement:** `content/30-requirements/2026-08-31-package-rename-transition.md` **Phase:** Pilot

**Implement (в этом дереве, `ktalk-plugin`):**
- `compat.json`: `ktalk_mcp_version` → `package_name` + `package_version`.
- `scripts/ktalk-onboard.sh`: новая `pin_name()`; `installed_version()` → `installed_identity()`
  (оба токена `ktalk --version`, резервный путь по конечному списку имён в `uv tool list`);
  новая `identity_eq` рядом с `version_eq` (не меняется); литералы `"ktalk-mcp"` в
  `remedy_cmd_text`/`remedy_cmd_array`/резервном grep/четырёх сообщениях (список строк —
  раздел «Точка правки: литералы») параметризуются; новые коды `E_WRONG_PACKAGE=13`,
  `E_SLOT_COLLISION=34`; распознавание отказа `uv` (`Executable already exists`) в
  `run_install`/`cmd_install`; новые JSON-поля `installed_package`/`pinned_package` в
  `report`/`install_report` (аддитивно, без переименования `installed_version`/`min_version`).
- `README.md`, `references/onboarding.md`: замена литерала `ktalk-mcp` на актуальный пин по
  тому же приёму, что уже применён релизным runbook'ом `cli-only-boundary` для смены версии.
- `scripts/test-onboard.sh`: фикстуры под два поля пина, под `wrong_package`/`slot_collision`,
  под резервный путь `uv tool list` с обоими именами (`registered_both`).

**Implement (кросс-репо контракт, дерево пакета `ktalk-cli`, отдельная задача Dev того
репозитория):** `ktalk --version` печатает `"ktalk-cli <версия>"` — тот же формат, что уже у
`ktalk-mcp` (`ktalk_mcp/cli.py:381`); `__init__.py` читает `importlib.metadata.version` под
новым литералом дистрибутива, не старым (тот же класс дефекта, что уже случился один раз при
рассинхронизации `pyproject.toml`/`__version__` в 0.8.0, `ktalk_mcp/__init__.py:9`, дерево
пакета, прочитано).

**Order:** фикстуры `test-onboard.sh` под новую схему → `compat.json` → `pin_name`/
`installed_identity`/`identity_eq` → параметризация литералов → новые коды/JSON-поля →
документация (`README.md`/`references/onboarding.md`).

**Acceptance scenarios:** все 7 `#### Scenario:` `openspec/specs/package-rename-transition/spec.md`.

## Brief for DevOps

**Architecture:** этот файл

**Prepare:**
- Расширение пред-релизного гейта AC-9 (`cli-only-boundary` runbook) на канал `ktalk-cli` —
  тот же скрипт, параметризованный именем пакета, не новый скрипт.
- Раздел рансбука отката, дословно раздел «Схема отката» этой статьи — три шага в
  строгом порядке, явно с предупреждением против «удалите новый пакет».
- Публикация в PyPI (`ktalk-cli` 1.0.0, финальная версия-указатель `ktalk-mcp`) — в этом
  дереве нет CI-пайплайна публикации; санкция сегодня — процедурный контроль (датированная
  инструкция владельца), не файл и не гейт. Если публикационный CI появится (в любом из двух
  репозиториев) — он обязан читать явную санкцию тем же fail-closed приёмом, что
  `onboarding.toml` (ADR-014 §2), а не полагаться на факт мержа ветки как согласие.

**NFRs from BA:** сохранение имени команды `ktalk` (диффом, не гейтом — см. NFR Mapping);
порядок публикации пакет→плагин (расширение AC-9); явность коллизии слота (см. Data flow).

## Contract with QA-author

**Acceptance scenarios (полный список capability-спеки):**
- Scenario: Prompt-layer text is unaffected by the rename — из `### Requirement: The ktalk
  command name is preserved across the package rename`
- Scenario: The plugin is not released ahead of ktalk-cli's first publication — из
  `### Requirement: The plugin is not released ahead of the renamed package's first published
  version`
- Scenario: An operator installs or already has the final ktalk-mcp version — из
  `### Requirement: The retired ktalk-mcp package resolves to an explicit deprecation pointer`
- Scenario: Default install refuses a silent takeover — из `### Requirement: A command-name
  collision between the two package identities is surfaced explicitly`
- Scenario: An overridden takeover leaves a diagnosable trail — там же
- Scenario: Uninstalling the active package does not silently orphan the command — там же
- Scenario: A release step reaches the publish action — из `### Requirement: Neither package
  is published to PyPI without a prior, explicit owner sanction`

**Architectural context for the tests:**
- Компоненты этого дерева: `compat.json`, `scripts/ktalk-onboard.sh` (`pin_name`,
  `installed_identity`, `identity_eq`, `cmd_check`, `cmd_install`, `finish_install`).
- Компонент дерева пакета (формат `--version` пакета `ktalk-cli`, текст депрекации
  `ktalk-mcp`) — вне контракта этого QA-author, тестируется в репозитории пакета.
- Публикационная санкция (сценарий 7) — процедурный контроль без автоматизируемой
  поверхности в этом дереве; нет CI-пайплайна публикации, который можно было бы протестировать
  здесь.
- Границы доверия: `compat.json` (доверенный источник пина, часть дерева плагина) →
  `installed_identity()` (недоверенный вход — машина оператора) → сравнение → санкция →
  подпроцесс `uv`.

**Edge cases / boundary conditions:**
- Формат `--version` пакета `ktalk-cli` может не совпасть с контрактом (первый токен — имя
  дистрибутива) до тех пор, пока дерево пакета не реализует его — тест обязан проверить и
  путь «формат верный», и резервный путь «формат неожиданный → `uv tool list`», не только
  оптимистичный случай.
- `registered_both` (оба пакета видны в `uv tool list` одновременно) — диагностический
  признак, не статус отказа; тест обязан отличать «оба зарегистрированы» от «коллизия при
  install» — это разные ветки (пассивное наблюдение при `check` против активного отказа `uv`
  при `install`).
- Коллизия слота при `install`: тест стабит `uv` так, чтобы он вернул код 2 и текст
  `Executable already exists` — проверяет, что скрипт репортит `slot_collision`, а НЕ повторяет
  попытку с `--force` ни при какой комбинации `allow_install`/`allow_update`.
- Код 127 после `uninstall` владеющего пакета: тест стабит `command -v ktalk` отказом при
  живой (но неактуальной) записи в `uv tool list` — проверяет, что `check` возвращает
  `missing_cli`, а не «совместим» на основании списка.
- `hash -r` в `cmd_check`: `finish_install` уже вызывает `hash -r` после install (комментарий
  в коде называет это находкой прошлого ревью) — `cmd_check` сегодня этого не делает. Схема
  отката этой статьи явно просит оператора выполнить `check` сразу после ручного `--force` в
  той же сессии шелла — тест должен проверить, ловит ли `cmd_check` кэш bash-хэша в этом
  сценарии, эмпирически, не по памяти о поведении `command -v`.

**Test-pyramid recommendation:**

| Группа сценариев | Уровень | Обоснование |
|---|---|---|
| Prompt-layer text is unaffected by the rename | unit | статический диф по путям, без подпроцессов и без сети |
| The plugin is not released ahead of ktalk-cli's first publication | e2e/pipeline | сетевой запрос к индексу пакета — шаг релизного пайплайна, не юнит |
| An operator installs or already has the final ktalk-mcp version | вне контракта (частично) + integration | текст депрекации — тесты пакета; реакция плагина («любая ktalk-mcp = wrong_package») — стаб `ktalk`/`uv`, тем же приёмом, что `test-onboard.sh` |
| Default install refuses a silent takeover | integration | стаб `uv`, возвращающий код 2 и текст отказа — реальный подпроцесс скрипта, не мок функции |
| An overridden takeover leaves a diagnosable trail | integration | стаб `ktalk --version`/`uv tool list` под пост-force состояние |
| Uninstalling the active package does not silently orphan the command | integration | стаб `command -v ktalk` отказом при живой записи в `uv tool list` |
| A release step reaches the publish action | вне автоматизируемого контракта | процедурный контроль без CI-пайплайна публикации в этом дереве; проверяется ревью-чеклистом, не тестом |
