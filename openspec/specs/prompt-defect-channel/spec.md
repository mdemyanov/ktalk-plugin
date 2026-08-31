# prompt-defect-channel

## Purpose

Governs the transport from a `ktalk-eval` report's defect finding to a GitLab issue of the
plugin repository, without adding a script, a sanction, or a journal (ADR-019): the agent
prepares a structured record and, once a class has repeated on two or more recordings with a
complete pair of quotations, a candidate issue body; a human always performs the actual filing.
Verification of the threshold and the quotation pair is disciplinary — a documented rule read by
a human and by the prompt, not a blocking check — because the repository is read anonymously,
without authorisation, by anyone.

## Requirements

### Requirement: The eval report carries a structured, six-field defect record

Each defect finding in the `ktalk-eval` report's defect section SHALL carry six fields: defect
class, meeting type, the affected rubric dimension, a transcript quotation, a protocol
quotation, and a proposed rule. A record missing any of the six SHALL NOT be considered
complete. When a record is carried into an issue body, its fields SHALL transfer one-to-one,
without rewording.

#### Scenario: A complete record carries all six fields

- **WHEN** the defect section of a report records a finding
- **THEN** the record SHALL carry all six fields — a record missing one is not complete

#### Scenario: An issue body transfers fields without rewording

- **WHEN** a record is prepared for publication as an issue body
- **THEN** the text of its fields SHALL match the record's fields verbatim, apart from the
  anonymisation the corresponding requirement below requires

### Requirement: An issue is filed only for a defect class confirmed on 2+ recordings

`CONTRIBUTING.md` SHALL state, in words, that a defect class confirmed on fewer than two
recordings of the quality tracker does not get an issue — it stays a tracker row. The
`ktalk-eval` prompt instruction that builds the defect section SHALL likewise forbid including a
class that has occurred on only one recording. Repeat-count is read from the tracker's current
contents, not from an operator's memory of earlier runs.

#### Scenario: `CONTRIBUTING.md` states the threshold in words

- **WHEN** `CONTRIBUTING.md`'s section on filing a prompt-defect issue is read
- **THEN** it SHALL state, literally, that a class confirmed on fewer than two tracker
  recordings does not receive an issue

#### Scenario: The prompt instruction forbids a single-occurrence class

- **WHEN** the `ktalk-eval` agent's instruction for building the defect section is read
- **THEN** it SHALL explicitly forbid including a class that has occurred on only one recording

### Requirement: An issue is not filed without a complete pair of quotations

An issue SHALL NOT be filed for a defect case missing either its transcript quotation or its
protocol quotation. A case with only one of the two stays in the tracker until the pair is
complete.

#### Scenario: `CONTRIBUTING.md` requires the pair

- **WHEN** `CONTRIBUTING.md`'s section on required issue attachments is read
- **THEN** it SHALL name the transcript-and-protocol quotation pair as mandatory for every
  confirming case

#### Scenario: The prompt instruction forbids an incomplete case

- **WHEN** the `ktalk-eval` agent's instruction for recording a defect case is read
- **THEN** it SHALL explicitly forbid including a case missing either quotation

### Requirement: A human files the issue; the agent prepares but never publishes it

The agent SHALL prepare the issue body from the report's defect record and show it to the
operator; its involvement in this channel ends there. Filing the issue — copying the body into
the GitLab interface and creating the issue — SHALL be a manual action of the operator. The
agent SHALL NOT call a GitLab API and SHALL have no technical path to publish an issue as part
of this channel.

#### Scenario: The agent stops at showing the prepared body

- **WHEN** an issue body has been prepared from a record that meets the threshold and quotation
  requirements
- **THEN** the agent SHALL show it to the operator and SHALL NOT file the issue itself

#### Scenario: Filing is a manual GitLab action

- **WHEN** the operator files the prepared issue
- **THEN** that step SHALL be a manual action in the GitLab interface, with no CLI call or
  script performing it on the operator's behalf

### Requirement: Quotations are anonymised before publication, with a human preview

Every quotation carried into an issue body SHALL have employee names replaced by a role or an
anonymous identifier, and client names and monetary amounts removed or replaced by a
placeholder, before the operator ever sees it as something ready to copy. The full prepared body
SHALL be shown to the operator for review before it is copied into GitLab. No part of this
anonymisation SHALL be automatic pattern substitution (regex, a name catalogue): the barrier is
a mandatory prompt step plus a mandatory human review, by deliberate design, not oversight.

#### Scenario: The prompt instruction requires the substitution

- **WHEN** the `ktalk-eval` prompt prepares quotations for publication
- **THEN** its instruction SHALL contain an explicit step replacing employee names with a role
  and monetary amounts with a placeholder

#### Scenario: A full-body preview precedes copying into GitLab

- **WHEN** an issue body is ready and the operator is about to publish it
- **THEN** the operator SHALL be shown the complete body before copying it into GitLab

#### Scenario: No automatic substitution exists for any sensitive class

- **WHEN** the channel is inspected for an automatic replacement of employee, client or amount
  data
- **THEN** no such automatic step SHALL exist for any of the three classes

### Requirement: The channel adds no new infrastructure

The channel SHALL rely only on components that already exist: the report's defect section, the
quality tracker, the plugin repository's issue tracker, and the operator's manual action in
GitLab. It SHALL NOT add an executable transport script, a persistent sanction or journal on the
operator's machine, or a new top-level gate beyond `scripts/check-plugin-composition.sh`.
`CONTRIBUTING.md` and the defect-class catalogue are text, not executable.

#### Scenario: The composition gate gains no new executable

- **WHEN** the plugin's composition is checked by `scripts/check-plugin-composition.sh` after
  this channel is implemented
- **THEN** the gate SHALL find no new executable file or top-level gate beyond the report,
  tracker, `CONTRIBUTING.md` and the defect-class catalogue

#### Scenario: Publishing needs no script, sanction, or journal

- **WHEN** the operator publishes a prepared issue
- **THEN** the path SHALL require no script, no sanction, and no journal file on the operator's
  machine — only copying the prepared body into GitLab
