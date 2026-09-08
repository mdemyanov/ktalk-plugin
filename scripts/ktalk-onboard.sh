#!/usr/bin/env bash
# Онбординг плагина ktalk: обнаружение пакета, санкция, установка.
# Контракт — ADR-014-onboarding-spec.md в репозитории пакета (исторически
# ktalk-mcp, с ADR-024 — ktalk-cli; идентичность самого пакета читается из
# compat.json, не зашита литералом — см. pin_name()/pin_version() ниже).
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPAT_FILE="$PLUGIN_ROOT/compat.json"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ktalk"
SANCTION_FILE="$CONFIG_DIR/onboarding.toml"
# Команда ремонта (install/update) не может быть top-level константой: она
# встраивает пин, и пин не известен раньше, чем прочитан compat.json —
# см. remedy_cmd_text/remedy_cmd_array ниже, вызываемые после pin_version()
# (ADR-022 companion, «Точка правки: порядок инициализации»).

# Конечный список идентичностей пакета, известных за время перехода
# ktalk-mcp → ktalk-cli (ADR-024 Д1/Д5) — используется ТОЛЬКО для распознавания
# фактически установленного пакета (installed_identity() ниже), не для пина:
# пин всегда приходит из compat.json (pin_name()), никогда не хардкодится.
KNOWN_PACKAGE_NAMES=(ktalk-mcp ktalk-cli)

E_OK=0; E_MISSING_CLI=10; E_OUTDATED=11; E_MISSING_UV=12; E_WRONG_PACKAGE=13
# E_RETIRED_MODE=14 — код 14 (ADR-029 Д1/Д2, BA-001 content/30-requirements/2026-09-08-
# retired-mode-detection.md, «Почему код возврата 14»): пакет полностью готов (версия
# совпадает с пином), но в окружении процесса обнаружена переменная отставного режима
# авторизации — предупреждение, не ошибка готовности пакета, поэтому отдельный код рядом с
# 10-13, не переиспользует ни один из них.
E_RETIRED_MODE=14
E_INTERNAL=20
E_NO_SANCTION=30; E_INSTALL_FAILED=31; E_NO_UPDATE_SANCTION=32; E_NO_TTY=33
E_SLOT_COLLISION=34

JSON=0

pin_field() { # pin_field <ключ> — сырое значение строкового ключа верхнего уровня compat.json
  grep -Eo "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$COMPAT_FILE" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/'
}

pin_name() { # pin_name → печатает пинуемое ИМЯ пакета из compat.json либо отказывает
  # ADR-024 Д1: идентичность пакета — пара package_name/package_version, оба
  # поля обязательны ОДНОВРЕМЕННО (companion, «Синтаксис пина») — отсутствие
  # ЛЮБОГО из двух (включая старые ключи ktalk_mcp_version/..._min_version,
  # оставшиеся до этого перехода) есть «пина нет», не молчаливый дефолт.
  local n v
  n="$(pin_field package_name)"; v="$(pin_field package_version)"
  [ -n "$n" ] && [ -n "$v" ] || return 1
  printf '%s\n' "$n"
}

