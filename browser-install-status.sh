#!/usr/bin/env bash
set -u

PAVE_HOME="${PAVE_HOME:-$HOME/.pave}"
STATUS_FILE="${PAVE_HOME}/browser-install/status.txt"
LOG_FILE="${PAVE_HOME}/browser-install/install.log"

if [ ! -f "$STATUS_FILE" ]; then
  echo "state=not_started"
  echo "log=$LOG_FILE"
  exit 0
fi

cat "$STATUS_FILE"
state="$(sed -n 's/^state=//p' "$STATUS_FILE" | head -1)"
if [ "$state" = "running" ] && [ -f "$LOG_FILE" ]; then
  echo
  echo "--- recent log ---"
  tail -n 25 "$LOG_FILE"
fi
