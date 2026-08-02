#!/usr/bin/env bash
# Bridge Godot's localhost-bound ports to the Docker bridge network
# so the devcontainer can reach them via host.docker.internal.
#
# Godot binds to 127.0.0.1 only. On Linux with Docker Engine, containers
# reach the host via the bridge gateway (typically 172.17.0.1), which is
# a different interface. This script runs socat on the host to relay
# between them.
#
# On macOS and Windows, Docker Desktop handles host.docker.internal
# natively — the bridge is not needed and this script exits cleanly.

set -euo pipefail

OS="$(uname -s)"

needs_bridge() {
  case "$OS" in
    Linux)  return 0 ;;  # Docker Engine needs the relay
    *)      return 1 ;;  # Docker Desktop (macOS/Windows) handles it natively
  esac
}

GODOT_WS_PORT="${GODOT_WS_PORT:-6550}"
GODOT_LSP_PORT="${GODOT_LSP_PORT:-6005}"
GODOT_DAP_PORT="${GODOT_DAP_PORT:-6006}"
BLENDER_PORT="${BLENDER_PORT:-9876}"

# Every port the container needs to reach on the host.
BRIDGE_PORTS=("$GODOT_WS_PORT" "$GODOT_LSP_PORT" "$GODOT_DAP_PORT" "$BLENDER_PORT")

# Ports whose absence is normal rather than broken, so the doctor reports them
# as "—" instead of failing: DAP is only needed for get_console_output, and
# Blender is a separate application that is usually not running.
OPTIONAL_PORTS=("$GODOT_DAP_PORT" "$BLENDER_PORT")

is_optional_port() {
  local needle=$1 p
  for p in "${OPTIONAL_PORTS[@]}"; do
    [ "$p" = "$needle" ] && return 0
  done
  return 1
}

get_gateway() {
  docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null
}

