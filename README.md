# Claw Tabs

Local-first agent chat/tab web client, hosted by you at:

`https://<your-device>.ts.net/clawtabs`

This repo is intentionally separate from `usemyclaw.com` / `openclaw-chat` so public production can stay stable while Claw Tabs evolves.

## Principles

- Local-first hosting on your own tailnet URL
- Path-scoped app (`/clawtabs`) so it can coexist with other tailnet apps
- PWA scope isolated to `/clawtabs/`
- No dependency on a public hosted frontend
- Direct-to-tabs startup (no landing/connect wall)
- Same-host bootstrap: server can read a compatible agent gateway token from env/config and auto-connect the UI

## Quick start

```bash
git clone https://github.com/humanitylabs-org/claw-tabs.git
cd claw-tabs
./scripts/setup.sh
```

The setup script will:
1. Run prerequisite checks
2. Start a local app server
3. Expose `/clawtabs` via `tailscale serve`
4. Verify health + manifest scope

Optional one-command panel onboarding:

```bash
# Core app + Browser/Terminal tile dependencies
./scripts/setup.sh --with-panels
```

## Run commands

```bash
# Start local server only
./scripts/start.sh

# Stop local server
./scripts/stop.sh

# Re-apply tailscale path mapping
./scripts/serve-path.sh

# Optional panel dependencies (Browser/Terminal tiles)
./scripts/setup-panels.sh --all
./scripts/setup-panels.sh --terminal
./scripts/setup-panels.sh --browser

# Panel readiness JSON (used by the UI unlock hints)
./scripts/panels-status.sh
```

## Configuration

Optional environment variables:

- `CLAWTABS_PORT` (default: `8788`)
- `CLAWTABS_HOST` (default: `127.0.0.1`)
- `CLAWTABS_BASE_PATH` (default: `/clawtabs`)
- `CLAWTABS_GATEWAY_URL` or `AGENT_GATEWAY_URL` for a compatible agent gateway URL
- `CLAWTABS_GATEWAY_TOKEN` or `AGENT_GATEWAY_TOKEN` to provide the gateway token directly
- `CLAWTABS_GATEWAY_CONFIG` for a JSON config file containing `gateway.auth.token` (legacy `CLAWTABS_OPENCLAW_CONFIG` still works)

Example:

```bash
export CLAWTABS_PORT=8790
export CLAWTABS_BASE_PATH=/clawtabs
./scripts/setup.sh
```

## Panel support (Browser + Terminal tiles)

- **Linux:** full support (terminal + browser panel automation).
- **macOS:** terminal panel automation supported; browser panel auto-setup is Linux-only for now.
- If a tile is locked, Claw Tabs now shows an **Install in chat** button that asks your AI to run the exact setup command.

## Gateway notes

- Claw Tabs expects a compatible WebSocket gateway. Set `CLAWTABS_GATEWAY_URL`/`CLAWTABS_GATEWAY_TOKEN` when the installer is not using the default local config path.
- If Claw Tabs and your agent gateway are on different tailnet hostnames, add the Claw Tabs origin to that gateway's allowed origins.
- For OpenClaw, keep `gateway.tailscale.mode=serve` enabled.

## Tech

- Pure HTML/CSS/JS frontend
- Ed25519 device auth + compatible agent WebSocket protocol
- Local credentials in browser storage
