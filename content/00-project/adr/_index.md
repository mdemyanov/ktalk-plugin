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

## Правила

- Принятый ADR не редактируется: при пересмотре — новый ADR, ссылка «superseded in part» в его
  разделе «Consequences», статус старого ADR не трогается (отдельная задача PM).
- Реализационная деталь, бриф для Dev/DevOps и контракт с QA-author — не в теле ADR, а в
  companion-статье `content/40-architecture/`.
