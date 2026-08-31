# package-rename-transition

## Purpose

Governs the properties specific to the migration of the plugin's package dependency from
`ktalk-mcp` to `ktalk-cli` (ADR-012 boundary, second breaking change after `cli-only-boundary`):
that the plugin's prompt layer is unaffected by the rename, that the retired package name
resolves to an explicit pointer rather than a silent drift, that a command-name collision
between the two package identities is surfaced rather than resolved silently, and that
publication of either package to PyPI happens only under an explicit owner sanction. These
properties are transitional: once `ktalk-mcp` is fully retired from operator machines, this
capability's subject ceases to exist. The steady-state properties of the plugin↔package
boundary (dependency footprint, MCP surface, version-pin discipline) remain governed by
`cli-only-boundary`; this capability does not restate them.

## Requirements

### Requirement: The `ktalk` command name is preserved across the package rename

Renaming the package from `ktalk-mcp` to `ktalk-cli` SHALL NOT require any change to the text of
the plugin's prompt layer (`skills/`, `agents/`, `commands/`) that invokes the `ktalk` command.
The rename SHALL be visible only in the files that name the package by its distribution name:
`compat.json`, `README.md`, `references/onboarding.md`, `scripts/ktalk-onboard.sh`,
`scripts/test-onboard.sh`, and the package-name mention in `.claude-plugin/plugin.json`.

#### Scenario: Prompt-layer text is unaffected by the rename

- **WHEN** the package rename lands (the plugin's pin moves from a `ktalk-mcp` version to a
  `ktalk-cli` version)
- **THEN** a diff restricted to `skills/`, `agents/`, `commands/` SHALL be empty; every changed
  line SHALL fall within `compat.json`, `README.md`, `references/onboarding.md`,
  `scripts/ktalk-onboard.sh`, `scripts/test-onboard.sh`, or the package-name text of
  `.claude-plugin/plugin.json`

### Requirement: The plugin is not released ahead of the renamed package's first published version

A plugin release that changes its pinned package identity from `ktalk-mcp` to `ktalk-cli` SHALL
NOT be tagged or published before the target `ktalk-cli` version is already published and
installable through the package's distribution channel (PyPI). This generalises the sequencing
constraint already established for a version-only pin change (`cli-only-boundary`, "The plugin
is not released ahead of its pinned package version") to the case where the package's identity,
not only its version, changes.

#### Scenario: The plugin is not released ahead of ktalk-cli's first publication

- **WHEN** a plugin release changes `compat.json` to pin a `ktalk-cli` version for the first time
- **THEN** that version SHALL already be published and installable via PyPI at the moment the
  plugin release is tagged; a release pinning an unpublished `ktalk-cli` version SHALL be
  blocked before it reaches an operator

### Requirement: The retired `ktalk-mcp` package announces its retirement loudly, not silently

The final published version of `ktalk-mcp` SHALL declare no `ktalk` entry point and SHALL carry
no application functionality of its own; its sole entry point (the `ktalk-mcp` command) SHALL,
on every invocation, name `ktalk-cli` as the replacement and exit with a non-zero code — the
pointer's retirement is total and loud, not partial or silent. Because the pointer does not
claim the `ktalk` command, an operator who upgrades an already-installed `ktalk-mcp` in place,
or installs the pointer version fresh, loses the bare `ktalk` command outright unless
`ktalk-cli` is separately installed. This loss SHALL be an acknowledged, diagnosable state — the
plugin's own onboarding check SHALL name it as a distinct condition — not a defect masked by
silence or by a claim that the command still works.

#### Scenario: Invoking the retired package names the replacement and fails loudly

- **WHEN** the `ktalk-mcp` command — the pointer release's only entry point — is invoked, whether
  freshly installed or already present as an in-place upgrade
- **THEN** it SHALL print to stderr a message naming `ktalk-cli` and the exact install command,
  and SHALL exit with a non-zero code

#### Scenario: A bare `ktalk` invocation is not found after adopting the pointer

- **WHEN** an operator upgrades an already-installed `ktalk-mcp` in place to its final pointer
  version, or installs that version fresh, without separately installing `ktalk-cli`
- **THEN** the `ktalk` command SHALL no longer resolve on that machine; a direct terminal
  invocation of `ktalk`, made outside the plugin's own onboarding check, SHALL return the
  shell's ordinary "command not found" outcome — this is the accepted cost of the pointer not
  claiming the slot, and no part of the plugin SHALL claim or imply that the bare command still
  works

#### Scenario: The plugin's onboarding check names the mismatch, not the raw shell error

- **WHEN** an operator reaches the same state — any installed `ktalk-mcp` (pointer or earlier)
  while the plugin's compatibility declaration pins `ktalk-cli` — through the plugin's own
  onboarding check rather than a bare terminal call
- **THEN** the check SHALL report a distinct, named condition for "the installed package is not
  the pinned package", separately from "the installed package is an outdated version of the
  pinned package"

### Requirement: A command-name collision between the two package identities is surfaced explicitly

When both `ktalk-mcp` and `ktalk-cli` attempt to claim the `ktalk` command-name slot on one
machine, the collision SHALL be surfaced to the operator as an explicit, attributable condition.
Neither package's default install flow SHALL silently overwrite the other's `ktalk` command, and
no automatic remedy path SHALL add a forcing flag on the operator's behalf to resolve the
collision on its own; no subsequent state of the slot (working, overridden, or broken) SHALL go
undiagnosed by the plugin's own onboarding check.

#### Scenario: Default install refuses a silent takeover

- **WHEN** an operator installs one of {`ktalk-mcp`, `ktalk-cli`} through the plugin's default
  onboarding remedy command, while the other package already provides the `ktalk` command on the
  same machine
- **THEN** the install SHALL fail with an explicit message naming `ktalk` as the conflicting
  command, and SHALL NOT alter the command already provided by the other package

#### Scenario: An overridden takeover leaves a diagnosable trail

- **WHEN** an operator, acting by hand — never the onboarding flow itself, which SHALL NOT add a
  forcing flag automatically — deliberately overrides the collision so that the second package's
  `ktalk` becomes the active one
- **THEN** a subsequent run of the plugin's onboarding check SHALL report which package's
  `ktalk` is currently active, not merely that a package is installed

#### Scenario: Uninstalling the active package does not silently orphan the command

- **WHEN** an operator uninstalls the package currently providing the active `ktalk` executable,
  while the other package still holds a registration for the same command name
- **THEN** the plugin's onboarding check SHALL detect and report that `ktalk` is no longer
  resolvable, rather than reporting the other, non-providing package as compatible

### Requirement: Neither package is published to PyPI without a prior, explicit owner sanction

Publication of `ktalk-cli` 1.0.0, the `ktalk-mcp` deprecation-pointer release, or a PyPI name
reservation placeholder for either name SHALL NOT be performed by automation or an agent without
a prior, explicit, dated instruction from the package owner naming the exact package, version,
and index the action targets.

#### Scenario: A release step reaches the publish action

- **WHEN** a release process — manual, CI-driven, or agent-initiated — reaches the step that
  would push a package to PyPI under either name
- **THEN** it SHALL proceed only if an explicit, dated owner sanction naming that exact package,
  version and index already exists; absent such a sanction, the step SHALL halt before
  contacting PyPI
