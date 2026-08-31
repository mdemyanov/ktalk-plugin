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

stub_uv_installs() { # stub_uv_installs <версия> [текст вывода] — uv, «ставящий» ktalk
  local msg="${2:-Installed 1 executable: ktalk}"
  cat > "$TMP/bin/uv" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$@" >> "$TMP/uv-args"
printf '#!/usr/bin/env bash\\nprintf "ktalk-mcp $1\\\\n"\\n' > "$TMP/bin/ktalk"
chmod +x "$TMP/bin/ktalk"
echo "$msg"
exit 0
EOF
  chmod +x "$TMP/bin/uv"
}

stub_uv_installs_off_path() { # stub_uv_installs_off_path <версия> — DEV-007 дефект 1:
  # «ставит» ktalk вне PATH (типовой случай ~/.local/bin не в PATH), но `uv tool list`
  # видит установленный пакет — воспроизводит расхождение предикатов install/check.
  mkdir -p "$TMP/offpath"
  cat > "$TMP/bin/uv" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tool" ] && [ "\$2" = "list" ]; then
  printf 'ktalk-mcp v$1\\n'
  exit 0
fi
printf '%s\\n' "\$@" >> "$TMP/uv-args"
printf '#!/usr/bin/env bash\\nprintf "ktalk-mcp $1\\\\n"\\n' > "$TMP/offpath/ktalk"
chmod +x "$TMP/offpath/ktalk"
echo "Installed 1 executable: ktalk"
exit 0
EOF
  chmod +x "$TMP/bin/uv"
}

# 1. ktalk отсутствует, uv есть → 10
make_env; stub uv 0 ""
"$SCRIPT" check >/dev/null 2>&1; check_eq 10 $? "check: нет ktalk, есть uv → 10"

# 2. ни ktalk, ни uv → 12
make_env
"$SCRIPT" check >/dev/null 2>&1; check_eq 12 $? "check: нет uv → 12"

# 3. версия ниже минимальной → 11
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.4.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 11 $? "check: 0.4.0 < 0.10.0 → 11"

# 3a. 0.9.2 ниже 0.10.0 — сравнение посегментно-числовое, не лексикографическое
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.9.2"
"$SCRIPT" check >/dev/null 2>&1; check_eq 11 $? "check: 0.9.2 < 0.10.0 → 11"

# 4. версия достаточна → 0
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.10.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 0 $? "check: 0.10.0 → 0"

# 5 (AC-7, ADR-022 Д3 — пин симметричен, не порог). Версия ВЫШЕ пина тоже
# несовместима: «новее» перестаёт быть безусловным OK, как было при пороге.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 1.2.3"
"$SCRIPT" check >/dev/null 2>&1; check_eq 11 $? "check: 1.2.3 (новее пина 0.10.0) → 11, не молчаливый 0"

# 6. --version не поддержан, версия берётся из uv tool list
make_env
printf '#!/usr/bin/env bash\nexit 2\n' > "$TMP/bin/ktalk"; chmod +x "$TMP/bin/ktalk"
stub uv 0 "ktalk-mcp v0.10.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 0 $? "check: fallback на uv tool list"

# 7. --json печатает валидный JSON
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.10.0"
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
stub_uv_installs 0.10.0
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: с санкцией → 0"

# 16. пакет уже свежий → 0 и uv не вызывался (идемпотентность)
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.10.0"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: уже установлен → 0"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: уже установлен — uv не вызывался"

# 17. устаревшая версия без санкции на обновление → 32
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.4.0"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 32 $? "install: устарел, нет allow_update → 32"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: устарел, нет allow_update — uv не вызывался"

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

