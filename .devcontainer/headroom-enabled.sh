#!/bin/bash
# Sourced by poststart.sh and the claude/opencode launchers. Defines
# headroom_enabled: true only if HEADROOM=on (set via .env / containerEnv) and
# the image was built with Headroom installed (build arg of the same name).
headroom_enabled() {
  case "${HEADROOM,,}" in
    on)
      command -v headroom >/dev/null 2>&1 && return 0
      echo "[devcontainer] WARNING: HEADROOM=on but Headroom is not installed in this image. Rebuild with HEADROOM=on: npm run build && npm run up" >&2
      return 1 ;;
    off|"") return 1 ;;
    *)
      echo "[devcontainer] WARNING: Unknown HEADROOM='$HEADROOM' (expected on or off), treating as off" >&2
      return 1 ;;
  esac
}
