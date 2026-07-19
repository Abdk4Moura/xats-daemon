# xats-daemon (patched cross-agent-teams-mcp)

Patched version of cross-agent-teams-mcp v0.7.4 with Fixes A-E for the xats cross-agent bus.

## Fixes

| Fix | File(s) | Description |
|-----|---------|-------------|
| A | agents-repo.ts, list-agents.ts | Uniform reaping + accurate online: TTL-based (180s default), same for ALL delivery kinds. Stale agents reaped. |
| B | send-message.ts, broadcast.ts, broadcast-to-role.ts | Reachability gate: refuses direct sends to offline agents; skips unreachable in broadcast. |
| C | client/xats-status | CLI: `xats-status` shows agent table (name, device, online, last-seen, reachable). |
| D | client/xats-keepalive | Helper (fallback): auto-heartbeat + SQLite peek + wake for Claude Code jobs. |
| E | delivery-spec.ts, send-message.ts, broadcast.ts, broadcast-to-role.ts | claude-job delivery support: register accepts claude-job, wake file written on delivery. |

## Build

```bash
# From the repo root:
npx esbuild src/cli.ts --bundle --platform=node --format=esm \
  --external:better-sqlite3 --external:fastify \
  --external:@modelcontextprotocol/sdk --external:zod \
  --external:json-schema-diff-validator \
  --outfile=dist/cli.js
```

Uses esbuild directly (not tsup) because fastify's CJS require() fails in ESM bundle mode.

## Install

```bash
# Fresh install:
chmod +x install.sh
./install.sh

# With SessionStart hook wiring:
./install.sh --wire-hook
```

install.sh is idempotent: checks node/npm, ensures cross-agent-teams-mcp is installed globally, builds from src/, backs up current dist/cli.js, deploys, installs client tools, restarts daemon, verifies health.

## Client Tools

- `~/.local/bin/xats-keepalive`: Heartbeat + SQLite peek + wake for CC jobs (singleton guard, self-clean)
- `~/.local/bin/xats-status`: Agent status table (name, device, online, last-seen, reachable)
- `~/.claude/hooks/session-start-xats.sh`: Existing CC hook (registers + pings)
- `client/session-start-hook.json`: SessionStart hook snippet for settings.json

## Daemon Flags

- `AGENT_TTL_MS` (default 180000): Agent online TTL in ms
- `AGENT_REAP_INTERVAL_MS` (default 60000): Reap sweep interval
- `XATS_TTL_SECONDS`: Override for online check TTL

## Files Carrying Each Fix

| Fix | Source files |
|-----|-------------|
| A | src/storage/agents-repo.ts (isAgentLive uniform TTL), src/mcp/list-agents.ts (removed tmux dep) |
| B | src/mcp/send-message.ts (reachability check), src/mcp/broadcast.ts (skip unreachable), src/mcp/broadcast-to-role.ts (skip unreachable) |
| E | src/lib/delivery-spec.ts (claude-job type), src/mcp/send-message.ts (wake write), src/mcp/broadcast.ts (wake write), src/mcp/broadcast-to-role.ts (wake write) |
