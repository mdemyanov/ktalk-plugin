#!/usr/bin/env bash
# test-agreements-reconciliation.sh — детерминированные проверки промт-слоя шага 5.5
# `ktalk-processor` (сверка «📝 Открытые договорённости», ktalk-plugin-o9l, QA-001).
#
# Предмет — ТЕКСТ промт-слоя (agents/ktalk-processor.md,
# references/ktalk-processor/vault-update-and-report.md), не поведение модели: здесь нет
# прикладного кода (ADR-012), поэтому что можно проверить скриптом — это наличие и
# форму инструкций, а не факт, что модель им следует. Поведенческие сценарии (молчание
# не акцепт, отбор области, разбор таблицы) закрывают фикстуры из
# content/30-requirements/2026-08-26-agreements-reconciliation/at-design.md — их
# прогоняет человек или QA-runner поверх реального навыка, автоматического ассерта у
# них нет.
#
# На момент написания (до Dev/DEV-001) шаг 5.5 в agents/ktalk-processor.md ещё не
# существует — все проверки ниже КРАСНЫЕ. Это ожидаемо и является контрактом с Dev
# (TDD: red → green).
#
# Прогон: bash scripts/test-agreements-reconciliation.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROCESSOR="$ROOT/agents/ktalk-processor.md"
VAULT_REF="$ROOT/references/ktalk-processor/vault-update-and-report.md"

[[ -f "$PROCESSOR" ]] || { echo "ERROR: $PROCESSOR not found" >&2; exit 2; }
[[ -f "$VAULT_REF" ]] || { echo "ERROR: $VAULT_REF not found" >&2; exit 2; }

PASS=0
FAIL=0

# Секция шага 5.5 нужна ОТДЕЛЬНО от всего файла: шаг 4.5 уже упоминает «угу», «понятно»,
# «смена темы» и т.п. для добавления новых строк (симметрия, которую и должен зеркалить
# шаг 5.5) — проверка по всему файлу дала бы ложный зелёный ДО того, как Dev вставил
# собственный текст шага 5.5. Вырезаем текст между заголовком «### 5.5» и следующим
# заголовком того же уровня («### 6.») и проверяем группу A только по этому куску.
# До Dev секция отсутствует → STEP55 пуст → все проверки группы A закономерно красные.
STEP55_FILE="$(mktemp)"
trap 'rm -f "$STEP55_FILE"' EXIT
awk '/^### 5\.5/{flag=1} /^### 6\./{flag=0} flag' "$PROCESSOR" > "$STEP55_FILE"

assert_contains() { # assert_contains <ac-id> <описание> <файл> <паттерн (fixed string)>
  local ac="$1" desc="$2" file="$3" pattern="$4"
  if grep -qF -- "$pattern" "$file"; then
    echo "  ✓ $ac $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $ac $desc"
    echo "    не найдено в $file: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains_re() { # assert_contains_re <ac-id> <описание> <файл> <ERE-паттерн>
  local ac="$1" desc="$2" file="$3" pattern="$4"
  if grep -qE -- "$pattern" "$file"; then
    echo "  ✓ $ac $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $ac $desc"
    echo "    не найдено в $file (regex): $pattern"
    FAIL=$((FAIL + 1))
  fi
}

assert_order() { # assert_order <ac-id> <описание> <файл> <паттерн-раньше> <паттерн-позже>
  local ac="$1" desc="$2" file="$3" first="$4" second="$5"
  local line_first line_second
  line_first="$(grep -nF -- "$first" "$file" | head -1 | cut -d: -f1)"
  line_second="$(grep -nF -- "$second" "$file" | head -1 | cut -d: -f1)"
  if [[ -n "$line_first" && -n "$line_second" && "$line_first" -lt "$line_second" ]]; then
    echo "  ✓ $ac $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $ac $desc"
    echo "    ожидался порядок «${first} » (строка ${line_first:-нет}) раньше «${second} » (строка ${line_second:-нет})"
    FAIL=$((FAIL + 1))
  fi
}

echo "== Группа A: шаг 5.5 в agents/ktalk-processor.md =="

# Все проверки этого блока (кроме AC-2, которой нужен весь файл для порядка шагов)
# идут по $STEP55_FILE — вырезке секции «### 5.5» — а не по $PROCESSOR целиком. Шаг 4.5
# уже содержит «угу»/«понятно»/«смена темы» для добавления новых строк: проверка по
# всему файлу дала бы ложный зелёный ДО правки Dev. До появления секции 5.5
# $STEP55_FILE пуст — все проверки ниже честно красные.

# AC-1 — Profile has no open-agreements section: отсутствие секции — легитимный
# «шаг неприменим», не ошибка, секция не создаётся.
assert_contains_re "AC-1" \
  "явная пометка: секции нет → шаг неприменим, не ошибка, секция не создаётся" \
  "$STEP55_FILE" \
  "never creates a section|step not applicable"

# AC-2 — Profile has the section: сверка выполняется до добавления новых строк (шаг 6).
assert_contains "AC-2" \
  "шаг 5.5 существует как отдельный подшаг между шагом 5 и шагом 6" \
  "$PROCESSOR" "5.5"
assert_order "AC-2" \
  "шаг 5.5 расположен раньше шага 6 (сверка предшествует добавлению)" \
  "$PROCESSOR" "5.5" "### 6."

