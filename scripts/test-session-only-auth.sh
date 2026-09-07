#!/usr/bin/env bash
# test-session-only-auth.sh — тест-дизайн QA-001 (ktalk-plugin-6sm) для требования
# content/30-requirements/2026-09-07-session-only-auth.md, capability
# openspec/specs/session-only-auth/spec.md (9 Requirement, 10 Scenario) плюс изменённый
# Scenario «No token value appears in what the plugin controls»
# (openspec/specs/plugin-onboarding-sanctioned-install/spec.md).
#
# AC-1..AC-10 — в порядке появления `#### Scenario:` в session-only-auth/spec.md (Requirement 1
# несёт два Scenario — AC-1 и AC-2). AC-11 — Scenario из plugin-onboarding-sanctioned-install,
# перечисленный в задаче отдельно («Plus изменённый Scenario»). Та же нумерация — AC ID в
# content/30-requirements/2026-09-07-session-only-auth/at-design.md.
#
# ПЕРИМЕТР литерала KTALK_PERSONAL_API_KEY (Д5 ADR-028, дословно = периметр Scenario «No
# prompt-layer file names the retired mode as supported»): README.md, references/, skills/,
# agents/, commands/. scripts/, content/, openspec/ — вне периметра (scripts/ких диагностирует
# факт легитимно; content/openspec обязаны цитировать литерал как факт о коде пакета). AC-1/AC-4/
# AC-6 сканируют РОВНО этот периметр, не всё дерево — иначе стаб поймал бы собственные артефакты
# этого же эпика (content/, openspec/, RES-001) и вынес бы неверный вердикт по причине, не
# относящейся к предмету.
#
# Стабы не зовут сеть и не зовут `ktalk` мутирующими командами — только чтение файлов дерева и
# один локальный вызов scripts/ktalk-onboard.sh (диагностика, не мутация системы).
#
# Ни один блок не зовёт `exit` до итогового — упавший блок не прерывает остальные.
# Прогон: bash scripts/test-session-only-auth.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

ok()      { PASS=$((PASS + 1)); printf '  ✓ %s %s\n' "$1" "$2"; }
bad()     { FAIL=$((FAIL + 1)); printf '  ✗ %s %s\n' "$1" "$2"; [[ -n "${3:-}" ]] && printf '      %s\n' "$3"; }
skip_ac() { SKIP=$((SKIP + 1)); printf '  ⋯ %s %s\n' "$1" "$2"; [[ -n "${3:-}" ]] && printf '      %s\n' "$3"; }

# assert_true <ac> <desc> <0=условие выполнено/1=нарушение> [причина]
assert_true() { if [[ "$3" == "0" ]]; then ok "$1" "$2"; else bad "$1" "$2" "${4:-}"; fi; }

# assert_contains_re <ac> <desc> <текст> <ERE>
assert_contains_re() {
  if grep -qE -- "$4" <<<"$3"; then ok "$1" "$2"; else bad "$1" "$2" "не найдено (regex): $4"; fi
}

# assert_not_contains_re <ac> <desc> <текст> <ERE>
assert_not_contains_re() {
  if grep -qE -- "$4" <<<"$3"; then bad "$1" "$2" "найдено (не должно быть, regex): $4"; else ok "$1" "$2"; fi
}

README="$ROOT/README.md"
ONBOARDING="$ROOT/references/onboarding.md"
REGISTRY_SKILL="$ROOT/skills/ktalk-registry/SKILL.md"
MEETINGS_SKILL="$ROOT/skills/ktalk-meetings/SKILL.md"
ONBOARD_SH="$ROOT/scripts/ktalk-onboard.sh"

for f in "$README" "$ONBOARDING" "$REGISTRY_SKILL" "$MEETINGS_SKILL" "$ONBOARD_SH"; do
  [[ -f "$f" ]] || { echo "ERROR: $f не найден" >&2; exit 2; }
done

