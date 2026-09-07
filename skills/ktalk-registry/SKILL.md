---
name: ktalk-registry
description: >
  Manage the Kontur Talk recording registry — synchronise new recordings, track processing,
  archive transcripts into markdown.
  Trigger phrases (Russian, matched against the owner's utterance — do not translate):
  "ktalk", "записи", "транскрипты", "реестр встреч",
  "обработай записи", "что нового в толке", "ktalk registry",
  "покажи необработанные встречи", "синхронизируй записи".
  Use this skill even when the user merely mentions ktalk recordings.
---

# Kontur Talk recording registry

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

This is an orchestrator skill. All the registry mechanics (synchronisation, deduplication,
expiration, status changes, rendering the dashboard and the markdown mirror) are performed by
the **`ktalk` CLI**, not by the model's reasoning. The skill calls the CLI, shows its output,
collects the user's selection and context, and launches background processor agents.

The host project's directory layout (registry paths, protocol routing, profile and project
directories) is not hard-coded in this skill — it is read by `ktalk config show --json`
(step 0). A project with no declared layout is a normal branch: the registry commands
(`sync`/`dashboard`/`list`/`show`/`mark-*`/`export`) work on the machine default, and the
steps that depend on profile/project directories or on `qmd` mark their result explicitly
rather than being half-performed.

The detailed data model: `references/registry-format.md`
The analysis-quality instructions: `references/analysis-quality.md`

## Architecture

- **SQLite** — the operational source of truth (IDs, statuses, paths, dates, participants).
  Its location is resolved by the priority `--db > KTALK_REGISTRY_DB > the host's config >
  a machine default` — it is not a constant of this skill.
- **The `ktalk` CLI** — deterministic mechanics and content reading (recordings, transcripts,
  summaries). Every command supports `--json` (valid JSON on stdout; errors on stderr with a
  non-zero exit code). This is the sole call channel from this skill to the circuit —
  the plugin declares no MCP server (ADR-022 D1). **One exception:** `get-transcript` (only
  this command) returns exit code `3` for a fully printed, complete response whose independent
  identity check did not confirm the speakers — not a call failure. See the table row below.
- **The markdown mirror of the registry** — generated and read-only (`ktalk export`), at a
  path inside the host project. **Never edit it by hand and never parse it as a source.**

## Principles

1. **Mechanics live in the CLI.** Do not read or rewrite tables, do not deduplicate and do not
   expire by hand — `ktalk sync` does that.
2. **Idempotency** — a repeated `ktalk sync` breeds no duplicates.
3. **Context before launch** — every question to the user is collected BEFORE the agent is
   launched.
4. **Background processing** — the `ktalk-processor` agent is launched in the background.
5. **ktalk_id first** — look profiles up by ktalk_id (exact), falling back to the name.
6. **Degradation is explicit.** A missing host directory or integration does not block the
   steps that do not depend on it; the unavailable part is marked in the output rather than
   passed over in silence.

## Workflow

### Step 0. Read the host project's configuration

```
ktalk config show --json
```

Take `registry.db_path` (informational — the CLI resolves the priority itself),
`directories.people`, `directories.projects_active`, `routing.*` and `integrations.qmd`. A
missing key is not an error but a normal branch (see "The degradation contract" below). Keep
the values in context for steps 4 and 5.

### Step 1. Synchronisation

```
ktalk sync --json
```

The CLI fetches recordings from ktalk for the window (7 days by default), adds new ones
(`new`), expires `new` records strictly older than 7 days (→ `skipped`), and updates
`last_synced` / `sync_count`. The output:

```json
{
  "synced": N, "inserted": N, "updated": N,
  "expired": ["id", ...],
  "stats": {"new": N, "processing": N, "done": N, "skipped": N, "partial": N}
}
```

On an error (an expired `KTALK_SESSION_TOKEN`, for instance) the CLI returns a non-zero code
and a message on stderr — show it to the user and stop.

### Step 2. Show the dashboard

Get the list of new recordings and the statistics:

```
ktalk dashboard --json
```

Output: `{"new": [{recording_id, name, date, duration_min, ...}], "stats":{...}, "last_synced": "2026-08-27" | null}` — `last_synced` is a top-level key (not inside `stats`), always present: a calendar date string after the first successful sync, `null` before it.

Show the user a numbered list of new recordings and the statistics:

```
## Реестр ktalk — {{today}}

### Новые записи (N)
1. [ID_SHORT] Название — YYYY-MM-DD — 45 мин
2. ...

### Пропущенные в этот раз (M)
- (из `expired` шага 1)

### Статистика
- Новых: N | Обработано: Y | Пропущено: Z | Частично: P | В обработке: K

Какие записи обработать? (номера через запятую, "все" или "нет")
```

`ID_SHORT` is the first 8 characters of `recording_id`.

### Step 3. Get the user's selection

- The user enters numbers (`1, 3`), `все` or `нет`.
- If `нет` → print `Реестр синхронизирован` and finish (go to step 6 — export).
- If `все` → every recording with status `new`.

### Step 4. Gather context for each selected recording

For each selected recording, get the details (participants with `ktalk_id` / `vault_id`):

```
ktalk show <recording_id> --json
```

**4.1. Match participants to profiles (for participants with no `vault_id`).** The two lookups
are independent — the unavailability of one does not stop the step (FR-24 of the `ktalk`
plugin, ADR-012):

1. If `qmd` is available (the MCP tool is present in the session): look the profile up with
   `mcp__qmd__search(query="ktalk_id: \"N\"", collection="cto-people")`
