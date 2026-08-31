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

# CLI-граница плагина: снятие MCP-поверхности и пин версии пакета

**ADR:** `content/00-project/adr/ADR-022-cli-only-boundary.md`
**Requirement:** `content/30-requirements/2026-08-31-cli-only-boundary.md`
**Capability:** `openspec/specs/cli-only-boundary/spec.md`

## Context

ADR-022 решает три архитектурных вопроса границы CLI/MCP и модель санкций онбординга. Эта
статья — реализационная деталь: где именно живёт пин, как переставить порядок
инициализации `scripts/ktalk-onboard.sh`, какую форму принимает пред-релизное условие, и
контракт для Dev, DevOps и QA-author. Требование BA-001 явно выносит синтаксис extra
`fastmcp` в `pyproject.toml` пакета `ktalk-mcp` за пределы этого дерева — своя SA-статья в
репозитории пакета; здесь эта часть только упомянута в NFR-mapping как выполняемая там.

## Components

| Компонент | Ответственность | Входы | Выходы | Зависимости |
|-----------|------------------|-------|--------|-------------|
| `compat.json` | Единственный источник контракта совместимой версии | правка Dev/DevOps при релизе плагина | ключ `ktalk_mcp_version` — ровно один semver, пин | читается `pin_version()` |
| `scripts/ktalk-onboard.sh`: `pin_version()` (переименование `min_version()`) | Читает пин из `compat.json` | `compat.json` | строка версии либо отказ | grep/sed, без JSON-парсера — не меняется |
| `scripts/ktalk-onboard.sh`: `remedy_cmd_text()` / `remedy_cmd_array()` (новые) | Строит команду ремонта, встраивающую пин | пин, известный только после `pin_version()` | `uv tool install ktalk-mcp==<pin>` — текст и массив | вызывается после чтения пина, не до |
| `scripts/ktalk-onboard.sh`: `cmd_check`/`finish_install` | Сравнивают установленную версию с пином на точное равенство | `installed_version()`, пин | коды 0/10/11/12/20 | новая `version_eq`, не `version_ge` |
| `scripts/ktalk-onboard.sh`: `cmd_install` | Устанавливает/чинит версию по санкции | `allow_install`/`allow_update`, пин | коды 0/30/31/32 | один и тот же `remedy_cmd_*` для установки и для ремонта |
| `.mcp.json` (удаляется) | — | — | — | — |
| Пред-релизный гейт (имя предлагается Dev/DevOps, не создаётся этой статьёй) | Проверяет, что пин опубликован в канале распространения пакета, до тега релиза плагина | `compat.json`, индекс пакета | блокирующий код возврата в релизном пайплайне | сетевой запрос — вне `check-plugin-composition.sh` |

## Boundaries

- Этот дизайн не проверяет цепочку поставки пакета по хэшам — риск принят BA-001, вне
  области.
- `scripts/ktalk-onboard.sh` не запускает `uv tool install`/ремонт без предъявленной сейчас
  санкции ни в одной ветке — ADR-022 Д3 не вводит путь в обход этого.
- Пред-релизный гейт не бежит на каждый коммит — только в момент публикации плагина;
  сетевая зависимость не встраивается в локальный pre-commit `check-plugin-composition.sh`.
- Синтаксис extra `fastmcp` в `pyproject.toml` пакета `ktalk-mcp` не проектируется здесь —
  собственный SA-процесс репозитория пакета.
- **Два из трёх ретируемых MCP-имён (обе команды предпросмотра встреч) — литералы,
  запрещённые в дереве плагина** проверкой `check-plugin-composition.sh` («MCP-имя операции
  встреч вместо CLI»). Таблица наименований ниже называет их по роли, не по идентификатору, —
  это осознанное ограничение формы, а не пропуск: писать запрещённый литерал даже в
  объяснительных целях внутри дерева плагина нельзя.

## Data flow

1. Оператор/CI читают `compat.json` → `pin_version()` возвращает пин или отказывает
   (`E_INTERNAL=20`, «переустановите плагин» — не меняется).
