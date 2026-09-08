#!/usr/bin/env bash
# test-retired-mode-detection.sh — тест-дизайн QA-001 (ktalk-plugin-swm) для требования
# content/30-requirements/2026-09-08-retired-mode-detection.md, capability
# openspec/specs/session-only-auth/spec.md, три новых `### Requirement:` (строки 155-227 спеки),
# шесть `#### Scenario:`.
#
# AC-1..AC-6 — в порядке появления Scenario в спеке (Requirement 1 несёт два Scenario — AC-1 и
# AC-2; Requirement 3 несёт три Scenario — AC-4, AC-5, AC-6). Нумерация ЛОКАЛЬНА для этого файла
# и этого требования — не продолжает AC-1..AC-11 content/30-requirements/2026-09-07-session-
# only-auth/at-design.md (другой файл, другое требование, собственная приёмочная сводка BA).
# Полная раскладка AC → Scenario → ассерт — content/30-requirements/2026-09-08-retired-mode-
# detection/at-design.md.
#
# РЕШЕНИЕ О РАЗМЕЩЕНИИ: отдельный файл, не блок внутри test-session-only-auth.sh — идиома
# репозитория "один файл на BA-требование, отдельная строка .nauta-gates.yaml"
# (test-dual-channel-delivery.sh, test-release-delivery-tails.sh, test-session-only-auth.sh).
# ОБЯЗАТЕЛЬНОЕ действие Dev: добавить эту строку в .nauta-gates.yaml → projectGates.full — без
# неё зелёный этой сьюты никем не исполняется (находка 2 аудита прошлого эпика, см. отчёт
# задачи QA-001).
#
# Контракт имени JSON-поля НЕ зафиксирован SA (ADR-029 фиксирует решение "не устранять", не имя
# поля report()). Стаб не хардкодит один буквальный литерал: ассерты матчат JSON-ключ,
# содержащий (регистронезависимо) "retired" ИЛИ "personal_key", со значением true/false. Если
# реализация назовёт поле без обеих подстрок — расширь RETIRED_TRUE_RE/RETIRED_FALSE_RE ниже в
# том же коммите, где называешь поле (см. at-design.md, шапка).
#
# Стабы не зовут сеть и не зовут ktalk мутирующими командами — только процессные подмены PATH
# (фиктивный ktalk в mktemp -d) и переменные окружения дочернего вызова
# scripts/ktalk-onboard.sh (диагностика, не мутация системы).
#
# Ни один блок не зовёт exit до итогового — упавший блок не прерывает остальные.
# Прогон: bash scripts/test-retired-mode-detection.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONBOARD_SH="$ROOT/scripts/ktalk-onboard.sh"
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

# assert_not_contains_literal <ac> <desc> <текст> <фиксированная строка>
assert_not_contains_literal() {
  if grep -qF -- "$4" <<<"$3"; then bad "$1" "$2" "найдено дословно"; else ok "$1" "$2"; fi
}

[[ -f "$ONBOARD_SH" ]] || { echo "ERROR: $ONBOARD_SH не найден" >&2; exit 2; }

# Фикстуры — именованные переменные, не литералы присваивания прямо в команде (приём
# EMPTY_FIXTURE="" из content/30-requirements/2026-09-07-session-only-auth/at-design.md,
# AC11-2). Форма "VAR=\"\$FIXTURE\"" безопасна для check-plugin-composition.sh — после
# необязательной кавычки следует "$", исключённый из паттерна "секрет со значением"
# (scripts/check-plugin-composition.sh:60-62).
FIXTURE_KEY_SIMPLE="synthetic-personal-key-rmd-ac"
FIXTURE_KEY_SPECIAL='S3cr#t"value with spaces and $(rm -rf tmp) and `backtick`'
EMPTY_FIXTURE=""

# Регэксп контракта AC-1/AC-3 — см. комментарий об имени поля в шапке файла.
RETIRED_TRUE_RE='"[A-Za-z0-9_]*(retired|personal_key)[A-Za-z0-9_]*"[[:space:]]*:[[:space:]]*true'
RETIRED_FALSE_RE='"[A-Za-z0-9_]*(retired|personal_key)[A-Za-z0-9_]*"[[:space:]]*:[[:space:]]*false'

