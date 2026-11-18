#!/usr/bin/env bash
# Prints one line per tool so the agent can report the truth instead of guessing.
set -uo pipefail

export PATH="$HOME/.local/bin:$HOME/.composio:$HOME/.npm-global/bin:$PATH"
PAVE_HOME="${PAVE_HOME:-$HOME/.pave}"

pass=0
fail=0

row() { # row <label> <command...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  OK    %-16s %s\n' "$label" "$( "$@" 2>&1 | head -1 )"
    pass=$((pass + 1))
  else
    miss "$label" "command failed"
  fi
}

miss() { # miss <label> [reason]
  printf '  MISS  %-16s %s\n' "$1" "${2:-not on PATH}"
  fail=$((fail + 1))
}

skip() {
  printf '  SKIP  %-16s %s\n' "$1" "${2:-optional}"
}

has() { command -v "$1" >/dev/null 2>&1; }

echo "pave-setup verify  home=$HOME"
echo

echo "CLI"
has oo         && row  "oo"         oo --version         || miss "oo" "not on PATH"
has composio   && row  "composio"   composio --version   || miss "composio" "not on PATH"
has officecli  && row  "officecli"  officecli --version  || miss "officecli" "not on PATH"
has agent-browser && row "agent-browser" agent-browser --version || skip "agent-browser" "optional, not installed"
has heygen-mcp && row  "heygen-mcp" heygen-mcp --help    || miss "heygen-mcp" "not on PATH"
has pdftoppm   && row  "pdftoppm"   pdftoppm -v          || miss "pdftoppm" "poppler-utils missing"
has node       && row  "node"       node --version       || miss "node" "missing"
has git        && row  "git"        git --version        || miss "git" "missing"

echo
echo "Browser install (background)"
BROWSER_STATUS="$PAVE_HOME/browser-install/status.txt"
if [ -f "$BROWSER_STATUS" ]; then
  bstate="$(sed -n 's/^state=//p' "$BROWSER_STATUS" | head -1)"
  bphase="$(sed -n 's/^phase=//p' "$BROWSER_STATUS" | head -1)"
  case "$bstate" in
    running|starting)
      printf '  WAIT  %-16s phase=%s\n' "browser" "$bphase" ;;
    done)
      printf '  OK    %-16s Playwright + Chrome\n' "browser" ;;
    partial)
      printf '  PART  %-16s some browser components failed\n' "browser" ;;
    *)
      printf '  MISS  %-16s state=%s\n' "browser" "$bstate" ;;
  esac
else
  skip "browser" "no background status"
fi

echo
echo "Skills  ($PAVE_HOME/skills)"
expected="agent-browser heygen-mcp officecli pave-setup pw-redbook-image seedance-2.0-superprompt seedance2-skill"
for name in $expected; do
  if [ -f "$PAVE_HOME/skills/$name/SKILL.md" ]; then
    printf '  OK    %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  MISS  %s\n' "$name"
    fail=$((fail + 1))
  fi
done

echo
echo "AGENTS.md"
if [ -f "$PWD/AGENTS.md" ]; then
  printf '  OK    %s (%s lines)\n' "$PWD/AGENTS.md" "$(wc -l < "$PWD/AGENTS.md" | tr -d ' ')"
else
  printf '  MISS  no AGENTS.md in %s\n' "$PWD"
fi

echo
echo "Logins (these are the user's job, not the installer's)"
printf '  oo        : %s\n' "$(oo auth status 2>&1 | head -1 || echo 'unknown')"
printf '  composio  : %s\n' "$(composio whoami 2>&1 | head -1 || echo 'unknown')"

echo
printf 'summary: %s ok, %s missing\n' "$pass" "$fail"
exit 0