# Периметр Д5 ADR-028 — только эти пять точек (README.md как файл, остальные — каталоги целиком).
PERIPHERY_FILES=("$README")
while IFS= read -r -d '' f; do PERIPHERY_FILES+=("$f"); done < <(
  find "$ROOT/references" "$ROOT/skills" "$ROOT/agents" "$ROOT/commands" -type f -print0 2>/dev/null
)

# Секция README «3. Положите токен» (шаг настройки токена + гид на отказ авторизации).
README_STEP3="$(sed -n '/^### 3\. Положите токен/,/^### 4\. Укажите адрес пространства/p' "$README")"

# Секция onboarding.md «## Authorisation» — последний заголовок файла, до EOF.
ONBOARD_AUTH="$(sed -n '/^## Authorisation/,$p' "$ONBOARDING")"

# Строка(и) onboarding.md, голо упоминающие `.ktalk.toml`, с одной строкой контекста сверху.
ONBOARD_TOML_MENTION="$(grep -B1 -F '.ktalk.toml' "$ONBOARDING")"

# Секция meetings SKILL.md «## Failure diagnostics» (до следующего «## »).
MEETINGS_FAILURE="$(sed -n '/^## Failure diagnostics/,/^## Schedule/p' "$MEETINGS_SKILL")"

# Секция meetings SKILL.md «## Related commands» — последний заголовок файла, до EOF.
MEETINGS_RELATED="$(sed -n '/^## Related commands/,$p' "$MEETINGS_SKILL")"

# Строка registry SKILL.md, описывающая форму вывода `ktalk dashboard --json`.
REGISTRY_DASHBOARD_LINE="$(grep -F 'Output: `{"new"' "$REGISTRY_SKILL")"

echo "###############################################################################"
echo "# AC-1 — Requirement: The prompt layer declares exactly one supported authorisation mode"
echo "# Scenario: No prompt-layer file names the retired mode as supported"
echo "###############################################################################"

# AC1-1: блочный запрет литерала во всём периметре Д5 (не во всём дереве — content/openspec
# легитимно цитируют его как факт о коде пакета, scripts/ легитимно диагностирует его наличие).
AC1_HITS="$(grep -nF 'KTALK_PERSONAL_API_KEY' "${PERIPHERY_FILES[@]}" 2>/dev/null || true)"
if [[ -z "$AC1_HITS" ]]; then
  ok "AC1-1" "литерал KTALK_PERSONAL_API_KEY отсутствует в периметре (README.md, references/, skills/, agents/, commands/)"
else
  bad "AC1-1" "литерал KTALK_PERSONAL_API_KEY отсутствует в периметре" "найдено:
$AC1_HITS"
fi

# AC1-2 (masked failure): даже если литерал переписан в описательную фразу («выпустите
# личный/персональный API-ключ»/«issue a personal API key»), рекомендация не должна остаться —
# guard на голый литерал молча пропустил бы такую перефразировку.
AC1_PARAPHRASE="$(grep -niE -- 'персональн\w* +api-?ключ|личн\w* +api-?ключ|personal +api +key' "${PERIPHERY_FILES[@]}" 2>/dev/null || true)"
if [[ -z "$AC1_PARAPHRASE" ]]; then
  ok "AC1-2 (masked failure)" "нет описательной рекомендации личного ключа без литерала"
else
  bad "AC1-2 (masked failure)" "нет описательной рекомендации личного ключа без литерала" "найдено:
$AC1_PARAPHRASE"
fi

echo "###############################################################################"
echo "# AC-2 — Requirement: The prompt layer declares exactly one supported authorisation mode"
echo "# Scenario: The authorisation section names one mode, not a priority between two"
echo "###############################################################################"

# AC2-1: секция Authorisation onboarding.md не формулирует правило приоритета между двумя режимами.
assert_not_contains_re "AC2-1" "секция Authorisation не формулирует правило приоритета между режимами" \
  "$ONBOARD_AUTH" 'wins|both are set|приоритет'

