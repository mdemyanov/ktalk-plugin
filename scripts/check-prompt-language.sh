#!/usr/bin/env bash
# check-prompt-language.sh — gate for the capability `prompt-language-boundary`
# (ADR-021 D6; openspec/specs/prompt-language-boundary/spec.md).
#
# Subject: the TEXT of the prompt layer — `skills/`, `commands/`, `agents/`, `references/`.
# The boundary runs by the ROLE of the text, not by the file (ADR-021 D1): instructional
# prose addressed to the model is English, text the model reproduces verbatim or shows to a
# human stays Russian. This script is what makes that boundary machine-checkable rather than
# a review convention.
#
# `content/`, README.md and CONTRIBUTING.md are OUT of scope by design: a different audience
# and a different schema (content/.doc-root.yaml declares `language: ru`).
#
# Four groups of checks:
#   A. Cyrillic appears only in a fenced block, in inline backticks, or in a `description:`
#      frontmatter value (ADR-021 D2). Anything else is a violation naming file and line.
#   B. Each of the 6 entry points carries the language directive (ADR-021 D4).
#   C. The 25 Russian trigger phrases of the 4 dispatch surfaces survive verbatim (D3) —
#      they are matched against a Russian-speaking owner's utterance, so losing one is an
#      observable behaviour change, which NFR-1 forbids.
#   D. Verbatim literals that reach the host's vault survive (FR-3 class 2).
#
# Deliberately stdlib python3, not `uv run`: this gate belongs in pre-commit, and it must not
# pay uv's resolution cost on every commit. It has no third-party dependency.
#
# Run: bash scripts/check-prompt-language.sh
set -uo pipefail

cd "$(dirname "$0")/.."

python3 - <<'PY'
import re, sys, pathlib

CYR = re.compile(r'[а-яА-ЯёЁ]')
DIRECTIVE = re.compile(r'^\*\*Language\.\*\* Reason in English\.', re.M)

ENTRY_POINTS = [
    "agents/ktalk-processor.md",
    "agents/ktalk-evaluator.md",
    "skills/ktalk-registry/SKILL.md",
    "skills/ktalk-eval/SKILL.md",
    "skills/ktalk-meetings/SKILL.md",
    "commands/ktalk-registry.md",
]

# Frozen 2026-08-29 from the pre-migration tree; the extraction command is in the QA-001
# section of content/30-requirements/2026-08-29-prompt-language-boundary.md.
TRIGGERS = {
    "skills/ktalk-registry/SKILL.md": [
        "записи", "транскрипты", "реестр встреч", "обработай записи",
        "что нового в толке", "покажи необработанные встречи", "синхронизируй записи"],
    "skills/ktalk-eval/SKILL.md": [
        "оценить качество", "проверить протокол", "оцени обработку"],
    "skills/ktalk-meetings/SKILL.md": [
        "расписание", "встреча", "запланируй встречу", "отмени встречу",
        "найди участника", "проверь комнату", "kто свободен", "покажи календарь",
        "создай встречу в толке"],
    "commands/ktalk-registry.md": [
        "записи", "транскрипты", "реестр встреч", "обработай записи",
        "что нового в толке", "синхронизируй записи"],
}

# FR-3 class 2 — text that lands in the host's vault. Losing or rewording any of these is a
# defect, not an improvement (spec: "Verbatim Russian is preserved byte-for-byte").
VERBATIM = {
    "agents/references/protocol-template.md": [
        "## Участники", "## Ключевые решения", "## Договорённости",
        "| # | Решение | Кто принял | Таймкод | Confidence |"],
    "agents/ktalk-processor.md": [
        "✅ выполнено", "❌ снято", "🔄 в работе", "ДД.ММ.ГГГГ", "ГГГГ-ММ-ДД", "вне области"],
    "agents/references/vault-update-and-report.md": ["📝 Открытые договорённости"],
}

