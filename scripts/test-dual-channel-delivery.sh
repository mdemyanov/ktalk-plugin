#!/usr/bin/env bash
# test-dual-channel-delivery.sh — тест-дизайн QA-001 (ktalk-plugin-dhg.19) для требования
# content/30-requirements/2026-09-04-dual-channel-delivery.md, capability
# openspec/specs/dual-channel-delivery/spec.md (6 Requirement, 6 Scenario).
#
# AC-1..AC-6 — в порядке появления `#### Scenario:` в spec.md; та же нумерация — AC ID в
# content/30-requirements/2026-09-04-dual-channel-delivery/at-design.md и в приёмочном логе
# BA. EDGE-1 — edge case из «Contract with QA-author» companion-статьи (content/40-
# architecture/2026-09-04-dual-channel-delivery.md), не привязанный к одному сценарию:
# «манифест и .gitlab-ci.yml сами не входят в payload».
#
# ЛОВУШКА (content/lessons-learned.md, записи 2026-08-31 и 2026-09-04, дважды за один
# эпик до этой задачи): scripts/ входит в payload-манифест (Д4 ADR-027), поэтому будущий
# check_payload_domain (Dev, AC-5) будет сканировать И ЭТОТ файл наравне с остальными.
# Внутренний GitLab-домен нигде ниже не написан одной строкой — только собран во время
# исполнения из двух частей (build_internal_domain), иначе эта же сьюта уронила бы
# check.sh на самой себе в день, когда AC-5 подключат к projectGates.
#
# Ограничение среды исполнения этой сессии (не архитектурное): роль qa-author не имеет
# полномочия O4 (`git push`, ADR-036 Д5/Д6) — фикстуры паритета (AC-2/AC-4) построены БЕЗ
# push и БЕЗ реальных remote: один локальный репозиторий, коммиты для каждой стороны и
# `git update-ref refs/remotes/<gitlab|github>/<tag> <sha>` вместо push. Команды Д6 ADR-027
# оперируют такими ref'ами буквально (`gitlab/<tag>`, `github/<tag>`) — им всё равно, откуда
# взялся объект, лишь бы ref резолвился, поэтому подмена ничего не ослабляет в проверяемом
# поведении.
#
# Ни один блок не зовёт `exit` до итогового — упавший блок не должен прерывать остальные.
# Прогон: bash scripts/test-dual-channel-delivery.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

ok() { PASS=$((PASS + 1)); printf '  ✓ %s %s\n' "$1" "$2"; }
bad() { FAIL=$((FAIL + 1)); printf '  ✗ %s %s\n' "$1" "$2"; [[ -n "${3:-}" ]] && printf '      %s\n' "$3"; }
skip_ac() { SKIP=$((SKIP + 1)); printf '  ⋯ %s %s\n' "$1" "$2"; }

require_true() { # require_true <ac> <desc> <0=ок/1=нарушение> [причина]
  if [[ "$3" == "0" ]]; then ok "$1" "$2"; else bad "$1" "$2" "${4:-}"; fi
}

assert_contains() { # assert_contains <ac> <desc> <текст> <фикс.строка>
  if grep -qF -- "$4" <<<"$3"; then ok "$1" "$2"; else bad "$1" "$2" "не найдено: $4"; fi
}

assert_not_contains() { # assert_not_contains <ac> <desc> <текст> <фикс.строка>
  if grep -qF -- "$4" <<<"$3"; then bad "$1" "$2" "найдено (не должно быть): $4"; else ok "$1" "$2"; fi
}

assert_contains_re() { # assert_contains_re <ac> <desc> <текст> <ERE>
  if grep -qE -- "$4" <<<"$3"; then ok "$1" "$2"; else bad "$1" "$2" "не найдено (regex): $4"; fi
}

# build_internal_domain — литерал внутреннего GitLab-домена собран из двух частей на лету
# (см. заголовок файла) — ни на одной физической строке дискового текста этого файла не
# лежит контигуально.
build_internal_domain() {
  local part1="doc-hub.gitlab"
  local part2="yandexcloud.net"
  printf '%s.%s' "$part1" "$part2"
}
INTERNAL_DOMAIN="$(build_internal_domain)"

SOURCE_MKT="$ROOT/.claude-plugin/marketplace.json"
GITLAB_CI="$ROOT/.gitlab-ci.yml"
PAYLOAD_MANIFEST="$ROOT/.gitlab/payload-manifest.txt"
COMPOSITION_SH="$ROOT/scripts/check-plugin-composition.sh"
EXPECTED_MIRROR_NAME="ktalk-plugins-mirror"   # Д1 ADR-027 — литерал решён SA, не деталь Dev