# 22 (Ruling R4, пересмотрено ADR-022 Д2/AC-8). устарел, обе санкции выданы →
# 0; ремонт зовёт ТУ ЖЕ команду install==<пин>, не upgrade — Д2 не разводит
# install/update по тексту команды, только по санкции, проверяемой раньше.
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.4.0"
stub_uv_installs 0.10.0 "Installed 1 executable: ktalk"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: устарел, есть allow_update → 0"
grep -qx 'install' "$TMP/uv-args"; check_eq 0 $? "install: ремонт зовёт uv tool install, не upgrade (AC-8)"
grep -q '^ktalk-mcp==0\.10\.0$' "$TMP/uv-args"; check_eq 0 $? "install: аргумент называет пин явно — ktalk-mcp==0.10.0 (AC-8)"

# 23. install --json на успехе → валидный JSON
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub_uv_installs 0.10.0
OUT="$("$SCRIPT" install --json 2>/dev/null)"
printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
check_eq 0 $? "install --json: валидный JSON на успехе"

# 24. install --json на провале (код 31) → валидный JSON
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
printf '#!/usr/bin/env bash\necho "error: Permission denied"\nexit 1\n' > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
OUT="$("$SCRIPT" install --json 2>/dev/null)"
check_eq 31 $? "install --json: код возврата 31 сохранён"
printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
check_eq 0 $? "install --json: валидный JSON на провале"

# 25. install --json на выводе uv с кавычкой и переводом строки → валидный JSON
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
printf '#!/usr/bin/env bash\nprintf '"'"'strange "quoted" line\\nsecond line\\n'"'"'\nexit 0\n' \
  > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
OUT="$("$SCRIPT" install --json 2>/dev/null)"
printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
check_eq 0 $? "install --json: валидный JSON при кавычках и переводах строк в выводе uv"

# 26. NFR-19: секреты KTalk не доходят до дочернего процесса и не попадают в вывод.
# Стаб uv дампит своё окружение — худший случай ретрансляции (SEC-004, MAJ-01).
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
printf '#!/usr/bin/env bash\nenv | sort\nexit 0\n' > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
FIXTURE_TOKEN="SYNTHETIC-ONBOARD-TOKEN-0000000000"
FIXTURE_URL="https://example.invalid"
OUT="$(KTALK_SESSION_TOKEN="$FIXTURE_TOKEN" KTALK_PERSONAL_API_KEY="$FIXTURE_TOKEN" \
       KTALK_BASE_URL="$FIXTURE_URL" "$SCRIPT" install --json 2>&1)"
printf '%s' "$OUT" | grep -q "$FIXTURE_TOKEN"
check_eq 1 $? "install --json: значение токена не попадает в вывод"
OUT="$(KTALK_SESSION_TOKEN="$FIXTURE_TOKEN" KTALK_PERSONAL_API_KEY="$FIXTURE_TOKEN" \
       KTALK_BASE_URL="$FIXTURE_URL" "$SCRIPT" install 2>&1)"
printf '%s' "$OUT" | grep -q "$FIXTURE_TOKEN"
check_eq 1 $? "install: значение токена не попадает в текстовый вывод"

# 27 (FR-31). uv отчитался успехом, но версия по-прежнему ниже минимальной → 11
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub_uv_installs 0.4.0
"$SCRIPT" install >/dev/null 2>&1; check_eq 11 $? "install: индекс отдал 0.4.0 → постусловие 11"
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub_uv_installs 0.4.0
OUT="$("$SCRIPT" install --json 2>/dev/null)"
printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
check_eq 0 $? "install --json: валидный JSON при постусловии 11"
printf '%s' "$OUT" | grep -q '"status":"outdated"'; check_eq 0 $? "install --json: статус outdated при постусловии 11"
printf '%s' "$OUT" | grep -q '"installed_version":"0.4.0"'; check_eq 0 $? "install --json: несёт installed_version"
printf '%s' "$OUT" | grep -q '"message":"'; check_eq 0 $? "install --json: несёт message"
printf '%s' "$OUT" | grep -q '"uv_output":"'; check_eq 0 $? "install --json: сохранил uv_output"

