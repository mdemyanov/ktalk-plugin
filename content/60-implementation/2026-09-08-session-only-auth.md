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

# Реализация: единственный режим авторизации — токен браузерной сессии

**Capability:** `openspec/specs/session-only-auth/spec.md`

DEV-001 эпика `ktalk-plugin-6sm` (ADR-028). Стабы — `scripts/test-session-only-auth.sh`,
тест-дизайн — `content/30-requirements/2026-09-07-session-only-auth/at-design.md` (11 AC).

## Что сделано

- `README.md` (шаг 3 «Положите токен»): убрана рекомендация личного API-ключа; шаг называет
  файл `~/.config/ktalk-mcp/token` и переменную `KTALK_SESSION_TOKEN` как равноправные места
  значения, не одно как резерв другого. Добавлен раздел «Что нового в пине `ktalk-cli` 2.1.0»
  (код возврата `3` у `get-transcript`).
- `references/onboarding.md` («## Authorisation»): один бюллет режима вместо двух, снята фраза
  о приоритете, файл и команда `ktalk token set -` названы самим текстом (не отсылкой на
  README), голое упоминание `.ktalk.toml` доведено до README-раздела «Настройка проекта».
- `skills/ktalk-registry/SKILL.md`: строка вывода `ktalk dashboard --json` получила ключ
  верхнего уровня `last_synced` (GitLab #8), с обеими формами значения (дата-строка/`null`).
- `skills/ktalk-meetings/SKILL.md` («Related commands»): указатель на команды записей в
  `ktalk-registry`, без копии таблицы и без `list-archive`/отчёта по участникам — они не имеют
  session-профиля (RES-001 §2) и не входят в мандат единственного оставшегося режима.
- `.claude-plugin/plugin.json`: `1.14.0` → `1.15.0` (NFR-25 — правка `skills/ktalk-registry/`).
- `scripts/test-onboard.sh`: снимок `EXPECTED_PROMPT_LAYER_SHA256` перебазирован (тот же приём,
  что в предыдущих раундах, at-design.md прямо называет его «самостоятельно перебазируемым Dev,
  без версии») — дневниковая запись добавлена над константой.
- `content/30-requirements/2026-08-18-onboarding-sanctioned-install.md`: FR-28 получил
  блокquote-отметку `Superseded in part` (ADR-028 Д1/Д4) тем же приёмом, что уже применён в
  `openspec/specs/cli-only-boundary/spec.md` (blockquote `> **Retired (…)**` сразу после текста
  Requirement, до его AC/Scenario) — тело и статус статьи не редактировались, только добавлена
  отметка перед `**AC:**`.

## Неочевидное

**Приём избежать «условной оговорки-резерва» (AC3-3).** Требование запрещает подавать файл
токена как fallback («если переменная не задана — используется файл»). Формулировка построена
без слова «если» рядом с «переменн»/«файл»/«token» вообще — оба места держат симметричную
формулировку «оба места равноправны, CLI читает любое из них», не условную.

**Cyrillic-в-английской-прозе (ADR-021 D2).** Ссылки на русские заголовки README
(`Положите токен`, `Настройка проекта: .ktalk.toml`) внутри английского `onboarding.md` должны
быть обёрнуты в бэктики — `check-prompt-language.sh` ловит голую кириллицу в прозе. Обнаружено
только прогоном `check.sh --fast` после первой правки, не при написании текста.

## Стаб с найденной находкой — AC10-2

`assert_contains_re "AC10-2 (masked failure)" ... "$README" 'код возврата|exit code|get-transcript'`
передаёт в grep переменную `$README`, которая в шапке скрипта объявлена как **путь к файлу**
(`README="$ROOT/README.md"`), не его содержимое — в отличие от соседней проверки AC7-3, которая
корректно берёт `"$(cat "$REGISTRY_SKILL")"`. Ассерт грепает строку `/…/README.md` саму по себе
и не может найти в ней ни «код возврата», ни «get-transcript» ни при каком содержимом файла —
структурно недоказуем этим стабом независимо от текста README. Проверено вручную: искомые оба
литерала в README реально присутствуют (`grep -n "код возврата\|get-transcript" README.md` →
строка 158, раздел «Что нового в пине `ktalk-cli` 2.1.0»). AC10-1 (наличие самого раздела)
проходит корректно — дефект локализован в одной строке AC10-2. Стаб не правился (мандат этой
роли — красный → зелёный через реализацию, не редактирование теста); находка — QA-runner/QA-author.

## Прогоны-доказательства

```
bash scripts/test-session-only-auth.sh → PASS=29 FAIL=1 SKIP=1 (AC10-2 — стаб, см. выше;
                                          AC11-2 — легитимный SKIP по дизайну, вне периметра кода)
bash scripts/check.sh --fast            → passed
bash scripts/check.sh --full            → passed
bash scripts/test-onboard.sh            → PASS: 106  FAIL: 0
bash scripts/test-dual-channel-delivery.sh   → PASS=38 FAIL=0 SKIP=0
bash scripts/test-release-delivery-tails.sh  → PASS=54 FAIL=0 SKIP=3
npx -y @fission-ai/openspec@1.8.0 validate --specs --strict → 12 passed, 0 failed
```
