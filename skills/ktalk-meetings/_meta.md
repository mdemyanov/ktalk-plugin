---
id: ktalk-meetings
version: 1.0.0
source: custom
author: mdemyanov
status: active
tags: [ktalk, meetings, calendar, contacts, rooms]
created: 2026-08-18
updated: 2026-08-29
---

# ktalk-meetings — metadata

## Changelog

### v1.0.0 (2026-08-18, wave 5, plugin DEV-006)
- Initial version — SA-006 (`content/40-architecture/ktalk-plugin-meetings-spec.md`, the
  `ktalk-mcp` repository), requirement BA-005 (`ktalk-plugin-meetings.md`, FR-32…FR-38,
  NFR-20…NFR-23).
- Six sections: schedule, meeting creation, meeting cancellation, participant search, room
  diagnostics, and failure diagnostics (shared by the other five).
- CLI contract per DEV-009 (`ktalk-mcp` ≥ 0.8.0): `create-meeting-preview`,
  `cancel-meeting-preview` and `search-contacts` support `--json`; `search-contacts`
  distinguishes exit codes `0`/`1`/`2`. See `compat.json`.
- Two-step handoff for creation and cancellation (ADR-015): the skill never calls
  `*-confirm` programmatically, under any outcome.

### 2026-08-29 (issue #4, epic prompt-language-boundary)
- Instructional prose translated to English; verbatim Russian output preserved (ADR-021)
