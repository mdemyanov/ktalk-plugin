---
order: 30
title: Требования
---

JTBD, функциональные и нефункциональные требования, бизнес-правила.

## Внутри раздела

- [2026-08-26-agreements-reconciliation.md](2026-08-26-agreements-reconciliation.md) — сверка
  открытых договорённостей при обработке записи встречи (issue #2)
- [2026-08-26-agreements-reconciliation/](2026-08-26-agreements-reconciliation/_index.md) —
  тест-дизайн QA-001: покрытие сценариев, детерминированные проверки, сценарные фикстуры
- [2026-08-29-prompt-language-boundary.md](2026-08-29-prompt-language-boundary.md) — языковая
  граница промт-слоя: рассуждение по-английски, выход по-русски (issue #4)
- [2026-08-29-prompt-language-boundary/](2026-08-29-prompt-language-boundary/_index.md) —
  тест-дизайн QA-001: покрытие AC группами A–D, что проверяется руками

## Правила

- Требование пишет `/nauta:ba`; критерии приёмки живут не здесь, а в capability-спеке
  `openspec/specs/<capability>/spec.md`, объявленной строкой `**Capability:**` в шапке.
- Формулировка проверяема: «быстро» и «удобно» требованием не являются.