# AC2-2 (masked failure — структурный guard): секция называет РОВНО один режим бюллетом, а не два
# (просто убрать предложение о приоритете и оставить оба бюллета — тоже нарушение «exactly one»).
AUTH_MODE_BULLETS="$(grep -cE '^- `KTALK_(SESSION_TOKEN|PERSONAL_API_KEY)`' <<<"$ONBOARD_AUTH" || true)"
assert_true "AC2-2 (masked failure)" "секция Authorisation перечисляет ровно один режим бюллетом (найдено: $AUTH_MODE_BULLETS)" \
  "$([[ "$AUTH_MODE_BULLETS" == "1" ]] && echo 0 || echo 1)" \
  "ожидался 1 бюллет с режимом, найдено $AUTH_MODE_BULLETS"

echo "###############################################################################"
echo "# AC-3 — Requirement: The instruction names the token file as a legitimate holder of the value"
echo "# Scenario: The token file is named alongside the environment variable"
echo "###############################################################################"

# AC3-1: README, шаг 3 — самодостаточен (Д2 ADR-028): называет И файл, И переменную окружения
# как место значения, не только файл.
assert_contains_re "AC3-1a" "README шаг 3 называет файл токена" "$README_STEP3" '~/\.config/ktalk-mcp/token'
assert_contains_re "AC3-1b" "README шаг 3 называет переменную окружения (KTALK_SESSION_TOKEN) как альтернативный носитель" \
  "$README_STEP3" 'KTALK_SESSION_TOKEN'

# AC3-2: onboarding.md, секция Authorisation — тоже самодостаточна: называет И файл, И переменную.
assert_contains_re "AC3-2a" "onboarding.md Authorisation называет переменную окружения" "$ONBOARD_AUTH" 'KTALK_SESSION_TOKEN'
assert_contains_re "AC3-2b" "onboarding.md Authorisation называет файл токена" "$ONBOARD_AUTH" '~/\.config/ktalk-mcp/token'

# AC3-3 (masked failure): файл не должен быть представлен «резервом», низведённым ниже переменной
# условной оговоркой («если переменная не задана/недоступна») — тогда он не «наравне».
assert_not_contains_re "AC3-3 (masked failure)" "файл токена не подан условной оговоркой-резервом относительно переменной" \
  "$README_STEP3
$ONBOARD_AUTH" 'если.{0,25}(переменн|не задан).{0,25}(файл|token)'

echo "###############################################################################"
echo "# AC-4 — Requirement: The instruction names the actual command that writes the token file"
echo "# Scenario: The named command exists and matches the CLI"
echo "###############################################################################"

# AC4-1: во всём периметре Д5 не названо ни одной несуществующей команды (`ktalk session ...`).
AC4_GHOST="$(grep -nE -- 'ktalk[[:space:]]+session([[:space:]]|$)' "${PERIPHERY_FILES[@]}" 2>/dev/null || true)"
if [[ -z "$AC4_GHOST" ]]; then
  ok "AC4-1" "несуществующая команда 'ktalk session' нигде в периметре не названа"
else
  bad "AC4-1" "несуществующая команда 'ktalk session' нигде в периметре не названа" "найдено:
$AC4_GHOST"
fi

# AC4-2: README шаг 3 называет ровно `ktalk token set -` как команду записи.
assert_contains_re "AC4-2" "README шаг 3 называет команду 'ktalk token set -'" "$README_STEP3" 'ktalk token set -'

# AC4-3 (masked failure — самодостаточность Д2): onboarding.md называет ТУ ЖЕ команду сам, а не
# отсылкой «см. README» — иначе точка входа «повторный онбординг» не самодостаточна.
assert_contains_re "AC4-3 (masked failure)" "onboarding.md Authorisation сам называет команду 'ktalk token set -' (не отсылкой)" \
  "$ONBOARD_AUTH" 'ktalk token set -'

echo "###############################################################################"
echo "# AC-5 — Requirement: Authorisation-failure guidance points to a single remedy"
echo "# Scenario: Failure guidance names one path forward"
echo "###############################################################################"

# AC5-1: README шаг 3 (текст об истечении токена) не предлагает личный ключ как альтернативу.
assert_not_contains_re "AC5-1" "README, гид при истечении токена, не предлагает личный ключ" \
  "$README_STEP3" 'персональн\w* +api-?ключ|API_KEY|API-ключ'