2. `installed_version()` определяет фактическую версию (`ktalk --version`, fallback —
   `uv tool list`) — не меняется.
3. Сравнение — **точное равенство** (`version_eq`, не `version_ge` из сегодняшнего кода) →
   `ok` при совпадении, `outdated` при любом расхождении, в обе стороны.
4. Расхождение и `ktalk` не найден вовсе → нужна `allow_install` (код `30`, если санкции
   нет). Расхождение и `ktalk` найден с другой версией → нужна `allow_update` (код `32`,
   если санкции нет). Разделение веток — не меняется, меняется только предикат «другая
   версия».
5. Санкция есть → `remedy_cmd_array(pin)` → `uv tool install ktalk-mcp==<pin>` через
   `run_clean` (секреты KTalk сняты, NFR-19 — не меняется), с тем же ретраем на сетевую
   ошибку (`KTALK_ONBOARD_RETRY_DELAY` — не меняется).
6. `finish_install` перечитывает версию **тем же предикатом равенства**: успех (код `0`)
   требует `installed == pin` ровно, не `installed >= pin`.

## Точка правки: порядок инициализации `scripts/ktalk-onboard.sh`

`scripts/ktalk-onboard.sh:10-13` объявляет `INSTALL_CMD`/`INSTALL_CMD_TEXT`/`UPDATE_CMD`/
`UPDATE_CMD_TEXT` константами верхнего уровня — до определения `min_version()` (строка 20) и
до первого места, где версия вообще становится известна (внутри `cmd_check`, строка 78).
Команда, встраивающая пин текстом, не может быть константой, вычисленной раньше, чем
прочитан файл, откуда этот пин берётся.

**Способ:** убрать все четыре константы. Ввести `remedy_cmd_text(<pin>)` и
`remedy_cmd_array(<pin>)` как функции, вызываемые **после** успешного `pin_version()` — то
есть там, где сегодня используется `$INSTALL_CMD_TEXT`/`$UPDATE_CMD_TEXT`/`${INSTALL_CMD[@]}`/
`${UPDATE_CMD[@]}`: `cmd_check` (строки 84, 87, 93–94), `cmd_install` (293, 297, 303, 309,
315, 322–324, 328–330), `finish_install` (271, 278–279, 282). Install и update используют
**одну и ту же** функцию ремонта — Д2 ADR-022 не разводит их по тексту команды, только по
санкции, которая проверяется перед вызовом.

Дизайн не разрешает, соответствует ли равенство точной строке пина также при наличии
pre-release/build-метаданных (`0.10.0` против `0.10.0+local`) — сегодняшняя `version_ge`
отрезает `-`/`+`-суффикс перед сравнением; `version_eq` может унаследовать ту же
нормализацию для минимального риска, либо получить собственное правило. Требование не
специфицирует это поведение — решение остаётся за Dev, не додумывается здесь.

## Синтаксис пина в `compat.json`

Ключ **заменяется**, не дополняется: `ktalk_mcp_min_version` → `ktalk_mcp_version`.
Сосуществование двух ключей («пол» и «пин») создало бы вопрос, какой из них авторитетен —
ровно то расхождение, которое пин обязан устранить. Единственное значение — semver без
диапазона:

```json
{
  "ktalk_mcp_version": "0.10.0"
}
```

Статус-строка JSON-вывода (`"status":"outdated"`) не переименовывается под «версия новее» —
минимальное изменение поверхности, которую уже читает `test-onboard.sh` и любой внешний
потребитель `--json`. Слово перестаёт быть буквально точным для случая «новее», но остаётся
единственным статусом «версия не та, нужен ремонт» — сознательный компромисс в пользу
меньшего количества мест для расхождения, а не путаница в терминологии.

## Форма пред-релизного условия

Сценарий «The plugin is not released ahead of its pinned package version» требует сетевой
проверки канала распространения пакета — свойство, которого нет ни у одной сегодняшней
проверки `check-plugin-composition.sh` (все статические, без сети). Дизайн: отдельный шаг
релизного пайплайна (не pre-commit, не `check-plugin-composition.sh`), запускаемый на тег
релиза плагина, не на каждый коммит:

1. Читает пин из `compat.json` рабочего дерева тега.
2. Опрашивает канал распространения пакета `ktalk-mcp` на наличие ровно этой версии.
3. Ненулевой код возврата останавливает публикацию плагина до того, как релиз дойдёт до
   оператора — тот же принцип, что `check-plugin-composition.sh` уже применяет к составу
   дерева (GO-критерий, ненулевой код = провал сборки), только на другом шаге пайплайна.

Имя скрипта и точный механизм опроса канала — бриф DevOps ниже; эта статья фиксирует
контракт (когда бежит, что проверяет, чем блокирует), не код.

## Наименование: retired MCP → CLI

Три инструмента, чьё CLI-имя отличается от MCP-имени (сверка BA-001: 15 MCP-инструментов,
17 CLI-подкоманд без MCP-эквивалента). Оператор, который раньше вызывал retired-инструмент
напрямую, находит здесь путь на CLI:

| Retired MCP-инструмент | CLI-эквивалент |
|---|---|
| предпросмотр создания встречи | `ktalk create-meeting-preview` |
| предпросмотр отмены встречи | `ktalk cancel-meeting-preview` |
| `ktalk_get_summary_by_type` | `ktalk get-summary-type` |

Первые две строки названы по роли, не по идентификатору инструмента: их буквальные
retired-имена — среди литералов, которые `check-plugin-composition.sh` запрещает во всём
дереве плагина, включая `content/` (см. «Boundaries»). Таблица для оператора (README или
`references/onboarding.md` — решает Dev)
обязана нести тот же контракт под тем же ограничением формы, а не восстанавливать
буквальные имена.

## Удаление `.mcp.json`

Файл удаляется целиком, а не опустошается до `{"mcpServers": {}}` — отсутствие файла
тривиально проверяемо («нет декларации сервера»), тогда как пустой объект требует парсинга
JSON, чтобы отличить «нет сервера» от «есть, но с другим именем ключа».

**Пробел в текущем гейте, найденный этим дизайном:** `check-plugin-composition.sh` сегодня
ищет только литералы MCP-имён операций встреч в тексте промт-слоя — он не проверяет
содержимое `.mcp.json` вообще. После этого изменения нужна отдельная статическая проверка:
файл `.mcp.json` либо отсутствует, либо не содержит ключ `ktalk` внутри `mcpServers`. Без
неё регресс («кто-то вернул декларацию сервера») не поймает ни один существующий гейт.

## Integration points

| Точка | Протокол | Контракт | Auth | Rate limit | Обработка ошибок |
|-------|----------|----------|------|------------|-------------------|
| `compat.json` → `ktalk-onboard.sh` | чтение файла, grep/sed | ключ `ktalk_mcp_version`, ровно одно значение semver | — | — | отсутствие/битый файл → `E_INTERNAL=20` |
| `ktalk-onboard.sh` → `uv tool install ktalk-mcp==<pin>` | подпроцесс, stdout/stderr захвачены | код возврата + текст; сетевая ошибка — 1 ретрай (не меняется) | секреты KTalk сняты (`run_clean`, NFR-19) | `KTALK_ONBOARD_RETRY_DELAY` (не меняется) | `E_INSTALL_FAILED=31`, состояние машины не меняется |
| Пред-релизный гейт → канал распространения пакета | сетевой запрос к индексу пакета | пин обязан существовать и быть устанавливаемым до тега релиза плагина | вне этой статьи (см. DevOps) | вне этой статьи | ненулевой код блокирует релизный пайплайн |
| Оператор → `grant install`/`grant update` | TTY-only bash | тот же файл-санкция `onboarding.toml`, fail-closed чтение (ADR-014 §2, не меняется) | — | — | без TTY — `E_NO_TTY=33` |

## NFR Mapping