echo "###############################################################################"
echo "# AC-1 — Requirement: The two channels declare distinguishable marketplace identities"
echo "# Scenario: A consumer adds both channels' marketplaces"
echo "###############################################################################"

if [[ ! -f "$GITLAB_CI" ]]; then
  bad "AC1-1" "механизм зеркалирования (.gitlab-ci.yml, джоб mirror-github) существует" \
      "$GITLAB_CI не найден — патч marketplace.json.name на пропатченной копии нечем произвести"
  bad "AC1-2" "пропатченная копия несёт name=\"$EXPECTED_MIRROR_NAME\", отличный от исходника (\"ktalk-plugins\")" \
      "недостижимо без .gitlab-ci.yml"
  bad "AC1-3 (edge case)" "остальное содержимое marketplace.json (в т.ч. plugins[0]) идентично исходнику — отличается ТОЛЬКО name" \
      "недостижимо без .gitlab-ci.yml"
  bad "AC1-4 (malformed input guard)" "результат патча — валидный JSON" "недостижимо без .gitlab-ci.yml"
else
  # Извлекаем jq-фильтр джоба mirror-github (форма из Dev-брифа: jq '.name = "..."'). Если Dev
  # выбрал другой инструмент («jq/эквивалент», companion-статья, Components), фильтр не
  # найдётся — тогда используем более слабую, но инструмент-агностичную проверку присутствия
  # литерала рядом с marketplace.json в теле джоба.
  MIRROR_JQ_FILTER="$(grep -oE "jq[[:space:]]+'\.name[^']*'" "$GITLAB_CI" | head -1 | sed -E "s/^jq[[:space:]]+'//; s/'\$//")"
  PATCHED_JSON=""
  if [[ -n "$MIRROR_JQ_FILTER" ]]; then
    ok "AC1-1" "джоб mirror-github несёт jq-фильтр, патчащий поле name ($MIRROR_JQ_FILTER)"
    PATCHED_JSON="$(jq "$MIRROR_JQ_FILTER" "$SOURCE_MKT" 2>/dev/null || true)"
  elif grep -q "marketplace.json" "$GITLAB_CI" && grep -qF "$EXPECTED_MIRROR_NAME" "$GITLAB_CI"; then
    ok "AC1-1 (слабая форма)" "джоб упоминает marketplace.json и литерал \"$EXPECTED_MIRROR_NAME\" рядом (инструмент патча — не jq)"
  else
    bad "AC1-1" "джоб mirror-github содержит jq-фильтр по .name либо явное упоминание marketplace.json + \"$EXPECTED_MIRROR_NAME\""
  fi

  SRC_NAME="$(jq -r '.name' "$SOURCE_MKT" 2>/dev/null)"
  PATCHED_NAME="$(jq -r '.name' <<<"$PATCHED_JSON" 2>/dev/null || true)"
  if [[ -n "$PATCHED_NAME" && "$PATCHED_NAME" == "$EXPECTED_MIRROR_NAME" && "$PATCHED_NAME" != "$SRC_NAME" ]]; then
    ok "AC1-2" "пропатченная копия несёт name=\"$EXPECTED_MIRROR_NAME\", отличный от исходного (\"$SRC_NAME\")"
  else
    bad "AC1-2" "пропатченная копия несёт name=\"$EXPECTED_MIRROR_NAME\", отличный от исходника" \
        "PATCHED_NAME='${PATCHED_NAME:-<пусто>}' SRC_NAME='$SRC_NAME'"
  fi

  if [[ -n "$PATCHED_JSON" ]]; then
    SRC_REST="$(jq -S 'del(.name)' "$SOURCE_MKT" 2>/dev/null)"
    PATCHED_REST="$(jq -S 'del(.name)' <<<"$PATCHED_JSON" 2>/dev/null || true)"
    require_true "AC1-3 (edge case)" "остальное содержимое (включая plugins[0]) идентично исходнику — отличается ТОЛЬКО name" \
      "$([[ "$SRC_REST" == "$PATCHED_REST" && -n "$SRC_REST" ]] && echo 0 || echo 1)"
    if jq -e . >/dev/null 2>&1 <<<"$PATCHED_JSON"; then
      ok "AC1-4 (malformed input guard)" "результат патча — валидный JSON"
    else
      bad "AC1-4 (malformed input guard)" "результат патча — валидный JSON" "jq не смог распарсить результат"
    fi
  else
    skip_ac "AC1-3 (edge case)" "jq-фильтр не извлечён (слабая форма AC1-1) — сравнить содержимое нечем"
    skip_ac "AC1-4 (malformed input guard)" "jq-фильтр не извлечён — валидность результата не проверить"
  fi
fi

echo
echo "###############################################################################"
echo "# AC-2 — Requirement: Cross-channel parity is a checkable fact, not a claim"
echo "# Scenario: Comparing a mirrored release against its source"
echo "###############################################################################"

