#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

HOST="${CLAWTABS_HOST:-127.0.0.1}"
PORT="${CLAWTABS_PORT:-8788}"
BASE_PATH="${CLAWTABS_BASE_PATH:-/clawtabs}"
BASE_PATH="/${BASE_PATH#/}"
BASE_PATH="${BASE_PATH%/}"

LOCAL_HEALTH="http://${HOST}:${PORT}${BASE_PATH}/api/health"


echo "Step 1/4: prerequisite check"
./scripts/prereq-check.sh

echo
echo "Step 2/4: start local app server"
./scripts/start.sh

echo
echo "Step 3/4: expose tailnet path"
./scripts/serve-path.sh

echo
echo "Step 4/4: verify install"
if curl -fsS "$LOCAL_HEALTH" >/dev/null; then
  echo "✅ Local health check passed: $LOCAL_HEALTH"
else
  echo "❌ Local health check failed: $LOCAL_HEALTH"
  exit 1
fi

python3 - <<PY
import json, pathlib, sys
manifest = json.loads(pathlib.Path("manifest.json").read_text())
expected = "${BASE_PATH}/"
errors = []
for key in ("id", "start_url", "scope"):
    if manifest.get(key) != expected:
        errors.append(f"{key}={manifest.get(key)!r} (expected {expected!r})")
if errors:
    print("❌ Manifest scope check failed:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("✅ Manifest scope check passed")
PY

DNS_NAME="$(tailscale status --self --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName", "").rstrip("."))' 2>/dev/null || true)"
if [[ -n "$DNS_NAME" ]]; then
  echo "✅ Final URL: https://${DNS_NAME}${BASE_PATH}"
else
  echo "✅ Final URL: https://<this-device>.ts.net${BASE_PATH}"
fi