pin_version() { # pin_version → печатает пинуемую ВЕРСИЮ из compat.json либо отказывает
  # Точный semver, не диапазон (ADR-022 Д3) — то же правило, распространённое
  # на пару полей (ADR-024 Д1) вместо одного ключа с именем пакета внутри.
  local n v
  n="$(pin_field package_name)"; v="$(pin_field package_version)"
  [ -n "$n" ] && [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

remedy_cmd_text() { # remedy_cmd_text <версия-пина> → текст команды ремонта с явным именем и пином
  # Одна и та же команда для install и update (ADR-022 Д2): под точным пином
  # санкции разводят install/update по смыслу действия (создание состояния vs
  # мутация чужого), не по тексту команды — оба случая переустанавливают ровно
  # версию пина, не "upgrade" на новейшую. Имя пакета — ПАРАМЕТР, читаемый из
  # compat.json через pin_name(), не текстовый литерал (ADR-024, «Точка
  # правки: литералы "ktalk-mcp" внутри функций» — тот же класс дефекта, что
  # уже ударил версию в 0.8.0).
  printf 'uv tool install %s==%s' "$(pin_name)" "$1"
}

remedy_cmd_array() { # remedy_cmd_array <версия-пина> → заполняет глобальный REMEDY_CMD
  REMEDY_CMD=(uv tool install "$(pin_name)==$1")
}

II_NAME=''; II_VERSION=''; II_REGISTERED_BOTH=0

installed_identity() { # installed_identity → заполняет II_NAME/II_VERSION/II_REGISTERED_BOTH; 0 при успехе
  # Расширение прежней installed_version(): разбирает ОБА токена вывода
  # `ktalk --version` — "<имя-дистрибутива> <версия>" (кросс-репо контракт,
  # ADR-024 companion «Точка правки: формат --version») — вместо того чтобы
  # (как раньше) вырезать из вывода только цифры и отбрасывать имя. Регэксп
  # версии захватывает пре-релизный/билд-суффикс целиком, не только числовое
  # ядро X.Y.Z — иначе rc-сборка теряет свой суффикс ДО того, как version_eq()
  # успеет его увидеть, и молча признаётся равной пину (находка code review
  # DEV-002 round 2, тест 42).
  #
  # Резервный путь (ktalk отсутствует/не поддерживает --version, но uv есть)
  # перебирает КОНЕЧНЫЙ список известных идентичностей, не один литерал: если
  # видны ОБЕ известные строки одновременно — это диагностический признак
  # registered_both (коллизия уже случилась ранее, вероятно, вручным --force),
  # не отдельный статус отказа сам по себе (ADR-024 companion, Data flow п.2).
  II_NAME=''; II_VERSION=''; II_REGISTERED_BOTH=0
  local out name ver
  if out="$(ktalk --version 2>/dev/null)"; then
    name="$(printf '%s' "$out" | awk '{print $1}')"
    ver="$(printf '%s' "$out" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.+-]*' | head -1)"
    local known
    for known in "${KNOWN_PACKAGE_NAMES[@]}"; do
      if [ "$name" = "$known" ] && [ -n "$ver" ]; then
        II_NAME="$name"; II_VERSION="$ver"; return 0
      fi
    done
  fi
  if command -v uv >/dev/null 2>&1; then
    local list known hits=() hit
    list="$(uv tool list 2>/dev/null)"
    for known in "${KNOWN_PACKAGE_NAMES[@]}"; do
      if printf '%s\n' "$list" | grep -Eq "^${known}[[:space:]]"; then
        hits+=("$known")
      fi
    done
    if [ "${#hits[@]}" -gt 1 ]; then
      II_REGISTERED_BOTH=1
      return 1
    fi
    if [ "${#hits[@]}" -eq 1 ]; then
      hit="${hits[0]}"
      ver="$(printf '%s\n' "$list" | grep -E "^${hit}[[:space:]]" | head -1 \
            | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.+-]*' | head -1)"
      if [ -n "$ver" ]; then II_NAME="$hit"; II_VERSION="$ver"; return 0; fi
    fi
  fi
  return 1
}

identity_eq() { # identity_eq <установленное-имя> <имя-пина> — точное совпадение имени дистрибутива
  [ "$1" = "$2" ]
}

version_eq() { # version_eq A B → 0, если версии равны с учётом пина (ADR-022 Д3)
  # Решение по границе, намеренно оставленной companion-статьёй Dev'у
  # (0.10.0+local против пина 0.10.0): билд-метаданные (+xyz) ИГНОРИРУЮТСЯ при
  # сравнении — это дословно правило самого semver (spec §10: "Build metadata
  # SHOULD be ignored when determining version precedence"), и мы его
  # наследуем, а не изобретаем своё. Пре-релизные идентификаторы (-rc1 и т.п.),
  # наоборот, СОХРАНЯЮТСЯ и делают версию неравной пину: пин называет ровно
  # опубликованный релиз (ADR-022 Д3 — "точный пин", не диапазон), а не любую
  # сборку с тем же числовым ядром. Если бы пре-релиз тоже отбрасывался, ремонт
  # молча признавал бы "0.10.0-rc1" совместимой с пином "0.10.0" — версией,
  # которая ещё не является тем самым опубликованным релизом, что подрывает
  # именно ту гарантию, ради которой пин введён (BA-001 → ADR-022 Д3).
  local a_core="${1%%[-+]*}" b_core="${2%%[-+]*}"
  local a_pre='' b_pre=''
  # Билд-метаданные ОБЯЗАНЫ быть отрезаны (%%+*) ДО поиска дефиса
  # пре-релиза — находка code review DEV-002 round 2 (тест 43): дефис ищется
  # по всей сырой строке, а он может лежать ВНУТРИ билд-метаданных
  # ("0.10.0+build-1" — дефис в "build-1", это часть билд-меты, не
  # пре-релиз). Semver §10 требует игнорировать билд-метаданные целиком,
  # независимо от её собственного содержимого.
  local a_before_build="${1%%+*}" b_before_build="${2%%+*}"
  case "$a_before_build" in *-*) a_pre="${a_before_build#*-}" ;; esac
  case "$b_before_build" in *-*) b_pre="${b_before_build#*-}" ;; esac
  local a b x y i
  IFS=. read -r -a a <<< "$a_core"
  IFS=. read -r -a b <<< "$b_core"
  for i in 0 1 2; do
    x="${a[i]:-0}"; y="${b[i]:-0}"
    x="${x//[!0-9]/}"; y="${y//[!0-9]/}"
    x="${x:-0}"; y="${y:-0}"
    [ "$((10#$x))" -eq "$((10#$y))" ] || return 1
  done
  [ "$a_pre" = "$b_pre" ]
}

