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

# Реализация: закрытие трёх пунктов дрейфа REV-002 (ktalk-plugin-109)

**Требование:** `content/30-requirements/2026-08-19-analysis-quality-calibration.md`, FR-42
четвёртый AC, FR-43 первый и третий AC (пометки «Дрейф (2026-08-31, статус Draft)»)
**Capability:** `openspec/specs/meeting-analysis-quality-calibration/spec.md`
**Долг:** `ktalk-plugin-109`, заведён коммитом `751cc61`

## Что было неочевидно

**Спека уже документировала дрейф — задача не в правке спеки, а в реализации промт-слоя,
которую спека называет «pending».** Коммит `751cc61` (2026-08-31, ответ координатора на
REV-002) сузил три сценария `openspec/specs/meeting-analysis-quality-calibration/spec.md` до
фактического предписания и оставил желаемое свойство в тексте требования с пометкой «desired
follow-up property... deferred rather than asserted here... pending its own prompt-layer
calibration task». Эта задача и есть «pending prompt-layer calibration task» — реализовать
свойство в промте, не трогая `spec.md` (красная линия `CLAUDE.md`). После реализации сценарии
спеки останутся сформулированными как «не предписано» до отдельной задачи SA/BA, которая
расширит их обратно под факт, — это осознанно вне рамок DEV-101.

**Ловушка frozen-области: `analysis-quality.md` — не то же самое, что `protocol-template.md`.**
Первая интуитивная локация для «единообразие маркировки» — `skills/ktalk-registry/references/
analysis-quality.md` (её называет и сама спека: «§10 of `analysis-quality.md`», и FR-42
трассировка). Но любой diff под `agents/` или `skills/ktalk-registry/` относительно
`origin/main` включает гейт `check_prompt_version_sync()` в `check-plugin-composition.sh`
(NFR-25) — требует подъёма minor-версии `plugin.json`, а `test-onboard.sh` несёт sha256-снимок
дерева, который тогда тоже разъезжается. Оба файла — не моя область этого раунда (бриф
DEV-101). Решение — свойство легло в `references/ktalk-processor/protocol-template.md`: файл
физически определяет сам маркер `[ASR?]`, поэтому правило о его единообразном применении по
документу там же уместно по смыслу, не только «в обход гейта». `analysis-quality.md` не
тронут; проверено `grep -c` по `.nauta-scripts-basis.yaml` (0 для обоих задетых файлов) и
прогоном `check-plugin-composition.sh`/`check-prompt-language.sh` до и после правки — оба OK,
`check_prompt_version_sync()` не сработал (diff не задевает `agents/`/`skills/ktalk-registry/`).

**Третий пункт живёт в `eval-rubric.md`, не в `defect-classes.md`.** `defect-classes.md` —
append-only каталог УЖЕ НАЙДЕННЫХ дефектов (id/название/пример), не место для правила «что
дефектом не является». Свойство «рост счётчика сам по себе не дефект» — метод верификации,
поэтому легло строкой в таблицу `## Verification method: reading the protocol vs an A/B run`,
рядом с уже существующими строками про регресс confidence и устойчивость починки — тем же
методом (A/B-сравнение двух прогонов), которого симметрично не хватало именно этому пункту
(дословно по REV-002: «таблица A/B... покрывает регресс confidence и устойчивость починки, но
не рост счётчиков»).

## Что вписано, куда и почему проверяемо

| # | Свойство (REV-002) | Файл | Носитель проверки |
|---|---|---|---|
| 1 | Единообразие маркировки одного имени по документу | `references/ktalk-processor/protocol-template.md`, абзац «Document-wide consistency of one name's marking» | `scripts/test-quality-calibration-drift.sh` AC1-1..AC1-3 |
| 2 | Явная констатация при `decisions_count` 0 | `references/ktalk-processor/protocol-template.md`, абзац «Zero decisions» | там же, AC2-1..AC2-3 |
| 3 | Рост счётчиков между ревизиями сам по себе не дефект | `skills/ktalk-eval/references/eval-rubric.md`, новая строка таблицы `Verification method` | там же, AC3-1..AC3-3 |

