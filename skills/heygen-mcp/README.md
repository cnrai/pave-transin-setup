# OpenPAVE HeyGen MCP Skill

**Doctrine playbook for the HeyGen Remote MCP server** (`https://mcp.heygen.com/mcp/v1/`, bridged in PAVE as `mcp_heygen_*` tools).

This is a doctrine-first skill: its payload is `SKILL.md` plus per-product-area doctrine under `skills/` — verified operational knowledge for the HeyGen MCP bridge — with a dependency-free Node.js CLI, a diagnostic probe (`probe/heygen-probe.mjs`), an OAuth stepper (`tools/oauth-stepper.mjs`), and an orchestration brief (`orchestration/brief.template.md`).

## CLI for Debian sandboxes

The CLI exposes the remote MCP server without registering all 114 tool schemas with the agent. OAuth uses a persistent, headed `agent-browser` session inside the sandbox. During the authorization tail, the CLI starts a short-lived loopback listener inside the sandbox, captures `code` and `state` at the socket, responds once, and closes the listener. This avoids Chromium replacing the failed callback with `chrome-error://chromewebdata/`. No callback server is needed on the user's machine.

### Install and preflight

```bash
npm i -g agent-browser
agent-browser install --with-deps
sudo apt-get update && sudo apt-get install -y xvfb xfonts-base
npm install -g .
heygen-mcp doctor
```

Node.js 18 or newer is required. A headed browser on displayless Debian still needs the system `xvfb` package; `agent-browser install --with-deps` alone did not install it in the verified sandbox. `heygen-mcp doctor` reports Node, `agent-browser`, `DISPLAY`/`Xvfb`, callback-port availability, token, and pending-login state with an exact fix for each failure.

### Login with a user-owned magic link

This is the preferred sandbox flow. The user solves any CAPTCHA in their own browser, so the sandbox never sends the login email.

Give the user these instructions:

1. Open `https://app.heygen.com` in a private window.
2. Choose **Use email**, enter the HeyGen account email, and choose **Send a secure magic link** once.
3. Complete **Verify you are human** personally if it appears.
4. Open the newest HeyGen email, right-click the button, and choose **Copy link address**. Do not click the button: the link is single-use and must be consumed by the sandbox browser.
5. Paste the copied link into the chat.

The agent then runs:

```bash
# Read the link from stdin so it does not appear in CLI arguments.
heygen-mcp login --magic-link < magic-link.txt

# Only after the user chooses a plan and the CLI reports plan_required:
heygen-mcp login --plan free

heygen-mcp whoami
```

Remove `magic-link.txt` immediately. Both `https://app.heygen.com/magic-web/...` and the newer `https://auth.heygen.com/magic-web/...` links are accepted. A successful redemption may land on `https://app.heygen.com/home` instead of showing the older "Return to your original tab" page; both are accepted.

`heygen-mcp login --email <address>` remains available only when the user can interact with the sandbox browser to solve the CAPTCHA. Do not use it as a blind background step.

If `agent-browser` reports `Resource temporarily unavailable` or “no response came back”, the daemon may or may not have run the command. Run `heygen-mcp doctor`. If the browser is already on `app.heygen.com/home`, run `heygen-mcp login --resume` to continue with fresh OAuth state. Otherwise request one new magic link.

The CLI exits with status `7` when a plan choice is required. `free`, `creator`, and `pro` are accepted only in the separate `login --plan` invocation, after the picker appears. Paid plans require the user's explicit approval. HeyGen authorization state can expire in about 13 minutes, so the CLI creates a fresh authorization after magic-link redemption and again before the plan-selected tail. Tokens are stored in `~/.heygen-mcp/tokens.json` with mode `0600`; refresh is automatic. Pending login state is stored separately with mode `0600` and removed after success. The CLI owns the loopback callback port only during the authorization tail; `doctor` verifies that it is free. Do not run the old OAuth bridge on the same port concurrently.

The callback listener is part of OAuth's normal loopback flow. It accepts only a top-level document navigation to the expected origin and path, with the expected OAuth `state` and a non-empty `code` or OAuth `error`; other requests get `400`. It keeps the latest valid candidates, uses them only after the browser reports a callback or `chrome-error://`, and tries another candidate if the browser URL or a code exchange fails. It records no token file, writes authorization codes only to process memory, and closes in a `finally` block even when login exits with a plan gate or error.

### Use MCP tools on demand

```bash
heygen-mcp tools                              # names and short descriptions
heygen-mcp schema create_video_agent          # one full schema, only when needed
heygen-mcp call get_current_user '{}'
heygen-mcp call create_video_agent @args.json
heygen-mcp whoami
```

