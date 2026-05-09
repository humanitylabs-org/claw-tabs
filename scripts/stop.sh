#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$APP_DIR/.runtime/server.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No server.pid file found."
  exit 0
fi

PID="$(cat "$PID_FILE" 2>/dev/null || true)"
if [[ -z "$PID" ]]; then
  rm -f "$PID_FILE"
  echo "Empty PID file removed."
  exit 0
fi

if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "Stopped Claw Tabs server (pid $PID)."
else
  echo "PID $PID was not running."
fi

rm -f "$PID_FILE"
