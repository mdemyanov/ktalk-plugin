#!/usr/bin/env bash
# test-release-delivery-tails.sh — тест-дизайн QA-001 (ktalk-plugin-ke5.11) для требования
# content/30-requirements/2026-09-03-release-delivery-tails.md, capability
# openspec/specs/release-delivery-tails/spec.md (9 Requirement, 16 Scenario).
#
# Один стаб на волну (не два по числу ADR) — оба ADR (025, 026) закрывают ОДНО требование и
# ОДНУ capability; решение и обоснование — content/40-architecture/
# 2026-09-03-release-delivery-tails-at-design.md, раздел «Почему один стаб».
#
# AC-1..AC-16 — в порядке появления `#### Scenario:` в spec.md (та же нумерация — AC ID
# в at-design.md и в acceptance-логе BA). Каждая группа печатает, что именно проверяет и
# каким текущим фактом дерева обеспечен красный (или, где это регрессионная защита —
# зелёный по построению, как REL-1 в scripts/test-plugin-requirements-relocation.sh).
#
# Предмет ADR-026-сценариев (AC-8..AC-13) — ТЕКСТ промт-слоя, не поведение модели: здесь
# нет прикладного кода (ADR-012), поэтому что можно проверить скриптом — это наличие и
# форма инструкций, а не факт, что модель им следует (тот же принцип, что
# scripts/test-agreements-reconciliation.sh уже документирует дословно). Полная поведенческая
# проверка (агент реально делает один повтор и жёстко останавливается) — не автоматизируется
# этим стабом; носитель назван в at-design.md, «Не покрывается».
#
# Прогон: bash scripts/test-release-delivery-tails.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROCESSOR="$ROOT/agents/ktalk-processor.md"
REGISTRY_SKILL="$ROOT/skills/ktalk-registry/SKILL.md"
GATES_YAML="$ROOT/.nauta-gates.yaml"
DOC_ROOT_YAML="$ROOT/content/.doc-root.yaml"
COMPAT_JSON="$ROOT/compat.json"
README="$ROOT/README.md"
MARKETPLACE_JSON="$ROOT/.claude-plugin/marketplace.json"
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"

for f in "$PROCESSOR" "$REGISTRY_SKILL" "$GATES_YAML" "$DOC_ROOT_YAML" "$COMPAT_JSON" \
         "$README" "$MARKETPLACE_JSON" "$PLUGIN_JSON"; do
  [[ -f "$f" ]] || { echo "ERROR: $f not found" >&2; exit 2; }