Tool results with `isError: true` are printed and return CLI exit status `2`. `tools --json` emits the full large catalog for external tooling; agents should normally use compact `tools` followed by one `schema` call.

All existing safety fences still apply. Paid generation calls require the platform/cost disclosure and any approval required by the host doctrine. Subscription actions (`cancel_subscription`, `show_subscription_action`, and `continue_subscription_cancellation`) require an explicit user request and a final confirmation. Never use the generic `call` command to bypass those gates.

The CLI OAuth/MCP flows pass automated mock-server tests. A real sandbox session on 2026-11-17 completed a user-owned `auth.heygen.com` link, consent, plan selection, token exchange, and `whoami` using a small loopback responder because Chromium hid the failed callback URL. That responder is now built into the CLI; the built-in path is mock-verified and still deserves a second live run.

## PAVE skill install

```
pave install johnmak101-ops/openpave-heygen-mcp
```

Then read the doctrine from any PAVE session:

```
skill_docs(skill="heygen-mcp")
```

## What's inside

| Path | What it is |
|---|---|
| `SKILL.md` | Doctrine index, install runbook, verification ledger, bridge-wide rules |
| `skills/heygen-video-agent/` | Video Agent sessions (one-shot + multi-turn generation) |
| `skills/heygen-classic-video/` | Classic editor video creation (avatar/image/studio/cinematic), scenes |
| `skills/heygen-avatar/` | Avatar groups, looks, creation (prompt/photo/digital twin), consent |
| `skills/heygen-voice/` | Voices, speech (TTS), audio catalog |
| `skills/heygen-models/` | Model-first generation: text/image/reference-to-video, look remix, images |
| `skills/heygen-translate/` | Video translation |
| `skills/heygen-lipsync/` | Standalone lipsync jobs |
| `skills/heygen-clipping/` | AI clipping |
| `skills/heygen-filler-words/` | Filler word removal |
| `skills/heygen-templates/` | Templates and variable-driven generation |
| `skills/heygen-brand/` | Brand kits and brand glossaries |
| `skills/heygen-assets/` | Assets, direct-to-S3 upload, upload batches, folders |
| `skills/heygen-batches/` | Video / translation / lipsync batch operations |
| `skills/heygen-account/` | Account state, with hard-fenced subscription tools |
| `cli/` | Dependency-free CLI with hosted-browser OAuth, token refresh, and on-demand MCP calls |
| `probe/heygen-probe.mjs` | Token-safe JSON-RPC diagnostic probe |
| `tools/oauth-stepper.mjs` | Playwright driver for the hosted-browser OAuth lane (login → magic link → consent → plan pick → callback); refuses headless runs |
| `orchestration/brief.template.md` | A/B orchestrated-install brief |

## Two connection lanes (decision 2026-11-12)

1. **API-key lane (primary)** — paste a HeyGen API key once; PAVE calls the
   v3 REST API directly. No OAuth geometry. Verified 2026-11-12.
2. **MCP lane (alternative)** — the remote MCP server over OAuth. Consent is
   driven by `tools/oauth-stepper.mjs` in a hosted Playwright browser
   (headed under Xvfb — headless is Turnstile-flagged; on some hosts the
   widget is interactive, not invisible), verified end to end 2026-11-12
   with a single user paste (the magic-link URL). Bridge and paste-URL
   relay lanes remain as fallbacks.

See `SKILL.md` §0 for the full doctrine and §9.4 for the lane runbooks.

## Verification status

Every doctrine claim carries a tag: `[verified <date>]` (tested live), `[bridge snapshot <date>]` (from a live `tools/list` schema dump), or `[unverified]` (from upstream docs, not yet reproduced). Live surface verified 2026-11-12: **114 tools** on `heygen-mcp` v1.30.0 — upstream docs claim ~88; trust the probe, not the docs. The running ledger is `evidence/VERIFICATION.md`.

## Maintenance

Quarterly (or when the bridge behaves oddly):

```bash
node probe/heygen-probe.mjs tools/list > /tmp/tools-now.txt          # count tools
diff <(node -e "const s=require('./schemas/snapshot-2026-11-12.json');console.log(s.tools.map(t=>t.name).sort().join('\n'))") \
     <(grep '^- ' /tmp/tools-now.txt | sed 's/^- \([^:]*\):.*/\1/' | sort)   # what changed
```

New tools → write doctrine for them before use. Missing tools → check
[HeyGen's changelog](https://developers.heygen.com/changelog.md) and the
[official skills repo](https://github.com/heygen-com/skills) for intent
before assuming removal. Also watch that repo's releases — its skills are the
upstream wedge this playbook ports.

## License

MIT
