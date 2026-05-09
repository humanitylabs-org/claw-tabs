#!/usr/bin/env bash
set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale CLI not found on PATH."
  exit 1
fi

if ! tailscale status >/dev/null 2>&1; then
  echo "tailscale is not connected. Run: tailscale up"
  exit 1
fi

PORT="${CLAWTABS_PORT:-8788}"
BASE_PATH="${CLAWTABS_BASE_PATH:-/clawtabs}"
BASE_PATH="/${BASE_PATH#/}"
BASE_PATH="${BASE_PATH%/}"
TARGET="http://127.0.0.1:${PORT}${BASE_PATH}"

echo "Configuring Tailscale Serve path: ${BASE_PATH} -> ${TARGET}"
tailscale serve --bg --https=443 --set-path="$BASE_PATH" "$TARGET"

DNS_NAME="$(tailscale status --self --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName", "").rstrip("."))' 2>/dev/null || true)"
if [[ -n "$DNS_NAME" ]]; then
  echo
  echo "Done. Open: https://${DNS_NAME}${BASE_PATH}"
else
  echo
  echo "Done. Open: https://<this-device>.ts.net${BASE_PATH}"
fi
