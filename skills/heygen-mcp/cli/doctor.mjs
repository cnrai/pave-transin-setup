import fs from "node:fs";
import net from "node:net";
import path from "node:path";

async function callbackPortStatus(redirectUri) {
  const url = new URL(redirectUri);
  const port = Number(url.port);
  if (!Number.isInteger(port) || port <= 0) return { ok: false, detail: "Callback URI has no explicit port" };
  const host = url.hostname;
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once("error", (error) => {
      resolve({
        ok: false,
        detail: error.code === "EADDRINUSE" ? `Port ${port} is already in use` : `Cannot bind ${host}:${port}: ${error.message}`,
      });
    });
    server.listen(port, host, () => {
      server.close(() => resolve({ ok: true, detail: `Port ${port} is available for the temporary listener` }));
    });
  });
}

function executableCandidates(command, env) {
  const winExtensions = (env.PATHEXT || ".EXE;.CMD;.BAT;.COM").split(";");
  if (command.includes("/") || command.includes("\\")) {
    if (process.platform !== "win32" || path.extname(command)) return [command];
    return [command, ...winExtensions.map((extension) => `${command}${extension.toLowerCase()}`)];
  }
  const extensions = process.platform === "win32" ? winExtensions : [""];
  return (env.PATH || "").split(path.delimiter).flatMap((directory) =>
    extensions.map((extension) => path.join(directory, `${command}${extension}`)));
}

export function findExecutable(command, env = process.env) {
  const mode = process.platform === "win32" ? fs.constants.F_OK : fs.constants.X_OK;
  return executableCandidates(command, env).find((candidate) => {
    try {
      fs.accessSync(candidate, mode);
      return true;
    } catch {
      return false;
    }
  }) || null;
}

export async function runDoctor(config, { env = process.env, platform = process.platform } = {}) {
  const checks = [];
  const nodeMajor = Number(process.versions.node.split(".")[0]);
  checks.push({
    name: "node",
    ok: nodeMajor >= 18,
    detail: `Node ${process.versions.node}`,
    fix: "Install Node.js 18 or newer.",
  });

  const browserPath = findExecutable(config.browserCommand, env);
  checks.push({
    name: "agent-browser",
    ok: Boolean(browserPath),
    detail: browserPath || `${config.browserCommand} not found on PATH`,
    fix: "npm i -g agent-browser && agent-browser install --with-deps",
  });

  if (platform === "linux") {
    const xvfb = findExecutable("Xvfb", env);
    const hasDisplay = Boolean(env.DISPLAY);
    checks.push({
      name: "display",
      ok: hasDisplay || Boolean(xvfb),
      detail: hasDisplay ? `DISPLAY=${env.DISPLAY}` : xvfb ? `Xvfb found at ${xvfb}` : "No DISPLAY and Xvfb is not installed",
      fix: "sudo apt-get update && sudo apt-get install -y xvfb xfonts-base",
    });
  }

  let callbackStatus;
  try {
    callbackStatus = await callbackPortStatus(config.redirectUri);
  } catch (error) {
    callbackStatus = { ok: false, detail: `Invalid callback URI: ${error.message}` };
  }
  checks.push({
    name: "callback-port",
    ok: callbackStatus.ok,
    detail: callbackStatus.detail,
    fix: "Stop the old callback listener or OAuth bridge, or change HEYGEN_OAUTH_REDIRECT_URI.",
  });

  let tokenDetail = "No token file; run heygen-mcp login";
  let tokenOk = false;
  try {
    const tokens = JSON.parse(fs.readFileSync(config.tokenFile, "utf8"));
    tokenOk = Boolean(tokens.access_token);
    tokenDetail = tokenOk
      ? `${config.tokenFile}${tokens.expires_at ? `, expires ${tokens.expires_at}` : ""}`
      : `${config.tokenFile} has no access token`;
  } catch (error) {
    if (error.code !== "ENOENT") tokenDetail = `Cannot read ${config.tokenFile}: ${error.message}`;
  }
  checks.push({
    name: "tokens",
    ok: tokenOk,
    detail: tokenDetail,
    fix: "Run the login flow; this check is optional for login.",
    optional: true,
  });

  let pendingDetail = "No pending login";
  try {
    const pending = JSON.parse(fs.readFileSync(config.pendingFile, "utf8"));
    pendingDetail = `Pending stage: ${pending.stage || "unknown"}`;
  } catch (error) {
    if (error.code !== "ENOENT") pendingDetail = `Cannot read ${config.pendingFile}: ${error.message}`;
  }
  checks.push({ name: "pending", ok: true, detail: pendingDetail });

  const blockers = checks.filter((check) => !check.ok && !check.optional);
  return { ok: blockers.length === 0, checks };
}

export function formatDoctor(result) {
  const lines = result.checks.map((check) => {
    const marker = check.ok ? "OK" : check.optional ? "INFO" : "FAIL";
    return `[${marker}] ${check.name}: ${check.detail}${check.ok || !check.fix ? "" : `\n       fix: ${check.fix}`}`;
  });
  return `${lines.join("\n")}\n`;
}
