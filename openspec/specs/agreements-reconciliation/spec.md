# agreements-reconciliation

## Purpose

Governs the behaviour of the `ktalk-processor` agent when it updates a participant profile's
"📝 Открытые договорённости" section during meeting processing: before appending new rows, the
agent SHALL reconcile existing open rows against the transcript of the meeting being processed,
so that execution, refusal or rescheduling spoken aloud in a meeting is reflected in the row's
status instead of being lost in an append-only history that never closes.

## Requirements

### Requirement: Conditional activation by section presence

The reconciliation step SHALL run only for a participant profile that already contains a
"📝 Открытые договорённости" section. A profile without the section SHALL NOT be created or
altered by this step. The processor SHALL NOT require any new explicit configuration key as a
precondition for reconciliation beyond the existing `registry.directories.people` gate.

#### Scenario: Profile has no open-agreements section

- **WHEN** the matched participant's profile contains no "📝 Открытые договорённости" section
- **THEN** the processor SHALL skip reconciliation for that profile without creating the section
  and without treating the absence as an error

#### Scenario: Profile has the section

- **WHEN** the matched participant's profile contains a "📝 Открытые договорённости" section
- **THEN** the processor SHALL run reconciliation against that section before appending any new
  row for the current meeting

### Requirement: Reconciliation precedes append

For a profile in scope, the processor SHALL read and reconcile the existing rows of the open
agreements section before adding rows produced by the current meeting's analysis.

#### Scenario: New agreement added in the same run as a reconciled row

- **WHEN** the current meeting both confirms execution of an existing row and produces a new
  open agreement for the same participant
- **THEN** the processor SHALL write the status update to the existing row and append the new
  row as two distinct edits, and SHALL NOT merge them into one row

### Requirement: Explicit confirmation required to change status

A row's status SHALL change only when the transcript contains an explicit statement, attributable
to a participant, that the agreement was executed, refused, rescheduled, or superseded by a
different subject. Silence, absence of objection, a bare acknowledgement ("угу", "понятно"), or a
change of topic SHALL NOT be treated as confirmation of any kind, by symmetry with the "molчание
не акцепт" rule applied to drafting new rows.

#### Scenario: Explicit execution statement found

- **WHEN** the transcript contains an explicit statement that a specific open row was completed,
  refused, or rescheduled
- **THEN** the processor SHALL update that row's status to `✅ выполнено`, `❌ снято`, or
  `🔄 в работе` (with the new deadline) accordingly, and SHALL record a revision line citing the
  current meeting's protocol as the source

#### Scenario: No explicit confirmation found for a candidate row

- **WHEN** the transcript's discussion of a topic overlapping an open row does not contain an
  explicit statement of execution, refusal, or rescheduling
- **THEN** the processor SHALL leave that row's status and text unchanged and SHALL NOT add a
  revision line for it

#### Scenario: Row confirmed still open without change

- **WHEN** a participant explicitly restates that an open row is still pending, unchanged
- **THEN** the processor SHALL leave the row unchanged and SHALL NOT record this as a distinct
  update

### Requirement: Revision line format

A status change to an existing row SHALL be recorded as a revision appended to that row's text
cell, in the form:
`{original text} <br>↳ *ревизия {date}: {what was confirmed, source}* | {deadline} | {new status}`,
where the source cites the protocol of the meeting being processed. The row's original text and
its original date cell SHALL be preserved unmodified.

#### Scenario: Row updated with a revision

- **WHEN** the processor changes a row's status
- **THEN** the row's original date and original text SHALL remain intact, and the revision
  clause SHALL name the current meeting's protocol as the source of the confirmation

### Requirement: Table parsing tolerates escaped pipes

When reading the open-agreements table, the processor SHALL split a row into cells only on
unescaped `|` characters, treating an escaped pipe inside a wiki-link (`[[путь\|Метка]]`) as part
of the cell content rather than a column boundary.

#### Scenario: A row contains a wiki-link with an escaped pipe

- **WHEN** a row's text cell contains `[[путь\|Метка]]`
- **THEN** the processor SHALL parse the row into the same four columns as a row without a
  wiki-link, without splitting inside the escaped pipe

### Requirement: Date parsing accepts two accepted formats

The processor SHALL correctly parse and compare dates in a row's date column expressed either as
`ДД.ММ.ГГГГ` or as `ГГГГ-ММ-ДД`, and SHALL NOT require the profile to be normalised to one format
before reconciliation runs.

#### Scenario: Mixed date formats in one table

- **WHEN** a profile's open-agreements table contains rows dated in both `ДД.ММ.ГГГГ` and
  `ГГГГ-ММ-ДД`
- **THEN** the processor SHALL parse both forms and SHALL NOT skip or misread either

### Requirement: Bounded reconciliation scope

For a profile whose open-agreements section holds more rows than a threshold `N` (rows older
than `N` days, or rows not referenced by the current meeting — the exact rule is a configuration
decision left to SA design, not fixed by this contract), the processor SHALL reconcile only the
in-scope rows and SHALL leave out-of-scope rows untouched. The processor SHALL NOT infer that an
out-of-scope row is confirmed-still-open merely because it was not reconciled.

#### Scenario: A profile has more open rows than the scope allows

- **WHEN** a participant's open-agreements section exceeds the configured scope
- **THEN** the processor SHALL reconcile only the in-scope rows and SHALL report the count of
  rows left outside scope, without altering their status or text

### Requirement: Reconciliation outcome is reported

The final processing report SHALL state, for each profile in scope, how many rows were updated by
reconciliation, and — when a bounded scope applied — how many rows were left out of scope. When
reconciliation did not run for a profile because the section was absent, the report SHALL state
that explicitly, by the same convention used for other unavailable steps.

#### Scenario: Report reflects reconciliation results

- **WHEN** the processor finishes updating one or more profiles in a single run
- **THEN** the final report SHALL list, per profile, the number of rows whose status changed by
  reconciliation, distinct from the count of newly appended rows