done
command -v claude >/dev/null 2>&1 || { echo "ERROR: платформенный CLI 'claude' не найден в PATH — AC-1/2/4 требуют реального вызова, не заглушки" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 не найден в PATH" >&2; exit 2; }

PASS=0; FAIL=0; SKIP=0

check_true() { # check_true <0=ок/1=нарушение> <название>
  if [ "$1" = "0" ]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$2"
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$2"; fi
}

check_eq() { # check_eq <ожидание> <факт> <название>
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$3"
  else FAIL=$((FAIL+1)); printf 'FAIL %s: ожидалось "%s", получено "%s"\n' "$3" "$1" "$2"; fi
}

assert_contains() { # assert_contains <ac> <описание> <файл-или-строка-как-текст> <паттерн>
  local ac="$1" desc="$2" text="$3" pattern="$4"
  if grep -qF -- "$pattern" <<<"$text"; then
    PASS=$((PASS+1)); printf 'ok   %s %s\n' "$ac" "$desc"
  else
    FAIL=$((FAIL+1)); printf 'FAIL %s %s\n       не найдено: %s\n' "$ac" "$desc" "$pattern"
  fi
}

assert_contains_re() { # assert_contains_re <ac> <описание> <текст> <ERE>
  local ac="$1" desc="$2" text="$3" pattern="$4"
  if grep -qE -- "$pattern" <<<"$text"; then
    PASS=$((PASS+1)); printf 'ok   %s %s\n' "$ac" "$desc"
  else
    FAIL=$((FAIL+1)); printf 'FAIL %s %s\n       не найдено (regex): %s\n' "$ac" "$desc" "$pattern"
  fi
}

assert_not_contains() { # assert_not_contains <ac> <описание> <текст> <паттерн>
  local ac="$1" desc="$2" text="$3" pattern="$4"
  if grep -qF -- "$pattern" <<<"$text"; then
    FAIL=$((FAIL+1)); printf 'FAIL %s %s\n       найдено (не должно быть): %s\n' "$ac" "$desc" "$pattern"
  else
    PASS=$((PASS+1)); printf 'ok   %s %s\n' "$ac" "$desc"
  fi
}

assert_order() { # assert_order <ac> <описание> <файл> <паттерн-раньше> <паттерн-позже>
  local ac="$1" desc="$2" file="$3" first="$4" second="$5" l1 l2
  l1="$(grep -nE -- "$first" "$file" | head -1 | cut -d: -f1)"
  l2="$(grep -nE -- "$second" "$file" | head -1 | cut -d: -f1)"
  if [[ -n "$l1" && -n "$l2" && "$l1" -lt "$l2" ]]; then
    PASS=$((PASS+1)); printf 'ok   %s %s\n' "$ac" "$desc"
  else
    FAIL=$((FAIL+1)); printf 'FAIL %s %s\n       "%s" (строка %s) ожидалась раньше "%s" (строка %s)\n' \
      "$ac" "$desc" "$first" "${l1:-нет}" "$second" "${l2:-нет}"
  fi
}

note_skip() { # note_skip <ac> <причина> — носитель назван в at-design.md, не тихий пропуск
  SKIP=$((SKIP+1)); printf 'SKIP %s %s\n' "$1" "$2"
}

# slice_between <файл> <ERE начала> <ERE конца-исключая> — awk-вырезка секции, тот же приём,
# что STEP55_FILE в test-agreements-reconciliation.sh: проверка по всему файлу дала бы ложный
# зелёный ДО правки Dev (соседние шаги уже несут похожую лексику).
slice_between() {
  awk -v s="$2" -v e="$3" 'BEGIN{f=0} $0 ~ e {f=0} $0 ~ s {f=1} f' "$1"
}

# resolve_ref <имя-файла> — три справочника ktalk-processor переезжают Д5 ADR-025 из
# agents/references/ в references/ktalk-processor/; тест не должен жёстко привязываться к
# ОДНОМУ порядку, в котором Dev выполняет два ADR одного раунда (Brief SA называет только
# порядок ВНУТРИ ADR-025, не порядок между ADR-025 и ADR-026).
resolve_ref() {
  local name="$1"
  if [[ -f "$ROOT/references/ktalk-processor/$name" ]]; then
    echo "$ROOT/references/ktalk-processor/$name"
  elif [[ -f "$ROOT/agents/references/$name" ]]; then
    echo "$ROOT/agents/references/$name"
  else
    echo ""
  fi
}

echo "###############################################################################"
echo "# AC-1 — Requirement: A release tag resolves in the form the platform expects"
echo "# Scenario: The release tag matches the platform's dry-run form"
echo "###############################################################################"
# Регрессионная защита (приём REL-1, test-plugin-requirements-relocation.sh): форма тега —
# СВОЙСТВО платформенного инструмента `claude plugin tag`, не код этого раунда Dev (тег
# следующего релиза заводит DevOps будущим рансбуком, ADR-025 Д1). Зелёный СЕГОДНЯ — это
# ожидаемо, не vacuous: assert НЕ сравнивается с захардкоженной строкой, а читает
# plugin.json динамически и, вторым прогоном, доказывает мутацией (версия 9.9.9 в
# одноразовом scratch-репозитории), что проверка следит за значением, а не совпала случайно.
PLUGIN_NAME="$(python3 -c "import json;print(json.load(open('$PLUGIN_JSON'))['name'])")"
PLUGIN_VERSION="$(python3 -c "import json;print(json.load(open('$PLUGIN_JSON'))['version'])")"
LIVE_TAG_LINE="$(claude plugin tag --dry-run --force 2>&1 | grep -E '^Tag:' | head -1)"
EXPECTED_LIVE="Tag:     ${PLUGIN_NAME}--v${PLUGIN_VERSION}"
check_eq "$EXPECTED_LIVE" "$LIVE_TAG_LINE" \
  "AC-1a: claude plugin tag --dry-run для реального plugin.json резолвит <plugin>--v<version> (регрессионная защита, зелёный по построению)"

# Мутационная проверка «не захардкожено» (урок 2026-09-01 QA-author): scratch git-репозиторий
# с версией 9.9.9, независимый от рабочего дерева — assert обязан проследовать за мутацией.
mutation_tag_dry_run() { # mutation_tag_dry_run <version> — печатает строку Tag:
  local ver="$1" tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude-plugin"
  python3 - "$tmp" "$ver" <<'PYEOF'
import json, sys
tmp, ver = sys.argv[1], sys.argv[2]
json.dump({"name": "ktalk", "version": ver, "description": "scratch",
           "author": {"name": "mdemyanov"}}, open(f"{tmp}/.claude-plugin/plugin.json", "w"))
json.dump({"name": "ktalk-plugins", "owner": {"name": "mdemyanov"},
           "plugins": [{"name": "ktalk", "source": "./", "description": "scratch"}]},
          open(f"{tmp}/.claude-plugin/marketplace.json", "w"))
PYEOF
  (cd "$tmp" && git init -q && git add -A && git -c user.email=a@a -c user.name=a commit -q -m scratch)
  (cd "$tmp" && claude plugin tag --dry-run --force 2>&1 | grep -E '^Tag:' | head -1)
  rm -rf "$tmp"
}
MUTATED_TAG="$(mutation_tag_dry_run "9.9.9")"
check_eq "Tag:     ktalk--v9.9.9" "$MUTATED_TAG" \
  "AC-1b: мутация version=9.9.9 в scratch-репозитории меняет резолвящийся тег синхронно (не сравнение с захардкоженной строкой)"

echo
echo "###############################################################################"
echo "# AC-2 — Requirement: The marketplace manifest declares a description"
echo "# Scenario: Marketplace validation reports no missing-description warning"
echo "###############################################################################"
MKT_HAS_TOP_DESC="$(python3 - "$MARKETPLACE_JSON" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
top = d.get("description")
plugin_desc = (d.get("plugins") or [{}])[0].get("description")
print("1" if (top and top != plugin_desc) else "0")
PYEOF
)"
check_eq "1" "$MKT_HAS_TOP_DESC" \
  "AC-2a: .claude-plugin/marketplace.json несёт top-level description, отдельный от plugins[0].description"
