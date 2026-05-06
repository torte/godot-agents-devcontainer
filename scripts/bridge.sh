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

  local log=/tmp/godot-bridge.log
  : > "$log"
  socat "TCP-LISTEN:${GODOT_WS_PORT},bind=${gateway},fork,reuseaddr" "TCP:127.0.0.1:${GODOT_WS_PORT}" >>"$log" 2>&1 &
  socat "TCP-LISTEN:${GODOT_LSP_PORT},bind=${gateway},fork,reuseaddr" "TCP:127.0.0.1:${GODOT_LSP_PORT}" >>"$log" 2>&1 &

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
  for port in "$GODOT_WS_PORT" "$GODOT_LSP_PORT"; do
    if ss -tln | grep -q "${gateway}:${port}"; then
      echo "  ${gateway}:${port} -> 127.0.0.1:${port} ✓"
    else
      echo "  ${gateway}:${port} NOT listening ✗"
      ok=false
    fi
  done

  $ok && echo "Bridge healthy." || echo "Some ports not bridged — run '$0 start' to fix."
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
  for port in "$GODOT_WS_PORT" "$GODOT_LSP_PORT"; do
    if ss -tln | grep -qE "127\.0\.0\.1:${port} "; then
      echo "  127.0.0.1:${port} ✓"
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
    for port in "$GODOT_WS_PORT" "$GODOT_LSP_PORT"; do
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
    if docker exec "$cid" bash -c 'ss -tln 2>/dev/null | grep -q ":6005 "'; then
      echo "  container :6005 (LSP relay socat) ✓"
    else
      echo "  container :6005 (LSP relay socat) ✗  (poststart watchdog not running)"
      fail=true
    fi
    if docker exec "$cid" bash -c 'getent hosts host.docker.internal >/dev/null'; then
      echo "  host.docker.internal resolvable from container ✓"
    else
      echo "  host.docker.internal resolvable from container ✗"
      fail=true
    fi
    for port in "$GODOT_LSP_PORT" "$GODOT_WS_PORT"; do
      if docker exec "$cid" bash -c "timeout 1 bash -c '</dev/tcp/host.docker.internal/${port}' 2>/dev/null"; then
        echo "  container -> host.docker.internal:${port} ✓"
      else
        echo "  container -> host.docker.internal:${port} ✗"
        fail=true
      fi
    done
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
