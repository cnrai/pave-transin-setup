import http from "node:http";

export class CallbackServerError extends Error {}

export async function startCallbackServer(redirectUri, expectedState) {
  const expected = new URL(redirectUri);
  const host = expected.hostname;
  if (!["127.0.0.1", "localhost", "::1"].includes(host)) {
    throw new CallbackServerError("The callback listener only supports a loopback redirect URI.");
  }
  const port = Number(expected.port);
  if (!Number.isInteger(port) || port <= 0) {
    throw new CallbackServerError("The loopback redirect URI must include an explicit port.");
  }
  if (!expectedState) throw new CallbackServerError("The callback listener requires the OAuth state.");

  let capturedUrls = [];
  const server = http.createServer((request, response) => {
    if (request.url === "/favicon.ico") {
      response.writeHead(204);
      response.end();
      return;
    }
    let requestUrl;
    try {
      requestUrl = new URL(request.url, expected.origin);
    } catch {
      requestUrl = null;
    }
    const code = requestUrl?.searchParams.get("code");
    const error = requestUrl?.searchParams.get("error");
    const navigation = String(request.headers["sec-fetch-mode"] || "").toLowerCase() === "navigate"
      && String(request.headers["sec-fetch-dest"] || "").toLowerCase() === "document";
    const valid = requestUrl
      && requestUrl.origin === expected.origin
      && requestUrl.pathname === expected.pathname
      && requestUrl.searchParams.get("state") === expectedState
      && Boolean(code || error)
      && navigation;
    if (!valid) {
      response.writeHead(400, {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
      });
      response.end("Invalid callback request");
      return;
    }
    if (!capturedUrls.includes(requestUrl.href)) {
      capturedUrls = [...capturedUrls.slice(-4), requestUrl.href];
    }
    response.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'",
    });
    response.end("<!doctype html><title>HeyGen login received</title><p>Login received. You can close this tab.</p>");
  });

  await new Promise((resolve, reject) => {
    const onError = (error) => {
      server.off("listening", onListening);
      if (error.code === "EADDRINUSE") {
        reject(new CallbackServerError(
          `Callback port ${port} is already in use. Stop the old callback listener or OAuth bridge, then retry.`,
        ));
      } else {
        reject(new CallbackServerError(`Cannot start the callback listener: ${error.message}`));
      }
    };
    const onListening = () => {
      server.off("error", onError);
      resolve();
    };
    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(port, host);
  });

  return {
    urls() {
      return [...capturedUrls];
    },
    async close() {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}
