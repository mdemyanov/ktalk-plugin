# Transcript analysis quality instructions

Used by the `ktalk-processor` agent when processing each meeting. The paths and directories
referred to below as `{directories.people}` / `{directories.projects_active}` and the like come
from `ktalk config show --json` (step 0b of the `ktalk-processor.md` core) — none are
hard-coded here.

Russian literals in this file are transcript cues, protocol section names and verbatim
examples of output; they are reproduced as they are, never translated (ADR-021).

---

## 1. Context-first (mandatory before the analysis)

Load the context **before** reading the transcript, using whichever dependency is available
(`qmd` or `{directories.people}` — independently of each other, FR-24 degradation):

- The profiles of ALL participants (role, current goals, open agreements)
- The cards of the relevant projects (status, risks, open decisions)
- For 1-1: the last 2–3 meeting records with this person
- Related architectural decisions (ADRs) on the meeting's topic, if `qmd` is available

Profile lookup (if `{directories.people}` is declared):

1. `Grep: pattern="ktalk_id: \"{N}\"", path={directories.people}` → an exact frontmatter match
2. If not found → `Grep: pattern="name: \".*{Фамилия}\"", path={directories.people}, output_mode="content"`
3. If no profile is found at all — mark it `unknown_person` and do not try to guess

If `{directories.people}` is not declared and `qmd` is unavailable, the step is marked
unavailable in full (see `ktalk-processor.md`, step 0c). Degradation does not mean silently
skipping the marking: if resolution is physically impossible (not one dependency available),
every name in the transcript — a participant's or a third party's — that raises doubt when
matched against the meeting context already known (a distortion, a homonym, a form not seen in
`additional_context` or the summary) is marked `[ASR?]` (`protocol-template.md`) in the
finished protocol. "Nothing to resolve with" is no reason not to mark; it is a reason to mark
more widely: without a directory there is nothing to tell a distorted name from an exact one,
so every name without external confirmation counts as doubtful (FR-42 AC3).

Profile lookup through the directory applies not only to the meeting's participants but also
to third parties mentioned in speech, if the name occurs in text already assigned to the
`Договорённости`, `Ключевые решения` or `Обновления статуса` sections (not in passing speech
outside those categories). The batch-lookup mechanics are in §1a below.

---

## 1a. Batch resolution of third parties

The list of unique third-party names is assembled after the structured extraction (pass 1,
`two-pass-analysis.md`, sections A–E) — not while reading the transcript. The Grep runs in a
batch over the assembled list, not once per mention. A name already resolved or already marked
`[ASR?]` within the current run is not looked up again — the result is cached for the whole
run.

**Normative (FR-42, the whole section):** a name that resolved unambiguously through the
profile directory is written in its corrected form, with no marker. A name that did not
resolve (the directory is available but found no match, OR the directory and `qmd` are
unavailable altogether — the two cases are equivalent as far as the final marking goes) is
marked `[ASR?]` always, at every point of use in the finished text; silently skipping the
marking for an unresolved name is the defect this rule closes (see also §10 below on the
historical source of the defect — marking used to be prescribed for participants only).

---

## 2. Role weighting of utterances

Not everything said carries equal weight — take the speaker's role from their profile into
account (if the profile is available):

| Speaker | Wording | Interpretation |
|---------|---------|----------------|
| A decision-making manager | `нам нужно X`, `сделай X` | A directive / hard commitment → record in the agreements |
| Another manager | `мы сделаем X`, `берём X` | A team commitment → open agreements |
| An IC / implementer | `можно было бы X`, `предлагаю X` | A proposal → **not** a commitment |
| All participants | `решили X`, `договорились X` | A collective decision → a candidate architectural decision (ADR) |

---

## 3. Two-pass analysis

The two-pass algorithm and the structured-extraction checklist are normative in
`agents/references/two-pass-analysis.md` (sections A–E). They are not duplicated here.

---

## 4. Temporal markers

```
Прошедшее время ("сделали", "завершили", "закрыли")
  → найти существующую задачу/договорённость → обновить статус → готово

Будущее время ("сделаем", "возьму", "к пятнице")
  → создать новую запись в открытых договорённостях профиля

Условное ("если...", "возможно...", "может быть...", "планируем")
  → пометить [UNCLEAR] → не записывать как commitment → флагировать
```

