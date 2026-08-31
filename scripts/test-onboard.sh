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
printf '#!/usr/bin/env bash\\nprintf "ktalk-cli $1\\\\n"\\n' > "$TMP/bin/ktalk"
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
  printf 'ktalk-cli v$1\\n'
  exit 0
fi
printf '%s\\n' "\$@" >> "$TMP/uv-args"
printf '#!/usr/bin/env bash\\nprintf "ktalk-cli $1\\\\n"\\n' > "$TMP/offpath/ktalk"
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
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 0.4.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 11 $? "check: 0.4.0 < 1.0.0 → 11"

# 3a. 0.9.2 ниже 0.10.0 — сравнение посегментно-числовое, не лексикографическое
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 0.9.2"
"$SCRIPT" check >/dev/null 2>&1; check_eq 11 $? "check: 0.9.2 < 1.0.0 → 11"

# 4. версия достаточна → 0
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 1.0.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 0 $? "check: 1.0.0 → 0"

# 5 (AC-7, ADR-022 Д3 — пин симметричен, не порог). Версия ВЫШЕ пина тоже
# несовместима: «новее» перестаёт быть безусловным OK, как было при пороге.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 1.2.3"
"$SCRIPT" check >/dev/null 2>&1; check_eq 11 $? "check: 1.2.3 (новее пина 1.0.0) → 11, не молчаливый 0"

# 6. --version не поддержан, версия берётся из uv tool list
make_env
printf '#!/usr/bin/env bash\nexit 2\n' > "$TMP/bin/ktalk"; chmod +x "$TMP/bin/ktalk"
stub uv 0 "ktalk-cli v1.0.0"
"$SCRIPT" check >/dev/null 2>&1; check_eq 0 $? "check: fallback на uv tool list"

# 7. --json печатает валидный JSON
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 1.0.0"
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
stub_uv_installs 1.0.0
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: с санкцией → 0"

# 16. пакет уже свежий → 0 и uv не вызывался (идемпотентность)
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-cli 1.0.0"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: уже установлен → 0"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: уже установлен — uv не вызывался"

# 17. устаревшая версия без санкции на обновление → 32
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-cli 0.4.0"
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
stub ktalk 0 "ktalk-cli 0.4.0"
stub_uv_installs 1.0.0 "Installed 1 executable: ktalk"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: устарел, есть allow_update → 0"
grep -qx 'install' "$TMP/uv-args"; check_eq 0 $? "install: ремонт зовёт uv tool install, не upgrade (AC-8)"
grep -q '^ktalk-cli==1\.0\.0$' "$TMP/uv-args"; check_eq 0 $? "install: аргумент называет пин явно — ktalk-cli==1.0.0 (AC-8)"

# 23. install --json на успехе → валидный JSON
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub_uv_installs 1.0.0
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
stub ktalk 0 "ktalk-cli 0.4.0"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "%s/uv-args"\necho "Already installed"\nexit 0\n' \
  "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 11 $? "install: ремонт успешен, версия не изменилась → 11 (постусловие не доверяет коду возврата)"
grep -qx 'install' "$TMP/uv-args"; check_eq 0 $? "install: ветка обновления по-прежнему зовёт uv tool install, не upgrade"

# 29 (FR-31). успешная установка совместимой версии → 0 и статус ok
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub_uv_installs 1.0.0
OUT="$("$SCRIPT" install --json 2>/dev/null)"; check_eq 0 $? "install: индекс отдал 0.10.0 → 0"
printf '%s' "$OUT" | grep -q '"status":"ok"'; check_eq 0 $? "install --json: статус ok при успехе"
printf '%s' "$OUT" | grep -q '"installed_version":"1.0.0"'; check_eq 0 $? "install --json: installed_version при успехе"

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
stub ktalk 0 "ktalk-cli 0.4.0"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
OUT="$("$SCRIPT" install --json 2>/dev/null)"; check_eq 32 $? "install --json: устарел, нет allow_update → 32"
check_json_telemetry "$OUT" 0 "install --json: нет allow_update — телеметрия честная"