# Пять операций Requirement 3 — литералы спеки, не сокращённые и не переименованные.
AFFECTED_OPS=(get-room list-calendar create-meeting cancel-meeting search-contacts)

# Фиктивный ktalk, отвечающий на --version версией, не совпадающей с пином compat.json —
# принудительно получаем исход НЕ-ok (outdated, E_OUTDATED=11), нужный AC-1b: поле факта
# обязано появляться не только на ok-исходе.
FAKE_DIR="$(mktemp -d)"
cat > "$FAKE_DIR/ktalk" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then printf 'ktalk-cli 9.9.9\n'; exit 0; fi
exit 1
FAKE
chmod +x "$FAKE_DIR/ktalk"
cleanup() { rm -rf "$FAKE_DIR"; }
trap cleanup EXIT

echo "###############################################################################"
echo "# AC-1 — Requirement: \`check\` detects the retired mode in the process environment"
echo "#         only, never in a file"
echo "# Scenario: The fact is named on every outcome, the value never is"
echo "###############################################################################"

# AC-1a: базовая машина этого дерева сегодня уже совпадает с пином (compat.json ktalk-cli
# 2.1.0) — ok-исход без переменной: поле факта обязано быть false.
unset KTALK_PERSONAL_API_KEY
OUT_1A="$(bash "$ONBOARD_SH" check --json 2>&1)"
assert_contains_re "AC-1a" "поле факта — false на ok-исходе без переменной" \
  "$OUT_1A" "$RETIRED_FALSE_RE"

# AC-1b: тот же факт — но на НЕ-ok исходе (принудительный outdated фиктивным ktalk на PATH),
# плюс boundary-инвариант требования: находка не вытесняет код готовности пакета — код
# возврата остаётся 11 (outdated), не переключается на 14, хотя переменная задана.
OUT_1B="$(PATH="$FAKE_DIR:$PATH" KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SIMPLE" \
          bash "$ONBOARD_SH" check --json 2>&1)"; RC_1B=$?
assert_contains_re "AC-1b" "поле факта — true на НЕ-ok исходе (outdated), не только на ok" \
  "$OUT_1B" "$RETIRED_TRUE_RE"
assert_true "AC-1b (boundary)" \
  "готовность пакета приоритетнее находки — код остаётся 11 (outdated), не 14" \
  "$([[ "$RC_1B" -eq 11 ]] && echo 0 || echo 1)" \
  "код возврата $RC_1B (ожидался 11 — приоритет готовности пакета над кодом 14)"

# AC-1c (malformed/mistyped input — искажённое значение переменной): значение со спецсимволами
# оболочки не попадает в вывод ни в --json, ни в текстовом режиме.
OUT_1C_JSON="$(KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SPECIAL" bash "$ONBOARD_SH" check --json 2>&1)"
OUT_1C_TXT="$(KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SPECIAL" bash "$ONBOARD_SH" check 2>&1)"
assert_not_contains_literal "AC-1c" "значение переменной (со спецсимволами) не в --json" \
  "$OUT_1C_JSON" "$FIXTURE_KEY_SPECIAL"
assert_not_contains_literal "AC-1c-txt" "значение переменной (со спецсимволами) не в тексте" \
  "$OUT_1C_TXT" "$FIXTURE_KEY_SPECIAL"

# AC-1d (masked failure): поле не «залипает» в true — на ok-исходе без переменной регэксп
# true отсутствует (guard против реализации, всегда отвечающей «обнаружено»).
assert_not_contains_re "AC-1d" \
  "поле не 'залипает' в true — на ok-исходе без переменной 'true' не встречается" \
  "$OUT_1A" "$RETIRED_TRUE_RE"

echo "###############################################################################"
echo "# AC-2 — тот же Requirement"
echo "# Scenario: A variable not yet exported into the running session is not reported"
echo "###############################################################################"