json_escape() { # json_escape <строка> — экранирует \, ", CR, LF, TAB для JSON-строки
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

report() { # report <status> <installed_pkg> <installed_ver> <pin_pkg> <pin_ver> <message> [cmd_text] [extra_json]
  # JSON-ключи "installed_version"/"min_version" остаются сознательно
  # (companion-статья, «Синтаксис пина»): то же минимально-рискованное
  # решение, каким там оставлен статус "outdated" для обеих сторон
  # расхождения — не переименовывать поле, которое уже читает test-onboard.sh
  # и любой внешний потребитель. "installed_package"/"pinned_package" —
  # НОВЫЕ поля, добавленные аддитивно (ADR-024 companion, «Consequences»).
  # [extra_json] — необязательный, уже сформированный JSON-фрагмент вида
  # ',"registered_both":true' — вставляется как есть (тот же приём, что
  # install_report уже применяет к first_attempt_output).
  local status="$1" ipkg="$2" iver="$3" ppkg="$4" pver="$5" msg="$6" \
        cmd_text="${7:-}" extra="${8:-}"
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"%s","installed_version":"%s","min_version":"%s","installed_package":"%s","pinned_package":"%s","install_command":"%s"%s,"message":"%s"}\n' \
      "$(json_escape "$status")" "$(json_escape "$iver")" "$(json_escape "$pver")" \
      "$(json_escape "$ipkg")" "$(json_escape "$ppkg")" "$(json_escape "$cmd_text")" \
      "$extra" "$(json_escape "$msg")"
  else
    printf '%s\n' "$msg"
  fi
}

# retired_mode_set — 0, если переменная отставного режима авторизации задана (непусто) в
# ОКРУЖЕНИИ ЭТОГО ПРОЦЕССА (BA-001 content/30-requirements/2026-09-08-retired-mode-detection.md,
# «Почему обнаружение — только переменная процесса»; ADR-029 Д1). Не читает ~/.zshenv, любой
# другой файл автозапуска оболочки и файл .env рабочего каталога — единственный источник
# истины здесь сама переменная, той же формой `[ -n ... ]`, что называет требование.
#
# Форма ниже — дефис без двоеточия перед закрывающей скобкой подстановки, НЕ двоеточие-дефис:
# обе формы одинаково безопасны под `set -u` для неустановленной переменной (default
# применяется, когда переменная не установлена — под `-n` дальше пустая/непустая строка не
# отличаются между формами для этого предиката), но форма с двоеточием сразу после имени
# переменной матчит паттерн "секрет со значением" `check-plugin-composition.sh` (символ `[:=]`
# этого паттерна), а форма без двоеточия — нет: следующий за именем переменной символ не `:`/`=`,
# гейт молчит.
retired_mode_set() {
  [ -n "${KTALK_PERSONAL_API_KEY-}" ]
}

# retired_extra_json <0|1> → JSON-фрагмент нового аддитивного поля report() (кандидат 2, BA-001)
# — печатается на КАЖДОМ исходе cmd_check (Requirement «check detects the retired mode…»,
# Scenario «The fact is named on every outcome, the value never is»), не только на исходе,
# который сам код 14 выделяет отдельно. Имя поля намеренно содержит "retired" (контракт стаба,
# at-design.md «Контракт имени JSON-поля не зафиксирован SA»).
retired_extra_json() {
  if [ "$1" -eq 1 ]; then printf ',"retired_mode_detected":true'; else printf ',"retired_mode_detected":false'; fi
}

