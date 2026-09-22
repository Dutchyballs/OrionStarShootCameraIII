#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CAMERA_SCRIPT="${CAMERA_SCRIPT:-$PROJECT_ROOT/orion-camera.sh}"
export ORION_RUNTIME_DIR="${ORION_RUNTIME_DIR:-/tmp/orion-starshoot-$(id -u)}"
DEVICE="${ORION_VIDEO_DEVICE:-/dev/video0}"
TEST_DIR="$(mktemp -d -t orion-live-test.XXXXXXXX)"
echo "TEST_ARTIFACTS=$TEST_DIR"

for attempt in {1..40}; do
  [[ -c "$DEVICE" ]] && break
  sleep 0.25
done
[[ -c "$DEVICE" ]]

for cycle in 1 2 3; do
  echo "PREVIEW_CYCLE=$cycle START"
  bash "$CAMERA_SCRIPT" preview on >"$TEST_DIR/orion-repeat-$cycle.log" 2>&1 &
  wrapper_pid=$!

  for attempt in {1..30}; do
    [[ -f "$ORION_RUNTIME_DIR/preview.pid" ]] && break
    if ! kill -0 "$wrapper_pid" 2>/dev/null; then
      cat "$TEST_DIR/orion-repeat-$cycle.log" >&2
      echo "Preview wrapper exited before opening on cycle $cycle" >&2
      exit 30
    fi
    sleep 0.25
  done
  [[ -f "$ORION_RUNTIME_DIR/preview.pid" ]]

  sleep 3
  preview_pid="$(cat "$ORION_RUNTIME_DIR/preview.pid")"
  kill -TERM "$preview_pid"
  wait "$wrapper_pid"

  [[ ! -e "$ORION_RUNTIME_DIR/preview.pid" ]]
  ! kill -0 "$preview_pid" 2>/dev/null
  ! fuser "$DEVICE" >/dev/null 2>&1
  echo "PREVIEW_CYCLE=$cycle CLOSED_AND_READY"
done

echo REPEATED_PREVIEW_TEST_OK
