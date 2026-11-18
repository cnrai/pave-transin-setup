#!/usr/bin/env bash
# Fail when a credential or a personal email is committed to this repo.
# Usage: bash secret-scan.sh [--history]
#   --history  also scan every commit in the repo (slower)
set -uo pipefail

HISTORY=0
for arg in "$@"; do
  case "$arg" in
    --history) HISTORY=1 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2

# Placeholders are fine; only a real value is a finding.
PLACEHOLDER_RE='XXXXXX|<[^>]*>|YOUR_|your-|example|EXAMPLE|\$\{|\$[A-Z_]+'

SECRET_RES=(
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'
  'gh[pousr]_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'sk-[A-Za-z0-9_-]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[abprs]-[A-Za-z0-9-]{10,}'
  'user_code=[A-Za-z0-9]{6,}'
)

EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
EMAIL_ALLOW_RE='example\.(com|org)|users\.noreply\.github\.com|github\.com|npmjs\.com|dex\.moe|w3\.org|schema\.org|anthropic\.com|openai\.com'

if [ "$HISTORY" -eq 1 ]; then
  REVS="$(git rev-list --all 2>/dev/null || true)"
  echo "secret-scan: all commits"
else
  REVS=""
  echo "secret-scan: working tree"
fi

collect() { # collect <regex> -> matching "path:line:text" lines
  if [ "$HISTORY" -eq 1 ]; then
    [ -n "$REVS" ] || return 0
    git grep -n -I -E "$1" $REVS 2>/dev/null
  else
    git grep -n -I --untracked -E "$1" -- . 2>/dev/null
  fi
}

strip_placeholders() {
  grep -Ev "$PLACEHOLDER_RE" || true
}

findings=0
for re in "${SECRET_RES[@]}"; do
  out="$(collect "$re" | strip_placeholders)"
  [ -n "$out" ] || continue
  n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  findings=$((findings + n))
  printf '%s\n' "$out" | while IFS= read -r line; do
    printf '  FAIL  %s  %s\n' "$re" "$line"
  done
done

emails="$(collect "$EMAIL_RE" | grep -Ev "$EMAIL_ALLOW_RE" || true)"
warnings=0
if [ -n "$emails" ]; then
  warnings="$(printf '%s\n' "$emails" | wc -l | tr -d ' ')"
  echo
  echo "personal email (warn):"
  printf '%s\n' "$emails" | sed 's/^/  WARN  /'
fi

echo
if [ "$findings" -gt 0 ]; then
  printf 'result: %s credential finding(s), %s email warning(s)\n' "$findings" "$warnings"
  echo 'Rotate the credential, then remove it from git history before pushing.'
  exit 1
fi
printf 'result: no credentials found (%s email warning(s))\n' "$warnings"
exit 0