# retired_mode_message <pin_n> <version> <remedy_text> → текст находки кода 14 (BA-001,
# Requirement «The reported message names the affected operations and the actual remedy»).
# Называет ровно пять операций спеки (RES-001 §2), команду `unset KTALK_PERSONAL_API_KEY` и
# оговорку о её непостоянстве — не называет ни один конкретный файл автозапуска оболочки и не
# предлагает его править (ADR-029 Д1/Д2, Scenario «The plugin does not name a specific file or
# edit one»).
retired_mode_message() {
  local pin_n="$1" ver="$2"
  printf 'Обнаружена переменная отставного режима авторизации KTALK_PERSONAL_API_KEY в окружении процесса — пакет %s %s установлен и совпадает с пином, это предупреждение, не ошибка готовности пакета. Пять операций не имеют другого рабочего пути, кроме токена сессии, и под этой переменной откажут: get-room, list-calendar, create-meeting, cancel-meeting, search-contacts. Немедленное действие в этой оболочке: unset KTALK_PERSONAL_API_KEY — команда очищает только текущую оболочку и не переживёт новую оболочку или новый запуск; то же присваивание в файле автозапуска оболочки или в .env рабочего каталога, если оно есть, останется как было и продолжит действовать после. check не читает такие файлы, поэтому не знает и не называет, где именно такое присваивание могло бы быть, и не изменяет ни один такой файл — найти и снять его на постоянной основе, если оператор этого хочет, предстоит ему самому.' \
    "$pin_n" "$ver"
}

cmd_check() {
  local pin pin_n remedy_text retired=0 retired_json
  if retired_mode_set; then retired=1; fi
  retired_json="$(retired_extra_json "$retired")"
  if ! pin="$(pin_version)"; then
    report error "" "" "" "" "Не прочитан compat.json плагина — переустановите плагин." "" "$retired_json"
    return "$E_INTERNAL"
  fi
  pin_n="$(pin_name)"
  remedy_text="$(remedy_cmd_text "$pin")"
  if ! command -v ktalk >/dev/null 2>&1; then
    if ! command -v uv >/dev/null 2>&1; then
      report missing_uv "" "" "$pin_n" "$pin" "Не найден uv. Установите uv, затем: $remedy_text" "$remedy_text" "$retired_json"
      return "$E_MISSING_UV"
    fi
    report missing_cli "" "" "$pin_n" "$pin" "Пакет $pin_n не установлен. Команда установки: $remedy_text" "$remedy_text" "$retired_json"
    return "$E_MISSING_CLI"
  fi
  if ! installed_identity; then
    local extra="$retired_json"
    if [ "$II_REGISTERED_BOTH" -eq 1 ]; then extra=',"registered_both":true'"$extra"; fi
    report identity_unknown "" "" "$pin_n" "$pin" \
      "Идентичность установленного пакета не распознана штатным способом (ktalk --version и uv tool list). Ремонт: $remedy_text" \
      "$remedy_text" "$extra"
    return "$E_OUTDATED"
  fi
  if ! identity_eq "$II_NAME" "$pin_n"; then
    report wrong_package "$II_NAME" "$II_VERSION" "$pin_n" "$pin" \
      "Установлен пакет $II_NAME ($II_VERSION), а согласно compat.json требуется $pin_n $pin. Ремонт: $remedy_text" \
      "$remedy_text" "$retired_json"
    return "$E_WRONG_PACKAGE"
  fi
  if ! version_eq "$II_VERSION" "$pin"; then
    report outdated "$II_NAME" "$II_VERSION" "$pin_n" "$pin" \
      "Версия пакета (${II_VERSION}) не совпадает с требуемой версией $pin. Ремонт: $remedy_text" \
      "$remedy_text" "$retired_json"
    return "$E_OUTDATED"
  fi
  # Готовность пакета приоритетнее находки (BA-001, «Наличие находки не мешает check вернуть
  # коды 10-13/20/30-34») — этот блок стоит ПОСЛЕ version_eq и ДО report ok (Brief for SA).
  if [ "$retired" -eq 1 ]; then
    report retired_mode "$II_NAME" "$II_VERSION" "$pin_n" "$pin" \
      "$(retired_mode_message "$pin_n" "$II_VERSION")" "$remedy_text" "$retired_json"
    return "$E_RETIRED_MODE"
  fi
  report ok "$II_NAME" "$II_VERSION" "$pin_n" "$pin" "Пакет $pin_n $II_VERSION установлен, версия совместима." "$remedy_text" "$retired_json"
  return "$E_OK"
}

