# meeting-analysis-quality-calibration

## Purpose

Governs four calibration properties of the meeting-analysis prompt layer
(`agents/ktalk-processor.md`, `agents/references/two-pass-analysis.md`,
`skills/ktalk-registry/references/analysis-quality.md`, `agents/references/protocol-template.md`)
found by three `ktalk-eval` runs across meeting types: a commitment named in the draft's prose
SHALL NOT go missing from the `Договорённости` table without a recorded reason; `confidence`
SHALL track the acceptance utterance, not the mood of the request; every proper name — a
participant's or a third party's — SHALL be resolved or marked, never silently left as-is; and
none of this SHALL license inventing content that was not in the transcript. A fifth property
keeps a prompt-layer edit visible to the quality tracker: a change to this prompt layer SHALL
raise the plugin's minor version.

## Requirements

### Requirement: A final pass reconciles the draft's prose against the `Договорённости` table

After the draft protocol is assembled, a pass SHALL run once over the draft as a whole — not a
repeat of transcript extraction — checking every sentence describing one participant's
commitment (including the header and the `Формат` block, not only the body text) against the
`Договорённости` table. For each commitment with no matching row, the pass SHALL either add the
row or record, in `Открытые вопросы`, an explicit reason there is none; it SHALL NOT pass over
the gap in silence.

#### Scenario: A prose-only commitment gets a row or a recorded reason

- **WHEN** the draft's prose names a commitment with no corresponding row in `Договорённости`
- **THEN** the final protocol SHALL either carry that row, or carry an explicit reason in
  `Открытые вопросы` naming why there is none

#### Scenario: A request-acceptance exchange is a candidate regardless of section

- **WHEN** the transcript carries a requesting utterance and, within the same exchange, an
  utterance of explicit agreement
- **THEN** the reconciliation pass SHALL treat it as a row candidate no matter which section of
  the draft first mentioned it

#### Scenario: Silence is not acceptance

- **WHEN** the only basis for a candidate row is the absence of an objection, an acknowledgement
  such as `угу`/`понятно`, or a change of subject — with no articulated act of agreement
- **THEN** the pass SHALL route it to `Открытые вопросы` with a reason, not to `Договорённости`
  or `Ключевые решения`

### Requirement: Confidence follows the acceptance utterance, not the request's mood

`confidence` SHALL be determined by the character of the reply that accepts a request, not by
whether the request itself was phrased conditionally. An explicit act of agreement in the
acceptance ("договорились", "сделаю", "хорошо" in reply to a direct request) SHALL yield HIGH; a
one-word reaction to a conditional proposal ("покопать", "посмотрю") SHALL yield MEDIUM even
when the request itself was doubly conditional. No example in the calibration reference marked
GOOD SHALL prescribe HIGH for a reply with no explicit act of agreement.

#### Scenario: An explicit acceptance after a conditional request yields HIGH

- **WHEN** a conditionally phrased request is met with an explicit agreement in the reply
- **THEN** the assigned `confidence` SHALL be HIGH

#### Scenario: A one-word reaction to a doubly conditional request yields MEDIUM

- **WHEN** a request carrying two layers of conditionality is met with a one-word,
  non-committal reaction
- **THEN** the assigned `confidence` SHALL be MEDIUM, not HIGH

#### Scenario: Calibration examples are internally consistent

- **WHEN** the calibration reference's examples marked GOOD are reviewed
- **THEN** none of them SHALL assign HIGH to a reply carrying no explicit act of agreement

### Requirement: Every proper name is resolved or marked, participants and third parties alike

Each proper name encountered in the transcript — not only meeting participants, but any third
party named in speech — SHALL be resolved against the host project's declared profile
directory. A name that resolves unambiguously SHALL be written corrected, with no marker. A name
that does not resolve — whether the lookup found no match or no directory is declared at all —
SHALL always carry the single marker fixed by the protocol template, never silently left
unmarked and never marked with an ad hoc form invented per occurrence. The same name SHALL be
marked (or not) consistently everywhere it appears in one document.

