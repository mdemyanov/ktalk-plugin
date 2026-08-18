---
id: ktalk-eval
version: 1.0.0
source: custom
author: mdemyanov
status: active
tags: [ktalk, eval, quality, testing]
created: 2026-04-03
updated: 2026-08-18
---

# ktalk-eval — Метаданные

## Changelog

### v1.0.0 (2026-04-03)
- Начальная версия
- 5 измерений качества (Completeness, Accuracy, Schema, Actionability, Confidence)
- Трекер качества
- A/B тестирование промтов
- Агент-оценщик (`../../agents/ktalk-evaluator.md`)

### 2026-08-18 (волна 3, DEV-002 плагина)
- Перенос в плагин `ktalk`: пути отчёта/трекера читаются из `.ktalk.toml`
  хозяина (`ktalk config show --json`), не зашиты в промт
- Чтение саммари переведено на CLI (`ktalk get-summary`) вместо MCP
