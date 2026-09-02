---
description: >
  Kontur Talk recording registry — synchronisation, review, transcript processing.
  Trigger phrases (Russian, matched against the owner's utterance — do not translate):
  "ktalk", "записи", "транскрипты", "реестр встреч",
  "обработай записи", "что нового в толке", "синхронизируй записи".
---

# /ktalk-registry — Kontur Talk recording registry

> **Synchronise ktalk recordings, gather context, launch background processor agents**

**Language.** Reason in English. Every string shown to a human — and every string written into
the host's vault — is Russian: reproduce the Russian literals in this file and in the
referenced files verbatim, never translate or reword them (ADR-021).

---

## What this command does

1. Fetches new recordings from Kontur Talk (the last 7 days)
2. Updates the markdown mirror of the registry
3. Updates `ktalk_id` in participant profiles (if a profile directory is declared)
4. Shows the unprocessed recordings
5. For each selected recording — gathers context (where to save, extra input)
6. Launches the `ktalk-processor` agent in the background for each meeting

---

## Instructions

Load and run the workflow from the `ktalk-registry` skill
(`skills/ktalk-registry/SKILL.md`).

The host project's directory layout lives neither in this command nor in the host's
`CLAUDE.md`: the discovery config `.ktalk.toml` (if declared) is read by the CLI
package through `ktalk config show --json` (workflow step 0) — go there, not to any textual
description of the layout.

---

## Related tools

| Tool | Purpose |
|------|---------|
| `ktalk-processor` agent | Processing one recording (launched automatically) |
| `ktalk config show` | The host project's layout |
