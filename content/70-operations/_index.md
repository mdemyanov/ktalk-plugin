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
- [2026-09-03-release-delivery-tails-release-runbook.md](2026-09-03-release-delivery-tails-release-runbook.md) —
  релиз 1.10.0: тег `claude plugin tag` вместо `git tag`, пред-релизный гейт GO-критериев
  `check.sh --full`, границы оркестратора/обработчика (`project-curator`), перенос issue
  `#5`/`#7` в трекер пакета, закрытие `#6`
- [2026-09-04-dual-channel-delivery-release-runbook.md](2026-09-04-dual-channel-delivery-release-runbook.md) —
  двухканальная поставка (GitLab — источник истины, GitHub-зеркало): первая публикация зеркала,
  джоб `mirror-github` на каждом релизе, guard резолвимости ref'ов + три команды сверки паритета
  (ADR-027 Д6), откат по новому тегу (не по перемещению/удалению уже опубликованного)

## Правила

- Runbook пишет `/nauta:devops`; шаг без проверяемого исхода шагом runbook не является.
