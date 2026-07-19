#!/bin/bash
# xats-daemon install.sh: install patched cross-agent-teams-mcp
# Idempotent, no sudo, fresh-machine-capable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "=== xats-daemon install ==="

# --- Check node/npm ---
if ! command -v node &>/dev/null; then
  echo "ERROR: node not found. Install Node.js first."
  exit 1
fi
if ! command -v npm &>/dev/null; then
  echo "ERROR: npm not found."
  exit 1
fi
echo "[ok] node $(node -v), npm $(npm -v)"

# --- Ensure cross-agent-teams-mcp is installed globally ---
NPM_GLOBAL=$(npm root -g 2>/dev/null || echo "/usr/lib/node_modules")
DAEMON_PKG="$NPM_GLOBAL/cross-agent-teams-mcp"
if [ ! -d "$DAEMON_PKG" ]; then
  echo "[install] cross-agent-teams-mcp not found globally, installing..."
  npm i -g cross-agent-teams-mcp@latest
fi
echo "[ok] daemon package at $DAEMON_PKG"

# --- Build dist/cli.js from src/ ---
echo "[build] building dist/cli.js from src/..."
cd "$SCRIPT_DIR"
mkdir -p dist

# Use esbuild directly (tsup has CJS/ESM interop issues with fastify)
npx esbuild src/cli.ts \
  --bundle \
  --platform=node \
  --format=esm \
  --external:better-sqlite3 \
  --external:fastify \
  --external:@modelcontextprotocol/sdk \
  --external:zod \
  --external:json-schema-diff-validator \
  --outfile=dist/cli.js

echo "[ok] built dist/cli.js ($(wc -c < dist/cli.js) bytes)"

# --- Backup current dist/cli.js ---
DEST="$DAEMON_PKG/dist/cli.js"
BAK="$DAEMON_PKG/dist/cli.js.prepatch-bak"
if [ -f "$DEST" ] && [ ! -f "$BAK" ]; then
  cp "$DEST" "$BAK"
  echo "[ok] backed up to cli.js.prepatch-bak"
elif [ -f "$BAK" ]; then
  echo "[skip] backup already exists"
fi

# --- Overlay our built dist/cli.js ---
cp dist/cli.js "$DEST"
echo "[ok] deployed dist/cli.js to $DEST"

# --- Install client pieces ---
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

cp "$SCRIPT_DIR/client/xats-keepalive" "$BIN_DIR/xats-keepalive"
chmod +x "$BIN_DIR/xats-keepalive"
echo "[ok] installed $BIN_DIR/xats-keepalive"

cp "$SCRIPT_DIR/client/xats-status" "$BIN_DIR/xats-status"
chmod +x "$BIN_DIR/xats-status"
echo "[ok] installed $BIN_DIR/xats-status"

HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/client/session-start-xats.sh" "$HOOKS_DIR/session-start-xats.sh"
chmod +x "$HOOKS_DIR/session-start-xats.sh"
echo "[ok] installed $HOOKS_DIR/session-start-xats.sh"

# --- Wire SessionStart hook (only with --wire-hook) ---
if [ "${1:-}" = "--wire-hook" ]; then
  SETTINGS="$HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
    echo "[ok] backed up $SETTINGS"
  fi

  if [ -f "$SETTINGS" ] && grep -q "xats-keepalive" "$SETTINGS" 2>/dev/null; then
    echo "[skip] hook already present"
  else
    if [ ! -f "$SETTINGS" ]; then
      echo '{"hooks":{"SessionStart":[]}}' > "$SETTINGS"
    fi
    node -e "
const fs = require('fs');
const path = '$SETTINGS';
const settings = JSON.parse(fs.readFileSync(path, 'utf8'));
if (!settings.hooks) settings.hooks = {};
if (!settings.hooks.SessionStart) settings.hooks.SessionStart = [];
settings.hooks.SessionStart.push({
  matcher: '',
  hooks: [{
    type: 'command',
    command: 'if [ -n \"\$CLAUDE_JOB_DIR\" ]; then setsid nohup xats-keepalive </dev/null &>/dev/null & fi'
  }]
});
fs.writeFileSync(path, JSON.stringify(settings, null, 2));
console.log('[ok] hook wired');
"
  fi
else
  echo "[skip] hook not wired (pass --wire-hook to enable)"
fi

# --- Restart daemon ---
echo "[restart] restarting daemon..."
pkill -f "cross-agent-teams-mcp.*daemon" 2>/dev/null || true
sleep 1
setsid /usr/bin/node "$DEST" daemon --port 9100 > /tmp/xats-daemon.log 2>&1 &
DAEMON_PID=$!
sleep 3

# --- Verify ---
echo "[verify] checking daemon..."
HEALTH=$(curl -sf http://127.0.0.1:9100/health 2>/dev/null || echo '{"ok":false}')
if echo "$HEALTH" | grep -q '"ok":true'; then
  echo "[ok] daemon healthy"
else
  echo "[FAIL] daemon not responding, check /tmp/xats-daemon.log"
  exit 1
fi

# --- Verify claude-job register ---
echo "[verify] testing claude-job register..."
TEST_JOB_DIR=$(mktemp -d)
REG=$(curl -sf -X POST http://127.0.0.1:9100/api/register -H "Content-Type: application/json" \
  -d "{\"name\":\"install-test\",\"team\":\"default\",\"role\":\"worker\",\"agent_type\":\"claude-code\",\"delivery\":{\"kind\":\"claude-job\",\"job_id\":\"test\",\"job_dir\":\"$TEST_JOB_DIR\"}}" 2>/dev/null)
if echo "$REG" | grep -q "agent_id"; then
  echo "[ok] claude-job register works"
  AID=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin)['agent_id'])" 2>/dev/null)
  curl -sf -X POST http://127.0.0.1:9100/api/deregister -H "Content-Type: application/json" -d "{\"agent_id\":\"$AID\"}" >/dev/null 2>&1
else
  echo "[WARN] claude-job register may have issues"
fi

# --- Verify xats-status ---
echo "[verify] testing xats-status..."
$BIN_DIR/xats-status 2>&1 | head -3

rm -rf "$TEST_JOB_DIR"

echo ""
echo "=== install complete ==="
echo "Daemon: $DEST"
echo "Client: $BIN_DIR/xats-keepalive, $BIN_DIR/xats-status"
echo "Hook: $HOOKS_DIR/session-start-xats.sh"
echo "Logs: /tmp/xats-daemon.log"