sanction_granted() { # sanction_granted install|update
  [ -f "$SANCTION_FILE" ] || return 1
  grep -Eq "^allow_$1[[:space:]]*=[[:space:]]*true[[:space:]]*\$" "$SANCTION_FILE"
}

sanction_json() {
  local i u
  sanction_granted install && i=true || i=false
  sanction_granted update && u=true || u=false
  printf '{"install":%s,"update":%s}' "$i" "$u"
}

cmd_status() {
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"ok","sanction":%s,"sanction_file":"%s"}\n' "$(sanction_json)" "$SANCTION_FILE"
  else
    local i u
    sanction_granted install && i="есть" || i="нет"
    sanction_granted update && u="есть" || u="нет"
    printf 'Санкция на установку: %s\nСанкция на обновление: %s\nФайл: %s\n' "$i" "$u" "$SANCTION_FILE"
  fi
  return "$E_OK"
}

set_key() { # set_key <install|update> <true|false>
  local tmp
  mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR" || return "$E_INTERNAL"
  tmp="$(mktemp "$CONFIG_DIR/.onboarding.XXXXXX")" || return "$E_INTERNAL"
  {
    grep -Ev "^allow_$1[[:space:]]*=" "$SANCTION_FILE" 2>/dev/null
    printf 'allow_%s = %s\n' "$1" "$2"
  } > "$tmp"
  chmod 600 "$tmp" && mv "$tmp" "$SANCTION_FILE" || return "$E_INTERNAL"
  return "$E_OK"
}

cmd_grant() {
  case "${1:-}" in
    install|update) ;;
    *) printf 'Укажите, что разрешаете: grant install | grant update\n' >&2; return "$E_INTERNAL" ;;
  esac
  if [ ! -t 0 ]; then
    printf 'Санкция выдаётся только в терминале. Запустите вручную:\n  bash %s grant %s\n' \
      "${BASH_SOURCE[0]}" "$1" >&2
    return "$E_NO_TTY"
  fi
  set_key "$1" true || return "$E_INTERNAL"
  printf 'Санкция "%s" выдана. Файл: %s\nОтзыв: bash %s revoke %s\n' \
    "$1" "$SANCTION_FILE" "${BASH_SOURCE[0]}" "$1"
  return "$E_OK"
}

cmd_revoke() {
  case "${1:-}" in
    install|update) ;;
    *) printf 'Укажите, что отзываете: revoke install | revoke update\n' >&2; return "$E_INTERNAL" ;;
  esac
  [ -f "$SANCTION_FILE" ] || return "$E_OK"
  set_key "$1" false || return "$E_INTERNAL"
  printf 'Санкция "%s" отозвана.\n' "$1"
  return "$E_OK"
}

RETRY_DELAY="${KTALK_ONBOARD_RETRY_DELAY:-3}"
case "$RETRY_DELAY" in
  ''|*[!0-9.]*) RETRY_DELAY=3 ;;
esac

is_network_error() {
  printf '%s' "$1" | grep -Eqi \
    'failed to fetch|connection|timed out|timeout|temporary failure in name resolution|network|could not resolve'
}

run_clean() { # run_clean <команда...> — запуск без секретов KTalk в окружении (NFR-19)
  # Вывод менеджера пакетов ретранслируется в диалог агента целиком. Менеджеру
  # секреты KTalk не нужны, поэтому они снимаются с дочернего процесса: любой его
  # вывод перестаёт быть каналом для значения токена по построению, а не по
  # предположению о том, что uv не печатает окружение (SEC-004, MAJ-01).
  (
    unset KTALK_SESSION_TOKEN KTALK_PERSONAL_API_KEY KTALK_BASE_URL
    "$@"
  )
}

RI_RAN=0; RI_RETRIED=0; RI_RC=0; RI_OUT=''; RI_FIRST_OUT=''

