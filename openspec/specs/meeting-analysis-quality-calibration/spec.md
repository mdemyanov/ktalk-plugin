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
unmarked and never marked with an ad hoc form invented per occurrence. Each occurrence's marker
follows from that occurrence's own resolution outcome, decided independently (§10 of
`analysis-quality.md`). Document-wide consistency of one name's marking across its several
occurrences — so that two occurrences of the same resolution outcome never disagree — is a
desired property; no file of the prompt layer prescribes a check across occurrences today, so it
is deferred rather than asserted here (tracked in `content/30-requirements/
2026-08-19-analysis-quality-calibration.md` FR-42's fourth AC, pending its own prompt-layer
calibration task).

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

#### Scenario: A repeated name's marking is decided per occurrence, not by a document-wide pass

- **WHEN** the same name occurs more than once in one protocol
- **THEN** each occurrence's marker SHALL follow from that occurrence's own resolution against
  the profile directory (resolved → no marker; unresolved → the fixed marker); a check that
  compares occurrences against each other for consistency is not prescribed by the prompt layer
  and is out of scope for this scenario — it is a desired follow-up property, not yet
  calibrated (see the Requirement note above)

### Requirement: A new row requires an articulated act of agreement, not silence

The reconciliation pass and the naming rules above SHALL NOT license inventing content absent
from the transcript. A row in `Договорённости`/`Ключевые решения` is legitimate only when a
dialogue turn carries an articulated act of agreement — explicit consent, a directive already
carried out in the meeting, or an unambiguous acceptance — never the mere absence of an
objection. A meeting with no such acts SHALL NOT have a conditional wording substituted as if it
were a decision — `decisions_count` SHALL be `0` in that case. A plain-language statement in the
protocol text that no decisions were found is a desired property; no file of the prompt layer
instructs adding such a statement, so it is deferred rather than asserted here (tracked in
`content/30-requirements/2026-08-19-analysis-quality-calibration.md` FR-43's first AC, pending
its own prompt-layer calibration task). Growth of `decisions_count`/`commitments_count`/
`unclear_count` between two prompt revisions on the same recording is consistent with, and
expected from, the reconciliation pass above moving an already-spoken commitment from prose or
from `Открытые вопросы` into the table — but a formal rule that excludes such growth from the
`ktalk-eval` evaluator's own defect criteria is a desired property; `eval-rubric.md`'s A/B
verification method does not carry it today, so it is deferred rather than asserted here (same
FR-43, third AC, pending calibration of the rubric rather than of the analysis prompt). The
optional `Ключевые тезисы` section for the `session` meeting type is part of the protocol
template's contract, not an ad hoc addition of a particular run.

#### Scenario: Zero decisions are not backfilled from conditional wording

- **WHEN** a meeting carries no "решили"/"договорились" moment
- **THEN** `decisions_count` SHALL be `0` and no conditional wording SHALL be substituted as if
  it were a decision; a plain-language statement that no decisions were found is a desired
  follow-up property, not yet instructed by the protocol template — out of scope for this
  scenario (see the Requirement note above)

#### Scenario: Every table row traces to an articulated acceptance

- **WHEN** a row is present in `Договорённости`/`Решения`
- **THEN** it SHALL trace to a transcript turn carrying an articulated act of agreement; a row
  whose only basis is the absence of an objection SHALL NOT pass this check

#### Scenario: A rising count between revisions is consistent with the reconciliation pass

- **WHEN** `decisions_count`/`commitments_count`/`unclear_count` grows between two prompt
  revisions run on the same recording
- **THEN** that growth by itself is consistent with the reconciliation pass (Requirement above)
  moving an already-spoken commitment into the table, and is not on its face evidence of
  invented content; a formal `eval-rubric.md` rule that excludes such growth from the
  evaluator's own defect criteria is a desired follow-up property, not yet carried by the A/B
  verification method — out of scope for this scenario (see the Requirement note above)

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