# AC-2a: переменная присвоена в РОДИТЕЛЬСКОЙ оболочке БЕЗ export — дочерний check её не
# наследует (POSIX: неэкспортированная переменная не попадает в environ дочернего процесса).
OUT_2A="$( (KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SIMPLE"; bash "$ONBOARD_SH" check --json) 2>&1 )"
assert_contains_re "AC-2a" \
  "не-экспортированная переменная не наследуется дочерним check — поле false" \
  "$OUT_2A" "$RETIRED_FALSE_RE"

# AC-2b (masked failure): .env рабочего каталога с той же переменной НЕ читается — check
# ограничен окружением процесса, не файлами (Requirement, "SHALL NOT read a project .env file").
DOTENV_DIR="$(mktemp -d)"
# Строка .env строится из переменной, не литералом присваивания в исходнике этого файла —
# check-plugin-composition.sh ловит "VAR=<не-$/не-пробел/не-кавычка>" в исходном тексте
# scripts/ (та же ловушка, что дважды поймала BA/координатора, см. шапку файла).
DOTENV_LINE="KTALK_PERSONAL_API_KEY=$FIXTURE_KEY_SIMPLE"
printf '%s\n' "$DOTENV_LINE" > "$DOTENV_DIR/.env"
OUT_2B="$(cd "$DOTENV_DIR" && unset KTALK_PERSONAL_API_KEY && bash "$ONBOARD_SH" check --json 2>&1)"
rm -rf "$DOTENV_DIR"
assert_contains_re "AC-2b" \
  "check не читает .env рабочего каталога — поле остаётся false" \
  "$OUT_2B" "$RETIRED_FALSE_RE"

# AC-2c (malformed/mistyped input — опечатка в имени переменной): KTALK_PERSONAL_APIKEY (без
# подчёркивания перед KEY) не принимается за KTALK_PERSONAL_API_KEY.
OUT_2C="$(KTALK_PERSONAL_APIKEY="$FIXTURE_KEY_SIMPLE" bash "$ONBOARD_SH" check --json 2>&1)"
assert_contains_re "AC-2c" \
  "опечатка в имени переменной не принимается за находку — поле false" \
  "$OUT_2C" "$RETIRED_FALSE_RE"

# AC-2d (boundary — пустое, но экспортированное значение): [ -n "$KTALK_PERSONAL_API_KEY" ]
# (текст требования, раздел «Почему обнаружение — только переменная процесса») не считает
# пустую строку «заданной».
OUT_2D="$(KTALK_PERSONAL_API_KEY="$EMPTY_FIXTURE" bash "$ONBOARD_SH" check --json 2>&1)"
assert_contains_re "AC-2d" \
  "пустое, но экспортированное значение не считается 'заданной' переменной" \
  "$OUT_2D" "$RETIRED_FALSE_RE"

echo "###############################################################################"
echo "# AC-3 — Requirement: Detecting the retired mode is a warning, not a"
echo "#         package-readiness failure"
echo "# Scenario: A correctly installed package with the retired mode set is neither"
echo "#           ok nor a package error"
echo "###############################################################################"

OUT_3A_JSON="$(KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SIMPLE" bash "$ONBOARD_SH" check --json 2>&1)"; RC_3A=$?
assert_true "AC-3a" "код возврата — выделенный 14, не 0(ok) и не код готовности пакета" \
  "$([[ "$RC_3A" -eq 14 ]] && echo 0 || echo 1)" "код возврата $RC_3A (ожидался 14)"

assert_not_contains_re "AC-3b" "статус JSON — не ok и не один из статусов готовности пакета" \
  "$OUT_3A_JSON" \
  '"status"[[:space:]]*:[[:space:]]*"(ok|missing_cli|outdated|missing_uv|wrong_package|identity_unknown)"'

# AC-3c (malformed/mistyped input): искажённое значение переменной классифицировано тем же
# кодом 14, не как внутренняя ошибка (20) и не иначе.
OUT_3C_JSON="$(KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SPECIAL" bash "$ONBOARD_SH" check --json 2>&1)"; RC_3C=$?
assert_true "AC-3c" \
  "искажённое значение переменной классифицировано тем же предупреждающим кодом 14" \
  "$([[ "$RC_3C" -eq 14 ]] && echo 0 || echo 1)" "код возврата $RC_3C (ожидался 14)"