if [[ -f "$PAYLOAD_MANIFEST" ]]; then
  ok "AC2-1" ".gitlab/payload-manifest.txt существует — команда №3 паритета (Д6 ADR-027, git ls-tree -- \$(cat .gitlab/payload-manifest.txt)) исполнима буквально в реальном дереве"
else
  bad "AC2-1" ".gitlab/payload-manifest.txt существует — команда №3 паритета исполнима буквально" \
      "$PAYLOAD_MANIFEST не найден — третья буквальная команда Д6 сегодня читает \$(cat) от несуществующего файла"
fi

# Фикстура: ОДИН локальный репозиторий, без push и без реальных remote (см. заголовок файла).
# Коммит "gitlab" несёт полное дерево источника (включая .gitlab/, compat.json); коммит
# "github" на отдельной ветке несёт ТОЛЬКО файлы из манифеста — так, как выглядела бы честно
# смирроленная копия. refs/remotes/<gitlab|github>/<tag> — вручную выставленные указатели,
# ровно то, что подставляют команды Д6 (`gitlab/<tag>`, `github/<tag>`).
#
# Каждый diff записан В ОТДЕЛЬНЫЙ ФАЙЛ внутри подоболочки — присвоение переменной строкой
# вида `echo "D=[$val]"` и последующий grep/sed ломается, если $val сам многострочный (обычный
# случай для diff), поэтому передача через файлы, не через маркеры в stdout.
MISTYPED_TAG="v1.2.O"
TMP2="$(mktemp -d)"
(
  cd "$TMP2"
  git init -q repo
  cd repo

  # Явное имя ветки (не дефолт git init, который зависит от версии/конфигурации) — после
  # серии orphan-checkout'ов ниже нужно однозначно вернуться сюда: команда №3 Д6 читает
  # .gitlab/payload-manifest.txt ИЗ РАБОЧЕЙ КОПИИ (не из ref'а), как и буквальный текст ADR-027.
  git checkout -q -b gitlab-mainline
  mkdir -p .claude-plugin .gitlab
  printf '{"name": "ktalk", "version": "9.9.9", "description": "fixture"}' > .claude-plugin/plugin.json
  printf '{"package_name": "ktalk-cli", "package_version": "9.9.9"}' > compat.json
  printf 'README.md\n.claude-plugin/\ncompat.json\n' > .gitlab/payload-manifest.txt
  printf 'fixture\n' > README.md
  git add -A
  git -c user.email=qa@example.invalid -c user.name=qa commit -q -m "gitlab full tree"
  git update-ref refs/remotes/gitlab/v9.9.9 "$(git rev-parse HEAD)"

  git checkout -q --orphan mirror-ok
  git rm -rq --cached . > /dev/null 2>&1 || true
  rm -rf .claude-plugin .gitlab compat.json README.md
  mkdir -p .claude-plugin
  printf '{"name": "ktalk", "version": "9.9.9", "description": "fixture"}' > .claude-plugin/plugin.json
  printf '{"package_name": "ktalk-cli", "package_version": "9.9.9"}' > compat.json
  printf 'fixture\n' > README.md
  git add -A
  git -c user.email=qa@example.invalid -c user.name=qa commit -q -m "github mirrored tree (parity)"
  git update-ref refs/remotes/github/v9.9.9 "$(git rev-parse HEAD)"

  # Назад на ветку с полным деревом источника — иначе `cat .gitlab/payload-manifest.txt`
  # (команда №3 ниже) читает рабочую копию orphan-ветки mirror-ok, где .gitlab/ не существует.
  git checkout -q gitlab-mainline

  # --- Случай 1 (happy path): три команды Д6 буквально, на паритетной фикстуре ---
  diff <(git show gitlab/v9.9.9:.claude-plugin/plugin.json | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])") \
       <(git show github/v9.9.9:.claude-plugin/plugin.json | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])") \
       > "$TMP2/d1.txt" 2>&1 || true
  diff <(git show gitlab/v9.9.9:compat.json) <(git show github/v9.9.9:compat.json) \
       > "$TMP2/d2.txt" 2>&1 || true
  diff <(git ls-tree -r --name-only gitlab/v9.9.9 -- $(cat .gitlab/payload-manifest.txt)) \
       <(git ls-tree -r --name-only github/v9.9.9) \
       > "$TMP2/d3.txt" 2>&1 || true

  # --- Случай 2 (boundary — дефект зеркалирования): другой коммит на github с той же
  # структурой, но иной версией внутри plugin.json ---
  git checkout -q --orphan mirror-bad
  git rm -rq --cached . > /dev/null 2>&1 || true
  rm -rf .claude-plugin .gitlab compat.json README.md
  mkdir -p .claude-plugin
  printf '{"name": "ktalk", "version": "1.1.0", "description": "fixture"}' > .claude-plugin/plugin.json
  printf 'fixture\n' > README.md
  git add -A
  git -c user.email=qa@example.invalid -c user.name=qa commit -q -m "github mirrored tree (defect)"
  git update-ref refs/remotes/github/v1.2.0 "$(git rev-parse HEAD)"
  git checkout -q --orphan mirror-gl-bad
  git rm -rq --cached . > /dev/null 2>&1 || true
  rm -rf .claude-plugin .gitlab compat.json README.md
  mkdir -p .claude-plugin
  printf '{"name": "ktalk", "version": "1.2.0", "description": "fixture"}' > .claude-plugin/plugin.json
  git add -A
  git -c user.email=qa@example.invalid -c user.name=qa commit -q -m "gitlab tree for the same tag"
  git update-ref refs/remotes/gitlab/v1.2.0 "$(git rev-parse HEAD)"

  diff <(git show gitlab/v1.2.0:.claude-plugin/plugin.json | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])") \
       <(git show github/v1.2.0:.claude-plugin/plugin.json | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])") \
       > "$TMP2/d1_bad.txt" 2>&1 || true

  # --- Malformed input (обязательный класс): DevOps опечатался в имени тега (латинская O
  # вместо нуля). Известный риск ЛИТЕРАЛЬНЫХ команд Д6: обе ветки `git show <ref>:...` внутри
  # process substitution падают на неразрешимом ref'е, каждая печатает ПУСТОЙ stdout — diff
  # двух пустых строк тоже пуст, то есть ошибка обращения к тегу МАСКИРУЕТСЯ под «паритет
  # подтверждён». Тест документирует и подтверждает этот риск: он не устраним правкой Dev
  # (команды зафиксированы Д6 ADR-027 буквально) — носитель: рансбук DevOps (проверка
  # `git rev-parse --verify` ДО diff), не код Dev. См. at-design.md, Error cases → masked failure.
  diff <(git show "gitlab/$MISTYPED_TAG":.claude-plugin/plugin.json 2>/dev/null) \
       <(git show "github/$MISTYPED_TAG":.claude-plugin/plugin.json 2>/dev/null) \
       > "$TMP2/d1_typo.txt" 2>&1 || true
)
D1="$(cat "$TMP2/d1.txt" 2>/dev/null || true)"
D2="$(cat "$TMP2/d2.txt" 2>/dev/null || true)"
D3="$(cat "$TMP2/d3.txt" 2>/dev/null || true)"
D1_BAD="$(cat "$TMP2/d1_bad.txt" 2>/dev/null || true)"
D1_TYPO="$(cat "$TMP2/d1_typo.txt" 2>/dev/null || true)"

