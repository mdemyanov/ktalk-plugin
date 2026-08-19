#!/usr/bin/env bash
# Статическая проверка состава плагина ktalk перед сборкой/публикацией
# (GO-критерий 3 постановки волны 3, ADR-012-spec: «Test-pyramid рекомендация»).
# Ищет по дереву плагина следы конкретного vault'а хозяина: жёстко зашитые
# каталоги раскладки, абсолютные пути, значения секретов, внутренний домен.
# Ненулевой код возврата при первой находке — вызывающая сторона (CI) считает
# это провалом сборки. Из обхода исключён только сам этот файл (он содержит
# паттерны поиска и иначе ловит сам себя): `scripts/` поставляется пользователю
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
# без синхронного подъёма version в .claude-plugin/plugin.json — провал. Сравнение идёт
# с базой ветки (по умолчанию origin/main; переопределяется NFR25_BASE_REF — например,
# для локального прогона без доступа к origin) против ТЕКУЩЕГО рабочего дерева (двухточечный
# diff, не диапазон commit...HEAD) — гейт видит и незакоммиченную правку, актуально для
# pre-commit; в CI после коммита рабочее дерево совпадает с HEAD, эквивалентно. Если база
# недоступна в этом дереве — проверка пропускается с предупреждением, не падает (нет
# ложного FAIL на shallow clone или detached HEAD без origin).
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

    local version_diff
    version_diff=$(git diff --name-only "$base_ref" -- .claude-plugin/plugin.json 2>/dev/null || true)
    if [ -z "$version_diff" ]; then
        echo "FAIL: правка промт-слоя без подъёма version в .claude-plugin/plugin.json (NFR-25)"
        echo "Изменённые файлы промт-слоя (относительно $base_ref):"
        echo "$prompt_diff"
        fail=1
    fi
}

check_prompt_version_sync

if [ "$fail" -ne 0 ]; then
    echo
    echo "Проверка состава плагина: FAIL"
    exit 1
fi

echo "Проверка состава плагина: OK"
exit 0