def split_front_matter(text):
    """Returns (frontmatter, body, body_offset_in_lines). No frontmatter -> ('', text, 0)."""
    m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
    if not m:
        return "", text, 0
    fm = m.group(1)
    return fm, text[m.end():], text[:m.end()].count("\n")

def strip_description(fm):
    """Blanks out the `description:` value — the one place where bare Cyrillic is legal
    outside code markup (ADR-021 D3). A value may be folded (`>`) across several indented
    lines; it ends at the next key at column 0."""
    out, in_desc = [], False
    for ln in fm.splitlines():
        if re.match(r'^description\s*:', ln):
            in_desc = True; out.append(""); continue
        if in_desc:
            if ln.strip() == "" or ln[:1] in (" ", "\t"):
                out.append(""); continue
            in_desc = False
        out.append(ln)
    return "\n".join(out)

def strip_code(body):
    """Blanks Cyrillic-bearing code markup: fenced blocks and inline backtick spans.
    Line count is preserved so reported line numbers stay true."""
    out, fenced = [], False
    for ln in body.splitlines():
        if ln.lstrip().startswith("```"):
            fenced = not fenced; out.append(""); continue
        if fenced:
            out.append(""); continue
        out.append(re.sub(r'`[^`]*`', '', ln))
    return out

files = sorted(p for d in ("skills", "commands", "agents", "references")
               for p in pathlib.Path(d).rglob("*.md"))

violations, checked = [], 0

# --- Group A -----------------------------------------------------------------
for p in files:
    checked += 1
    text = p.read_text(encoding="utf-8")
    fm, body, offset = split_front_matter(text)
    for i, ln in enumerate(strip_description(fm).splitlines(), start=2):
        if CYR.search(ln):
            violations.append(("A", f"{p}:{i}", "Cyrillic in frontmatter outside `description:`", ln.strip()[:90]))
    for i, ln in enumerate(strip_code(body), start=offset + 1):
        if CYR.search(ln):
            violations.append(("A", f"{p}:{i}", "Cyrillic in prose — wrap the literal in backticks or a fenced block (ADR-021 D2)", ln.strip()[:90]))

# --- Group B -----------------------------------------------------------------
for f in ENTRY_POINTS:
    p = pathlib.Path(f)
    if not p.exists():
        violations.append(("B", f, "entry point missing", "")); continue
    if not DIRECTIVE.search(p.read_text(encoding="utf-8")):
        violations.append(("B", f, "no language directive — expected a line starting `**Language.** Reason in English.` (ADR-021 D4)", ""))

# --- Group C -----------------------------------------------------------------
for f, phrases in TRIGGERS.items():
    text = pathlib.Path(f).read_text(encoding="utf-8")
    fm, _, _ = split_front_matter(text)
    for ph in phrases:
        if f'"{ph}"' not in fm:
            violations.append(("C", f, f'trigger phrase lost from description: "{ph}" (ADR-021 D3)', ""))

# --- Group D -----------------------------------------------------------------
for f, literals in VERBATIM.items():
    text = pathlib.Path(f).read_text(encoding="utf-8")
    for lit in literals:
        if lit not in text:
            violations.append(("D", f, f"verbatim literal lost: {lit}", ""))

if violations:
    by_group = {}
    for g, where, what, ctx in violations:
        by_group.setdefault(g, []).append((where, what, ctx))
    for g in sorted(by_group):
        rows = by_group[g]
        print(f"FAIL group {g}: {len(rows)} violation(s)")
        for where, what, ctx in rows[:40]:
            print(f"  {where}: {what}")
            if ctx:
                print(f"      | {ctx}")
        if len(rows) > 40:
            print(f"  … and {len(rows) - 40} more in group {g}")
    print()
    print(f"Проверка языка промт-слоя: FAIL ({len(violations)} нарушений, {checked} файлов)")
    sys.exit(1)

print(f"Проверка языка промт-слоя: OK ({checked} файлов проверено)")
PY
