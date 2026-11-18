#!/usr/bin/env bash
# pave-setup installer — installs the PAVE toolchain into the current user account.
# Idempotent: every step is skipped when the tool is already present.
set -euo pipefail

SKILLS_ONLY=0
NO_BROWSER=0
ALLOW_APT=1
FORCE_SKILLS=0
AGENTS_TARGET=""

usage() {
  cat <<'EOF'
usage: install.sh [options]

  --skills-only     copy skills and AGENTS.md only (no CLI download)
  --no-browser      do not install Playwright, Chrome, or agent-browser
  --with-browser    accepted for compatibility; browser install is now the default
  --no-apt          never call apt-get, even for browser deps
  --force-skills    overwrite skills that already exist
  --agents <path>   where to write AGENTS.md (default: the current directory)
  -h, --help        show this help

Environment:
  PAVE_HOME         default $HOME/.pave
  OO_TEAM           team name for `oo login` (never a token)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-browser) : ;;
    --no-browser) NO_BROWSER=1 ;;
    --skills-only) SKILLS_ONLY=1 ;;
    --no-apt) ALLOW_APT=0 ;;
    --force-skills) FORCE_SKILLS=1 ;;
    --agents) AGENTS_TARGET="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skills"
PAVE_HOME="${PAVE_HOME:-$HOME/.pave}"
SKILLS_DIR="$PAVE_HOME/skills"
[ -n "$AGENTS_TARGET" ] || AGENTS_TARGET="$PWD/AGENTS.md"
NPM_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
export NPM_CONFIG_PREFIX="$NPM_PREFIX"
mkdir -p "$NPM_PREFIX/bin"

export PATH="$NPM_PREFIX/bin:$HOME/.local/bin:$HOME/.composio:$HOME/.npm-global/bin:$PATH"

have() { command -v "$1" >/dev/null 2>&1; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
ok()   { printf '   + %s\n' "$*"; }

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo && sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    return 1
  fi
}

preflight() {
  step "Prerequisites"
  mkdir -p "$HOME/.local/bin" "$HOME/.composio" "$NPM_PREFIX/bin" "$SKILLS_DIR"

  if have npm; then
    ok "npm global prefix: $NPM_CONFIG_PREFIX"
  else
    warn "npm not found: heygen-mcp, Playwright, and agent-browser cannot install"
  fi

  if have unzip; then
    ok "unzip present"
  elif [ "$ALLOW_APT" -eq 1 ] && have apt-get && as_root apt-get update >/dev/null 2>&1; then
    if as_root apt-get install -y unzip >/dev/null 2>&1 && have unzip; then
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
  local d name
  for d in "$SKILL_SRC"/*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -e "$SKILLS_DIR/$name" ] && [ "$FORCE_SKILLS" -ne 1 ]; then
      ok "kept    $name"
      continue
    fi
    rm -rf "$SKILLS_DIR/$name"
    cp -a "$d" "$SKILLS_DIR/"
    ok "copied  $name"
  done
}

# ---------------------------------------------------------------- AGENTS.md
write_agents() {
  step "AGENTS.md -> $AGENTS_TARGET"
  if [ -e "$AGENTS_TARGET" ]; then
    if cmp -s "$REPO_DIR/AGENTS.md" "$AGENTS_TARGET"; then
      ok "already current"
    else
      cp "$AGENTS_TARGET" "$AGENTS_TARGET.bak"
      cp "$REPO_DIR/AGENTS.md" "$AGENTS_TARGET"
      ok "replaced (old copy kept as AGENTS.md.bak)"
    fi
  else
    mkdir -p "$(dirname "$AGENTS_TARGET")"
    cp "$REPO_DIR/AGENTS.md" "$AGENTS_TARGET"
    ok "written"
  fi
}

# ---------------------------------------------------------------- oo
install_oo() {
  step "oo (OOMOL connectors)"
  if have oo; then ok "already: $(oo --version 2>/dev/null || echo present)"; return 0; fi
  if ! curl -fsSL https://cli.oomol.com/install.sh | bash; then
    warn "oo installer failed"
    return 1
  fi
  export PATH="$HOME/.local/bin:$PATH"
  have oo && ok "installed" || { warn "oo not on PATH yet (open a new shell)"; return 1; }
}

# ---------------------------------------------------------------- composio
install_composio() {
  step "composio"
  if have composio; then ok "already: present"; return 0; fi
  if ! have unzip; then
    warn "unzip is required by the composio installer; run: sudo apt-get install -y unzip"
    return 1
  fi
  # --no-plugins keeps this to the single binary: no editor or agent plugins.
  if curl -fsSL https://composio.dev/install | sh -s -- --no-plugins; then
    export PATH="$HOME/.composio:$HOME/.local/bin:$PATH"
  else
    warn "retrying composio install without --no-plugins"
    curl -fsSL https://composio.dev/install | sh
    export PATH="$HOME/.composio:$HOME/.local/bin:$PATH"
  fi
  have composio && ok "installed" || { warn "composio not on PATH yet (open a new shell)"; return 1; }
}

# ---------------------------------------------------------------- officecli
install_officecli() {
  step "officecli"
  if have officecli; then ok "already: present"; return 0; fi
  if ! curl -fsSL https://d.officecli.ai/install.sh | bash; then
    warn "officecli installer failed"
    return 1
  fi
  export PATH="$HOME/.local/bin:$PATH"
  have officecli && ok "installed" || { warn "officecli not on PATH yet (open a new shell)"; return 1; }
}

# ---------------------------------------------------------------- browser
start_browser_install() {
  step "Playwright + Chrome (background)"
  local state_dir="$PAVE_HOME/browser-install"
  local status="$state_dir/status.txt"
  local log="$state_dir/install.log"
  local old_pid=""
  mkdir -p "$state_dir"

  if [ -f "$status" ]; then
    old_pid="$(sed -n 's/^pid=//p' "$status" | head -1)"
    if grep -qE '^state=(running|starting)$' "$status" && [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      ok "already running (pid $old_pid)"
      printf '   status: bash %s/browser-install-status.sh\n' "$REPO_DIR"
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
}

# ---------------------------------------------------------------- heygen-mcp
install_heygen() {
  step "heygen-mcp (from the skill folder)"
  local src="$SKILLS_DIR/heygen-mcp"
  if have heygen-mcp; then ok "already: present"; return 0; fi
  if [ ! -f "$src/package.json" ]; then warn "skill not found: $src"; return 0; fi
  if ! have npm; then warn "npm not found, skipping heygen-mcp"; return 0; fi
  if ( cd "$src" && npm install -g . >/dev/null 2>&1 ); then
    export PATH="$HOME/.npm-global/bin:$PATH"
    have heygen-mcp && ok "installed" || warn "heygen-mcp not on PATH yet"
  else
    warn "npm install -g . failed in $src"
  fi
}

# ---------------------------------------------------------------- main
echo "pave-setup  home=$HOME  repo=$REPO_DIR"

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
  else
    start_browser_install
  fi
  if [ "$failures" -gt 0 ]; then
    printf '\n%s step(s) failed. See the lines marked ! above.\n' "$failures" >&2
    exit 1
  fi
fi

printf '\nDone. Next: bash %s/verify.sh\n' "$REPO_DIR"
if [ "$SKILLS_ONLY" -ne 1 ] && [ "$NO_BROWSER" -ne 1 ]; then
  printf 'Browser install continues in background. Monitor: bash %s/browser-install-status.sh\n' "$REPO_DIR"
  printf 'Wait for completion: bash %s/browser-install-wait.sh\n' "$REPO_DIR"
fi
