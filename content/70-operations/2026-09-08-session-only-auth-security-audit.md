---
properties:
  - name: Тип контента
    value: [Прочее]
  - name: Фаза
    value: [Pilot]
  - name: Статус
    value: [Draft]
  - name: Audience
    value: [Internal]
---

# Аудит безопасности: поверхность токена после единственного режима авторизации (SEC-001)

**Capability:** `openspec/specs/session-only-auth/spec.md`
**ADR:** `content/00-project/adr/ADR-028-session-only-authorisation.md`
**Соседний DEV-отчёт:** `content/60-implementation/2026-09-08-session-only-auth.md`,
`content/60-implementation/2026-09-08-personal-api-key-literal-guard.md`

## Вердикт

**НЕ БЛОКИРУЕТ** релиз `1.15.0`. Ни секрета, ни персональных данных, ни утечки значения в
дифф не попало — все находки ниже про целостность автоматических гейтов и точность
машинного контракта, не про факт утечки. Рекомендую закрыть Находку 2 (тест-сьюта эпика не
подключена к GO-гейту) до релиза или сразу следующим раундом — она снижает ценность «зелёного»
`check.sh --full` именно для той поверхности, которую переписал этот эпик. Находки 1 и 3 — в
бэклог, не блокеры.

## Scope

Предмет — дифф эпика `ktalk-plugin-6sm` относительно `main`, не всё дерево:

```
git diff --stat main...HEAD    # 23 файла, +1647/-34
git log --oneline main..HEAD   # 13 коммитов, RES-001 → BA-001 → SA-001 → QA-001 → DEV-001 → DEV-002
```

Коммит на момент аудита — `053eeb0` (`sec-001`, слияние DEV-002). Ревью — пять пунктов задания:
секрет в дереве, корректность инструкции о хранении, живая проверка непечати значения, сторож
DEV-002 как средство защиты, сравнение старой/новой редакции Requirement онбординга.

## Находка 1 (Medium) — сторож `check_no_retired_auth_literal` обходится симлинком внутри периметра

`scripts/check-plugin-composition.sh:189-224` вводит блокирующую проверку на литерал
`KTALK_PERSONAL_API_KEY` в периметре README.md/references/skills/agents/commands, реализованную
как `grep -rnF "$pattern" --exclude-dir=.git "${paths[@]}"`. BSD grep (macOS, версия из
`/usr/bin/grep`, `2.6.0-FreeBSD` — та же, что реально исполняет скрипт: `bash -c 'type grep'`
даёт `/usr/bin/grep`) при рекурсивном обходе (`-r`) **не разыменовывает симлинки**, найденные
внутри просматриваемого каталога — только те, что переданы в аргументах явно.

Воспроизведено экспериментально (дерево возвращено чистым после проверки, `git status --short`
— пусто):
```
ln -s /tmp/outside.txt references/symlink_probe   # /tmp/outside.txt содержит литерал
bash -c 'paths=(README.md references skills agents commands); \
  grep -rnF "KTALK_PERSONAL_API_KEY" --exclude-dir=.git "${paths[@]}"'
# → 0 совпадений, symlink_probe не просканирован
grep -rnF "KTALK_PERSONAL_API_KEY" references/symlink_probe   # путь передан явно — находит
grep -RnF "KTALK_PERSONAL_API_KEY" --exclude-dir=.git references  # -R (dereference) — находит
```
Для контроля проверены три соседних класса — все три пойманы штатно (гейт полноценен ВНЕ
класса симлинков): вложенный подкаталог (`references/deep/nested/note.md`), файл без
расширения (`references/noext_probe`) — оба found; `.gitignore` тут не участвует, git сам
трекает симлинк как blob режима `120000`, то есть путь коммитится и уходит в payload плагина
как обычный файл дерева.

Эксплуатируемость — не «случайная», нужен намеренный коммит симлинка внутрь периметра; но это
ровно тот класс, для защиты от которого сторож и заведён (ADR-028 Д5 — не дать `README.md`/
`references/`/`skills/`/`agents/`/`commands/` назвать отставной режим поддерживаемым), и
регрессия таким путём не даст `check.sh --full`/`--fast` покраснеть.

**Замечание.** Находка не про факт наличия симлинка в дереве сегодня — их там нет
(`find README.md references skills agents commands -type l` → пусто, проверено).

## Находка 2 (Medium) — тест-сьюта QA-001 не подключена к GO-гейту `check.sh --full`

`scripts/test-session-only-auth.sh` — единственная сьюта, проверяющая именно ту поверхность,
которую переписал этот эпик (11 Requirement / 37 ассертов capability `session-only-auth`, плюс
GUARD-1..6 на сам сторож Находки 1). Она НЕ зарегистрирована в `.nauta-gates.yaml`:

```
grep -n "test-session-only-auth" .nauta-gates.yaml   # 0 совпадений
```
`projectGates.full` сегодня несёт только `test-onboard.sh`, `test-release-delivery-tails.sh`,
`test-dual-channel-delivery.sh` — все три о доставке/онбординге пакета, не о содержимом
авторизационной инструкции. Живой прогон `bash scripts/check.sh --full` (эта задача, коммит
`053eeb0`) даёт `✓ check.sh --full — passed`, но список запущенных гейтов (`grep -nE "^▶ "`
по логу прогона) не включает `test-session-only-auth.sh` — «зелёный `--full`» и «эпик
верифицирован» сегодня не одно и то же для этой поверхности.

DEV-001 прогнал сьюту вручную и зафиксировал результат в
`content/60-implementation/2026-09-08-session-only-auth.md` (`PASS=29 FAIL=1 SKIP=1`, FAIL —
известный дефект самого стаба AC10-2, не предмета) — но это ручное доказательство раунда, не
постоянная защита от будущей регрессии. Следующая правка `README.md`/`references/onboarding.md`
может тихо вернуть, например, условную оговорку-резерв файла относительно переменной (AC3-3)
или снять указатель на команды записей (AC8) — `check.sh --full` останется зелёным.

**Не то же самое, что Находка 1.** `check_no_retired_auth_literal` (сторож DEV-002) проверяет
только голый литерал и ЗАРЕГИСТРИРОВАН (`projectGates.fast`) — он продолжит защищать именно
свой узкий периметр. Находка 2 — про остальные 10 Requirement capability, у которых защиты в
GO-гейте нет вовсе.

## Находка 3 (Low, для бэклога) — openspec-контракт потерял явный запрет места хранения, не восстановив его в новом владельце

Сравнение `git diff main...HEAD -- openspec/specs/plugin-onboarding-sanctioned-install/spec.md`:
старый Requirement «The authorisation instruction never carries a secret value» называл места
размещения значения буквально — `«a process environment variable, or the host project's
configuration — never a file inside the plugin tree»`. Новая редакция делегирует вопрос «где
может храниться значение» capability `session-only-auth` целиком и убирает эту фразу из своего
текста, не восстанавливая её нигде. Проверено: ни один Requirement/Scenario
`openspec/specs/session-only-auth/spec.md` не содержит запрета «не файл внутри дерева плагина»
— там названы только два ЛЕГИТИМНЫХ носителя (файл токена и переменная), без встречного запрета
на третий (файл внутри дерева плагина).

Эффект **не тождественен ослаблению де-факто**: сам текст промт-слоя не пострадал —
`references/onboarding.md:145-147` дословно несёт то же ограничение, что и раньше («the value
never lives in a file inside the plugin tree, and never in `.ktalk.toml`»), и это ограничение
никогда не проверялось Scenario/тестом ни до, ни после правки (`grep -rn "inside the plugin
tree|internal a plugin tree"` по истории `test-onboard.sh` до этого эпика — 0 совпадений).
То есть машинно проверяемый контракт не потерял покрытие, которого не было — но потерял место,
где это ограничение вообще СФОРМУЛИРОВАНО как Requirement, а не только как проза одного файла.
Кто-то, читающий только `openspec/specs/`, не найдёт этого ограничения нигде.

**Рекомендация (бэклог, не блокер):** добавить в `session-only-auth` явный Requirement/Scenario
вида «SHALL NOT name a location inside the plugin tree as a place to hold the value» — тогда
существующая проза `onboarding.md` получит спека-якорь и тестируемость, которых у неё сегодня
нет ни в старой, ни в новой редакции.

## Секреты

- Диффу эпика (`git log -p main..HEAD`, все 13 коммитов) — реальных значений токена/ключа не
  найдено. Единственные литералы, похожие на секрет по regex `(SECRET|API_KEY|PASSWORD|TOKEN|
  PRIVATE_KEY|AWS_)` — имена переменных окружения (`KTALK_SESSION_TOKEN`,
  `KTALK_PERSONAL_API_KEY`, `KTALK_TOKEN_FILE`) и путь `~/.config/ktalk-mcp/token`; ни одного
  фактического значения.
- Фикстуры новых тестов синтетические и промаркированы как таковые:
  `scripts/test-session-only-auth.sh:314` — `FIXTURE_TOKEN='SYNTH"TOKEN with spaces and
  $(danger)'` (намеренно с кавычкой/пробелом/командной подстановкой — проверка на инъекцию и
  утечку через `check`/`check --json`, не реальный формат токена); `scripts/test-onboard.sh:227`
  — `FIXTURE_TOKEN="SYNTHETIC-ONBOARD-TOKEN-0000000000"`, был и раньше, не тронут этим диффом.