VALIDATE_OUT="$(claude plugin validate . 2>&1)"
assert_not_contains "AC-2b" "claude plugin validate . не печатает предупреждение об отсутствующем description маркетплейса" \
  "$VALIDATE_OUT" "No marketplace description provided"

echo
echo "###############################################################################"
echo "# AC-3 — Requirement: The documented update path names every command it takes"
echo "# Scenario: The documented sequence moves an installed copy to the new version"
echo "###############################################################################"
# Полное поведенческое доказательство («установленная копия действительно перешла на новую
# версию») требует состояния ~/.claude/plugins/installed_plugins.json ВНЕ дерева репозитория
# — companion ADR-025, Test-pyramid: «вне автоматизируемого контракта этого дерева».
# Автоматизируемая часть — полнота ТЕКСТА README (обе команды, в порядке, плюс перезапуск).
README_TEXT="$(cat "$README")"
assert_contains "AC-3a" "README называет marketplace update" "$README_TEXT" "claude plugin marketplace update ktalk-plugins"
assert_contains "AC-3b" "README называет plugin update (вторая, недостающая сегодня команда)" "$README_TEXT" "claude plugin update ktalk@ktalk-plugins"
assert_order "AC-3c" "marketplace update упомянут раньше plugin update (порядок из companion Д3)" \
  "$README" "claude plugin marketplace update ktalk-plugins" "claude plugin update ktalk@ktalk-plugins"
assert_contains_re "AC-3d" "README называет перезапуск сессии как обязательный третий шаг" \
  "$README_TEXT" "[Rr]estart|перезапуст"
note_skip "AC-3e" \
  "полное поведенческое доказательство («installed_plugins.json действительно перешёл на новую версию») — состояние вне дерева репозитория; носитель: шаг релизного рансбука DevOps (по образцу живого замера ADR-025 companion: marketplace update не двигает installed_plugins.json, plugin update двигает), не тест кода этого дерева."

echo
echo "###############################################################################"
echo "# AC-4 — Requirement: A file that is a reference, not an agent, is not registered as one"
echo "# Scenario: A reference file does not appear as an agent in the session's tool list"
echo "###############################################################################"
REF_FILES=(two-pass-analysis.md protocol-template.md vault-update-and-report.md)
STILL_UNDER_AGENTS=0
NEW_LOCATION_MISSING=0
for f in "${REF_FILES[@]}"; do
  [[ -f "$ROOT/agents/references/$f" || -n "$(find "$ROOT/agents" -name "$f" 2>/dev/null)" ]] && STILL_UNDER_AGENTS=1
  [[ -f "$ROOT/references/ktalk-processor/$f" ]] || NEW_LOCATION_MISSING=1
done
check_true "$STILL_UNDER_AGENTS" "AC-4a: ни один из трёх справочников не остался под agents/ (сканируемый каталог агентов)"
check_true "$NEW_LOCATION_MISSING" "AC-4b: все три справочника существуют под references/ktalk-processor/ (ADR-025 Д5)"

# Вторая сторона (урок «известная ловушка этой волны», предостережение брифа PM): «нет в
# списке агентов» ложноположительно проходит, если файл просто переименован в
# нерезолвящийся путь — поэтому решает ЖИВОЙ прогон claude plugin tag --dry-run, а не
# только факт отсутствия по старому пути. Сегодня инструмент печатает предупреждение «No
# frontmatter block found» по всем трём файлам под agents/references/ — после переезда он не
# должен упоминать ни один из трёх файлов вовсе (не переехали в другой каталог агентов).
DRYRUN_OUT="$(claude plugin tag --dry-run --force 2>&1)"
NAMED_AS_CANDIDATE=0
for f in "${REF_FILES[@]}"; do
  grep -qF -- "$f" <<<"$DRYRUN_OUT" && NAMED_AS_CANDIDATE=1
