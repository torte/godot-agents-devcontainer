#!/bin/bash
# Post-start setup for Claude Code and OpenCode
# Runs after the devcontainer starts to configure MCP servers, symlink user config, and start port forwarding

USER_CONFIG="/home/node/.claude-user-config"

# --- Shared: Symlink user config (skills, CLAUDE.md, AGENTS.md) ---
[ -d "$USER_CONFIG/skills" ] && ln -sfn "$USER_CONFIG/skills" /home/node/.claude/skills
[ -f "$USER_CONFIG/CLAUDE.md" ] && ln -sf "$USER_CONFIG/CLAUDE.md" /home/node/.claude/CLAUDE.md
[ -f "$USER_CONFIG/AGENTS.md" ] && ln -sf "$USER_CONFIG/AGENTS.md" /home/node/.claude/AGENTS.md

# --- Claude Code: Register MCP servers ---
claude mcp add godot-mcp -s user \
  -e GODOT_HOST=host.docker.internal \
  -e GODOT_PORT=6550 \
  -- npx -y @satelliteoflove/godot-mcp

claude mcp add minimal-godot-mcp -s user \
  -e GODOT_LSP_PORT=6005 \
  -e GODOT_WORKSPACE_PATH=/workspace \
  -- npx -y @ryanmazzolini/minimal-godot-mcp

# --- OpenCode: Generate config with MCP servers and permissions ---
cat > /home/node/.config/opencode/opencode.json << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": "allow"
  },
  "mcp": {
    "godot-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@satelliteoflove/godot-mcp"],
      "environment": {
        "GODOT_HOST": "host.docker.internal",
        "GODOT_PORT": "6550"
      }
    },
    "minimal-godot-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@ryanmazzolini/minimal-godot-mcp"],
      "environment": {
        "GODOT_LSP_PORT": "6005",
        "GODOT_WORKSPACE_PATH": "/workspace"
      }
    }
  }
}
EOF

# Symlink AGENTS.md for OpenCode global rules
[ -f "$USER_CONFIG/AGENTS.md" ] && ln -sf "$USER_CONFIG/AGENTS.md" /home/node/.config/opencode/AGENTS.md

# --- Port forwarding: LSP proxy for container-side access ---
# Wait for host.docker.internal to be resolvable
for i in $(seq 1 10); do
  getent hosts host.docker.internal >/dev/null 2>&1 && break
  sleep 0.5
done

# Kill any stale socat on port 6005
pkill -f "socat TCP-LISTEN:6005" 2>/dev/null || true
sleep 0.2

# Start socat relay with logging
nohup socat TCP-LISTEN:6005,fork,reuseaddr TCP:host.docker.internal:6005 \
  > /tmp/socat-lsp.log 2>&1 &

# Verify it's listening
sleep 0.5
if ss -tln | grep -q ':6005'; then
  echo "LSP relay listening on container localhost:6005"
else
  echo "WARNING: LSP relay failed to start. Check /tmp/socat-lsp.log"
fi
