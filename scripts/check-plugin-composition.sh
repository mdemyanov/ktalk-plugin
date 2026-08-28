#!/usr/bin/env bash
# Статическая проверка состава плагина ktalk перед сборкой/публикацией
# (GO-критерий 3 постановки волны 3, ADR-012-spec: «Test-pyramid рекомендация»).
# Ищет по дереву плагина следы конкретного vault'а хозяина: жёстко зашитые
# каталоги раскладки, абсолютные пути, значения секретов, внутренний домен.
# Ненулевой код возврата при первой находке — вызывающая сторона (CI) считает
# это провалом сборки. Из обхода исключены только сам этот файл (он содержит
# паттерны поиска и иначе ловит сам себя) и `__pycache__/`: .pyc — компилированный
# артефакт тех же .py, что проверяются в исходной форме, а зашитый в нём /Users/ —
# путь компиляции, не состав плагина. По той же причине исключён `.beads/` —
# локальный стор `bd` (nauta), не отслеживаемый git и не входящий в состав
# поставляемого плагина: его служебный `repo_state.json` хранит абсолютный путь
# к рабочей копии, то есть свойство машины разработчика, а не текста плагина.
# Тем же основанием исключён `agent-memory/` (.claude/agent-memory — заметки
# субагентов о собственной работе): каталог локален, внесён в .gitignore и в
# поставку плагина не входит, а его записи цитируют пути и паттерны, которые
# проверка ищет. `scripts/` поставляется пользователю
# и обязан проверяться наравне с промтами (волна 4, DEV-005).
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

check() {
    local label="$1"
    local pattern="$2"
    local hits
    if hits=$(grep -rnE "$pattern" \
        --exclude-dir=.git \
        --exclude-dir=__pycache__ \
        --exclude-dir=.beads \
        --exclude-dir=agent-memory \
        --exclude=check-plugin-composition.sh \
        .); then
        echo "FAIL: $label"
        echo "$hits"
        fail=1
    fi
}

# Жёстко зашитые каталоги раскладки vault'а naumen-cto — должны приходить
# только из .ktalk.toml хозяина, не из текста плагина (ADR-012 §1, DEV-002).
check "жёстко зашитая раскладка vault'а" '95_TRANSCRIPTS|20_MEETINGS|10_PEOPLE|30_PROJECTS'

# Абсолютные пути домашнего каталога — плагин обязан быть переносим между
# проектами без правки (ADR-012 «Три дома», критерий «Плагин»).
check "абсолютный путь /Users/" '/Users/'

# Значение секрета рядом с именем переменной (не само упоминание имени —
# упоминание "истёк KTALK_SESSION_TOKEN" в диагностике легитимно, FR-25).
# Присваивание значения из переменной (KTALK_SESSION_TOKEN="$FIXTURE_TOKEN")
# литералом не является: необязательная кавычка съедается, а $ и { отсекаются.
check "секрет со значением" 'KTALK_(SESSION_TOKEN|PERSONAL_API_KEY|BASE_URL)\s*[:=]\s*"?[^[:space:]{$"]'

# Внутренний домен хозяина.
check "внутренний домен ktalk.ru" 'ktalk\.ru'

# MCP-имена операций встреч — промт-поверхность обязана называть только CLI-команды
# (ADR-012 §2а, ADR-015 «Решение» п.1: MCP заморожен для этой поверхности, FR-32…FR-36).
check "MCP-имя операции встреч вместо CLI" \
  'ktalk_list_calendar|ktalk_get_room|ktalk_search_contacts|ktalk_preview_meeting|ktalk_preview_cancel_meeting'

# ADR-016 §8: санкцию на запись выдаёт только человек в своём терминале. Навык
# печатает команду `ktalk sanction grant` как текст для оператора — это легитимно;
# нелегитимен её программный запуск. Проверка эвристическая (текст промта не
# исполняемый код, точного признака «вызов» в нём нет) и намеренно узкая: ловит
# подстановку в шелл и повелительное «выполни/запусти» рядом с командой. Обратные
# кавычки в паттерн не входят: в markdown это разметка кода, а не подстановка.
check "программный запуск sanction grant" \
  '\$\(.{0,40}sanction grant|sanction grant.{0,40}(&&|\|\|)|(выполни|запусти|execute)[^.]{0,60}sanction grant'

