#!/usr/bin/env bash
# Онбординг плагина ktalk: обнаружение пакета, санкция, установка.
# Контракт — ADR-014-onboarding-spec.md в репозитории пакета ktalk-mcp.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPAT_FILE="$PLUGIN_ROOT/compat.json"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ktalk"
SANCTION_FILE="$CONFIG_DIR/onboarding.toml"
# Команда ремонта (install/update) не может быть top-level константой: она
# встраивает пин, и пин не известен раньше, чем прочитан compat.json —
# см. remedy_cmd_text/remedy_cmd_array ниже, вызываемые после pin_version()
# (ADR-022 companion, «Точка правки: порядок инициализации»).

E_OK=0; E_MISSING_CLI=10; E_OUTDATED=11; E_MISSING_UV=12; E_INTERNAL=20
E_NO_SANCTION=30; E_INSTALL_FAILED=31; E_NO_UPDATE_SANCTION=32; E_NO_TTY=33

JSON=0

pin_version() { # pin_version → печатает пин из compat.json либо отказывает
  # Ключ compat.json — "ktalk_mcp_version", точный semver, не диапазон
  # (ADR-022 Д3). Отсутствие ключа (в любой форме, включая старый
  # "ktalk_mcp_min_version") — отказ, не молчаливый дефолт: нет пина —
  # не с чем сравнивать (E_INTERNAL=20 у вызывающей стороны).
  local raw
  raw="$(grep -Eo '"ktalk_mcp_version"[[:space:]]*:[[:space:]]*"[^"]+"' "$COMPAT_FILE" 2>/dev/null \
        | head -1 | sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/')"
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw"
}

remedy_cmd_text() { # remedy_cmd_text <пин> → текст команды ремонта с явным пином
  # Одна и та же команда для install и update (ADR-022 Д2): под точным пином
  # санкции разводят install/update по смыслу действия (создание состояния vs
  # мутация чужого), не по тексту команды — оба случая переустанавливают ровно
  # версию пина, не "upgrade" на новейшую.
  printf 'uv tool install ktalk-mcp==%s' "$1"
}

remedy_cmd_array() { # remedy_cmd_array <пин> → заполняет глобальный REMEDY_CMD
  REMEDY_CMD=(uv tool install "ktalk-mcp==$1")
}

installed_version() {
  local out
  if out="$(ktalk --version 2>/dev/null)"; then
    out="$(printf '%s' "$out" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
  fi
  if command -v uv >/dev/null 2>&1; then
    out="$(uv tool list 2>/dev/null | grep -E '^ktalk-mcp[[:space:]]' | head -1 \
          | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
  fi
  return 1
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
  case "$1" in *-*) a_pre="${1#*-}"; a_pre="${a_pre%%+*}" ;; esac
  case "$2" in *-*) b_pre="${2#*-}"; b_pre="${b_pre%%+*}" ;; esac
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

report() { # report <status> <installed> <pin> <message> [cmd_text]
  # JSON-ключ поля остаётся "min_version" сознательно (companion-статья,
  # «Синтаксис пина»): то же минимально-рискованное решение, каким там
  # оставлен статус "outdated" для обеих сторон расхождения — не множить
  # изменения во внешней поверхности `--json`, которую уже читает
  # test-onboard.sh и любой внешний потребитель, ради переименования поля,
  # которое ни один сценарий не проверяет по имени.
  local cmd_text="${5:-}"
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"%s","installed_version":"%s","min_version":"%s","install_command":"%s","message":"%s"}\n' \
      "$(json_escape "$1")" "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$cmd_text")" "$(json_escape "$4")"
  else
    printf '%s\n' "$4"
  fi
}

cmd_check() {
  local pin installed remedy_text
  if ! pin="$(pin_version)"; then
    report error "" "" "Не прочитан compat.json плагина — переустановите плагин." ""
    return "$E_INTERNAL"
  fi
  remedy_text="$(remedy_cmd_text "$pin")"
  if ! command -v ktalk >/dev/null 2>&1; then
    if ! command -v uv >/dev/null 2>&1; then
      report missing_uv "" "$pin" "Не найден uv. Установите uv, затем: $remedy_text" "$remedy_text"
      return "$E_MISSING_UV"
    fi
    report missing_cli "" "$pin" "Пакет ktalk-mcp не установлен. Команда установки: $remedy_text" "$remedy_text"
    return "$E_MISSING_CLI"
  fi
  installed="$(installed_version)" || installed=""
  if [ -z "$installed" ] || ! version_eq "$installed" "$pin"; then
    report outdated "$installed" "$pin" \
      "Версия пакета (${installed:-неопределима}) не совпадает с требуемой версией $pin. Ремонт: $remedy_text" \
      "$remedy_text"
    return "$E_OUTDATED"
  fi
  report ok "$installed" "$pin" "Пакет ktalk-mcp $installed установлен, версия совместима." "$remedy_text"
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

install_report() { # install_report <status> <installed> <min> <message> <cmd_text>
  # Тот же набор полей, что у report(), плюс телеметрия запуска менеджера пакетов.
  # Поля attempts/return_code/uv_output печатаются на ЛЮБОМ исходе (DEV-007 дефект 2,
  # ADR-014-onboarding-spec §1) — включая ветки, где менеджер не запускался (нет
  # санкции, нет uv, нужна отдельная санкция на обновление, пакет уже свежий):
  # attempts=0, return_code=null, uv_output="" — честные значения «менеджер не
  # запускался», не пропуск полей.
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
    printf '{"status":"%s","installed_version":"%s","min_version":"%s","install_command":"%s","attempts":%s,"return_code":%s,"uv_output":"%s"%s,"message":"%s"}\n' \
      "$(json_escape "$1")" "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$5")" \
      "$attempts" "$rc_field" "$(json_escape "$RI_OUT")" "$tail" "$(json_escape "$4")"
  else
    printf '%s\n' "$4"
  fi
}

