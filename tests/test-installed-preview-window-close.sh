#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CAMERA_SCRIPT="${CAMERA_SCRIPT:-$PROJECT_ROOT/orion-camera.sh}"
export ORION_RUNTIME_DIR="${ORION_RUNTIME_DIR:-/tmp/orion-starshoot-$(id -u)}"
DEVICE="${ORION_VIDEO_DEVICE:-/dev/video0}"
TEST_DIR="$(mktemp -d -t orion-live-test.XXXXXXXX)"
echo "TEST_ARTIFACTS=$TEST_DIR"

for attempt in {1..30}; do
  [[ -c "$DEVICE" ]] && break
  sleep 0.25
done
[[ -c "$DEVICE" ]]

bash "$CAMERA_SCRIPT" preview on >"$TEST_DIR/orion-xclose-test.log" 2>&1 &
WRAPPER_PID=$!
sleep 4

# Closing the FFplay window makes that child exit. Killing the child here
# exercises the same cleanup path without depending on desktop automation.
PREVIEW_PID="$(cat "$ORION_RUNTIME_DIR/preview.pid")"
kill -TERM "$PREVIEW_PID"
wait "$WRAPPER_PID"

test ! -e "$ORION_RUNTIME_DIR/preview.pid"
if kill -0 "$PREVIEW_PID" 2>/dev/null; then
  echo "Preview process remained alive after window close" >&2
  exit 20
fi
if fuser "$DEVICE" >/dev/null 2>&1; then
  echo "Camera remained busy after window close" >&2
  exit 21
fi

v4l2-ctl -d "$DEVICE" \
  --set-fmt-video=width=640,height=480,pixelformat=BA81 \
  --stream-mmap=3 --stream-count=1 --stream-to="$TEST_DIR/orion-xclose-test.raw"
stat -c 'AFTER_WINDOW_CLOSE_BYTES=%s' "$TEST_DIR/orion-xclose-test.raw"
echo PREVIEW_WINDOW_CLOSE_TEST_OK