#### Scenario: A resolved, distorted name is written without a marker

- **WHEN** a name distorted by speech recognition resolves unambiguously against the profile
  directory
- **THEN** the protocol SHALL write the corrected name with no marker

#### Scenario: An unresolved third-party name is always marked

- **WHEN** a third party's name (not a meeting participant) does not resolve against the profile
  directory
- **THEN** the protocol SHALL carry it with the single marker fixed by the protocol template

#### Scenario: No declared directory degrades to marking every uncertain name

- **WHEN** the host project declares no profile directory
- **THEN** every name whose form is in doubt against the transcript SHALL be marked — the
  degraded path SHALL NOT silently skip any case

#### Scenario: One name is marked consistently across the document

- **WHEN** the same name occurs more than once in one protocol
- **THEN** its marking SHALL NOT differ between occurrences without an explicit, stated reason

### Requirement: A new row requires an articulated act of agreement, not silence

The reconciliation pass and the naming rules above SHALL NOT license inventing content absent
from the transcript. A row in `Договорённости`/`Ключевые решения` is legitimate only when a
dialogue turn carries an articulated act of agreement — explicit consent, a directive already
carried out in the meeting, or an unambiguous acceptance — never the mere absence of an
objection. A meeting with no such acts SHALL state plainly that none were found, not substitute
a conditional wording as if it were a decision. Growth of `decisions_count`/`commitments_count`/
`unclear_count` between two prompt revisions on the same recording is not, by itself, a defect:
it is expected when the reconciliation pass above moves an already-spoken commitment from prose
or from `Открытые вопросы` into the table. The optional `Ключевые тезисы` section for the
`session` meeting type is part of the protocol template's contract, not an ad hoc addition of a
particular run.

#### Scenario: No explicit decisions are stated plainly

- **WHEN** a meeting carries no "решили"/"договорились" moment
- **THEN** `decisions_count` SHALL be `0` and the protocol text SHALL say plainly that no
  decisions were found, without substituting a conditional wording as a decision

#### Scenario: Every table row traces to an articulated acceptance

- **WHEN** a row is present in `Договорённости`/`Решения`
- **THEN** it SHALL trace to a transcript turn carrying an articulated act of agreement; a row
  whose only basis is the absence of an objection SHALL NOT pass this check

#### Scenario: A rising count between revisions is not itself a defect

- **WHEN** `decisions_count`/`commitments_count`/`unclear_count` grows between two prompt
  revisions run on the same recording
- **THEN** that growth alone SHALL NOT be classified as a defect; the defect determination
  follows only from whether each new row traces to an articulated acceptance

#### Scenario: The session-type thesis section is a template contract, not an add-on

- **WHEN** a `session`-type meeting carries substantive points with no decision status
- **THEN** the `Ключевые тезисы` section SHALL be available as part of the protocol template for
  that meeting type, without a separate agreement outside the prompt

### Requirement: A prompt-layer edit raises the plugin's minor version

Editing any file of the analysis prompt layer (`agents/`, `skills/ktalk-registry/`) SHALL be
accompanied by raising the plugin's minor version (`.claude-plugin/plugin.json`). The `ktalk-eval`
tracker SHALL record the plugin version under which a run was performed, not only the prompt
layer's own internal version counter — the two counters are independent and neither substitutes
for the other.

#### Scenario: A prompt-layer edit bumps the minor version

- **WHEN** a file under `agents/` or `skills/ktalk-registry/` changes relative to the base branch
- **THEN** the plugin's minor version in `.claude-plugin/plugin.json` SHALL be higher than on the
  base branch

#### Scenario: The tracker records the plugin version of the run

- **WHEN** `ktalk-eval` writes a tracker record for a run
- **THEN** that record SHALL carry the plugin version as of the run, alongside and independent
  of the prompt layer's own internal version counter
