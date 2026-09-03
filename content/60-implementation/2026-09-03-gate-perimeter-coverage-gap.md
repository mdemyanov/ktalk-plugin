---
properties:
  - name: Тип контента
    value: [Прочее]
  - name: Фаза
    value: [Pilot]
  - name: Статус
    value: [Draft]
  - name: Audience
    value: [Internal]
---

# Реализация: периметр сторожей промт-слоя расширен на `references/`

**Требование:** [2026-08-19-analysis-quality-calibration.md](../30-requirements/2026-08-19-analysis-quality-calibration.md) (NFR-25)
**Architecture:** ADR-025 Д5 (переезд `agents/references/*.md` → `references/ktalk-processor/`)
**Capability:** `openspec/specs/meeting-analysis-quality-calibration/spec.md`

## Что было неочевидно

**Переезд файлов из ADR-025 Д5 создал слепую зону сразу в двух сторожах.** Коммит `234d79e`
увёл три справочника `ktalk-processor` (`two-pass-analysis.md`, `protocol-template.md`,
`vault-update-and-report.md`) из `agents/references/` в новый top-level каталог
`references/ktalk-processor/` — решение верное само по себе (`claude plugin tag --dry-run`
сканировал `agents/` как источник агентов по расположению, не по фронтматтеру, и ошибочно
находил там несуществующих агентов). Побочный эффект: ни снимок неизменности
`scripts/test-onboard.sh` (`find skills agents commands`), ни диапазон диффа
`scripts/check-plugin-composition.sh` (`git diff … -- agents/ skills/ktalk-registry/`) не
задевают новый каталог — оба периметра были названы как список конкретных директорий, а не
выведены из состава плагина. Правка `references/ktalk-processor/protocol-template.md` в
коммите `281be92` (задача DEV-101, тем же раундом волны) прошла мимо обоих гейтов одновременно
— молча, до ручной сверки при слиянии волны.

**Разный периметр для AC-1 и NFR-25 — осознанное решение, не недосмотр.** AC-1
(`test-onboard.sh`) — общий снимок всего текста промт-слоя, его формулировка не сужена
предметом одного требования; расширен на весь `references/` (третий аргумент `find`), включая
`references/onboarding.md` — по прецеденту `check-mcp-channel-language.sh` (DEV-102), который
уже трактует `skills/+agents/+commands/+references/` как один промт-слой из четырёх каталогов.
NFR-25 (`check-plugin-composition.sh`) — уже сама формулировка требования сужает предмет до
«промт-слоя анализа»; расширен только на `references/ktalk-processor/` (файлы, которые
трассировка FR-40/FR-41 требования называет как источник AC), `references/onboarding.md` в
диапазон NFR-25 сознательно не включён — он не о калибровке анализа.

**Расширение периметра NFR-25 само вскрыло реальный, уже смёрженный дрейф.** До этой задачи
`check_prompt_version_sync()` не видел `references/ktalk-processor/` вовсе, поэтому правка
`281be92` (DEV-101, два абзаца в `protocol-template.md` про маркер `[ASR?]` и константу
`decisions_count: 0`) прошла без подъёма minor-версии — версия плагина к этому моменту уже
стояла на 1.10.0 (поднята раньше, коммитом `ac09cd5`, по другому поводу). После расширения
периметра `check-plugin-composition.sh` немедленно упал на этом самом диффе; проверено прогоном
на 1.10.0 (FAIL, см. отчёт задачи) и на 1.11.0 (OK) — версия плагина поднята 1.10.0 → 1.11.0
этим же раундом.

## Мутационное доказательство

Временная правка одного символа в `references/ktalk-processor/two-pass-analysis.md` переводит
AC-1 в FAIL (ожидаемый/полученный хэш расходятся); откат восстанавливает зелёный статус. До
расширения периметра та же мутация была бы невидима снимку — она физически вне `find skills
agents commands`.

## Что не тронуто

- Содержимое промт-слоя (`agents/`, `skills/`, `commands/`, `references/`) — задача про периметр
  сторожей, не про правила калибровки.
- `scripts/check.sh`, `openspec/specs/`, тела принятых ADR — красные линии задачи.
