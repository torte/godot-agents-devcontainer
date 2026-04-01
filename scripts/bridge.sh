#!/usr/bin/env bash
# Bridge Godot's localhost-bound ports to the Docker bridge network
# so the devcontainer can reach them via host.docker.internal.
#
# Godot binds to 127.0.0.1 only. Docker containers reach the host
# via the bridge gateway (typically 172.17.0.1), which is a different
# interface. This script runs socat on the host to relay between them.

set -euo pipefail

GODOT_WS_PORT="${GODOT_WS_PORT:-6550}"
GODOT_LSP_PORT="${GODOT_LSP_PORT:-6005}"

GATEWAY=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
if [ -z "$GATEWAY" ]; then
  echo "Error: Could not determine Docker bridge gateway IP"
  exit 1
fi

stop_bridge() {
  local pids
  pids=$(pgrep -f "socat TCP-LISTEN:.*,bind=${GATEWAY}" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill 2>/dev/null || true
    echo "Stopped bridge processes"
  else
    echo "No bridge processes running"
  fi
}

start_bridge() {
  stop_bridge

  echo "Starting bridge on ${GATEWAY} (ports ${GODOT_WS_PORT}, ${GODOT_LSP_PORT})..."

  socat "TCP-LISTEN:${GODOT_WS_PORT},bind=${GATEWAY},fork,reuseaddr" "TCP:127.0.0.1:${GODOT_WS_PORT}" &
  socat "TCP-LISTEN:${GODOT_LSP_PORT},bind=${GATEWAY},fork,reuseaddr" "TCP:127.0.0.1:${GODOT_LSP_PORT}" &

  sleep 0.5

  local ok=true
  for port in "$GODOT_WS_PORT" "$GODOT_LSP_PORT"; do
    if ss -tln | grep -q "${GATEWAY}:${port}"; then
      echo "  ${GATEWAY}:${port} -> 127.0.0.1:${port} ✓"
    else
      echo "  ${GATEWAY}:${port} -> 127.0.0.1:${port} ✗ (failed)"
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
