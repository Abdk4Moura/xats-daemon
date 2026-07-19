#!/bin/bash
# SessionStart hook: register this Claude Code session with xats daemon.
# Reads event JSON from stdin (includes session_id, source).
# For background jobs ($CLAUDE_JOB_DIR set): registers with delivery.kind=claude-job
#   and a stable name claude-<host>-job-<basename>.
# For interactive sessions: registers as claude-<host>-<session_id_prefix>.
# Spawns a detached heartbeat pinger that bumps last_seen_at every 30s.

set -euo pipefail

INPUT=$(cat)

XATS_BASE="http://127.0.0.1:9100"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
SRC=$(echo "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")

# Background job detection: $CLAUDE_JOB_DIR is set by the Claude daemon for
# background/async jobs. Use a stable identity name so re-registrations reuse
# the same agent_id via the ON CONFLICT clause.
if [ -n "${CLAUDE_JOB_DIR:-}" ]; then
  JOB_ID=$(basename "$CLAUDE_JOB_DIR")
  NAME="claude-$(hostname)-job-$JOB_ID"
  TAG="job-$JOB_ID"
  DELIVERY_JSON="{\"kind\":\"claude-job\",\"job_id\":\"$JOB_ID\",\"job_dir\":\"$CLAUDE_JOB_DIR\"}"
else
  if [ -z "$SESSION_ID" ]; then
    NAME="claude-$(hostname)-$SRC"
    TAG="no-session"
  else
    NAME="claude-$(hostname)-${SESSION_ID:0:8}"
    TAG="$SESSION_ID"
  fi
  DELIVERY_JSON="null"
fi
TEAM="default"

RESP=$(curl -sf -X POST "$XATS_BASE/api/register" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$NAME\",\"team\":\"$TEAM\",\"agent_type\":\"claude-code\",\"device\":\"$(hostname)\",\"delivery\":$DELIVERY_JSON}" 2>/dev/null) || exit 0

AGENT_ID=$(echo "$RESP" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0

if [ -n "$AGENT_ID" ]; then
  echo "$AGENT_ID" > "/tmp/.xats-agent-id-$TAG"
  # Detached heartbeat pinger: bumps last_seen_at every 30s while CC process lives.
  # Dies when CC exits (the kill -0 $PPID check fails).
  setsid bash -c "while kill -0 $PPID 2>/dev/null; do
    curl -sf -X POST http://127.0.0.1:9100/api/heartbeat \
      -H 'Content-Type: application/json' \
      -d '{\"agent_id\":\"'$AGENT_ID'\"}' >/dev/null 2>&1
    sleep 30
  done" >/dev/null 2>&1 &
fi
exit 0