| Requirement / Scenario | Как удовлетворяется |
|---|---|
| Default install excludes MCP-only dependency — все 4 сценария | Реализация в `pyproject.toml` пакета `ktalk-mcp`; вне этого дерева (собственный SA-процесс пакета). **Retired** (2026-08-31, `package-rename-transition`, ADR-024 Д6) — пакет снимает зависимость целиком, не extra'ом; см. `content/40-architecture/2026-08-31-package-rename-transition.md`, раздел «Retirement `cli-only-boundary`» |
| No MCP server is declared | Удаление `.mcp.json` (раздел «Удаление `.mcp.json`»); новая статическая проверка в `check-plugin-composition.sh` (пробел, названный выше) |
| An operator who previously called an MCP tool directly | Таблица «Retired MCP → CLI» выше, размещаемая в пользовательской документации Dev'ом |
| Installed version differs from the pin | `version_eq` вместо `version_ge` в `cmd_check`/`finish_install` (раздел «Data flow» п.3, 6) |
| The remedy command names the exact version | `remedy_cmd_text(pin)`/`remedy_cmd_array(pin)`, вызываемые после чтения пина (раздел «Точка правки») |
| The plugin is not released ahead of its pinned package version | Пред-релизный гейт релизного пайплайна (раздел «Форма пред-релизного условия») |

## Brief for Dev

**Architecture:** этот файл **Requirement:** `content/30-requirements/2026-08-31-cli-only-boundary.md` **Phase:** Pilot

**Implement (в этом дереве, `ktalk-plugin`):**
- `compat.json`: ключ `ktalk_mcp_version` вместо `ktalk_mcp_min_version`.
- `scripts/ktalk-onboard.sh`: `min_version()`→`pin_version()` (новый ключ); удалить
  константы строк 10–13; ввести `remedy_cmd_text`/`remedy_cmd_array`, вызываемые после
  `pin_version()`, во всех местах использования старых констант (список строк — раздел
  «Точка правки»); `version_ge`→`version_eq` в `cmd_check` и `finish_install`; текст
  сообщений «ниже минимально совместимой» → «не совпадает с требуемой версией».
- Удалить `.mcp.json`.
- Добавить в `check-plugin-composition.sh` проверку отсутствия декларации `ktalk` в
  `mcpServers` (или отсутствия файла) — пробел, названный в разделе «Удаление `.mcp.json`».
- Разместить таблицу «Retired MCP → CLI» в README или `references/onboarding.md`, соблюдая
  ограничение формы (роль вместо запрещённого литерала для двух из трёх строк).

**Implement (в дереве пакета `ktalk-mcp`, отдельная задача Dev того репозитория):** extra
`fastmcp` в `pyproject.toml`, dev-группа сохраняет `fastmcp`.

**Order:** фикстуры `test-onboard.sh` под новую семантику (equal, не ge; обе стороны
расхождения) → `compat.json` → функции `ktalk-onboard.sh` → `.mcp.json` → новая проверка
композиции → документация.

**Acceptance scenarios:** все 9 `#### Scenario:` `openspec/specs/cli-only-boundary/spec.md`
(4 — в дереве пакета, 5 — в этом дереве: см. NFR Mapping).

## Brief for DevOps

**Architecture:** этот файл

**Prepare:**
- Шаг релизного пайплайна «пин опубликован» (раздел «Форма пред-релизного условия»):
  сетевая проверка канала распространения пакета на тег релиза плагина, блокирующий код
  возврата до того, как релиз дойдёт до оператора.
- Runbook отката: как поступить оператору, у которого установлена версия `ktalk-mcp` новее
  пина ради не связанной с плагином задачи (ADR-022 Д3, «Negative») — что именно теряется
  откатом, куда обращаться, если откат нежелателен.

**NFRs from BA:** NFR из требования BA-001 — время холодной установки (замер BA:
23,1 с/152,8 с, таймаут 120 с), NFR-19 (секреты не попадают в вывод менеджера пакетов, не
меняется этим решением).

## Contract with QA-author

