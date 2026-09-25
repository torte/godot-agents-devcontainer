#!/bin/bash
# Claude Code launcher: wraps claude in Headroom when HEADROOM=on, otherwise
# runs it plain. Extra args (e.g. --resume, -p) pass through.
. /home/node/.devcontainer/headroom-enabled.sh

if headroom_enabled; then
  exec headroom wrap claude --no-proxy --code-memory none --no-mcp -- --dangerously-skip-permissions "$@"
fi
exec claude --dangerously-skip-permissions "$@"
