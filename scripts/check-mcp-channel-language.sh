#!/usr/bin/env bash
# check-mcp-channel-language.sh — generalised guard for the capability `cli-only-boundary`
# (openspec/specs/cli-only-boundary/spec.md, Requirement "The plugin declares no MCP
# interface surface"): "none [of the prompt-layer text] SHALL describe or imply an MCP path
# to the `ktalk` circuit ... as a live or alternative channel".
#
# Origin (backlog `ktalk-plugin-ddq`, DEV-102). Review REV-002 (`ktalk-plugin-56l.26`,
# 2026-08-31) named the residual risk this replaces: the guard `scripts/test-onboard.sh` had
# for this property (its test 46, now ND-25/ND-26 below) was two literal `grep`s for two known
# phrasings. The Requirement is general ("any formulation, any file"); the old guard was not.
# New wording of the same idea would pass it silently. This script inverts the polarity to fix
# that: instead of a deny-list of known-bad phrases (which a rewrite always evades), it is a
# default-deny scan — every prompt-layer mention of MCP is a FAIL unless it matches one of
# three explicitly allow-listed, evidence-backed exemptions. New lexicon that is not one of the
# three legitimate classes below fails by construction, without the gate author having seen it.
#
# Subject: skills/, agents/, commands/, references/ — the same four directories
# check-prompt-language.sh scans (prompt layer proper). Unit of judgement is the PARAGRAPH
# (a blank-line-delimited block, or a single heading line), not the raw line: legitimate
# absence-declarations and changelog entries routinely wrap a sentence across two source
# lines, and a per-line check would fracture that context and misclassify the second line.
#
# Three exempt classes (verified against the live tree — see report of DEV-102 for the
# transcript on both ends):
#   1. Constatation of absence — "the plugin declares no MCP server/interface" and its
#      immediate structural family. Detected by an explicit `declares no MCP` /
#      `no MCP <server|interface|surface|path>` pattern, plus a small set of
#      unambiguous historical/negation verbs (retired, removed, renamed, migrated, forbids,
#      excludes) that this tree's own text already uses for the same claim (e.g. "forbids"
#      in references/onboarding.md, "Retired MCP tool" in its table header).
#   2. Historical changelog entries — any paragraph nested under a heading whose text
#      contains "Changelog" (case-insensitive), tracked by heading level so the exemption
#      ends at the next heading of equal-or-higher level, the way every `_meta.md` in this
#      tree already structures its "## Changelog" section. A heading titled with a bare
#      version or date (`### 4.0.0 (2026-04-03)`, `### 2026-08-31 (...)`), a shape unique to
#      changelog entries in this tree, is exempt even without an ancestor literally named
#      "Changelog".
#   3. The foreign `qmd` contour (vector search in the host's vault, unrelated to the `ktalk`
#      circuit this Requirement governs) — any paragraph mentioning `qmd` is exempt outright,
#      covering `tools:` frontmatter arrays and inline `mcp__qmd__*` calls alike.
#
# What counts as "an MCP mention" at all: the literal token `mcp` (word-bounded, so it does
# NOT fire on the substring inside `ktalk-mcp`/`ktalk_mcp_version`/`ktalk_mcp_min_version` —
# those name the package's retired identity, ADR-024's concern, not this Requirement's), the
# `mcp__` tool-name prefix, and the spelled-out phrase "Model Context Protocol" (with any of
# space/hyphen as the word separator, and tolerant of a mid-phrase line wrap, since Markdown
# prose wraps at will and a paragraph is matched as one whitespace-normalised string, not
# line-by-line). The MCP-only-package-identity string `ktalk-mcp` is deliberately never itself
# a trigger — see the report of DEV-102, "Known scope boundary", for why extending this gate to
# also police that string would duplicate ADR-024/package-rename-transition's own guard rather
# than the live-channel property this gate is scoped to.
#
# Deliberately stdlib python3, not `uv run` — same reasoning as check-prompt-language.sh: this
# gate is meant for `projectGates.fast` (pre-commit-cheap), and must not pay uv's resolution
# cost on every commit.
#
# Run: bash scripts/check-mcp-channel-language.sh
set -uo pipefail

cd "$(dirname "$0")/.."

python3 - <<'PY'
import re
import sys
import pathlib

ROOT = pathlib.Path(".")
SCAN_DIRS = ["skills", "agents", "commands", "references"]