The rule that confidence is calibrated by the fact of agreement, not by the mood of the
request — see Examples 3a/3b in the appendix.

---

## 5. Type-specific analysis focus

### 1-1 (type: 1-1)

- **Main thing:** personal agreements, the person's blockers, development areas, motivation
- **Update:** the open agreements and the 1-1 history in the profile (if
  `{directories.people}` is declared)
- **Flag:** a change of motivation or mood, risks concerning the person, burnout signals
- **Do not:** create an architectural decision out of a personal conversation

### Project status / sync (type: status, other)

- **Main thing:** milestone updates, deadline changes, new risks, blockers
- **Update:** the project card — status, current tasks, risks (if
  `{directories.projects_active}` is declared)
- **Flag:** deadline shifts, escalations, team changes

### Committee / architecture board (type: committee)

- **Main thing:** collective decisions, resource questions, strategic forks
- **Update:** the meeting protocol at `routing.committee` (if declared)
- **Flag:** ADR candidates, budget decisions, org-design changes

### Standup (type: standup)

- **Main thing:** escalations, cross-team dependencies, recurring blockers
- **Update:** task statuses, open questions in the projects
- **Flag:** systemic problems, delays affecting adjacent teams

### Strategy session (type: session)

- **Main thing:** priority changes, new directions, directions being closed
- **Update:** nothing without explicit confirmation (the changes may be drafts)
- **Flag:** ADR candidates, org-structure changes, new projects

---

## 6. Safeguards against hallucination

```
НЕ ДЕЛАТЬ:
  - Додумывать детали которые не прозвучали
  - Интерпретировать молчание как согласие
  - Угадывать сроки если не названы явно
  - Приписывать ответственность без явного "берёт" / "отвечает"
  - Создавать записи с LOW confidence

ДЕЛАТЬ:
  - Ссылаться на таймстамп для каждого извлечённого факта
  - Предпочесть пропустить, чем изобрести
  - При конфликте между участниками — флагировать оба мнения
  - Помечать неясные моменты как [UNCLEAR: <описание>]
```

**Specifically for core step 4.5 (`ktalk-processor.md`):** the ban on
`Интерпретировать молчание как согласие` above covers not only the original extraction
(step 4) but also the reconciliation of the draft against the tables at step 4.5. A draft
wording such as `X не возразил` or `Y промолчал, значит согласен` does not by itself justify a
row in `Ключевые решения` or `Договорённости` — that is the same case of silence taken for
agreement, merely found at the reconciliation step rather than the extraction step. A
candidate with no articulated acceptance (not `угу`, not a change of subject, not the absence
of an objection) goes to `Открытые вопросы` with the reason stated — Example 3c below.

The confidence scale:

- **HIGH** — said explicitly, a verbatim quotation or a paraphrase
- **MEDIUM** — unambiguously inferred from the context of the conversation
- **LOW** — a guess → do not record, flag it

---

## 7. Deduplication before writing

Before creating any new record (if the dependency is available):

```
Grep(pattern="ktalk_id: \"{id}\"", path={directories.people})     # найти профиль
mcp__qmd__vector_search(query="{тема задачи} {имя ответственного}")  # проверить дубли, если qmd доступен

Если найдено совпадение:
  → обновить существующую запись
  → НЕ создавать новую
  → указать источник изменения: "Обновлено на основе встречи {название} {date}"
```

---

## 8. Flags for the project owner

If the host project's owner takes part in the meeting (the identifier is passed by the
orchestrator, where applicable) — additionally scan for:

| Pattern | Action |
|---------|--------|
| A choice of technology, tool or architectural approach | Propose creating an ADR |
| Personnel decisions (hiring, transfer, dismissal, structure) | Update the profiles plus the org structure |
| Regulatory, compliance or information-security topics | Flag for the host's separate review, if one exists |
| Resource decisions (budget, hiring, contracts) | Record as a decision with an explicit source |
| A change of product or platform priorities | Check against the host's priorities, if a priorities directory is declared |
| A new project or initiative | Propose creating a project card (if `{directories.projects_active}` is declared) |

---

## 9. Sources of changes

State the source with every update:

```markdown
> Обновлено на основе встречи "{{название}}" ({{date}})
> Транскрипт: [[{путь по routing.transcript_archive}]]
```

This makes it possible to trace where any change came from.

---

## 10. Correcting names from the transcript

