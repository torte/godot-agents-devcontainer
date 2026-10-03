#!/bin/bash
# Hands CLAUDE_CODE_OAUTH_TOKEN (from .env) to the running container as a file,
# ~/.claude/.oauth-token (mode 600, in the config volume), which
# claude-launch.sh exports. Kept out of the container's environment on purpose:
# `devcontainer exec` passes that environment as `docker exec -e` arguments,
# which any local user can read with `ps`, and `docker inspect` shows it too.
# The token travels on stdin. An unset token removes the file.
CID=$(docker ps -q -f "label=devcontainer.local_folder=$(pwd)")
[ -n "$CID" ] || { echo "oauth-token: no running container" >&2; exit 1; }

printf %s "${CLAUDE_CODE_OAUTH_TOKEN:-}" | docker exec -i -u node "$CID" sh -c '
  f=/home/node/.claude/.oauth-token
  umask 077
  cat >"$f.tmp"
  if [ -s "$f.tmp" ]; then
    mv "$f.tmp" "$f"
    # A leftover (usually expired) .credentials.json from an interactive login
    # makes the TUI show a login screen even though the token authenticates.
    if [ -f /home/node/.claude/.credentials.json ]; then
      rm -f /home/node/.claude/.credentials.json
      echo "[devcontainer] Removed stale .credentials.json (using CLAUDE_CODE_OAUTH_TOKEN)"
    fi
    echo "[devcontainer] Long-lived Claude token installed"
  else
    rm -f "$f.tmp" "$f"
  fi'
