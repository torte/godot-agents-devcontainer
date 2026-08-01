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

# --- Godot addon: keep it in lockstep with the pinned godot-mcp package ---
# The addon ships inside the npm package, so a stale addon silently disables
# whole tools (a 2.17.0 addon against a 4.1.0 server has no runtime_state,
# game_time, exec or mesh commands, and no scene reload). The installer is
# idempotent: it no-ops when versions match and refuses to downgrade.
# A failure here is not fatal — the container is still usable for everything
# that does not need the editor bridge.
if [ -f /workspace/project.godot ]; then
  if addon_out=$(godot-mcp --install-addon /workspace 2>&1); then
    echo "[devcontainer] Godot addon: ${addon_out}"
  else
    echo "[devcontainer] WARNING: Godot addon install failed: ${addon_out}" >&2
  fi
else
  echo "[devcontainer] WARNING: /workspace/project.godot not found — skipping Godot addon install." >&2
  echo "[devcontainer]          Check GODOT_PROJECT_PATH in .env points at a Godot project." >&2
fi

# --- Vendored addons: sync into the project ---
# Addons with no upstream package to install from. See .devcontainer/addons/README.md
# for provenance and licensing. Copied unconditionally rather than
# version-compared: their plugin.cfg versions are static upstream, so a version
# check would never pick up a change. They are a handful of small text files.
VENDORED_ADDONS=/home/node/.devcontainer/addons
if [ -f /workspace/project.godot ] && [ -d "$VENDORED_ADDONS" ]; then
  vendored_synced=""
  for addon_src in "$VENDORED_ADDONS"/*/; do
    [ -f "${addon_src}plugin.cfg" ] || continue
    addon_name=$(basename "$addon_src")
    mkdir -p "/workspace/addons/${addon_name}"
    if cp -r "${addon_src}." "/workspace/addons/${addon_name}/"; then
      vendored_synced="${vendored_synced} ${addon_name}"
    else
      echo "[devcontainer] WARNING: vendored addon ${addon_name} sync failed" >&2
    fi
  done
  [ -n "$vendored_synced" ] && echo "[devcontainer] Vendored addons synced:${vendored_synced}"
fi

# --- Claude Code: Register MCP servers ---
claude mcp add godot-mcp -s user \
  -e GODOT_HOST=host.docker.internal \
  -e GODOT_PORT=6550 \
  -- npx -y @satelliteoflove/godot-mcp

claude mcp add minimal-godot-mcp -s user \
  -e GODOT_LSP_PORT=6005 \
  -e GODOT_DAP_PORT=6006 \
  -e GODOT_WORKSPACE_PATH=/workspace \
  -- npx -y @ryanmazzolini/minimal-godot-mcp

# OpenCode MCP config is generated lazily by .devcontainer/opencode-launch.sh
# at invocation time, so OpenCode does not squat the single godot-mcp
# connection slot when no OpenCode session is active.

# --- LSP/DAP relays: bridge the container's 127.0.0.1 to the host's Godot ---
# minimal-godot-mcp hardcodes 127.0.0.1 in both its LSP client (6005) and its
# DAP client (6006, used by get_console_output), so both need a local relay to
# host.docker.internal. Each runs under a watchdog so a transient socat failure
# self-heals.
RELAY_LOG=/tmp/socat-godot.log
RELAY_PORTS="6005 6006"

# Wait for host.docker.internal to resolve (up to 5s)
for i in $(seq 1 10); do
  getent hosts host.docker.internal >/dev/null 2>&1 && break
  sleep 0.5
done
if ! getent hosts host.docker.internal >/dev/null 2>&1; then
  echo "ERROR: host.docker.internal did not resolve after 5s. Godot relays cannot start." >&2
  exit 1
fi

for port in $RELAY_PORTS; do
  tag="godot-relay-${port}-watchdog"

  # Kill any stale watchdog/socat from a previous start
  pkill -f "$tag" 2>/dev/null || true
  pkill -f "socat .*TCP-LISTEN:${port}" 2>/dev/null || true
done
sleep 0.3

for port in $RELAY_PORTS; do
  tag="godot-relay-${port}-watchdog"

  # Watchdog: restart socat if it ever exits. Tagged via $0 for safe pkill.
  nohup bash -c '
    port=$1
    echo "[$(date)] $0 starting"
    while true; do
      socat -d TCP-LISTEN:${port},fork,reuseaddr TCP:host.docker.internal:${port}
      rc=$?
      echo "[$(date)] socat :${port} exited with rc=$rc, restarting in 2s..."
      sleep 2
    done
  ' "$tag" "$port" >> "$RELAY_LOG" 2>&1 &
done

# Verify the listeners actually came up (up to 3s each)
relay_failed=""
for port in $RELAY_PORTS; do
  listening=false
  for i in $(seq 1 6); do
    if ss -tln 2>/dev/null | grep -q ":${port} "; then
      listening=true
      break
    fi
    sleep 0.5
  done

  if $listening; then
    echo "Godot relay listening on container :${port} (-> host.docker.internal:${port})"
  else
    relay_failed="${relay_failed} ${port}"
  fi
done

if [ -n "$relay_failed" ]; then
  echo "ERROR: Godot relays failed to start within 3s on port(s):${relay_failed}. Tail of $RELAY_LOG:" >&2
  tail -10 "$RELAY_LOG" >&2 || true
  exit 1
fi
