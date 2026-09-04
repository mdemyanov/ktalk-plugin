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

# Двухканальная поставка: публичное GitHub-зеркало payload

**ADR:** `content/00-project/adr/ADR-027-github-mirror-channel.md`
**Requirement:** `content/30-requirements/2026-09-04-dual-channel-delivery.md`
**Capability:** `openspec/specs/dual-channel-delivery/spec.md`

## Context

ADR-027 решает шесть вопросов второго канала поставки. Эта статья — реализационная деталь:
точный манифест payload, точки правки по файлам, брифы Dev/DevOps, контракт QA-author.

## Components

| Компонент | Ответственность | Входы | Выходы | Зависимости |
|-----------|------------------|-------|--------|-------------|
| `.gitlab/payload-manifest.txt` (новый) | Единственный список путей, считающихся публичным payload | санкция оператора + Д5 (`.github/`) | список строк, по одному пути на строку | читается Д2-джобом и Д4-проверкой |
| `.gitlab-ci.yml` (новый) | Джоб `mirror-github`: сборка, правка `name`, push | тег `ktalk--v*`, манифест | коммит+тег на `github.com/mdemyanov/ktalk-plugin` | GitLab CI runner, protected CI/CD переменная с токеном GitHub |
| `.claude-plugin/marketplace.json` (правка в скопированном дереве, не в источнике) | Различимость маркетплейса на зеркале | исходный файл + Д2 шаг 2 | `name: "ktalk-plugins-mirror"` вместо `"ktalk-plugins"` | `jq`/эквивалент внутри джоба |
| `README.md` (правка) | Установочная документация обоих каналов | Д3 | два подраздела с разными командами | — |
| `.github/CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/*.md`, `.github/PULL_REQUEST_TEMPLATE.md` (новые) | Подтверждение источника истины на входе | Д5 | текст, видимый до отправки issue/PR | нативный механизм GitHub |
| `scripts/check-plugin-composition.sh` (правка: новая функция) | Scoped-проверка домена по манифесту, не по всему дереву | манифест, паттерн домена | `FAIL`/тишина | манифест payload |

## Boundaries

- Мирроринг не делает ничего, кроме копирования уже готового релизного дерева и правки одного
  JSON-поля — не пересобирает, не тестирует, не публикует отдельно от релизного тега GitLab.
- Приём issue/PR на GitHub не автоматизирует перенос и не закрывает обращения сам — только
  показывает текст; перенос во внутренний бэклог делает человек.
- Scoped-проверка домена (Д4) не заменяет и не трогает существующую проверку первого
  внутреннего домена продукта (строка 65) — та выходит за рамки этого решения.
- Три команды паритета (Д6) не автоматизированы CI-джобом в этом раунде — исполняются DevOps
  вручную после публикации; заведение их как отдельного CI-шага не предмет этого решения (нет
  измеренной частоты релизов, оправдывающей стоимость нового джоба, чем и грозит красная линия
  ADR-027 против придуманных чисел).

## Data flow

Релиз → `claude plugin tag` (ADR-025 Д1) создаёт тег `ktalk--vX.Y.Z` на GitLab → тег запускает
`mirror-github` → джоб читает `.gitlab/payload-manifest.txt`, копирует перечисленные пути тега
во временное дерево, патчит `.claude-plugin/marketplace.json.name`, коммитит, пушит тот же тег
на `github.com/mdemyanov/ktalk-plugin` → DevOps проверяет резолвимость обоих ref'ов и прогоняет
три команды Д6 → расхождение — дефект зеркалирования, разбирается вручную, повторный `Retry`
джоба.

## Payload-манифест (`.gitlab/payload-manifest.txt`)

```
.claude-plugin/
agents/
commands/
skills/
references/
scripts/
README.md
LICENSE
.github/
```

Ровно операторская санкция (`.claude-plugin/`…`scripts/`, README, LICENSE) плюс `.github/`,
добавленный Д5 этим решением. Файл не публикуется (вне списка) — читается только внутри
исходного дерева самим джобом и самим гейтом.

## Integration points

| Точка | Протокол | Контракт | Auth | Rate limit | Обработка ошибок |
|-------|----------|----------|------|------------|-------------------|
| GitLab CI → GitHub | `git push` по HTTPS | тег `ktalk--vX.Y.Z` + payload-дерево по манифесту | protected/masked CI/CD переменная (GitHub-токен, только защищённые теги) | не задействован (один push на релиз) | ненулевой код джоба, пайплайн красный, релиз GitLab не откатывается, повтор — ручной `Retry` |
| GitHub issue/PR → человек | форма GitHub (issue/PR template) | текст-баннер источника истины, показан до отправки | — | — | без ответа формы обращение всё равно создаётся — баннер не блокирует отправку, только информирует |
| `check-plugin-composition.sh` → манифест | чтение файла со списком путей | один путь на строку, без `..`, без абсолютных | — | — | манифест не найден/пуст — гейт логирует предупреждение и не пропускает проверку молча (эквивалент поведения существующих `check()` при недоступном источнике) |