# Прежняя проверка «нет программного вызова *-confirm» снята сознательно: волна 6
# сделала такой вызов штатным путём (ADR-016 отменяет ADR-005 §3 и ADR-015 §2).

# NFR-25 (ADR-018 решение 7): правка промт-слоя анализа (agents/, skills/ktalk-registry/)
# без подъёма minor-версии в .claude-plugin/plugin.json — провал. AC NFR-25 требует
# буквально «minor-версия плагина поднята», не просто «файл изменился» и не любой рост —
# правка одного лишь description или patch-инкремент (1.2.1→1.2.2) не проходит: patch
# по семантике проекта — для правок вне промт-слоя (например, README), не для калибровки
# поведения агента. Мажорный рост (2.0.0) тоже проходит — он строго превосходит minor.
# Сравнение идёт с базой ветки (по умолчанию origin/main; переопределяется NFR25_BASE_REF)
# против ТЕКУЩЕГО рабочего дерева (не диапазон commit...HEAD) — гейт видит и незакоммиченную
# правку, актуально для pre-commit; в CI после коммита рабочее дерево совпадает с HEAD,
# эквивалентно. Если база недоступна — проверка пропускается с предупреждением, не падает
# (нет ложного FAIL на shallow clone или detached HEAD без origin).
check_prompt_version_sync() {
    local base_ref="${NFR25_BASE_REF:-origin/main}"

    if ! git rev-parse --verify --quiet "$base_ref" >/dev/null; then
        echo "SKIP: синхронизация версии промт-слоя (NFR-25) — база '$base_ref' недоступна"
        return 0
    fi

    local prompt_diff
    prompt_diff=$(git diff --name-only "$base_ref" -- agents/ skills/ktalk-registry/ 2>/dev/null || true)
    if [ -z "$prompt_diff" ]; then
        return 0
    fi

    local plugin_json=".claude-plugin/plugin.json"
    local base_version cur_version
    base_version=$(git show "${base_ref}:${plugin_json}" 2>/dev/null | grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    cur_version=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$plugin_json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)

    if [ -z "$base_version" ] || [ -z "$cur_version" ]; then
        echo "FAIL: не удалось прочитать version из $plugin_json (база: '$base_version', рабочее дерево: '$cur_version') — NFR-25 не проверен"
        fail=1
        return
    fi

    local base_major base_minor cur_major cur_minor
    IFS='.' read -r base_major base_minor _ <<< "$base_version"
    IFS='.' read -r cur_major cur_minor _ <<< "$cur_version"

    local minor_raised=0
    if [ "$cur_major" -gt "$base_major" ]; then
        minor_raised=1
    elif [ "$cur_major" -eq "$base_major" ] && [ "$cur_minor" -gt "$base_minor" ]; then
        minor_raised=1
    fi

    if [ "$minor_raised" -ne 1 ]; then
        echo "FAIL: правка промт-слоя без подъёма minor-версии в $plugin_json (NFR-25)"
        echo "  version в базе ($base_ref): $base_version"
        echo "  version в рабочем дереве:  $cur_version"
        echo "Изменённые файлы промт-слоя (относительно $base_ref):"
        echo "$prompt_diff"
        fail=1
    fi
}

check_prompt_version_sync

# ADR-021 Д6 (capability `prompt-language-boundary`): языковая граница промт-слоя —
# блокирующий гейт, и живёт он здесь, а не в scripts/check.sh: тот доставляется плагином
# nauta и заморожен по sha256 в .nauta-scripts-basis.yaml, правка увела бы дерево в дрейф
# поставки. Скрипт печатает собственную диагностику; здесь достаточно кода возврата.
if ! bash scripts/check-prompt-language.sh; then
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo
    echo "Проверка состава плагина: FAIL"
    exit 1
fi

echo "Проверка состава плагина: OK"
exit 0
