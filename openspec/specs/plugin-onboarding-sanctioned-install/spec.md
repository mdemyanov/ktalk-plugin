# plugin-onboarding-sanctioned-install

## Purpose

Governs when the plugin detects that the `ktalk-mcp` package is missing or not the pinned
version, how it helps the operator fix that cooperatively, and under what explicit, separately
keyed sanction it fixes it itself. This capability owns the *process* — the moment of
detection, the cooperative-vs-automatic split, the TTY barrier on granting a sanction, the
idempotency and retry rules of an automatic install. It does **not** own the question "what
counts as a compatible version" — that contract belongs to `cli-only-boundary`'s Requirement
"The compatibility check pins an exact package version" (ADR-023 D2): a pin is exact, a
mismatch in either direction is incompatible, and the remedy command names the pinned version,
not a bare package name. Every scenario below that mentions "the remedy command" or "a
compatible version" relies on that Requirement rather than restating it.

Nor does it own which authorisation mode the onboarding instruction names, where it says the
value may be held, or which command it names to place it there — that content belongs to
`session-only-auth`'s Requirements ("The prompt layer declares exactly one supported
authorisation mode", "The instruction names the token file as a legitimate holder of the
value", "The instruction names the actual command that writes the token file"; ADR-028). This
capability's own authorisation Requirement below covers only that no secret value ever appears
in what the plugin controls.

## Requirements

### Requirement: Absence of the CLI is detected before the first circuit operation

The plugin has no post-install hook; detection happens on the first attempt to run a circuit
operation in a session, through `scripts/ktalk-onboard.sh check`. `uv` missing from `PATH` SHALL
be distinguished from `ktalk-mcp` missing: the message SHALL name the actually absent
prerequisite, not `ktalk-mcp` when the real gap is `uv`.

#### Scenario: Missing CLI is reported, not silently skipped

- **WHEN** a skill or agent runs `ktalk-onboard.sh check` before its first circuit operation of
  the session and the `ktalk` command does not resolve
- **THEN** the operator SHALL receive an explicit message naming the missing dependency, and the
  step SHALL NOT be skipped silently or its result invented

#### Scenario: A missing `uv` is named as the actual blocker

- **WHEN** `uv` itself is not on `PATH`
- **THEN** the check SHALL name `uv`, not `ktalk-mcp`, as the missing prerequisite

### Requirement: Cooperative mode shows the remedy command but never runs it

Without an automatic-install sanction, the only operations the plugin performs on its own are
reading `PATH`/version for diagnosis and printing instructions. It SHALL show the remedy command
(the exact-pin command governed by `cli-only-boundary`) ready to copy, and SHALL NOT execute it.

#### Scenario: The remedy command is shown, not run

- **WHEN** `ktalk-mcp` is not installed and no install sanction is granted
- **THEN** the plugin SHALL print the remedy command and SHALL NOT run it itself

#### Scenario: No command in cooperative mode changes installed packages

- **WHEN** no automatic-install sanction is granted
- **THEN** none of the commands the plugin runs on its own SHALL install or change a package in
  the system — only diagnosis and text output

### Requirement: The authorisation instruction never carries a secret value

Which authorisation mode the onboarding instruction names, where it says the value may be held,
and which command it names to place it there is governed by `session-only-auth` (ADR-028); this
capability does not restate that content. What this capability owns is narrower: the
instruction process itself SHALL NOT write a token value to any file it controls, and SHALL NOT
print a token value under any condition — it checks and reports only whether the token file or
an environment variable is set, never the value held.

#### Scenario: No token value appears in what the plugin controls

- **WHEN** any onboarding step is logged or its output inspected
- **THEN** no token value SHALL appear in it — only the fact that the token file or a variable
  is or is not set

### Requirement: Automatic install and update each require their own explicit sanction

An automatic install SHALL run only after the operator has explicitly and specifically granted
it in advance — silence is not a sanction, and a session with no TTY SHALL NOT be treated as one
either. A sanction to install where nothing is installed SHALL NOT silently extend to updating
an already-installed, non-matching version: the two are gated by separate sanction keys.

#### Scenario: No sanction — cooperative mode only

- **WHEN** the CLI is missing and no install sanction has been granted
- **THEN** the plugin SHALL NOT run any install command itself and SHALL fall back to
  cooperative mode

#### Scenario: A granted sanction runs the same remedy command shown cooperatively

- **WHEN** the install sanction is granted and the plugin performs the install itself
- **THEN** it SHALL run the exact command it would otherwise have shown the operator — not an
  alternative, undisclosed path

#### Scenario: An install sanction does not cover an update

- **WHEN** `ktalk-mcp` is already installed at a version that does not match the pin, and only
  the install sanction (not the update sanction) is granted
- **THEN** the plugin SHALL NOT perform the remedy on its own — it SHALL report that a separate
  sanction is required

#### Scenario: No TTY — never treated as a sanction

- **WHEN** a session has no interactive terminal at the moment a sanction would need to be
  granted
- **THEN** the plugin SHALL NOT request or infer a sanction interactively, and SHALL fall back
  to cooperative mode exactly as it would with no sanction at all

### Requirement: An automatic install is idempotent and network-tolerant within limits

Once the installed version already matches the pin, neither cooperative nor automatic mode SHALL
run the install command again. A failure of the network class (index unreachable, timeout, DNS
failure) SHALL be retried exactly once with the same command; a failure of rights, version
conflict, or package-not-found class SHALL NOT be retried at all. A failed automatic install
SHALL leave the system in the state it was in before the attempt — not a partially installed,
undiscoverable state — and its result (return code and output) SHALL always be reported to the
operator explicitly.

#### Scenario: Already-compatible install is a no-op

- **WHEN** the installed version already matches the pin
- **THEN** the plugin SHALL NOT run the install command again, in either mode

#### Scenario: Exactly one retry on a network-class failure

- **WHEN** an automatic install fails with a network-class error
- **THEN** the plugin SHALL retry the same command exactly once and SHALL NOT retry a
  rights/version-conflict/not-found failure at all

#### Scenario: A failed attempt is reported, not silently absorbed

- **WHEN** an automatic install attempt finishes, successfully or not
- **THEN** the operator SHALL be shown the return code and the command's output explicitly
