export class McpClient {
  constructor({ url, token, fetchImpl = fetch }) {
    this.url = url;
    this.token = token;
    this.fetch = fetchImpl;
    this.sessionId = null;
    this.nextId = 1;
  }

  async rpc(method, params, notification = false) {
    const body = { jsonrpc: "2.0", method };
    if (!notification) body.id = this.nextId++;
    if (params !== undefined) body.params = params;
    const headers = {
      Accept: "application/json, text/event-stream",
      Authorization: `Bearer ${this.token}`,
      "Content-Type": "application/json",
    };
    if (this.sessionId) headers["mcp-session-id"] = this.sessionId;
    const response = await this.fetch(this.url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    this.sessionId = response.headers.get("mcp-session-id") || this.sessionId;
    const raw = await response.text();
    if (response.status === 202 && !raw) return null;
    if (!response.ok) throw new Error(`MCP HTTP ${response.status}: ${raw.slice(0, 500)}`);
    let message;
    if (response.headers.get("content-type")?.includes("text/event-stream")) {
      const events = raw.split(/\r?\n/).filter((line) => line.startsWith("data:"));
      if (!events.length) throw new Error("MCP returned an empty SSE response");
      message = JSON.parse(events.at(-1).slice(5).trim());
    } else {
      message = JSON.parse(raw);
    }
    if (message.error) throw new Error(`MCP ${method}: ${JSON.stringify(message.error)}`);
    return message.result;
  }

  async initialize() {
    await this.rpc("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "openpave-heygen-cli", version: "0.3.0" },
    });
    await this.rpc("notifications/initialized", undefined, true);
  }

  async listTools() {
    const tools = [];
    let cursor;
    do {
      const result = await this.rpc("tools/list", cursor ? { cursor } : {});
      tools.push(...(result.tools || []));
      cursor = result.nextCursor;
    } while (cursor);
    return tools;
  }

  async callTool(name, args) {
    return this.rpc("tools/call", { name, arguments: args });
  }
}

export async function connectMcp(config) {
  const client = new McpClient({ url: config.mcpUrl, token: config.accessToken });
  await client.initialize();
  return client;
}
