---
id: ktalk-meetings
version: 1.0.0
source: custom
author: mdemyanov
status: active
tags: [ktalk, meetings, calendar, contacts, rooms]
created: 2026-08-18
updated: 2026-08-18
---

# ktalk-meetings — Метаданные

## Changelog

### v1.0.0 (2026-08-18, волна 5, DEV-006 плагина)
- Начальная версия — SA-006 (`content/40-architecture/ktalk-plugin-meetings-spec.md`,
  репозиторий `ktalk-mcp`), требование BA-005 (`ktalk-plugin-meetings.md`, FR-32…FR-38,
  NFR-20…NFR-23).
- Шесть секций: расписание, создание встречи, отмена встречи, поиск участника, диагностика
  комнаты, диагностика при отказе (общая для остальных пяти).
- Контракт CLI — по DEV-009 (`ktalk-mcp` ≥ 0.8.0): `create-meeting-preview`/
  `cancel-meeting-preview`/`search-contacts` поддерживают `--json`; `search-contacts` различает
  коды `0`/`1`/`2`. См. `compat.json`.
- Двухшаговый handoff создания/отмены (ADR-015): навык не вызывает `*-confirm` программно ни при
  каком исходе.