done
check_true "$NAMED_AS_CANDIDATE" \
  "AC-4c: claude plugin tag --dry-run не упоминает ни один из трёх файлов как кандидата в агенты (сегодня — три предупреждения 'No frontmatter block found')"

echo
echo "###############################################################################"
echo "# AC-5 — Requirement: A file that is a reference, not an agent, is not registered as one"
echo "# Scenario: Every agent-carrying file the platform validates still resolves correctly"
echo "###############################################################################"
PROCESSOR_TEXT="$(cat "$PROCESSOR")"
NEW_FORM_COUNT="$(grep -oF '${CLAUDE_PLUGIN_ROOT}/references/ktalk-processor/' "$PROCESSOR" | wc -l | tr -d ' ')"
check_eq "8" "$NEW_FORM_COUNT" \
  "AC-5a: agents/ktalk-processor.md несёт ровно 8 ссылок формы \${CLAUDE_PLUGIN_ROOT}/references/ktalk-processor/<файл>.md (Д5, строки 47-49,150,188,222,311,315)"
BARE_FORM_LEFT=0
for f in "${REF_FILES[@]}"; do
  # Голая форма без ${CLAUDE_PLUGIN_ROOT}-префикса перед ней (символ ДО "references/" не
  # "/") — конвенция, которой уже следуют все остальные 4 промта дерева (строка 36 самого
  # ktalk-processor.md).
  if grep -qE "[^/]references/${f}" "$PROCESSOR"; then BARE_FORM_LEFT=1; fi
done
check_true "$BARE_FORM_LEFT" \
  "AC-5b: в agents/ktalk-processor.md не осталось голой формы references/<файл>.md без \${CLAUDE_PLUGIN_ROOT}-префикса"
RESOLVE_FAIL=0
for f in "${REF_FILES[@]}"; do
  [[ -f "$ROOT/references/ktalk-processor/$f" ]] || RESOLVE_FAIL=1
done
check_true "$RESOLVE_FAIL" \
  "AC-5c: каждый из трёх путей \${CLAUDE_PLUGIN_ROOT}/references/ktalk-processor/<файл>.md резолвится в существующий файл"

# AC-5 доп. (Dev-brief companion, не отдельный Scenario спеки, но то же наблюдаемое
# свойство «ссылки резолвятся» распространено companion-статьёй на 5 внешних файлов) —
# считается в общий счёт AC-5, отдельным ID не заводится (тот же приём именования
# «(доп.)», что test-agreements-reconciliation.sh). Простой список пар вместо
# ассоциативного массива: /bin/bash поставки macOS — 3.2, `declare -A` недоступен.
EXTERNAL_CITER_FILES="skills/ktalk-eval/references/eval-rubric.md
skills/ktalk-registry/references/analysis-quality.md
skills/ktalk-registry/references/registry-format.md"
STALE_EXTERNAL=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  if [[ -f "$ROOT/$rel" ]] && grep -qF "agents/references/" "$ROOT/$rel"; then
    STALE_EXTERNAL=1
  fi
done <<< "$EXTERNAL_CITER_FILES"
check_true "$STALE_EXTERNAL" \
  "AC-5 доп.: три внешних файла-цитаты (skills/*/references/*) больше не называют путь agents/references/… (companion Д5, вне ktalk-processor.md, но то же свойство разрешимости)"

echo
echo "###############################################################################"
echo "# AC-6 — Requirement: Prompt-layer text and metadata do not name a retired package identity"
echo "# Scenario: Repository metadata describing the plugin's dependency names no retired package"
echo "###############################################################################"
DOC_ROOT_HAS_RETIRED=0; grep -qF "ktalk-mcp" "$DOC_ROOT_YAML" && DOC_ROOT_HAS_RETIRED=1
GATES_HAS_RETIRED=0; grep -qF "ktalk-mcp" "$GATES_YAML" && GATES_HAS_RETIRED=1
check_true "$DOC_ROOT_HAS_RETIRED" "AC-6a: content/.doc-root.yaml не называет retired-имя ktalk-mcp (строка 10)"
check_true "$GATES_HAS_RETIRED" "AC-6b: .nauta-gates.yaml не называет retired-имя ktalk-mcp (комментарий строки 103)"

