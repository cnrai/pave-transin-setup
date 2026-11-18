import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { AgentBrowser } from "./agent-browser.mjs";

export class LoginRequiredError extends Error {
  constructor(message, exitCode = 1) {
    super(message);
    this.exitCode = exitCode;
  }
}

export function getConfig(env = process.env) {
  const home = env.HEYGEN_CONFIG_HOME || path.join(os.homedir(), ".heygen-mcp");
  return {
    authBaseUrl: env.HEYGEN_AUTH_BASE_URL || "https://api2.heygen.com",
    clientId: env.HEYGEN_CLIENT_ID || "an1xhCM552m7m1AuY7hLlwzM",
    mcpUrl: env.HEYGEN_MCP_URL || "https://mcp.heygen.com/mcp/v1",
    redirectUri: env.HEYGEN_OAUTH_REDIRECT_URI || "http://127.0.0.1:49153/callback",
    resource: env.HEYGEN_RESOURCE || "https://mcp.heygen.com/mcp/v1",
    tokenFile: env.HEYGEN_TOKEN_FILE || path.join(home, "tokens.json"),
    pendingFile: env.HEYGEN_PENDING_FILE || path.join(home, "pending-login.json"),
    browserCommand: env.HEYGEN_AGENT_BROWSER || "agent-browser",
  };
}

export function createAuthorization(config) {
  const verifier = crypto.randomBytes(48).toString("base64url");
  const codeChallenge = crypto.createHash("sha256").update(verifier, "ascii").digest("base64url");
  const state = crypto.randomBytes(24).toString("base64url");
  const authorizeUrl = `${config.authBaseUrl}/v1/oauth/authorize?${new URLSearchParams({
    response_type: "code",
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: "openid profile email",
    state,
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
    resource: config.resource,
  })}`;
  return { version: 1, verifier, state, authorizeUrl, stage: "new", createdAt: new Date().toISOString() };
}

export function parseCallbackUrl(rawUrl, pending, config) {
  const actual = new URL(rawUrl);
  const expected = new URL(config.redirectUri);
  if (actual.origin !== expected.origin || actual.pathname !== expected.pathname) return null;
  const returnedState = actual.searchParams.get("state");
  if (returnedState !== pending.state) {
    throw new LoginRequiredError("OAuth state mismatch. Start login again.");
  }
  const oauthError = actual.searchParams.get("error");
  if (oauthError) {
    throw new LoginRequiredError(`HeyGen authorization failed: ${oauthError}`);
  }
  const code = actual.searchParams.get("code");
  if (!code) throw new LoginRequiredError("The OAuth callback did not contain a code.");
  return code;
}

function writePrivate(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.${crypto.randomBytes(6).toString("hex")}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  fs.renameSync(temporary, file);
  try { fs.chmodSync(file, 0o600); } catch {}
}

function readPrivate(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw new Error(`Cannot read ${file}: ${error.message}`);
  }
}

function normalizeTokens(tokens) {
  const normalized = {
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token || null,
    token_type: tokens.token_type || "Bearer",
    scope: tokens.scope || "openid",
  };
  if (tokens.expires_in) {
    normalized.expires_at = new Date(Date.now() + Number(tokens.expires_in) * 1000).toISOString();
  } else if (tokens.expires_at) {
    normalized.expires_at = tokens.expires_at;
  }
  return normalized;
}