run_install() { # run_install <текст команды для пользователя> <команда...>
  # Результат кладётся в RI_* — печать JSON остаётся за install_report, чтобы на
  # любом исходе (включая постусловие FR-31) в stdout был ровно один объект.
  local cmd_text="$1"; shift
  local out1 rc1 out2='' rc2=''
  RI_RAN=1; RI_RETRIED=0; RI_RC=0; RI_OUT=''; RI_FIRST_OUT=''

  out1="$(run_clean "$@" 2>&1)"; rc1=$?

  if [ "$rc1" -ne 0 ] && is_network_error "$out1"; then
    RI_RETRIED=1
    if [ "$JSON" -ne 1 ]; then
      printf 'Попытка 1:\n%s\n' "$out1"
      printf 'Сетевая ошибка, повтор через %s с.\n' "$RETRY_DELAY"
    fi
    sleep "$RETRY_DELAY"
    out2="$(run_clean "$@" 2>&1)"; rc2=$?
    if [ "$JSON" -ne 1 ]; then
      printf 'Попытка 2:\n%s\n' "$out2"
    fi
  fi

  if [ "$RI_RETRIED" -eq 1 ]; then
    RI_RC="$rc2"; RI_OUT="$out2"; RI_FIRST_OUT="$out1"
  else
    RI_RC="$rc1"; RI_OUT="$out1"; RI_FIRST_OUT=''
  fi

  if [ "$JSON" -ne 1 ]; then
    if [ "$RI_RETRIED" -ne 1 ]; then
      printf '%s\n' "$out1"
    fi
    printf 'Команда: %s\nКод возврата: %s\n' "$cmd_text" "$RI_RC"
  fi

  [ "$RI_RC" -eq 0 ] || return "$E_INSTALL_FAILED"
  return "$E_OK"
}

install_report() { # install_report <status> <installed_pkg> <installed_ver> <pin_pkg> <pin_ver> <message> <cmd_text>
  # Тот же набор полей, что у report(), плюс телеметрия запуска менеджера пакетов.
  # Поля attempts/return_code/uv_output печатаются на ЛЮБОМ исходе (DEV-007 дефект 2,
  # ADR-014-onboarding-spec §1) — включая ветки, где менеджер не запускался (нет
  # санкции, нет uv, нужна отдельная санкция на обновление, пакет уже свежий):
  # attempts=0, return_code=null, uv_output="" — честные значения «менеджер не
  # запускался», не пропуск полей. installed_package/pinned_package — те же
  # новые поля, что у report() (ADR-024, аддитивно).
  local status="$1" ipkg="$2" iver="$3" ppkg="$4" pver="$5" msg="$6" cmd_text="$7"
  if [ "$JSON" -eq 1 ]; then
    local attempts=0 rc_field=null tail=''
    if [ "$RI_RAN" -eq 1 ]; then
      attempts=1
      rc_field="$RI_RC"
      if [ "$RI_RETRIED" -eq 1 ]; then
        attempts=2
        tail="$(printf ',"first_attempt_output":"%s"' "$(json_escape "$RI_FIRST_OUT")")"
      fi
    fi
    printf '{"status":"%s","installed_version":"%s","min_version":"%s","installed_package":"%s","pinned_package":"%s","install_command":"%s","attempts":%s,"return_code":%s,"uv_output":"%s"%s,"message":"%s"}\n' \
      "$(json_escape "$status")" "$(json_escape "$iver")" "$(json_escape "$pver")" \
      "$(json_escape "$ipkg")" "$(json_escape "$ppkg")" "$(json_escape "$cmd_text")" \
      "$attempts" "$rc_field" "$(json_escape "$RI_OUT")" "$tail" "$(json_escape "$msg")"
  else
    printf '%s\n' "$msg"
  fi
}

is_slot_collision() { # is_slot_collision <код возврата uv> <захваченный вывод uv>
  # Замер BA на синтетических пакетах: `uv tool install` отказывает кодом 2 и
  # текстом "Executable already exists" именно и только когда слот команды
  # уже занят ДРУГИМ пакетом (ADR-024 Д3) — распознаётся текстом, не
  # предугадывается заранее опросом `uv tool list` (список ненадёжен именно в
  # этом состоянии, companion «Форма коллизии слота»).
  [ "$1" -eq 2 ] 2>/dev/null && printf '%s' "$2" | grep -qi 'executable already exists'
}

