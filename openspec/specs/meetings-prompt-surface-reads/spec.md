# meetings-prompt-surface-reads

## Purpose

Governs the five read-only operations the `ktalk-meetings` skill exposes over the `ktalk` CLI —
schedule, participant search, room diagnostics, and the two diagnostic escalations that follow
a failure of any of them — plus the handling of authorisation secrets across this surface. The
write operations of the same skill (meeting creation and cancellation, the sanction that gates
them) are a separate capability, `meeting-write-sanction-workflow`. Whether the plugin exposes
any MCP server for the circuit at all — including for this reading surface — is governed by
`cli-only-boundary`, the capability that owns that contract; this capability does not repeat
that scenario (ADR-023 D3).

## Requirements

### Requirement: The schedule is read with an explicit date window

The skill SHALL call `ktalk list-calendar` only with `--start`/`--end` values obtained from the
operator or from their own wording. It SHALL NOT substitute a default period on its own. An
`incomplete_segments` warning returned by the CLI SHALL be carried into the answer shown to the
operator verbatim, not dropped during formatting. A non-zero exit code SHALL be distinguished
from a zero exit code with an empty result: the former SHALL NOT be presented as "no meetings
found".

#### Scenario: No implicit date window

- **WHEN** the operator asks to see the schedule without stating a period
- **THEN** the skill SHALL ask for or derive explicit `--start`/`--end` values before calling
  `ktalk list-calendar`, and SHALL NOT call it with an assumed default window

#### Scenario: An incomplete-segment warning survives formatting

- **WHEN** `ktalk list-calendar --json` returns a non-empty `incomplete_segments` array
- **THEN** the answer shown to the operator SHALL state that the segment is incomplete

#### Scenario: A failed read is not shown as an empty schedule

- **WHEN** `ktalk list-calendar` exits with a non-zero code
- **THEN** the skill SHALL show the CLI's error text and SHALL NOT report "no meetings found"
  for that period

### Requirement: Participant search never auto-selects a candidate

The skill SHALL call `ktalk search-contacts --query` and distinguish its three documented
outcomes by exit code, not by parsing the message text: code `0` with more than one candidate,
code `0` with exactly one candidate, and code `2` (zero candidates, not a failure). It SHALL
NOT pick a candidate on the operator's behalf and SHALL NOT substitute a `key` into a later
meeting-creation call without first showing whose `key` is being used.

#### Scenario: More than one candidate

- **WHEN** `search-contacts` returns more than one candidate
- **THEN** the skill SHALL show every candidate (`key`, full name, job title) and SHALL ask the
  operator to choose, without substituting the first candidate's `key` anywhere

#### Scenario: Exactly one candidate

- **WHEN** `search-contacts` returns exactly one candidate and its `key` is later used in a
  meeting-creation call
- **THEN** the skill SHALL show the operator whose `key` is being substituted before using it

#### Scenario: Zero candidates is not an error

- **WHEN** `search-contacts` exits with the zero-candidates code
- **THEN** the skill SHALL report that no participant was found for the query and SHALL NOT
  treat this outcome as a network or authorisation failure

### Requirement: Room diagnostics always carries the side-effect warning

Every `ktalk get-room` call SHALL be accompanied, in the same answer, by a warning that the
call may create the room as a side effect for any name — the circuit does not distinguish an
existing room from one created by this very call. The skill SHALL NOT describe or use
`get-room` as a way to check whether a room name is free.

#### Scenario: The warning appears for every name, not only a plausibly new one

- **WHEN** the skill shows the result of a `get-room` call, for any room name
- **THEN** the answer SHALL include the side-effect warning unconditionally

#### Scenario: "Is this name free" is refused as a use case

- **WHEN** the operator asks to check whether a room name is free
- **THEN** the skill SHALL NOT call `get-room` for that purpose and SHALL explain that no such
  check exists in the circuit

### Requirement: A degradation by authorisation mode is explained, not guessed

When a CLI command of this surface fails because the active authorisation mode does not carry a
confirmed profile for the operation, the skill SHALL pass the CLI's error text to the operator
without rewording it into a generic failure message, and SHALL NOT suggest that the operation
will probably succeed.

#### Scenario: The CLI's message is not replaced

- **WHEN** a command fails with a message naming a missing or unconfirmed operation profile
- **THEN** the skill SHALL show that message to the operator as it is

#### Scenario: No probabilistic-success hint

- **WHEN** the operator is in an authorisation mode with no confirmed profile for the requested
  operation
- **THEN** the skill SHALL NOT hint that the operation will "probably work"

### Requirement: A failure escalates to rights and configuration diagnostics before retry

When any read command of this surface fails, the skill SHALL offer `ktalk auth-status --json`
and, if the failure looks like a host-project configuration problem rather than the circuit
operation itself, additionally offer `ktalk config show --json`, before suggesting a retry or
pointing at source code. `auth-status` SHALL NOT be the only hypothesis offered for a failure
that does not look like an authorisation problem.

#### Scenario: An authorisation-looking failure escalates to `auth-status`

- **WHEN** a command of this surface fails with a 401/403 or an error diagnosed as
  rights-related
- **THEN** the skill SHALL offer to run `ktalk auth-status --json` and, if the operator agrees,
  show its result

#### Scenario: A non-authorisation failure is not forced into the same hypothesis

- **WHEN** a command fails with a network error or an undocumented-circuit response
- **THEN** the skill SHALL pass the CLI's text through as received and SHALL NOT present
  `auth-status` as the only explanation offered

### Requirement: Secrets are never reintroduced into this surface's output

`KTALK_SESSION_TOKEN`/`KTALK_PERSONAL_API_KEY` values SHALL NOT appear in text this surface
shows to the operator, logs, or saves — including after a CLI error already redacted the value.

#### Scenario: A redacted CLI error stays redacted

- **WHEN** a command of this surface fails with an error whose secret value the CLI has already
  redacted
- **THEN** the skill SHALL NOT reconstruct or reprint the secret value from the environment or
  from a prompt variable