# AC5-2: тот же текст называет обновление файла токена единственным путём исправления.
assert_contains_re "AC5-2" "README, гид при истечении токена, называет 'ktalk token set -' путём исправления" \
  "$README_STEP3" 'ktalk token set -'

# AC5-3 (masked failure — регресс-guard соседнего файла): failure diagnostics ktalk-meetings тоже
# не должен внезапно предложить личный ключ как альтернативу auth-status.
assert_not_contains_re "AC5-3 (masked failure)" "Failure diagnostics ktalk-meetings не предлагает личный ключ" \
  "$MEETINGS_FAILURE" 'PERSONAL_API_KEY|персональн\w* +api-?ключ|personal +api +key'

echo "###############################################################################"
echo "# AC-6 — Requirement: Operations without a session profile are not offered"
echo "# Scenario: Command tables do not list an operation with no session profile"
echo "###############################################################################"

# AC6-1: list-archive не документирован как доступная операция нигде в периметре Д5.
AC6_LIST_ARCHIVE="$(grep -niE -- 'list-archive' "${PERIPHERY_FILES[@]}" 2>/dev/null || true)"
if [[ -z "$AC6_LIST_ARCHIVE" ]]; then
  ok "AC6-1" "'list-archive' не документирован нигде в периметре"
else
  bad "AC6-1" "'list-archive' не документирован нигде в периметре" "найдено:
$AC6_LIST_ARCHIVE"
fi

# AC6-2: отчёт по участникам (participants-report) не документирован как доступная операция.
AC6_PART_REPORT="$(grep -niE -- 'participants-report|отчёт по участникам|отчет по участникам' "${PERIPHERY_FILES[@]}" 2>/dev/null || true)"
if [[ -z "$AC6_PART_REPORT" ]]; then
  ok "AC6-2" "отчёт по участникам не документирован нигде в периметре"
else
  bad "AC6-2" "отчёт по участникам не документирован нигде в периметре" "найдено:
$AC6_PART_REPORT"
fi

# AC6-3 (masked failure — near-miss написание): будущая правка не должна проскользнуть под
# альтернативным написанием того же имени (подчёркивание вместо дефиса, обратный порядок слов).
AC6_NEAR_MISS="$(grep -niE -- 'list_archive|archive-list|archive_list' "${PERIPHERY_FILES[@]}" 2>/dev/null || true)"
if [[ -z "$AC6_NEAR_MISS" ]]; then
  ok "AC6-3 (masked failure)" "near-miss написание list-archive тоже отсутствует"
else
  bad "AC6-3 (masked failure)" "near-miss написание list-archive тоже отсутствует" "найдено:
$AC6_NEAR_MISS"
fi

echo "###############################################################################"
echo "# AC-7 — Requirement: The registry dashboard's output shape is documented completely"
echo "# Scenario: The documented shape names all three top-level keys"
echo "###############################################################################"

# AC7-1: строка «Output: ...» называет last_synced как ключ (не только new/stats).
assert_contains_re "AC7-1" "описание вывода 'ktalk dashboard --json' называет last_synced" \
  "$REGISTRY_DASHBOARD_LINE" 'last_synced'

# AC7-2 (masked failure — позиция ключа): если last_synced появится, он обязан быть ВЕРХНЕГО
# уровня, не вложен внутрь описания "stats": {...} — иначе буквальное совпадение по литералу
# прошло бы, а контракт («не внутри stats») остался бы нарушен. Недоказуемо, пока литерала нет.
if [[ "$REGISTRY_DASHBOARD_LINE" != *"last_synced"* ]]; then
  skip_ac "AC7-2 (masked failure)" "last_synced — ключ ВЕРХНЕГО уровня, не вложен в stats" \
    "недоказуемо: литерал last_synced ещё не появился в строке (см. AC7-1)"
