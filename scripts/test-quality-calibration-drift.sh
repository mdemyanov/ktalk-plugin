#!/usr/bin/env bash
# test-quality-calibration-drift.sh — закрытие трёх пунктов дрейфа REV-002 в
# `openspec/specs/meeting-analysis-quality-calibration/spec.md`, заведённых отдельным долгом
# `ktalk-plugin-109` коммитом 751cc61 (`fix(pairing): сузить три сценария калибровки под
# факт, отметить дрейф в требовании`). DEV-101.
#
# Предмет — ТЕКСТ промт-слоя (references/ktalk-processor/protocol-template.md,
# skills/ktalk-eval/references/eval-rubric.md), не поведение модели: в этом плагине нет
# прикладного кода (ADR-012), поэтому проверяемо наличие и форма предписания, не факт, что
# модель ему следует — тот же жанр, что у scripts/test-agreements-reconciliation.sh
# («проверка предписаний промт-слоя грепом по смыслу»).
#
# Почему отдельная сьюта, а не расширение test-agreements-reconciliation.sh: та сьюта по
# заголовку и содержанию — о шаге 5.5 `agents/ktalk-processor.md` и
# `references/ktalk-processor/vault-update-and-report.md` (сверка «Открытые договорённости»);
# жёстко называет оба пути в переменных PROCESSOR/VAULT_REF. Предмет здесь — три другие,
# не пересекающиеся по файлам свойства (маркировка имён и нулевые решения в
# protocol-template.md, рост счётчиков в eval-rubric.md); смешение раздуло бы чужой файл
# предметом, к которому он не относится.
#
# Каждый ассерт проверен мутацией (см. отчёт задачи DEV-101): временное удаление вписанной
# фразы обязано покраснить соответствующий ассерт, восстановление — вернуть в зелёное.
#
# Прогон: bash scripts/test-quality-calibration-drift.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/references/ktalk-processor/protocol-template.md"
RUBRIC="$ROOT/skills/ktalk-eval/references/eval-rubric.md"

[[ -f "$TEMPLATE" ]] || { echo "ERROR: $TEMPLATE not found" >&2; exit 2; }
[[ -f "$RUBRIC" ]] || { echo "ERROR: $RUBRIC not found" >&2; exit 2; }

PASS=0
FAIL=0

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

echo "== Пункт 1 (REV-002): единообразие маркировки одного имени по документу =="
echo "   ${TEMPLATE#$ROOT/}"

# Каждая проверка ниже — отдельный фрагмент ОДНОЙ строки файла (не составной ERE-паттерн на
# несколько строк подряд): перенос markdown не даёт случайного зелёного (урок 2026-08-29).
assert_contains "AC1-1" \
  "правило единообразия маркировки названо явно" \
  "$TEMPLATE" "Document-wide consistency of one name's marking"
assert_contains "AC1-2" \
  "повторное вхождение несёт закэшированный результат, не свежее независимое решение" \
  "$TEMPLATE" "cached result written again, not a fresh independent decision"
assert_contains "AC1-3" \
  "расхождение маркировки двух вхождений допустимо только с явной причиной в тексте" \
  "$TEMPLATE" "unless the protocol text states an explicit reason"

echo ""
echo "== Пункт 2 (REV-002): явная констатация при decisions_count = 0 =="
echo "   ${TEMPLATE#$ROOT/}"

assert_contains "AC2-1" \
  "правило нулевых решений названо явно" \
  "$TEMPLATE" "Zero decisions:"
assert_contains "AC2-2" \
  "текст протокола прямо констатирует отсутствие решений при decisions_count 0" \
  "$TEMPLATE" "states plainly that no decisions"
assert_contains "AC2-3" \
  "запрет подставлять условную формулировку как решение" \
  "$TEMPLATE" "SHALL NOT be written into the table"

echo ""
echo "== Пункт 3 (REV-002): рост счётчиков между ревизиями сам по себе не дефект =="
echo "   ${RUBRIC#$ROOT/}"

assert_contains "AC3-1" \
  "строка Verification method называет рост счётчиков «не дефект сам по себе»" \
  "$RUBRIC" "not a defect by itself"
assert_contains "AC3-2" \
  "литералы трёх счётчиков присутствуют в той же строке" \
  "$RUBRIC" 'Growth of `decisions_count`/`commitments_count`/`unclear_count`'
assert_contains "AC3-3" \
  "определение дефекта отсылает к §1 Method item 2, не к направлению счётчика" \
  "$RUBRIC" "follows only from §1 Method item 2"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
