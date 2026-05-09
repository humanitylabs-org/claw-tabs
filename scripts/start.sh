#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$APP_DIR/.runtime"
PID_FILE="$RUNTIME_DIR/server.pid"
LOG_FILE="$RUNTIME_DIR/server.log"
mkdir -p "$RUNTIME_DIR"

HOST="${CLAWTABS_HOST:-127.0.0.1}"
PORT="${CLAWTABS_PORT:-8788}"
BASE_PATH="${CLAWTABS_BASE_PATH:-/clawtabs}"
HEALTH_URL="http://${HOST}:${PORT}${BASE_PATH}/api/health"

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Claw Tabs server already running (pid $OLD_PID)"
    echo "Health: $HEALTH_URL"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

cd "$APP_DIR"

nohup env CLAWTABS_HOST="$HOST" CLAWTABS_PORT="$PORT" CLAWTABS_BASE_PATH="$BASE_PATH" node scripts/server.mjs >"$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"

for _ in $(seq 1 50); do
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    echo "✅ Claw Tabs server started (pid $PID)"
    echo "Health: $HEALTH_URL"
    exit 0
  fi
  sleep 0.2
done

echo "❌ Claw Tabs server failed to start"
echo "Last log lines:"
tail -n 40 "$LOG_FILE" || true
exit 1
