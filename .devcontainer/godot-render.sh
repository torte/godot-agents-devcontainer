#!/bin/bash
# Runs Godot so it draws real frames: under Xvfb, with the graphics API picked
# by RENDER_DEFAULT (opengl or vulkan). All arguments pass through to godot.
# One-off override: RENDER_DEFAULT=vulkan godot-render ...
# Installed as /usr/local/bin/godot-render; see README "Optional: rendering in
# the container".
set -euo pipefail

lower() { echo "${1:-}" | tr '[:upper:]' '[:lower:]'; }

pathway=$(lower "${RENDER_DEFAULT:-opengl}")
case "$pathway" in
  opengl)
    if [ "$(lower "${RENDER_OPENGL:-}")" != "on" ] || ! command -v xvfb-run >/dev/null; then
      echo "godot-render: OpenGL rendering is not installed in this image." >&2
      echo "  Set RENDER_OPENGL=on in .env, then: npm run build && npm run up" >&2
      exit 1
    fi
    # The Compatibility method is the only one that runs on OpenGL, so it is
    # forced: Forward+/Mobile projects render too (with visual differences).
    flags=(--rendering-driver opengl3 --rendering-method gl_compatibility)
    ;;
  vulkan)
    if [ "$(lower "${RENDER_VULKAN:-}")" != "on" ] || ! command -v xvfb-run >/dev/null; then
      echo "godot-render: Vulkan rendering is not installed in this image." >&2
      echo "  Set RENDER_VULKAN=on in .env, then: npm run build && npm run up" >&2
      exit 1
    fi
    # Xvfb cannot present a hardware Vulkan device, so Mesa's CPU driver
    # (lavapipe) is pinned. The project's own rendering method is kept:
    # Forward+ and Mobile run on Vulkan, Compatibility needs RENDER_DEFAULT=opengl.
    lvp=$(ls /usr/share/vulkan/icd.d/lvp_icd.*.json 2>/dev/null | head -1)
    [ -n "$lvp" ] && export VK_DRIVER_FILES="$lvp" VK_ICD_FILENAMES="$lvp"
    flags=(--rendering-driver vulkan)
    ;;
  *)
    echo "godot-render: Unknown RENDER_DEFAULT '$pathway' (expected opengl or vulkan)" >&2
    exit 1
    ;;
esac

exec xvfb-run -a -s "-screen 0 1920x1080x24" \
  godot --display-driver x11 "${flags[@]}" --audio-driver Dummy "$@"
