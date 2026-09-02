# release-delivery-tails

## Purpose

Governs the properties left open after the 1.9.0 release that determine whether a release
actually reaches an already-installed consumer, whether the plugin's declared composition and
documentation state true facts about the interface it exposes, and whether cross-agent
delegation inside the plugin's own prompt layer stays inside the boundaries its agents can
actually act within. Three groups of behaviour move under this capability: the plugin's release
and marketplace surface (tag form, marketplace metadata, the documented update path), the
accuracy of what the plugin declares about itself (which files are agents, what package it
depends on, what a config file is read by), and the boundary between the `ktalk-registry`
orchestrator and the `ktalk-processor` agent it launches (delegation, and defence against acting
on data fetched under a race). The gate contour that is supposed to enforce this repository's
own GO-criteria is governed here as well: a criterion CLAUDE.md names as mandatory SHALL be
enforced by the automated check, not left to memory.

## Requirements

### Requirement: A release tag resolves in the form the platform expects

A git tag created for a plugin release SHALL name the plugin and its version in the exact form
the platform's own tagging tool produces, so that version constraints declared by other plugins
against this one resolve correctly. A tag that only encodes the bare semantic version, without
the plugin-name prefix the tool prepends, SHALL NOT be treated as the release tag of record.

#### Scenario: The release tag matches the platform's dry-run form

- **WHEN** a release is tagged for a given `plugin.json` version
- **THEN** the tag SHALL be the exact string the platform's tag tool reports for that version and
  that `plugin.json`, not a hand-chosen form that differs from it

### Requirement: The marketplace manifest declares a description

The marketplace manifest (`.claude-plugin/marketplace.json`) SHALL declare a top-level
`description` field, distinct from the per-plugin `description` already present in its `plugins`
entry, so that a marketplace validation run reports no missing-description warning for the
manifest itself.

#### Scenario: Marketplace validation reports no missing-description warning

- **WHEN** the marketplace manifest is validated
- **THEN** the validation SHALL report no warning about a missing marketplace description

### Requirement: The documented update path names every command it takes to move an installed plugin forward

The plugin's own documentation of how to obtain a new release SHALL name every command an
operator needs to run, in order, to move an already-installed copy of the plugin to the newest
published version — not only the command that refreshes the marketplace's local cache. A
documented update path that stops after the cache-refresh step, while the installed plugin
version remains unchanged until a separate command runs, SHALL be treated as incomplete.

#### Scenario: The documented sequence moves an installed copy to the new version

- **WHEN** an operator on an older installed version follows the documented update steps, in the
  order given, against the plugin's real marketplace and installation state
- **THEN** the installed plugin's recorded version SHALL equal the newest published version after
  the documented steps complete, and any step the platform requires afterwards to make the new
  version take effect (such as restarting the session) SHALL be named as well

### Requirement: A file that is a reference, not an agent, is not registered as one

A file that exists to be read by another agent as supporting material — an algorithm detail, a
template, a format specification — SHALL NOT be placed where the platform's agent scanner
registers every file it finds as an independently invocable agent. Renaming such a file or
adding frontmatter to it does not satisfy this Requirement if the file still sits inside a
directory the platform scans as an agent source; only its location decides whether the platform
registers it.

#### Scenario: A reference file does not appear as an agent in the session's tool list

- **WHEN** the plugin ships a file whose purpose is to be read by another agent, not invoked on
  its own
- **THEN** that file SHALL NOT appear as a distinct agent available in an operator's session
  after the plugin is installed

#### Scenario: Every agent-carrying file the platform validates still resolves correctly

- **WHEN** the plugin's remaining agent files are validated after reference files are relocated
- **THEN** every cross-reference from an agent file to its reference material SHALL still resolve
  to an existing path, using the same path convention (`${CLAUDE_PLUGIN_ROOT}`-relative) already
  used elsewhere in that same agent file

### Requirement: Prompt-layer text and metadata do not name a retired package identity

Text and metadata the plugin ships SHALL NOT name a package identity that has been retired,
independently of whether that text sits in a skill, an agent, or a repository metadata file such
as the documentary-circuit configuration or the gate configuration's own comments. The
dependency's identity is authoritative only in `compat.json`; prose anywhere else describes the
dependency by role, not by a literal name that can go stale the next time the dependency is
renamed.

#### Scenario: Repository metadata describing the plugin's dependency names no retired package

- **WHEN** a metadata file that is not part of the operator-facing prompt layer (a documentary-
  circuit configuration, a gate configuration comment) describes the plugin's dependency on an
  external package
- **THEN** that description SHALL NOT name a retired package identity, matching the standard
  already applied to the skill, agent and command files of the prompt layer

### Requirement: README's operational claims match the interface the package actually exposes