async function tokenRequest(config, parameters, fallbackRefreshToken = null) {
  const response = await fetch(`${config.authBaseUrl}/v1/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(parameters),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.access_token) {
    const detail = body.error_description || body.error || body.message || `HTTP ${response.status}`;
    throw new LoginRequiredError(`HeyGen token request failed: ${detail}`);
  }
  const tokens = normalizeTokens(body);
  if (!tokens.refresh_token && fallbackRefreshToken) tokens.refresh_token = fallbackRefreshToken;
  writePrivate(config.tokenFile, tokens);
  return tokens;
}

export async function getAccessToken(config) {
  const tokens = readPrivate(config.tokenFile);
  if (!tokens?.access_token) {
    throw new LoginRequiredError("Not logged in. Run: heygen-mcp login --email <address>");
  }
  const expiresAt = Date.parse(tokens.expires_at || "");
  if (!Number.isFinite(expiresAt) || expiresAt > Date.now() + 60_000) return tokens.access_token;
  if (!tokens.refresh_token) {
    throw new LoginRequiredError("The access token expired. Run heygen-mcp login again.");
  }
  const refreshed = await tokenRequest(config, {
    grant_type: "refresh_token",
    refresh_token: tokens.refresh_token,
    client_id: config.clientId,
    resource: config.resource,
  }, tokens.refresh_token);
  return refreshed.access_token;
}

function selectedPlan(plan) {
  if (!plan) return null;
  const names = { free: "Continue with Free", creator: "Continue with Creator", pro: "Continue with Pro" };
  if (!names[plan]) throw new LoginRequiredError("Plan must be one of: free, creator, pro");
  return names[plan];
}

async function finishAuthorization(browser, pending, config, plan) {
  const chosen = selectedPlan(plan);
  const deadline = Date.now() + 120_000;
  let consentClicked = false;
  let planClicked = false;
  let code;
  while (Date.now() < deadline && !code) {
    code = parseCallbackUrl(await browser.currentUrl(), pending, config);
    if (code) break;
    const snapshot = await browser.snapshot();
    if (/invalid or expired state/i.test(snapshot)) {
      throw new LoginRequiredError("HeyGen expired the authorization state. Run heygen-mcp login again to create a fresh one.");
    }
    if (/use email|enter your email/i.test(snapshot)) {
      throw new LoginRequiredError("HeyGen still requires email login. Run heygen-mcp login --email <address> to request one new magic link.");
    }
    if (!consentClicked && /authorize access/i.test(snapshot)) {
      const clicked = await browser.clickButton("Authorize access", { optional: true });
      if (!clicked) throw new LoginRequiredError("The Authorize access button was found but could not be clicked.");
      consentClicked = true;
      await browser.wait(5000);
      continue;
    }
    if (/continue with (free|creator|pro)|pick a plan/i.test(snapshot)) {
      if (planClicked) {
        await browser.wait(1000);
        continue;
      }
      if (!chosen) {
        pending.stage = "plan_required";
        writePrivate(config.pendingFile, pending);
        throw new LoginRequiredError(
          "HeyGen requires a plan choice. Ask the user to choose free, creator, or pro, then run: heygen-mcp login --plan <choice>",
          7,
        );
      }
      const clicked = await browser.clickButton(chosen, { optional: true });
      if (!clicked) throw new LoginRequiredError(`The ${plan} plan button was not found.`);
      planClicked = true;
      await browser.wait(5000);
      continue;
    }
    await browser.wait(1000);
  }
  if (!code) {
    throw new LoginRequiredError("Authorization did not reach the callback. Start login again; request a new magic link only if HeyGen still requires email login.");
  }
  const tokens = await tokenRequest(config, {
    grant_type: "authorization_code",
    code,
    redirect_uri: config.redirectUri,
    client_id: config.clientId,
    code_verifier: pending.verifier,
    resource: config.resource,
  });
  try { fs.unlinkSync(config.pendingFile); } catch {}
  await browser.close();
  return tokens;
}

export async function login(config, { email, magicLink, plan } = {}) {
  const browser = new AgentBrowser({ command: config.browserCommand });
  let pending = readPrivate(config.pendingFile);

  if (email) {
    pending = createAuthorization(config);
    pending.stage = "email_started";
    writePrivate(config.pendingFile, pending);
    await browser.open(pending.authorizeUrl);
    await browser.wait(3000);
    let snapshot = await browser.snapshot();
    const useEmailClicked = /use email/i.test(snapshot)
      ? await browser.clickButton("Use email", { optional: true })
      : false;
    if (useEmailClicked) {
      await browser.wait(1500);
      snapshot = await browser.snapshot();
    }
    const emailFormVisible = useEmailClicked || /input type="email"|textbox.*email|enter your email/i.test(snapshot);
    if (!emailFormVisible) {
      const tokens = await finishAuthorization(browser, pending, config, null);
      return { pending: false, tokenFile: config.tokenFile, expiresAt: tokens.expires_at };
    }
    await browser.fillEmail(email);
    await browser.clickButton("send a secure magic link");
    await browser.wait(8000);
    snapshot = await browser.snapshot();
    const sendConfirmed = /check your (email|inbox)|magic link (has been )?sent|return to your original tab/i.test(snapshot);
    if (/suspicious activity|flagged/i.test(snapshot) || !sendConfirmed) {
      const pendingSend = /sending[.…]?/i.test(snapshot);
      throw new LoginRequiredError(
        pendingSend
          ? "HeyGen is still showing Sending. An interactive CAPTCHA may be blocking the request; arrange manual browser access and do not resend the link."
          : "HeyGen did not explicitly confirm the magic-link request. Check the browser before retrying; do not resend blindly.",
      );
    }
    pending.stage = "magic_link_sent";
    writePrivate(config.pendingFile, pending);
    return {
      pending: true,
      message: "Magic link requested. Copy the link address from the newest HeyGen email and pass it to heygen-mcp login --magic-link through stdin. Do not open it in another browser.",
    };
  }

  if (magicLink) {
    if (!pending) throw new LoginRequiredError("No pending login. Run heygen-mcp login --email <address> first.");
    if (!/^https:\/\/app\.heygen\.com\/magic-web\//.test(magicLink)) {
      throw new LoginRequiredError("The magic link must be an https://app.heygen.com/magic-web/ URL.");
    }
    await browser.open(magicLink);
    await browser.wait(5000);
    const landing = await browser.snapshot();
    if (!/return to your original tab/i.test(landing)) {
      throw new LoginRequiredError("The magic link was not accepted. It may be expired or already used; run login --email to request one new link.");
    }
    pending = createAuthorization(config);
    pending.stage = "browser_authenticated";
    writePrivate(config.pendingFile, pending);
    await browser.open(pending.authorizeUrl);
    await browser.wait(3000);
    const tokens = await finishAuthorization(browser, pending, config, null);
    return { pending: false, tokenFile: config.tokenFile, expiresAt: tokens.expires_at };
  }

  if (plan) {
    if (pending?.stage !== "plan_required") {
      throw new LoginRequiredError("No plan choice is pending. Start with heygen-mcp login or login --magic-link.");
    }
  } else if (pending?.stage === "magic_link_sent") {
    throw new LoginRequiredError("Pass the newest magic link through stdin with heygen-mcp login --magic-link.");
  } else if (pending?.stage === "plan_required") {
    throw new LoginRequiredError("Ask the user to choose free, creator, or pro, then run heygen-mcp login --plan <choice>.", 7);
  }

  pending = createAuthorization(config);
  pending.stage = plan ? "plan_required" : "browser_authenticated";
  writePrivate(config.pendingFile, pending);
  await browser.open(pending.authorizeUrl);
  await browser.wait(3000);
  const tokens = await finishAuthorization(browser, pending, config, plan);
  return { pending: false, tokenFile: config.tokenFile, expiresAt: tokens.expires_at };
}