# Masked-failure класс (companion Д6, дословно): регресс того же рода закрылся бы наивной
# заменой retired-литерала НА ДРУГОЙ литерал (`ktalk-cli`) — читалось бы как починка, а
# правило требует описания ПО РОЛИ, не по имени. compat.json сегодня несёт "ktalk-cli" —
# используем его для проверки, что описание не совпадает буквально ни с одним значением.
# Как и AC-6c: сегодня файлы несут только "ktalk-mcp" (см. AC-6a/b выше), поэтому этот
# под-тест зелёный vacuous-зелёным — не потому что Dev уже описал зависимость по роли, а
# потому что "ktalk-cli" там пока не появлялось вовсе. Содержательной регрессионной защитой
# он становится ПОСЛЕ правки Dev (тот же приём, что REL-10 в test-plugin-requirements-relocation.sh).
DOC_ROOT_HAS_OTHER_LITERAL=0; grep -qF "ktalk-cli" "$DOC_ROOT_YAML" && DOC_ROOT_HAS_OTHER_LITERAL=1
GATES_HAS_OTHER_LITERAL=0; grep -qF "ktalk-cli" "$GATES_YAML" && GATES_HAS_OTHER_LITERAL=1
check_true "$DOC_ROOT_HAS_OTHER_LITERAL" \
  "AC-6a-masked: content/.doc-root.yaml не заменяет retired-литерал на ДРУГОЙ жёсткий литерал (ktalk-cli) — companion Д6: тот же класс регресса со сменой носителя"
check_true "$GATES_HAS_OTHER_LITERAL" \
  "AC-6b-masked: .nauta-gates.yaml не заменяет retired-литерал на ДРУГОЙ жёсткий литерал (ktalk-cli) — та же ловушка"

# Мутационная проверка (обязательное предписание companion + урок 2026-09-01): описание по
# роли не должно зависеть от ЗНАЧЕНИЯ compat.json вовсе — подменяем package_name на третье,
# синтетическое имя и убеждаемся, что ни retired-, ни синтетический литерал не появились.
# ВАЖНО: сегодня оба файла ещё несут "ktalk-mcp" (см. AC-6a/b выше) — эта под-проверка
# закономерно vacuous-зелёная СЕГОДНЯ (файлы просто не содержат случайную строку ниже,
# не потому что Dev уже переписал их по роли); настоящий дефект уже пойман AC-6a/b.
# После правки Dev она становится содержательной регрессионной защитой (приём REL-10).
COMPAT_BACKUP="$(mktemp)"
cp "$COMPAT_JSON" "$COMPAT_BACKUP"
restore_compat() { cp "$COMPAT_BACKUP" "$COMPAT_JSON"; rm -f "$COMPAT_BACKUP"; }
trap restore_compat EXIT
SYNTHETIC_NAME="zzz-synthetic-pkg-qa001"
python3 - "$COMPAT_JSON" "$SYNTHETIC_NAME" <<'PYEOF'
import json, sys
path, name = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d["package_name"] = name
json.dump(d, open(path, "w"))
PYEOF
SYNTH_LEAKED=0
grep -qF "$SYNTHETIC_NAME" "$DOC_ROOT_YAML" && SYNTH_LEAKED=1
grep -qF "$SYNTHETIC_NAME" "$GATES_YAML" && SYNTH_LEAKED=1
check_true "$SYNTH_LEAKED" \
  "AC-6c (мутация compat.json → имя синтетическое): ни один из двух файлов не подхватывает буквальное имя зависимости — описание по роли не зависит от значения (vacuous-зелёная до правки Dev, см. комментарий выше)"
restore_compat
trap - EXIT

echo
echo "###############################################################################"
echo "# AC-7 — Requirement: README's operational claims match the interface the package exposes"
echo "# Scenario: README's token-file claim names only interfaces the package exposes"
echo "###############################################################################"
assert_not_contains "AC-7a" "README не утверждает, что токен подхватывает MCP-сервер (строка 50)" \
  "$README_TEXT" "MCP-сервер"
KTALK_HELP_OUT="$(ktalk --help 2>&1 || true)"
assert_not_contains "AC-7b" "ktalk --help (реальный CLI, доказательная проверка факта, а не документа) не содержит mcp" \
  "$(tr '[:upper:]' '[:lower:]' <<<"$KTALK_HELP_OUT")" "mcp"

echo
echo "###############################################################################"
echo "# AC-8 — Requirement: Project delegation to project-curator is routed through the orchestrator"
echo "# Scenario: A processor agent that touched a project does not call project-curator"
echo "###############################################################################"
FINAL_STEP="$(slice_between "$PROCESSOR" '^## Final step' '^\x00NEVER\x00')"
assert_not_contains "AC-8a" "'Final step' agents/ktalk-processor.md не вызывает project-curator напрямую (Д2 ADR-026)" \
  "$FINAL_STEP" "project-curator"
assert_contains "AC-8b" "финальный отчёт несёт строку «Проекты затронуты: {ids}»/«нет» вместо «Делегировано project-curator»" \
  "$FINAL_STEP" "Проекты затронуты"
