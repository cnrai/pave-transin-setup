# OpenPAVE HeyGen MCP Skill

**Doctrine playbook for the HeyGen Remote MCP server** (`https://mcp.heygen.com/mcp/v1/`, bridged in PAVE as `mcp_heygen_*` tools).

This is a doctrine-first skill: its payload is `SKILL.md` plus per-product-area doctrine under `skills/` — verified operational knowledge for the HeyGen MCP bridge — with a dependency-free Node.js CLI, a diagnostic probe (`probe/heygen-probe.mjs`), an OAuth stepper (`tools/oauth-stepper.mjs`), and an orchestration brief (`orchestration/brief.template.md`).

## CLI for Debian sandboxes

The CLI exposes the remote MCP server without registering all 114 tool schemas with the agent. OAuth uses a persistent, headed `agent-browser` session inside the sandbox. It captures the loopback redirect URL from the browser, so **no local callback HTTP server is required**.

### Install

```bash
npm i -g agent-browser
agent-browser install --with-deps
npm install -g .
```

Node.js 18 or newer is required. On a displayless Debian host, `agent-browser --headed` starts Xvfb automatically; do not disable it for HeyGen login.

### Login

The agent runs these commands. The user does not need shell access.

First ask the user for their HeyGen account email. Do not assume an address from a previous session, a file, or an example.

```bash
# 1. Start OAuth and request one magic link.
heygen-mcp login --email "<user's HeyGen account email>"

# 2. Copy the link address from the NEWEST HeyGen email and pass it to the
# sandbox browser through stdin. Do not open it in the user's local browser.
heygen-mcp login --magic-link < magic-link.txt

# 3. Only if HeyGen presents the plan picker, after the user chooses a plan:
heygen-mcp login --plan free
```

Remove `magic-link.txt` immediately after use. A magic link is a single-use credential. Request only one link; each resend invalidates earlier links. Clicking it only on the user's own computer does not authenticate the browser inside the sandbox; its URL must be opened by the sandbox browser. If HeyGen presents an interactive CAPTCHA, stop and arrange manual access to the sandbox browser rather than bypassing it.

The CLI exits with status `7` when a plan choice is required. `free`, `creator`, and `pro` are accepted only in the separate `login --plan` invocation, after the picker appears. Paid plans require the user's explicit approval. HeyGen authorization state can expire in about 13 minutes, so the CLI creates a fresh authorization after magic-link redemption and again before the plan-selected tail. Tokens are stored in `~/.heygen-mcp/tokens.json` with mode `0600`; refresh is automatic. Pending login state is stored separately with mode `0600` and removed after success. Do not run the old OAuth bridge on port `49153` at the same time.

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

The CLI login and MCP flows have passed an automated mock-server smoke test. Live HeyGen login through `agent-browser` is not yet verified; the existing Playwright lane below remains the verified fallback.

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