## NFR Mapping — соответствие Д ↔ Scenario

| Requirement / Scenario (`openspec/specs/dual-channel-delivery/spec.md`) | Д | Как удовлетворяется |
|---|---|---|
| The two channels declare distinguishable marketplace identities — Scenario: A consumer adds both channels' marketplaces | Д1 | `name: "ktalk-plugins-mirror"` на зеркале, правится механически при зеркалировании |
| Cross-channel parity is a checkable fact, not a claim — Scenario: Comparing a mirrored release against its source | Д6 | guard резолвимости ref'ов + три буквальные команды `diff`/`git ls-tree`, DevOps-рансбук |
| Documentation names each channel and how to tell them apart — Scenario: An operator reads the installation instructions | Д3 | README, два подраздела с разными командами и статусом (источник истины/зеркало) |
| A consumer can tell "mirror lags" from "version does not exist" — Scenario: A version was released internally but not yet mirrored | Д2 | тег на GitHub создаётся только при успешном push — список тегов зеркала структурно не опережает реально смирроренное |
| The public payload carries no internal infrastructure literal — Scenario: The composition gate scans for the internal domain | Д4 | scoped-проверка по payload-манифесту, не по всему дереву |
| Input arriving through the public channel is triaged manually — Scenario: An issue is opened on the public mirror | Д5 | `.github/CONTRIBUTING.md` + шаблоны issue/PR, без автоматизации переноса/закрытия |

## Brief for Dev

**Architecture:** этот файл **Requirement:**
`content/30-requirements/2026-09-04-dual-channel-delivery.md` **Phase:** Pilot

**Implement:**
- `LICENSE` (MIT) — в дереве отсутствует (`ls LICENSE` → нет), санкция оператора требует его
  в payload; завести текстом MIT, автор `mdemyanov`.
- `.gitlab/payload-manifest.txt` — список путей, ровно как в разделе «Payload-манифест» выше.
- `.gitlab-ci.yml` — джоб `mirror-github`: `rules: if $CI_COMMIT_TAG =~ /^ktalk--v/`, стадии —
  сборка дерева по манифесту → `jq '.name = "ktalk-plugins-mirror"'` над скопированным
  `.claude-plugin/marketplace.json` → `git push` тега и дерева на `github.com/mdemyanov/
  ktalk-plugin` токеном из protected/masked переменной `GITHUB_MIRROR_TOKEN`.
- `README.md`, раздел «2. Поставьте плагин»: два подраздела («Внутренний GitLab — источник
  истины» / «Публичное GitHub-зеркало»), каждый — своя команда `/plugin marketplace add` и имя
  маркетплейса (`ktalk-plugins` / `ktalk-plugins-mirror`); строка 26 (сегодняшний литерал
  домена) заменяется плейсхолдером со ссылкой на `CLAUDE.md`, «Справочные пути».
- `.github/CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/` (минимум один шаблон), `.github/
  PULL_REQUEST_TEMPLATE.md` — текст источника истины и ручного переноса (Д5); формулировка
  своя, не копия внутреннего `CONTRIBUTING.md` (тот не публикуется).
- `scripts/check-plugin-composition.sh`: новая функция `check_payload_domain` — грепает
  паттерн `doc-hub\.gitlab\.yandexcloud\.net` только по путям из `.gitlab/payload-manifest.txt`
  (не по `.`), исключая сам скрипт тем же приёмом, что строка 40. Существующую проверку
  первого внутреннего домена продукта (строка 65) не трогать — вне предмета.

**Order:** `LICENSE` → `.gitlab/payload-manifest.txt` → `check_payload_domain` (проверяемо
независимо от CI) → `README.md`/`.github/*` (текстовые правки) → `.gitlab-ci.yml` (зависит от
манифеста и от уже поправленного README/`.github/`) → `bash scripts/check.sh --fast`.

**Acceptance scenarios:** `A consumer adds both channels' marketplaces`; `Comparing a mirrored
release against its source`; `An operator reads the installation instructions`; `A version was
released internally but not yet mirrored`; `The composition gate scans for the internal
domain`; `An issue is opened on the public mirror` — все шесть, `openspec/specs/dual-channel-
delivery/spec.md`.

## Brief for DevOps

**Architecture:** этот файл

**Prepare:**
- CI/CD переменная `GITHUB_MIRROR_TOKEN` — protected (только защищённые теги), masked; область
  токена на стороне GitHub — запись в один репозиторий `mdemyanov/ktalk-plugin`, не шире.
- Рансбук релиза: после `claude plugin tag` и обычного релизного процесса — дождаться
  `mirror-github` в пайплайне; при красном джобе — не трогать релиз GitLab, разобрать причину,
  `Retry` вручную.
- Рансбук паритета (после каждого успешного зеркалирования) — guard резолвимости обоих ref'ов,
  затем три команды Д6 ADR-027, буквально (раздел «Decision, Д6» ADR-027); guard не пройден —
  тег не резолвится, сверка не проводилась, это не паритет; guard пройден и непустой вывод
  любой из трёх команд — дефект зеркалирования, не публикуется как «версия для другой
  аудитории».