make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-cli 1.0.0"
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
stub ktalk 0 "ktalk-cli 1.2.3"
printf '#!/usr/bin/env bash\ntouch "%s/uv-was-called"\nexit 0\n' "$TMP" > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
"$SCRIPT" install >/dev/null 2>&1; check_eq 32 $? "install: версия НОВЕЕ пина без allow_update → 32, не молчаливый 0"
[ -f "$TMP/uv-was-called" ]; check_eq 1 $? "install: версия новее пина без санкции — uv не вызывался"

# 33 (AC-7, симметрично тесту 22). Версия новее пина, allow_update выдана →
# ремонт откатывает на точный пин той же командой install==<пин> (downgrade —
# не «безобидное движение вперёд», ADR-022 Д2).
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
stub ktalk 0 "ktalk-cli 1.2.3"
stub_uv_installs 1.0.0 "Installed 1 executable: ktalk"
"$SCRIPT" install >/dev/null 2>&1; check_eq 0 $? "install: версия новее пина, есть allow_update → откат на пин → 0"
grep -q '^ktalk-cli==1\.0\.0$' "$TMP/uv-args"; check_eq 0 $? "install: команда отката называет пин явно — ktalk-cli==1.0.0"

# 34 (AC-7/AC-8). check --json: расхождение «версия НИЖЕ пина» — команда
# ремонта в JSON называет пин явно, не голое имя пакета без версии.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 0.4.0"
OUT="$("$SCRIPT" check --json 2>/dev/null)"
printf '%s' "$OUT" | grep -q '"install_command":"[^"]*1\.0\.0[^"]*"'
check_eq 0 $? "check --json (версия ниже пина): install_command называет пин 1.0.0"
printf '%s' "$OUT" | grep -Eq '"install_command":"uv tool install ktalk-cli"'
check_eq 1 $? "check --json (версия ниже пина): install_command — не голое имя пакета без версии"

# 35 (AC-7/AC-8). check --json: расхождение «версия ВЫШЕ пина» — та же
# гарантия, симметрично тесту 34.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 1.2.3"
OUT="$("$SCRIPT" check --json 2>/dev/null)"
printf '%s' "$OUT" | grep -q '"install_command":"[^"]*1\.0\.0[^"]*"'
check_eq 0 $? "check --json (версия выше пина): install_command называет пин 1.0.0"

# 36 (AC-7, класс «malformed/mistyped input»). ktalk печатает нераспознаваемую
# версию (не semver, например билд-тег вместо релизной версии) — не крашится
# и не признаёт версию совместимой молча.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli dev-build"
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
# Решение Dev (обоснование — комментарий над version_eq в ktalk-onboard.sh):
# билд-метаданные (+xyz) игнорируются при сравнении (semver §10 — они не
# участвуют в precedence), пре-релизные идентификаторы (-rc1…) — нет, версия
# с пре-релизом не равна пину. Вызывается сама функция напрямую (source в
# отдельном процессе), а не через check/install: installed_version() и так
# вырезает суффикс регэкспом до сравнения — граница проверяема только на
# уровне version_eq, не через CLI-обёртку.
VEQ_BUILD="$(bash -c "source '$SCRIPT' >/dev/null 2>&1; version_eq '0.10.0+local' '0.10.0'; echo \$?" 2>/dev/null | tail -1)"
check_eq 0 "$VEQ_BUILD" \
  "version_eq: билд-метаданные игнорируются — 0.10.0+local равно пину 0.10.0 (semver §10)"

VEQ_PRERELEASE="$(bash -c "source '$SCRIPT' >/dev/null 2>&1; version_eq '0.10.0-rc1' '0.10.0'; echo \$?" 2>/dev/null | tail -1)"
check_eq 1 "$VEQ_PRERELEASE" \
  "version_eq: пре-релизный идентификатор значим — 0.10.0-rc1 НЕ равно пину 0.10.0"