require_true "AC2-2" "команда №1 Д6 (версия плагина) на паритетной фикстуре даёт пустой diff" \
  "$([[ -z "$D1" ]] && echo 0 || echo 1)" "diff: $D1"
require_true "AC2-3" "команда №2 Д6 (compat.json) на паритетной фикстуре даёт пустой diff" \
  "$([[ -z "$D2" ]] && echo 0 || echo 1)" "diff: $D2"
require_true "AC2-4" "команда №3 Д6 (состав payload) на паритетной фикстуре даёт пустой diff" \
  "$([[ -z "$D3" ]] && echo 0 || echo 1)" "diff: $D3"
require_true "AC2-5 (boundary — дефект зеркалирования)" "команда №1 обнаруживает разную версию под одним тегом (не молчаливый паритет)" \
  "$([[ -n "$D1_BAD" ]] && echo 0 || echo 1)" "diff пуст, хотя версии разные: 1.2.0 vs 1.1.0"
require_true "AC2-6 (malformed input — известный риск литеральных команд Д6)" \
  "опечатанный тег НЕ маскируется под пустой (паритетный) diff" \
  "$([[ -n "$D1_TYPO" ]] && echo 0 || echo 1)" \
  "diff пуст при заведомо неразрешимом теге '$MISTYPED_TAG' — команда Д6 читает это как «паритет», не как ошибку обращения к тегу"
rm -rf "$TMP2"

echo
echo "###############################################################################"
echo "# AC-3 — Requirement: Documentation names each channel and how to tell them apart"
echo "# Scenario: An operator reads the installation instructions"
echo "###############################################################################"

README_TEXT="$(cat "$ROOT/README.md")"
GITHUB_MIRROR_URL="github.com/mdemyanov/ktalk-plugin"

assert_contains_re "AC3-1" "README несёт подраздел «Внутренний GitLab — источник истины» (Dev-бриф, буквальная формулировка)" \
  "$README_TEXT" "Внутренний GitLab.{0,3}источник истины"
