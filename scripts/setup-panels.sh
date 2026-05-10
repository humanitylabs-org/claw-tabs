#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$APP_DIR/.runtime"
mkdir -p "$RUNTIME_DIR"

MODE="all"

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-panels.sh [--all|--terminal|--browser]

Installs and configures optional Claw Tabs panel dependencies.

Modes:
  --all       Setup terminal + browser panels (default)
  --terminal  Setup terminal panel only
  --browser   Setup browser panel only (Linux only)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      MODE="all"
      shift
      ;;
    --terminal)
      MODE="terminal"
      shift
      ;;
    --browser)
      MODE="browser"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

OS_UNAME="$(uname -s)"
case "$OS_UNAME" in
  Linux) OS="linux" ;;
  Darwin) OS="darwin" ;;
  *) OS="other" ;;
esac

if [[ "$OS" == "other" ]]; then
  echo "❌ Unsupported OS: $OS_UNAME"
  exit 1
fi

WANT_TERMINAL=0
WANT_BROWSER=0
case "$MODE" in
  all)
    WANT_TERMINAL=1
    WANT_BROWSER=1
    ;;
  terminal)
    WANT_TERMINAL=1
    ;;
  browser)
    WANT_BROWSER=1
    ;;
esac

if [[ "$OS" == "darwin" && "$WANT_BROWSER" -eq 1 ]]; then
  echo "⚠️ Browser panel auto-setup is Linux-only right now (needs Xvfb/noVNC stack)."
  echo "   On macOS, terminal panel is supported; browser panel can be added later."
  if [[ "$MODE" == "browser" ]]; then
    exit 1
  fi
  WANT_BROWSER=0
fi

ok() { echo "✅ $1"; }
warn() { echo "⚠️  $1"; }
fail() { echo "❌ $1"; exit 1; }

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "This step needs root privileges, but sudo is not installed."
  fi
}

ensure_tailscale_ready() {
  command -v tailscale >/dev/null 2>&1 || fail "tailscale CLI not found. Install Tailscale first: https://tailscale.com/download"
  tailscale status >/dev/null 2>&1 || fail "Tailscale is not connected. Run: tailscale up"
  tailscale serve status >/dev/null 2>&1 || fail "tailscale serve is not ready yet. Run: tailscale serve 3000 and complete the consent flow once."
}

map_ttyd_asset() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    armv7l|armv6l) echo "arm" ;;
    i386|i686) echo "i686" ;;
    *) echo "" ;;
  esac
}

install_ttyd_binary_fallback() {
  local asset tmpdir url
  asset="$(map_ttyd_asset)"
  [[ -n "$asset" ]] || return 1

  tmpdir="$(mktemp -d)"
  url="https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.${asset}"

  if ! command -v curl >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 1
  fi

  if ! curl -fsSL "$url" -o "$tmpdir/ttyd"; then
    rm -rf "$tmpdir"
    return 1
  fi

  chmod +x "$tmpdir/ttyd"
  if [[ -w /usr/local/bin ]]; then
    install -m 0755 "$tmpdir/ttyd" /usr/local/bin/ttyd
  else
    as_root install -m 0755 "$tmpdir/ttyd" /usr/local/bin/ttyd
  fi

  rm -rf "$tmpdir"
  return 0
}

install_ttyd() {
  if command -v ttyd >/dev/null 2>&1; then
    ok "ttyd already installed"
    return
  fi

  echo "Installing ttyd..."

  if command -v brew >/dev/null 2>&1; then
    brew install ttyd || true
  fi

  if ! command -v ttyd >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    as_root apt-get update
    as_root apt-get install -y ttyd || true
  fi

  if ! command -v ttyd >/dev/null 2>&1 && command -v dnf >/dev/null 2>&1; then
    as_root dnf install -y ttyd || true
  fi

  if ! command -v ttyd >/dev/null 2>&1 && command -v yum >/dev/null 2>&1; then
    as_root yum install -y ttyd || true
  fi

  if ! command -v ttyd >/dev/null 2>&1 && command -v pacman >/dev/null 2>&1; then
    as_root pacman -Sy --noconfirm ttyd || true
  fi

  if ! command -v ttyd >/dev/null 2>&1; then
    install_ttyd_binary_fallback || true
  fi

  command -v ttyd >/dev/null 2>&1 || fail "Could not install ttyd automatically. Install manually, then rerun this script."
  ok "ttyd installed: $(ttyd --version 2>/dev/null | head -n 1 || echo ttyd)"
}

setup_terminal_linux() {
  cat <<'EOF' >/tmp/web-terminal.service
[Unit]
Description=Web Terminal (ttyd via Tailscale)
After=network-online.target

[Service]
Type=simple
User=root
Environment=HOME=/root
Environment=TERM=xterm-256color
ExecStart=/usr/local/bin/ttyd \
  --interface 127.0.0.1 \
  --port 7681 \
  --writable \
  --max-clients 3 \
  --ping-interval 30 \
  --client-option titleFixed=Tailnet-Terminal \
  --client-option title=Tailnet-Terminal \
  bash
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  as_root cp /tmp/web-terminal.service /etc/systemd/system/web-terminal.service
  rm -f /tmp/web-terminal.service

  as_root systemctl daemon-reload
  as_root systemctl enable --now web-terminal.service
  systemctl is-active --quiet web-terminal.service || fail "web-terminal.service failed to start"

  tailscale serve --bg --https=7681 http://127.0.0.1:7681 >/dev/null
  ok "Terminal panel ready on :7681"
}