- `.gitignore` не менялся этим диффом; `.env*`/`*.pem`/`*.key`/`credentials*` в дереве
  корректно нет — плагин не хранит секретов в своём дереве (тот же вывод, что в
  `2026-09-04-dual-channel-delivery-security-audit.md`, раздел «Секреты»).
- Секрет-стор: `~/.config/ktalk-mcp/token`, вне дерева плагина, права `0600`
  (README.md:131, `references/onboarding.md:144`) — верно, владелец-only. Ротация — по факту
  протухания сессии, гид называет единственный путь исправления (`ktalk token set -`), без
  предложения альтернативы личным ключом (README.md:132-135; проверено stub AC5-1/AC5-2).

## Живая проверка непечати значения (пункт 3 задания)

```
FIXTURE_TOKEN='<синтетическая строка-маркер SEC-001, не формат реального токена>'
KTALK_SESSION_TOKEN="$FIXTURE_TOKEN" bash scripts/ktalk-onboard.sh check
# → "Пакет ktalk-cli 2.1.0 установлен, версия совместима." (rc=0, значение НЕ в выводе)
KTALK_SESSION_TOKEN="$FIXTURE_TOKEN" bash scripts/ktalk-onboard.sh check --json
# → {"status":"ok","installed_version":"2.1.0",...} (rc=0, значение НЕ в JSON)
```
`ktalk-onboard.sh check` сегодня вообще не отчитывается о состоянии токена (только о версии
пакета) — значение физически негде утечь на этой команде; ту же живую проверку с спецсимволами
оболочки в значении уже несёт стаб AC11-1a/AC11-1b (`scripts/test-session-only-auth.sh:314-325`)
— повторный прогон этой задачей подтверждает тот же результат независимо.

## Supply-chain

- Пакетного менеджера/лок-файлов в дереве плагина по-прежнему нет и не должно быть (ADR-012,
  тот же вывод, что в предыдущем аудите) — этот эпик ничего здесь не меняет.
- Единственная внешняя зависимость — `ktalk-cli`, пин не сдвинут этим эпиком (`2.1.0`,
  `compat.json` не в диффе); README получил раздел «Что нового в пине `ktalk-cli` 2.1.0»
  (код возврата `3` у `get-transcript --json` при несовпадении `identity_check`) — точность
  этого раздела подтверждена stub AC10-1 (раздел существует) и вручную AC10-2 (стаб структурно
  недоказуем из-за бага в самом тесте — читает путь к файлу, а не содержимое; находка уже
  зафиксирована DEV-001, не эта роль её чинит).
- SAST-инструменты (`semgrep`/`bandit`) в этом окружении недоступны, как и в прошлый раз —
  компенсирующая мера: ручной обзор изменённых `.sh`-скриптов
  (`check-plugin-composition.sh`, `test-session-only-auth.sh`, `test-onboard.sh`,
  `ktalk-onboard.sh`) на инъекционные паттерны — `eval`/`system` с внешним недоверенным вводом
  не найдены; единственный `eval` в проекте (`check.sh`) не в диффе этого эпика.
- Находки 1 и 2 — тот же класс ответственности, что и Находки 2/3/5 прошлого аудита:
  структурный дефект гарантии «то, что задекларировано защищённым, действительно защищено
  автоматически», не CVE в зависимости.

## Классы, не покрытые полностью

Все пять пунктов задания закрыты. Частичное покрытие — SAST (см. «Supply-chain»):
`semgrep`/`bandit` недоступны в окружении, компенсировано ручным обзором с названными
паттернами.

## Проверка

`bash scripts/check.sh --full` (коммит `053eeb0`) — зелёный:
```
✓ check-hooks-path.sh
✓ check-branch-discipline.py
✓ secret-scan-tree
✓ validate-content.py
✓ validate-profile.py
✓ check-content-actuality.py
✓ id-check.sh
✓ test-check-id.sh
✓ test-validate-content.sh
✓ scripts/test-onboard.sh
✓ scripts/test-release-delivery-tails.sh
✓ scripts/test-dual-channel-delivery.sh
✓ scripts/check-plugin-composition.sh
✓ scripts/check-prompt-language.sh
✓ scripts/check-mcp-channel-language.sh
✓ scripts/test-quality-calibration-drift.sh
✓ check.sh --full — passed
```
Список гейтов, реально исполненных этим прогоном, НЕ включает `scripts/test-session-only-auth.sh`
— см. Находку 2. `bash scripts/test-session-only-auth.sh` (отдельно, этой же задачей) —
`PASS=37 FAIL=0 SKIP=1` (SKIP — AC11-2, легитимный by design: `ktalk-onboard.sh check` сегодня
не отчитывается о состоянии токена вовсе, предмет недоказуем на этом уровне до появления такой
логики).

Эксперимент по Находке 1 выполнен на реальном дереве и полностью откачен —
`git status --short` после эксперимента пуст (проверено дважды: сразу после отката и перед
записью этого отчёта).
