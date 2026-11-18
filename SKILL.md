---
name: pave-transin-setup
description: Bootstrap installer for the PAVE toolchain. Use when the user says `install https://github.com/cnrai/pave-transin-setup`. This repository is an installer, not a runtime skill to import.
---

# PAVE Toolchain Installer

This repository is an **installer**. Some skill catalogs do not list it; that is expected. The root `SKILL.md` and `INSTALL.md` describe the setup. Review the scripts and ask the user before executing anything you are unsure about.

Treat:

```text
install https://github.com/cnrai/pave-transin-setup
```

as: clone this repository, inspect its installer, run it, and report the result.

## What it installs

- `oo`, `composio`, and `officecli`
- the `heygen-mcp` CLI
- seven skills under `skills/`
- Playwright, Chrome, Chromium, and `agent-browser` in the background

`AGENTS.md` is opt-in: it is written only when you pass `--agents <path>`, and
only after the user has seen its contents.

It does not log in to any account. The user performs logins later through
`/setup`.

## Run

```bash
rm -rf /tmp/pave-transin-setup
git clone --depth 1 https://github.com/cnrai/pave-transin-setup /tmp/pave-transin-setup
less /tmp/pave-transin-setup/INSTALL.md
bash /tmp/pave-transin-setup/install.sh --dry-run   # what would happen
bash /tmp/pave-transin-setup/install.sh             # do it
```

`install.sh` prints a summary table at the end (`ok` / `skip` / `fail` /
`plan` / `running`) and exits 1 when a step failed. Report that table as-is.

Writing `AGENTS.md` rewrites the global rules for every future session. Only do
it on request, and show the content first:

```bash
bash /tmp/pave-transin-setup/install.sh --print-agents
bash /tmp/pave-transin-setup/install.sh --agents "$PWD/AGENTS.md"
```

Reading `INSTALL.md` first is expected. Do not fetch the GitHub HTML page and
do not treat this as a normal `SKILL.md` import.

`install.sh` starts Playwright, Chrome, Chromium, and `agent-browser` in the
background. It returns quickly. Do not wait for those downloads in the main
conversation.

If the Bash sandbox blocks network or apt, or only permits filesystem/Node
operations, run `install.sh --no-network`. Report which CLIs are already
present and which must be installed later in a network-enabled shell. Do not
retry a command that already timed out.

## Monitor without blocking

Immediately start a background sub-session and have it run:

```bash
bash /tmp/pave-transin-setup/browser-install-wait.sh
```

That command returns as soon as the state is `done`, `partial`, or `failed`.
It does not use a fixed timer. Report the real result and log errors from
`~/.pave/browser-install/install.log`.

## Verify

```bash
bash /tmp/pave-transin-setup/verify.sh
```

`WAIT` means the background browser install is still running. `MISS` means a
required tool is missing. Installing is not the same as logging in.

## Safety

- Review `install.sh`, `INSTALL.md`, and the two browser-install scripts before
  running them.
- Do not ask for or store passwords, tokens, cookies, or API keys.
- Do not write `AGENTS.md` without the user's explicit consent.
- `--no-browser` is only for an explicit user request.
- Never automate a HeyGen email or CAPTCHA from a browser the user cannot see.
- Before pushing, run `bash secret-scan.sh --history` and fix any finding.