A claim in the plugin's README about which interface reads a piece of configuration (a token
file, an environment variable) SHALL name only interfaces the currently shipped package
actually exposes. A claim naming an interface surface the package does not have (an MCP server,
after that surface has been removed) SHALL be corrected to name the interfaces that remain.

#### Scenario: README's token-file claim names only interfaces the package exposes

- **WHEN** README describes which interface reads the token file the onboarding steps create
- **THEN** it SHALL name only interfaces present in the currently shipped package, verified
  against that package's own command surface

### Requirement: Project delegation to `project-curator` is routed through the orchestrator

The `ktalk-processor` agent SHALL NOT attempt to invoke the `project-curator` agent directly.
When a processed meeting touches one or more projects, `ktalk-processor` SHALL record the
affected project ids in its final report and stop there. The `ktalk-registry` orchestrator SHALL
invoke `project-curator` itself, exactly once per orchestration run, after every launched
`ktalk-processor` agent of that run has completed, passing the union of affected project ids
collected from all of their reports. An orchestration run in which no launched processor
reported any affected project SHALL NOT invoke `project-curator` at all.

#### Scenario: A processor agent that touched a project does not call project-curator

- **WHEN** `ktalk-processor` finishes analysing a meeting that touched one or more projects
- **THEN** its final report SHALL list the affected project ids, and the agent SHALL NOT attempt
  to call `project-curator` itself

#### Scenario: The orchestrator invokes project-curator once, after every processor completes

- **WHEN** an orchestration run has launched one or more `ktalk-processor` agents and all of them
  have completed
- **THEN** `ktalk-registry` SHALL invoke `project-curator` at most once for that run, with the
  union of the affected project ids reported by every completed processor of that run

#### Scenario: project-curator is not installed in the host project

- **WHEN** `project-curator` is not installed in the host project
- **THEN** the orchestrator SHALL skip the delegation and note the skip in the run's summary,
  and `ktalk-processor` SHALL still record the affected project ids in its own report regardless
  of whether the orchestrator can act on them

### Requirement: A fetched transcript's identity is verified before it is used

Before `ktalk-processor` builds its analysis on a transcript fetched via `get-transcript`, it
SHALL verify that the fetched content's identifying details (the participants named in it) are
consistent with the participants named in its own launch context for that `recording_id`. A
mismatch on the first fetch SHALL trigger exactly one retry of the same fetch before any other
action. A mismatch that persists after that retry SHALL stop the agent's processing of that
recording — the agent SHALL NOT build or save any analysis, protocol, or vault update from
content whose identity it could not confirm — and SHALL report the mismatch explicitly, naming
both the requested `recording_id` and the participants actually found in the fetched content.

#### Scenario: A matching transcript proceeds without an extra step

- **WHEN** a fetched transcript's participants match the launch context's participants for the
  requested `recording_id`
- **THEN** `ktalk-processor` SHALL proceed to analysis without any additional confirmation step

#### Scenario: A mismatched transcript is retried once

- **WHEN** a fetched transcript's participants do not match the launch context's participants for
  the requested `recording_id`
- **THEN** `ktalk-processor` SHALL re-fetch the same `recording_id` exactly once before taking any
  other action

#### Scenario: A mismatch that survives the retry is a hard stop, not a silent continuation

- **WHEN** the re-fetched transcript still does not match the launch context's participants
- **THEN** `ktalk-processor` SHALL NOT save, write, or otherwise act on the fetched content, and
  its report SHALL state the mismatch explicitly, naming the requested `recording_id` and the
  participants actually found

### Requirement: The GO-criterion gates CLAUDE.md names are enforced automatically

Every check CLAUDE.md names as a GO-criterion for publication SHALL be wired into the
repository's automated gate run, not left to be executed by memory before a release. The
repository's branch-naming discipline SHALL be judged by an explicitly declared profile, not
left undetermined. The repository's gate-delivery basis SHALL be kept close enough to the
installed gate-tooling version that gates already available to the tooling are not silently
absent from what actually runs in this tree.

#### Scenario: The composition and language gates run as part of the automated check

- **WHEN** the repository's automated gate check runs, in either its fast or full profile
- **THEN** it SHALL execute the repository's own composition-boundary check, prompt-language
  check, and onboarding-script test suite as part of that run, and SHALL report their pass/fail
  status alongside the rest of the run's output

#### Scenario: The branch-naming discipline is judged, not undetermined

- **WHEN** the repository's automated gate check evaluates branch-naming discipline
- **THEN** it SHALL judge the tree against an explicitly declared profile, and SHALL NOT report
  the discipline as undetermined for a repository that has decided a branching profile

#### Scenario: The gate-delivery basis is not silently behind the installed tooling

- **WHEN** the repository's gate-delivery basis is inspected against the version of the gate-
  delivering tooling actually installed
- **THEN** a gate the installed tooling already ships SHALL NOT be missing from the repository's
  delivered set solely because the delivery basis was never refreshed after the tooling was
  updated