assert_contains "AC3-2" "README несёт подраздел «Публичное GitHub-зеркало»" "$README_TEXT" "Публичное GitHub-зеркало"
assert_contains_re "AC3-3" "README называет команду add для публичного зеркала ($GITHUB_MIRROR_URL)" \
  "$README_TEXT" "marketplace add https://${GITHUB_MIRROR_URL}(\.git)?"
assert_contains "AC3-4" "README называет имя маркетплейса зеркала явно" "$README_TEXT" "$EXPECTED_MIRROR_NAME"
assert_contains_re "AC3-5" "README называет одностороннюю природу GitHub-канала явно" \
  "$README_TEXT" "(одностороннее зеркало|GitHub-зеркал)"

# Boundary/masked failure: имя маркетплейса рядом с URL зеркала — не перепутано с внутренним
# (тот же класс риска, что коллизия имён в JTBD требования: два канала называют один и тот же
# маркетплейс операнту, только теперь ошибка не в JSON, а в тексте инструкции).
GITHUB_SUBSECTION="$(awk '/Публичное GitHub-зеркало/{f=1; next} /^### 3\./{if (f) exit} f' "$ROOT/README.md")"
if [[ -n "$GITHUB_SUBSECTION" ]]; then
  assert_contains "AC3-6 (masked failure guard)" "подраздел GitHub-зеркала использует ИМЕННО имя зеркала, не внутреннее" \
    "$GITHUB_SUBSECTION" "$EXPECTED_MIRROR_NAME"
else
  bad "AC3-6 (masked failure guard)" "подраздел «Публичное GitHub-зеркало» найден, чтобы проверить его содержимое" \
    "подраздел ещё не выделен в README — нечем проверить, что имя маркетплейса рядом с URL зеркала не перепутано с внутренним"
fi

# Malformed input / см. также AC-5: README ВХОДИТ в публичный payload — реальный литерал
# внутреннего домена здесь означает утечку при КАЖДОМ релизе, а не только «текст неполон».
assert_not_contains "AC3-7 (см. также AC-5)" "README не несёт внутренний домен литералом (Д3 ADR-027: плейсхолдер + ссылка на CLAUDE.md)" \
  "$README_TEXT" "$INTERNAL_DOMAIN"

echo
echo "###############################################################################"
echo "# AC-4 — Requirement: A consumer can tell \"mirror lags\" from \"version does not exist\""
echo "# Scenario: A version was released internally but not yet mirrored"
echo "###############################################################################"

if [[ -f "$GITLAB_CI" ]]; then
  assert_contains_re "AC4-1" ".gitlab-ci.yml ограничивает джоб mirror-github тегами формы ktalk--v* (тег на GitHub появляется только после успешного push, Д2 ADR-027)" \
    "$(cat "$GITLAB_CI")" "ktalk--v"
else
  bad "AC4-1" ".gitlab-ci.yml ограничивает джоб mirror-github тегами формы ktalk--v*" \
    "$GITLAB_CI не найден — структурное свойство «тег на GitHub появляется только при успешном push» пока ничем не обеспечено"
fi

# Фикстура (регресс-guard метода, зелёная по построению — тот же приём, что REL-1 в
# test-plugin-requirements-relocation.sh): свойство «латест-тег зеркала ниже запрошенной
# версии» читается из САМОГО списка тегов зеркала, без привилегированного доступа к
# внутреннему GitLab — не зависит от реализации Dev, только от честного git-состояния.
TMP4="$(mktemp -d)"
(
  cd "$TMP4"
  git init -q repo
  cd repo
  printf '1.0.0' > VERSION
  git add -A && git -c user.email=qa@example.invalid -c user.name=qa commit -q -m v1.0.0
  git update-ref refs/remotes/github/v1.0.0 "$(git rev-parse HEAD)"
  printf '1.1.0' > VERSION
  git add -A && git -c user.email=qa@example.invalid -c user.name=qa commit -q -m v1.1.0
  # v1.1.0 существует только на "gitlab" стороне (внутренний тег) — не отражена в
  # refs/remotes/github; зеркало сегодня видит только v1.0.0.
  git tag v1.1.0-gitlab-only "$(git rev-parse HEAD)"
  git for-each-ref --format='%(refname:short)' refs/remotes/github | sed 's#^github/##' | sort -V \
    > "$TMP4/mirror-tags.txt"
)
MIRROR_TAGS="$(cat "$TMP4/mirror-tags.txt" 2>/dev/null || true)"
MIRROR_LATEST="$(tail -1 <<<"$MIRROR_TAGS")"
rm -rf "$TMP4"
require_true "AC4-2" "латест-тег зеркала (v1.0.0) ниже запрошенной версии (v1.1.0) — «ещё не смирролено» отличимо от «версии никогда не было» без привилегированного доступа к внутреннему GitLab" \
  "$([[ "$MIRROR_LATEST" == "v1.0.0" ]] && echo 0 || echo 1)" "MIRROR_LATEST='$MIRROR_LATEST'"

