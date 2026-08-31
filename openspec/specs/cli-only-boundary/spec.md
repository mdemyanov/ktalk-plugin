# cli-only-boundary

## Purpose

Governs three properties of the boundary between the `ktalk` plugin and the `ktalk-mcp` package
(ADR-012): what dependency footprint a default install of `ktalk-mcp` carries, whether the plugin
declares an MCP interface surface at all, and how the plugin expresses which package version it is
compatible with. The three properties SHALL move together: a default install SHALL NOT require the
MCP-only dependency, the plugin SHALL declare no MCP interface, and the plugin's compatibility
check SHALL treat an exact package version as the contract, not a floor.

## Requirements

### Requirement: Default `ktalk-mcp` install excludes the MCP-only dependency

A default install of the `ktalk-mcp` package SHALL NOT require the dependency that exists solely
to run its MCP entry point. That dependency SHALL be reachable only through an explicit,
separately named install option. The package's CLI SHALL be fully functional — including a command
that makes a network call — without that option installed. The package's own development tooling
(the dependency group its contributors use to run its test suite) SHALL continue to include the
MCP-only dependency, so that the part of the test suite covering the MCP layer keeps running
unmodified.

#### Scenario: CLI runs without the MCP-only dependency

- **WHEN** `ktalk-mcp` is installed without its MCP-only install option
- **THEN** every CLI subcommand SHALL run normally, including a subcommand that performs a network
  call

#### Scenario: The MCP entry point is launched without the MCP-only dependency

- **WHEN** the package's MCP entry point is started in an environment where the MCP-only install
  option was not installed
- **THEN** the package SHALL exit with a message naming the missing install option and the command
  to add it, and SHALL NOT surface a raw import error or an unhandled stack trace

#### Scenario: Contributor test run is unaffected

- **WHEN** a contributor installs the package's own development dependency group to run its test
  suite
- **THEN** the MCP-only dependency SHALL be present, and every test file covering the MCP layer
  SHALL run exactly as before this change

#### Scenario: Default install completes within an interactive timeout

- **WHEN** the default (non-MCP) dependency set is installed cold, with no package cache warmed
- **THEN** the install SHALL complete within the timeout a contributor's interactive tooling
  applies by default to a single command (120 seconds), a bound the full dependency set does not
  meet

### Requirement: The plugin declares no MCP interface surface

The plugin SHALL NOT declare an MCP server. No `mcp__ktalk__*` tool SHALL be exposed to the
operator's session as a side effect of having this plugin installed. The CLI SHALL remain the sole
supported way to reach the circuit from the plugin's prompt layer, continuing the direction already
set for the plugin's own skills and agents. This property is not only a matter of declaration: the
text of every skill, agent and command in the plugin's prompt layer SHALL be consistent with it —
none SHALL describe or imply an MCP path to the `ktalk` circuit, for any operation, as a live or
alternative channel (ADR-023 D3, generalising the narrower "no MCP name for a meeting operation"
check this Requirement already absorbs). A prompt-layer file that still reads as though an MCP
tool for this circuit exists or is a fallback is a violation of this Requirement even when the
dependency declaration itself is already clean.

#### Scenario: A prompt-layer file describes MCP as a live channel

- **WHEN** the text of a skill, agent or command file describes an MCP tool of the `ktalk` circuit
  as an available, comparable, or fallback way to perform an operation this plugin already covers
  by CLI
- **THEN** that text SHALL be treated as a violation of this Requirement, independently of whether
  the plugin's dependency declaration itself names an MCP server

#### Scenario: No MCP server is declared

- **WHEN** the plugin's dependency declaration is inspected
- **THEN** it SHALL declare no MCP server for the `ktalk` circuit

#### Scenario: An operator who previously called an MCP tool directly

- **WHEN** an operator who used to invoke a `mcp__ktalk__*` tool directly (outside any skill,
  ad hoc in a chat turn) does so after this change ships
- **THEN** the tool SHALL NOT be available, and the operator SHALL be able to reach the same
  outcome through the CLI subcommand that already covers it (a naming table of the previously
  available tools and their CLI equivalents SHALL exist for the three tools whose CLI name differs
  from the retired MCP tool's name)

### Requirement: The compatibility check pins an exact package version

The plugin's compatibility declaration SHALL name one exact `ktalk-mcp` version, not a minimum. A
package version that differs from the pin — whether older or newer — SHALL be reported as
incompatible, not only a version below a floor. Any command the plugin prints or runs to bring the
package to a compatible state SHALL target that exact version, not a bare package name resolving to
whatever is newest.

#### Scenario: Installed version differs from the pin

- **WHEN** the compatibility check runs against an installed `ktalk-mcp` whose version is not equal
  to the pin, in either direction
- **THEN** the check SHALL report the package as incompatible and SHALL name the pinned version the
  remedy targets

#### Scenario: The remedy command names the exact version

- **WHEN** the plugin prints or runs a command to install or bring the package to a compatible
  state
- **THEN** that command SHALL include the pinned version, not a bare package name

#### Scenario: The plugin is not released ahead of its pinned package version

- **WHEN** a plugin release changes the pin to a `ktalk-mcp` version
- **THEN** that version SHALL already be published and installable through the package's
  distribution channel at the moment the plugin release is tagged; a plugin release pinning an
  unpublished package version SHALL be blocked before it reaches an operator
