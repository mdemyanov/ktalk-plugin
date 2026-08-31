---
order: 60
title: Тест-дизайн перехода ktalk-mcp → ktalk-cli
---

Тест-дизайн QA-001 эпика `ktalk-plugin-foz.17`: сохранение имени команды `ktalk`, схема
`compat.json` (`package_name`/`package_version`), различимость `wrong_package`/`outdated`/
`slot_collision`, порядок отката.

## Внутри раздела

- [at-design.md](at-design.md) — покрытие 7 сценариев capability-спеки, стабы
  `test-onboard.sh` (47–56), граничные и ошибочные случаи, зафиксированное расхождение
  BA-спеки с принятым решением о пакете-указателе