- Мониторинг: новый сигнал — статус джоба `mirror-github` в пайплайне GitLab (нативный UI, без
  нового канала алертинга); нет нового сетевого сервиса, кроме исходящего `git push` на GitHub.

**NFRs from BA:** различимость имён маркетплейсов (Д1); отсутствие обратной автосинхронизации
issue/PR (Д5); паритет версии/`compat.json`/состава как проверяемый факт (Д6); отсутствие
внутреннего домена в публичном payload (Д4).

## Contract with QA-author

**Acceptance scenarios (полный список из capability spec):**
- Scenario: A consumer adds both channels' marketplaces — из `### Requirement: The two channels
  declare distinguishable marketplace identities`
- Scenario: Comparing a mirrored release against its source — из `### Requirement: Cross-channel
  parity is a checkable fact, not a claim`
- Scenario: An operator reads the installation instructions — из `### Requirement: Documentation
  names each channel and how to tell them apart`
- Scenario: A version was released internally but not yet mirrored — из `### Requirement: A
  consumer can tell "mirror lags" from "version does not exist"`
- Scenario: The composition gate scans for the internal domain — из `### Requirement: The public
  payload carries no internal infrastructure literal`
- Scenario: An issue is opened on the public mirror — из `### Requirement: Input arriving
  through the public channel is triaged manually`

**Architectural context for the tests:**
- Компоненты: `.gitlab/payload-manifest.txt` (статический список), `.gitlab-ci.yml` (джоб,
  исполняется платформой GitLab CI — сеть и внешний сервис), `.claude-plugin/marketplace.json`
  (два состояния: исходное и пропатченное), `README.md` (текст), `.github/*` (текст, нативно
  читается GitHub), `scripts/check-plugin-composition.sh` (новая функция).
- Интеграции: GitLab CI runner → GitHub (push по сети, реальный внешний сервис — единственная
  сетевая интеграция во всём решении); `claude plugin tag`/`validate` — не предмет этого
  решения (ADR-025).
- Границы доверия: манифест — вход джоба и гейта, доверенный (в дереве источника, не
  пользовательский ввод); GitHub issue/PR — вход снаружи проекта, не доверенный по содержимому,
  но не исполняется автоматически ни в каком виде (Д5) — снимает класс рисков «код из
  недоверенного PR запускается CI», потому что такого запуска нет вовсе.

**Edge cases / boundary conditions:**
- Push на GitHub падает после того, как тег уже создан на GitLab, но до того, как он появился
  на зеркале — окно, в котором зеркало и GitLab расходятся легитимно (не дефект, а Д2 «на
  ретрае»); тест обязан отличать это временное окно от постоянного расхождения (Scenario
  «версия выпущена, но не смирролена» — это и есть штатное состояние окна, не баг).
- Проверка домена (Д4) обязана падать на файле ВНУТРИ манифеста, но не падать на точно том же
  литерале в файле ВНЕ манифеста (`content/`, ADR, требования) — тест на оба направления,
  иначе scoped-проверка неотличима от старой whole-tree по факту прохождения теста.
- Манифест и `.gitlab-ci.yml` сами не входят в payload — тест обязан подтвердить их отсутствие
  на зазеркаленном дереве (иначе аудит структуры внутреннего CI утекает наружу неявно).
- `marketplace.json` на зеркале обязан отличаться ТОЛЬКО полем `name` — тест на остальное
  содержимое (например, `plugins[0]`) должно быть идентично исходному, не «файл другой».
- Шаблон issue/PR показывает баннер до отправки, а не после — тест не должен подтверждать
  свойство созданием issue и проверкой бот-комментария (в этом решении бота нет); проверяется
  наличие и текст самого файла шаблона.

**Test-pyramid recommendation:**

| Группа сценариев | Уровень | Обоснование |
|---|---|---|
| A consumer adds both channels' marketplaces | unit | сравнение строки `name` двух файлов `marketplace.json` (исходного и пропатченной копии-фикстуры) |
| Comparing a mirrored release against its source | integration | реальные `git show`/`git ls-tree` над двумя тестовыми remote (или их фикстурами), не мок |
| An operator reads the installation instructions | unit | статическое чтение README на наличие обоих подразделов, обеих команд, слов «источник истины»/«зеркало» |
| A version was released internally but not yet mirrored | integration | фикстура двух git-remote с разным набором тегов, проверка сравнения «последний тег зеркала» |
| The composition gate scans for the internal domain | unit + unit | (а) файл в манифесте с литералом домена → `FAIL`; (б) тот же литерал в файле вне манифеста (`content/`-фикстура) → без `FAIL` от этой проверки |
| An issue is opened on the public mirror | unit | статическая проверка наличия и текста `.github/CONTRIBUTING.md`/шаблонов — не e2e через реальный GitHub API |