# AC-3 — Reconciliation precedes append: два разных Edit, не слияние (привязка к
# контексту сверки/добавления — не любое упоминание «два разных» в файле).
assert_contains_re "AC-3" \
  "инструкция о двух разных Edit для сверки и добавления (не сливаются в одну правку)" \
  "$STEP55_FILE" \
  "two separate[^.]{0,80}(Edit|edit)"

# AC-4 — Explicit execution statement found: статусы и ревизия со ссылкой на протокол.
assert_contains "AC-4" "статус ✅ выполнено упомянут в шаге 5.5" "$STEP55_FILE" "✅ выполнено"
assert_contains "AC-4" "статус ❌ снято упомянут в шаге 5.5" "$STEP55_FILE" "❌ снято"
assert_contains "AC-4" "статус 🔄 в работе упомянут в шаге 5.5" "$STEP55_FILE" "🔄 в работе"
assert_contains "AC-4" "ревизионная клауза ссылается на протокол текущей встречи" \
  "$STEP55_FILE" "ревизия"

# AC-5/AC-6 — молчание не акцепт, симметрия с шагом 4.5, для ЗАКРЫТИЯ строки (текст
# должен быть повторён в шаге 5.5 — зеркалирование, не ссылка «см. шаг 4.5»).
assert_contains "AC-5" "явно перечислена неявная реакция «угу» как не-подтверждение" \
  "$STEP55_FILE" "угу"
assert_contains "AC-5" "явно перечислена неявная реакция «понятно» как не-подтверждение" \
  "$STEP55_FILE" "понятно"
assert_contains "AC-5" "явно перечислена смена темы как не-подтверждение" \
  "$STEP55_FILE" "change of subject"
# Проверка по смыслу, не по дословной фразе: исходная формулировка промта была
# грамматически сломана («это не как отдельное обновление»), и дословный паттерн
# закреплял именно опечатку. Ловим утверждение «это не обновление» в любой
# из естественных форм.
assert_contains_re "AC-6" \
  "явное подтверждение «строка остаётся открытой» не считается отдельным обновлением" \
  "$STEP55_FILE" "not an update"

# AC-7 — Revision line format: шаблон ревизии — 4 столбца, дата/текст не меняются.
assert_contains "AC-7" "маркер ревизионной строки «↳ *ревизия» присутствует" \
  "$STEP55_FILE" "↳ *ревизия"
assert_contains_re "AC-7" \
  "инструкция сохранности исходного текста/даты (не переписывать первые два столбца)" \
  "$STEP55_FILE" \
  "original (date|text)"

# AC-8 — Table parsing tolerates escaped pipes.
assert_contains "AC-8" "контракт разбора: экранированный пайп внутри вики-ссылки" \
  "$STEP55_FILE" '[[путь\|Метка]]'
assert_contains_re "AC-8" \
  "инструкция не делить строку на экранированном обратном слэше перед пайпом" \
  "$STEP55_FILE" \
  "preceded by a backslash"

# AC-9 — Date parsing accepts two accepted formats.
assert_contains "AC-9" "формат даты ДД.ММ.ГГГГ упомянут" "$STEP55_FILE" "ДД.ММ.ГГГГ"
assert_contains "AC-9" "формат даты ГГГГ-ММ-ДД упомянут" "$STEP55_FILE" "ГГГГ-ММ-ДД"

# AC-10 — Bounded reconciliation scope: N=90 дней, критерий ИЛИ (дата / упоминание в транскрипте).
assert_contains "AC-10" "порог N=90 дней зафиксирован литералом" "$STEP55_FILE" "90"
assert_contains_re "AC-10" \
  "критерий отбора — объединение (ИЛИ) даты и упоминания в транскрипте, не пересечение" \
  "$STEP55_FILE" \
  "90[^.]{0,200}(mention|transcript)|(mention|transcript)[^.]{0,200}90"
assert_contains "AC-10" "счётчик «вне области» упомянут в шаге 5.5" "$STEP55_FILE" "вне области"

echo ""
echo "== Группа B: references/ktalk-processor/vault-update-and-report.md =="

# AC-3 (доп.) — «Автоматически» → «Профили участников»: сверка и добавление — два Edit.
assert_contains_re "AC-3" \
  "блок «Профили участников» описывает два отдельных Edit (сверка, затем добавление)" \
  "$VAULT_REF" \
  "first the revision[^.]{0,80}(reconcil|revision)"

# AC-10 (доп.) — место счётчиков «обновлено / вне области» в итоговом отчёте.
assert_contains "AC-10" \
  "формат строки счётчиков сверки в блоке «Автоматически обновлено»" \
  "$VAULT_REF" "вне области"

# AC-11 — Reconciliation outcome is reported: обновлено/вне области различимы,
# отсутствие секции — по конвенции недоступных шагов.
assert_contains "AC-11" \
  "счётчик сверки «обновлено» отделён от счётчика новых строк (не суммируются)" \
  "$VAULT_REF" "сверка договорённостей"
assert_contains_re "AC-11" \
  "секция отсутствует → отчёт помечает шаг «неприменим» по конвенции недоступных шагов" \
  "$VAULT_REF" \
  "сверка договорённостей.{0,20}секци.{0,20}(отсутствует|нет)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