# 28 (FR-31, пересмотрено ADR-022 Д2/AC-7). Ремонт отчитался успехом («Already
# installed»), но версия не изменилась (переустановка того же артефакта/кеш) →
# постусловие обязано перечитать версию, а не доверять коду возврата менеджера
# пакетов. Verb-специфичный ассерт «upgrade» снят: ремонт теперь всегда зовёт
# install с явным пином (тест 22), «upgrade» этой веткой больше не вызывается.
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.4.0"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "%s/uv-args"\necho "Already installed"\nexit 0\n' \
  "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 11 $? "install: ремонт успешен, версия не изменилась → 11 (постусловие не доверяет коду возврата)"
grep -qx 'install' "$TMP/uv-args"; check_eq 0 $? "install: ветка обновления по-прежнему зовёт uv tool install, не upgrade"

# 29 (FR-31). успешная установка совместимой версии → 0 и статус ok
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub_uv_installs 0.10.0
OUT="$("$SCRIPT" install --json 2>/dev/null)"; check_eq 0 $? "install: индекс отдал 0.10.0 → 0"
printf '%s' "$OUT" | grep -q '"status":"ok"'; check_eq 0 $? "install --json: статус ok при успехе"
printf '%s' "$OUT" | grep -q '"installed_version":"0.10.0"'; check_eq 0 $? "install --json: installed_version при успехе"

# 30 (DEV-007 дефект 1). uv tool list подтверждает версию, но ktalk не резолвится через
# PATH (типовой случай ~/.local/bin не в PATH) — install не вправе молча сообщать успех;
# постусловие install обязано использовать тот же предикат, что check.
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub_uv_installs_off_path 0.10.0
OUT="$("$SCRIPT" install 2>&1)"; RC=$?
check_eq 10 "$RC" "install: ktalk вне PATH после установки → 10, не молчаливый успех"
printf '%s' "$OUT" | grep -qi 'path'; check_eq 0 $? "install: сообщение об ошибке называет PATH"
"$SCRIPT" check >/dev/null 2>&1; check_eq "$RC" $? "install→check: одинаковый предикат, одинаковый код"

# 31 (DEV-007 дефект 2). install --json несёт attempts/return_code/uv_output на исходах,
# где менеджер пакетов не запускался: без санкции (30), нет uv (12), нужна отдельная
# санкция на обновление (32), пакет уже свежий (0).
check_json_telemetry() { # check_json_telemetry <json> <expect_attempts> <название>
  printf '%s' "$1" | python3 -c '
import json, sys
obj = json.load(sys.stdin)
for k in ("attempts", "return_code", "uv_output"):
    assert k in obj, f"нет поля {k}"
assert obj["attempts"] == '"$2"', obj["attempts"]
assert obj["return_code"] is None, obj["return_code"]
assert obj["uv_output"] == "", obj["uv_output"]
' 2>/dev/null
  check_eq 0 $? "$3"
}

make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
OUT="$("$SCRIPT" install --json 2>/dev/null)"; check_eq 30 $? "install --json: без санкции → 30"
check_json_telemetry "$OUT" 0 "install --json: без санкции — телеметрия честная (менеджер не запускался)"

make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
OUT="$("$SCRIPT" install --json 2>/dev/null)"; check_eq 12 $? "install --json: нет uv → 12"
check_json_telemetry "$OUT" 0 "install --json: нет uv — телеметрия честная"

make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.4.0"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
OUT="$("$SCRIPT" install --json 2>/dev/null)"; check_eq 32 $? "install --json: устарел, нет allow_update → 32"
check_json_telemetry "$OUT" 0 "install --json: нет allow_update — телеметрия честная"

make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 0.10.0"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
OUT="$("$SCRIPT" install --json 2>/dev/null)"; check_eq 0 $? "install --json: уже свежий → 0"
check_json_telemetry "$OUT" 0 "install --json: уже свежий — телеметрия честная (uv не вызывался)"