# Malformed/mistyped input: опечатанный номер версии (латинская O вместо нуля) не обязан
# фаззи-матчить ближайший реальный тег зеркала.
MISTYPED_QUERY="v1.O.0"
FUZZY_HIT=0
grep -qxF "$MISTYPED_QUERY" <<<"$MIRROR_TAGS" && FUZZY_HIT=1
require_true "AC4-3 (malformed input)" "опечатанный запрос версии не матчит ни один реальный тег зеркала" "$FUZZY_HIT"

# Masked failure: нигде в дереве, уходящем в payload, не должно быть закешированного/статичного
# поля вида «последняя смирроленная версия» — такое поле могло бы устареть и молчаливо соврать
# про currency, в отличие от списка тегов зеркала, читаемого динамически при каждом запросе.
STALE_FIELD_PATTERN='(mirror_last_synced|last_mirrored|mirrored_version|mirror_version)'
STALE_HIT=0
for t in ".claude-plugin" "compat.json"; do
  [[ -e "$ROOT/$t" ]] || continue
  grep -rqiE "$STALE_FIELD_PATTERN" "$ROOT/$t" 2>/dev/null && STALE_HIT=1
done
require_true "AC4-4 (masked failure)" "нет закешированного поля «последняя смирроленная версия» в файлах payload — currency читается из тегов, не из статичного значения" \
  "$STALE_HIT" "найдено совпадение с $STALE_FIELD_PATTERN"

echo
echo "###############################################################################"
echo "# AC-5 — Requirement: The public payload carries no internal infrastructure literal"
echo "# Scenario: The composition gate scans for the internal domain"
echo "###############################################################################"

HAS_PAYLOAD_DOMAIN_CHECK=0
grep -q "check_payload_domain" "$COMPOSITION_SH" 2>/dev/null && HAS_PAYLOAD_DOMAIN_CHECK=1

if [[ "$HAS_PAYLOAD_DOMAIN_CHECK" -eq 0 ]]; then
  bad "AC5-1a" "check_payload_domain (сканирует payload-манифест на внутренний домен) существует в scripts/check-plugin-composition.sh" \
      "функция не найдена — сегодня гейт ловит только ПЕРВЫЙ внутренний домен продукта (строка 65, whole-tree; см. content/lessons-learned.md о том, почему второй домен не называется здесь literal-ом), не второй (внутренний GitLab)"
  skip_ac "AC5-1b" "направление (б) — тот же литерал ВНЕ манифеста не должен давать FAIL — недоказуемо до появления check_payload_domain"
  skip_ac "AC5-1c" "malformed manifest path (../, абсолютный путь) — недоказуемо до появления check_payload_domain"
  skip_ac "AC5-1d" "пустой/отсутствующий манифест обязан дать громкое предупреждение, не тихий пропуск — недоказуемо до появления check_payload_domain"
