---
name: ktalk-eval
description: >
  Quality evaluation of processed Kontur Talk recordings — compares protocols against
  transcripts, scores five dimensions, maintains a tracker.
  Trigger phrases (Russian, matched against the owner's utterance — do not translate):
  "eval", "оценить качество", "проверить протокол",
  "quality check ktalk", "ktalk eval", "оцени обработку".
---

# Quality evaluation of ktalk processing

**Language.** Reason in English. Every string shown to a human — and every string written into
the host's vault — is Russian: reproduce the Russian literals in this file and in the
referenced files verbatim, never translate or reword them (ADR-021).

## Precondition: the CLI package

Before the first `ktalk` command in a session, run:

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/ktalk-onboard.sh check --json

Exit code 0 — carry on. A non-zero code — read
`${CLAUDE_PLUGIN_ROOT}/references/onboarding.md` and follow it; never skip the step silently
and never invent its result. You do not run the installation and sanction commands yourself:
`install` only after the user has already granted the sanction, `grant` never.

A skill for the systematic quality evaluation of meeting protocols produced by the
`ktalk-processor` agent.

The scoring rubric: `references/eval-rubric.md`

The host project's layout (where to save the report, where the tracker lives) is not
hard-coded in this skill — it is read by `ktalk config show --json` (step 0).

## Principles

1. **Post-hoc audit** — it evaluates already processed recordings (both transcript and
   protocol exist)
2. **LLM-as-judge** — the evaluator uses the same model in a different role (auditor, not
   author)
3. **Concrete anchors** — the scores 1–5 are tied to concrete criteria, not to a subjective
   "good/bad"
4. **Tracking** — every score is written into the tracker for trend analysis

## Workflow

### Step 0. Read the host project's configuration

```
ktalk config show --json
```

Take `routing.eval_report` (the report path template). If the key is not declared, agree the
report location with the user explicitly at step 3 — do not guess the path.

### Step 1. Choose the recordings to evaluate

If a `recording_id` was passed → use it.

If not, get the list of processed recordings through the CLI (without parsing the markdown
mirror of the registry — that is a generated file):

```
ktalk list --status done --json
```

Show the last 10 records from the `recordings` array (newest first):

```
## Оценка качества ktalk

Записи для оценки:
1. [ID_SHORT] Название — YYYY-MM-DD — тип
2. ...

Какие записи оценить? (номера, "все" или "нет")
```

`ID_SHORT` is the first 8 characters of `recording_id`. The type is the `meeting_type` field
(if it is `null`, show `—`).

### Step 2. Load the data

For each selected recording:

1. Take the transcript path (`transcript_path`) and the protocol path (`protocol_path`) from
   the JSON record (from `ktalk list` in step 1; for a single `recording_id` —
   `ktalk show <id> --json`)
2. Read the transcript (the Read tool)
3. Read the protocol (the Read tool)
4. Read the rubric: `references/eval-rubric.md`

For chunked transcripts (>50KB): load the summary through
`ktalk get-summary <recording_id> --json` plus the first and last 200 lines of the transcript.

### Step 3. Run the evaluation

Determine the report path: from the `routing.eval_report` template of step 0 (you substitute
the `{date}` and `{title}` placeholders yourself); otherwise ask the user.

Launch the `ktalk-evaluator` agent in the background:

```
Agent("ktalk-evaluator", prompt="""
recording_id: {recording_id}
recording_name: {recording_name}
date: {date}
meeting_type: {тип}
transcript_path: {путь к транскрипту}
protocol_path: {путь к протоколу}
prompt_version: {текущая версия из _meta.md}
plugin_version: {текущая version из .claude-plugin/plugin.json}
report_output_path: {путь отчёта, см. выше}
tracker_path: {путь трекера — из routing/directories хозяина или запрошен у пользователя}
""", run_in_background=true)
```

`plugin_version` is a mandatory parameter (NFR-25 AC2) and is not derived from
`prompt_version`: it is read separately from `.claude-plugin/plugin.json` (the `version`
field) immediately before the agent is launched, so that the report and the tracker record
the plugin version as of this particular run.

### Step 4. Show the result

Once the agent has finished:

```
Оценка завершена: "{recording_name}" — {date}

Отчёт: {report_output_path}

| Измерение | Оценка |
|-----------|--------|
| Completeness | X/5 |
| Accuracy | X/5 |
| Schema Consistency | X/5 |
| Actionability | X/5 |
| Confidence Usage | X/5 |
| **Overall** | **X.XX** |

Версия плагина прогона: {plugin_version} (`prompt_version`: {prompt_version})

Трекер обновлён: {tracker_path}
```

If the report carries a `Дефекты промта` section (the agent includes it only for cases ready
to become an issue — the threshold of 2+ recordings per class and a complete pair of
quotations, see `ktalk-evaluator.md`), show it to the operator separately from the score
table, in full, as text, and point at the plugin repository's `CONTRIBUTING.md` for filing the
issue:

```
Дефекты промта, готовые к issue:

{таблица «Дефекты промта» из отчёта — полностью}

Заведение issue — вручную, по правилам CONTRIBUTING.md репозитория плагина (порог 2+ записей,
обязательная пара цитат, обезличивание перед публикацией). Этот навык issue не заводит и не
публикует.
```

## A/B mode

For comparing two prompt versions:

### Step A1. Preparation

1. Make sure the analysis-instruction versions `v{A}` and `v{B}` exist (snapshots live outside
   this plugin, held by the host if they are needed)
2. Choose the recordings for the test (2–3 recommended)

### Step A2. Processing

1. Process the recordings with version A (if there is no protocol for `v{A}` yet)
2. Process the same recordings with version B → save to `{original_path}.v{B}.md`

### Step A3. Evaluation

1. Run the eval on both protocols
2. Generate a comparison report (the path is agreed with the user if the host declared no
   separate route for comparison reports)

## Related tools

| Tool | Purpose |
|------|---------|
| `ktalk config show --json` | The host project's layout (report routes) |
| `ktalk-evaluator` agent | Runs the six-pass evaluation |
| `references/eval-rubric.md` | The rubric with anchor descriptions |
| `ktalk list --status done --json` | The source of `done` records: transcript/protocol paths, statuses |
