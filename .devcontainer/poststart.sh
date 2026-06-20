#!/bin/bash
# Post-start setup for Claude Code and OpenCode
# Runs after the devcontainer starts to configure MCP servers, symlink user config, and start port forwarding

USER_CONFIG="/home/node/.claude-user-config"

# --- Shared: Symlink user config (skills, CLAUDE.md, AGENTS.md) ---
[ -d "$USER_CONFIG/skills" ] && ln -sfn "$USER_CONFIG/skills" /home/node/.claude/skills
[ -f "$USER_CONFIG/CLAUDE.md" ] && ln -sf "$USER_CONFIG/CLAUDE.md" /home/node/.claude/CLAUDE.md
[ -f "$USER_CONFIG/AGENTS.md" ] && ln -sf "$USER_CONFIG/AGENTS.md" /home/node/.claude/AGENTS.md

# --- Claude Code: drop stale credentials when using a long-lived token ---
# When CLAUDE_CODE_OAUTH_TOKEN is set it authenticates Claude Code directly, but a
# leftover (usually expired) .credentials.json in the persisted volume makes the
# interactive TUI show a login screen even though auth actually succeeds. The env
# token always takes precedence, so the file is safe to remove.
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -f /home/node/.claude/.credentials.json ]; then
  rm -f /home/node/.claude/.credentials.json
  echo "[devcontainer] Removed stale .credentials.json (using CLAUDE_CODE_OAUTH_TOKEN)"
fi

# --- Patch: minimal-godot-mcp workspace override guard ---
# Prevents Godot's workspaceChange LSP notification from replacing
# GODOT_WORKSPACE_PATH with the host path (unreachable inside the container).
DIAG_MGR="/usr/local/share/npm-global/lib/node_modules/@ryanmazzolini/minimal-godot-mcp/dist/diagnostics-manager.js"
if [ -f "$DIAG_MGR" ] && ! grep -q "process.env.GODOT_WORKSPACE_PATH" "$DIAG_MGR"; then
  sed -i "s/lspClient.on('workspaceChange', (params) => {/lspClient.on('workspaceChange', (params) => {\n            if (process.env.GODOT_WORKSPACE_PATH) { return; }/" "$DIAG_MGR"
  echo "[devcontainer] Patched minimal-godot-mcp diagnostics-manager.js"
fi

# --- Claude Code: Register MCP servers ---
claude mcp add godot-mcp -s user \
  -e GODOT_HOST=host.docker.internal \
  -e GODOT_PORT=6550 \
  -- npx -y @satelliteoflove/godot-mcp

claude mcp add minimal-godot-mcp -s user \
  -e GODOT_LSP_HOST=host.docker.internal \
  -e GODOT_LSP_PORT=6005 \
  -e GODOT_WORKSPACE_PATH=/workspace \
  -- npx -y @ryanmazzolini/minimal-godot-mcp

# OpenCode MCP config is generated lazily by .devcontainer/opencode-launch.sh
# at invocation time, so OpenCode does not squat the single godot-mcp
# connection slot when no OpenCode session is active.

# --- LSP relay: bridge container's 127.0.0.1:6005 to host's Godot LSP ---
# minimal-godot-mcp hardcodes 127.0.0.1, so we relay to host.docker.internal.
# Runs under a watchdog so a transient socat failure self-heals.
LSP_LOG=/tmp/socat-lsp.log
LSP_WATCHDOG_TAG=godot-lsp-watchdog

# Wait for host.docker.internal to resolve (up to 5s)
for i in $(seq 1 10); do
  getent hosts host.docker.internal >/dev/null 2>&1 && break
  sleep 0.5
done
if ! getent hosts host.docker.internal >/dev/null 2>&1; then
  echo "ERROR: host.docker.internal did not resolve after 5s. LSP bridge cannot start." >&2
  exit 1
fi

# Kill any stale watchdog/socat from a previous start
pkill -f "$LSP_WATCHDOG_TAG" 2>/dev/null || true
pkill -f "socat .*TCP-LISTEN:6005" 2>/dev/null || true
sleep 0.3

# Watchdog: restart socat if it ever exits. Tagged via $0 for safe pkill.
nohup bash -c '
  echo "[$(date)] '"$LSP_WATCHDOG_TAG"' starting"
  while true; do
    socat -d TCP-LISTEN:6005,fork,reuseaddr TCP:host.docker.internal:6005
    rc=$?
    echo "[$(date)] socat exited with rc=$rc, restarting in 2s..."
    sleep 2
  done
' "$LSP_WATCHDOG_TAG" >> "$LSP_LOG" 2>&1 &

# Verify the listener actually came up (up to 3s)
listening=false
for i in $(seq 1 6); do
  if ss -tln 2>/dev/null | grep -q ':6005 '; then
    listening=true
    break
  fi
  sleep 0.5
done

if $listening; then
  echo "LSP relay listening on container :6005 (-> host.docker.internal:6005)"
else
  echo "ERROR: LSP relay failed to start within 3s. Tail of $LSP_LOG:" >&2
  tail -5 "$LSP_LOG" >&2 || true
  exit 1
fi
