#!/usr/bin/env bash
# Тест-дизайн QA-001 (ktalk-plugin-56l.17): наблюдаемые исходы ADR-023 — переезд четырёх
# требований плагина из дерева пакета, пять новых capability на плагинной стороне.
# Прогон ручной: bash scripts/test-plugin-requirements-relocation.sh
#
# Предмет эпика — документы и гейты, не код: "падающий тест" здесь означает прогон
# scripts/check.sh / grep по дереву с ненулевым кодом СЕЙЧАС. REL-1 сегодня зелёный по
# построению — regression guard (fast уже Errors: 0 в этом дереве до всякого DEV-001),
# не пропущенный дефект (тот же приём, что тест 45 cli-only-boundary/at-design.md).
#
# Источник контракта: content/00-project/adr/ADR-023-plugin-requirements-relocation.md,
# content/40-architecture/2026-08-31-plugin-requirements-relocation.md (migration map,
# naming/layout decision, «Три пересечения», «Contract with QA-author»).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

check_true() { # check_true <условие 0=ок/1=нарушение> <название>
  if [ "$1" = "0" ]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$2"
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$2"; fi
}

check_eq() { # check_eq <ожидание> <факт> <название>
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$3"
  else FAIL=$((FAIL+1)); printf 'FAIL %s: ожидалось "%s", получено "%s"\n' "$3" "$1" "$2"; fi
}