2. If `directories.people` is declared and exists (from step 0), fall back to
   `Grep(pattern="name: \".*Фамилия\"", path=<the value of directories.people>, output_mode="content")`
3. If neither dependency is available — mark the matching as unavailable, do not substitute a
   guess about the participant, and carry on with the remaining steps.
4. If the profile is found and holds no `ktalk_id` → add it to the frontmatter after `id:`.
5. Record the binding in the registry:
   ```
   ktalk set-vault-id <recording_id> <ktalk_id> <vault_id>
   ```
6. If the profile is not found → leave the participant without a `vault_id` (the processor
   will handle it).

**4.2. Gather the context interactively** (before the agent is launched):

```
📋 Встреча [N/M]: "{recording_name}"
   Дата: {date}
   Участники: {список имён}
   Тип: {автоопределение}

Где сохранить протокол?
  {автопредложения на основе типа и участников — по routing.* из шага 0}
  [N] Только транскрипт, протокол не нужен

Дополнительный контекст для анализа (Enter — пропустить):
>
```

**Automatic meeting-type detection** (the cues are Russian because the meeting titles are):

- Contains `🤝` or two names separated by a delimiter → `1-1`
- Contains `комитет`, `архком`, `committee` → `committee`
- Contains `стратегическ`, `стратком`, `strategy` → `session`
- Contains `стендап`, `оперативн`, `standup`, `sync` → `standup`
- Contains `статус`, `status` → `status`
- Otherwise → `other`

**Automatic save-location suggestions** come from `routing.<meeting_type>` (a template in the
host's config, step 0). If no route key is declared for this `meeting_type`, do not suggest a
path automatically — offer only `Только транскрипт` and manual path entry by the user.

### Step 5. Launch the processor agents

Once the context is gathered, launch the agent **in the background** immediately, without
waiting for it to finish:

```
Agent("ktalk-processor", prompt="""
recording_id: {recording_id}
recording_name: {recording_name}
date: {date}
participants:
  - name: "Имя Фамилия"
    ktalk_id: "N"
    vault_id: "id_или_unknown"
meeting_type: {тип}
save_location: {путь}
additional_context: |
  {дополнительный контекст от пользователя}
""", run_in_background=true)
```

After each launch:

```
▶ Обработка запущена: "{название}" [фон]
```

Then move straight on to the next meeting (step 4). After all the launches:

```
✅ Запущено N агентов. Уведомлю по завершении каждого.
```

The agent moves the record to `processing` at the start and to `done`/`partial` at the end
itself, through `ktalk mark-*` — the skill does not interfere. The agent obtains the directory
layout the same way this skill does, with `ktalk config show --json`, not through the
parameters of this prompt.

### Step 5.5. Collecting affected projects and delegating to project-curator

`ktalk-processor` never calls `project-curator` itself (ADR-026 D1) — it only reports the
projects a meeting touched. This step is where that report turns into action, once per run of
this skill, not once per agent:

1. As task notifications about each launched agent's completion arrive, read the
   `Проекты затронуты: {ids}` / `Проекты затронуты: нет` line of that agent's final report and
   union its ids into a running set for this run. Mark that agent completed.
2. Once every agent launched by step 5 of **this** run is marked completed:
   - the union is empty — do nothing further, `project-curator` is not called at all for this
     run.
   - the union is non-empty — call `project-curator` **exactly one time**, at most once per
     run, never once per agent, with the combined list of ids and the `(date, save_location)`
     pairs already known from step 4 of this same run.
   - if that call does not resolve (`project-curator` is not installed in the host project) —
     catch it and add to the run's summary: `project-curator не установлен — обновление карточек пропущено`. This is a degradation, not a failure of the run.
3. An agent that crashes or hangs before sending its final report never gets marked completed
   — it drops out of this run's set, and `project-curator` is not called for this run even for
   the ids other agents already reported (a known limitation, not a designed timeout).

### Step 6. Refresh the markdown mirror

After the launches (and when the user chose `нет`), regenerate the markdown mirror of the
registry:

```
ktalk export
```

```
✅ Зеркало обновлено
```

> Once the background agents have finished, it is worth repeating `ktalk export` so that the
> mirror reflects the new `done` records.

## Related tools

| Tool | Purpose |
|------|---------|
| `ktalk config show --json` | The host project's layout (registry, directories, routes, integrations) |
| `ktalk sync` | Synchronisation + deduplication + expiration + dashboard |
| `ktalk dashboard` | New recordings and statistics |
| `ktalk show <id>` | Recording details (participants, statuses, paths) |
| `ktalk set-vault-id <id> <ktalk_id> <vault_id>` | Bind a profile to a participant |
| `ktalk export` | Regenerate the markdown mirror of the registry |
| `ktalk-processor` agent | Process a recording (transcript + profile/project updates) |
| `ktalk get-transcript <id> --json` | The transcript by pages (`--chunk`, `--chunk-size`); since 2.0.0 always wrapped in a `transcript`/`identity_check` envelope, identity check on by default (`--no-verify-identity` to disable). Since 2.1.0, exit code `3` means the envelope printed above is complete and `identity_check.result == "mismatch"` — not a failed call; read `.transcript` as usual (`ktalk-processor.md` step 2b runs its own separate check regardless of this field) |
| `ktalk get-summary <id> --json` | The meeting's summary and protocol |
| `references/registry-format.md` | The data model: SQLite + CLI |
| `references/analysis-quality.md` | The analysis-quality instructions for the agent |
| `/find-person` | Look up information about a person (a host-project skill, if installed) |
