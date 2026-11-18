#!/usr/bin/env bash
# pave-setup installer — installs the PAVE toolchain into the current user account.
# Idempotent: every step is skipped when the tool is already present.
# Writes only under $HOME (plus the AGENTS.md path you pass in explicitly).
set -euo pipefail

SKILLS_ONLY=0
NO_BROWSER=0
NO_NETWORK=0
ALLOW_APT=1
FORCE_SKILLS=0
AGENTS_TARGET=""
PRINT_AGENTS=0
DRY_RUN=0

usage() {
  cat <<'EOF'
usage: install.sh [options]

  --skills-only     copy skills only (no CLI download, no AGENTS.md)
  --no-browser      do not install Playwright, Chrome, or agent-browser
  --no-network      skip remote CLI installs (oo, composio, officecli)
  --with-browser    accepted for compatibility; browser install is now the default
  --no-apt          never call apt-get, even for browser deps
  --force-skills    overwrite skills that already exist
  --agents <path>   opt in: write AGENTS.md to <path>. Nothing is written without it.
  --print-agents    print the bundled AGENTS.md and exit; writes nothing
  --dry-run         print what would happen, change nothing
  -h, --help        show this help

Installing is not logging in. Logins stay with the user (see /setup).

Environment:
  PAVE_HOME         default $HOME/.pave
  OO_TEAM           team name for `oo login` (never a token)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-browser) : ;;
    --no-browser) NO_BROWSER=1 ;;
    --no-network) NO_NETWORK=1; NO_BROWSER=1 ;;
    --skills-only) SKILLS_ONLY=1 ;;
    --no-apt) ALLOW_APT=0 ;;
    --force-skills) FORCE_SKILLS=1 ;;
    --agents) AGENTS_TARGET="${2:-}"; shift ;;
    --print-agents) PRINT_AGENTS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skills"
PAVE_HOME="${PAVE_HOME:-$HOME/.pave}"
SKILLS_DIR="$PAVE_HOME/skills"
NPM_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
export NPM_CONFIG_PREFIX="$NPM_PREFIX"

export PATH="$NPM_PREFIX/bin:$HOME/.local/bin:$HOME/.composio:$HOME/.npm-global/bin:$PATH"
NETWORK_AVAILABLE=1
NETWORK_CHECK_TIMEOUT="${NETWORK_CHECK_TIMEOUT:-4}"
NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-20}"

