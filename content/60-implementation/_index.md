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
- [2026-09-03-quality-calibration-drift-closure.md](2026-09-03-quality-calibration-drift-closure.md)
  — закрытие трёх пунктов дрейфа REV-002 в промт-слое калибровки анализа (DEV-101,
  ktalk-plugin-109)
- [2026-09-03-gate-perimeter-coverage-gap.md](2026-09-03-gate-perimeter-coverage-gap.md) —
  периметр AC-1/NFR-25 расширен на `references/` после переезда ADR-025 Д5, minor-версия
  1.10.0 → 1.11.0 (DEV-103, ktalk-plugin-igu)
- [2026-09-04-cli-2-0-0-contract-sync.md](2026-09-04-cli-2-0-0-contract-sync.md) —
  синхронизация промт-слоя с ломающим изменением `ktalk-cli` 2.0.0 (конверт
  `transcript`/`identity_check` у `get-transcript`), minor-версия 1.11.0 → 1.12.0
- [2026-09-04-cli-2-1-0-exit-code-3.md](2026-09-04-cli-2-1-0-exit-code-3.md) — код возврата `3`
  у `get-transcript` (сверка идентичности не сошлась, тело ответа полно) в `ktalk-cli` 2.1.0
  (DEV-002, ktalk-plugin-dhg.21); minor-версия плагина НЕ поднята — конфликт с NFR-25, не решён
  исполнителем

## Правила

- Дом отчёта о прогоне тестов — стор задач (правило трёх домов). Пока стора нет, отчёты лежат
  временно здесь, под типом «Прочее» (см. `test-reports/_index.md`) — переезд в стор без потери
  содержимого будет отдельной задачей, когда стор появится.
