---
id: ktalk-eval
version: 1.0.0
source: custom
author: mdemyanov
status: active
tags: [ktalk, eval, quality, testing]
created: 2026-04-03
updated: 2026-08-29
---

# ktalk-eval — metadata

## Changelog

### v1.0.0 (2026-04-03)
- Initial version
- Five quality dimensions (Completeness, Accuracy, Schema, Actionability, Confidence)
- Quality tracker
- A/B testing of prompts
- Evaluator agent (`../../agents/ktalk-evaluator.md`)

### 2026-08-18 (wave 3, plugin DEV-002)
- Moved into the `ktalk` plugin: report and tracker paths are read from the host's
  `.ktalk.toml` (`ktalk config show --json`), not hard-coded in the prompt
- Summary reading moved to the CLI (`ktalk get-summary`) instead of MCP

### 2026-08-29 (issue #4, epic prompt-language-boundary)
- Instructional prose translated to English; verbatim Russian output preserved (ADR-021)