### QA-001 (эпик ktalk-plugin-4nk, requirement 2026-08-31-cli-only-boundary) ###
# Стабы 32–41 покрывают 5 из 9 сценариев capability-спеки cli-only-boundary,
# закреплённых за деревом плагина (AC-5 .. AC-8 из
# openspec/specs/cli-only-boundary/spec.md; нумерация AC — по порядку
# `#### Scenario:` в спеке, детали — content/30-requirements/2026-08-31-cli-only-boundary/at-design.md).
# AC-1..AC-4 (extra fastmcp) и AC-9 (пред-релизный гейт) в этом дереве не
# реализуются — см. at-design.md, раздел «Внешние сценарии».
#
# Красные ДО Dev: 5 (изменена), 22 (изменена), 28 (изменена), 32, 33, 34, 35,
# 38, 40, 41. Тест 36 и 37 сегодня уже проходят как регресс-guard существующего
# fail-closed поведения — доказательство, что ассерт способен упасть, дано
# мутацией во внешнем отчёте QA-author (не в этом файле), см. at-design.md.
# Тест 39 — намеренная незелёная заглушка на решение Dev (не автопройдёт, пока
# Dev не заменит check_eq на реальную проверку выбранной нормализации).

# 32 (AC-7, ADR-022 Д2/Д3 — санкция под пином, "masked failure" guard).
# Установленная версия НОВЕЕ пина, allow_update не выдана → обязана требовать
# санкцию (32), а не молчаливый 0, как было при пороге (см. старый тест 5).
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 1.2.3"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 32 $? "install: версия НОВЕЕ пина без allow_update → 32, не молчаливый 0"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: версия новее пина без санкции — uv не вызывался"

# 33 (AC-7, симметрично тесту 22). Версия новее пина, allow_update выдана →
# ремонт откатывает на точный пин той же командой install==<пин> (downgrade —
# не «безобидное движение вперёд», ADR-022 Д2).
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-mcp 1.2.3"
stub_uv_installs 0.10.0 "Installed 1 executable: ktalk"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: версия новее пина, есть allow_update → откат на пин → 0"
grep -q '^ktalk-mcp==0\.10\.0$' "$TMP/uv-args"; check_eq 0 $? "install: команда отката называет пин явно — ktalk-mcp==0.10.0"

# 34 (AC-7/AC-8). check --json: расхождение «версия НИЖЕ пина» — команда
# ремонта в JSON называет пин явно, не голое имя пакета без версии.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.4.0"
OUT="$("$SCRIPT" check --json 2>/dev/null)"
printf '%s' "$OUT" | grep -q '"install_command":"[^"]*0\.10\.0[^"]*"'
check_eq 0 $? "check --json (версия ниже пина): install_command называет пин 0.10.0"
printf '%s' "$OUT" | grep -Eq '"install_command":"uv tool install ktalk-mcp"'
check_eq 1 $? "check --json (версия ниже пина): install_command — не голое имя пакета без версии"

# 35 (AC-7/AC-8). check --json: расхождение «версия ВЫШЕ пина» — та же
# гарантия, симметрично тесту 34.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp 1.2.3"
OUT="$("$SCRIPT" check --json 2>/dev/null)"
printf '%s' "$OUT" | grep -q '"install_command":"[^"]*0\.10\.0[^"]*"'
check_eq 0 $? "check --json (версия выше пина): install_command называет пин 0.10.0"

# 36 (AC-7, класс «malformed/mistyped input»). ktalk печатает нераспознаваемую
# версию (не semver, например билд-тег вместо релизной версии) — не крашится
# и не признаёт версию совместимой молча.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-mcp dev-build"
"$SCRIPT" check >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ]; check_eq 0 $? "check: нераспознаваемая версия строки — не молчаливый успех (код != 0)"
check_eq 11 "$RC" "check: нераспознаваемая версия трактуется как несовпадение с пином → 11"

