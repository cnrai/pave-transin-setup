import { spawn } from "node:child_process";

export class AgentBrowserError extends Error {}

export class AgentBrowser {
  constructor({ command = "agent-browser", session = "heygen-mcp-oauth" } = {}) {
    this.command = command;
    this.session = session;
  }

  async run(args, { allowFailure = false, redact = [] } = {}) {
    const globalArgs = [
      "--session",
      this.session,
      "--restore",
      this.session,
      "--headed",
    ];
    const result = await new Promise((resolve, reject) => {
      const windowsBatch = process.platform === "win32" && /\.(cmd|bat)$/i.test(this.command);
      const quoteBatchArg = (value) => `"${String(value).replace(/"/g, '""')}"`;
      const command = windowsBatch ? (process.env.ComSpec || "cmd.exe") : this.command;
      const commandArgs = windowsBatch
        ? ["/d", "/s", "/c", `"${[this.command, ...globalArgs, ...args].map(quoteBatchArg).join(" ")}"`]
        : [...globalArgs, ...args];
      const child = spawn(command, commandArgs, {
        stdio: ["ignore", "pipe", "pipe"],
        windowsHide: true,
        windowsVerbatimArguments: windowsBatch,
      });
      let stdout = "";
      let stderr = "";
      child.stdout.setEncoding("utf8");
      child.stderr.setEncoding("utf8");
      child.stdout.on("data", (chunk) => { stdout += chunk; });
      child.stderr.on("data", (chunk) => { stderr += chunk; });
      child.on("error", (error) => {
        if (error.code === "ENOENT") {
          reject(new AgentBrowserError(
            "agent-browser is not installed. Run: npm i -g agent-browser && agent-browser install --with-deps",
          ));
        } else {
          reject(error);
        }
      });
      child.on("close", (code) => resolve({ code, stdout, stderr }));
    });

    let detail = `${result.stderr}\n${result.stdout}`.trim();
    for (const secret of redact) detail = detail.split(secret).join("[redacted]");
    if (result.code !== 0 && !allowFailure) {
      throw new AgentBrowserError(
        `agent-browser ${args[0]} failed${detail ? `: ${detail.slice(0, 800)}` : ""}`,
      );
    }
    return { ...result, detail };
  }

  async open(url) {
    await this.run(["open", url], { redact: [url] });
  }

  async clickButton(name, { optional = false } = {}) {
    const result = await this.run(
      ["find", "role", "button", "click", "--name", name],
      { allowFailure: optional },
    );
    return result.code === 0;
  }

  async fillEmail(email) {
    const label = await this.run(
      ["find", "label", "Email", "fill", email],
      { allowFailure: true },
    );
    if (label.code === 0) return;
    await this.run(["find", "role", "textbox", "fill", "--name", "Enter your email", email]);
  }

  async snapshot() {
    const result = await this.run(["snapshot", "-c"]);
    return result.stdout;
  }

  async wait(milliseconds) {
    await this.run(["wait", String(milliseconds)]);
  }

  async currentUrl() {
    const result = await this.run(["get", "url"]);
    const lines = result.stdout.trim().split(/\r?\n/);
    return lines.at(-1)?.trim() || "";
  }

  async close() {
    await this.run(["close"], { allowFailure: true });
  }
}