finish_install() { # finish_install <пин> — постусловие установки/ремонта (FR-31)
  # Код возврата менеджера пакетов не является доказательством совместимости:
  # `uv tool install` печатает «Already installed»/«Nothing to upgrade» с
  # кодом 0, а индекс может отдавать версию, не равную пину. Постусловие
  # перечитывает версию тем же предикатом равенства, что и cmd_check —
  # verb-агностично: install и update ветки зовут одну и ту же команду ремонта
  # (ADR-022 Д2), поэтому единственный параметр здесь — пин, текст команды
  # вычисляется внутри.
  #
  # Предикат выровнен с cmd_check (DEV-007, дефект 1), а не наоборот: успех install
  # требует того же — `command -v ktalk` — что и первый гейт check, не только
  # installed_version() с fallback на `uv tool list`. Без этого install мог вернуть 0,
  # когда пакет поставлен вне PATH (типовой случай ~/.local/bin не в PATH) — уже
  # следующий check в цепочке check → install → check отдавал бы 10, расходясь с
  # «успехом», о котором только что отчитался install.
  local pin="$1" installed remedy_text
  remedy_text="$(remedy_cmd_text "$pin")"
  hash -r 2>/dev/null || true
  if ! command -v ktalk >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1; then
      installed="$(installed_version)" || installed=""
    else
      installed=""
    fi
    install_report missing_cli "$installed" "$pin" \
      "Менеджер пакетов сообщает об установке${installed:+ (версия $installed)}, но команда ktalk не резолвится через PATH. Добавьте каталог инструментов uv (обычно ~/.local/bin) в PATH и повторите: $remedy_text" \
      "$remedy_text"
    return "$E_MISSING_CLI"
  fi
  installed="$(installed_version)" || installed=""
  if [ -z "$installed" ] || ! version_eq "$installed" "$pin"; then
    install_report outdated "$installed" "$pin" \
      "Версия пакета (${installed:-неопределима}) не совпадает с требуемой версией $pin. Ремонт: $remedy_text" \
      "$remedy_text"
    return "$E_OUTDATED"
  fi
  install_report ok "$installed" "$pin" "Пакет ktalk-mcp $installed установлен, версия совместима." "$remedy_text"
  return "$E_OK"
}

cmd_install() {
  local pin installed remedy_text
  # RI_RAN сброшен явно (DEV-007 дефект 2): все выходы из этой функции идут через
  # install_report, а не report, чтобы attempts/return_code/uv_output были в JSON на
  # любом исходе, включая ветки, где менеджер пакетов не запускается вовсе.
  RI_RAN=0; RI_RETRIED=0; RI_RC=0; RI_OUT=''; RI_FIRST_OUT=''
  if ! pin="$(pin_version)"; then
    install_report error "" "" "Не прочитан compat.json плагина — переустановите плагин." ""
    return "$E_INTERNAL"
  fi
  remedy_text="$(remedy_cmd_text "$pin")"
  if ! command -v uv >/dev/null 2>&1; then
    install_report missing_uv "" "$pin" "Не найден uv. Установите uv, затем: $remedy_text" "$remedy_text"
    return "$E_MISSING_UV"
  fi
  if command -v ktalk >/dev/null 2>&1; then
    installed="$(installed_version)" || installed=""
    if [ -n "$installed" ] && version_eq "$installed" "$pin"; then
      install_report ok "$installed" "$pin" "Пакет ktalk-mcp $installed уже установлен — установка не требуется." "$remedy_text"
      return "$E_OK"
    fi
    # Санкция на обновление нужна и когда установленная версия НОВЕЕ пина, не
    # только когда она старше (ADR-022 Д2/Д3) — под точным пином расхождение в
    # обе стороны требует мутации уже существующего состояния машины, а не
    # только «движения вперёд».
    if ! sanction_granted update; then
      install_report no_update_sanction "$installed" "$pin" \
        "Версия ${installed:-неопределима} не совпадает с требуемой $pin. Ремонт требует отдельной санкции: bash ${BASH_SOURCE[0]} grant update" \
        "$remedy_text"
      return "$E_NO_UPDATE_SANCTION"
    fi
    remedy_cmd_array "$pin"
    if ! run_install "$remedy_text" "${REMEDY_CMD[@]}"; then
      install_report install_failed "$installed" "$pin" \
        "Команда «${remedy_text}» завершилась с кодом $RI_RC. Состояние системы не изменено." \
        "$remedy_text"
      return "$E_INSTALL_FAILED"
    fi
    finish_install "$pin"
    return $?
  fi
  if ! sanction_granted install; then
    install_report no_sanction "" "$pin" \
      "Санкции на автоматическую установку нет. Установите сами: $remedy_text — или выдайте санкцию: bash ${BASH_SOURCE[0]} grant install" \
      "$remedy_text"
    return "$E_NO_SANCTION"
  fi
  remedy_cmd_array "$pin"
  if ! run_install "$remedy_text" "${REMEDY_CMD[@]}"; then
    install_report install_failed "" "$pin" \
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