report_slot_collision() { # report_slot_collision <имя-пина> <версия-пина> <текст ремонта>
  # Никогда не добавляет --force и не повторяет попытку (ADR-024 Д3) — только
  # называет обе стороны коллизии: пакет, который пытались поставить (пин), и
  # (если определим) пакет, реально удерживающий слот сейчас.
  local pin_n="$1" pin="$2" remedy_text="$3" active=''
  if installed_identity; then active="$II_NAME"; fi
  install_report slot_collision "${active}" "" "$pin_n" "$pin" \
    "Слот команды ktalk уже занят пакетом ${active:-другим пакетом} — установка $pin_n $pin остановлена без изменения состояния системы. Автоматическая принудительная замена (--force) не выполняется ни при какой санкции; это ручное действие оператора." \
    "$remedy_text"
}

finish_install() { # finish_install <пин> — постусловие установки/ремонта (FR-31)
  # Код возврата менеджера пакетов не является доказательством совместимости:
  # `uv tool install` печатает «Already installed»/«Nothing to upgrade» с
  # кодом 0, а индекс может отдавать версию, не равную пину. Постусловие
  # перечитывает идентичность тем же предикатом, что и cmd_check —
  # verb-агностично: install и update ветки зовут одну и ту же команду ремонта
  # (ADR-022 Д2), поэтому единственный параметр здесь — пин, текст команды
  # и имя пакета вычисляются внутри.
  #
  # Предикат выровнен с cmd_check (DEV-007, дефект 1), а не наоборот: успех install
  # требует того же — `command -v ktalk` — что и первый гейт check, не только
  # installed_identity() с fallback на `uv tool list`. Без этого install мог вернуть 0,
  # когда пакет поставлен вне PATH (типовой случай ~/.local/bin не в PATH) — уже
  # следующий check в цепочке check → install → check отдавал бы 10, расходясь с
  # «успехом», о котором только что отчитался install.
  local pin="$1" pin_n remedy_text installed_name installed_ver
  pin_n="$(pin_name)"
  remedy_text="$(remedy_cmd_text "$pin")"
  hash -r 2>/dev/null || true
  if ! command -v ktalk >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1 && installed_identity; then
      installed_name="$II_NAME"; installed_ver="$II_VERSION"
    else
      installed_name=""; installed_ver=""
    fi
    install_report missing_cli "$installed_name" "$installed_ver" "$pin_n" "$pin" \
      "Менеджер пакетов сообщает об установке${installed_ver:+ (версия $installed_ver)}, но команда ktalk не резолвится через PATH. Добавьте каталог инструментов uv (обычно ~/.local/bin) в PATH и повторите: $remedy_text" \
      "$remedy_text"
    return "$E_MISSING_CLI"
  fi
  if installed_identity; then installed_name="$II_NAME"; installed_ver="$II_VERSION"
  else installed_name=""; installed_ver=""; fi
  if [ -z "$installed_name" ] || ! identity_eq "$installed_name" "$pin_n"; then
    install_report wrong_package "$installed_name" "$installed_ver" "$pin_n" "$pin" \
      "Установлен пакет ${installed_name:-неопределим} (${installed_ver:-?}), а требуется $pin_n $pin. Ремонт: $remedy_text" \
      "$remedy_text"
    return "$E_WRONG_PACKAGE"
  fi
  if [ -z "$installed_ver" ] || ! version_eq "$installed_ver" "$pin"; then
    install_report outdated "$installed_name" "$installed_ver" "$pin_n" "$pin" \
      "Версия пакета (${installed_ver:-неопределима}) не совпадает с требуемой версией $pin. Ремонт: $remedy_text" \
      "$remedy_text"
    return "$E_OUTDATED"
  fi
  install_report ok "$installed_name" "$installed_ver" "$pin_n" "$pin" "Пакет $pin_n $installed_ver установлен, версия совместима." "$remedy_text"
  return "$E_OK"
}

