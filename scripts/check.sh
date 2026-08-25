#!/usr/bin/env bash
# check.sh — single entry-point для всех валидаций.
#
# Usage:
#   bash scripts/check.sh [--fast | --full]
#
# --fast (default): validate-content.py + validate-profile.py + check-adr-line-limit.py
#         (ADR-013).
# --full: + check-backlog-closure.py (ADR-012 Д4) + id-check.sh (ADR-038, решение владельца
#         Р22) + self-test harness (test-check-adr-line-limit.sh, test-check-backlog-
#         closure.sh, test-check-breaking-change-section.sh, test-check-id.sh — последняя
#         зарегистрирована DEV-022; до того доставлялась payload'ом и не бежала нигде).
#
# ADR-037 (content/00-project/adr/ADR-037-gate-roster-from-delivery-basis.md +
# content/40-architecture/ADR-037-gate-roster-from-delivery-basis-spec.md): перечень вызовов
# ниже — намерение («какие гейты этот раннер знает вообще»), НЕ факт обязательности. Факт —
# .nauta-scripts-basis.yaml (ADR-030 Д3), единственная запись дерева-потребителя о том, что
# ему привезли. Дерево-источник payload'а (само это дерево, опознаётся по подписи
# bin/deliver.sh) — исключение: там обязателен весь перечень целиком, найденный рядом базис
# на это не влияет (ADR-037 Д3).

set -euo pipefail

# uv-guard: обязательная зависимость
if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: 'uv' не найден в PATH. Установите: https://docs.astral.sh/uv/getting-started/installation/" >&2
  exit 1
fi

MODE="${1:---fast}"

case "$MODE" in
  --fast|--full|-h|--help) ;;
  *)
    echo "Usage: $0 [--fast | --full]" >&2
    exit 2
    ;;
esac

if [[ "$MODE" == "-h" ]] || [[ "$MODE" == "--help" ]]; then
  cat <<EOF
Usage: $0 [--fast | --full]

Modes:
  --fast (default)  Run validators (validate-content.py + validate-profile.py +
                    check-adr-line-limit.py). Quick gate. Suitable for pre-commit hook.
  --full            Run --fast checks + check-backlog-closure.py (ADR-012 Д4 — lives in
                    --full, not --fast) + id-check.sh (ADR-038 identifier registry audit;
                    --full by owner ruling Р22) + self-test harness (test-check-adr-line-
                    limit.sh, test-check-backlog-closure.sh,
                    test-check-breaking-change-section.sh, test-check-id.sh). Suitable for
                    CI / pre-merge gate.

Obligation (ADR-037): which of the gates above MUST exist in this tree is resolved from
.nauta-scripts-basis.yaml (delivery record), not hardcoded — see ADR-037-spec §2.

Exit codes:
  0  All checks passed
  1  Validator, gate, suite failed, or the delivery basis could not be read
  2  Invalid usage
EOF
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# ADR-037 §2 — разрешение режима обязательности. Выполняется РОВНО один раз, здесь, ДО
# первого вызова гейта — вердикт о том, обязана ли каждая позиция перечня существовать,
# принимается прежде, чем побежит хоть один шаг.
# ---------------------------------------------------------------------------
BASIS_FILE="$REPO_ROOT/.nauta-scripts-basis.yaml"
ORIGIN_INSTALLER="$REPO_ROOT/bin/deliver.sh"

# Признак источника — СОДЕРЖИМОЕ, не имя файла (ADR-037-spec §2): bin/deliver.sh — родовой
# путь, у потребителя может лежать одноимённый чужой скрипт выкладки. Подпись — литерал имени
# базиса (".nauta-scripts-basis.yaml", несущая строка BASIS_NAME= в самом bin/deliver.sh:31)
# в тексте установщика: писатель базиса обязан называть файл, который пишет.
ORIGIN=0
if [[ -f "$ORIGIN_INSTALLER" ]] && grep -Fq -- ".nauta-scripts-basis.yaml" "$ORIGIN_INSTALLER"; then
  ORIGIN=1
fi

OBLIGATION_MODE="STRICT"   # STRICT | DELIVERED
DECLARED_FILES=""          # \n-разделённый список путей files: (заполняется в DELIVERED)
SKIPPED_FILES=""           # \n-разделённый список путей skip: (заполняется в DELIVERED)
BASIS_NAUTA_VERSION=""
BASIS_NAUTA_REF_SHA=""
BASIS_SYNCED_AT=""
BASIS_FILES_COUNT=""

# --- §4 ADR-037-spec: читатели базиса — блочный awk, та же форма, что уже разбирает базис
#     bin/deliver.sh (секция 3 того файла): вход в блок по заголовку без отступа, выход — на
#     первой строке без отступа. Каждый читатель обязан ВСЕГДА возвращать 0 (см. заметку в
#     bin/deliver.sh про set -euo pipefail и command substitution внутри присваивания —
#     "не нашёл" не ошибка выполнения самого читателя, различие видно по ПУСТОТЕ вывода).