else
  STATS_INNER="$(sed -E 's/.*"stats":\s*\{([^}]*)\}.*/\1/' <<<"$REGISTRY_DASHBOARD_LINE")"
  assert_not_contains_re "AC7-2 (masked failure)" "last_synced — ключ ВЕРХНЕГО уровня, не вложен в stats" \
    "$STATS_INNER" 'last_synced'
fi

# AC7-3 (boundary): текст называет обе формы значения — дата-строка ИЛИ null (не только одну).
if [[ "$REGISTRY_DASHBOARD_LINE" != *"last_synced"* ]]; then
  skip_ac "AC7-3 (boundary)" "текст называет обе формы значения last_synced (дата-строка / null)" \
    "недоказуемо: литерал last_synced ещё не появился в строке (см. AC7-1)"
else
  assert_contains_re "AC7-3 (boundary)" "текст называет обе формы значения last_synced (дата-строка / null)" \
    "$(cat "$REGISTRY_SKILL")" 'last_synced.{0,80}null|null.{0,80}last_synced'
fi

echo "###############################################################################"
echo "# AC-8 — Requirement: The meetings skill points to where recording commands are documented"
echo "# Scenario: A reader looking for a recording command is redirected, not left empty-handed"
echo "###############################################################################"

# AC8-1: секция «Related commands» ktalk-meetings называет или указывает на ktalk-registry
# (или на конкретную команду записей: list-recordings/get-transcript/get-summary).
assert_contains_re "AC8-1" "'Related commands' указывает на ktalk-registry или команды записей" \
  "$MEETINGS_RELATED" 'ktalk-registry|list-recordings|get-transcript|get-summary'

# AC8-2 (masked failure — конкретность указателя): указатель не должен быть расплывчатым
# («смотрите другие навыки» без имени) — недоказуемо, пока указателя нет вовсе (см. AC8-1).
if grep -qE 'ktalk-registry|list-recordings|get-transcript|get-summary' <<<"$MEETINGS_RELATED"; then
  assert_not_contains_re "AC8-2 (masked failure)" "указатель называет конкретный навык/файл, не расплывчатую фразу" \
    "$MEETINGS_RELATED" 'смотрите (другие|остальные) навыки|see other skills'
else
  skip_ac "AC8-2 (masked failure)" "указатель называет конкретный навык/файл, не расплывчатую фразу" \
    "недоказуемо: указатель отсутствует вовсе (см. AC8-1)"
fi

echo "###############################################################################"
echo "# AC-9 — Requirement: A bare cross-file mention of .ktalk.toml names where it is explained"
echo "# Scenario: The onboarding mention of .ktalk.toml points to its explanation"
echo "###############################################################################"

# AC9-1: голое упоминание `.ktalk.toml` в onboarding.md называет README (файл-носитель объяснения).
assert_contains_re "AC9-1" "упоминание .ktalk.toml в onboarding.md называет README" \
  "$ONBOARD_TOML_MENTION" 'README'

# AC9-2 (masked failure — конкретность указателя): указатель называет ИМЕННО раздел объяснения
# («Настройка проекта»), а не только слово «README» без адреса внутри файла (расплывчато).
assert_contains_re "AC9-2 (masked failure)" "указатель называет раздел README ('Настройка проекта'), не только слово README" \
  "$ONBOARD_TOML_MENTION" 'Настройка проекта|#.*ktalk-toml|README\.md#'

echo "###############################################################################"
echo "# AC-10 — Requirement: README names the operator-visible novelties of the pinned CLI version"
echo "# Scenario: README names what changed in the pinned version"
echo "###############################################################################"

# AC10-1: README несёт раздел, называющий изменения текущего пина ktalk-cli (не только номер).
AC10_SECTION="$(grep -niE -- '## .*(что нового|новое в|изменени|changed in|novelt)' "$README" || true)"
if [[ -n "$AC10_SECTION" ]]; then
  ok "AC10-1" "README несёт раздел о новизне текущего пина ktalk-cli"
else
  bad "AC10-1" "README несёт раздел о новизне текущего пина ktalk-cli" "заголовок раздела не найден"
fi

