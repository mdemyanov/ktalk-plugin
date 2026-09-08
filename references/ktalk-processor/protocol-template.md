# Meeting protocol template

A reference file of `ktalk-processor.md` (core step 5). `{id}` in profile links is
substituted from `registry.directories.people` returned by `ktalk config show --json`
(core step 0b); if the key is not declared, the participant is named as plain text, with no
wiki-link to a profile directory.

The template below is the artefact written into the host's vault. Its Russian headings, table
headers and placeholders are reproduced verbatim — translating or rewording any of them
changes every protocol the plugin writes (ADR-021 D1, FR-3 class 2).

```markdown
---
type: meeting
subtype: {meeting_type}
recording_id: "{recording_id}"
title: "{recording_name}"
date: {date}
duration_min: {длительность в минутах}
participants:
  - "[[{directories.people}/{id}/{id}|Имя Фамилия]]"
source: ktalk
transcript: "[[{путь по registry.routing.transcript_archive}]]"
decisions_count: {N}
commitments_count: {N}
unclear_count: {N}
---

# {recording_name} — {date}

## Участники
{список участников с ссылками на профили (если каталог профилей объявлен)}

## Ключевые решения
| # | Решение | Кто принял | Таймкод | Confidence |
|---|---------|-----------|---------|-----------|

## Договорённости
| Кто | Что | Срок | Confidence | Таймкод |
|-----|-----|------|-----------|---------|

## Обновления статуса
(только если есть)
| Что | Новый статус | Предыдущий | Источник |
|-----|-------------|-----------|---------|

## Открытые вопросы
- [UNCLEAR] {описание} (⏱ {HH:MM:SS})

## Флаги для владельца проекта
(только если применимо — см. `two-pass-analysis.md`, пункт E)

## Заметки
> Обновлено на основе встречи "{название}" ({date})
> Транскрипт: [[{путь по registry.routing.transcript_archive}]]

## Ключевые тезисы
(только для `meeting_type: session`; отсутствует у прочих типов встречи — не
пустая секция с заглушкой, а полностью опущена)
- {тезис} (⏱ {HH:MM:SS})
```

**Uncertain-name marker:** `[ASR?]`, placed immediately after the name with no space before
the bracket — for example, `Дмитрий Иванов[ASR?]`. It means the name did not resolve
unambiguously through the profile directory (a participant or a third party). It is neither
the same as nor a replacement for `[UNCLEAR]` (open questions of the meeting, a separate
section and a separate `unclear_count` counter) — two different meanings, two different
tokens. `[ASR?]` does not count towards `unclear_count`.

**Document-wide consistency of one name's marking:** `analysis-quality.md` §1a resolves (or
marks `[ASR?]`) a given name once per processing run and caches the outcome; every further
occurrence of that same name in the finished protocol carries the identical outcome — the
cached result written again, not a fresh independent decision made anew at the point of
writing. Two occurrences of one name disagreeing (one carries `[ASR?]`, the other does not) is
a defect unless the protocol text states an explicit reason at the differing occurrence (for
example, the transcript itself renders the name distorted at one mention and clean at another,
so the two mentions are not the same input). Marking one occurrence and leaving another
unmarked with no such stated reason is silent inconsistency, not an independent per-occurrence
decision.

**Zero decisions:** when `decisions_count` is `0`, the `Ключевые решения` table carries no
rows, and the protocol text placed directly under the table states plainly that no decisions
were found — a short Russian sentence such as `Решений в этой встрече не зафиксировано.` The
table SHALL NOT be left as bare headers with nothing said below them, and a conditional wording
(`может быть`, `если получится`) SHALL NOT be written into the table or the text as if it were
a decision.

Section order in the protocol: `Участники`, `Ключевые решения`, `Договорённости`,
`Обновления статуса`, `Открытые вопросы`, `Флаги для владельца проекта`, `Заметки`,
**`Ключевые тезисы`** (only for `meeting_type: session`; absent for every other meeting type —
not an empty section with a placeholder, but omitted entirely). The first seven sections are
fixed and their order never changes; the eighth is an optional addition for `session` only.
