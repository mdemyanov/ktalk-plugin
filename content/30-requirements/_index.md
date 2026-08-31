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
- [2026-08-31-cli-only-boundary.md](2026-08-31-cli-only-boundary.md) — необязательный MCP-extra
  пакета `ktalk-mcp`, снятие MCP-поверхности плагина, пин точной версии (эпик `ktalk-plugin-4nk`)
- [2026-08-31-cli-only-boundary/](2026-08-31-cli-only-boundary/_index.md) — тест-дизайн QA-001:
  покрытие 9 сценариев спеки, стабы `test-onboard.sh`
- [2026-08-18-meetings-prompt-surface.md](2026-08-18-meetings-prompt-surface.md) — промт-
  поверхность встреч: расписание, создание/отмена по санкции, поиск участника, диагностика
  комнаты (переезд из дерева пакета `ktalk-mcp`, ADR-023, эпик `ktalk-plugin-56l`)
- [2026-08-18-onboarding-sanctioned-install.md](2026-08-18-onboarding-sanctioned-install.md) —
  обнаружение отсутствующего/несовместимого пакета и санкционированная установка (переезд из
  дерева пакета `ktalk-mcp`, ADR-023)
- [2026-08-19-analysis-quality-calibration.md](2026-08-19-analysis-quality-calibration.md) —
  калибровка извлечения обязательств, confidence и маркировки имён в промте анализа (переезд из
  дерева пакета `ktalk-mcp`, ADR-023)
- [2026-08-19-prompt-defect-channel.md](2026-08-19-prompt-defect-channel.md) — канал дефектов
  промта: секция отчёта `ktalk-eval` → issue репозитория плагина, порог 2+ записи (переезд из
  дерева пакета `ktalk-mcp`, ADR-023)

## Правила

- Требование пишет `/nauta:ba`; критерии приёмки живут не здесь, а в capability-спеке
  `openspec/specs/<capability>/spec.md`, объявленной строкой `**Capability:**` в шапке.
- Формулировка проверяема: «быстро» и «удобно» требованием не являются.
