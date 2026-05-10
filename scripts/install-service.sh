#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_PATH="/etc/systemd/system/clawtabs.service"

cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Claw Tabs Tailnet App
After=network-online.target tailscaled.service openclaw-gateway.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=CLAWTABS_HOST=127.0.0.1
Environment=CLAWTABS_PORT=8788
Environment=CLAWTABS_BASE_PATH=/clawtabs
ExecStart=/usr/bin/node $APP_DIR/scripts/server.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable clawtabs.service >/dev/null
systemctl restart clawtabs.service
systemctl is-enabled clawtabs.service >/dev/null
systemctl is-active clawtabs.service >/dev/null

echo "✅ systemd ready: clawtabs.service (enabled + active)"
