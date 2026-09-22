#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CAMERA_SCRIPT="${CAMERA_SCRIPT:-$PROJECT_ROOT/orion-camera.sh}"
export ORION_RUNTIME_DIR="${ORION_RUNTIME_DIR:-/tmp/orion-starshoot-$(id -u)}"
DEVICE="${ORION_VIDEO_DEVICE:-/dev/video0}"
TEST_DIR="$(mktemp -d -t orion-live-test.XXXXXXXX)"
echo "TEST_ARTIFACTS=$TEST_DIR"

bash "$CAMERA_SCRIPT" preview on >"$TEST_DIR/orion-preview-v11.log" 2>&1 &
WRAPPER_PID=$!
sleep 5

test -f "$ORION_RUNTIME_DIR/preview.pid"
PREVIEW_PID="$(cat "$ORION_RUNTIME_DIR/preview.pid")"
echo "PREVIEW_CHILD=$PREVIEW_PID"
bash "$CAMERA_SCRIPT" stop-preview

for attempt in {1..20}; do
  if ! kill -0 "$WRAPPER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.25
done
wait "$WRAPPER_PID"

if kill -0 "$PREVIEW_PID" 2>/dev/null; then
  echo "ffplay remained alive after preview stop" >&2
  exit 10
fi
if fuser "$DEVICE" >/dev/null 2>&1; then
  echo "video0 remained busy after preview stop" >&2
  exit 11
fi

bash "$CAMERA_SCRIPT" controls
v4l2-ctl -d "$DEVICE" \
  --set-fmt-video=width=640,height=480,pixelformat=BA81 \
  --stream-mmap=3 --stream-count=1 --stream-to="$TEST_DIR/orion-after-preview.raw"
stat -c 'AFTER_PREVIEW_BYTES=%s' "$TEST_DIR/orion-after-preview.raw"
echo PREVIEW_CLEANUP_TEST_OK
