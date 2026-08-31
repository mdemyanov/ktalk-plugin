---
order: 70
title: Эксплуатация
---

Runbook, деплой, мониторинг, откат.

## Внутри раздела

- [2026-08-31-cli-only-boundary-release-runbook.md](2026-08-31-cli-only-boundary-release-runbook.md) —
  выпуск на два репозитория (`ktalk-mcp` → `ktalk`), пред-релизная проверка AC-9, откат
  плагина и пакета раздельно
- [2026-08-31-package-rename-transition-release-runbook.md](2026-08-31-package-rename-transition-release-runbook.md) —
  переход `ktalk-mcp` → `ktalk-cli`: три публикации в строгом порядке, гейт перед релизом
  плагина, откат по идентичности пакета (не только по версии), санкция публикации

## Правила

- Runbook пишет `/nauta:devops`; шаг без проверяемого исхода шагом runbook не является.
