#!/usr/bin/env bash
set -uo pipefail

PAVE_HOME="${PAVE_HOME:-$HOME/.pave}"
SKILLS_DIR="${PAVE_HOME}/skills"
STATE_DIR="${PAVE_HOME}/browser-install"
STATUS_FILE="${STATE_DIR}/status.txt"
LOG_FILE="${STATE_DIR}/install.log"
ALLOW_APT="${ALLOW_APT:-1}"
mkdir -p "$STATE_DIR"

export PATH="$HOME/.local/bin:$HOME/.composio:$HOME/.npm-global/bin:$PATH"
NPM_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
export NPM_CONFIG_PREFIX="$NPM_PREFIX"
mkdir -p "$NPM_PREFIX/bin"
export PATH="$NPM_PREFIX/bin:$PATH"
export npm_config_yes=true
export DEBIAN_FRONTEND=noninteractive

write_status() {
  local state="$1" phase="$2" code="${3:-}"
  local tmp="${STATUS_FILE}.$$"
  {
    printf 'state=%s\n' "$state"
    printf 'phase=%s\n' "$phase"
    printf 'pid=%s\n' "$$"
    printf 'started=%s\n' "$STARTED"
    printf 'updated=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'finished=%s\n' "${FINISHED:-}"
    printf 'exit_code=%s\n' "$code"
    printf 'log=%s\n' "$LOG_FILE"
    printf 'chrome=%s\n' "${CHROME_STATUS:-pending}"
    printf 'chromium=%s\n' "${CHROMIUM_STATUS:-pending}"
    printf 'agent_browser=%s\n' "${AGENT_BROWSER_STATUS:-pending}"
  } > "$tmp"
  mv "$tmp" "$STATUS_FILE"
}

finish() {
  local code=$?
  trap - EXIT
  FINISHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$code" -eq 0 ] && [ "${CHROME_STATUS:-}" = "ok" ]; then
    write_status "done" "complete" "$code"
  elif [ "${CHROMIUM_STATUS:-}" = "ok" ] || [ "${AGENT_BROWSER_STATUS:-}" = "ok" ]; then
    write_status "partial" "complete" "$code"
  else
    write_status "failed" "complete" "$code"
  fi
  exit "$code"
}

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FINISHED=""
CHROME_STATUS="pending"
CHROMIUM_STATUS="pending"
AGENT_BROWSER_STATUS="pending"
trap finish EXIT
: > "$LOG_FILE"
write_status "running" "dependencies"

run() {
  printf '\n[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE"
  "$@" >> "$LOG_FILE" 2>&1
}

if ! command -v npm >/dev/null 2>&1; then
  printf 'npm not found\n' >> "$LOG_FILE"
  exit 1
fi

write_status "running" "agent-browser"
if ! command -v agent-browser >/dev/null 2>&1; then
  run npm install -g agent-browser || exit 1
fi
if run agent-browser install; then
  AGENT_BROWSER_STATUS="ok"
else
  AGENT_BROWSER_STATUS="failed"
fi

if [ "$ALLOW_APT" -eq 1 ] && command -v sudo >/dev/null 2>&1; then
  write_status "running" "xvfb"
  run sudo -n apt-get update || true
  run sudo -n apt-get install -y xvfb xfonts-base || true
fi

write_status "running" "playwright"
if [ ! -f "$SKILLS_DIR/heygen-mcp/package.json" ]; then
  printf 'heygen-mcp skill not found at %s\n' "$SKILLS_DIR/heygen-mcp" >> "$LOG_FILE"
  exit 1
fi
if ! ( cd "$SKILLS_DIR/heygen-mcp" && run npm install playwright --no-save --no-package-lock --no-audit --no-fund ); then
  exit 1
fi

write_status "running" "chrome"
if ( cd "$SKILLS_DIR/heygen-mcp" && run npx playwright install chrome ); then
  CHROME_STATUS="ok"
else
  CHROME_STATUS="failed"
fi

write_status "running" "chromium"
if ( cd "$SKILLS_DIR/heygen-mcp" && run npx playwright install chromium ); then
  CHROMIUM_STATUS="ok"
else
  CHROMIUM_STATUS="failed"
fi

if [ "$CHROME_STATUS" != "ok" ] && [ "$CHROMIUM_STATUS" != "ok" ]; then
  exit 1
fi
