---
name: pave-transin-setup
description: Bootstrap installer for the PAVE toolchain. Use when the user says `install https://github.com/cnrai/pave-transin-setup`. This repository is an installer, not a runtime skill to import.
---

# PAVE Toolchain Installer

This repository is an **installer**. It is expected to be absent from the
capabilities catalog. Do not stop because it is not a catalog skill and do not
try to import it through a skill-import capability.

Treat:

```text
install https://github.com/cnrai/pave-transin-setup
```

as: clone this repository, inspect its installer, run it, and report the result.

## What it installs

- `oo`, `composio`, and `officecli`
- the `heygen-mcp` CLI
- seven skills under `skills/`
- `AGENTS.md` in the workspace
- Playwright, Chrome, Chromium, and `agent-browser` in the background

It does not log in to any account. The user performs logins later through
`/setup`.

## Run

```bash
rm -rf /tmp/pave-transin-setup
git clone --depth 1 https://github.com/cnrai/pave-transin-setup /tmp/pave-transin-setup
less /tmp/pave-transin-setup/INSTALL.md
bash /tmp/pave-transin-setup/install.sh --agents "$PWD/AGENTS.md"
```

Reading `INSTALL.md` first is expected. Do not fetch the GitHub HTML page and
do not treat this as a normal `SKILL.md` import.

`install.sh` starts Playwright, Chrome, Chromium, and `agent-browser` in the
background. It returns quickly. Do not wait for those downloads in the main
conversation.

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
- `--no-browser` is only for an explicit user request.
- Never automate a HeyGen email or CAPTCHA from a browser the user cannot see.