have() { command -v "$1" >/dev/null 2>&1; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
ok()   { printf '   + %s\n' "$*"; }
plan() { printf '   > would %s\n' "$*"; }

SUMMARY=()
record() { SUMMARY+=("$1|$2|$3"); }

if [ "$PRINT_AGENTS" -eq 1 ]; then
  cat "$REPO_DIR/AGENTS.md"
  exit 0
fi

# --agents is opt-in and must never land on a path this repo owns.
if [ -n "$AGENTS_TARGET" ]; then
  case "$AGENTS_TARGET" in
    /*) ;;
    *) AGENTS_TARGET="$PWD/$AGENTS_TARGET" ;;
  esac
  case "$AGENTS_TARGET" in
    "$REPO_DIR"|"$REPO_DIR"/*)
      echo "refusing --agents inside the installer repo: $AGENTS_TARGET" >&2
      echo "point it at your workspace root instead, e.g. \"\$PWD/AGENTS.md\"" >&2
      exit 2
      ;;
  esac
  case "$AGENTS_TARGET" in
    /tmp/*) warn "AGENTS.md in /tmp will not be read by the agent: $AGENTS_TARGET" ;;
  esac
fi

run_limited() {
  local seconds="$1"
  shift
  if have timeout; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

as_root_limited() {
  local seconds="$1"
  shift
  if [ "$(id -u)" -eq 0 ]; then
    run_limited "$seconds" "$@"
  elif have sudo && sudo -n true >/dev/null 2>&1; then
    run_limited "$seconds" sudo -n "$@"
  else
    return 1
  fi
}

preflight() {
  step "Prerequisites"
  if [ "$DRY_RUN" -eq 1 ]; then
    ok "dry run: no directory or package changes"
  else
    mkdir -p "$HOME/.local/bin" "$HOME/.composio" "$NPM_PREFIX/bin" "$SKILLS_DIR"
  fi

  if have npm; then
    ok "npm global prefix: $NPM_CONFIG_PREFIX"
  else
    warn "npm not found: heygen-mcp, Playwright, and agent-browser cannot install"
  fi

  if [ "$NO_NETWORK" -eq 1 ]; then
    NETWORK_AVAILABLE=0
    ok "remote CLI installs disabled (--no-network)"
  elif ! have curl; then
    NETWORK_AVAILABLE=0
    warn "curl not found; remote CLI installs will be skipped"
  elif run_limited "$NETWORK_CHECK_TIMEOUT" curl -fsS --connect-timeout 2 --max-time "$NETWORK_CHECK_TIMEOUT" -o /dev/null https://cli.oomol.com/install.sh; then
    ok "network available"
  else
    NETWORK_AVAILABLE=0
    warn "network blocked or unavailable; remote CLI installs will be skipped (use --no-network to make this explicit)"
  fi

  if have unzip; then
    ok "unzip present"
  elif [ "$DRY_RUN" -eq 1 ]; then
    plan "apt-get install -y unzip (composio needs it)"
  elif [ "$ALLOW_APT" -eq 1 ] && have apt-get && as_root_limited 15 apt-get update >/dev/null 2>&1; then
    if as_root_limited 20 apt-get install -y unzip >/dev/null 2>&1 && have unzip; then
      ok "unzip installed"
    else
      warn "unzip install failed; composio will be skipped"
    fi
  else
    warn "unzip missing; install it before composio: sudo apt-get install -y unzip"
  fi
}


# ---------------------------------------------------------------- skills
copy_skills() {
  step "skills -> $SKILLS_DIR"
  local d name copied=0 kept=0
  for d in "$SKILL_SRC"/*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -e "$SKILLS_DIR/$name" ] && [ "$FORCE_SKILLS" -ne 1 ]; then
      ok "kept    $name"
      kept=$((kept + 1))
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      plan "copy $name"
    else
      rm -rf "${SKILLS_DIR:?}/$name"
      cp -a "$d" "$SKILLS_DIR/"
      ok "copied  $name"
    fi
    copied=$((copied + 1))
  done
  if [ "$DRY_RUN" -eq 1 ]; then
    record skills plan "would copy $copied, keep $kept"
  else
    record skills ok "$copied copied, $kept kept"
  fi
}

# ---------------------------------------------------------------- AGENTS.md
write_agents() {
  if [ -z "$AGENTS_TARGET" ]; then
    step "AGENTS.md"
    printf '   - skipped (opt-in). Add --agents <workspace>/AGENTS.md to write it.\n'
    printf '   - preview it first: bash %s --print-agents\n' "$REPO_DIR/install.sh"
    record agents skip "opt-in, not requested"
    return 0
  fi

  step "AGENTS.md -> $AGENTS_TARGET"
  if [ "$DRY_RUN" -eq 1 ]; then
    plan "write $AGENTS_TARGET (replaces the global rules for every future session)"
    record agents plan "would write $AGENTS_TARGET"
    return 0
  fi

  if [ -e "$AGENTS_TARGET" ]; then
    if cmp -s "$REPO_DIR/AGENTS.md" "$AGENTS_TARGET"; then
      ok "already current"
      record agents ok "already current"
    else
      cp "$AGENTS_TARGET" "$AGENTS_TARGET.bak"
      cp "$REPO_DIR/AGENTS.md" "$AGENTS_TARGET"
      ok "replaced (old copy kept as AGENTS.md.bak)"
      record agents ok "replaced, backup kept"
    fi
  else
    mkdir -p "$(dirname "$AGENTS_TARGET")"
    cp "$REPO_DIR/AGENTS.md" "$AGENTS_TARGET"
    ok "written"
    record agents ok "written"
  fi
}

# ---------------------------------------------------------------- oo
install_oo() {
  step "oo (OOMOL connectors)"
  if have oo; then ok "already: $(oo --version 2>/dev/null | head -1 || echo present)"; record oo ok "already present"; return 0; fi
  if [ "$NETWORK_AVAILABLE" -ne 1 ]; then warn "skipped: network unavailable"; record oo skip "network unavailable"; return 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then plan "install oo from cli.oomol.com/install.sh"; record oo plan "would install"; return 0; fi
  if ! curl -fsSL --connect-timeout 5 --max-time "$NETWORK_TIMEOUT" https://cli.oomol.com/install.sh | run_limited "$NETWORK_TIMEOUT" bash; then
    warn "oo installer failed"
    record oo fail "installer failed"
    return 1
  fi
  export PATH="$HOME/.local/bin:$PATH"
  have oo && ok "installed" || { warn "oo not on PATH yet (open a new shell)"; record oo fail "not on PATH"; return 1; }
  record oo ok "installed"
}

# ---------------------------------------------------------------- composio
install_composio() {
  step "composio"
  if have composio; then ok "already: present"; record composio ok "already present"; return 0; fi
  if [ "$NETWORK_AVAILABLE" -ne 1 ]; then warn "skipped: network unavailable"; record composio skip "network unavailable"; return 0; fi
  if ! have unzip; then
    warn "unzip is required by the composio installer; run: sudo apt-get install -y unzip"
    record composio fail "unzip missing"
    return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then plan "install composio from composio.dev/install --no-plugins"; record composio plan "would install"; return 0; fi
  # --no-plugins keeps this to the single binary: no editor or agent plugins.
  if curl -fsSL --connect-timeout 5 --max-time "$NETWORK_TIMEOUT" https://composio.dev/install | run_limited "$NETWORK_TIMEOUT" sh -s -- --no-plugins; then
    export PATH="$HOME/.composio:$HOME/.local/bin:$PATH"
  else
    warn "composio installer failed or timed out"
    record composio fail "installer failed"
    return 1
  fi
  have composio && ok "installed" || { warn "composio not on PATH yet (open a new shell)"; record composio fail "not on PATH"; return 1; }
  record composio ok "installed"
}

# ---------------------------------------------------------------- officecli
install_officecli() {
  step "officecli"
  if have officecli; then ok "already: present"; record officecli ok "already present"; return 0; fi
  if [ "$NETWORK_AVAILABLE" -ne 1 ]; then warn "skipped: network unavailable"; record officecli skip "network unavailable"; return 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then plan "install officecli from d.officecli.ai/install.sh"; record officecli plan "would install"; return 0; fi
  if ! curl -fsSL --connect-timeout 5 --max-time "$NETWORK_TIMEOUT" https://d.officecli.ai/install.sh | run_limited "$NETWORK_TIMEOUT" bash; then
    warn "officecli installer failed or timed out"
    record officecli fail "installer failed"
    return 1
  fi
  export PATH="$HOME/.local/bin:$PATH"
  have officecli && ok "installed" || { warn "officecli not on PATH yet (open a new shell)"; record officecli fail "not on PATH"; return 1; }
  record officecli ok "installed"
}

# ---------------------------------------------------------------- browser
start_browser_install() {
  step "Playwright + Chrome (background)"
  local state_dir="$PAVE_HOME/browser-install"
  local status="$state_dir/status.txt"
  local log="$state_dir/install.log"
  local old_pid=""

  if [ "$DRY_RUN" -eq 1 ]; then
    plan "install agent-browser, Playwright, Chrome, Chromium in the background"
    plan "apt-get install -y xvfb xfonts-base (only if sudo -n works)"
    record browser plan "would start in background"
    return 0
  fi

  mkdir -p "$state_dir"

  if [ -f "$status" ]; then
    old_pid="$(sed -n 's/^pid=//p' "$status" | head -1)"
    if grep -qE '^state=(running|starting)$' "$status" && [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      ok "already running (pid $old_pid)"
      printf '   status: bash %s/browser-install-status.sh\n' "$REPO_DIR"
      record browser running "pid $old_pid"
      return 0
    fi
  fi

  printf 'state=starting\nphase=launching\nstarted=%s\nlog=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$log" > "$status"
  PAVE_HOME="$PAVE_HOME" ALLOW_APT="$ALLOW_APT" NPM_CONFIG_PREFIX="$NPM_CONFIG_PREFIX" \
    nohup bash "$REPO_DIR/install-browser-background.sh" >"$state_dir/launcher.log" 2>&1 &
  ok "started in background"
  printf '   status: bash %s/browser-install-status.sh\n' "$REPO_DIR"
  printf '   wait:   bash %s/browser-install-wait.sh\n' "$REPO_DIR"
  record browser running "background, see status"
}

# ---------------------------------------------------------------- heygen-mcp
install_heygen() {
  step "heygen-mcp (from the skill folder)"
  local src="$SKILLS_DIR/heygen-mcp"
  if have heygen-mcp; then ok "already: present"; record heygen-mcp ok "already present"; return 0; fi
  if [ ! -f "$src/package.json" ]; then warn "skill not found: $src"; record heygen-mcp skip "skill not found"; return 0; fi
  if ! have npm; then warn "npm not found, skipping heygen-mcp"; record heygen-mcp skip "npm missing"; return 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then plan "npm install -g . in $src"; record heygen-mcp plan "would install"; return 0; fi
  if ( cd "$src" && run_limited 60 npm install -g . >/dev/null 2>&1 ); then
    export PATH="$NPM_PREFIX/bin:$PATH"
    have heygen-mcp && ok "installed" || warn "heygen-mcp not on PATH yet"
    record heygen-mcp ok "installed"
  else
    warn "npm install -g . failed in $src"
    record heygen-mcp fail "npm install failed"
    return 1
  fi
}

# ---------------------------------------------------------------- summary
print_summary() {
  step "Summary"
  printf '   %-14s %-7s %s\n' "component" "state" "detail"
  local line name state detail
  if [ "${#SUMMARY[@]}" -gt 0 ]; then
    for line in "${SUMMARY[@]}"; do
      name="${line%%|*}"
      line="${line#*|}"
      state="${line%%|*}"
      detail="${line#*|}"
      printf '   %-14s %-7s %s\n' "$name" "$state" "$detail"
    done
  fi
  printf '\n   Installing is not logging in. Logins stay with the user: /setup\n'
}

# ---------------------------------------------------------------- main
if [ "$DRY_RUN" -eq 1 ]; then
  echo "pave-setup  home=$HOME  repo=$REPO_DIR  (dry run: nothing will change)"
else
  echo "pave-setup  home=$HOME  repo=$REPO_DIR"
fi

preflight
copy_skills
write_agents

if [ "$SKILLS_ONLY" -ne 1 ]; then
  failures=0
  install_oo || failures=$((failures + 1))
  install_composio || failures=$((failures + 1))
  install_officecli || failures=$((failures + 1))
  install_heygen || failures=$((failures + 1))
  if [ "$NO_BROWSER" -eq 1 ]; then
    printf '\n== Playwright + Chrome\n   - skipped (--no-browser)\n'
    if [ "$NO_NETWORK" -eq 1 ]; then
      record browser skip "--no-network"
    else
      record browser skip "--no-browser"
    fi
  elif [ "$NETWORK_AVAILABLE" -ne 1 ]; then
    printf '\n== Playwright + Chrome\n   - skipped (network unavailable)\n'
    record browser skip "network unavailable"
  else
    start_browser_install
  fi
  print_summary
  if [ "$failures" -gt 0 ]; then
    printf '\n%s step(s) failed. See the lines marked ! above.\n' "$failures" >&2
    exit 1
  fi
else
  record cli skip "--skills-only"
  print_summary
fi

printf '\nDone. Next: bash %s/verify.sh\n' "$REPO_DIR"
if [ "$SKILLS_ONLY" -ne 1 ] && [ "$NO_BROWSER" -ne 1 ] && [ "$NETWORK_AVAILABLE" -eq 1 ]; then
  printf 'Browser install continues in background. Monitor: bash %s/browser-install-status.sh\n' "$REPO_DIR"
  printf 'Wait for completion: bash %s/browser-install-wait.sh\n' "$REPO_DIR"
fi