# AC10-2 (masked failure — конкретность): раздел, если появится, обязан называть КОНКРЕТНОЕ
# изменение (например, код возврата 3 у get-transcript), не только повторять номер версии.
if [[ -z "$AC10_SECTION" ]]; then
  skip_ac "AC10-2 (masked failure)" "раздел называет конкретное изменение, не только номер версии" \
    "недоказуемо: раздел о новизне ещё не существует (см. AC10-1)"
else
  assert_contains_re "AC10-2 (masked failure)" "раздел называет конкретное изменение, не только номер версии" \
    "$README" 'код возврата|exit code|get-transcript'
fi

echo "###############################################################################"
echo "# AC-11 — plugin-onboarding-sanctioned-install (изменённый Scenario)"
echo "# Scenario: No token value appears in what the plugin controls"
echo "###############################################################################"

# AC11-1 (malformed/mistyped value — значение с спецсимволами оболочки): ktalk-onboard.sh check
# и check --json никогда не печатают значение токена, даже когда оно содержит кавычки/пробелы/
# перевод строки — не только «чистое» синтетическое значение, как в существующем
# scripts/test-onboard.sh:26 (там проверен только install/install --json, не check).
FIXTURE_TOKEN='SYNTH"TOKEN with spaces and $(danger)'
OUT_CHECK="$(KTALK_SESSION_TOKEN="$FIXTURE_TOKEN" KTALK_PERSONAL_API_KEY="$FIXTURE_TOKEN" \
             bash "$ONBOARD_SH" check 2>&1 || true)"
if grep -qF "$FIXTURE_TOKEN" <<<"$OUT_CHECK"; then
  bad "AC11-1a" "значение токена (со спецсимволами) не попадает в вывод 'check'" "найдено дословно в выводе"
else
  ok "AC11-1a" "значение токена (со спецсимволами) не попадает в вывод 'check'"
fi
OUT_CHECK_JSON="$(KTALK_SESSION_TOKEN="$FIXTURE_TOKEN" KTALK_PERSONAL_API_KEY="$FIXTURE_TOKEN" \
                  bash "$ONBOARD_SH" check --json 2>&1 || true)"
if grep -qF "$FIXTURE_TOKEN" <<<"$OUT_CHECK_JSON"; then
  bad "AC11-1b" "значение токена (со спецсимволами) не попадает в вывод 'check --json'" "найдено дословно в выводе"
else
  ok "AC11-1b" "значение токена (со спецсимволами) не попадает в вывод 'check --json'"
fi

# AC11-2 (masked failure — граничное значение): переменная задана ПУСТОЙ строкой — check не
# обязан отчитываться о токене вовсе (RES-001/onboard.sh сегодня не проверяют токен), но ЕСЛИ
# когда-нибудь начнёт — пустая строка не должна маскированно засчитаться как «задано». Сегодня
# ktalk-onboard.sh не содержит логики токена вовсе — предмет недоказуем на этом уровне.
if grep -q 'token' "$ONBOARD_SH"; then
  EMPTY_FIXTURE=""
  OUT_EMPTY="$(KTALK_SESSION_TOKEN="$EMPTY_FIXTURE" bash "$ONBOARD_SH" check --json 2>&1 || true)"
  assert_not_contains_re "AC11-2 (masked failure)" "пустая строка не засчитана как 'токен задан'" \
    "$OUT_EMPTY" '"token"[^}]*"set"[^}]*true'
else
  skip_ac "AC11-2 (masked failure)" "пустая строка не засчитана как 'токен задан'" \
    "ktalk-onboard.sh check вообще не отчитывается о состоянии токена — вне периметра этого стаба; см. 'Не покрывается'"
fi

# AC11-3: промт-слой явно гарантирует, что значение никогда не печатается и не запрашивается в чат.
assert_contains_re "AC11-3" "onboarding.md явно гарантирует непечать/незапрос значения токена" \
  "$(cat "$ONBOARDING")" 'never print|never.{0,20}ask.{0,20}token|Token values are never'

echo "###############################################################################"
echo "ИТОГО: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
echo "###############################################################################"

[[ "$FAIL" -eq 0 ]]
