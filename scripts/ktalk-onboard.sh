#!/usr/bin/env bash
# Онбординг плагина ktalk: обнаружение пакета, санкция, установка.
# Контракт — ADR-014-onboarding-spec.md в репозитории пакета ktalk-mcp.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPAT_FILE="$PLUGIN_ROOT/compat.json"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ktalk"
SANCTION_FILE="$CONFIG_DIR/onboarding.toml"
INSTALL_CMD=(uv tool install ktalk-mcp)
INSTALL_CMD_TEXT="uv tool install ktalk-mcp"
UPDATE_CMD=(uv tool upgrade ktalk-mcp)
UPDATE_CMD_TEXT="uv tool upgrade ktalk-mcp"

E_OK=0; E_MISSING_CLI=10; E_OUTDATED=11; E_MISSING_UV=12; E_INTERNAL=20
E_NO_SANCTION=30; E_INSTALL_FAILED=31; E_NO_UPDATE_SANCTION=32; E_NO_TTY=33

JSON=0

min_version() {
  local raw
  raw="$(grep -Eo '"ktalk_mcp_min_version"[[:space:]]*:[[:space:]]*"[^"]+"' "$COMPAT_FILE" 2>/dev/null \
        | head -1 | sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/')"
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw"
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

version_ge() { # version_ge A B → 0, если A >= B
  local a b x y i
  IFS=. read -r -a a <<< "${1%%[-+]*}"
  IFS=. read -r -a b <<< "${2%%[-+]*}"
  for i in 0 1 2; do
    x="${a[i]:-0}"; y="${b[i]:-0}"
    x="${x//[!0-9]/}"; y="${y//[!0-9]/}"
    x="${x:-0}"; y="${y:-0}"
    if [ "$((10#$x))" -gt "$((10#$y))" ]; then return 0; fi
    if [ "$((10#$x))" -lt "$((10#$y))" ]; then return 1; fi
  done
  return 0
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

report() { # report <status> <installed> <min> <message> [cmd_text]
  local cmd_text="${5:-$INSTALL_CMD_TEXT}"
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"%s","installed_version":"%s","min_version":"%s","install_command":"%s","message":"%s"}\n' \
      "$(json_escape "$1")" "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$cmd_text")" "$(json_escape "$4")"
  else
    printf '%s\n' "$4"
  fi
}

cmd_check() {
  local min installed
  if ! min="$(min_version)"; then
    report error "" "" "Не прочитан compat.json плагина — переустановите плагин."
    return "$E_INTERNAL"
  fi
  if ! command -v ktalk >/dev/null 2>&1; then
    if ! command -v uv >/dev/null 2>&1; then
      report missing_uv "" "$min" "Не найден uv. Установите uv, затем: $INSTALL_CMD_TEXT"
      return "$E_MISSING_UV"
    fi
    report missing_cli "" "$min" "Пакет ktalk-mcp не установлен. Команда установки: $INSTALL_CMD_TEXT"
    return "$E_MISSING_CLI"
  fi
  installed="$(installed_version)" || installed=""
  if [ -z "$installed" ] || ! version_ge "$installed" "$min"; then
    report outdated "$installed" "$min" \
      "Версия пакета (${installed:-неопределима}) ниже минимально совместимой $min. Обновление: $UPDATE_CMD_TEXT" \
      "$UPDATE_CMD_TEXT"
    return "$E_OUTDATED"
  fi
  report ok "$installed" "$min" "Пакет ktalk-mcp $installed установлен, версия совместима."
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

finish_install() { # finish_install <min> <текст команды> — постусловие установки (FR-31)
  # Код возврата менеджера пакетов не является доказательством совместимости:
  # `uv tool upgrade` печатает «Nothing to upgrade» с кодом 0, а индекс может
  # отдавать версию ниже минимальной. Постусловие перечитывает версию.
  #
  # Предикат выровнен с cmd_check (DEV-007, дефект 1), а не наоборот: успех install
  # требует того же — `command -v ktalk` — что и первый гейт check, не только
  # installed_version() с fallback на `uv tool list`. Без этого install мог вернуть 0,
  # когда пакет поставлен вне PATH (типовой случай ~/.local/bin не в PATH) — уже
  # следующий check в цепочке check → install → check отдавал бы 10, расходясь с
  # «успехом», о котором только что отчитался install.
  local installed
  hash -r 2>/dev/null || true
  if ! command -v ktalk >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1; then
      installed="$(installed_version)" || installed=""
    else
      installed=""
    fi
    install_report missing_cli "$installed" "$1" \
      "Менеджер пакетов сообщает об установке${installed:+ (версия $installed)}, но команда ktalk не резолвится через PATH. Добавьте каталог инструментов uv (обычно ~/.local/bin) в PATH и повторите: $2" \
      "$2"
    return "$E_MISSING_CLI"
  fi
  installed="$(installed_version)" || installed=""
  if [ -z "$installed" ] || ! version_ge "$installed" "$1"; then
    install_report outdated "$installed" "$1" \
      "Версия пакета (${installed:-неопределима}) ниже минимально совместимой $1. Обновление: $UPDATE_CMD_TEXT" \
      "$UPDATE_CMD_TEXT"
    return "$E_OUTDATED"
  fi
  install_report ok "$installed" "$1" "Пакет ktalk-mcp $installed установлен, версия совместима." "$2"
  return "$E_OK"
}

cmd_install() {
  local min installed
  # RI_RAN сброшен явно (DEV-007 дефект 2): все выходы из этой функции идут через
  # install_report, а не report, чтобы attempts/return_code/uv_output были в JSON на
  # любом исходе, включая ветки, где менеджер пакетов не запускается вовсе.
  RI_RAN=0; RI_RETRIED=0; RI_RC=0; RI_OUT=''; RI_FIRST_OUT=''
  if ! min="$(min_version)"; then
    install_report error "" "" "Не прочитан compat.json плагина — переустановите плагин." "$INSTALL_CMD_TEXT"
    return "$E_INTERNAL"
  fi
  if ! command -v uv >/dev/null 2>&1; then
    install_report missing_uv "" "$min" "Не найден uv. Установите uv, затем: $INSTALL_CMD_TEXT" "$INSTALL_CMD_TEXT"
    return "$E_MISSING_UV"
  fi
  if command -v ktalk >/dev/null 2>&1; then
    installed="$(installed_version)" || installed=""
    if [ -n "$installed" ] && version_ge "$installed" "$min"; then
      install_report ok "$installed" "$min" "Пакет ktalk-mcp $installed уже установлен — установка не требуется." "$INSTALL_CMD_TEXT"
      return "$E_OK"
    fi
    if ! sanction_granted update; then
      install_report no_update_sanction "$installed" "$min" \
        "Версия ${installed:-неопределима} ниже $min. Обновление требует отдельной санкции: bash ${BASH_SOURCE[0]} grant update" \
        "$UPDATE_CMD_TEXT"
      return "$E_NO_UPDATE_SANCTION"
    fi
    if ! run_install "$UPDATE_CMD_TEXT" "${UPDATE_CMD[@]}"; then
      install_report install_failed "$installed" "$min" \
        "Команда «${UPDATE_CMD_TEXT}» завершилась с кодом $RI_RC. Состояние системы не изменено." \
        "$UPDATE_CMD_TEXT"
      return "$E_INSTALL_FAILED"
    fi
    finish_install "$min" "$UPDATE_CMD_TEXT"
    return $?
  fi
  if ! sanction_granted install; then
    install_report no_sanction "" "$min" \
      "Санкции на автоматическую установку нет. Установите сами: $INSTALL_CMD_TEXT — или выдайте санкцию: bash ${BASH_SOURCE[0]} grant install" \
      "$INSTALL_CMD_TEXT"
    return "$E_NO_SANCTION"
  fi
  if ! run_install "$INSTALL_CMD_TEXT" "${INSTALL_CMD[@]}"; then
    install_report install_failed "" "$min" \
      "Команда «${INSTALL_CMD_TEXT}» завершилась с кодом $RI_RC. Состояние системы не изменено." \
      "$INSTALL_CMD_TEXT"
    return "$E_INSTALL_FAILED"
  fi
  finish_install "$min" "$INSTALL_CMD_TEXT"
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
