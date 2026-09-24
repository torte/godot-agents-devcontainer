#!/bin/bash
# Proves the container can draw a real frame: renders the tiny project next to
# this script under Xvfb and checks the result. Run inside the container, or
# from the host with `npm run doctor:render`.
set -uo pipefail

if ! command -v xvfb-run >/dev/null; then
  echo "FAIL: this is the basic variant (DEVCONTAINER_VARIANT=${DEVCONTAINER_VARIANT:-basic}), which cannot render."
  echo "      Set DEVCONTAINER_VARIANT=extended in .env, then: npm run build && npm run up"
  exit 1
fi

work=/tmp/render-doctor
rm -rf "$work" && mkdir -p "$work"
cp -r "$(dirname "$(readlink -f "$0")")"/. "$work"/
frame="$work/frame.png"

if [ -e /dev/dri ]; then
  echo "GPU devices: $(ls /dev/dri | tr '\n' ' ')"
else
  echo "GPU devices: none (RENDER_DEVICE unset), expecting llvmpipe"
fi

start=$(date +%s%N)
log=$(xvfb-run -a -s "-screen 0 960x540x24" \
  godot --path "$work" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution 960x540 -- --out="$frame" 2>&1)
rc=$?
ms=$(( ($(date +%s%N) - start) / 1000000 ))

device=$(grep -m1 'OpenGL API' <<<"$log")
errors=$(grep -E '^(ERROR|SCRIPT ERROR):' <<<"$log")
result=$(grep -m1 '^RENDER_DOCTOR' <<<"$log")

echo "Device:  ${device:-unknown}"
echo "Result:  ${result:-none}"
echo "Time:    ${ms} ms"
if [ -e /dev/dri ] && grep -q llvmpipe <<<"$device"; then
  echo "Note:    GPU passed in, but Xvfb offers no direct GPU path, so Mesa drew on the CPU."
fi

if [ $rc -eq 0 ] && [ -z "$errors" ] && [ -s "$frame" ]; then
  echo "OK: real frame drawn, saved to $frame"
  exit 0
fi

echo "FAIL: exit code $rc"
[ -n "$errors" ] && echo "$errors"
[ -z "$result" ] && echo "$log" | tail -20
exit 1