# 37 (AC-7, класс «masked failure»). compat.json без ключа пина вовсе — явный
# отказ (20), а не тихий дефолт «любая версия подходит». Зеркало дерева, не
# правка реального compat.json репозитория (DEV-002 владеет этим файлом).
make_env
MIRROR="$TMP/mirror-empty"; mkdir -p "$MIRROR/scripts"
cp "$SCRIPT" "$MIRROR/scripts/ktalk-onboard.sh"
printf '{}' > "$MIRROR/compat.json"
stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.10.0"
"$MIRROR/scripts/ktalk-onboard.sh" check >/dev/null 2>&1
check_eq 20 $? "check: compat.json без ключа пина вовсе → явный отказ 20, не молчаливое ok"

# 38 (AC-7, класс «masked failure»). compat.json несёт только СТАРЫЙ ключ
# ktalk_mcp_min_version — после переименования на ktalk_mcp_version это то же
# самое «пина нет»: обязан явно отказать (20), а не молчаливо принять старый
# формат ключа. КРАСНЫЙ уже сегодня: текущий min_version() ещё читает старый
# ключ и вернёт 0 (совместимо), не 20.
make_env
MIRROR="$TMP/mirror-oldkey"; mkdir -p "$MIRROR/scripts"
cp "$SCRIPT" "$MIRROR/scripts/ktalk-onboard.sh"
printf '{\n  "ktalk_mcp_min_version": "0.10.0"\n}\n' > "$MIRROR/compat.json"
stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.10.0"
"$MIRROR/scripts/ktalk-onboard.sh" check >/dev/null 2>&1
check_eq 20 $? "check: только старый ключ ktalk_mcp_min_version после переименования → отказ 20, не молчаливое приятие старого формата"

# 39 (граница, поведение НЕ специфицировано требованием — companion-статья,
# раздел «Точка правки»: version_eq и pre-release/build-метаданные решает Dev).
# Это намеренная незелёная заглушка, не готовый ассерт: Dev обязан выбрать
# норму (0.10.0+local равно пину 0.10.0 или нет), закодировать её и заменить
# строку ниже на реальную проверку с обоснованием в комментарии.
check_eq "решение Dev, ADR-022 companion" "TODO" \
  "AC-7 граница: 0.10.0+local против пина 0.10.0 — нормализация не специфицирована требованием, замени эту строку решением Dev"

# 40 (AC-5, «masked failure» — регресс .mcp.json). Сегодня .mcp.json в корне
# репозитория ДЕКЛАРИРУЕТ ktalk как MCP-сервер, а check-plugin-composition.sh
# не заглядывает внутрь файла вовсе (пробел, найденный SA) — гейт обязан
# упасть на этом состоянии дерева. КРАСНЫЙ уже сегодня без всякой мутации:
# .mcp.json реальный, а проверки для него ещё нет.
OUT="$(bash "$ROOT/scripts/check-plugin-composition.sh" 2>&1)"; RC=$?
[ "$RC" -ne 0 ]; check_eq 0 $? "check-plugin-composition.sh: .mcp.json декларирует ktalk-MCP-сервер → гейт обязан упасть"
printf '%s' "$OUT" | grep -qi '\.mcp\.json'; check_eq 0 $? "check-plugin-composition.sh: сообщение об ошибке называет .mcp.json"

# 41 (AC-6, таблица «Retired MCP → CLI»). Оператор, вызывавший ретируемый
# MCP-инструмент напрямую, обязан найти в документации CLI-эквивалент — все
# три перечислены дословно. Проверка ведётся по CLI-командам (разрешённым к
# написанию), не по буквальным retired-именам двух инструментов предпросмотра
# встреч (они — запрещённые литералы дерева плагина, check-plugin-composition.sh).
DOC_HIT=0
for f in "$ROOT/README.md" "$ROOT/references/onboarding.md"; do
  [ -f "$f" ] || continue
  if grep -q 'ktalk create-meeting-preview' "$f" \
     && grep -q 'ktalk cancel-meeting-preview' "$f" \
     && grep -q 'ktalk get-summary-type' "$f"; then
    DOC_HIT=1
  fi
done
check_eq 1 "$DOC_HIT" "документация: таблица retired MCP → CLI перечисляет все три CLI-эквивалента в одном файле"

printf '\nPASS: %s  FAIL: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
