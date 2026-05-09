# Claw Tabs

Local-first OpenClaw web client, hosted by you at:

`https://<your-device>.ts.net/clawtabs`

This repo is intentionally separate from `usemyclaw.com` / `openclaw-chat` so public production can stay stable while Claw Tabs evolves.

## Principles

- Local-first hosting on your own tailnet URL
- Path-scoped app (`/clawtabs`) so it can coexist with other tailnet apps
- PWA scope isolated to `/clawtabs/`
- No dependency on a public hosted frontend

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

## Run commands

```bash
# Start local server only
./scripts/start.sh

# Stop local server
./scripts/stop.sh

# Re-apply tailscale path mapping
./scripts/serve-path.sh
```

## Configuration

Optional environment variables:

- `CLAWTABS_PORT` (default: `8788`)
- `CLAWTABS_HOST` (default: `127.0.0.1`)
- `CLAWTABS_BASE_PATH` (default: `/clawtabs`)

Example:

```bash
export CLAWTABS_PORT=8790
export CLAWTABS_BASE_PATH=/clawtabs
./scripts/setup.sh
```

## Gateway notes

- If Claw Tabs and your OpenClaw gateway are on different tailnet hostnames, add the Claw Tabs origin to `gateway.controlUi.allowedOrigins`.
- Keep `gateway.tailscale.mode=serve` enabled.

## Tech

- Pure HTML/CSS/JS frontend
- Ed25519 device auth + OpenClaw WebSocket protocol
- Local credentials in browser storage
