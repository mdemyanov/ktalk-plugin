# dual-channel-delivery

## Purpose

Governs what a consumer observes across the plugin's two delivery channels — the internal
GitLab marketplace (source of truth) and the public GitHub mirror (a one-way, release-triggered
copy of the payload) — so that a consumer who reaches either channel can tell which one it is,
trust that what the two channels carry for the same release is the same thing, tell a lagging
mirror from a version that was never released, and find no internal-infrastructure literal in
what is published publicly. It also governs how an input arriving through the public channel (an
issue, a pull request) enters the project, since that channel did not previously exist.

## Requirements

### Requirement: The two channels declare distinguishable marketplace identities

A consumer who adds both the internal marketplace and the public mirror's marketplace to the same
Claude Code installation SHALL be able to tell them apart by the declared marketplace name alone.
The two channels' `marketplace.json` `name` fields SHALL NOT be identical.

#### Scenario: A consumer adds both channels' marketplaces

- **WHEN** an operator has already added one channel's marketplace and adds the other channel's
  marketplace under the same Claude Code profile
- **THEN** the two marketplace records SHALL carry distinct `name` values, so that neither add
  operation silently overwrites or masks the other's entry

### Requirement: Cross-channel parity is a checkable fact, not a claim

For any commit tagged as a release, the plugin version, the `compat.json` pin, and the set of
files that make up the shipped payload SHALL be identical between the two channels for that
release. A mirrored tree that carries a different `plugin.json` version, a different `compat.json`
pin, or a payload file set with additions or omissions relative to the same-tagged internal
release SHALL be treated as a mirror defect, not a channel-specific customization.

#### Scenario: Comparing a mirrored release against its source

- **WHEN** a release tag exists on both the internal GitLab repository and the public GitHub
  mirror
- **THEN** `.claude-plugin/plugin.json` version, `compat.json` contents, and the payload file
  listing SHALL be identical between the two tagged trees

### Requirement: Documentation names each channel and how to tell them apart

The plugin's installation documentation SHALL name both delivery channels, state which one is the
source of truth and which is a one-way mirror, and give the install/update command for each
channel separately. A single documented installation path that does not distinguish channels
SHALL be treated as incomplete once a second channel exists.

#### Scenario: An operator reads the installation instructions

- **WHEN** an operator opens the plugin's installation documentation after the second channel
  exists
- **THEN** the documentation SHALL name both channels explicitly, state that the internal GitLab
  is authoritative and the GitHub mirror is one-way, and give a separate install command for each

### Requirement: A consumer can tell "mirror lags" from "version does not exist"

The public mirror's published tags SHALL name exactly the release versions that have already been
pushed to it, and SHALL NOT claim currency with the internal marketplace beyond the versions
actually present on it. A consumer who does not find a given version's tag on the mirror SHALL be
able to determine, from the mirror's own visible state, whether that version has simply not been
mirrored yet or was never released at all, without contacting the plugin owner.

#### Scenario: A version was released internally but not yet mirrored

- **WHEN** a version has a release tag on the internal GitLab repository but no corresponding tag
  yet exists on the GitHub mirror
- **THEN** the GitHub mirror's own latest tag SHALL be lower than the requested version, so that
  "not yet mirrored" is distinguishable from "no such version was ever released"

### Requirement: The public payload carries no internal infrastructure literal

No file published to the public channel SHALL contain the internal GitLab domain or any other
literal naming the internal-only source-of-truth infrastructure. The repository's composition gate
SHALL fail with a non-zero exit code if such a literal is found in any file destined for the
public payload.

#### Scenario: The composition gate scans for the internal domain

- **WHEN** the plugin composition gate runs against the set of files destined for the public
  payload
- **THEN** it SHALL report a failure and a non-zero exit code if the internal GitLab domain
  literal is present in any of those files

### Requirement: Input arriving through the public channel is triaged manually

An issue or pull request opened on the public GitHub mirror SHALL receive an acknowledgement that
the project's source of truth is the internal GitLab, and SHALL NOT be merged or closed by any
automated synchronization. An issue accepted for work SHALL be re-entered into the internal
backlog by a person, carrying a link back to the public issue; no mechanism SHALL perform that
transfer, or close the public issue as resolved, without that manual step.

#### Scenario: An issue is opened on the public mirror

- **WHEN** a new issue is opened on the public GitHub mirror repository
- **THEN** it SHALL be acknowledged, and, if accepted, re-entered into the internal backlog by a
  person with a link back to the original issue — no automated process SHALL perform this transfer
