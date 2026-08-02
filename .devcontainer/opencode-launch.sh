#!/bin/bash
# OpenCode launcher: writes opencode config (with MCP servers) lazily, then
# execs opencode. Config is generated at invocation rather than container
# start so OpenCode's godot-mcp client doesn't squat the single connection
# slot when no OpenCode session is active.
set -e

USER_CONFIG="/home/node/.claude-user-config"
CFG_DIR="/home/node/.config/opencode"
mkdir -p "$CFG_DIR"

cat > "$CFG_DIR/opencode.json" <<'EOF'
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
        "GODOT_DAP_PORT": "6006",
        "GODOT_WORKSPACE_PATH": "/workspace"
      }
    },
    "blender-mcp": {
      "type": "local",
      "command": ["blender-mcp"],
      "environment": {
        "BLENDER_HOST": "host.docker.internal",
        "BLENDER_PORT": "9876"
      }
    }
  }
}
EOF

[ -f "$USER_CONFIG/AGENTS.md" ] && ln -sf "$USER_CONFIG/AGENTS.md" "$CFG_DIR/AGENTS.md"

exec opencode "$@"
