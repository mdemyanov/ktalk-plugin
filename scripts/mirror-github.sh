#!/usr/bin/env bash
# mirror-github.sh — тело джоба mirror-github (ADR-027 Д2; уточнение PM поверх брифа SA,
# ktalk-plugin-dhg.11, п.5): собирает payload-дерево релизного тега по манифесту
# .gitlab/payload-manifest.txt, патчит .claude-plugin/marketplace.json.name на
# "ktalk-plugins-mirror" (Д1 ADR-027), коммитит и (только по явной санкции) пушит тег и
# дерево на публичное GitHub-зеркало. .gitlab-ci.yml — тонкий вызывающий; ВСЁ тело
# зеркалирования живёт здесь, проверяемо без раннера GitLab CI (в дереве сегодня нет ни
# одного CI-файла — `find . -iname "*.gitlab-ci*"` пуст на момент этой правки).
#
# jq-фильтр патча name (тот же, что упоминает .gitlab-ci.yml как документацию шага —
# единственная логика патча живёт здесь, комментарий в CI-файле её не дублирует):
#   jq '.name = "ktalk-plugins-mirror"'
#
# Push — санкционируемая операция (полномочие O4, ADR-036 Д5/Д6): без --push (или без
# GITHUB_MIRROR_TOKEN в окружении) скрипт всегда работает в режиме --dry-run и никогда
# не исполняет git push, даже если токен всё же присутствует в окружении, — только явный
# флаг включает попытку push. Приёмка Dev в этой задаче — исключительно --dry-run;
# реальный push выполняет координатор/DevOps по отдельной санкции.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: mirror-github.sh [--tag <ktalk--vX.Y.Z>] [--remote <url>] [--dry-run] [--push]

  --tag <tag>     Тег релиза, зеркалируемый на GitHub. По умолчанию — тег текущего HEAD
                  (git describe --tags --exact-match), если он единственный.
  --remote <url>  URL публичного GitHub-репозитория. По умолчанию
                  https://github.com/mdemyanov/ktalk-plugin.git.
  --dry-run       Собрать payload-дерево, напечатать план push, ничего не отправлять.
                  Поведение по умолчанию, если --push не указан явно.
  --push          Реально выполнить git push. Требует GITHUB_MIRROR_TOKEN в окружении.
                  Без этого флага скрипт НИКОГДА не пушит, даже если токен задан.
  -h, --help      Показать эту справку.
EOF
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_URL="https://github.com/mdemyanov/ktalk-plugin.git"
TAG=""
DO_PUSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --remote) REMOTE_URL="$2"; shift 2 ;;
    --dry-run) DO_PUSH=0; shift ;;
    --push) DO_PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "FAIL: неизвестный аргумент: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TAG" ]]; then
  TAG="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null || true)"
fi
if [[ -z "$TAG" ]]; then
  TAG="HEAD"
  echo "WARN: --tag не указан и текущий HEAD не помечен ровно одним тегом — payload собирается из HEAD (допустимо для локального --dry-run; --push с TAG=HEAD ниже отдельно запрещён)" >&2
fi
if [[ "$DO_PUSH" -eq 1 && "$TAG" == "HEAD" ]]; then
  echo "FAIL: --push требует настоящего тега (форма ktalk--vX.Y.Z) — HEAD не тег" >&2
  exit 1
fi

MANIFEST="$ROOT/.gitlab/payload-manifest.txt"
if [[ ! -s "$MANIFEST" ]]; then
  echo "FAIL: манифест $MANIFEST не найден или пуст — нечего собирать в payload-дерево" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DEST="$WORK/payload"
mkdir -p "$DEST"

