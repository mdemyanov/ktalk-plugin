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

report() { # report <status> <installed> <min> <message>
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"%s","installed_version":"%s","min_version":"%s","install_command":"%s","message":"%s"}\n' \
      "$1" "$2" "$3" "$INSTALL_CMD_TEXT" "$4"
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
      "Версия пакета (${installed:-неопределима}) ниже минимально совместимой $min. Обновление: uv tool upgrade ktalk-mcp"
    return "$E_OUTDATED"
  fi
  report ok "$installed" "$min" "Пакет ktalk-mcp $installed установлен, версия совместима."
  return "$E_OK"
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
    *)
      printf 'Использование: ktalk-onboard.sh {check|install|grant|revoke|status} [--json]\n' >&2
      return "$E_INTERNAL" ;;
  esac
}

main "$@"
