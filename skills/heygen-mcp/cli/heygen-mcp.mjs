#!/usr/bin/env node
import fs from "node:fs";
import { connectMcp } from "./mcp-client.mjs";
import { getAccessToken, getConfig, login, LoginRequiredError } from "./oauth.mjs";

const HELP = `HeyGen MCP CLI — no local callback server required

Usage:
  heygen-mcp login --email <address>
  heygen-mcp login --magic-link < magic-link.txt
  heygen-mcp login --plan <free|creator|pro>
  heygen-mcp tools [--json]
  heygen-mcp schema <tool>
  heygen-mcp call <tool> <json|@file|->
  heygen-mcp whoami

Login runs a persistent, headed agent-browser session inside this machine or
sandbox. It captures the loopback redirect URL; it never starts a callback
listener. Complete CAPTCHAs manually if one appears. Never choose a paid plan
without the user's explicit approval.

Environment overrides:
  HEYGEN_CONFIG_HOME       Token and pending-login directory
  HEYGEN_TOKEN_FILE        Token file path
  HEYGEN_AGENT_BROWSER     agent-browser executable path
`;

function usageError(message) {
  const error = new Error(message);
  error.exitCode = 2;
  return error;
}

function parseLogin(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--email") {
      options.email = args[++i];
      if (!options.email) throw usageError("--email requires an address");
    } else if (arg === "--magic-link") {
      options.magicLink = true;
    } else if (arg === "--plan") {
      options.plan = args[++i];
      if (!options.plan) throw usageError("--plan requires free, creator, or pro");
    } else {
      throw usageError(`Unknown login option: ${arg}`);
    }
  }
  if (options.email && options.magicLink) {
    throw usageError("Use --email or --magic-link, not both");
  }
  if (options.plan && (options.email || options.magicLink)) {
    throw usageError("Use --plan only in a separate invocation after the plan picker appears");
  }
  if (options.plan && !["free", "creator", "pro"].includes(options.plan)) {
    throw usageError("Plan must be one of: free, creator, pro");
  }
  return options;
}

async function readStdin() {
  let value = "";
  for await (const chunk of process.stdin) value += chunk;
  return value.trim();
}

async function parseToolArgs(args) {
  if (args.length !== 1) throw usageError("Provide exactly one JSON object, @file, or - for stdin");
  let raw;
  if (args[0] === "-") raw = await readStdin();
  else if (args[0].startsWith("@")) raw = fs.readFileSync(args[0].slice(1), "utf8");
  else raw = args[0];
  let value;
  try { value = JSON.parse(raw); } catch (error) { throw usageError(`Invalid JSON: ${error.message}`); }
  if (!value || Array.isArray(value) || typeof value !== "object") {
    throw usageError("Tool arguments must be a JSON object");
  }
  return value;
}

async function mcp(config) {
  const accessToken = await getAccessToken(config);
  return connectMcp({ ...config, accessToken });
}

function printToolResult(result) {
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (result?.isError) process.exitCode = 2;
}

async function main(argv) {
  const [command, ...args] = argv;
  const config = getConfig();
  if (!command || command === "help" || command === "--help" || command === "-h") {
    process.stdout.write(HELP);
    return;
  }
  if (command === "login") {
    const options = parseLogin(args);
    if (options.magicLink) {
      options.magicLink = await readStdin();
      if (!options.magicLink) throw usageError("Provide the magic link through stdin");
    }
    const result = await login(config, options);
    if (result.pending) process.stdout.write(`${result.message}\n`);
    else process.stdout.write(`Login complete. Tokens stored in ${result.tokenFile}\n`);
    return;
  }
  if (command === "tools") {
    if (args.length > 1 || (args.length === 1 && args[0] !== "--json")) {
      throw usageError("Usage: heygen-mcp tools [--json]");
    }
    const client = await mcp(config);
    const tools = await client.listTools();
    if (args[0] === "--json") {
      process.stdout.write(`${JSON.stringify(tools, null, 2)}\n`);
    } else {
      for (const tool of tools) {
        const description = String(tool.description || "").replace(/\s+/g, " ").slice(0, 140);
        process.stdout.write(`- ${tool.name}: ${description}\n`);
      }
      process.stdout.write(`(${tools.length} tools)\n`);
    }
    return;
  }
  if (command === "schema") {
    if (args.length !== 1) throw usageError("Usage: heygen-mcp schema <tool>");
    const client = await mcp(config);
    const tool = (await client.listTools()).find((item) => item.name === args[0]);
    if (!tool) throw new Error(`Unknown tool: ${args[0]}`);
    process.stdout.write(`${JSON.stringify(tool, null, 2)}\n`);
    return;
  }
  if (command === "call") {
    if (args.length < 2) throw usageError("Usage: heygen-mcp call <tool> <json|@file|->");
    const toolArgs = await parseToolArgs(args.slice(1));
    const client = await mcp(config);
    printToolResult(await client.callTool(args[0], toolArgs));
    return;
  }
  if (command === "whoami") {
    if (args.length) throw usageError("Usage: heygen-mcp whoami");
    const client = await mcp(config);
    printToolResult(await client.callTool("get_current_user", {}));
    return;
  }
  throw usageError(`Unknown command: ${command}\n\n${HELP}`);
}

main(process.argv.slice(2)).catch((error) => {
  const exitCode = error.exitCode || (error instanceof LoginRequiredError ? 1 : 1);
  process.stderr.write(`heygen-mcp: ${error.message}\n`);
  process.exitCode = exitCode;
});
