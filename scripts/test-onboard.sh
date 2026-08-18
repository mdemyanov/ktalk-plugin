#!/usr/bin/env bash
# Тесты онбординг-скрипта. Прогон ручной: bash scripts/test-onboard.sh
# Ветка записи `grant` в TTY здесь НЕ проверяется — эмуляция pty обошла бы барьер,
# который тест и должен защищать (проверка владельцем вручную, ADR-014-onboarding-spec §8).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/ktalk-onboard.sh"
PASS=0; FAIL=0

check_eq() { # check_eq <ожидание> <факт> <название>
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$3"
  else FAIL=$((FAIL+1)); printf 'FAIL %s: ожидалось "%s", получено "%s"\n' "$3" "$1" "$2"; fi
}

make_env() { # make_env <каталог> — временный PATH и XDG_CONFIG_HOME
  TMP="$(mktemp -d)"; mkdir -p "$TMP/bin" "$TMP/config"
  export XDG_CONFIG_HOME="$TMP/config"
  export PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

stub() { # stub <имя> <код> <stdout>
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\nexit %s\n' "$3" "$2" > "$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

# 1. ktalk отсутствует, uv есть → 10
make_env; stub uv 0 ""
"$SCRIPT" check >/dev/null 2>&1; check_eq 10 $? "check: нет ktalk, есть uv → 10"

# 2. ни ktalk, ни uv → 12
make_env
"$SCRIPT" check >/dev/null 2>&1; check_eq 12 $? "check: нет uv → 12"

# 3. версия ниже минимальной → 11
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.4.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 11 $? "check: 0.4.0 < 0.7.0 → 11"

# 4. версия достаточна → 0
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.7.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 0 $? "check: 0.7.0 → 0"

# 5. версия выше минимальной → 0
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 1.2.3"
"$SCRIPT" check >/dev/null 2>&1; check_eq 0 $? "check: 1.2.3 → 0"

# 6. --version не поддержан, версия берётся из uv tool list
make_env
printf '#!/usr/bin/env bash\nexit 2\n' > "$TMP/bin/ktalk"; chmod +x "$TMP/bin/ktalk"
stub uv 0 "ktalk-mcp v0.7.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 0 $? "check: fallback на uv tool list"

# 7. --json печатает валидный JSON
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.7.0"
OUT="$("$SCRIPT" check --json 2>/dev/null)"
printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
check_eq 0 $? "check --json: валидный JSON"

# 8. нет файла санкции → status сообщает отсутствие, код 0
make_env
OUT="$("$SCRIPT" status --json 2>/dev/null)"; check_eq 0 $? "status: без файла код 0"
printf '%s' "$OUT" | grep -q '"install":false' ; check_eq 0 $? "status: install=false без файла"

# 9. корректный файл → санкция видна
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
"$SCRIPT" status --json 2>/dev/null | grep -q '"install":true'
check_eq 0 $? "status: allow_install = true распознан"

# 10. мусор в файле → fail-closed
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install=maybe\nallow_install : true\n<<<\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
"$SCRIPT" status --json 2>/dev/null | grep -q '"install":false'
check_eq 0 $? "status: битый файл → санкции нет"

# 11. grant без TTY → 33 и файл не создан
make_env
"$SCRIPT" grant install </dev/null >/dev/null 2>&1; check_eq 33 $? "grant без TTY → 33"
[ -f "$XDG_CONFIG_HOME/ktalk/onboarding.toml" ]; check_eq 1 $? "grant без TTY не создал файл"

# 12. revoke снимает ключ без TTY
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
"$SCRIPT" revoke install >/dev/null 2>&1; check_eq 0 $? "revoke: код 0"
"$SCRIPT" status --json 2>/dev/null | grep -q '"install":false'
check_eq 0 $? "revoke: санкция снята"

# 13. неизвестный ключ санкции → 20
make_env
"$SCRIPT" grant everything </dev/null >/dev/null 2>&1; check_eq 20 $? "grant с неверным ключом → 20"

# 14. нет санкции → 30, uv не вызывался
make_env
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 30 $? "install: без санкции → 30"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: без санкции uv не вызывался"

# 15. санкция есть, установка успешна → 0
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
printf '#!/usr/bin/env bash\necho "Installed 1 executable: ktalk"\nexit 0\n' > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: с санкцией → 0"

# 16. пакет уже свежий → 0 и uv не вызывался (идемпотентность)
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.7.0"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: уже установлен → 0"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: уже установлен — uv не вызывался"

# 17. устаревшая версия без санкции на обновление → 32
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.4.0"; stub uv 0 ""
"$SCRIPT" install >/dev/null 2>&1; check_eq 32 $? "install: устарел, нет allow_update → 32"

# 18. сетевая ошибка → ровно две попытки, код 31
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
printf '#!/usr/bin/env bash\necho attempt >> "%s/attempts"\necho "error: Failed to fetch" >&2\nexit 1\n' \
  "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 31 $? "install: сетевой сбой → 31"
check_eq 2 "$(wc -l < "$TMP/attempts" | tr -d ' ')" "install: сетевой сбой — ровно 2 попытки"

# 19. несетевая ошибка → одна попытка, код 31
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
printf '#!/usr/bin/env bash\necho attempt >> "%s/attempts"\necho "error: Permission denied" >&2\nexit 1\n' \
  "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 31 $? "install: отказ прав → 31"
check_eq 1 "$(wc -l < "$TMP/attempts" | tr -d ' ')" "install: отказ прав — одна попытка"

# 20. нет uv → 12
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
"$SCRIPT" install >/dev/null 2>&1; check_eq 12 $? "install: нет uv → 12"

# 21 (Ruling R7). allow_update = true не даёт санкции на установку
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 30 $? "install: allow_update не даёт установки → 30"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: allow_update — uv не вызывался"

# 22 (Ruling R4). устарел, обе санкции выданы → 0, вызван upgrade, не install
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.4.0"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "%s/uv-args"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: устарел, есть allow_update → 0"
grep -q '^upgrade$' "$TMP/uv-args"; check_eq 0 $? "install: ветка обновления вызывает uv tool upgrade"
grep -qx 'install' "$TMP/uv-args"; check_eq 1 $? "install: ветка обновления не вызывает uv tool install"

printf '\nPASS: %s  FAIL: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
