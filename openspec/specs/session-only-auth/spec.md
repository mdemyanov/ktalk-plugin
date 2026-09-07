# session-only-auth

## Purpose

Governs what the plugin's prompt layer (`README.md`, `references/`, `skills/`, `agents/`,
`commands/`) says about authorisation against Kontur Talk once the owner's decision retires the
personal API key from the plugin's declared surface: exactly one mode is named, the token file
is named as a legitimate holder of its value alongside the environment, the command that writes
that file is named correctly, and failure guidance points to one remedy, not a choice between
two. `openspec/specs/plugin-onboarding-sanctioned-install/spec.md` keeps owning the onboarding
*process* (detection, cooperative-vs-automatic install, the TTY barrier); this capability owns
only the *content* of the authorisation instruction it prints, superseding that spec's
Requirement "The authorisation instruction never carries a secret value" where the two disagree
on how many modes are named. It does not reach into the `ktalk-cli` package: the package keeps
accepting a personal key at the protocol level (tracked separately,
`github.com/mdemyanov/ktalk-cli#10`); this capability governs the plugin's own text only.

A second, unrelated group of Requirements below closes four documentation-accuracy gaps
surfaced by the same 2026-09-07 live session that prompted the authorisation change: an output
shape the registry dashboard documents incompletely, a command table that leaves a reader unable
to find recording commands, a cross-file reference that names a file without saying where it is
explained, and a README that does not name what changed in the currently pinned CLI version.
These are grouped with the authorisation change because they were discovered and are closed in
the same pass, not because they share a mechanism with it.

## Requirements

### Requirement: The prompt layer declares exactly one supported authorisation mode

Prompt-layer text SHALL name the browser session token as the sole supported authorisation
mode. It SHALL NOT name `KTALK_PERSONAL_API_KEY` as a supported, recommended, or alternative
option, and SHALL NOT state a priority rule between two modes — there is only one mode to
prioritise against.

#### Scenario: No prompt-layer file names the retired mode as supported

- **WHEN** `README.md`, `references/`, `skills/`, `agents/`, `commands/` are searched for the
  literal `KTALK_PERSONAL_API_KEY`
- **THEN** no occurrence presents it as a supported or recommended option

#### Scenario: The authorisation section names one mode, not a priority between two

- **WHEN** the onboarding authorisation instruction is read
- **THEN** it names the session token as the only mode and does not describe a rule for what
  happens when two modes are set at once

### Requirement: The instruction names the token file as a legitimate holder of the value

The authorisation instruction SHALL name the token file (`~/.config/ktalk-mcp/token`, or its
documented override) as a supported way to hold the session-token value, in addition to a
process environment variable. It SHALL NOT state or imply that the value is held by the
environment alone.

#### Scenario: The token file is named alongside the environment variable

- **WHEN** the authorisation instruction lists where the session-token value may be held
- **THEN** it names both the token file and the environment variable, not the environment alone

### Requirement: The instruction names the actual command that writes the token file

The authorisation instruction SHALL name `ktalk token set -` (reading the value from stdin) as
the command that writes the token file. It SHALL NOT name a command that does not exist in the
CLI.

#### Scenario: The named command exists and matches the CLI

- **WHEN** the authorisation instruction tells the operator how to place a session-token value
- **THEN** the command it names is `ktalk token set -`, and no non-existent command (such as a
  `ktalk session` subcommand) is named anywhere in the prompt layer

### Requirement: Authorisation-failure guidance points to a single remedy

Prompt-layer text addressing a failed or expired authorisation SHALL direct the operator to
refresh the session-token file. It SHALL NOT offer switching to a personal API key as an
alternative remedy.

#### Scenario: Failure guidance names one path forward

- **WHEN** the plugin's failure-diagnostics text addresses an authorisation error (an expired or
  missing token)
- **THEN** it names refreshing the session-token file as the remedy, and does not name a
  personal-key alternative

### Requirement: Operations without a session profile are not offered

Prompt-layer text SHALL NOT document or offer `ktalk list-archive` or a participants-report
operation as available to the operator: neither has a session-token profile in the CLI, and
retiring the personal-key mode from the plugin's declared surface removes their only supported
path.

#### Scenario: Command tables do not list an operation with no session profile

- **WHEN** a prompt-layer command table is read
- **THEN** neither `list-archive` nor a participants-report operation is listed as an operation
  available to the operator

### Requirement: The registry dashboard's output shape is documented completely

Prompt-layer text describing the output of `ktalk dashboard --json` SHALL enumerate every
top-level key the command returns, including `last_synced` (a date string or `null`, always
present).

#### Scenario: The documented shape names all three top-level keys

- **WHEN** `skills/ktalk-registry/SKILL.md` describes the output of `ktalk dashboard --json`
- **THEN** the text names `new`, `stats`, and `last_synced` as top-level keys, not only the
  first two

### Requirement: The meetings skill points to where recording commands are documented

`ktalk-meetings`'s own command reference SHALL NOT omit recording-related commands
(`list-recordings`, `get-transcript`, `get-summary`, and siblings) silently: it SHALL point the
reader to the skill or table that documents them.

#### Scenario: A reader looking for a recording command is redirected, not left empty-handed

- **WHEN** the operator reads the "Related commands" table of `skills/ktalk-meetings/SKILL.md`
  looking for a recording-related command
- **THEN** the text names or points to where recording commands (owned by `ktalk-registry`) are
  documented

### Requirement: A bare cross-file mention of `.ktalk.toml` names where it is explained

A prompt-layer mention of `.ktalk.toml` that does not itself explain the file's purpose and
format SHALL name where that explanation lives, rather than naming the bare filename with no
pointer.

#### Scenario: The onboarding mention of `.ktalk.toml` points to its explanation

- **WHEN** `references/onboarding.md` mentions `.ktalk.toml`
- **THEN** the text names the README section where the file's purpose and format are explained

### Requirement: README names the operator-visible novelties of the pinned CLI version

README SHALL carry a section naming the operator-visible changes introduced by the currently
pinned `ktalk-cli` version. The section SHALL be updated whenever `compat.json`'s pinned version
changes to a version with operator-visible changes.

#### Scenario: README names what changed in the pinned version

- **WHEN** `compat.json` pins a `ktalk-cli` version
- **THEN** README carries a section naming the operator-visible changes of that version, not
  only the version number
