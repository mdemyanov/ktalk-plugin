---
order: 10
title: ADR
---

Архитектурные решения проекта, по одному файлу на решение.

## Внутри раздела

- [ADR-020-agreements-reconciliation-scope.md](ADR-020-agreements-reconciliation-scope.md) —
  порог объёма и способ активации сверки открытых договорённостей
- [ADR-021-prompt-language-boundary.md](ADR-021-prompt-language-boundary.md) —
  языковая граница промт-слоя и способ пометки русских литералов
- [ADR-022-cli-only-boundary.md](ADR-022-cli-only-boundary.md) —
  снятие MCP-поверхности плагина, точный пин версии пакета, судьба санкции `grant update`
- [ADR-023-plugin-requirements-relocation.md](ADR-023-plugin-requirements-relocation.md) —
  переезд четырёх требований плагина из дерева пакета, пять capability, судьба трёх пересечений
  с `cli-only-boundary`
- [ADR-024-package-rename-transition.md](ADR-024-package-rename-transition.md) —
  переход `ktalk-mcp` → `ktalk-cli`: идентичность пакета в `compat.json`, коллизия слота
  `uv tool`, схема отката
- [ADR-026-orchestrator-processor-boundary.md](ADR-026-orchestrator-processor-boundary.md) —
  граница оркестратора и обработчика: кто вызывает `project-curator`, что обработчик
  возвращает отчётом, проверка личности транскрипта перед анализом (issue #5, #6)

## Правила

- Принятый ADR не редактируется: при пересмотре — новый ADR, ссылка «superseded in part» в его
  разделе «Consequences», статус старого ADR не трогается (отдельная задача PM).
- Реализационная деталь, бриф для Dev/DevOps и контракт с QA-author — не в теле ADR, а в
  companion-статье `content/40-architecture/`.