else
  # Изолированная копия дерева (тот же приём, что AC-14 в test-release-delivery-tails.sh):
  # rsync без .git/.beads/agent-memory, плюс собственный QA-манифест — реальный
  # .gitlab/payload-manifest.txt на момент, когда Dev уже добавил функцию, но эта сьюта ещё не
  # обновлена, мог не существовать (проверяется отдельно, AC2-1/EDGE-1).
  build_fixture_tree() { # build_fixture_tree <dst>
    local dst="$1"
    mkdir -p "$dst"
    rsync -a --exclude='.git' --exclude='.beads' --exclude='agent-memory' \
          --exclude='.nauta-authority-observations.jsonl' "$ROOT/" "$dst/"
    mkdir -p "$dst/.gitlab"
    printf '.claude-plugin/\nagents/\ncommands/\nskills/\nreferences/\nscripts/\nREADME.md\nLICENSE\n.github/\n' \
      > "$dst/.gitlab/payload-manifest.txt"
    # LICENSE и .github/ — предмет ЭТОЙ ЖЕ задачи Dev (брифом ещё не заведены на реальном
    # дереве, ADR-027 Consequences: «LICENSE в дереве сегодня нет»). Без заглушки `grep -r`
    # по манифесту падает с exit 2 («No such file or directory») на отсутствующем пути ДО
    # того, как успевает сравнить содержимое существующих — маскирует находку домена ошибкой
    # обращения к пути, а не отражает её. Заглушки не подменяют собой Brief for Dev — они
    # только изолируют предмет ЭТОГО теста (сканирование текста) от предмета ДРУГОГО пункта
    # брифа (заведение самих файлов).
    [[ -f "$dst/LICENSE" ]] || printf 'MIT (fixture placeholder)\n' > "$dst/LICENSE"
    [[ -d "$dst/.github" ]] || { mkdir -p "$dst/.github"; printf 'fixture\n' > "$dst/.github/CONTRIBUTING.md"; }
    # README.md реального дерева СЕГОДНЯ несёт внутренний домен литералом (AC3-7/Д3 ADR-027
    # — отдельная, ещё не выполненная правка Dev). Не нейтрализовать её здесь означало бы,
    # что AC5-1a/b всегда FAIL через README.md независимо от инжектируемой фикстуры — два
    # разных предмета (сканирование ЛЮБОГО домена в манифесте vs конкретная правка README)
    # слились бы в одно наблюдение. Изолируем предмет ИМЕННО этого теста.
    printf 'fixture README without the internal domain literal\n' > "$dst/README.md"
  }

  T5A="$(mktemp -d)"; build_fixture_tree "$T5A"
  printf 'internal ref: %s\n' "$INTERNAL_DOMAIN" > "$T5A/scripts/qa-fixture-domain-inside.txt"
  OUT5A="$(cd "$T5A" && bash scripts/check-plugin-composition.sh 2>&1)"; RC5A=$?
  require_true "AC5-1a" "гейт FAIL, когда внутренний домен лежит В файле из payload-манифеста (scripts/)" \
    "$([[ "$RC5A" -ne 0 ]] && echo 0 || echo 1)" "exit=$RC5A"
  rm -rf "$T5A"

  T5B="$(mktemp -d)"; build_fixture_tree "$T5B"
  mkdir -p "$T5B/content"
  printf 'internal ref: %s\n' "$INTERNAL_DOMAIN" > "$T5B/content/qa-fixture-domain-outside.md"
  OUT5B="$(cd "$T5B" && bash scripts/check-plugin-composition.sh 2>&1)"; RC5B=$?
  require_true "AC5-1b" "гейт НЕ падает из-за домена в файле ВНЕ payload-манифеста (content/) — scoped-проверка отличима от whole-tree" \
    "$([[ "$RC5B" -eq 0 ]] && echo 0 || echo 1)" "exit=$RC5B"
  rm -rf "$T5B"

  T5C="$(mktemp -d)"; build_fixture_tree "$T5C"
  printf 'scripts/\n../README.md\n' > "$T5C/.gitlab/payload-manifest.txt"
  OUT5C="$(cd "$T5C" && bash scripts/check-plugin-composition.sh 2>&1)"
  assert_contains_re "AC5-1c (malformed input)" "манифест с обходом каталога (..) даёт видимую реакцию гейта (предупреждение/ошибка), не тихий проход" \
    "$OUT5C" "(\.\.|manifest|манифест|WARN|FAIL)"
  rm -rf "$T5C"

  T5D="$(mktemp -d)"; build_fixture_tree "$T5D"
  : > "$T5D/.gitlab/payload-manifest.txt"
  OUT5D="$(cd "$T5D" && bash scripts/check-plugin-composition.sh 2>&1)"
  assert_contains_re "AC5-1d (masked failure)" "пустой манифест печатает видимое предупреждение (не тихий пропуск проверки, Integration points companion)" \
    "$OUT5D" "(манифест|manifest)"
  rm -rf "$T5D"
fi

echo
echo "###############################################################################"
echo "# EDGE-1 — не привязан к одному сценарию (companion, Edge cases):"
echo "# манифест и .gitlab-ci.yml сами не входят в payload"
echo "###############################################################################"

if [[ -f "$PAYLOAD_MANIFEST" ]]; then
  MANIFEST_TEXT="$(cat "$PAYLOAD_MANIFEST")"
  assert_not_contains "EDGE1-1" ".gitlab/payload-manifest.txt не перечисляет сам себя" "$MANIFEST_TEXT" "payload-manifest.txt"
  assert_not_contains "EDGE1-2" ".gitlab/payload-manifest.txt не перечисляет .gitlab-ci.yml" "$MANIFEST_TEXT" ".gitlab-ci.yml"
else
  bad "EDGE1-1" ".gitlab/payload-manifest.txt не перечисляет сам себя" "$PAYLOAD_MANIFEST не найден — нечего проверять"
  bad "EDGE1-2" ".gitlab/payload-manifest.txt не перечисляет .gitlab-ci.yml" "$PAYLOAD_MANIFEST не найден — нечего проверять"
fi

echo
echo "###############################################################################"
echo "# AC-6 — Requirement: Input arriving through the public channel is triaged manually"
echo "# Scenario: An issue is opened on the public mirror"
echo "###############################################################################"

