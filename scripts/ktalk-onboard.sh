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

run_install() { # run_install <текст команды для пользователя> <команда...>
  local cmd_text="$1"; shift
  local out1 rc1 out2='' rc2='' retried=0

  out1="$("$@" 2>&1)"; rc1=$?

  if [ "$rc1" -ne 0 ] && is_network_error "$out1"; then
    retried=1
    if [ "$JSON" -ne 1 ]; then
      printf 'Попытка 1:\n%s\n' "$out1"
      printf 'Сетевая ошибка, повтор через %s с.\n' "$RETRY_DELAY"
    fi
    sleep "$RETRY_DELAY"
    out2="$("$@" 2>&1)"; rc2=$?
    if [ "$JSON" -ne 1 ]; then
      printf 'Попытка 2:\n%s\n' "$out2"
    fi
  fi

  local final_rc
  if [ "$retried" -eq 1 ]; then final_rc="$rc2"; else final_rc="$rc1"; fi

  if [ "$JSON" -eq 1 ]; then
    local status_str
    if [ "$final_rc" -eq 0 ]; then status_str=ok; else status_str=install_failed; fi
    if [ "$retried" -eq 1 ]; then
      printf '{"status":"%s","install_command":"%s","attempts":2,"return_code":%s,"uv_output":"%s","first_attempt_output":"%s"}\n' \
        "$status_str" "$(json_escape "$cmd_text")" "$final_rc" "$(json_escape "$out2")" "$(json_escape "$out1")"
    else
      printf '{"status":"%s","install_command":"%s","attempts":1,"return_code":%s,"uv_output":"%s"}\n' \
        "$status_str" "$(json_escape "$cmd_text")" "$final_rc" "$(json_escape "$out1")"
    fi
  else
    if [ "$retried" -ne 1 ]; then
      printf '%s\n' "$out1"
    fi
    printf 'Команда: %s\nКод возврата: %s\n' "$cmd_text" "$final_rc"
  fi

  [ "$final_rc" -eq 0 ] || return "$E_INSTALL_FAILED"
  return "$E_OK"
}

cmd_install() {
  local min installed
  if ! min="$(min_version)"; then
    report error "" "" "Не прочитан compat.json плагина — переустановите плагин."
    return "$E_INTERNAL"
  fi
  if ! command -v uv >/dev/null 2>&1; then
    report missing_uv "" "$min" "Не найден uv. Установите uv, затем: $INSTALL_CMD_TEXT"
    return "$E_MISSING_UV"
  fi
  if command -v ktalk >/dev/null 2>&1; then
    installed="$(installed_version)" || installed=""
    if [ -n "$installed" ] && version_ge "$installed" "$min"; then
      report ok "$installed" "$min" "Пакет ktalk-mcp $installed уже установлен — установка не требуется."
      return "$E_OK"
    fi
    if ! sanction_granted update; then
      report no_update_sanction "$installed" "$min" \
        "Версия ${installed:-неопределима} ниже $min. Обновление требует отдельной санкции: bash ${BASH_SOURCE[0]} grant update" \
        "$UPDATE_CMD_TEXT"
      return "$E_NO_UPDATE_SANCTION"
    fi
    run_install "$UPDATE_CMD_TEXT" "${UPDATE_CMD[@]}"
    return $?
  fi
  if ! sanction_granted install; then
    report no_sanction "" "$min" \
      "Санкции на автоматическую установку нет. Установите сами: $INSTALL_CMD_TEXT — или выдайте санкцию: bash ${BASH_SOURCE[0]} grant install"
    return "$E_NO_SANCTION"
  fi
  run_install "$INSTALL_CMD_TEXT" "${INSTALL_CMD[@]}"
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
