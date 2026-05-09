#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$APP_DIR/.runtime"
REPORT_FILE="$RUNTIME_DIR/prereq-report.txt"
mkdir -p "$RUNTIME_DIR"

PORT="${CLAWTABS_PORT:-8788}"
BASE_PATH="${CLAWTABS_BASE_PATH:-/clawtabs}"

FAIL=0
WARN=0

declare -a FIX_ITEMS=()
declare -a FAIL_ITEMS=()
declare -a WARN_ITEMS=()

ok() { echo "✅ $1"; }
warn() {
  echo "⚠️  $1"
  WARN=1
  WARN_ITEMS+=("$1")
}
fail() {
  local message="$1"
  local fix="${2:-}"
  echo "❌ $message"
  FAIL=1
  FAIL_ITEMS+=("$message")
  if [[ -n "$fix" ]]; then
    FIX_ITEMS+=("$message|||$fix")
  fi
}

print_fix_hints() {
  if [[ "${#FIX_ITEMS[@]}" -eq 0 ]]; then
    return
  fi

  echo
  echo "Suggested safe fixes"
  echo "--------------------"
  local i=1
  for item in "${FIX_ITEMS[@]}"; do
    local issue="${item%%|||*}"
    local fix="${item#*|||}"
    echo "${i}) ${issue}"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "   $line"
    done <<<"$fix"
    echo
    i=$((i + 1))
  done
}

echo "Claw Tabs prerequisite check"
echo "Report file: $REPORT_FILE"
echo

exec > >(tee "$REPORT_FILE") 2>&1

if command -v tailscale >/dev/null 2>&1; then
  ok "tailscale CLI found"
else
  fail "tailscale CLI not found" $'Install Tailscale first:\n- https://tailscale.com/download\nLinux quick path (needs approval):\n  curl -fsSL https://tailscale.com/install.sh | sh'
fi

if command -v tailscale >/dev/null 2>&1; then
  if tailscale status >/dev/null 2>&1; then
    ok "Tailscale daemon reachable"
  else
    fail "Tailscale daemon not reachable or not authenticated" $'Try:\n  tailscale up\nIf tailscaled service is stopped (Linux/systemd):\n  sudo systemctl enable --now tailscaled'
  fi

  if tailscale serve status >/dev/null 2>&1; then
    ok "tailscale serve is available"
  else
    fail "tailscale serve is not ready on this tailnet/device" $'Try:\n  tailscale serve 3000\nThen follow any HTTPS/consent prompt once, and re-run this check.'
  fi
fi

if command -v node >/dev/null 2>&1; then
  ok "node found: $(node -v)"
else
  fail "node is not installed" $'Install Node.js 20+ and re-run this check.'
fi

if command -v openclaw >/dev/null 2>&1; then
  ok "openclaw CLI found"
else
  warn "openclaw CLI not found (UI can still run, but you need a reachable OpenClaw gateway)"
fi

if command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -q ":${PORT} "; then
    warn "port ${PORT} appears in use (set CLAWTABS_PORT to another value)"
  else
    ok "port ${PORT} appears available"
  fi
elif command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "port ${PORT} appears in use (set CLAWTABS_PORT to another value)"
  else
    ok "port ${PORT} appears available"
  fi
else
  warn "could not verify port usage (ss/lsof not found)"
fi

ok "base path configured: ${BASE_PATH}"

# Optional panel checks (non-blocking)
OS_UNAME="$(uname -s)"
if [[ "$OS_UNAME" == "Linux" ]]; then
  if command -v ttyd >/dev/null 2>&1; then
    ok "panel optional dep: ttyd found"
  else
    warn "panel optional dep missing: ttyd (run ./scripts/setup-panels.sh --terminal)"
  fi

  if command -v Xvfb >/dev/null 2>&1 && command -v x11vnc >/dev/null 2>&1; then
    ok "panel optional deps for browser found (Xvfb + x11vnc)"
  else
    warn "panel optional deps missing for browser panel (run ./scripts/setup-panels.sh --browser)"
  fi
elif [[ "$OS_UNAME" == "Darwin" ]]; then
  warn "Browser panel auto-setup is Linux-only right now. Terminal panel is supported on macOS via ./scripts/setup-panels.sh --terminal"
fi

echo
if [[ "$FAIL" -ne 0 ]]; then
  echo "Prerequisite check failed (${#FAIL_ITEMS[@]} required issue(s))."
  print_fix_hints
  exit 1
fi

echo "All required checks passed."
if [[ "$WARN" -ne 0 ]]; then
  echo "Warnings: ${#WARN_ITEMS[@]}"
fi
