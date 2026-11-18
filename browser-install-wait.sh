#!/usr/bin/env bash
set -u

PAVE_HOME="${PAVE_HOME:-$HOME/.pave}"
STATUS_FILE="${PAVE_HOME}/browser-install/status.txt"
LOG_FILE="${PAVE_HOME}/browser-install/install.log"
TIMEOUT="${BROWSER_WAIT_TIMEOUT:-1800}"
START="$(date +%s)"

while :; do
  if [ ! -f "$STATUS_FILE" ]; then
    echo "state=not_started"
    exit 2
  fi

  state="$(sed -n 's/^state=//p' "$STATUS_FILE" | head -1)"
  case "$state" in
    done|partial|failed)
      cat "$STATUS_FILE"
      if [ "$state" = "failed" ] && [ -f "$LOG_FILE" ]; then
        echo
        echo "--- last 40 log lines ---"
        tail -n 40 "$LOG_FILE"
      fi
      [ "$state" = "failed" ] && exit 1
      exit 0
      ;;
  esac

  if [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ]; then
    echo "state=timeout"
    echo "log=$LOG_FILE"
    exit 3
  fi
  sleep 2
done