# AC-3d (masked failure): текстовый режим (не только --json) тоже возвращает 14, не
# молчаливый 0 в человекочитаемой ветке.
OUT_3D_TXT="$(KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SIMPLE" bash "$ONBOARD_SH" check 2>&1)"; RC_3D=$?
assert_true "AC-3d" \
  "текстовый режим 'check' тоже возвращает 14, не маскирует находку молчаливым 0" \
  "$([[ "$RC_3D" -eq 14 ]] && echo 0 || echo 1)" "код возврата $RC_3D (ожидался 14, не 0)"

echo "###############################################################################"
echo "# AC-4 — Requirement: The reported message names the affected operations and"
echo "#         the actual remedy"
echo "# Scenario: The message names the affected commands, not a generic warning"
echo "###############################################################################"

OUT_45_TXT="$(KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SIMPLE" bash "$ONBOARD_SH" check 2>&1)"
OUT_45_JSON="$(KTALK_PERSONAL_API_KEY="$FIXTURE_KEY_SIMPLE" bash "$ONBOARD_SH" check --json 2>&1)"

for op in "${AFFECTED_OPS[@]}"; do
  assert_contains_re "AC-4-$op" "сообщение называет операцию $op явно" "$OUT_45_TXT" "$op"
done

# AC-4-json (masked failure): та же специфика — не только человекочитаемый текст, но и поле
# message самого --json (иначе машинный потребитель получил бы обобщённое предупреждение).
assert_contains_re "AC-4-json" \
  "поле message --json тоже называет операции явно, не обобщённо" \
  "$OUT_45_JSON" "get-room"

# Malformed/mistyped input — N/A: сообщение печатает фиксированный список из пяти операций
# спеки независимо от значения переменной, пользовательский ввод здесь не разбирается (см.
# at-design.md, раздел Error cases).

echo "###############################################################################"
echo "# AC-5 — тот же Requirement"
echo "# Scenario: The message names the immediate command and does not claim it is"
echo "#           permanent"
echo "###############################################################################"

assert_contains_re "AC-5a" "сообщение называет именно 'unset KTALK_PERSONAL_API_KEY'" \
  "$OUT_45_TXT" 'unset[[:space:]]+KTALK_PERSONAL_API_KEY'

# AC-5b (masked failure): сообщение явно оговаривает — команда не переживает новую оболочку/
# файл автозапуска/.env; без этой оговорки оператор молчаливо принял бы разовое действие за
# постоянное решение (ADR-029 Д1/Д2).
assert_contains_re "AC-5b" \
  "сообщение оговаривает: команда не переживает новую оболочку/файл автозапуска/.env" \
  "$OUT_45_TXT" \
  '(\.env|автозапуск|новую (обол(о|а)чку|сессию)|new (shell|terminal)|does not survive|не переживёт)'

# Malformed/mistyped input — N/A: та же причина, что AC-4 (см. at-design.md).

echo "###############################################################################"
echo "# AC-6 — тот же Requirement"
echo "# Scenario: The plugin does not name a specific file or edit one"
echo "###############################################################################"

# AC-6a (masked failure): сообщение не называет конкретный файл автозапуска оболочки — не
# «угадывает» местонахождение вместо честного «файл автозапуска, чьё расположение не известно».
assert_not_contains_re "AC-6a" \
  "сообщение не называет конкретный файл автозапуска оболочки" \
  "$OUT_45_TXT" '~/\.(zshenv|zshrc|bashrc|bash_profile|profile)'

assert_not_contains_re "AC-6b" "сообщение не предлагает и не выполняет правку файла" \
  "$OUT_45_TXT" '(отредактиру|правит файл|edit (the|a|this) file|sed -i|>>[[:space:]]*~/)'

# Malformed/mistyped input — N/A: та же причина, что AC-4/AC-5 (см. at-design.md).

echo "###############################################################################"
echo "ИТОГО: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
echo "###############################################################################"

rm -rf "$FAKE_DIR"
trap - EXIT

[[ "$FAIL" -eq 0 ]]