# 40 (AC-5, ПЕРЕСМОТРЕНО после DEV-002 — поручение координатора, QA-001).
# Прежние два ассерта прогоняли check-plugin-composition.sh на РЕАЛЬНОМ $ROOT и
# требовали RC != 0 — верно, только пока .mcp.json существовал и декларировал
# ktalk. Это были строительные леса «красный до Dev» (мутация лежала в самом
# дереве, не была специально устроена), а не постоянный контракт: AC-5 спеки
# («SHALL declare no MCP server») и companion-статья («Удаление .mcp.json»:
# «Файл удаляется целиком») требуют, чтобы .mcp.json в дереве не было вовсе —
# после DEV-002 так и есть, и прежнее «RC != 0 на живом дереве» стало
# противоречить самому свойству, которое тест обязан защищать. Ретированы.
#
# Свойство «оба направления регресса ловятся» не потеряно — покрыто регресс-
# тестом ниже на изолированной копии дерева (тот же приём, что тесты 37/38):
# файл с ktalk в mcpServers → гейт падает и называет файл; файла нет → гейт
# проходит. Проверено чтением реализации check_no_mcp_server()
# (scripts/check-plugin-composition.sh) перед тем, как полагаться на неё здесь.
#
# Взамен ретированных ассертов — прямая проверка постоянного состояния живого
# дерева: .mcp.json в корне отсутствует. Это наблюдаемое свойство AC-5, а не
# деталь реализации гейта — регресс «файл вернули» обязан ловиться и на живом
# дереве, не только на изолированной копии.
[ ! -e "$ROOT/.mcp.json" ]; check_eq 0 $? "живое дерево: .mcp.json отсутствует (AC-5 — плагин не объявляет MCP-сервер)"
MIRROR40="$TMP/mirror-mcp-regress"; cp -r "$ROOT" "$MIRROR40"; rm -rf "$MIRROR40/.git"
cat > "$MIRROR40/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "ktalk": {
      "type": "stdio",
      "command": "ktalk-mcp"
    }
  }
}
JSON
OUT40="$(bash "$MIRROR40/scripts/check-plugin-composition.sh" 2>&1)"; RC40=$?
[ "$RC40" -ne 0 ]; check_eq 0 $? "check-plugin-composition.sh (регресс на копии дерева): .mcp.json с ktalk в mcpServers → гейт падает"
printf '%s' "$OUT40" | grep -qi '\.mcp\.json'; check_eq 0 $? "check-plugin-composition.sh (регресс на копии дерева): сообщение называет .mcp.json"
rm -f "$MIRROR40/.mcp.json"
OUT40b="$(bash "$MIRROR40/scripts/check-plugin-composition.sh" 2>&1)"; RC40b=$?
check_eq 0 "$RC40b" "check-plugin-composition.sh (регресс на копии дерева): .mcp.json отсутствует → гейт проходит"

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

### QA-001, раунд доработки — 5 дефектов code review, пропущенных прежней сьютой ###
# Находки 1 и 5 обязаны идти через РЕАЛЬНЫЙ путь (cmd_check/cmd_install), не
# прямым вызовом version_eq() — именно обход реального пути спрятал оба
# дефекта в предыдущем раунде (тест 39 звал version_eq() напрямую).

# 42 (находка 1 — пре-релизная гарантия отсутствует на реальном пути, AC-7).
# installed_version() режет `ktalk --version` регуляркой [0-9]+\.[0-9]+\.[0-9]+
# и теряет пре-релизный суффикс ДО того, как строка попадает в version_eq —
# сравнение видит уже урезанное «0.10.0», не «0.10.0rc1»/«0.10.0-rc1», и
# признаёт rc-сборку равной пину. Обе типографии из репро координатора.
make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 1.0.0rc1"
"$SCRIPT" check >/dev/null 2>&1
check_eq 11 $? "check (реальный путь): установлена пре-релизная 0.10.0rc1 — код 11, не молчаливый 0 (installed_version теряет rc-суффикс)"

make_env; stub uv 0 ""; stub ktalk 0 "ktalk-cli 1.0.0-rc1"
"$SCRIPT" check >/dev/null 2>&1
check_eq 11 $? "check (реальный путь): установлена пре-релизная 0.10.0-rc1 — код 11, не молчаливый 0 (installed_version теряет rc-суффикс)"