# Дерево собирается из ТЕГА В GIT (git archive), не из рабочей копии на диске: рабочая
# копия может нести untracked/gitignored артефакты сборки (например, scripts/__pycache__/
# — тот же класс риска, что check-plugin-composition.sh исключает из своего обхода,
# описание вверху check-plugin-composition.sh), которых на самом теге нет и не будет.
PATHSPECS=()
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  case "$path" in
    /*|*..*)
      echo "WARN: путь '$path' из манифеста пропущен — абсолютный путь или обход каталога (..) не допускается" >&2
      continue
      ;;
  esac
  if [[ -z "$(git -C "$ROOT" ls-tree -r --name-only "$TAG" -- "$path" 2>/dev/null)" ]]; then
    echo "WARN: путь '$path' из манифеста отсутствует на теге $TAG — пропущен" >&2
    continue
  fi
  PATHSPECS+=("$path")
done < "$MANIFEST"

if [[ "${#PATHSPECS[@]}" -eq 0 ]]; then
  echo "FAIL: ни один путь из манифеста не найден на теге $TAG — payload-дерево пусто" >&2
  exit 1
fi

git -C "$ROOT" archive "$TAG" -- "${PATHSPECS[@]}" | tar -x -C "$DEST"

if [[ ! -f "$DEST/.claude-plugin/marketplace.json" ]]; then
  echo "FAIL: .claude-plugin/marketplace.json отсутствует в собранном payload-дереве — нечем патчить name (Д1 ADR-027)" >&2
  exit 1
fi

# Д1 ADR-027: единственная точка правки поля name — эта СКОПИРОВАННАЯ копия, не источник.
jq '.name = "ktalk-plugins-mirror"' "$DEST/.claude-plugin/marketplace.json" \
  > "$DEST/.claude-plugin/marketplace.json.tmp"
mv "$DEST/.claude-plugin/marketplace.json.tmp" "$DEST/.claude-plugin/marketplace.json"

echo "План зеркалирования:"
echo "  тег:            $TAG"
echo "  remote:         $REMOTE_URL"
echo "  payload-дерево: $DEST"
echo "  marketplace.json.name (пропатчено): $(jq -r '.name' "$DEST/.claude-plugin/marketplace.json")"
echo "  файлы:"
(cd "$DEST" && find . -type f | sed 's#^\./#    #' | sort)

if [[ "$DO_PUSH" -eq 0 ]]; then
  echo
  echo "DRY-RUN: push не выполнен. Для реального push — флаг --push и переменная GITHUB_MIRROR_TOKEN."
  exit 0
fi

if [[ -z "${GITHUB_MIRROR_TOKEN:-}" ]]; then
  echo "FAIL: --push указан, но GITHUB_MIRROR_TOKEN не задан в окружении — push не выполняется" >&2
  exit 1
fi

# Реальный push — только по явному --push и с токеном (санкция оператора, полномочие O4,
# ADR-036 Д5/Д6). Дальше — коммит payload-дерева и push ветки+тега на публичный remote.
#
# Push ветки и тега РАЗДЕЛЁН на две команды с разным режимом force (SEC-001, Находка 5,
# подтверждено исполнением на локальном bare-репозитории: второй прогон без --force падает
# `! [rejected] mirror-tmp -> main (fetch first)`, т.к. каждый запуск — новый `git init` без
# общего предка с прошлым состоянием `main`). Тег — БЕЗ --force: ADR-025 Д1 уже решает тег
# неперемещаемым, и это решение здесь не пересматривается — конфликт тега обязан падать
# громко. Ветка `main` зеркала — С --force: ADR-027 Д2 говорит, что зеркало на каждый релиз
# ПЕРЕСОБИРАЕТСЯ из тега, а не наращивается, то есть история `main` зеркала сама по себе не
# несёт ценности (единственный самостоятельно ценный указатель — тег, ему force не нужен по
# другой причине: он и так один на каждое дерево). --force-with-lease не даёт здесь
# дополнительной защиты и добавляет лишний fetch перед каждым push: lease сравнивается с
# ПРЕДЫДУЩИМ known-состоянием `main`, а каждый запуск начинает всё равно с нового `git init`
# без ссылки на предыдущее состояние — сравнивать не с чем.
(
  cd "$DEST"
  git init -q .
  git checkout -q -b mirror-tmp
  git add -A
  git -c user.email="mirror@ktalk-plugin.local" -c user.name="ktalk-mirror-bot" \
    commit -q -m "mirror: $TAG"
  git tag "$TAG"
  git remote add origin "$REMOTE_URL"
  git -c http.extraHeader="Authorization: Bearer ${GITHUB_MIRROR_TOKEN}" \
    push origin "$TAG"
  git -c http.extraHeader="Authorization: Bearer ${GITHUB_MIRROR_TOKEN}" \
    push --force origin "mirror-tmp:main"
)
echo "OK: $TAG запушен на $REMOTE_URL"
