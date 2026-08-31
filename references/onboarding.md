# Onboarding: the ktalk-cli package

The package was renamed from `ktalk-mcp` to `ktalk-cli` (ADR-024); `compat.json` names the
current pin as a `package_name`/`package_version` pair, not a single version under a
package-specific key. Any mention of `ktalk-mcp` below that is not explicitly about the retired
identity refers to history, not the current pin.

This file is read when `scripts/ktalk-onboard.sh check` returns a non-zero code. Token values
are never requested, printed or written anywhere here — only the fact of configuration is
checked.

Everything shown to the operator stays Russian; the instructions are English (ADR-021 D1).

## Code 10 — the package is not installed

Show the user the command `check` printed verbatim and **do not run it yourself** — it names
the pinned package and version explicitly (`uv tool install ktalk-cli==<pin>`), not a bare
package name that would resolve to whatever is newest.

Verification after installation: `which ktalk` or `ktalk --help`.

If the user is willing to let the plugin install it, the sanction is granted by the user
themselves, in their own terminal:

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/ktalk-onboard.sh grant install

The user runs this command. The agent never runs it: without a terminal it refuses (code 33).
Once the sanction is granted, the installation is performed by
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/ktalk-onboard.sh install`.

After `install`, repeat `check`: exit code 0 from `install` means only that the package
manager did its job and the version matched; any other code (including 11 — a version below
the minimum was installed) is handled by this same file.

`install` can return **10** even after the package manager finished without error: `uv` puts
the binary in its own tools directory (usually `~/.local/bin`), which is not always on the
process `PATH`. In that case the `install` message names the cause directly —
`команда ktalk не резолвится через PATH` — and offers to add uv's tools directory to `PATH`.
This is not an
installation failure: the package is installed and `uv tool list` sees it, but `ktalk …` still
cannot be executed in the current session. After fixing `PATH` (a new shell session or
`export PATH=...`) — run `check` again.

## Code 12 — no uv

`uv` is missing, not the pinned package. The plugin does not install `uv`. Tell the user that
`uv` needs to be installed (https://docs.astral.sh/uv/) and repeat the check.

## Code 11 — installed version differs from the pin (same package)

The plugin pins one exact package identity — name and version — in `compat.json` (ADR-022,
ADR-024). When the installed package's **name already matches** the pin but its version does
not, either older **or newer** than the pin, that is reported the same way, code 11. The remedy
is a separate sanction (`allow_update`) either way: under an exact pin, "newer" is not
automatically safe to overwrite — it may be a version someone installed on this machine for an
unrelated task, and the remedy command reinstalls exactly the pin, which is a downgrade in that
case.

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/ktalk-onboard.sh grant update
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/ktalk-onboard.sh install

The user runs the first command. The agent never runs it: without a terminal it refuses
(code 33). The agent runs the second one only after the update sanction has been granted.
The install/update sanctions are not merged into one: installing where nothing existed
creates state, while remedying an existing installation mutates state that may belong to
someone else's unrelated task — the two are gated separately on purpose.

After `install`, repeat `check`. `uv tool install` prints "Already installed" with exit
code 0 when the index already holds that exact version under a different local state (a
stale cache, a reinstall of the same artifact): `install` then re-reads the version and still
returns 11 if it did not actually change. Repeating the installation in that case is
pointless — tell the user that the index does not offer the pinned version right now.

Work can continue: a version mismatch is a warning, not a blocker. Some scenarios may not
work.

## Code 13 — installed package is not the pinned package

The command name `ktalk` resolves, but the package providing it is not the one `compat.json`
pins by name (ADR-024) — for example `ktalk-mcp` is active while the pin names `ktalk-cli`, or
vice versa after a rollback. This is reported separately from code 11 on purpose: "wrong
package" and "right package, wrong version" call for different remedies, and conflating them
would hide which one applies. The `check`/`install --json` output names both the active package
and the pinned one explicitly. The remedy is the same command as code 11
(`grant update` then `install`) — ADR-024 `D3` reuses the existing update sanction rather than
adding a new one, since "the command already points at something else" already covers a
different package, not only a different version of the same one.

## Code 34 — the command-name slot is already claimed by the other package

`uv tool install` refused (exit code 2, "Executable already exists") because the other known
package identity already provides the `ktalk` command on this machine. The plugin **never**
retries with `--force` — not on the default flow, not under any sanction — because that would
be exactly the silent takeover the rename's collision requirement forbids. The message names
both the package that was being installed and, where determinable, the one currently holding
the slot. Resolving the collision is a deliberate, manual operator action, typed by hand in a
terminal — not a plugin command and not something an agent should run without being asked
explicitly:

    uv tool install <target-package>==<target-pin> --force

After running it by hand, run `check` again in the **same shell session** — `hash -r` may be
needed if the shell cached the previous binary's path.

## Code 20 — internal plugin error

The plugin's `compat.json` was not read: the file is missing, unreadable, or is missing either
of the two pin fields it needs — `package_name` and `package_version` (ADR-024 D1). This
includes a `compat.json` that still only carries a retired key from before either rename
(`ktalk_mcp_version`, or the earlier `ktalk_mcp_min_version`) — both fields are required
together, so a leftover single-field pin from an older plugin version is treated the same as no
pin at all. The pinned identity is unknown and there is nothing to check against. The action is
to reinstall the plugin (`/plugin marketplace update ktalk-plugins`, then `/plugin install
ktalk@ktalk-plugins`). The `message` field in the JSON carries the same action verbatim.

## Retired MCP tools — CLI equivalents

The plugin declares no MCP server (ADR-022 D1): no `mcp__ktalk__*` tool is available to an
operator's session as a side effect of installing this plugin. An operator who used to call
one of those tools directly (outside any skill, ad hoc in a chat turn) reaches the same
outcome through the CLI subcommand that already covers it:

| Retired MCP tool | CLI equivalent |
|---|---|
| meeting-creation preview | `ktalk create-meeting-preview` |
| meeting-cancellation preview | `ktalk cancel-meeting-preview` |
| `ktalk_get_summary_by_type` | `ktalk get-summary-type` |

The first two rows are named by role, not by the retired tool's literal identifier: those two
identifiers are among the literals `scripts/check-plugin-composition.sh` forbids anywhere in
the plugin tree (the `"MCP-имя операции встреч вместо CLI"` check label), including in
documentation.

## Authorisation

Two modes are supported; the value is held by the environment, not by the plugin:

- `KTALK_PERSONAL_API_KEY` — a personal API key, sent in the `X-Auth-Token` header;
- `KTALK_SESSION_TOKEN` — a session token, sent in the `sessionToken` parameter.

If both are set, `KTALK_PERSONAL_API_KEY` wins and the session token is not read.

Where to get them: the personal API key — from the user profile in the Kontur Talk interface;
the session token — from an active web-client session. Where to put them: an environment
variable of the Claude Code process, or the host project's `settings.json`. The plugin declares
no MCP server (ADR-022 D1), so there is no `.mcp.json` env block to put them in either the
plugin's or the host project's tree. **Not** in a file inside the plugin tree, and not in
`.ktalk.toml`.

Checking the mode: `ktalk auth-status --json` — it prints the selected mode, never the secret
value. Never ask for a token value to be pasted into the chat, and never print one.