# Портируемая вырезка фронтматтера (macOS/BSD head не понимает `head -n -1`, а сьюта
# обязана бежать и там, и на GNU): awk считает маркеры '---' сам, без -1-хвоста head.
FRONTMATTER="$(awk 'BEGIN{c=0} /^---$/{c++; next} c==1{print}' "$PROCESSOR")"
assert_not_contains "AC-8c" "tools: фронтматтера не расширен инструментом вызова субагента (регрессионная защита Д1 ADR-026)" \
  "$FRONTMATTER" "- Task"

echo
echo "###############################################################################"
echo "# AC-9 — Requirement: Project delegation to project-curator is routed through the orchestrator"
echo "# Scenario: The orchestrator invokes project-curator once, after every processor completes"
echo "###############################################################################"
assert_contains_re "AC-9a" "skills/ktalk-registry/SKILL.md несёт новый шаг 5.5 между шагом 5 и шагом 6" \
  "$(cat "$REGISTRY_SKILL")" "^### Step 5\.5"
assert_order "AC-9b" "шаг 5.5 расположен раньше шага 6 (сборка прогона предшествует зеркалированию реестра)" \
  "$REGISTRY_SKILL" '^### Step 5\.5' '^### Step 6\.'
STEP55="$(slice_between "$REGISTRY_SKILL" '^### Step 5\.5' '^### Step 6\.')"
assert_contains "AC-9c" "шаг 5.5 вызывает project-curator" "$STEP55" "project-curator"
assert_contains_re "AC-9d" "шаг 5.5 явно ограничивает вызов одним разом на прогон (не более/ровно один)" \
  "$STEP55" "(не более|ровно один|at most once|exactly once)"

echo
echo "###############################################################################"
echo "# AC-10 — Requirement: Project delegation to project-curator is routed through the orchestrator"
echo "# Scenario: project-curator is not installed in the host project"
echo "###############################################################################"
assert_contains_re "AC-10a" "шаг 5.5 называет пропуск делегирования при неустановленном project-curator в сводке прогона" \
  "$STEP55" "(не установлен|not installed)"
assert_not_contains "AC-10b" "agents/ktalk-processor.md 'Final step' больше не проверяет установленность project-curator сам (знание переехало оркестратору, Д2 ADR-026)" \
  "$FINAL_STEP" "installed"

echo
echo "###############################################################################"
echo "# AC-11 — Requirement: A fetched transcript's identity is verified before it is used"
echo "# Scenario: A matching transcript proceeds without an extra step"
echo "###############################################################################"
assert_contains_re "AC-11a" "agents/ktalk-processor.md несёт новый шаг 2b между шагом 2 и шагом 2.5" \
  "$PROCESSOR_TEXT" "^### 2b"
assert_order "AC-11b" "шаг 2b расположен раньше шага 2.5 (сверка личности предшествует ориентации по саммари)" \
  "$PROCESSOR" '^### 2b' '^### 2\.5'
STEP2B="$(slice_between "$PROCESSOR" '^### 2b' '^### 2\.5')"
assert_contains_re "AC-11c" "шаг 2b явно определяет совпадение участников как основание продолжить без доп. шага" \
  "$STEP2B" "(match|совпад)"
assert_not_contains "AC-11d" "шаг 2b не превращает совпадение в запрос подтверждения у оператора (не маскирует проверку под диалог)" \
  "$STEP2B" "confirm with the user"

echo
echo "###############################################################################"
echo "# AC-12 — Requirement: A fetched transcript's identity is verified before it is used"
echo "# Scenario: A mismatched transcript is retried once"
echo "###############################################################################"
assert_contains_re "AC-12a" "шаг 2b предписывает повторный запрос get-transcript при несовпадении" \
  "$STEP2B" "(retry|re-fetch|повтор)"
assert_contains_re "AC-12b" "повтор ограничен ровно одним разом (не бесконечный retry, не тихий цикл)" \
  "$STEP2B" "(exactly one|ровно один|once)"

echo
echo "###############################################################################"
echo "# AC-13 — Requirement: A fetched transcript's identity is verified before it is used"
echo "# Scenario: A mismatch that survives the retry is a hard stop, not a silent continuation"
echo "###############################################################################"
assert_contains "AC-13a" "шаг 2b вызывает ktalk mark-partial при устойчивом несовпадении" "$STEP2B" "mark-partial"
MARK_PARTIAL_LINES="$(grep -F "mark-partial" "$PROCESSOR")"
assert_not_contains "AC-13b" "вызов mark-partial из шага 2b не несёт --transcript/--protocol (несохранённые данные не архивируются)" \
  "$MARK_PARTIAL_LINES" "--transcript"
