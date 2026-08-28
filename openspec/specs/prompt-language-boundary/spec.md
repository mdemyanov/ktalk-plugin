# prompt-language-boundary

## Purpose

Governs which language each piece of text in the ktalk plugin's prompt layer is written in.
Instructional prose addressed to the model SHALL be English, so that reasoning runs in the
same language as the neighbouring plugins and costs fewer tokens; text the model reproduces
verbatim or shows to a human SHALL stay Russian, so that protocols, reports, registry values
and operator messages are unaffected by the migration. The prompt layer is the four
directories `skills/`, `commands/`, `agents/` and `references/`; `content/`, `README.md` and
`CONTRIBUTING.md` are outside this capability.

## Requirements

### Requirement: Instructional prose is English

Every statement in a prompt-layer file that instructs the model — a step, a criterion, a
heuristic, a prohibition, a rationale — SHALL be written in English. A file SHALL NOT be
classified as "a Russian file" or "an English file": both languages coexist in one file by
design, each in the role assigned below.

#### Scenario: A step description in an entry point

- **WHEN** a prompt-layer file states an instruction the model is to follow
- **THEN** that instruction SHALL be in English, including any explanation of why a Russian
  literal nearby must not be translated

#### Scenario: A reference file loaded from an entry point

- **WHEN** a file under `agents/references/`, `skills/*/references/` or `references/` states
  an instruction
- **THEN** that instruction SHALL be in English on the same terms as an entry point

### Requirement: Cyrillic is legal only in three syntactic contexts

Cyrillic characters SHALL appear in a prompt-layer file only inside a fenced code block,
inside inline backticks, or inside the value of the `description:` frontmatter key. Cyrillic
outside those three contexts SHALL be treated as a violation.

Guillemets (« ») SHALL NOT be a legal context: in Russian prose they are ordinary quotation
marks, so admitting them would leave the check unable to tell a literal from a quotation.

#### Scenario: A literal the model must emit verbatim

- **WHEN** an instruction names a string the model writes verbatim into a host artefact, a
  registry value, or a message to the operator
- **THEN** that string SHALL be wrapped in inline backticks, or placed inside a fenced block,
  and SHALL NOT be paraphrased, re-cased or re-punctuated

#### Scenario: Cyrillic left in bare prose

- **WHEN** a prompt-layer file contains a Cyrillic character in prose, outside a fenced block,
  outside inline backticks and outside `description:`
- **THEN** the language check SHALL fail with a non-zero exit code and SHALL name the file and
  the line

#### Scenario: A separate verbatim marker is introduced

- **WHEN** a change proposes a comment marker such as `<!-- verbatim:ru -->` to delimit
  Russian regions
- **THEN** it SHALL be rejected: the markup already carries that information, and a paired
  marker adds an unclosed-marker failure class (ADR-021 D2)

### Requirement: Verbatim Russian is preserved byte-for-byte

Three classes of Russian text SHALL survive the migration unchanged: values bound by a schema
or data contract; text written into the host's vault artefacts; and text printed to the
operator. Rewording, re-casing or re-punctuating any of them SHALL be a defect, not an
improvement.

#### Scenario: The meeting protocol template

- **WHEN** `agents/references/protocol-template.md` is edited under this capability
- **THEN** the Russian headings and table headers inside its fenced block — including
  `## Участники`, `## Ключевые решения`, `## Договорённости` — SHALL be byte-identical to
  their pre-migration form

#### Scenario: Status markers of the agreements reconciliation step

- **WHEN** the reconciliation step of `agents/ktalk-processor.md` is translated
- **THEN** the literals `✅ выполнено`, `❌ снято`, `🔄 в работе`, `↳ *ревизия`, `ДД.ММ.ГГГГ`,
  `ГГГГ-ММ-ДД` and `вне области` SHALL remain present and unchanged

### Requirement: The description frontmatter stays a bilingual dispatch surface

The `description:` value of an entry point SHALL carry an English descriptive sentence and
SHALL retain the Russian trigger phrases verbatim, in quotes. The trigger phrases are matched
against a Russian-speaking owner's utterance; translating them would change observable
activation behaviour.

#### Scenario: A skill's trigger phrases

- **WHEN** the `description:` of `skills/ktalk-registry/SKILL.md`, `skills/ktalk-eval/SKILL.md`,
  `skills/ktalk-meetings/SKILL.md` or `commands/ktalk-registry.md` is rewritten
- **THEN** every quoted Russian trigger phrase present before the rewrite SHALL still be
  present after it

#### Scenario: An agent's description

- **WHEN** the `description:` of `agents/ktalk-processor.md` or `agents/ktalk-evaluator.md` is
  rewritten
- **THEN** it SHALL be English: these agents are dispatched by an orchestrating skill, not
  matched against the owner's utterance, so they carry no trigger phrases

### Requirement: Every entry point declares the language directive

Each of the six entry points — `agents/ktalk-processor.md`, `agents/ktalk-evaluator.md`,
`skills/ktalk-registry/SKILL.md`, `skills/ktalk-eval/SKILL.md`, `skills/ktalk-meetings/SKILL.md`,
`commands/ktalk-registry.md` — SHALL state explicitly that reasoning is in English and that
all output visible to a human, and all text written into the host's artefacts, is in Russian.

Reference files SHALL NOT repeat the directive: they are read only from an entry point that
has already declared it.

#### Scenario: A new entry point is added

- **WHEN** a file is added under `agents/` or as a `skills/*/SKILL.md`
- **THEN** the language check SHALL fail until that file carries the directive

### Requirement: The boundary is enforced by an executable check

`scripts/check-prompt-language.sh` SHALL exist, SHALL be invoked from
`scripts/check-plugin-composition.sh`, and SHALL exit non-zero on any violation of the
requirements above. It SHALL NOT be wired into `scripts/check.sh`: that file is delivered by
the nauta plugin and frozen by sha256 in `.nauta-scripts-basis.yaml`, so editing it would put
the tree in delivery drift (ADR-021 D6).

#### Scenario: A clean tree

- **WHEN** every prompt-layer file satisfies the requirements
- **THEN** the check SHALL exit 0 and SHALL report the number of files inspected

#### Scenario: Behaviour is unchanged by the migration

- **WHEN** the migration is complete
- **THEN** `scripts/test-agreements-reconciliation.sh` SHALL still report `PASS=25 FAIL=0`,
  and the number of its assertions SHALL NOT be reduced