MCP_TOKEN = re.compile(r'mcp__|\bmcp\b|model[- ]context[- ]protocol', re.IGNORECASE)
COMPOUND_IDENTITY = re.compile(r'ktalk[-_]mcp[-_a-z]*', re.IGNORECASE)
QMD_MENTION = re.compile(r'qmd', re.IGNORECASE)
HEADING = re.compile(r'^(#{1,6})\s+(.*)$')
CHANGELOG_HEADING = re.compile(r'changelog', re.IGNORECASE)
DATED_HEADING = re.compile(r'^(v?\d+\.\d+\.\d+|\d{4}-\d{2}-\d{2})\b')
HISTORICAL_OR_NEGATION = re.compile(
    r'\b(retired|removed|renamed|migrated|forbids?|forbidden|excludes?)\b', re.IGNORECASE)
ABSENCE_DECLARATION = re.compile(
    r'declares?\s+no\s+mcp|no\s+mcp\s+(server|interface|surface|path)', re.IGNORECASE)


def strip_identity(text):
    """Blank out `ktalk-mcp`/`ktalk_mcp_*` — the retired package's own name, ADR-024's
    concern, not this gate's (see header comment, "What counts as an MCP mention")."""
    return COMPOUND_IDENTITY.sub(' ', text)


def iter_files():
    for d in SCAN_DIRS:
        base = ROOT / d
        if not base.exists():
            continue
        for p in sorted(base.rglob("*.md")):
            yield p


def paragraphs(lines):
    """Split into (start_line, end_line, text, in_changelog) blocks: blank-delimited runs of
    body text, plus one block per heading line (a heading is judged on its own text, and also
    opens/closes the changelog-context tracked for the blocks that follow it)."""
    heading_stack = []  # list of (level, in_changelog_here)
    in_changelog = False
    buf, start = [], None
    blocks = []

    def flush():
        nonlocal buf, start
        if buf:
            blocks.append((start, start + len(buf) - 1, "\n".join(buf), in_changelog))
        buf, start = [], None

    for i, line in enumerate(lines):
        m = HEADING.match(line)
        if m:
            flush()
            level, text = len(m.group(1)), m.group(2)
            while heading_stack and heading_stack[-1][0] >= level:
                heading_stack.pop()
            is_changelog_heading = bool(CHANGELOG_HEADING.search(text)) or bool(DATED_HEADING.match(text))
            if is_changelog_heading:
                in_changelog = True
            elif heading_stack:
                in_changelog = heading_stack[-1][1]
            else:
                in_changelog = False
            heading_stack.append((level, in_changelog))
            blocks.append((i, i, line, in_changelog))
            continue
        if line.strip() == "":
            flush()
            continue
        if start is None:
            start = i
        buf.append(line)
    flush()
    return blocks


violations = []
checked = 0
for f in iter_files():
    checked += 1
    text = f.read_text(encoding="utf-8")
    lines = text.split("\n")
    for (s, e, ptext, in_changelog) in paragraphs(lines):
        flat = re.sub(r'\s+', ' ', ptext)
        if not MCP_TOKEN.search(strip_identity(flat)):
            continue  # no MCP mention here at all (or only the retired package's own name)
        if in_changelog:
            continue  # class 2 — historical changelog entry
        if QMD_MENTION.search(flat):
            continue  # class 3 — foreign `qmd` contour, out of this Requirement's scope
        if HISTORICAL_OR_NEGATION.search(flat) or ABSENCE_DECLARATION.search(flat):
            continue  # class 1 — constatation of absence
        rel = f.as_posix()
        loc = f"{rel}:{s + 1}" if s == e else f"{rel}:{s + 1}-{e + 1}"
        violations.append((loc, ptext.strip()[:200]))

if violations:
    print(f"FAIL: {len(violations)} упоминание(й) MCP не подпадает ни под один из трёх")
    print("допустимых классов (снятие поверхности / история changelog / контур qmd) —")
    print("текст читается как описывающий MCP живым или альтернативным каналом контура ktalk")
    print("(cli-only-boundary, Requirement «The plugin declares no MCP interface surface»):")
    for loc, ctx in violations:
        print(f"  {loc}")
        print(f"      | {ctx}")
    sys.exit(1)

print(f"Проверка «MCP как живой канал» промт-слоя: OK ({checked} файлов проверено)")
PY
