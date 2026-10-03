#!/bin/bash
# Claude Code launcher: wraps claude in Headroom when HEADROOM=on, otherwise
# runs it plain. Extra args (e.g. --resume, -p) pass through.
. /home/node/.devcontainer/headroom-enabled.sh

# The long-lived token, if .env sets one (written by scripts/oauth-token.sh).
[ -s /home/node/.claude/.oauth-token ] && export CLAUDE_CODE_OAUTH_TOKEN="$(cat /home/node/.claude/.oauth-token)"

if headroom_enabled; then
  exec headroom wrap claude --no-proxy --code-memory none --no-mcp -- --dangerously-skip-permissions "$@"
fi
exec claude --dangerously-skip-permissions "$@"
