# Two-pass transcript analysis — the detailed algorithm

A reference file of `ktalk-processor.md` (core steps 3.5 and 4). The paths and directories
this file refers to come from `ktalk config show --json` (core step 0b) — none are hard-coded
here.

The `confidence` scale and the safeguards against hallucination are normative in
`skills/ktalk-registry/references/analysis-quality.md` §6. They are not duplicated here.

Russian literals below are of two kinds, and neither is translated: cues to look for in the
transcript (the meeting is held in Russian, so the cue must be Russian to match), and section
names written into the protocol (ADR-021 D1).

## Format of the saved transcript file

```markdown
---
type: transcript
source: ktalk
recording_id: "{recording_id}"
title: "{recording_name}"
date: {date}
participants:
  - Имя Фамилия (ktalk:{id})
  - Имя Фамилия (ktalk:{id})
chunked: true          # только для больших транскриптов
total_chunks: N        # только для больших транскриптов
total_characters: M    # только для больших транскриптов
---

# {recording_name} — {date}

{полный собранный транскрипт}
```

For small transcripts, do NOT add the `chunked`, `total_chunks` and `total_characters` fields
to the frontmatter.

## For small transcripts (not chunked)

The full text is in context — analyse as usual:

**Pass 1 — FACTS** (with timestamps from the transcript):

- Verify every point of the summary against the transcript — find the timecodes and the exact
  wording
- What was discussed (the structure of the conversation)
- Explicit decisions: `решили`, `договорились`, `берёт`, `закрываем`
- Explicit tasks: `сделать до`, `взял на себя`, `к следующей встрече`
- Status updates: `завершили`, `готово`, `отменили`
- Find facts that are NOT in the summary — a summary can drop nuances

**Pass 2 — INTERPRETATION** (with confidence):

- Focus on what the summary missed: nuances, mood, implicit signals, conflicts
- Is this new or an update to something existing? → check through whichever dependency of
  core step 0c is available (`qmd` or `directories.people`)
- Confidence: HIGH (explicit) / MEDIUM (inferred) / LOW (a guess)
- Record only HIGH and MEDIUM
- LOW → an `[UNCLEAR]` flag for the user

## For large transcripts (chunked) — summary-first + on-demand

The transcript is too large for the context window. Use the summary as a navigator and load
chunks deliberately.

**Pass 1 — FACTS (through the summary plus targeted chunks):**

- The summary (from core step 2.5) is the primary source of structured facts
- To verify each point of the summary, load the targeted chunk:
  ```
  ktalk get-transcript {recording_id} --chunk N --json
  ```
- Estimating the chunk number from a timestamp:
  `chunk_index ≈ (timestamp_sec / total_duration_sec) * total_chunks + 1`. If the guess
  misses, check the neighbouring chunk.
- Do not load every chunk — only those holding the moments of interest
- Record every fact found, with its timestamp and chunk number

**Pass 2 — INTERPRETATION (summary-directed selective loading):**

1. Build a "coverage map" from Pass 1:
   - Which chunks are already loaded and analysed
   - Which topics from the summary are verified
   - Which topics from the summary were NOT found in the loaded chunks

2. Load the first and the last chunk (if Pass 1 did not load them) — the opening (greeting,
   agenda) and the ending (conclusions, wrap-up) often hold key decisions and commitments.

3. For uncovered topics — load the targeted chunks (the same estimate as above).

4. Do NOT reload chunks that are already loaded. Use the accumulated findings from Pass 1.

5. Analyse each loaded chunk — focus on what the summary missed: nuances, mood, implicit
   signals, conflicts.

6. Between chunks — carry the accumulated findings forward in condensed form, for context.

**Limits:** load at most 60% of `total_chunks` in Pass 2. If every topic is covered earlier,
stop.

- Confidence: HIGH (explicit) / MEDIUM (inferred) / LOW (a guess)
- Record only HIGH and MEDIUM
- LOW → an `[UNCLEAR]` flag for the user

## Structured extraction (checklist)

After the two passes — fill in every category. If a category is empty, write `Нет` explicitly.

**A. `Решения`** (filter: an explicit `решили` / `договорились` / `берём`, or a manager's
directive). For each:

- The wording of the decision (at most 2 sentences)
- Who made it (role + name)
- Timecode
- Confidence: HIGH/MEDIUM
- Success criterion (if stated)

**B. `Договорённости`** (filter: a concrete action plus a concrete owner). For each:

- Who (name)
- What (verb + object)
- Deadline (a date or `—`)
- Confidence: HIGH/MEDIUM

**C. `Обновления статуса`** (filter: `завершили` / `готово` / `отменили` / `сдвинулось`).
For each:

- What changed
- The new status
- The existing entry (if there is one — update it, do not duplicate)

**D. `Открытые вопросы`** (everything marked `[UNCLEAR]` plus explicitly unfinished topics).
For each:

- The wording of the question
- Who is to answer (if clear)
- Timecode

**E. `Флаги для владельца проекта`** (only if the owner is a participant of the meeting
themselves — the owner's identifier is passed by the orchestrator in `additional_context`,
where that applies to the host project):

- Candidates for architectural decisions (ADR)
- Personnel signals
- Compliance / information security
- Resource decisions