_basis_files_paths() {
  awk '
    /^files:[ \t]*(#.*)?$/ { infiles=1; next }
    infiles && $0 ~ /^[^ \t]/ { infiles=0 }
    infiles {
      line=$0
      sub(/^[ \t]+/, "", line)
      if (line == "" || line ~ /^#/) next
      colon = index(line, ":")
      if (colon == 0) next
      key = substr(line, 1, colon-1)
      gsub(/[ \t]+$/, "", key)
      print key
    }
  ' "$BASIS_FILE"
}

_basis_skip_paths() {
  awk '
    /^skip:[ \t]*(#.*)?$/ { inskip=1; next }
    inskip && $0 ~ /^[^ \t]/ { inskip=0 }
    inskip {
      line=$0
      sub(/^[ \t]*-[ \t]*/, "", line)
      gsub(/^[ \t]+/, "", line); gsub(/[ \t]+$/, "", line)
      if (line == "" || line ~ /^#/) next
      print line
    }
  ' "$BASIS_FILE"
}

_basis_has_files_block() {
  grep -qE '^files:[[:space:]]*(#.*)?$' "$BASIS_FILE"
}

_basis_top_level_scalar() {
  # $1 = ключ (nauta_version|nauta_ref_sha|synced_at|files_count). Печатает значение с
  # обрезанными кавычками, либо ничего, если ключ отсутствует — awk без явного `exit 1` в
  # END всегда завершается нулём независимо от того, нашлось совпадение или нет.
  local key="$1"
  awk -v key="$key" '
    index($0, key ":") == 1 {
      line = $0
      sub("^" key ":[ \t]*", "", line)
      gsub(/[ \t]+$/, "", line)
      gsub(/^"/, "", line); gsub(/"$/, "", line)
      print line
      exit
    }
  ' "$BASIS_FILE"
}

_basis_delivery_complete() {
  # §4: терпит кавычки вокруг булева значения ("true"/"false") — единственное место, где
  # терпимость дешевле строгости (закавыченный руками true иначе дал бы неверную причину —
  # "версия до ADR-037" вместо отказа по существу). Пусто — «ключа нет», не «false»: разницу
  # между LEGACY и PARTIAL несёт ПУСТОТА против буквального "false", не отсутствие вывода.
  grep -E '^delivery_complete:[[:space:]]*"?(true|false)"?[[:space:]]*$' "$BASIS_FILE" 2>/dev/null \
    | sed -E 's/^delivery_complete:[[:space:]]*"?(true|false)"?[[:space:]]*$/\1/' \
    | head -n1 || true
}

_count_nonempty_lines() {
  # $1 = \n-разделённая строка (может быть пустой). grep -c без совпадений выходит 1 —
  # гасится здесь один раз, а не у каждого вызывающего.
  local text="$1"
  if [[ -z "$text" ]]; then
    echo 0
    return 0
  fi
  printf '%s\n' "$text" | grep -c . || true
}

_in_newline_list() {
  # $1 = искомый путь, $2 = \n-разделённый список (может быть пустой строкой).
  local needle="$1" haystack="$2"
  [[ -n "$haystack" ]] && printf '%s\n' "$haystack" | grep -Fxq -- "$needle"
}

if [[ "$ORIGIN" -eq 1 ]]; then
  # Д3/Д4: признак источника проверяется ПЕРВЫМ и только УЖЕСТОЧАЕТ — найденный рядом базис
  # обязательств дерева-источника не сужает.
  OBLIGATION_MODE="STRICT"
  if [[ -f "$BASIS_FILE" ]]; then
    echo "[INFO] в дереве-источнике payload'а найден .nauta-scripts-basis.yaml — на обязательства он не"
    echo "       влияет: здесь обязателен весь перечень гейтов (ADR-037 Д3)."
  fi
elif [[ -f "$BASIS_FILE" ]]; then
  # Порядок вердиктов обязателен (§2/§4 ADR-037-spec): завершённость — РАНЬШЕ структурных.
  # Обрыв на первой же записи даёт базис с нулём записей И complete=false — назвать его
  # "нечитаемым" значило бы соврать про причину (Д5).
  BASIS_DELIVERY_COMPLETE="$(_basis_delivery_complete)"
  if [[ -z "$BASIS_DELIVERY_COMPLETE" ]]; then
    echo "ERROR: в .nauta-scripts-basis.yaml нет ключа delivery_complete — завершённость доставки по этому" >&2
    echo "базису неизвестна. Две гипотезы, механизм их не различает: базис написан версией nauta до ADR-037" >&2
    echo "либо блок метаданных правился руками. Ни один гейт не запущен. Почини: повтори" >&2
    echo "/nauta:sync-scripts — команда перепишет базис целиком, новый несёт ключ." >&2
    exit 1
  fi
  if [[ "$BASIS_DELIVERY_COMPLETE" == "false" ]]; then
    echo "ERROR: .nauta-scripts-basis.yaml объявляет незавершённую доставку (delivery_complete: false) —" >&2
    echo "синк был прерван, дерево укомплектовано частично. Считать \"мне столько и привезли\" нельзя: гейты," >&2
    echo "отсутствующие из-за обрыва, молчали бы законно (ADR-037 Д5). Ни один гейт не запущен. Почини:" >&2
    echo "повтори /nauta:sync-scripts — доставка докопирует недостающее (ADR-030 Д7)." >&2
    exit 1
  fi
  if ! _basis_has_files_block; then
    echo "ERROR: .nauta-scripts-basis.yaml в корне дерева есть, но прочитать его не удалось: блока files: нет." >&2
    echo "check.sh не может определить, что ему доставлено, и не станет молча считать, что не доставлено" >&2
    echo "ничего (ADR-007 Д1; ADR-031 Д3: \"не смог прочитать\" ≠ \"нарушений нет\"). Ни один гейт не" >&2
    echo "запущен. Почини: повтори /nauta:sync-scripts — команда перепишет базис целиком; если файл" >&2
    echo "правился руками, верни форму из ADR-030-spec §5." >&2
    exit 1
  fi
  DECLARED_FILES="$(_basis_files_paths)"
  DECLARED_COUNT="$(_count_nonempty_lines "$DECLARED_FILES")"
  if [[ "$DECLARED_COUNT" -eq 0 ]]; then
    echo "ERROR: .nauta-scripts-basis.yaml в корне дерева есть, но прочитать его не удалось: ни одной записи" >&2
    echo "в files:. check.sh не может определить, что ему доставлено, и не станет молча считать, что не" >&2
    echo "доставлено ничего (ADR-007 Д1; ADR-031 Д3: \"не смог прочитать\" ≠ \"нарушений нет\"). Ни один" >&2
    echo "гейт не запущен. Почини: повтори /nauta:sync-scripts — команда перепишет базис целиком; если файл" >&2
    echo "правился руками, верни форму из ADR-030-spec §5." >&2
    exit 1
  fi
  BASIS_FILES_COUNT="$(_basis_top_level_scalar files_count)"
  if [[ -z "$BASIS_FILES_COUNT" ]] || [[ "$BASIS_FILES_COUNT" != "$DECLARED_COUNT" ]]; then
    echo "ERROR: .nauta-scripts-basis.yaml обрезан: files_count объявляет ${BASIS_FILES_COUNT:-<нет>} записей," >&2
    echo "разобрать удалось ${DECLARED_COUNT}. Часть заявленного пропала бы бесшумно — гейты потерянных" >&2
    echo "строк выглядели бы как недоставленные, а не как порча (ADR-037 Д5). Ни один гейт не запущен." >&2
    echo "Почини: повтори /nauta:sync-scripts — команда перепишет базис целиком." >&2
    exit 1
  fi
  # skip_count — контрольное число секции skip:, но НЕ симметрично files_count: files:
  # правится ТОЛЬКО писателем ("Не редактируйте руками значения" — шапка базиса), а skip:
  # явно и санкционированно правится потребителем руками (та же шапка: "секцию skip: —
  # можно"; §3 ADR-037-spec). Симметричная проверка (`!=`, как у files_count) ловила бы ОБЕ
  # стороны расхождения — и обрез (`разобрано < объявлено`, порча), и САНКЦИОНИРОВАННОЕ
  # ручное добавление строки (`разобрано > объявлено`, ожидаемое поведение) — как одну и ту
  # же ошибку, блокируя каждый прогон/коммит до повторного синка за действие, которое базис
  # сам разрешает без синка. Направленное сравнение (`-lt`) ловит ТОЛЬКО обрез: если строк
  # оказалось МЕНЬШЕ заявленного — часть заявленного пропала бы бесшумно, путь, заявленный
  # ТОЛЬКО через skip: (§3), тихо перестал бы считаться заявленным — ровно та дыра, ради
  # закрытия которой заведена сама skip-клауза правила declared.
  # Если строк оказалось БОЛЬШЕ — это ручное добавление, санкционировано, не ошибка.
  SKIPPED_FILES="$(_basis_skip_paths)"
  SKIPPED_COUNT="$(_count_nonempty_lines "$SKIPPED_FILES")"
  BASIS_SKIP_COUNT="$(_basis_top_level_scalar skip_count)"
  if [[ -z "$BASIS_SKIP_COUNT" ]] \
      || ! [[ "$BASIS_SKIP_COUNT" =~ ^[0-9]+$ ]] \
      || [[ "$SKIPPED_COUNT" -lt "$BASIS_SKIP_COUNT" ]]; then
    echo "ERROR: .nauta-scripts-basis.yaml обрезан: skip_count объявляет ${BASIS_SKIP_COUNT:-<нет>} записей," >&2
    echo "разобрать удалось ${SKIPPED_COUNT} в skip:. Часть заявленного через skip: пропала бы бесшумно —" >&2
    echo "путь, добавленный в skip: до первого синка, перестал бы считаться заявленным (§3 ADR-037-spec)," >&2
    echo "и его гейт выключился бы тихо и навсегда (ADR-037 Д5). Ни один гейт не запущен. Почини: повтори" >&2
    echo "/nauta:sync-scripts — команда перепишет базис целиком." >&2
    exit 1
  fi

  # Базис обязан заявлять САМ scripts/check.sh — раннер, которым он читается. Защита в
  # глубину поверх писателя в bin/deliver.sh: базис без этой записи, даже при непустом
  # files: и сошедшемся files_count, — признак свернувшегося состава, не полноценное
  # описание доставки (§4 ADR-037-spec: "check.sh девятая позиция payload'а, к моменту его
  # появления в дереве базис заявляет минимум девять файлов").
  if ! { _in_newline_list "scripts/check.sh" "$DECLARED_FILES" \
      || _in_newline_list "scripts/check.sh" "$SKIPPED_FILES"; }; then
    echo "ERROR: .nauta-scripts-basis.yaml не заявляет сам scripts/check.sh — раннер, которым он читается." >&2
    echo "Базис, управляющий check.sh, обязан называть check.sh в files: или в skip: (§4 ADR-037-spec:" >&2
    echo "check.sh — девятая позиция payload'а, к моменту его появления в дереве базис заявляет минимум" >&2
    echo "девять файлов). Отсутствие этой записи — признак свернувшегося базиса (например, обрыв сразу" >&2
    echo "после предварительной записи писателя, до переобработки состава), а не полноценное описание" >&2
    echo "доставки этого дерева. Ни один гейт не запущен. Почини: повтори /nauta:sync-scripts — команда" >&2
    echo "перепишет базис целиком." >&2
    exit 1
  fi

  BASIS_NAUTA_VERSION="$(_basis_top_level_scalar nauta_version)"
  BASIS_NAUTA_REF_SHA="$(_basis_top_level_scalar nauta_ref_sha)"
  BASIS_SYNCED_AT="$(_basis_top_level_scalar synced_at)"
  OBLIGATION_MODE="DELIVERED"
  echo "[INFO] базис доставки .nauta-scripts-basis.yaml: nauta ${BASIS_NAUTA_VERSION}, ref ${BASIS_NAUTA_REF_SHA}, синк ${BASIS_SYNCED_AT},"
  echo "       заявлено файлов: ${BASIS_FILES_COUNT}. Обязательными считаются только заявленные (ADR-037 Д1)."
else
  # Д4: строгое умолчание — отсутствие базиса не значит "ничего не доставлено". Право на
  # молчание выдаёт исключительно прочитанный и завершённый базис.
  OBLIGATION_MODE="STRICT"
fi

failed=0
run_check() {
  local name="$1" cmd="$2"
  echo "▶ $name"
  if eval "$cmd"; then
    echo "  ✓ $name"
  else
    echo "  ✗ $name FAILED" >&2
    failed=1
  fi
}

# _declared <rel> — §3 ADR-037-spec: позиция заявлена, если режим STRICT (весь перечень
# заявлен по умолчанию), либо путь есть в files: базиса, либо путь есть в skip: базиса —
# skip: заявляет НАРАВНЕ с files: (иначе путь, добавленный в skip: до первого синка, не
# получает записи в files: никогда, и гейт выключился бы тихо и навсегда).
_declared() {
  local rel="$1"
  [[ "$OBLIGATION_MODE" == "STRICT" ]] && return 0
  _in_newline_list "$rel" "$DECLARED_FILES" && return 0
  _in_newline_list "$rel" "$SKIPPED_FILES" && return 0
  return 1
}

# _run_if_declared <base> <ext> <runner> <kind> <kind-genitive> <func-name> — общая функция
# для гейтов (.py, uv run) и сьютов (.sh, bash); §3 ADR-037-spec: "два безусловных вызова
# идут через ту же функцию, исключений в правиле нет" — распространено на ВСЕ вызовы ниже,
# не только validate-content.py/validate-profile.py. Пять исходов (§3 псевдокод):
#   present            → исполняет (присутствие исполняет, не запись)
#   declared && origin → ERROR-MISSING-AT-ORIGIN
#   declared && STRICT → ERROR-MISSING-NO-BASIS
#   rel in skip:       → ERROR-MISSING-SKIPPED
#   declared (прочее)  → ERROR-MISSING-DELIVERED
#   иначе              → INFO-NOT-DELIVERED, exit-код не меняется
_run_if_declared() {
  local base="$1" ext="$2" runner="$3" kind="$4" kind_gen="$5" func_name="$6"
  local rel="scripts/${base}.${ext}"
  local name="${base}.${ext}"

  if [[ -f "$rel" ]]; then
    run_check "$name" "$runner $rel"
    return
  fi

  if _declared "$rel"; then
    if [[ "$ORIGIN" -eq 1 ]]; then
      echo "▶ $name"
      echo "  ✗ $name FAILED" >&2
      echo "  ERROR: ${kind} \"$name\" объявлен в check.sh (${func_name} \"$base\"), но файла" >&2
      echo "  $rel в этом дереве нет. Дерево опознано как источник payload'а (bin/deliver.sh" >&2
      echo "  на месте и несёт подпись установщика) — здесь обязателен весь перечень (ADR-037 Д3), сужать" >&2
      echo "  его нечем. ADR-007 Д1: гейт возвращает 0 только если выполнил проверку и она прошла. Почини:" >&2
      echo "  верни файл на место либо убери \"$base\" из вызовов в check.sh, если этого предмета здесь" >&2
      echo "  больше не должно быть." >&2
      failed=1
      return
    fi
    if [[ "$OBLIGATION_MODE" == "STRICT" ]]; then
      echo "▶ $name"
      echo "  ✗ $name FAILED" >&2
      echo "  ERROR: ${kind} \"$name\" объявлен в check.sh, файла $rel нет, и сузить обязательства" >&2
      echo "  нечем: .nauta-scripts-basis.yaml в корне дерева отсутствует. Отсутствие базиса не значит" >&2
      echo "  \"ничего не доставлено\" (ADR-037 Д4). Две гипотезы, механизм их не различает: (1) это дерево" >&2
      echo "  получило scripts/ через /nauta:sync-scripts, а базис потерян — повтори команду, она перепишет" >&2
      echo "  базис; (2) это дерево-источник с повреждённым bin/ — верни bin/deliver.sh и файл ${kind_gen}." >&2
      failed=1
      return
    fi
    if _in_newline_list "$rel" "$SKIPPED_FILES"; then
      echo "▶ $name"
      echo "  ✗ $name FAILED" >&2
      echo "  ERROR: ${kind} \"$name\" стоит в секции skip: базиса .nauta-scripts-basis.yaml, но файла" >&2
      echo "  $rel в дереве нет. skip: означает \"не перезаписывай мою копию\", а не \"у меня" >&2
      echo "  этого нет\" (ADR-030-spec §5) — заявка есть, предмета нет, и это противоречие, а не отказ." >&2
      echo "  Почини: либо верни файл (повтори /nauta:sync-scripts, предварительно убрав путь из skip:)," >&2
      echo "  либо убери путь из skip:, если этот ${kind} вам не нужен, — тогда базис перестанет его заявлять." >&2
      failed=1
      return
    fi
    echo "▶ $name"
    echo "  ✗ $name FAILED" >&2
    echo "  ERROR: ${kind} \"$name\" заявлен доставленным (.nauta-scripts-basis.yaml, files: →" >&2
    echo "  $rel, nauta ${BASIS_NAUTA_VERSION}, синк ${BASIS_SYNCED_AT}), но файла в дереве нет — доставка" >&2
    echo "  повреждена. ADR-007 Д1: \"не смог проверить\" ≠ \"нечего проверять\". Почини: повтори" >&2
    echo "  /nauta:sync-scripts — отсутствующий файл создаётся заново и конфликтом не считается" >&2
    echo "  (ADR-030 Д4)." >&2
    failed=1
    return
  fi

  # Не заявлен и отсутствует — объявленное молчание (Д2/Д6): называет источник своего права,
  # не тихий [INFO] skip (Д7 — этот токен здесь не используется вовсе).
  echo "[INFO] $name не доставлен в это дерево: базис (nauta ${BASIS_NAUTA_VERSION}, синк ${BASIS_SYNCED_AT}) его не"
  echo "       заявляет — проверка не выполняется, exit-код не меняется. Чтобы ${kind} появился: обнови"
  echo "       плагин и повтори /nauta:sync-scripts; как только ${kind} войдёт в payload, базис его заявит,"
  echo "       и с этого момента его отсутствие станет ошибкой."
}

# run_gate_if_declared <gate-basename> — прогнать `uv run scripts/<basename>.py`. Имя
# заменяет исторический остаток `run_gate_if_present`/`run_suite_if_present` («_if_present»,
# докстрока-предшественник отмечала это как остаток эпохи двух курируемых снапшотов, ADR-006
# §Q1) — неверно называл предикат: обязательность решает ЗАЯВКА базиса, не голое присутствие
# файла (ADR-037-spec §3). Имена функций не проверяются ассертами нигде (ADR-037-spec §3);
# упоминания старых имён в прозе уже закрытых артефактов (CHANGELOG.md,
# content/lessons-learned.md, content/30-requirements/**) не правятся — состояние на момент
# написания.
run_gate_if_declared() {
  _run_if_declared "$1" "py" "uv run" "гейт" "гейта" "run_gate_if_declared"
}

# run_suite_if_declared <suite-basename> — прогнать scripts/<basename>.sh. Симметрична
# run_gate_if_declared (см. её докстроку).
run_suite_if_declared() {
  _run_if_declared "$1" "sh" "bash" "сьют" "сьюта" "run_suite_if_declared"
}

# run_gate_sh_if_declared <gate-basename> — прогнать `bash scripts/<basename>.sh` КАК ГЕЙТ
# (Д7 ADR-040): третья обёртка _run_if_declared — runner bash (как у сьюта), но род сообщения
# "гейт" (как у .py-гейтов) — `check-hooks-path.sh` и `id-check.sh` не .sh-регрессия
# self-test harness, а содержательная проверка дерева. Протокол обязательности (пять исходов
# ADR-037) не меняется — меняется только текст рода.
run_gate_sh_if_declared() {
  _run_if_declared "$1" "sh" "bash" "гейт" "гейта" "run_gate_sh_if_declared"
}

# check-hooks-path (ADR-040 Д2/Д7, ADR-040-spec §4) — маршрут хуков сверяется В --fast, ДО
# гейтов содержимого: расхождение маршрута отключает .githooks/pre-commit целиком (замер §1.2
# ADR-040-spec) — сообщить об этом раньше остального дерева, а не после.
run_gate_sh_if_declared "check-hooks-path"

# secret-scan-tree (ADR-040 Д1, secret-hygiene-gate) — обход РАБОЧЕГО дерева gitleaks'ом в
# --fast (симметрично --staged в .githooks/pre-commit, замер §1.4: 0.33с при 2.13с текущего
# --fast). Конфигурация: secretScan.enabled/secretScan.binary из .nauta-gates.yaml (§6),
# умолчание — включено, бинарь gitleaks. Отсутствие бинаря — громкая ошибка (uv-guard
# check.sh:23 прецедент), не тихий skip (secret-hygiene-gate: "unavailable scanner is a loud
# failure").
_gates_secret_scan_enabled() {
  local gates="$REPO_ROOT/.nauta-gates.yaml" v
  [[ -f "$gates" ]] || { echo true; return 0; }
  v="$(awk '
    /^secretScan:[ \t]*(#.*)?$/ { inblk=1; next }
    inblk && $0 ~ /^[^ \t]/ { inblk=0 }
    inblk && $0 ~ /^[ \t]*enabled:/ {
      line=$0
      sub(/^[ \t]*enabled:[ \t]*/, "", line)
      gsub(/[ \t]+$/, "", line); gsub(/^"/, "", line); gsub(/"$/, "", line)
      print line
      exit
    }
  ' "$gates")"
  [[ -z "$v" ]] && v=true
  echo "$v"
}
_gates_secret_scan_binary() {
  local gates="$REPO_ROOT/.nauta-gates.yaml" v
  [[ -f "$gates" ]] || { echo gitleaks; return 0; }
  v="$(awk '
    /^secretScan:[ \t]*(#.*)?$/ { inblk=1; next }
    inblk && $0 ~ /^[^ \t]/ { inblk=0 }
    inblk && $0 ~ /^[ \t]*binary:/ {
      line=$0
      sub(/^[ \t]*binary:[ \t]*/, "", line)
      gsub(/[ \t]+$/, "", line); gsub(/^"/, "", line); gsub(/"$/, "", line)
      print line
      exit
    }
  ' "$gates")"
  [[ -z "$v" ]] && v=gitleaks
  echo "$v"
}
SECRET_SCAN_ENABLED="$(_gates_secret_scan_enabled)"
if [[ "$SECRET_SCAN_ENABLED" == "true" ]]; then
  SECRET_SCAN_BINARY="$(_gates_secret_scan_binary)"
  echo "▶ secret-scan-tree"
  if ! command -v "$SECRET_SCAN_BINARY" >/dev/null 2>&1; then
    echo "  ✗ secret-scan-tree FAILED" >&2
    echo "  ERROR: '$SECRET_SCAN_BINARY' не найден в PATH — сканирование секретов рабочего" >&2
    echo "  дерева не выполнено (secretScan.enabled=true, .nauta-gates.yaml). Это НЕ \"0" >&2
    echo "  находок\" (ADR-007 Д1). Установи: brew install gitleaks (замер §1.1 ADR-040-spec)." >&2
    failed=1
  elif "$SECRET_SCAN_BINARY" dir --no-banner --redact -v "$REPO_ROOT" >/tmp/nauta-secret-scan-tree.$$ 2>&1; then
    echo "  ✓ secret-scan-tree"
    rm -f /tmp/nauta-secret-scan-tree.$$
  else
    cat /tmp/nauta-secret-scan-tree.$$ >&2
    rm -f /tmp/nauta-secret-scan-tree.$$
    echo "  ✗ secret-scan-tree FAILED" >&2
    failed=1
  fi
else
  echo "[INFO] secret-scan-tree выключен (.nauta-gates.yaml secretScan.enabled: false) — проверка не"
  echo "       выполняется, exit-код не меняется."
fi

# Два безусловных вызова (§3 ADR-037-spec: "исключений в правиле нет") — идут через ТУ ЖЕ
# функцию, что и остальной перечень: в реальном payload'е они всегда заявлены и присутствуют,
# наблюдаемое поведение не меняется; расходится только текст, если они когда-нибудь пропадут.
run_gate_if_declared "validate-content"
run_gate_if_declared "validate-profile"
run_gate_if_declared "check-adr-line-limit"

if [[ "$MODE" == "--full" ]]; then
  # check-backlog-closure (ADR-012 Д4, Ruling D задачи 8/S7-DEV-003): гейт живёт в --full,
  # не --fast — Д4 буквально: между тем, как тест Dev'а позеленел, и тем, как PM перенёс
  # пункт в «Won't», проходят коммиты; в --fast гейт бил бы по каждому из них, то есть по
  # нормальному ходу TDD внутри эпика, а не по расхождению между эпиками. Заработал только
  # после починки разбора заголовков бэклога (### и ####, scripts/check-backlog-closure.py,
  # эта же задача) — на реальном дереве даёт `OK: 0 нарушений`, не молчал раньше по причине
  # отсутствия вызова, а падал бы `ERROR: не найдены секции` до фикса.
  run_gate_if_declared "check-backlog-closure"

  # id-check (ADR-038 Д3/Д8, ADR-038-spec §4.3/§5; решение владельца Р22, roadmap 2026-08-18)
  # — коллизии, невозврат отменённого номера, расхождение реестра .nauta-ids.yaml с корпусом.
  # Живёт в --full, не в --fast, по тексту Р22 дословно: профиль назван решением. Обоснование
  # то же, что у check-backlog-closure выше, — гейт судит СОСТОЯНИЕ КОРПУСА целиком (полный
  # обход дерева), а не отдельный коммит; в --fast (вход .githooks/pre-commit) он бил бы по
  # каждому шагу TDD внутри эпика.
  #
  # ЦЕНА ПОДКЛЮЧЕНИЯ, записанная здесь, а не только в roadmap, — чтобы следующий читатель не
  # принял её за недосмотр и не «починил»: область поиска ступени 3 («определение вне всех
  # объявленных home», scripts/id-check.sh) сознательно СУЖЕНА до формы `filename-prefix` и
  # дополнительно исключает companion-файлы `-spec.md` (санкционированный прецедент ADR-013
  # Д2 — companion законно несёт номер решения). То есть гейт видит меньше, чем мог бы. Без
  # сужения однобуквенный префикс `Д` пространства decision-clause матчит обычную русскую
  # прозу («Дата», «Две», «Держать») — замер на живом дереве DEV-010: ~90 ложных ERROR, из них
  # ~29 на companion-файлах content/40-architecture/. Расширение области до честного маркера
  # определения — ОТДЕЛЬНАЯ задача (требует более строгого матчера и покрывающего теста), а не
  # условие включения этого вызова.
  #
  # `next-id.sh` в этом перечне не появляется НИКОГДА (Д5 ADR-040, подтверждено Р22):
  # аллокатор мутирует реестр, раннер обязан оставаться читателем.
  run_gate_sh_if_declared "id-check"

  # check-content-classification (Ruling C задачи 8/S7-DEV-003, ADR-033 Д2) — вызов НЕ
  # восстанавливается, это не забытый файл. Гейт требует `.publishignore`; модель «рабочая
  # ветка + производная публикуемая», для которой он писался, в nauta не существует (ADR-033
  # Д2) — семантика гейта у потомка инвертирована: он красил бы КАЖДЫЙ файл content/ как
  # неклассифицированный (живой прогон архивной копии — отчёт задачи 7). Предмета здесь нет
  # по принятому решению — громким этот вызов не делается, он просто отсутствует.

  # check-breaking-change-section (Ruling E задачи 8/S7-DEV-003, ADR-021 Д2/Д4) — гейт-
  # СКРИПТ из check.sh не вызывается: требует обязательный позиционный `<range>`,
  # несовместимый с run_gate_if_declared (зовёт без аргументов), и `.publishignore`, которого
  # тоже нет (тот же факт, что у check-content-classification выше). Неприменимость
  # документируется здесь, а не молчит — сам гейт остаётся advisory-инструментом для
  # `ba-agent.md --mode=acceptance` (диапазон эпика передаётся вручную). Его bash-СЬЮТ
  # (регрессия на синтетике, не живой прогон на `.publishignore`) при этом зарегистрирован
  # ниже — ADR-017 требует регистрацию раннера отдельно от применимости самого гейта.

  # Ruling F (задача 8/S7-DEV-003): список сьютов приведён к тому, что реально есть в
  # дереве («объявлено — значит обязано существовать», ADR-007 Д1 распространяется и на
  # self-test harness). Из 18 архивных имён остаются три — N1 (задача 7) перенёс их py/sh-
  # предметы в scripts/, задача 8 регистрирует третье (test-check-breaking-change-section
  # ранее нигде не упоминался, ADR-017). Остальные 15 удалены по ДВУМ разным причинам —
  # полная разбивка построчно в task-8-report.md, здесь — категории:
  #   (a) предмета здесь нет по принятому решению, не «не успели перенести»: test-publish-
  #       public, test-examples-sync, test-repo-zone-map (публикация/витрина examples/,
  #       ADR-033 Д2 убрал модель «рабочая ветка + производная публикуемая»); test-template
  #       (смоук rename/idempotency локальной directory-копии шаблона — ADR-009-plugin-
  #       centralization-migration-spec.md Д7 п.3: «становится бессмысленным... удалять, не
  #       переписывать», как только источник стал удалённой git-ссылкой); test-check-
  #       content-classification (Ruling C выше); test-central-plugin-checkout (ADR-009-spec
  #       п.5 — «новая тестовая поверхность БЕЗ АНАЛОГА», проверяет consumer-сторону
  #       установки nauta как ЧУЖОГО плагина; внутри самого nauta второй стороны, которую
  #       можно поставить потребителем, нет).
  #   (b) предмет здесь есть (код существует в scripts/ или agents/), но сам файл сьюта не
  #       перенесён — отложенная задача N3 роадмапа (owner-решение Р10), не код: test-
  #       validate-content, test-validate-profile, test-resolve-agents, test-check-status-
  #       drift, test-apply-overlay (предметы — validate-content.py, validate-profile.py,
  #       _resolve_agents.py, check-status-drift.py, apply-overlay.sh, все в scripts/);
  #       test-loud-gates (_validate_common.py/_drift_check.py); test-gate-debt (debt-батч
  #       PT-EPIC-13, большей частью тот же _drift_check.py/apply-overlay.sh); test-spdd-
  #       integration (two-way sync CLAUDE.md, PM-review drift-check, manifest drift_pairs —
  #       все три живут в этом дереве); test-backlog-cleanup (ownership-бухгалтерия PT-EPIC-16
  #       поверх check-backlog-closure.py/check-adr-line-limit.py); test-prompt-layer
  #       (ADR-016 промт-слой 11 ролей — agents/*.md, собственный домен nauta; 5 из 8
  #       исходных предметов уже переехали сюда напрямую вне этой задачи).
  #
  # test-check-id (DEV-022, NA-EPIC-11) — регистрируется тем же механизмом, что три соседа
  # выше, и это ЧЕТВЁРТОЕ имя перечня, а не исключение. Основание — то же правило ADR-017,
  # уже записанное абзацем выше про test-check-breaking-change-section: регистрация раннера
  # решается отдельно от применимости самого гейта. Разница с соседями по перечню одна и
  # ничего в протоколе не меняет: `scripts/test-check-id.sh` входит в PAYLOAD_FILES
  # (bin/deliver.sh) — то есть доставляется каждому потребителю, — тогда как три соседних
  # сьюты живут только здесь. Именно поэтому её отсутствие в перечне было вакуумом, а не
  # безобидным упущением: 19 мутационных проверок M1–M9 ехали в каждое дерево и не бежали ни
  # в одном профиле (находка DEV-019, «Осознанные границы» его отчёта).
  #
  # Обязательность НЕ ужесточается регистрацией: run_suite_if_declared соблюдает те же пять
  # исходов ADR-037, что и остальной перечень. У потребителя, синкнувшегося payload'ом БЕЗ
  # этой позиции, базис её не заявляет — он получит объявленное молчание (INFO-NOT-DELIVERED)
  # и exit 0, а не ложный красный. Красным она станет ровно тогда, когда базис её заявит.
  for suite in test-check-adr-line-limit test-check-backlog-closure \
               test-check-breaking-change-section test-check-id; do
    run_suite_if_declared "$suite"
  done
fi

if [[ "$failed" -ne 0 ]]; then
  echo "" >&2
  echo "✗ check.sh $MODE — FAILED" >&2
  exit 1
fi

echo ""
echo "✓ check.sh $MODE — passed"
