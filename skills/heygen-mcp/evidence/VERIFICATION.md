# Verification Ledger

Environment: disposable free-tier test account · server: heygen-mcp v1.30.0
Method: committed probe (`probe/heygen-probe.mjs`) with a temporary token file
(`HEYGEN_TOKEN_FILE`); every call through `https://mcp.heygen.com/mcp/v1`.
No paid calls were made.

| # | Tool | Result | Notes |
|---|---|---|---|
| 1 | `get_current_user` | verified | email + plan fields; stringified payload confirmed |
| 2 | `tools/list` | verified | 114 tools; snapshot committed (`schemas/snapshot-2026-11-12.json`) |
| 3 | `list_video_agent_styles` | verified | style items with thumbnails/previews |
| 4 | `list_templates` | verified | empty on the test account (expected) |
| 5 | `search_audio_sounds` | verified | music tracks with S3 audio URLs |
| 6 | `list_voices` | verified | one transient `fetch failed`, retry OK — edge flakiness |
| 7 | `create_speech` | verified | turbo-free model + public voice → WAV URL |
| 8 | `create_folder` / `get_folder` | verified | create/read round-trip OK |
| 9 | `create_asset_upload` → S3 PUT → `complete_asset_upload` → `get_asset` | verified | full §4.4 runbook |
| 10 | `create_prompt_avatar` | verified | group_id == look_id for prompt avatars; preview null → ready in about 90 s |
| 11 | `list_avatar_looks` | verified | resolves looks from group |
| 12 | `get_avatar_creation_status` | verified | **semantic quirk**: returns "No avatar creation is in progress" when idle — it tracks the guided creation flow, not look rendering. Use `list_avatar_looks` preview state for readiness |
| 13 | `create_video_agent` | verified | generation completed; short MP4 delivered through `get_video`; thinking → generating → completed |

## Headline result

The full generate chain was exercised on a free-tier test account:
prompt avatar (`create_prompt_avatar`) → readiness via `list_avatar_looks`
→ public voice (`list_voices`) → `create_video_agent` (mode `generate`,
camelCase `avatarId`/`voiceId`/`orientation`) → poll
`get_video_agent_session` → `get_video` → working presigned MP4 URL.
One transient HTTP 502 from the bridge during polling was retried successfully.

## Runbook lessons folded into doctrine

1. **Field naming is per-tool — read the schema before every first call.**
   `create_asset_upload` requires `filename`, `contentType` (camelCase),
   `sizeBytes`; the error message calls it `content_type`. The response field
   is `upload_headers` (not `headers`).
2. **Asset uploads accept media types only** — `text/plain` is refused with
   `invalid_parameter`; use image/video/audio MIME types.
3. **The bridge surfaces real error text** — failures arrive in
   `structuredContent` with `message`, `error_code`, `doc_url`, and
   `next_steps`.
4. **Argument validation errors are explicit**: `invalid_arguments` with the
   missing field named (`sizeBytes: Field required`).
5. Video Agent params are camelCase: `avatarId`, `voiceId`, `styleId`,
   `brandKitId`, `orientation`; only `prompt` is required.

## Relay verification

Both relay completion lanes were exercised successfully: the bridge lane and
the PAVE native relay lane. The native relay flow was:

1. Install the skill package.
2. Add the remote MCP server and complete the permission grant.
3. Run PAVE's `oauth/start`, approve consent, relay the loopback callback URL,
   and let PAVE perform the PKCE exchange.
4. Confirm the MCP entry is installed and tokens are stored with mode `0600`.
5. List the tool catalog and call `get_current_user` through the bridge.

## PAVE Connect extension

- **Tab capture: PASS.** After loopback navigation failed, the extension
  captured the callback and rendered its fallback page.
- **Relay path: PASS.** A mock relay received `{code, state, callback_url}`
  and answered `200 {installed:true}`. A double-fire case informed idempotency
  guidance.
- **Fallback preservation: PASS.** With no relay configured, the copy-page lane
  remains available.
- Firefox manifest is provided but untested. Safari packaging requires macOS.

## HyperFrames MCP server

- Separate MCP resource: `https://mcp.heygen.com/mcp/hyperframes/`
  (`heygen-mcp-hyperframes` v1.30.0, 18 tools; snapshot committed).
- One OAuth token spans all `mcp.heygen.com` resources; it is not
  audience-locked to the path that minted it.
- Tool families include project composition, renders, Claude-Design imports,
  project CRUD, and internal widget/player/analytics tools. Never call the
  internal tools from PAVE.
- The server was API-only when first documented, then promoted onto the bridge
  without an announcement.

## `browser:handoff` scope

The host-level PRM advertises `browser:handoff`. Testing showed the same
loopback redirect and dead tab as the default scope: no handoff page, rendered
code, or behaviour change. The scope serves HeyGen's widget/player handoff,
not cloud-agent OAuth.

## Hosted-browser lane

- A persistent browser profile was reused across runs and authenticated
  successfully.
- `chrome-headless-shell` is Turnstile-detected. Full Chromium headed under
  Xvfb is required. A later run also showed an interactive widget on some
  hosts; stop for the user rather than bypassing it.
- Magic-link protocol: send once, never click the email button in another
  browser, copy the newest link address, and expect single-use semantics.
- Renewal ladder: refresh token → OAuth result check → consent in the persistent
  profile → magic-link re-bootstrap when the browser session is gone.

## Hosted-browser consent leg

The full OAuth consent runs inside the hosted Playwright profile with no user
browser involved. Sequence:

`capabilities_add` → `pending_oauth` → permission grant → `oauth/start` →
authorize URL → email form → magic-link paste → consent → plan picker →
finish → callback → installed → token stored → tool catalog → authenticated
`get_current_user`.

## Findings folded into doctrine

1. **Headless bot detection extends beyond `chrome-headless-shell`.**
   Playwright `launchPersistentContext` with `headless: true` received `403`
   on the magic-link POST and a "flagged for suspicious activity" toast.
   Full Chromium headed under Xvfb was required.
2. **Magic-link semantics.** The link authenticates the requesting browser
   profile. The redeemed page may say "Return to your original tab"; navigate
   the authorize URL again to reach consent.
3. **State lifetime varies by host.** Observed lifetimes ranged from roughly
   13 to 35 minutes. Run the consent tail promptly after `oauth/start`.
4. **Plan-picker interstitial is billing consent.** Always relay it to the
   user; click a plan only when its name is explicitly supplied.
5. **Root installs can be refused.** Follow the host's documented local
   install and system-dependency procedure.

## Renewal-lane corrections

1. **Turnstile may be interactive.** A headed browser can still hang at
   "Sending…" with no `magic_link` POST. The widget iframe may sit inside a
   shadow root. The committed stepper fails loudly instead of pretending the
   email was sent. Do not bypass the challenge; ask the user to intervene.
2. **Do not split the OAuth tail across long delays.** State can expire while
   the user is choosing a plan. Re-run `oauth/start` and finish the consent tail
   immediately.