# 43 (находка 5 — билд-метаданные с дефисом читаются как пре-релиз, AC-7).
# version_eq(): `case "$1" in *-*)` смотрит на дефис ВО ВСЕЙ строке, а не в
# части до "+" — билд-метаданные вида "+build-1" ошибочно принимаются за
# пре-релиз "build-1" (semver §10 требует игнорировать билд-метаданные
# целиком, независимо от её собственного содержимого). Тест 39 покрывал
# только "+local" (без дефиса внутри) и не ловил этот случай. Реальный путь,
# которым это достижимо, — значение ПИНА в compat.json: оно приходит в
# version_eq сырым, без regex-фильтра (в отличие от installed_version()).
# Зеркало дерева, как в тестах 37/38 — не правка реального compat.json.
make_env
MIRROR43="$TMP/mirror-build-meta"; mkdir -p "$MIRROR43/scripts"
cp "$SCRIPT" "$MIRROR43/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "0.10.0+build-1"\n}\n' > "$MIRROR43/compat.json"
stub uv 0 ""; stub ktalk 0 "ktalk-cli 0.10.0"
"$MIRROR43/scripts/ktalk-onboard.sh" check >/dev/null 2>&1
check_eq 0 $? "check (реальный путь, пин с билд-метаданными 0.10.0+build-1): semver §10 — билд-метаданные игнорируются целиком, версии равны, код 0, не 11"

# 44 (находка 2 — гейт состава проверяет меньше, чем требует AC-5). Спека:
# «SHALL declare no MCP server for the ktalk circuit» — без оговорок про имя
# файла и имя ключа. check_no_mcp_server() смотрит только на файл .mcp.json
# и только на ключ, буквально совпадающий с "ktalk".

# 44a: тот же сервер контура ktalk (команда ktalk-mcp) под ключом, не равным
# буквально "ktalk", — гейт обязан заметить по команде/факту декларации, а
# не только по точному имени ключа.
MIRROR44A="$TMP/mirror-mcp-keyname"; cp -r "$ROOT" "$MIRROR44A"; rm -rf "$MIRROR44A/.git"
cat > "$MIRROR44A/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "ktalk-mcp": {
      "type": "stdio",
      "command": "ktalk-mcp"
    }
  }
}
JSON
bash "$MIRROR44A/scripts/check-plugin-composition.sh" >/dev/null 2>&1
check_eq 1 $? "check-plugin-composition.sh: MCP-сервер контура ktalk под ключом \"ktalk-mcp\" (не буквально \"ktalk\") тоже обязан провалить гейт"

# 44b: та же декларация лежит не в .mcp.json, а в другом файле состава
# плагина (marketplace.json) — check_no_mcp_server() читает только .mcp.json.
MIRROR44B="$TMP/mirror-mcp-otherfile"; cp -r "$ROOT" "$MIRROR44B"; rm -rf "$MIRROR44B/.git"
python3 - "$MIRROR44B/.claude-plugin/marketplace.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["mcpServers"] = {"ktalk": {"type": "stdio", "command": "ktalk-mcp"}}
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
bash "$MIRROR44B/scripts/check-plugin-composition.sh" >/dev/null 2>&1
check_eq 1 $? "check-plugin-composition.sh: MCP-сервер контура ktalk, объявленный в marketplace.json (не .mcp.json), тоже обязан провалить гейт"