# check_capability_line <файл> <csv ожидаемых slug'ов> <тест-имя>
# Покрывает все 4 исхода check_capability_link (validate-content.py:954-1000):
#   A) строки нет; B) строка без путей; C) путь не формы openspec/specs/<slug>/spec.md;
#   D) путь той формы, файла нет.
check_capability_line() {
  local file="$1" expected_csv="$2" name="$3"
  if [ ! -f "$file" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL %s: файла требования ещё нет (%s) — DEV-001 не выполнен\n' "$name" "$file"; return
  fi
  local line
  line="$(grep -m1 '\*\*Capability:\*\*' "$file" || true)"
  if [ -z "$line" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL %s: строки **Capability:** нет [исход A]\n' "$name"; return
  fi
  local paths
  paths="$(printf '%s\n' "$line" | grep -oE 'openspec/specs/[^`, ]+' || true)"
  if [ -z "$paths" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL %s: строка есть, ни одного пути [исход B]\n' "$name"; return
  fi
  local p bad_form=0 dangling=0
  for p in $paths; do
    if ! [[ "$p" =~ ^openspec/specs/[a-z0-9-]+/spec\.md$ ]]; then bad_form=1; fi
    if [ ! -f "$ROOT/$p" ]; then dangling=1; fi
  done
  check_true "$bad_form" "$name: все пути формы openspec/specs/<slug>/spec.md [исход C]"
  check_true "$dangling" "$name: все объявленные спеки существуют на диске [исход D]"
  local got want
  got="$(printf '%s\n' $paths | sed -E 's#openspec/specs/([a-z0-9-]+)/spec\.md#\1#' | sort | paste -sd, -)"
  want="$(printf '%s\n' "$expected_csv" | tr ',' '\n' | sort | paste -sd, -)"
  check_eq "$want" "$got" "$name: набор capability совпадает с migration map"
}

echo "== REL-1 (regression guard): check.sh --fast -> Errors: 0 =="
FAST_OUT="$("$ROOT/scripts/check.sh" --fast 2>&1)"
FAST_ERR_LINE="$(printf '%s\n' "$FAST_OUT" | grep -E '^Errors: ' | tail -1)"
FAST_ERR_COUNT="$(printf '%s\n' "$FAST_ERR_LINE" | grep -oE 'Errors: [0-9]+' | grep -oE '[0-9]+')"
check_eq "0" "${FAST_ERR_COUNT:-unknown}" "REL-1 validate-content.py: 0 ошибок (уже верно сегодня, держится через DEV-001)"

echo "== REL-2: check.sh --full -> exit 0 =="
"$ROOT/scripts/check.sh" --full >/tmp/rel2-full.log 2>&1
check_eq "0" "$?" "REL-2 check.sh --full завершается кодом 0 (сегодня падает на id-check.sh: 'adr' highwater устарел после ADR-023)"

echo "== REL-3/4/5: четыре переселенца — присутствие, Audience, Capability (4 исхода) =="
check_capability_line "$ROOT/content/30-requirements/2026-08-18-meetings-prompt-surface.md" \
  "meetings-prompt-surface-reads,meeting-write-sanction-workflow" "REL-5 meetings-prompt-surface"
check_capability_line "$ROOT/content/30-requirements/2026-08-18-onboarding-sanctioned-install.md" \
  "plugin-onboarding-sanctioned-install" "REL-5 onboarding-sanctioned-install"
check_capability_line "$ROOT/content/30-requirements/2026-08-19-analysis-quality-calibration.md" \
  "meeting-analysis-quality-calibration" "REL-5 analysis-quality-calibration"
check_capability_line "$ROOT/content/30-requirements/2026-08-19-prompt-defect-channel.md" \
  "prompt-defect-channel" "REL-5 prompt-defect-channel"

for f in 2026-08-18-meetings-prompt-surface.md 2026-08-18-onboarding-sanctioned-install.md \
         2026-08-19-analysis-quality-calibration.md 2026-08-19-prompt-defect-channel.md; do
  path="$ROOT/content/30-requirements/$f"
  if [ -f "$path" ] && grep -q 'value: \[Internal\]' "$path"; then
    PASS=$((PASS+1)); printf 'ok   REL-4 %s несёт Audience: [Internal]\n' "$f"
  else
    FAIL=$((FAIL+1)); printf 'FAIL REL-4 %s не несёт Audience: [Internal] (или файла ещё нет) — C4/C5\n' "$f"
  fi
done

echo "== REL-6: пять файлов openspec/specs/<capability>/spec.md существуют =="
for c in meetings-prompt-surface-reads meeting-write-sanction-workflow \
         plugin-onboarding-sanctioned-install meeting-analysis-quality-calibration \
         prompt-defect-channel; do
  if [ -f "$ROOT/openspec/specs/$c/spec.md" ]; then
    PASS=$((PASS+1)); printf 'ok   REL-6 %s\n' "$c"
  else
    FAIL=$((FAIL+1)); printf 'FAIL REL-6 openspec/specs/%s/spec.md отсутствует\n' "$c"
  fi
done

echo "== REL-7 (masked failure): cli-only-boundary Req.2 расширена, не продублирована =="
CLI_SPEC="$ROOT/openspec/specs/cli-only-boundary/spec.md"
MEETINGS_SPEC="$ROOT/openspec/specs/meetings-prompt-surface-reads/spec.md"
if [ ! -f "$MEETINGS_SPEC" ]; then
  FAIL=$((FAIL+1)); printf 'FAIL REL-7 meetings-prompt-surface-reads/spec.md ещё не существует\n'
else
  if grep -qi 'no mcp\|mcp interface\|declares no mcp' "$MEETINGS_SPEC"; then
    FAIL=$((FAIL+1)); printf 'FAIL REL-7 meetings-prompt-surface-reads дублирует сценарий "нет MCP" вместо ссылки на cli-only-boundary (ADR-023 Д3) — masked failure: молчаливый дубль контракта\n'
  else
    PASS=$((PASS+1)); printf 'ok   REL-7a meetings-prompt-surface-reads не заводит свой сценарий "нет MCP"\n'
  fi
fi
# Механический прокси, не доказательство семантики (архитектурная статья, «Edge cases»:
# «проверка — сравнение текста Requirement до/после правки, не только наличие новой
# строки»). BASELINE_SHA — хэш нормативного абзаца ДО правки Д3, снят на дату этого
# тест-дизайна (2026-08-31, коммит ADR-023 ещё не внёс изменений в spec.md). Тест: (а) хэш
# обязан ИЗМЕНИТЬСЯ (что-то реально тронуто, не молчаливый no-op), (б) новый текст обязан
# упоминать промт-текст ЛЮБОГО skill/agent/command, не только декларацию/`.mcp.json` —
# ключевые слова ниже НЕ доказывают достаточность обобщения, это остаётся ручным ревью
# (тот же класс ограничения, что и «Известное ограничение» теста 46 cli-only-boundary/at-design.md).
BASELINE_SHA="55f07d603585c1137f5aa64f801bb048a0fbabfbe6422d9857ddf78db4b95201"
if [ ! -f "$CLI_SPEC" ]; then
  FAIL=$((FAIL+1)); printf 'FAIL REL-7b cli-only-boundary/spec.md отсутствует\n'
else
  PARA="$(awk '/^### Requirement: The plugin declares no MCP interface surface/{f=1;next} /^#### Scenario:/{if(f){exit}} f' "$CLI_SPEC")"
  LIVE_SHA="$(printf '%s' "$PARA" | shasum -a 256 | cut -c1-64)"
  if [ "$LIVE_SHA" = "$BASELINE_SHA" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL REL-7b нормативный абзац второй Requirement не менялся с baseline — Д3 ещё не выполнено\n'
  elif printf '%s' "$PARA" | grep -qiE 'skill|agent|command'; then
    PASS=$((PASS+1)); printf 'ok   REL-7b абзац изменён и упоминает промт-слой (skill/agent/command) — семантическая достаточность остаётся ручным ревью\n'
  else
    FAIL=$((FAIL+1)); printf 'FAIL REL-7b абзац изменён, но не упоминает ни skill, ни agent, ни command — вряд ли обобщает промт-текст\n'
  fi
fi

echo "== REL-8 (masked failure): спека онбординга не наследует устаревший AC-язык дословно =="
ONBOARD_SPEC="$ROOT/openspec/specs/plugin-onboarding-sanctioned-install/spec.md"
if [ ! -f "$ONBOARD_SPEC" ]; then
  FAIL=$((FAIL+1)); printf 'FAIL REL-8 plugin-onboarding-sanctioned-install/spec.md ещё не существует\n'
else
  if grep -q 'uv tool install ktalk-mcp$' "$ONBOARD_SPEC" || grep -qi 'не ниже минимал' "$ONBOARD_SPEC"; then
    FAIL=$((FAIL+1)); printf 'FAIL REL-8 спека онбординга наследует устаревший AC-язык источника дословно (без версии / язык порога) — ADR-023 таблица "Три пересечения" п.1\n'
  else
    PASS=$((PASS+1)); printf 'ok   REL-8 спека онбординга не содержит устаревшие формулировки источника\n'
  fi
fi

echo "== REL-9: content/30-requirements/_index.md регистрирует 4 новых пункта =="
IDX="$ROOT/content/30-requirements/_index.md"
for f in 2026-08-18-meetings-prompt-surface.md 2026-08-18-onboarding-sanctioned-install.md \
         2026-08-19-analysis-quality-calibration.md 2026-08-19-prompt-defect-channel.md; do
  if grep -q "($f)" "$IDX"; then
    PASS=$((PASS+1)); printf 'ok   REL-9 %s зарегистрирован в _index.md\n' "$f"
  else
    FAIL=$((FAIL+1)); printf 'FAIL REL-9 %s не зарегистрирован в _index.md\n' "$f"
  fi
done

echo "== REL-10: ни один из 4 файлов не осиротел (C10) — есть входящая ссылка помимо _index.md =="
# C10 не считает self-ссылку и ссылку из СВОЕГО _index.md входящей отдельно не исключает,
# но заведомо не-сирота: файл, на который есть ссылка из ADR-023/companion-статьи.
ARCH="$ROOT/content/40-architecture/2026-08-31-plugin-requirements-relocation.md"
for f in 2026-08-18-meetings-prompt-surface.md 2026-08-18-onboarding-sanctioned-install.md \
         2026-08-19-analysis-quality-calibration.md 2026-08-19-prompt-defect-channel.md; do
  if [ -f "$ROOT/content/30-requirements/$f" ]; then
    if grep -q "$f" "$IDX" "$ARCH" 2>/dev/null; then
      PASS=$((PASS+1)); printf 'ok   REL-10 %s: есть входящая ссылка\n' "$f"
    else
      FAIL=$((FAIL+1)); printf 'FAIL REL-10 %s: нет ни одной входящей ссылки — C10 orphan\n' "$f"
    fi
  else
    PASS=$((PASS+1)); printf 'ok   REL-10 %s: файла ещё нет — нечего проверять (vacuous)\n' "$f"
  fi
done

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
