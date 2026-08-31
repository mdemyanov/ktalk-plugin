---
order: 40
title: Архитектура
---

Компоненты и границы, модели данных, контракты API, спеки-спутники к ADR.

## Внутри раздела

- [2026-08-26-agreements-reconciliation.md](2026-08-26-agreements-reconciliation.md) — сверка
  открытых договорённостей: шаг 5.5 `ktalk-processor`, companion к ADR-020
- [2026-08-31-cli-only-boundary.md](2026-08-31-cli-only-boundary.md) — снятие
  MCP-поверхности плагина и пин версии пакета, companion к ADR-022
- [2026-08-31-plugin-requirements-relocation.md](2026-08-31-plugin-requirements-relocation.md) —
  раскладка, наименование и брифы переезда четырёх требований плагина, companion к ADR-023
- [2026-08-31-plugin-requirements-relocation-at-design.md](2026-08-31-plugin-requirements-relocation-at-design.md) —
  тест-дизайн QA-001: 10 наблюдаемых исходов переезда (REL-1…REL-10), стаб
  `scripts/test-plugin-requirements-relocation.sh`

## Правила

- Решение «почему так» — в ADR (`00-project/adr/`); здесь — как это устроено.
- Статья-спутник ADR объявляет родителя ссылкой в шапке.
