---
order: 60
title: Реализация
---

Заметки Dev о специфике реализации: что было неочевидно, какие граничные случаи закрыты.

## Внутри раздела

- [test-reports/](test-reports/_index.md) — отчёты QA-runner о полных прогонах тестового набора
- [2026-09-03-release-delivery-tails.md](2026-09-03-release-delivery-tails.md) — хвосты релиза
  1.9.0: доставка, точность состава, границы оркестратора (DEV-001, ktalk-plugin-ke5.12)
- [2026-09-03-projectgates-full-recursion-guard.md](2026-09-03-projectgates-full-recursion-guard.md)
  — подключение `test-release-delivery-tails.sh` к `projectGates.full` без рекурсии (DEV-002,
  ktalk-plugin-ke5.14)

## Правила

- Дом отчёта о прогоне тестов — стор задач (правило трёх домов). Пока стора нет, отчёты лежат
  временно здесь, под типом «Прочее» (см. `test-reports/_index.md`) — переезд в стор без потери
  содержимого будет отдельной задачей, когда стор появится.