**Acceptance scenarios (полный список capability-спеки):**
- Scenario: CLI runs without the MCP-only dependency — из `### Requirement: Default
  ktalk-mcp install excludes the MCP-only dependency`
- Scenario: The MCP entry point is launched without the MCP-only dependency — там же
- Scenario: Contributor test run is unaffected — там же
- Scenario: Default install completes within an interactive timeout — там же
- Scenario: No MCP server is declared — из `### Requirement: The plugin declares no MCP
  interface surface`
- Scenario: An operator who previously called an MCP tool directly — там же
- Scenario: Installed version differs from the pin — из `### Requirement: The compatibility
  check pins an exact package version`
- Scenario: The remedy command names the exact version — там же
- Scenario: The plugin is not released ahead of its pinned package version — там же

**Architectural context for the tests:**
- Компоненты этого дерева: `compat.json`, `scripts/ktalk-onboard.sh` (`pin_version`,
  `remedy_cmd_text`/`remedy_cmd_array`, `cmd_check`, `cmd_install`, `finish_install`),
  `.mcp.json` (удаляется), новая проверка `check-plugin-composition.sh`.
- Компоненты дерева пакета (первые 4 сценария) — вне контракта этого QA-author, тестируются
  в репозитории `ktalk-mcp`.
- Границы доверия: оператор → `grant`/`revoke` (TTY-only) → файл-санкция → `install`/`check`
  (без TTY) → подпроцесс `uv`.

**Edge cases / boundary conditions:**
- `version_eq` и pre-release/build-метаданные (`0.10.0` vs `0.10.0+local`) — правило не
  специфицировано требованием, дизайн явно оставляет это Dev; QA-author фиксирует, какое
  поведение реализовано, тестом, а не додумывает норму сам.
- Новая ветка санкции: установленная версия **новее** пина, `allow_update` не выдана — до
  этого изменения такого состояния не существовало (при пороге «новее» всегда было `ok`).
  `test-onboard.sh` сегодня проверяет только «старше» (тесты 3, 3a, 17, 22) — нужен парный
  тест для «новее».
- Постусловие `finish_install` под равенством: успех `uv tool install ktalk-mcp==<pin>`,
  но индекс отдал не тот пин (тест 27/28/29 сегодняшнего `test-onboard.sh` написан для
  «ниже минимума» — переносится на «не равно пину» дословно тем же приёмом).
- Регресс `.mcp.json`: файл вернулся или получил `ktalk` в `mcpServers` — тест на новую
  проверку композиции, мутационный (испортить `.mcp.json`, убедиться, что гейт падает).
- Таблица «Retired MCP → CLI» в пользовательской документации: тест на присутствие и на то,
  что она не вводит запрещённый литерал заново (мутационный: временно вставить запрещённый
  литерал, убедиться, что `check-plugin-composition.sh` его ловит).

**Test-pyramid recommendation:**

| Группа сценариев | Уровень | Обоснование |
|---|---|---|
| 4 сценария extra `fastmcp` (дерево пакета) | вне контракта | тестируются QA пакета `ktalk-mcp`, не этого дерева. **Retired** (2026-08-31, ADR-024 Д6) — предмет снят пакетом целиком, сценарии не будут исполнены ни на каком дереве |
| No MCP server is declared | unit | статическая проверка файла/грепа, без сети и без подпроцессов |
| An operator who previously called an MCP tool directly | unit + e2e | таблица и её защита от запрещённого литерала — unit; фактическое отсутствие `mcp__ktalk__*` в списке инструментов операторской сессии — платформенное поведение, не автоматизируется в этом репозитории, e2e/ручная проверка |
| Installed version differs from the pin / remedy command names the exact version | integration | тот же приём `test-onboard.sh` — стаб `ktalk`/`uv`, реальный подпроцесс скрипта, не мок функции |
| The plugin is not released ahead of its pinned package version | e2e/pipeline | обращение к живому или замоканному индексу пакета вне обычной сьюты — шаг релизного пайплайна, не юнит-тест |
