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
- [ADR-025-release-delivery-surface.md](ADR-025-release-delivery-surface.md) —
  поставочная поверхность плагина и доставка релиза потребителю: форма релизного тега,
  манифест маркетплейса, полнота документированного пути обновления, состав `agents/`,
  подключение GO-критериев к `check.sh`
- [ADR-026-orchestrator-processor-boundary.md](ADR-026-orchestrator-processor-boundary.md) —
  граница оркестратора и обработчика: кто вызывает `project-curator`, что обработчик
  возвращает отчётом, проверка личности транскрипта перед анализом (issue #5, #6)
- [ADR-027-github-mirror-channel.md](ADR-027-github-mirror-channel.md) —
  второй канал поставки, публичное GitHub-зеркало payload: имя маркетплейса зеркала, процесс
  одностороннего зеркалирования, документация обоих каналов, scoped-проверка внутреннего
  домена, подтверждение источника истины для issue/PR, команды сверки паритета (extends in
  part ADR-025)
- [ADR-028-session-only-authorisation.md](ADR-028-session-only-authorisation.md) —
  единственный документированный режим авторизации плагина — токен сессии: снятие личного
  ключа с заявленной поверхности, файл токена наравне с переменной в двух точках входа,
  инвариант `list-archive`/отчёта по участникам, судьба FR-28 (superseded in part), периметр
  сторожа на литерал `KTALK_PERSONAL_API_KEY`
- [ADR-029-detection-without-remediation.md](ADR-029-detection-without-remediation.md) —
  обнаружение отставного режима авторизации без устранения: почему нет хука автоудаления
  переменной и хука правки файла оболочки при автообновлении, цена отказа от обнаружения
  вовсе

## Правила

- Принятый ADR не редактируется: при пересмотре — новый ADR, ссылка «superseded in part» в его
  разделе «Consequences», статус старого ADR не трогается (отдельная задача PM).
- Реализационная деталь, бриф для Dev/DevOps и контракт с QA-author — не в теле ADR, а в
  companion-статье `content/40-architecture/`.