# 45 (находка 3 — README рассинхронизируется с пином). Ранбук подъёма пина
# правит только compat.json; README жёстко называет версию в команде
# установки. Сегодня оба значения совпадают (0.10.0) — этот ассерт ЗЕЛЁНЫЙ на
# неизменённом дереве, и это не пропуск дефекта: сам дефект — отсутствие
# автоматической связи между файлами, а не расхождение значений сегодня.
# Мутационное доказательство приложено в отчёте QA-author, не в составе
# стаба: подъём пина в изолированной копии compat.json без правки README
# переводит этот же ассерт в красное.
PIN="$(grep -Eo '"package_version"[[:space:]]*:[[:space:]]*"[^"]+"' "$ROOT/compat.json" | grep -Eo '[0-9][^"]*')"
[ -n "$PIN" ]; check_eq 0 $? "compat.json: значение package_version читается"
PKG="$(grep -Eo '"package_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$ROOT/compat.json" | sed -E 's/.*"([^"]+)"$/\1/')"
[ -n "$PKG" ]; check_eq 0 $? "compat.json: значение package_name читается"
grep -q "$PKG==$PIN" "$ROOT/README.md"
check_eq 0 $? "README.md: команда установки называет тот же пакет и версию, что пин compat.json (сейчас $PKG==$PIN) — регресс-guard на будущий подъём/переименование пина"

# 46 (находка 6 — промт-слой противоречит собственному _meta.md). _meta.md
# навыка ktalk-registry объявляет MCP-поверхность контура ktalk снятой
# (".mcp.json removed"), но SKILL.md и agent-промт всё ещё описывают её как
# живой канал для сравнения/альтернативу. Проверка целится в описание
# СОБСТВЕННОГО MCP-сервера контура ktalk — упоминания стороннего инструмента
# `qmd` (skills/ktalk-registry/SKILL.md:152, agents/ktalk-processor.md:107)
# вне области этой находки и не затрагиваются.
grep -q "not MCP" "$ROOT/skills/ktalk-registry/SKILL.md"
check_eq 1 $? "SKILL.md: формулировка «primary call channel, not MCP» подразумевает MCP живой альтернативой — обязана уйти вместе со снятием MCP-поверхности (ADR-022 Д1, _meta.md)"

grep -qF '`ktalk_get_transcript` MCP tool' "$ROOT/agents/ktalk-processor.md"
check_eq 1 $? "ktalk-processor.md: контракт описан как «тот же, что у MCP tool ktalk_get_transcript» — ретированный инструмент контура ktalk назван в настоящем времени, будто ещё существует"

### QA-001 (эпик ktalk-plugin-foz, requirement 2026-08-31-package-rename-transition) ###
# Стабы 47–56 покрывают 7 сценариев capability-спеки package-rename-transition
# (нумерация AC — по порядку `#### Scenario:` в спеке; детали, класс каждого
# ассерта и дев-хинты — content/30-requirements/2026-08-31-package-rename-transition/
# at-design.md). AC-2 (пред-релизный гейт публикации) и AC-7 (санкция владельца на
# публикацию) в этом файле не покрыты — процедурные шаги релизного пайплайна без
# исполнимой поверхности в скрипте онбординга, закрыты чек-листом рансбука
# DevOps (см. at-design.md, «Не покрыто исполнимым стабом»), тем же приёмом, что
# AC-9 предыдущего требования cli-only-boundary.
#
# Красные ДО Dev: 48, 49, 50, 51, 52, 53, 55, 56 (новая схема compat.json,
# installed_identity(), новые коды E_WRONG_PACKAGE=13/E_SLOT_COLLISION=34 ещё не
# существуют — все обращения к новой схеме отказывают явным образом compat.json
# без нужных ключей, E_INTERNAL=20, что и ловят ассерты ниже). Тест 47 и 54
# сегодня уже проходят как регресс-guard (тот же приём, что тесты 36/45/46
# предыдущего раунда) — мутационное доказательство в отчёте QA-author, не в
# составе стаба.

# 47 (AC-1 — «Prompt-layer text is unaffected by the rename», Scenario 1).
# Механическая, не «на глаз», проверка: sha256-снимок ВСЕГО содержимого
# skills/+agents/+commands/ (99 вызовов `ktalk` в 10 файлах, ADR-024 companion
# §Boundaries), снятый до начала переименования пакета (2026-09-01). Снимок
# сильнее диффа одного коммита — ловит дрейф за весь эпик, не только за
# последний шаг. Зелёный сегодня (ничего ещё не менялось) — тот же приём, что
# тест 45 уже применяет к README/compat.json; мутационное доказательство
# (temp-правка одного символа в файле любого из трёх каталогов переводит
# ассерт в красное) приложено в отчёте QA-author, не в составе стаба.
EXPECTED_PROMPT_LAYER_SHA256="658d4111b1c317b28a905a449378349783bc95848267f557e3c815118b26213d"
ACTUAL_PROMPT_LAYER_SHA256="$(cd "$ROOT" && find skills agents commands -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | awk '{print $1}')"
check_eq "$EXPECTED_PROMPT_LAYER_SHA256" "$ACTUAL_PROMPT_LAYER_SHA256" \
  "AC-1: содержимое skills/+agents/+commands/ не изменилось со снимка — переименование пакета обязано остаться диффом из 6 названных файлов, не промт-слоя"

# 48 (AC-3 — wrong_package отличим от outdated по коду возврата, ADR-024 Д1/Д2,
# outcome#3 брифа). Зеркало с НОВОЙ схемой compat.json (package_name/
# package_version) и стабом ktalk --version, печатающим ЧУЖОЕ имя дистрибутива
# С ТЕМ ЖЕ номером версии, что и пин — ловит именно класс дефекта «сравнили
# только цифры, имя проигнорировали»: если бы check сравнивал только версию,
# это состояние прошло бы как ok (версии совпадают буквально).
make_env
MIRROR48="$TMP/mirror-wrong-package"; mkdir -p "$MIRROR48/scripts"
cp "$SCRIPT" "$MIRROR48/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR48/compat.json"
stub uv 0 ""; stub ktalk 0 "ktalk-mcp 1.0.0"
OUT48="$("$MIRROR48/scripts/ktalk-onboard.sh" check --json 2>&1)"; RC48=$?
check_eq 13 "$RC48" "AC-3: имя не совпадает с пином при СОВПАДАЮЩЕЙ версии → код 13 (wrong_package), не 0 и не 11 (outdated)"
printf '%s' "$OUT48" | grep -q '"status":"wrong_package"'
check_eq 0 $? "AC-3: --json называет статус именно wrong_package, не generic outdated/error"

# 49 (AC-3, граница — имя совпадает с пином, версия отличается → outdated
# по-прежнему 11 под НОВОЙ схемой полей). Регресс-guard: сравнение имени не
# должно перехватывать путь, который раньше (единственное поле пина) уже
# корректно вёл в outdated.
make_env
MIRROR49="$TMP/mirror-outdated-newschema"; mkdir -p "$MIRROR49/scripts"
cp "$SCRIPT" "$MIRROR49/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR49/compat.json"
stub uv 0 ""; stub ktalk 0 "ktalk-cli 0.9.0"
"$MIRROR49/scripts/ktalk-onboard.sh" check >/dev/null 2>&1
check_eq 11 $? "AC-3: имя совпадает с пином, версия ниже → 11 (outdated), не 13 — сравнение имени не должно перехватывать этот путь"

# 50 (AC-3, класс «malformed/mistyped input» — нераспознанный первый токен
# идентичности + диагностика registered_both, companion-статья «Edge cases»).
# ktalk --version печатает искажённую строку идентичности (не имя из
# известного списка) — резервный путь грепает uv tool list по ОБОИМ известным
# именам; если совпали обе строки, это диагностический признак
# registered_both в JSON, а не отдельный статус отказа установки (companion,
# Data flow п.2). Итоговый статус ПРИ ЭТОМ обязан остаться явным (не 0/ok) —
# нераспознанная идентичность сама по себе не подтверждает совместимость.
make_env
MIRROR50="$TMP/mirror-registered-both"; mkdir -p "$MIRROR50/scripts"
cp "$SCRIPT" "$MIRROR50/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR50/compat.json"
stub ktalk 0 "mystery-pkg 9.9.9"
cat > "$TMP/bin/uv" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tool" ] && [ "$2" = "list" ]; then
  printf 'ktalk-mcp v0.10.0\nktalk-cli v1.0.0\n'
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/uv"
OUT50="$("$MIRROR50/scripts/ktalk-onboard.sh" check --json 2>&1)"
printf '%s' "$OUT50" | grep -q '"registered_both":true'
check_eq 0 $? "AC-3: оба известных имени видны в uv tool list при нераспознанной идентичности → диагностический признак registered_both в --json"
printf '%s' "$OUT50" | grep -q '"status":"ok"'
check_eq 1 $? "AC-3: нераспознанная идентичность + registered_both НЕ является молчаливым ok — статус обязан остаться явным отказом"

# 51 (AC-4 — коллизия слота отличима от install_failed, никогда не решается
# автоматическим --force, outcome#4 брифа). uv отказывает РЕАЛЬНЫМ кодом 2 и
# текстом «Executable already exists», замеренным BA на синтетических
# пакетах — скрипт обязан распознать этот конкретный отказ как slot_collision
# (34), не общий install_failed (31), и НИКОГДА не повторить попытку с
# --force, включая путь с санкцией на обновление (allow_update), не только
# allow_install.
make_env; mkdir -p "$XDG_CONFIG_HOME/ktalk"
printf 'allow_install = true\nallow_update = true\n' > "$XDG_CONFIG_HOME/ktalk/onboarding.toml"
MIRROR51="$TMP/mirror-slot-collision"; mkdir -p "$MIRROR51/scripts"
cp "$SCRIPT" "$MIRROR51/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR51/compat.json"
cat > "$TMP/bin/uv" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$@" >> "$TMP/uv-args"
echo "error: Executable already exists: ktalk (use --force to overwrite)" >&2
exit 2
EOF
chmod +x "$TMP/bin/uv"
OUT51="$("$MIRROR51/scripts/ktalk-onboard.sh" install --json 2>&1)"; RC51=$?
check_eq 34 "$RC51" "AC-4: uv отказывает кодом 2 + «Executable already exists» → скрипт репортит 34 (slot_collision), не 31 (install_failed)"
printf '%s' "$OUT51" | grep -q '"status":"slot_collision"'
check_eq 0 $? "AC-4: --json называет статус именно slot_collision"
grep -qF -- '--force' "$TMP/uv-args"
check_eq 1 $? "AC-4: скрипт НИ РАЗУ не передал --force в uv, включая путь с санкцией allow_update — принудительная замена остаётся ручным действием оператора"

# 52 (AC-5 — перехваченный слот оставляет диагностируемый след, называя
# КОНКРЕТНОЕ активное имя, не только факт несовпадения, outcome брифа
# «оператор/скрипт видит, что реально исполняется»). Симулирует состояние
# ПОСЛЕ ручного --force: ktalk теперь называет ДРУГОЙ пакет, не тот, что
# пинует compat.json. cmd_check обязан назвать оба имени в сообщении/JSON —
# не «несовместимо», а «активен ktalk-mcp, пин требует ktalk-cli».
make_env
MIRROR52="$TMP/mirror-overridden-takeover"; mkdir -p "$MIRROR52/scripts"
cp "$SCRIPT" "$MIRROR52/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR52/compat.json"
stub uv 0 ""; stub ktalk 0 "ktalk-mcp 0.10.0"
OUT52="$("$MIRROR52/scripts/ktalk-onboard.sh" check --json 2>&1)"
printf '%s' "$OUT52" | grep -q 'ktalk-mcp'
check_eq 0 $? "AC-5: диагностика называет РЕАЛЬНО активное имя (ktalk-mcp), не только факт несовпадения"
printf '%s' "$OUT52" | grep -q 'ktalk-cli'
check_eq 0 $? "AC-5: диагностика называет и целевой пин (ktalk-cli) рядом с активным именем — оператору видно обе стороны расхождения"
# Дополнено координатором после мутационной проверки QA-002: два ассерта выше
# грепают ИМЕНА в выводе и остаются зелёными при сломанном identity_eq — оба
# имени попадают в JSON и когда статус ошибочно `ok`. Статус обязан проверяться
# отдельно, иначе тест защищает форму сообщения, а не сам вердикт.
"$MIRROR52/scripts/ktalk-onboard.sh" check --json >/dev/null 2>&1
check_eq 13 $? "AC-5: вердикт именно wrong_package (13), а не ok — тест защищает решение, не только формулировку"

# 53 (AC-6 — неверный порядок отката оставляет команду недиагностируемо
# сломанной, outcome#5 брифа: «Проверь, что стаб ловит именно неверный
# порядок, а не только конечное состояние»). Неверный порядок ADR-024 Д4 —
# сначала `uv tool uninstall` активного пакета, ПОТОМ (или никогда) установка
# целевого — воспроизводимо даёт код 127 у самого оператора (замер BA,
# наблюдение 3). Симулирует именно ЭТОТ промежуточный момент: команда ktalk
# уже не резолвится (бинарник стёрт), а uv tool list ПРОДОЛЖАЕТ числить снятый
# пакет владельцем — cmd_check обязан вернуть missing_cli (10), а не
# «совместим» на основании списка, который уже недостоверен (companion, Data
# flow п.6).
make_env
MIRROR53="$TMP/mirror-wrong-rollback-order"; mkdir -p "$MIRROR53/scripts"
cp "$SCRIPT" "$MIRROR53/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR53/compat.json"
stub uv 0 ""  # command -v uv резолвится
cat > "$TMP/bin/uv" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tool" ] && [ "$2" = "list" ]; then
  printf 'ktalk-mcp v0.10.0\n'
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/uv"
rm -f "$TMP/bin/ktalk"  # ktalk НЕ существует вовсе — бинарник уже стёрт uninstall'ом
"$MIRROR53/scripts/ktalk-onboard.sh" check >/dev/null 2>&1
check_eq 10 $? "AC-6: неверный порядок отката (uninstall раньше reinstall) → command -v ktalk не резолвится → 10 (missing_cli), не «совместим» по устаревшему uv tool list"

# 54 (AC-6/Д4 — верный порядок отката подтверждается ЖИВЫМ разрешением, не
# устаревшим uv tool list). Симулирует состояние ПОСЛЕ шага 1 схемы отката
# (принудительная переустановка целевой идентичности) и ДО шага 3 (снятие
# зависшей регистрации) — ktalk уже реально называет целевой пакет, но
# uv tool list ещё числит старый как «установленный» (шаг 3 не выполнен).
# check обязан подтвердить ok по живому разрешению, а не откатиться к
# устаревшему списку (companion, Data flow п.6 / Схема отката, шаг 2).
make_env
MIRROR54="$TMP/mirror-correct-rollback-order"; mkdir -p "$MIRROR54/scripts"
cp "$SCRIPT" "$MIRROR54/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "ktalk-cli",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR54/compat.json"
stub ktalk 0 "ktalk-cli 1.0.0"
cat > "$TMP/bin/uv" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tool" ] && [ "$2" = "list" ]; then
  printf 'ktalk-mcp v0.10.0\n'
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/uv"
"$MIRROR54/scripts/ktalk-onboard.sh" check >/dev/null 2>&1
check_eq 0 $? "AC-6: верный порядок отката — живое разрешение (ktalk --version) подтверждает целевой пакет, даже пока uv tool list ещё числит старый — check не откатывается к списку"

# 55 (outcome#2 брифа — идентичность параметризована, не литерал; ловит
# именно ловушку SA, не «имя стало ktalk-cli»). Зеркало с ПРОИЗВОЛЬНЫМ, не
# встречающимся в реальности именем пакета в compat.json — если ремонт
# называет ИМЕННО это имя, pin_name() реально читает файл; если ремонт
# продолжает называть «ktalk-mcp»/«ktalk-cli» текстом — тот же класс дефекта,
# что уже ударил версию в 0.8.0 (companion, «Точка правки: литералы»).
make_env
MIRROR55="$TMP/mirror-arbitrary-pkg-name"; mkdir -p "$MIRROR55/scripts"
cp "$SCRIPT" "$MIRROR55/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "zz-not-a-real-package-name",\n  "package_version": "42.0.0"\n}\n' > "$MIRROR55/compat.json"
stub uv 0 ""
rm -f "$TMP/bin/ktalk"
OUT55="$("$MIRROR55/scripts/ktalk-onboard.sh" check --json 2>&1)"
printf '%s' "$OUT55" | grep -q 'zz-not-a-real-package-name==42.0.0'
check_eq 0 $? "outcome#2: команда ремонта называет пин произвольным именем из compat.json (pin_name параметризован), не хардкод-литералом ktalk-mcp/ktalk-cli"

# 56 (AC-3, класс «malformed/mistyped input» — не отсутствие поля, а ИСКАЖЁННОЕ
# значение: package_name присутствует, но пуст). Оба поля схемы обязательны
# ОДНОВРЕМЕННО (companion, «Синтаксис пина») — пустая строка не то же самое,
# что отсутствующий ключ (тесты 37/38 уже покрывают полное отсутствие); пустое
# имя не должно молчаливо трактоваться как «подходит любому» или ронять скрипт
# необработанной ошибкой — явный отказ 20, тот же fail-closed приём.
make_env
MIRROR56="$TMP/mirror-empty-package-name"; mkdir -p "$MIRROR56/scripts"
cp "$SCRIPT" "$MIRROR56/scripts/ktalk-onboard.sh"
printf '{\n  "package_name": "",\n  "package_version": "1.0.0"\n}\n' > "$MIRROR56/compat.json"
stub uv 0 ""; stub ktalk 0 "ktalk-cli 1.0.0"
"$MIRROR56/scripts/ktalk-onboard.sh" check >/dev/null 2>&1
check_eq 20 $? "AC-3: package_name — пустая строка (искажённое, не отсутствующее значение) → явный отказ 20, не молчаливое ok/совпадение с любым именем"

printf '\nPASS: %s  FAIL: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
