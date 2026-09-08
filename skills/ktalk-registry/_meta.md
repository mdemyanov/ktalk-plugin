---
id: ktalk-registry
version: 4.0.0
source: custom
created: 2026-03-19
updated: 2026-08-29
author: mdemyanov
status: active
type: skill
tags: [ktalk, transcripts, meetings, registry, archive, agents, eval]
prompt_version: 2
---

# ktalk-registry

## Purpose

- Synchronise recordings from Kontur Talk through the `ktalk` CLI
- Maintain the registry with processing-status tracking
- Update `ktalk_id` in participant profiles (if a profile directory is declared)
- Gather context (save location, extra input) from the user
- Launch background `ktalk-processor` agents to process meetings

## Components

| File | Purpose |
|------|---------|
| `SKILL.md` | The orchestrator's main workflow |
| `references/registry-format.md` | Registry format specification |
| `references/analysis-quality.md` | Analysis-quality instructions for ktalk-processor |

## Related elements

| Element | Type | Path (inside the plugin) |
|---------|------|--------------------------|
| ktalk-processor | agent | `../../agents/ktalk-processor.md` |
| ktalk-evaluator | agent | `../../agents/ktalk-evaluator.md` |
| ktalk-eval | skill | `../ktalk-eval/SKILL.md` |
| Registry (data) | data | the path is resolved by `ktalk config show`, not hard-coded here |
| Quality tracker (data) | data | the path is passed in the input parameters of `ktalk-eval` |

## Changelog

### 4.0.0 (2026-04-03, deparameterised 2026-08-18, calibrated 2026-08-19)

- Fixed MCP parameter names in every call (recording_id→recording_key, date_from→start_from,
  date_to→start_to, limit→top)
- Explicit `format="markdown"` in every content-reading call
- Conditional enrichment — `get-recording` is called only if the recording list returned no
  duration
- Few-shot quality examples (Appendix A in analysis-quality.md) — three `ХОРОШО`/`ПЛОХО` pairs
- Structured extraction checklist — five mandatory categories
- Fixed protocol schema — rigid table columns, new frontmatter fields
- Summary-driven selective chunking — at most 60% of chunks instead of 100%
- Fast path for short meetings (<15 min) — single-pass analysis
- Memory-not-file warning — analyse from the loaded data, not from a file
- Eval framework: the `ktalk-eval` skill, the `ktalk-evaluator` agent, a five-dimension rubric
- A/B testing: infrastructure for comparing prompt versions
- **2026-08-18 (wave 3, plugin DEV-002):** moved into the `ktalk` plugin; host project paths
  deparameterised (`ktalk config show --json` instead of hard-coded constants); registry and
  content-reading calls moved to the `ktalk` CLI as the primary channel (MCP is secondary,
  content reading only); the news-digest step and the `analysis-quality.v1.md` snapshot were
  not carried over — outside the plugin boundary (host package ADR-012 §6)
- **2026-08-19 (DEV-014, ADR-018):** calibration of the analysis prompt layer against three
  defects measured by `ktalk-eval` (Completeness, confidence, name marking) — step 4.5, the
  final reconciliation of prose against the `Договорённости` table (`ktalk-processor.md`); a
  single `[ASR?]` marker for unresolved names and the optional `Ключевые тезисы` section for
  `session` (`protocol-template.md`); batch resolution of third parties with a per-run cache
  (`analysis-quality.md` §1/§1a); the calibration pair of examples 3a/3b replacing the
  erroneous Example 3 (a conditional request does not by itself lower confidence — the
  accepting utterance decides); normativity separated between `two-pass-analysis.md` (the
  A–E algorithm) and `analysis-quality.md` (the confidence scale, the appendix) — cross
  references instead of copied text; plugin version 1.2.1→1.3.0, `prompt_version` 1→2
  (NFR-25)

### Prompt versions

- v1 (2026-03-19): initial version of analysis-quality.md
- v2 (2026-04-03): few-shot examples, extraction checklist, fixed schema.
  Note: before the DEV-014 change the `prompt_version` frontmatter held `1`, although this
  list already recorded v2 as current — the discrepancy was found by that change, not created
  by it; it is not fixed retroactively, being outside the ADR-018 perimeter.
- v2, calibrated (2026-08-19, DEV-014/ADR-018), frontmatter `prompt_version: 2`: step 4.5 of
  the final reconciliation, the `[ASR?]` marker, batch resolution of third parties, examples
  3a/3b, normativity separated from `two-pass-analysis.md` (current)

### 3.1.0 (2026-04-03)

- Updated to the `ktalk-mcp` package v0.3.0
- The `ktalk-processor` agent: transcript chunking support (chunk/chunk_size)
- Loading large transcripts by chunks with automatic assembly
- Summary-first + on-demand analysis for chunked transcripts

### 3.0.0 (2026-04-03)

- Migrated to the `ktalk-mcp` package instead of a custom HTTP MCP
- New reading tools: recording list, recording details, transcript, summary
- Data enrichment when the list holds no duration
- Authentication: session token instead of bearer token

### 2.0.0 (2026-03-25)

- The registry moved to a generated markdown mirror
- Added updating of `ktalk_id` in participant profiles
- Added context gathering from the user before the agent is launched
- The `ktalk-processor` agent is launched in the background (run_in_background=true)
- Participants are stored with their full name and ktalk_id

### 1.0.0 (2026-03-19)

- First version: synchronisation, registry, archiving, expiration

### 2026-08-29 (issue #4, epic prompt-language-boundary)

- Instructional prose translated to English; verbatim Russian output preserved (ADR-021)

### 2026-08-31 (epic ktalk-plugin-4nk, DEV-002, ADR-022) — BREAKING

- **Breaking:** the plugin no longer declares an MCP server for the `ktalk` circuit (`.mcp.json`
  removed). "Related elements" above drops the `ktalk MCP` row — the secondary content-reading
  channel it named no longer exists; the CLI is the sole path from this skill to the circuit
- Operators who called a retired `mcp__ktalk__*` tool directly find the CLI equivalent in
  `references/onboarding.md` ("Retired MCP tools — CLI equivalents")
- Unrelated to this skill's own instructional prose — `prompt_version` is not bumped; the plugin's
  minor version is (NFR-25, `.claude-plugin/plugin.json`), since the change touches a file under
  `skills/ktalk-registry/`
