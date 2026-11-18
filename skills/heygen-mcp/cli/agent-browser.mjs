import { spawn } from "node:child_process";

export class AgentBrowserError extends Error {}

export class AgentBrowser {
  constructor({ command = "agent-browser", session = "heygen-mcp-oauth" } = {}) {
    this.command = command;
    this.session = session;
  }

  async run(args, { allowFailure = false, redact = [], retry = 0 } = {}) {
    const globalArgs = [
      "--session",
      this.session,
      "--restore",
      this.session,
      "--headed",
    ];
    const execute = () => new Promise((resolve, reject) => {
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
            "agent-browser is not installed. Run: heygen-mcp doctor, then npm i -g agent-browser && agent-browser install --with-deps",
          ));
        } else {
          reject(error);
        }
      });
      child.on("close", (code) => resolve({ code, stdout, stderr }));
    });

    let result;
    for (let attempt = 0; attempt <= retry; attempt++) {
      result = await execute();
      const transient = /Resource temporarily unavailable|no response came back|os error 11/i
        .test(`${result.stderr}\n${result.stdout}`);
      if (result.code === 0 || !transient || attempt === retry) break;
      await new Promise((resolve) => setTimeout(resolve, 750));
    }

    let detail = `${result.stderr}\n${result.stdout}`.trim();
    for (const secret of redact) detail = detail.split(secret).join("[redacted]");
    const transient = /Resource temporarily unavailable|no response came back|os error 11/i.test(detail);
    if (transient) {
      throw new AgentBrowserError(
        `agent-browser lost contact with its daemon during ${args[0]}; the command may or may not have run. Run heygen-mcp doctor, then inspect the browser before retrying.`,
      );
    }
    if (result.code !== 0 && !allowFailure) {
      throw new AgentBrowserError(
        `agent-browser ${args[0]} failed${detail ? `: ${detail.slice(0, 800)}` : ""}`,
      );
    }
    return { ...result, detail };
  }

  async open(url, { retry = false } = {}) {
    await this.run(["open", url], { redact: [url], retry });
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
    const result = await this.run(["snapshot", "-c"], { retry: 1 });
    return result.stdout;
  }

  async wait(milliseconds) {
    await this.run(["wait", String(milliseconds)], { retry: 1 });
  }

  async currentUrl() {
    const result = await this.run(["get", "url"], { retry: 1 });
    const lines = result.stdout.trim().split(/\r?\n/);
    return lines.at(-1)?.trim() || "";
  }

  async close() {
    try {
      await this.run(["close"], { allowFailure: true });
    } catch {}
  }
}