VAULT_REF_PATH="$(resolve_ref vault-update-and-report.md)"
if [[ -n "$VAULT_REF_PATH" ]]; then
  VAULT_REF_TEXT="$(cat "$VAULT_REF_PATH")"
  assert_not_contains "AC-13c" "отчёт формы hard-stop не несёт заголовок «✅ Встреча обработана» (Data flow п.3 companion ADR-026)" \
    "$VAULT_REF_TEXT" "Встреча обработана: \"{recording_name}\" — {date}\n\nHARD-STOP"
  assert_contains_re "AC-13d" "финальный отчёт hard-stop называет recording_id и найденных участников" \
    "$VAULT_REF_TEXT" "(participants actually found|найденных участник)"
else
  FAIL=$((FAIL+1)); printf 'FAIL AC-13c/d: справочник vault-update-and-report.md не резолвится ни по старому, ни по новому пути\n'
fi
# Ордер: сохранение chunk 0 (`registry.routing.transcript_archive`) переносится ПОСЛЕ
# подтверждения личности — сегодня оно стоит в середине шага 2, до какой-либо проверки.
assert_order "AC-13e" "сохранение chunk 0 по шаблону transcript_archive стоит ПОСЛЕ шага 2b (не до проверки личности, Д4 ADR-026)" \
  "$PROCESSOR" '^### 2b' 'following the .registry\.routing\.transcript_archive. template'

echo
echo "###############################################################################"
echo "# AC-14 — Requirement: The GO-criterion gates CLAUDE.md names are enforced automatically"
echo "# Scenario: The composition and language gates run as part of the automated check"
echo "###############################################################################"
GATES_TEXT="$(cat "$GATES_YAML")"
assert_contains_re "AC-14a" ".nauta-gates.yaml объявляет projectGates.fast с check-plugin-composition.sh" \
  "$GATES_TEXT" "projectGates:"
assert_contains "AC-14b" "projectGates.fast называет scripts/check-plugin-composition.sh" "$GATES_TEXT" "scripts/check-plugin-composition.sh"
assert_contains "AC-14c" "projectGates.fast называет scripts/check-prompt-language.sh" "$GATES_TEXT" "scripts/check-prompt-language.sh"
assert_contains "AC-14d" "projectGates.full называет scripts/test-onboard.sh" "$GATES_TEXT" "scripts/test-onboard.sh"

# Живые вызовы check.sh — DEV-002 (ktalk-plugin-ke5.14), Вариант B (изолированная копия
# дерева, не часовой вложенности через переменную окружения). Эта сьюта сама зарегистрирована
# в projectGates.full корневого .nauta-gates.yaml (см. ниже AC-14d и коммит DEV-002) — вызов
# bash "$ROOT/scripts/check.sh" --full ОТСЮДА воспроизводимо давал бесконечную рекурсию
# (check.sh запускает эту сьюту → сьюта снова запускает check.sh --full → …), проверено и
# остановлено вручную (pkill -9) при разработке DEV-002, отчёт координатору эпика. Копия
# дерева без .git — тот же приём, что MIRROR40/43/44A/44B в scripts/test-onboard.sh; её
# .nauta-gates.yaml лишён СВОЕЙ строки-самоссылки под full: (grep -v -F по буквальному пути,
# а не переписывание блока с нуля — переживает будущий дрейф остальных позиций projectGates).
# check.sh копии физически не может вызвать эту сьюту повторно — рекурсии нет по построению
# копии, не по соглашению о переменной окружения (граница глубины 1 гарантирована структурой
# фикстуры, не проверяется в рантайме). Носитель четырёх живых ассертов НЕ меняется при вложенном
# запуске (эта же сьюта как позиция projectGates.full реального $ROOT): AC-14e-h исполняются
# по-настоящему в обоих контекстах — и при прямом прогоне QA-runner'ом, и внутри check.sh
# --full реального дерева, — а не переходят в SKIP ни в одном из них (at-design.md,
# «Не покрывается» этой задачей не пополняется — носитель не сменился, полнота сохранена).
TMP14="$(mktemp -d)"
MIRROR14="$TMP14/mirror-check-live"
cp -r "$ROOT" "$MIRROR14"
rm -rf "$MIRROR14/.git"
grep -v -F 'scripts/test-release-delivery-tails.sh' "$GATES_YAML" > "$MIRROR14/.nauta-gates.yaml"

FAST_OUT="$(bash "$MIRROR14/scripts/check.sh" --fast 2>&1)"
assert_not_contains "AC-14e" "check.sh --fast больше не печатает 'projectGates: absent' (гейт подключён, не декоративно упомянут)" \
  "$FAST_OUT" "projectGates: absent"
assert_contains "AC-14f" "check.sh --fast исполняет и отражает scripts/check-plugin-composition.sh как позицию projectGates" \
  "$FAST_OUT" "▶ scripts/check-plugin-composition.sh"
