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

printf '\nPASS: %s  FAIL: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
