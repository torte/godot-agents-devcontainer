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

  echo "Starting bridge on ${gateway} (ports ${GODOT_WS_PORT}, ${GODOT_LSP_PORT})..."

  socat "TCP-LISTEN:${GODOT_WS_PORT},bind=${gateway},fork,reuseaddr" "TCP:127.0.0.1:${GODOT_WS_PORT}" &
  socat "TCP-LISTEN:${GODOT_LSP_PORT},bind=${gateway},fork,reuseaddr" "TCP:127.0.0.1:${GODOT_LSP_PORT}" &

  sleep 0.5

  local ok=true
  for port in "$GODOT_WS_PORT" "$GODOT_LSP_PORT"; do
    if ss -tln | grep -q "${gateway}:${port}"; then
      echo "  ${gateway}:${port} -> 127.0.0.1:${port} ✓"
    else
      echo "  ${gateway}:${port} -> 127.0.0.1:${port} ✗ (failed)"
      ok=false
    fi
  done

  $ok && echo "Bridge running." || echo "Some ports failed to bind."
}

case "${1:-start}" in
  start) start_bridge ;;
  stop)  stop_bridge ;;
  *)     echo "Usage: $0 {start|stop}" ;;
esac