setup_terminal_macos() {
  local pid_file log_file
  pid_file="$RUNTIME_DIR/ttyd.pid"
  log_file="$RUNTIME_DIR/ttyd.log"

  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      ok "ttyd already running (pid $old_pid)"
    else
      rm -f "$pid_file"
    fi
  fi

  if [[ ! -f "$pid_file" ]]; then
    nohup ttyd --interface 127.0.0.1 --port 7681 --writable --max-clients 3 --ping-interval 30 --client-option titleFixed=Tailnet-Terminal --client-option title=Tailnet-Terminal "$SHELL" -l >"$log_file" 2>&1 &
    echo "$!" >"$pid_file"
    sleep 0.6
  fi

  tailscale serve --bg --https=7681 http://127.0.0.1:7681 >/dev/null
  ok "Terminal panel ready on :7681"
  warn "macOS terminal service is started in user space (nohup). Re-run this script after reboot if needed."
}

find_browser_bin() {
  if command -v chromium >/dev/null 2>&1; then echo "chromium"; return; fi
  if command -v chromium-browser >/dev/null 2>&1; then echo "chromium-browser"; return; fi
  if command -v google-chrome >/dev/null 2>&1; then echo "google-chrome"; return; fi
  echo ""
}

install_browser_deps_linux() {
  local browser_bin

  if command -v Xvfb >/dev/null 2>&1 && command -v x11vnc >/dev/null 2>&1 && command -v websockify >/dev/null 2>&1 && [[ -x /usr/share/novnc/utils/launch.sh ]]; then
    ok "Browser dependencies already installed"
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    as_root apt-get update
    as_root apt-get install -y xvfb x11vnc websockify novnc
  elif command -v dnf >/dev/null 2>&1; then
    as_root dnf install -y xorg-x11-server-Xvfb x11vnc python3-websockify novnc
  elif command -v yum >/dev/null 2>&1; then
    as_root yum install -y xorg-x11-server-Xvfb x11vnc python3-websockify novnc
  elif command -v pacman >/dev/null 2>&1; then
    as_root pacman -Sy --noconfirm xorg-server-xvfb x11vnc websockify novnc
  else
    fail "No supported package manager found for browser dependencies"
  fi

  browser_bin="$(find_browser_bin)"
  if [[ -z "$browser_bin" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      as_root apt-get install -y chromium || true
    elif command -v dnf >/dev/null 2>&1; then
      as_root dnf install -y chromium || true
    elif command -v yum >/dev/null 2>&1; then
      as_root yum install -y chromium || true
    elif command -v pacman >/dev/null 2>&1; then
      as_root pacman -Sy --noconfirm chromium || true
    fi
  fi

  browser_bin="$(find_browser_bin)"
  [[ -n "$browser_bin" ]] || fail "Chromium/Chrome not found. Install one browser binary (chromium or google-chrome) and rerun."

  command -v Xvfb >/dev/null 2>&1 || fail "Xvfb missing after install"
  command -v x11vnc >/dev/null 2>&1 || fail "x11vnc missing after install"
  command -v websockify >/dev/null 2>&1 || fail "websockify missing after install"
  [[ -x /usr/share/novnc/utils/launch.sh ]] || fail "noVNC launch script missing at /usr/share/novnc/utils/launch.sh"

  ok "Browser dependencies installed"
}

setup_browser_linux() {
  cat <<'EOF' >/tmp/remote-browser.sh
#!/bin/bash
set -euo pipefail
export DISPLAY=:99

if command -v chromium >/dev/null 2>&1; then
  BROWSER_BIN="chromium"
elif command -v chromium-browser >/dev/null 2>&1; then
  BROWSER_BIN="chromium-browser"
elif command -v google-chrome >/dev/null 2>&1; then
  BROWSER_BIN="google-chrome"
else
  echo "No Chromium/Chrome binary found" >&2
  exit 1
fi

if [[ -x /usr/share/novnc/utils/launch.sh ]]; then
  NOVNC_LAUNCH="/usr/share/novnc/utils/launch.sh"
elif command -v novnc_proxy >/dev/null 2>&1; then
  NOVNC_LAUNCH="$(command -v novnc_proxy)"
else
  echo "noVNC launcher not found" >&2
  exit 1
fi

NOVNC_WEB_ROOT="/usr/local/share/remote-browser/novnc"
mkdir -p "$NOVNC_WEB_ROOT"
for item in /usr/share/novnc/*; do
  name="$(basename "$item")"
  [[ "$name" == "index.html" ]] && continue
  ln -sfn "$item" "$NOVNC_WEB_ROOT/$name"
done
cat >"$NOVNC_WEB_ROOT/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <meta name="theme-color" content="#0B0B0D" />
  <title>🧭 Tailnet Browser</title>
</head>
<body style="margin:0;background:#0B0B0D;color:#F2F2F2;font:16px system-ui,-apple-system,sans-serif;display:grid;place-items:center;min-height:100vh;">
  <p>Launching Tailnet Browser…</p>
  <script>
    (function () {
      const fromPathRoute = (window.location.pathname || '').startsWith('/browser');
      const wsPath = fromPathRoute ? 'browser/websockify' : 'websockify';
      const page = fromPathRoute ? '/browser/vnc_auto.html' : 'vnc_auto.html';
      const title = '🧭 Tailnet Browser';
      const target = `${page}?path=${encodeURIComponent(wsPath)}&title=${encodeURIComponent(title)}`;
      window.location.replace(target);
    })();
  </script>
</body>
</html>
HTML

PROFILE_DIR="/tmp/clawtabs-remote-browser"
mkdir -p "$PROFILE_DIR"

pkill -f "Xvfb :99" 2>/dev/null || true
pkill -f "x11vnc.*:99" 2>/dev/null || true
pkill -f "websockify.*6080" 2>/dev/null || true
pkill -f "novnc.*6080" 2>/dev/null || true
pkill -f "clawtabs-remote-browser" 2>/dev/null || true
sleep 1

Xvfb :99 -screen 0 1280x720x24 -ac &
XVFB_PID=$!
sleep 1

"$BROWSER_BIN" --no-sandbox --disable-gpu --no-first-run --disable-default-apps \
  --user-data-dir="$PROFILE_DIR" \
  --window-size=1280,720 --window-position=0,0 --display=:99 &
sleep 2

x11vnc -display :99 -nopw -forever -shared -localhost -bg
sleep 1

if [[ "$NOVNC_LAUNCH" == *"launch.sh" ]]; then
  "$NOVNC_LAUNCH" --listen 127.0.0.1:6080 --vnc localhost:5900 --web "$NOVNC_WEB_ROOT"
else
  "$NOVNC_LAUNCH" --listen localhost:6080 --vnc localhost:5900 --web "$NOVNC_WEB_ROOT"
fi

kill "$XVFB_PID" 2>/dev/null || true
pkill -f "x11vnc.*:99" 2>/dev/null || true
pkill -f "websockify.*6080" 2>/dev/null || true
pkill -f "clawtabs-remote-browser" 2>/dev/null || true
EOF

  as_root install -m 0755 /tmp/remote-browser.sh /usr/local/bin/remote-browser.sh
  rm -f /tmp/remote-browser.sh

  cat <<'EOF' >/tmp/remote-browser.service
[Unit]
Description=Remote Browser (Chromium via noVNC)
After=network-online.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStart=/usr/local/bin/remote-browser.sh
ExecStop=/bin/bash -c 'pkill -f "Xvfb :99"; pkill -f "x11vnc.*:99"; pkill -f "websockify.*6080"; pkill -f "clawtabs-remote-browser"'
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  as_root cp /tmp/remote-browser.service /etc/systemd/system/remote-browser.service
  rm -f /tmp/remote-browser.service

  as_root systemctl daemon-reload
  as_root systemctl enable --now remote-browser.service
  systemctl is-active --quiet remote-browser.service || fail "remote-browser.service failed to start"

  tailscale serve --bg --https=6080 http://127.0.0.1:6080 >/dev/null
  ok "Browser panel ready on :6080"
}

print_summary() {
  local dns_name
  dns_name="$(tailscale status --self --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName", "").rstrip("."))' 2>/dev/null || true)"

  echo
  echo "Panel setup complete."
  if [[ -n "$dns_name" ]]; then
    if [[ "$WANT_TERMINAL" -eq 1 ]]; then
      echo "- Terminal: https://${dns_name}:7681"
    fi
    if [[ "$WANT_BROWSER" -eq 1 ]]; then
      echo "- Browser:  https://${dns_name}:6080"
    fi
  else
    if [[ "$WANT_TERMINAL" -eq 1 ]]; then
      echo "- Terminal: https://<this-device>.ts.net:7681"
    fi
    if [[ "$WANT_BROWSER" -eq 1 ]]; then
      echo "- Browser:  https://<this-device>.ts.net:6080"
    fi
  fi
}

main() {
  ensure_tailscale_ready

  if [[ "$WANT_TERMINAL" -eq 1 ]]; then
    echo "Setting up terminal panel..."
    install_ttyd
    if [[ "$OS" == "linux" ]]; then
      setup_terminal_linux
    else
      setup_terminal_macos
    fi
  fi

  if [[ "$WANT_BROWSER" -eq 1 ]]; then
    echo "Setting up browser panel..."
    [[ "$OS" == "linux" ]] || fail "Browser panel auto-setup is Linux-only right now"
    install_browser_deps_linux
    setup_browser_linux
  fi

  print_summary
}

main "$@"