Speech recognition systematically distorts some surnames — not only those of the meeting's
participants but also of third parties mentioned in speech (§1a). Before writing, check
against the correction table maintained by the host project (if there is one — the host passes
the path separately; this skill does not hold it). If a surname (of a participant or of a
third party) raises doubt, check it against the profile through whichever dependency is
available (`qmd` or `{directories.people}`), including the batch resolution of third parties
(§1a).

Resolved unambiguously → write it in its corrected form, with no marker, and do not keep the
distorted form from the transcript. Not resolved (no match in the directory, the directory is
not declared, or both dependencies of step 0c are unavailable) → write it with the `[ASR?]`
marker (`protocol-template.md`) — do not skip it silently and do not leave the distorted form
unmarked. This rule is the normative source for §1 and §1a: the marking applies to every name
that raises doubt, not only to the meeting's participants (FR-42, the whole section).

---

## 11. Correcting terms and abbreviations from the transcript

Speech recognition distorts technical terms, and speakers use abbreviations without expanding
them. At an abbreviation's first mention in the protocol, give the expansion if it is known
from the meeting's context or from a participant's profile. The host project may maintain its
own term/abbreviation table — this skill does not hold one itself.

---

## Appendix: examples of good and bad analysis

The examples below are built on anonymised fragments of real 1-1 meetings — names and details
are changed, the structure of the reasoning and the typical errors are preserved. They are
used to calibrate the agent. Both the transcript fragments and the resulting tables are
verbatim Russian: the meeting is held in Russian and the protocol is written in Russian.

---

### Example 1: decision extraction

**Transcript fragment:**

```
> Участник А [00:10:47]: Да нет, да нет. Смотри, мы давай так. В итоге договорились с Б вчера, что параллельно мы запустим 2 вещи. 1-е — мы настроим какой-то базовый процесс на скриптах, команда В/Г. И, да, какой-то процесс на скриптах запрограммируем и сделаем то же самое примерно на альтернативном движке. Оба сценария дадим Д. Вот, есть вариант A и вариант B, бери сценарий, нагрузочное тестирование и гоняй A и B.
>
> Участник А [00:11:25]: Не, не, погоди. Я примерно хочу понять. Просто, опять же, смотри. Если окажется, что они соизмеримы, ну там 5-10 процентов, сделаем. Если окажется, что на скриптах в единицу времени при нагрузке проходит там 1000 запросов, а на альтернативном движке 10, то, как бы, что мы будем делать?
```

#### GOOD

```
| # | Решение | Confidence | Таймстамп |
|---|---------|-----------|-----------|
| 3 | Запустить нагрузочное тестирование параллельно — скрипты (В/Г) vs альтернативный движок, отдать Д | HIGH | 00:10:47 |

Открытый вопрос:
- Каковы реальные цифры производительности под нагрузкой vs скрипты? [UNCLEAR: срок тестирования не назван]
```

**Why this is good:**

- Precise attribution: who proposed it, and with whom it was agreed
- The concrete implementers are named
- The success criterion is extracted from the conversation: a 5–10% difference — carry on; a
  multiple-fold gap — reconsider
- The timestamp is tied to the key utterance where the decision itself is voiced
- The deadline was not stated — honestly marked `[UNCLEAR]`, not invented

#### BAD

```
| # | Решение | Confidence | Таймстамп |
|---|---------|-----------|-----------|
| 3 | Решили провести нагрузочное тестирование альтернативного движка | HIGH | 00:10:00 |
```

**Why this is bad:**

- The substance of the decision is lost: two scenarios were to be tested in parallel, not one
- No implementers — the concrete names are lost
- No success criterion — without it the decision is useless
- The timestamp is imprecise — it cannot be verified
- It is not marked that the deadline was not stated — creating a false impression of
  completeness

---

### Example 2: a commitment vs a suggestion

**Transcript fragment:**

```
> Участник Б [00:18:09]: Мне кажется, что вообще нужно проект захерить. Я думаю, он больше. Никакого в нём смысла больше просто нет. Либо трансформировать.
>
> Участник А [00:18:12]: Не что нет? Ну, нам делать. Вот, ключевое вот. Или не делай, да?
>
> Участник А [00:22:31]: Да. Ну, нормально. Я думаю, так надо потихонечку будет делать. Хорошо, что ты поддерживаешь. Я обсужу это с коллегой.
```

#### GOOD