assert_contains "AC-14g" "check.sh --fast исполняет и отражает scripts/check-prompt-language.sh как позицию projectGates" \
  "$FAST_OUT" "▶ scripts/check-prompt-language.sh"

FULL_OUT="$(bash "$MIRROR14/scripts/check.sh" --full 2>&1)"
assert_contains "AC-14h" "check.sh --full дополнительно исполняет scripts/test-onboard.sh (только в full:, не в fast:)" \
  "$FULL_OUT" "▶ scripts/test-onboard.sh"
rm -rf "$TMP14"

echo
echo "###############################################################################"
echo "# AC-15 — Requirement: The GO-criterion gates CLAUDE.md names are enforced automatically"
echo "# Scenario: The branch-naming discipline is judged, not undetermined"
echo "###############################################################################"
assert_contains_re "AC-15a" ".nauta-gates.yaml объявляет branchDiscipline.profile" "$GATES_TEXT" "branchDiscipline:"
assert_contains_re "AC-15b" "branchDiscipline.profile принимает объявленное значение перечня (single|team)" \
  "$GATES_TEXT" "profile:[[:space:]]*(single|team)"
BRANCH_DISC_OUT="$(python3 "$ROOT/scripts/check-branch-discipline.py" "$ROOT" 2>&1)"
assert_not_contains "AC-15c" "check-branch-discipline.py больше не сообщает 'не объявлен'/'undetermined' для этого дерева" \
  "$BRANCH_DISC_OUT" "не объявлен"
note_skip "AC-15d" \
  "боундари-условие companion (single vs team дают разный вердикт на одной паре имён веток) не закрываемо этим раундом Dev: check-branch-discipline.py — замороженная доставка nauta (sha256, .nauta-scripts-basis.yaml), а _guard_branch_names() измеримо не читает значение profile вовсе (grep team scripts/check-branch-discipline.py — только в перечне PROFILES и в двух текстах ошибок, не в логике сторожа). Носитель: следующий /nauta:sync-scripts владельца nauta, отдельный бэклог-пункт SA/DevOps, не Dev этого раунда."

# Malformed/mistyped input (обязательный класс, брифа PM): владелец плагина мог опечататься
# в значении перечня (`profile: singel`) вместо валидного single|team. Скретч-каталог, НЕ
# реальное дерево — не мутирует .nauta-gates.yaml репозитория. check-branch-discipline.py
# сам решает исход (уже доставленный код nauta, не задача Dev) — тест регрессионно
# защищает то, что мистайп остаётся громкой ошибкой (код 2), а не тихим умолчанием.
TMP_BOGUS="$(mktemp -d)"
printf 'branchDiscipline:\n  profile: bogus-value\n' > "$TMP_BOGUS/.nauta-gates.yaml"
python3 "$ROOT/scripts/check-branch-discipline.py" "$TMP_BOGUS" >/dev/null 2>&1
BOGUS_RC=$?
rm -rf "$TMP_BOGUS"
check_eq "2" "$BOGUS_RC" \
  "AC-15e (malformed input, scratch-дерево): опечатанное значение profile — громкая ошибка (код 2), не тихое умолчание undetermined/single"

echo
echo "###############################################################################"
echo "# AC-16 — Requirement: The GO-criterion gates CLAUDE.md names are enforced automatically"
echo "# Scenario: The gate-delivery basis is not silently behind the installed tooling"
echo "###############################################################################"
BASIS_VERSION="$(grep -oE 'nauta_version: "[0-9.]+"' "$ROOT/.nauta-scripts-basis.yaml" | grep -oE '[0-9.]+')"
CACHE_DIR="$HOME/.claude/plugins/cache/nauta/nauta"
if [[ -d "$CACHE_DIR" ]]; then
  INSTALLED_MAX="$(ls "$CACHE_DIR" 2>/dev/null | sort -V | tail -1)"
  echo "  инфо: базис .nauta-scripts-basis.yaml = ${BASIS_VERSION:-?}, установлено в кеше плагина = ${INSTALLED_MAX:-?}"
else
  echo "  инфо: $CACHE_DIR отсутствует на этой машине — сравнение неприменимо здесь"
fi
note_skip "AC-16" \
  "сравнение версии базиса доставки с версией установленного инструментария — процедурная проверка при апдейте nauta (companion ADR-025: «вне автоматизируемого контракта этого дерева»), не код-тест этого репозитория. Носитель: ручное сравнение .nauta_version в .nauta-scripts-basis.yaml против find ~/.claude/plugins/cache/nauta/nauta -maxdepth 1, выполняемое DevOps/владельцем при каждом /nauta:sync-scripts (тот же приём измерения, каким SA уже пользовался в ADR-025 Context)."

echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ "$FAIL" -eq 0 ]]
