#!/usr/bin/env bash
# Prints one line per tool so the agent can report the truth instead of guessing.
set -uo pipefail

export PATH="$HOME/.local/bin:$HOME/.composio:$HOME/.npm-global/bin:$PATH"
PAVE_HOME="${PAVE_HOME:-$HOME/.pave}"

pass=0
fail=0

row() { # row <label> <command...>
  local label="$1"; shift
  local out status first
  out="$("$@" 2>&1)"; status=$?
  first="$(printf '%s\n' "$out" | head -1)"
  if [ "$status" -eq 0 ]; then
    printf '  OK    %-16s %s\n' "$label" "$first"
    pass=$((pass + 1))
  else
    printf '  MISS  %-16s %s\n' "$label" "${first:-command failed}"
    fail=$((fail + 1))
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

check() { # check <label> <command...>
  local label="$1"; shift
  if has "$1"; then row "$label" "$@"; else miss "$label" "not on PATH"; fi
}

echo "pave-setup verify  home=$HOME"
echo

echo "CLI"
check "oo"         oo --version
check "composio"   composio --version
check "officecli"  officecli --version
check "heygen-mcp" heygen-mcp --help
if has agent-browser; then
  row "agent-browser" agent-browser --version
else
  skip "agent-browser" "optional, not installed"
fi

echo
echo "System"
check "node"     node --version
check "git"      git --version
check "curl"     curl --version
check "unzip"    unzip -v
check "pdftoppm" pdftoppm -v
if has xvfb-run; then
  printf '  OK    %-16s %s\n' "xvfb-run" "$(command -v xvfb-run)"
  pass=$((pass + 1))
else
  skip "xvfb-run" "no X server; apt-get install -y xvfb"
fi

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
  skip "AGENTS.md" "opt-in; use install.sh --agents <path>"
fi

echo
echo "Logins (these are the user's job, not the installer's)"
printf '  oo        : %s\n' "$(oo auth status 2>&1 | head -1 || echo 'unknown')"
printf '  composio  : %s\n' "$(composio whoami 2>&1 | head -1 || echo 'unknown')"

echo
printf 'summary: %s ok, %s missing\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