```
Ключевое решение:

| Решение | Таймкод | Confidence |
|---------|---------|------------|
| Участник А обсудит с коллегой передачу проекта | 00:22:31 | HIGH |
| Проект нужно трансформировать: не закрыть, но перезапустить под другим углом | 00:18:09–00:22:13 | MEDIUM |

Договорённость:

| Кто | Что | Срок | Источник |
|-----|-----|------|----------|
| Участник А | Обсудить с коллегой передачу проекта | — | 00:22:31 |
```

**Why this is good:**

- The proposal by `Б` (`нужно проект захерить`) is correctly separated from the decision
- `А` said `я обсужу` — that is a directive, recorded as the commitment of `А`
- Transforming the project is MEDIUM, because the concrete form was not confirmed
- The deadline was not stated — a dash stands there, not an invented date
- `Б` is NOT recorded as the implementer — they proposed the idea; `А` took the action

#### BAD

```
Ключевое решение:

| Решение | Таймкод | Confidence |
|---------|---------|------------|
| Решили закрыть проект и передать другому | 00:18:09 | HIGH |
```

**Why this is bad:**

- `Решили закрыть проект` is a factual error: `Б` proposed
  `захерить либо трансформировать`, and `А` did not agree to close it
- An IC's proposal is recorded as a commitment
- A task is attributed where there is neither authority nor a promise
- A deadline is invented that was not in the transcript
- Confidence HIGH for an unconfirmed decision — MEDIUM at most

---

### Example 3a [GOOD]: a conditional request with explicit acceptance → HIGH

**Transcript fragment (a status meeting):**

```
> Запрос [00:46:54]: А ты можешь вот это вот, может быть, следующий понедельник здесь рассказать?
>
> Акцепт [00:47:09]: Хорошо. […] Договорились.

Договорённости:

| Кто | Что | Срок | Confidence |
|-----|-----|------|-----------|
| Участник, к которому обращён запрос | Рассказать интерфейсный трек | следующий понедельник | HIGH |
```

**Why this is good:**

- The mood of the request is conditional (`может быть`) — it does not affect the outcome
- The acceptance is explicit (`Договорились`) — hence HIGH, not MEDIUM

### Example 3b [GOOD]: a conditional request with a one-word reaction → MEDIUM

**Transcript fragment (a session):**

```
> Запрос [00:57:40]: Если вдруг ты найдёшь способ… может быть, даже просто по КЦП… Подумаю дополнительно
>
> Акцепт [00:57:51]: Покопать.

Договорённости:

| Кто | Что | Срок | Confidence |
|-----|-----|------|-----------|
| Участник, к которому обращён запрос | Покопать по КЦП | не задан | MEDIUM |
```

**Why this is good:**

- The mood of the request is conditional — as in Example 3a, that alone does not lower the
  confidence
- What tells the pairs apart is not the mood of the request (conditional in both) but the
  force of the acceptance: a one-word reaction with no act of agreement → MEDIUM, not HIGH

### Example 3c [BAD → the fix]: silence taken for agreement (a research session)

**Transcript fragment:**

```
> Предложение [00:29:50–00:31:34]: Участник Б излагает собственную гипотезу о способе
> измерения объёма техдолга.
>
> Реакция [00:31:xx]: Участник А (руководитель): «Такого не было». «Угу».
```

#### BAD (found by a run)

```
Ключевые решения:

| Решение | Обоснование | Confidence |
|---------|-------------|-----------|
| Принята гипотеза Б об измерении объёма техдолга | Предложил Б, А не возразил | MEDIUM |
```

**Why this is bad:**

- `Не возразил` is not an acceptance but the fact of no reaction; `Угу` confirms attention,
  not agreement with the specific proposal
- The row's justification names the mechanism of the error in the protocol's own text — that
  does not lift the §6 `НЕ ДЕЛАТЬ` violation, it records it
- It was found at the step-4.5 reconciliation, not at the step-4 extraction — the rule applies
  at both steps

#### GOOD (the fix)

No row is created in `Ключевые решения`. Instead:

```
Открытые вопросы:
- Гипотеза Б об измерении объёма техдолга — предложена, явного акцепта А не прозвучало
  (00:29:50–00:31:34)
```

**Why this is good:**

- The proposal is recorded as a fact of the conversation, not as a decision
- The reason there is no table row is named explicitly, not passed over in silence