Правило 1 не отменяет «решается независимо на каждом вхождении» (§10 `analysis-quality.md`,
формулировку спеки) — оно добавляет второй слой: независимое РЕЗОЛВИНГ-решение того же имени
должно давать тот же исход при повторном вхождении (кэш §1a), а расхождение исходов требует
явно названной причины в тексте протокола. Это то самое сужение, которое коммит `751cc61`
внёс в сценарий «A repeated name's marking is decided per occurrence» — теперь оно
реализовано, а не только упомянуто как желаемое.

## Носитель проверки — отдельная сьюта, не расширение `test-agreements-reconciliation.sh`

`scripts/test-quality-calibration-drift.sh` — новый файл, жанр тот же («проверка предписаний
промт-слоя грепом по смыслу»), но предмет `test-agreements-reconciliation.sh` — шаг 5.5
`agents/ktalk-processor.md` и `vault-update-and-report.md` (жёстко зашитые пути `PROCESSOR`/
`VAULT_REF` в шапке файла), не пересекается с тремя файлами этой задачи. Смешение раздуло бы
чужой файл предметом вне его заявленной области.

Каждый из 9 ассертов проверен мутацией: `git stash` откатывал оба задетых файла к состоянию
`origin/main`, прогон давал `PASS=0 FAIL=9` (все девять красные по своей фразе, не по чужой),
`git stash pop` возвращал правку — `PASS=9 FAIL=0`. Каждая проверяемая фраза лежит целиком на
одной строке файла (не составной ERE-паттерн через перенос markdown) — та же предосторожность
против случайного зелёного, что после урока 2026-08-29.

Сьюта НЕ зарегистрирована в `.nauta-gates.yaml` / `projectGates` (файл вне моей области) и не
вызывается из `check.sh` (доставлен и заморожен nauta) — прогон только прямой:
`bash scripts/test-quality-calibration-drift.sh`.

## Что не сделано и почему

- **`openspec/specs/meeting-analysis-quality-calibration/spec.md` не тронут** — красная линия
  `CLAUDE.md` («SA-артефакт»); три сценария остаются сформулированными как «not prescribed by
  the prompt layer» до отдельной задачи, которая сверит их с этой правкой и расширит формулировку
  обратно под факт (тот самый порядок, который спека сама называет: «pending its own
  prompt-layer calibration task» → калибровка сделана этой задачей → следующий шаг за SA/BA).
- **`skills/ktalk-registry/references/analysis-quality.md` не тронут** — см. «Ловушка
  frozen-области» выше; правка там потребовала бы подъёма minor-версии `plugin.json` и
  перебазировки sha256 в `test-onboard.sh`, оба вне области этого брифа. Если координатор
  сочтёт, что свойство лучше жить именно в `analysis-quality.md` — нужна отдельная задача с
  явным правом на оба файла.
- **`skills/ktalk-registry/references/analysis-quality.md` и `defect-classes.md` не расширены**
  — оба рассмотрены как кандидаты и отклонены по существу (см. выше), не по недосмотру.

## Проверка

`bash scripts/check.sh --fast` — единственный красный узел `check-hooks-path.sh`
(`core.hooksPath` переставлен на путь основного дерева, не `.githooks` этого worktree) —
воспроизведён идентично на базовом коммите `4725295` ДО правки (`git stash` + прогон),
окружение worktree, не регрессия этой задачи.
`bash scripts/check-plugin-composition.sh` — OK. `bash scripts/check-prompt-language.sh` — OK.
`bash scripts/test-agreements-reconciliation.sh` — PASS=25 FAIL=0 (регрессии нет).
`bash scripts/test-release-delivery-tails.sh` — PASS=54 FAIL=0 SKIP=3 (чужая сьюта, регрессии
нет — прогнана для очистки совести, поскольку тоже цитирует оба задетых файла).
`bash scripts/test-quality-calibration-drift.sh` — PASS=9 FAIL=0, мутационно подтверждено.