stop_bridge() {
  if ! needs_bridge; then
    return 0
  fi

  local gateway
  gateway=$(get_gateway)
  if [ -z "$gateway" ]; then
    return 0
  fi

  local pids
  pids=$(pgrep -f "socat TCP-LISTEN:.*,bind=${gateway}" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill 2>/dev/null || true
    echo "Stopped bridge processes"
  else
    echo "No bridge processes running"
  fi
}

start_bridge() {
  if ! needs_bridge; then
    echo "Bridge not needed on ${OS} (Docker Desktop handles host.docker.internal natively)"
    return 0
  fi

  local gateway
  gateway=$(get_gateway)
  if [ -z "$gateway" ]; then
    echo "Error: Could not determine Docker bridge gateway IP"
    exit 1
  fi

  stop_bridge

  if ! command -v socat >/dev/null 2>&1; then
    echo "Error: socat is not installed. Install it with: sudo apt-get install socat"
    exit 1
  fi

  echo "Starting bridge on ${gateway} (ports ${BRIDGE_PORTS[*]})..."

  local log=/tmp/godot-bridge.log
  : > "$log"
  for port in "${BRIDGE_PORTS[@]}"; do
    socat "TCP-LISTEN:${port},bind=${gateway},fork,reuseaddr" "TCP:127.0.0.1:${port}" >>"$log" 2>&1 &
  done

  sleep 0.5

  local ok=true
  for port in "${BRIDGE_PORTS[@]}"; do
    if ss -tln | grep -q "${gateway}:${port}"; then
      echo "  ${gateway}:${port} -> 127.0.0.1:${port} ✓"
    else
      echo "  ${gateway}:${port} -> 127.0.0.1:${port} ✗ (failed)"
      ok=false
    fi
  done

  if $ok; then
    echo "Bridge running."
  else
    echo "Some ports failed to bind. Tail of $log:" >&2
    tail -5 "$log" >&2 || true
    exit 1
  fi
}

status_bridge() {
  if ! needs_bridge; then
    echo "Bridge not needed on ${OS} (Docker Desktop handles host.docker.internal natively)"
    return 0
  fi

  local gateway
  gateway=$(get_gateway)
  if [ -z "$gateway" ]; then
    echo "Error: Could not determine Docker bridge gateway IP"
    return 1
  fi

  local ok=true
  for port in "${BRIDGE_PORTS[@]}"; do
    if ss -tln | grep -q "${gateway}:${port}"; then
      echo "  ${gateway}:${port} -> 127.0.0.1:${port} ✓"
    else
      echo "  ${gateway}:${port} NOT listening ✗"
      ok=false
    fi
  done

  $ok && echo "Bridge healthy." || echo "Some ports not bridged — run '$0 start' to fix."
}

# Compare the addon installed in the Godot project against the one bundled in
# the container's pinned godot-mcp package. A skew silently disables whole tools
# rather than erroring, so it is worth checking explicitly. Both reads go
# through the container so this does not need GODOT_PROJECT_PATH from .env.
check_addon_version() {
  local cid=$1
  local pkg_cfg=/usr/local/share/npm-global/lib/node_modules/@satelliteoflove/godot-mcp/addon/plugin.cfg
  local read_version='sed -n "s/^version=\"\(.*\)\"/\1/p"'

  local bundled installed
  bundled=$(docker exec "$cid" bash -c "$read_version $pkg_cfg 2>/dev/null" | tr -d '\r')
  installed=$(docker exec "$cid" bash -c "$read_version /workspace/addons/godot_mcp/plugin.cfg 2>/dev/null" | tr -d '\r')

  if [ -z "$bundled" ]; then
    echo "  godot_mcp addon version ✗  (no addon bundled in the container package)"
    return 1
  fi
  if [ -z "$installed" ]; then
    echo "  godot_mcp addon not installed in /workspace ✗  (restart the container, or run 'npm run install-godot-addon')"
    return 1
  fi
  if [ "$installed" != "$bundled" ]; then
    echo "  godot_mcp addon ${installed} != package ${bundled} ✗  (restart the container, or run 'npm run install-godot-addon')"
    return 1
  fi

  echo "  godot_mcp addon ${installed} matches package ✓"

  # auto_reload is optional and independent of godot-mcp — report it, but never
  # fail the doctor over it.
  if docker exec "$cid" bash -c '[ -f /workspace/addons/auto_reload/plugin.cfg ]'; then
    if docker exec "$cid" bash -c 'grep -q "res://addons/auto_reload/plugin.cfg" /workspace/project.godot 2>/dev/null'; then
      echo "  auto_reload addon installed + enabled ✓"
    else
      echo "  auto_reload addon installed, NOT enabled —  (Project Settings > Plugins)"
    fi
  else
    echo "  auto_reload addon not installed —  (rebuild and restart the container)"
  fi

  # Installed but never enabled is a distinct failure: the server connects and
  # every editor command then fails.
  if docker exec "$cid" bash -c 'grep -q "res://addons/godot_mcp/plugin.cfg" /workspace/project.godot 2>/dev/null'; then
    echo "  godot_mcp plugin enabled in project.godot ✓"
  else
    echo "  godot_mcp plugin NOT enabled ✗  (Project Settings > Plugins, then restart the editor)"
    return 1
  fi
}

doctor_bridge() {
  echo "=== Godot bridge doctor ==="
  local fail=false

  echo "[host] OS: ${OS}"
  if ! needs_bridge; then
    echo "[host] Bridge not needed (Docker Desktop). Stopping checks here."
    return 0
  fi

  echo
  echo "[host] Godot listening on 127.0.0.1?"
  for port in "${BRIDGE_PORTS[@]}"; do
    if ss -tln | grep -qE "127\.0\.0\.1:${port} "; then
      echo "  127.0.0.1:${port} ✓"
    elif [ "$port" = "$GODOT_DAP_PORT" ]; then
      echo "  127.0.0.1:${port} —  (DAP off; enable Editor Settings > Network > Debug Adapter)"
    elif [ "$port" = "$BLENDER_PORT" ]; then
      echo "  127.0.0.1:${port} —  (Blender not serving; start it, then BlenderMCP > Connect to MCP server)"
    else
      echo "  127.0.0.1:${port} ✗  (start the Godot editor and verify port settings)"
      fail=true
    fi
  done

  echo
  echo "[host] Bridge relays on Docker gateway?"
  local gateway
  gateway=$(get_gateway)
  if [ -z "$gateway" ]; then
    echo "  Could not determine Docker bridge gateway IP ✗"
    fail=true
  else
    for port in "${BRIDGE_PORTS[@]}"; do
      if ss -tln | grep -q "${gateway}:${port}"; then
        echo "  ${gateway}:${port} ✓"
      else
        echo "  ${gateway}:${port} ✗  (run '$0 start')"
        fail=true
      fi
    done
  fi

  echo
  echo "[container] Inspecting devcontainer (if running)..."
  local cid
  cid=$(docker ps -q -f label=devcontainer.local_folder="$(pwd)" 2>/dev/null | head -1)
  if [ -z "$cid" ]; then
    echo "  No devcontainer found for $(pwd) — skipping container checks."
  else
    echo "  Container: $cid"
    for port in "$GODOT_LSP_PORT" "$GODOT_DAP_PORT"; do
      if docker exec "$cid" bash -c "ss -tln 2>/dev/null | grep -q ':${port} '"; then
        echo "  container :${port} (relay socat) ✓"
      else
        echo "  container :${port} (relay socat) ✗  (poststart watchdog not running)"
        fail=true
      fi
    done
    if docker exec "$cid" bash -c 'getent hosts host.docker.internal >/dev/null'; then
      echo "  host.docker.internal resolvable from container ✓"
    else
      echo "  host.docker.internal resolvable from container ✗"
      fail=true
    fi
    for port in "${BRIDGE_PORTS[@]}"; do
      if docker exec "$cid" bash -c "timeout 1 bash -c '</dev/tcp/host.docker.internal/${port}' 2>/dev/null"; then
        echo "  container -> host.docker.internal:${port} ✓"
      elif is_optional_port "$port"; then
        echo "  container -> host.docker.internal:${port} —  (optional, not running)"
      else
        echo "  container -> host.docker.internal:${port} ✗"
        fail=true
      fi
    done

    check_addon_version "$cid" || fail=true
  fi

  echo
  if $fail; then
    echo "Doctor: FAIL — see ✗ items above."
    return 1
  else
    echo "Doctor: OK — bridge is healthy end-to-end."
  fi
}

case "${1:-start}" in
  start)  start_bridge ;;
  stop)   stop_bridge ;;
  status) status_bridge ;;
  doctor) doctor_bridge ;;
  *)      echo "Usage: $0 {start|stop|status|doctor}" ;;
esac