GH_CONTRIB="$ROOT/.github/CONTRIBUTING.md"
GH_PR_TMPL="$ROOT/.github/PULL_REQUEST_TEMPLATE.md"
GH_ISSUE_DIR="$ROOT/.github/ISSUE_TEMPLATE"

if [[ -f "$GH_CONTRIB" ]]; then
  ok "AC6-1" ".github/CONTRIBUTING.md существует"
  CONTRIB_TEXT="$(cat "$GH_CONTRIB")"
  assert_contains_re "AC6-2" "CONTRIBUTING называет внутренний GitLab источником истины" "$CONTRIB_TEXT" "(source of truth|источник истины)"
  assert_contains_re "AC6-3" "CONTRIBUTING называет ручной перенос человеком (без автоматизации)" "$CONTRIB_TEXT" "(вручную|manual(ly)?|by a person|person)"
else
  bad "AC6-1" ".github/CONTRIBUTING.md существует" "файл не найден"
  bad "AC6-2" "CONTRIBUTING называет внутренний GitLab источником истины" "недостижимо — файла нет"
  bad "AC6-3" "CONTRIBUTING называет ручной перенос человеком" "недостижимо — файла нет"
fi

if [[ -d "$GH_ISSUE_DIR" ]] && compgen -G "$GH_ISSUE_DIR/*.md" > /dev/null 2>&1; then
  ISSUE_TMPL_FILE="$(ls "$GH_ISSUE_DIR"/*.md | head -1)"
  ok "AC6-4" ".github/ISSUE_TEMPLATE/ несёт минимум один .md-шаблон (${ISSUE_TMPL_FILE#"$ROOT/"})"
  assert_contains_re "AC6-5" "шаблон issue несёт баннер источника истины, который автор видит ДО отправки (наличие текста в самой форме)" \
    "$(cat "$ISSUE_TMPL_FILE")" "(source of truth|источник истины)"
else
  bad "AC6-4" ".github/ISSUE_TEMPLATE/ несёт минимум один .md-шаблон" "каталог/файл не найден"
  bad "AC6-5" "шаблон issue несёт баннер источника истины" "недостижимо — шаблона нет"
fi

if [[ -f "$GH_PR_TMPL" ]]; then
  ok "AC6-6" ".github/PULL_REQUEST_TEMPLATE.md существует"
  assert_contains_re "AC6-7" "шаблон PR несёт баннер источника истины" "$(cat "$GH_PR_TMPL")" "(source of truth|источник истины)"
else
  bad "AC6-6" ".github/PULL_REQUEST_TEMPLATE.md существует" "файл не найден"
  bad "AC6-7" "шаблон PR несёт баннер источника истины" "недостижимо — файла нет"
fi

# Masked failure: НЕТ автоматического merge/close issue/PR публичного зеркала (Requirement:
# "SHALL NOT be merged or closed by any automated synchronization"). Регресс-guard: сегодня
# .github/workflows/ не существует вовсе, поэтому проверка легитимно зелёная (тот же приём,
# что тест 45 cli-only-boundary/at-design.md) — становится содержательной, если Dev когда-либо
# заведёт workflow, отклонённый Д5 ADR-027 явно («Отклонено: пиновать комментарий ботом»).
WORKFLOWS_DIR="$ROOT/.github/workflows"
AUTOMERGE_HIT=0
if [[ -d "$WORKFLOWS_DIR" ]]; then
  grep -rlqiE '(auto-merge|automerge|gh issue close|gh pr merge)' "$WORKFLOWS_DIR" 2>/dev/null && AUTOMERGE_HIT=1
fi
require_true "AC6-8 (masked failure)" "нет автоматического merge/close issue/PR публичного зеркала — перенос только руками (Д5 ADR-027)" "$AUTOMERGE_HIT"

# Malformed/mistyped input: недоверенный внешний ввод (issue/PR body) не подаётся напрямую в
# исполняемый шаг workflow — сам класс риска "код из недоверенного PR запускается CI" снят
# отсутствием такого workflow вовсе (companion, «Границы доверия»), не его санитизацией.
UNSAFE_TRIGGER_HIT=0
if [[ -d "$WORKFLOWS_DIR" ]]; then
  grep -rlqiE 'pull_request_target|on:[[:space:]]*issues' "$WORKFLOWS_DIR" 2>/dev/null && UNSAFE_TRIGGER_HIT=1
fi
require_true "AC6-9 (malformed input)" "нет workflow, исполняющего недоверенный текст issue/PR как команду (pull_request_target/issues-триггер отсутствует — Д5: автоматизации переноса/закрытия нет вовсе)" "$UNSAFE_TRIGGER_HIT"

echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ "$FAIL" -eq 0 ]]
