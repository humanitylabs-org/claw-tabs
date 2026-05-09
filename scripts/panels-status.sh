#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_UNAME="$(uname -s)"

case "$OS_UNAME" in
  Linux) OS="linux" ;;
  Darwin) OS="darwin" ;;
  *) OS="other" ;;
esac

has_cmd() {
  command -v "$1" >/dev/null 2>&1 && echo 1 || echo 0
}

port_open() {
  local port="$1"
  python3 - "$port" <<'PY' 2>/dev/null
import socket, sys
port = int(sys.argv[1])
s = socket.socket()
s.settimeout(0.6)
try:
    s.connect(("127.0.0.1", port))
    print("1")
except Exception:
    print("0")
finally:
    s.close()
PY
}

port_open_bool() {
  local port="$1"
  local out
  out="$(port_open "$port" || true)"
  [[ "$out" == "1" ]] && echo 1 || echo 0
}

tailscale_ok=0
serve_ok=0
if command -v tailscale >/dev/null 2>&1; then
  if tailscale status >/dev/null 2>&1; then
    tailscale_ok=1
  fi
  if tailscale serve status >/dev/null 2>&1; then
    serve_ok=1
  fi
fi

serve_text=""
if [[ "$serve_ok" -eq 1 ]]; then
  serve_text="$(tailscale serve status 2>/dev/null || true)"
fi

serve_has_port() {
  local port="$1"
  if [[ -z "$serve_text" ]]; then
    echo 0
    return
  fi
  if grep -q ":${port}" <<<"$serve_text"; then
    echo 1
  else
    echo 0
  fi
}

browser_supported=0
browser_reason=""
terminal_supported=0

if [[ "$OS" == "linux" ]]; then
  terminal_supported=1
  browser_supported=1
elif [[ "$OS" == "darwin" ]]; then
  terminal_supported=1
  browser_supported=0
  browser_reason="Browser panel auto-setup is Linux-only right now."
else
  terminal_supported=0
  browser_supported=0
  browser_reason="Unsupported OS for panel automation."
fi

browser_cmd=0
if [[ "$(has_cmd chromium)" -eq 1 || "$(has_cmd chromium-browser)" -eq 1 || "$(has_cmd google-chrome)" -eq 1 ]]; then
  browser_cmd=1
fi

browser_deps=0
if [[ "$OS" == "linux" ]]; then
  if [[ "$(has_cmd Xvfb)" -eq 1 && "$(has_cmd x11vnc)" -eq 1 && "$(has_cmd websockify)" -eq 1 && "$browser_cmd" -eq 1 ]]; then
    if [[ -x /usr/share/novnc/utils/launch.sh ]] || command -v novnc_proxy >/dev/null 2>&1; then
      browser_deps=1
    fi
  fi
fi

terminal_cmd="$(has_cmd ttyd)"
browser_port="$(port_open_bool 6080)"
terminal_port="$(port_open_bool 7681)"
browser_serve="$(serve_has_port 6080)"
terminal_serve="$(serve_has_port 7681)"

terminal_service=0
browser_service=0

if [[ "$OS" == "linux" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet web-terminal.service 2>/dev/null; then terminal_service=1; fi
    if systemctl is-active --quiet remote-browser.service 2>/dev/null; then browser_service=1; fi
  fi
elif [[ "$OS" == "darwin" ]]; then
  pid_file="$APP_DIR/.runtime/ttyd.pid"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then terminal_service=1; fi
  fi
fi

terminal_ready=0
if [[ "$terminal_supported" -eq 1 && "$terminal_cmd" -eq 1 && "$terminal_port" -eq 1 && "$terminal_serve" -eq 1 ]]; then
  terminal_ready=1
fi

browser_ready=0
if [[ "$browser_supported" -eq 1 && "$browser_deps" -eq 1 && "$browser_port" -eq 1 && "$browser_serve" -eq 1 ]]; then
  browser_ready=1
fi

status_ok=0
if [[ "$terminal_ready" -eq 1 && ( "$browser_supported" -eq 0 || "$browser_ready" -eq 1 ) ]]; then
  status_ok=1
fi

export APP_DIR OS OS_UNAME tailscale_ok serve_ok browser_supported browser_reason terminal_supported
export terminal_cmd terminal_port terminal_serve terminal_service terminal_ready
export browser_cmd browser_deps browser_port browser_serve browser_service browser_ready status_ok

python3 - <<'PY'
import json, os

def b(name):
    return os.environ.get(name, "0") == "1"

def s(name, default=""):
    return os.environ.get(name, default)

app_dir = s("APP_DIR")
os_name = s("OS")

out = {
    "ok": b("status_ok"),
    "os": os_name,
    "osRaw": s("OS_UNAME"),
    "appDir": app_dir,
    "tailscale": {
        "connected": b("tailscale_ok"),
        "serveAvailable": b("serve_ok"),
    },
    "support": {
        "terminal": b("terminal_supported"),
        "browser": b("browser_supported"),
        "browserReason": s("browser_reason"),
    },
    "terminal": {
        "commandInstalled": b("terminal_cmd"),
        "serviceActive": b("terminal_service"),
        "portListening": b("terminal_port"),
        "serveMapped": b("terminal_serve"),
        "ready": b("terminal_ready"),
        "setupCommand": f'cd "{app_dir}" && ./scripts/setup-panels.sh --terminal',
    },
    "browser": {
        "depsInstalled": b("browser_deps"),
        "serviceActive": b("browser_service"),
        "portListening": b("browser_port"),
        "serveMapped": b("browser_serve"),
        "ready": b("browser_ready"),
        "setupCommand": f'cd "{app_dir}" && ./scripts/setup-panels.sh --browser',
    },
    "allCommand": f'cd "{app_dir}" && ./scripts/setup-panels.sh --all',
}

print(json.dumps(out, ensure_ascii=False))
PY
