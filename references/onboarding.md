# Onboarding: the ktalk-mcp package

This file is read when `scripts/ktalk-onboard.sh check` returns a non-zero code. Token values
are never requested, printed or written anywhere here — only the fact of configuration is
checked.

Everything shown to the operator stays Russian; the instructions are English (ADR-021 D1).

## Code 10 — the package is not installed

Show the user the command verbatim and **do not run it yourself**:

    uv tool install ktalk-mcp

Verification after installation: `which ktalk-mcp` or `ktalk --help`.

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

`uv` is missing, not `ktalk-mcp`. The plugin does not install `uv`. Tell the user that `uv`
needs to be installed (https://docs.astral.sh/uv/) and repeat the check.

## Code 11 — version below the minimum

Report the installed version and the minimum version. An upgrade is a separate sanction:

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/ktalk-onboard.sh grant update
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/ktalk-onboard.sh install

The user runs the first command. The agent never runs it: without a terminal it refuses
(code 33). The agent runs the second one only after the upgrade sanction has been granted.

After `install`, repeat `check`. `uv tool upgrade` prints "Nothing to upgrade" with exit
code 0 when the index holds no newer version: `install` then also returns 11 and the version
stays as it was. Repeating the installation in that case is pointless — tell the user that
the index holds no compatible version.

Work can continue: a version mismatch is a warning, not a blocker. Some scenarios may not
work.

## Code 20 — internal plugin error

The plugin's `compat.json` was not read: the file is missing, unreadable, or holds no
`ktalk_mcp_min_version` key. The minimum version is unknown and there is nothing to check
against. The action is to reinstall the plugin (`/plugin marketplace update ktalk-plugins`,
then `/plugin install ktalk@ktalk-plugins`). The `message` field in the JSON carries the same
action verbatim.

## Authorisation

Two modes are supported; the value is held by the environment, not by the plugin:

- `KTALK_PERSONAL_API_KEY` — a personal API key, sent in the `X-Auth-Token` header;
- `KTALK_SESSION_TOKEN` — a session token, sent in the `sessionToken` parameter.

If both are set, `KTALK_PERSONAL_API_KEY` wins and the session token is not read.

Where to get them: the personal API key — from the user profile in the Kontur Talk interface;
the session token — from an active web-client session. Where to put them: an environment
variable of the Claude Code process, or the host project's `.mcp.json` / `settings.json`.
**Not** in a file inside the plugin tree, and not in `.ktalk.toml`.

Checking the mode: `ktalk auth-status --json` — it prints the selected mode, never the secret
value. Never ask for a token value to be pasted into the chat, and never print one.
