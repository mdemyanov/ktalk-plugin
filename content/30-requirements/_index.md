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
- [2026-08-31-package-rename-transition.md](2026-08-31-package-rename-transition.md) —
  переименование пакета `ktalk-mcp` в `ktalk-cli`: сохранение имени команды, порядок публикации,
  версия-указатель, коллизия слота `uv tool`, санкция публикации (эпик `ktalk-plugin-foz`)
- [2026-08-31-package-rename-transition/](2026-08-31-package-rename-transition/_index.md) —
  тест-дизайн QA-001: покрытие 7 сценариев спеки, стабы `test-onboard.sh` (47–56)
- [2026-09-03-release-delivery-tails.md](2026-09-03-release-delivery-tails.md) — хвосты после
  1.9.0: тег и путь обновления плагина, фантомные агенты-справочники, retired-имя пакета в
  метаданных, границы оркестратора и обработчика (issue #5, #6), гейтовый контур вслед за
  `CLAUDE.md` (эпик `ktalk-plugin-ke5`)
- [2026-09-04-dual-channel-delivery.md](2026-09-04-dual-channel-delivery.md) — двухканальная
  поставка: внутренний GitLab-маркетплейс и публичное GitHub-зеркало, различимость имён
  маркетплейсов, кросс-канальное совпадение версии/пина/состава, отставание зеркала, гейт на
  внутренний домен, ручной приём issue/PR с публичной стороны (эпик `ktalk-plugin-dhg`)
- [2026-09-04-dual-channel-delivery/](2026-09-04-dual-channel-delivery/_index.md) — тест-дизайн
  QA-001: покрытие 6 сценариев спеки, стабы `scripts/test-dual-channel-delivery.sh`

## Правила

- Требование пишет `/nauta:ba`; критерии приёмки живут не здесь, а в capability-спеке
  `openspec/specs/<capability>/spec.md`, объявленной строкой `**Capability:**` в шапке.
- Формулировка проверяема: «быстро» и «удобно» требованием не являются.