cmd_install() {
  local pin pin_n installed_name installed_ver remedy_text
  # RI_RAN сброшен явно (DEV-007 дефект 2): все выходы из этой функции идут через
  # install_report, а не report, чтобы attempts/return_code/uv_output были в JSON на
  # любом исходе, включая ветки, где менеджер пакетов не запускается вовсе.
  RI_RAN=0; RI_RETRIED=0; RI_RC=0; RI_OUT=''; RI_FIRST_OUT=''
  if ! pin="$(pin_version)"; then
    install_report error "" "" "" "" "Не прочитан compat.json плагина — переустановите плагин." ""
    return "$E_INTERNAL"
  fi
  pin_n="$(pin_name)"
  remedy_text="$(remedy_cmd_text "$pin")"
  if ! command -v uv >/dev/null 2>&1; then
    install_report missing_uv "" "" "$pin_n" "$pin" "Не найден uv. Установите uv, затем: $remedy_text" "$remedy_text"
    return "$E_MISSING_UV"
  fi
  if command -v ktalk >/dev/null 2>&1; then
    if installed_identity; then installed_name="$II_NAME"; installed_ver="$II_VERSION"
    else installed_name=""; installed_ver=""; fi
    if [ -n "$installed_name" ] && identity_eq "$installed_name" "$pin_n" && version_eq "$installed_ver" "$pin"; then
      install_report ok "$installed_name" "$installed_ver" "$pin_n" "$pin" "Пакет $pin_n $installed_ver уже установлен — установка не требуется." "$remedy_text"
      return "$E_OK"
    fi
    # Санкция на обновление нужна и когда установленная версия НОВЕЕ пина, не
    # только когда она старше (ADR-022 Д2/Д3) — под точным пином расхождение в
    # обе стороны требует мутации уже существующего состояния машины, а не
    # только «движения вперёд». Та же ветка накрывает и смену ИДЕНТИЧНОСТИ
    # пакета (ADR-024 Д3): «команда уже существует и указывает на что-то
    # другое» уже описывает и другой пакет, не только другую версию того же —
    # новый ключ санкции не заводится.
    if ! sanction_granted update; then
      install_report no_update_sanction "$installed_name" "$installed_ver" "$pin_n" "$pin" \
        "Установлен ${installed_name:-неопределимый пакет} ${installed_ver:-неопределимой версии}, а требуется $pin_n $pin. Ремонт требует отдельной санкции: bash ${BASH_SOURCE[0]} grant update" \
        "$remedy_text"
      return "$E_NO_UPDATE_SANCTION"
    fi
    remedy_cmd_array "$pin"
    if ! run_install "$remedy_text" "${REMEDY_CMD[@]}"; then
      if is_slot_collision "$RI_RC" "$RI_OUT"; then
        report_slot_collision "$pin_n" "$pin" "$remedy_text"
        return "$E_SLOT_COLLISION"
      fi
      install_report install_failed "$installed_name" "$installed_ver" "$pin_n" "$pin" \
        "Команда «${remedy_text}» завершилась с кодом $RI_RC. Состояние системы не изменено." \
        "$remedy_text"
      return "$E_INSTALL_FAILED"
    fi
    finish_install "$pin"
    return $?
  fi
  if ! sanction_granted install; then
    install_report no_sanction "" "" "$pin_n" "$pin" \
      "Санкции на автоматическую установку нет. Установите сами: $remedy_text — или выдайте санкцию: bash ${BASH_SOURCE[0]} grant install" \
      "$remedy_text"
    return "$E_NO_SANCTION"
  fi
  remedy_cmd_array "$pin"
  if ! run_install "$remedy_text" "${REMEDY_CMD[@]}"; then
    if is_slot_collision "$RI_RC" "$RI_OUT"; then
      report_slot_collision "$pin_n" "$pin" "$remedy_text"
      return "$E_SLOT_COLLISION"
    fi
    install_report install_failed "" "" "$pin_n" "$pin" \
      "Команда «${remedy_text}» завершилась с кодом $RI_RC. Состояние системы не изменено." \
      "$remedy_text"
    return "$E_INSTALL_FAILED"
  fi
  finish_install "$pin"
}

main() {
  local cmd="${1:-}"; shift || true
  local rest=()
  for arg in "$@"; do
    case "$arg" in
      --json) JSON=1 ;;
      *) rest+=("$arg") ;;
    esac
  done
  case "$cmd" in
    check) cmd_check ;;
    install) cmd_install ;;
    status) cmd_status ;;
    grant) cmd_grant "${rest[0]:-}" ;;
    revoke) cmd_revoke "${rest[0]:-}" ;;
    *)
      printf 'Использование: ktalk-onboard.sh {check|install|grant|revoke|status} [--json]\n' >&2
      return "$E_INTERNAL" ;;
  esac
}

main "$@"
