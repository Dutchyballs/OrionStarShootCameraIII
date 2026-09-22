#!/usr/bin/env bash
set -euo pipefail

DEVICE="${ORION_VIDEO_DEVICE:-/dev/video0}"
CAMERA_ID=0e96:c001
RUNTIME_DIR="${ORION_RUNTIME_DIR:-/tmp/orion-starshoot-$(id -u)}"

# A private directory prevents other users planting PID files or symlinks when
# the Windows panel invokes this script as root inside WSL.
if [[ -L "$RUNTIME_DIR" ]]; then
  echo "Refusing symlink runtime directory: $RUNTIME_DIR" >&2
  exit 73
fi
if [[ ! -e "$RUNTIME_DIR" ]]; then
  (umask 077; mkdir -- "$RUNTIME_DIR") || exit 73
fi
if [[ ! -d "$RUNTIME_DIR" || ! -O "$RUNTIME_DIR" || "$(stat -c '%a' -- "$RUNTIME_DIR")" != 700 ]]; then
  echo "Runtime directory must be owned by this user with mode 700: $RUNTIME_DIR" >&2
  exit 73
fi
RECORD_PID_FILE="$RUNTIME_DIR/record.pid"
PREVIEW_PID_FILE="$RUNTIME_DIR/preview.pid"

require_camera() {
  if [[ ! -c "$DEVICE" ]]; then
    echo "The Orion camera is not connected at $DEVICE." >&2
    exit 2
  fi
  local device_name usb_path vendor product
  device_name="$(basename -- "$(readlink -f -- "$DEVICE")")"
  usb_path="$(readlink -f -- "/sys/class/video4linux/$device_name/device" 2>/dev/null || true)"
  while [[ -n "$usb_path" && "$usb_path" != / ]]; do
    if [[ -r "$usb_path/idVendor" && -r "$usb_path/idProduct" ]]; then
      vendor="$(cat "$usb_path/idVendor")"
      product="$(cat "$usb_path/idProduct")"
      if [[ "$vendor:$product" == "$CAMERA_ID" ]]; then
        return 0
      fi
      break
    fi
    usb_path="$(dirname -- "$usb_path")"
  done
  echo "Refusing $DEVICE: it is not the Orion camera ($CAMERA_ID). Set ORION_VIDEO_DEVICE to its video device." >&2
  exit 2
}

wait_for_camera() {
  local attempt
  for attempt in {1..20}; do
    if [[ -c "$DEVICE" ]] && v4l2-ctl -d "$DEVICE" --get-fmt-video >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

tracked_pid() {
  local pid_file="$1" expected_process="$2" target_pid
  [[ -f "$pid_file" && ! -L "$pid_file" ]] || return 1
  target_pid="$(cat -- "$pid_file")"
  # Never pass zero, a negative process group, or arbitrary file contents to kill.
  [[ "$target_pid" =~ ^[1-9][0-9]*$ && "$target_pid" != 1 ]] || return 1
  [[ "$(ps -p "$target_pid" -o comm= 2>/dev/null || true)" == "$expected_process" ]] || return 1
  [[ "$(ps -p "$target_pid" -o uid= 2>/dev/null | tr -d ' ')" == "$(id -u)" ]] || return 1
  # A reused PID for another media player must not become our stop target.
  tr '\0' '\n' < "/proc/$target_pid/cmdline" 2>/dev/null | grep -Fxq -- "$DEVICE" || return 1
  kill -0 "$target_pid" 2>/dev/null || return 1
  printf '%s\n' "$target_pid"
}

stop_pid_file() {
  local pid_file="$1" signal_name="$2" expected_process="$3" target_pid
  if target_pid="$(tracked_pid "$pid_file" "$expected_process")"; then
    kill "-$signal_name" "$target_pid" 2>/dev/null || true
    return 0
  fi
  rm -f -- "$pid_file"
  return 1
}

recover_camera() {
  if [[ -c "$DEVICE" ]]; then require_camera; fi
  local attempt
  for attempt in {1..12}; do
    if ! fuser "$DEVICE" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  if fuser "$DEVICE" >/dev/null 2>&1; then
    echo "Camera $DEVICE is still busy. Close the application using it and try again." >&2
    return 1
  fi

  if wait_for_camera; then
    require_camera
    return 0
  fi

  if command -v usbreset >/dev/null 2>&1; then
    usbreset "$CAMERA_ID" >/dev/null 2>&1 || true
    udevadm settle || true
  fi
  wait_for_camera && require_camera
}

set_manual_exposure() {
  local value="$1"
  if ! [[ "$value" =~ ^[0-9]{1,3}$ ]] || (( 10#$value > 255 )); then
    echo "Exposure must be a whole number from 0 to 255." >&2
    exit 65
  fi
  value=$((10#$value))
  require_camera
  v4l2-ctl -d "$DEVICE" --set-ctrl=gain_automatic=0
  v4l2-ctl -d "$DEVICE" --set-ctrl="exposure=$value"
  echo "AUTO=0"
  echo "EXPOSURE=$value"
}

case "${1:-}" in
  check)
    require_camera
    v4l2-ctl -d "$DEVICE" --get-fmt-video
    ;;

  controls)
    require_camera
    AUTO_VALUE="$(v4l2-ctl -d "$DEVICE" --get-ctrl=gain_automatic | awk '{print $2}')"
    EXPOSURE_VALUE="$(v4l2-ctl -d "$DEVICE" --get-ctrl=exposure | awk '{print $2}')"
    echo "AUTO=$AUTO_VALUE"
    echo "EXPOSURE=$EXPOSURE_VALUE"
    ;;

  auto)
    require_camera
    v4l2-ctl -d "$DEVICE" --set-ctrl=gain_automatic=1
    echo "AUTO=1"
    ;;

  exposure)
    set_manual_exposure "${2:?Exposure value is required}"
    ;;

  preset)
    case "${2:-}" in
      venus)   set_manual_exposure 20 ;;
      jupiter) set_manual_exposure 50 ;;
      saturn)  set_manual_exposure 105 ;;
      moon)    set_manual_exposure 30 ;;
      auto)    require_camera; v4l2-ctl -d "$DEVICE" --set-ctrl=gain_automatic=1; echo "AUTO=1" ;;
      *) echo "Preset must be venus, jupiter, saturn, moon, or auto." >&2; exit 64 ;;
    esac
    ;;

  preview)
    require_camera
    CROSSHAIR="${2:-on}"
    if tracked_pid "$PREVIEW_PID_FILE" ffplay >/dev/null; then
      echo "A preview is already running." >&2
      exit 3
    fi
    rm -f "$PREVIEW_PID_FILE"

    FILTERS="format=rgb24"
    if [[ "$CROSSHAIR" == "on" ]]; then
      FILTERS+=",drawbox=x=iw/2:y=0:w=2:h=ih:color=white@0.42:t=fill"
      FILTERS+=",drawbox=x=0:y=ih/2:w=iw:h=2:color=white@0.42:t=fill"
      FILTERS+=",drawbox=x=iw/2-22:y=ih/2-22:w=44:h=44:color=white@0.55:t=1"
    fi

    ffplay -hide_banner -loglevel warning \
      -window_title "Orion StarShoot Planetary Preview - close when finished" \
      -x 960 -y 720 -fflags nobuffer -flags low_delay -framedrop \
      -f v4l2 -input_format bayer_bggr8 -video_size 640x480 \
      -vf "$FILTERS" -i "$DEVICE" &
    PREVIEW_PID=$!
    echo "$PREVIEW_PID" > "$PREVIEW_PID_FILE"

    preview_cleanup() {
      rm -f "$PREVIEW_PID_FILE"
      recover_camera >/dev/null 2>&1 || true
    }
    trap preview_cleanup EXIT
    trap 'kill -TERM "$PREVIEW_PID" 2>/dev/null || true' INT TERM HUP
    set +e
    wait "$PREVIEW_PID"
    set -e
    ;;

  stop-preview)
    if stop_pid_file "$PREVIEW_PID_FILE" TERM ffplay; then
      echo "Stopping live preview..."
    else
      echo "No tracked preview was running."
    fi
    sleep 1
    recover_camera
    echo "CAMERA_READY=1"
    ;;

  recover)
    recover_camera
    echo "CAMERA_READY=1"
    ;;

  snapshot)
    OUTPUT="${2:?Snapshot output path is required}"
    if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then
      echo "Refusing to overwrite an existing capture: $OUTPUT" >&2
      exit 73
    fi
    require_camera
    RAW_FILE="$(mktemp --suffix=.raw)"
    trap 'rm -f "$RAW_FILE"' EXIT
    mkdir -p "$(dirname "$OUTPUT")"
    v4l2-ctl -d "$DEVICE" \
      --set-fmt-video=width=1280,height=1024,pixelformat=BA81 \
      --stream-mmap=3 --stream-count=1 --stream-to="$RAW_FILE"
    ffmpeg -nostdin -hide_banner -loglevel error -n \
      -f rawvideo -pixel_format bayer_bggr8 -video_size 1280x1024 \
      -i "$RAW_FILE" -frames:v 1 "$OUTPUT"
    echo "$OUTPUT"
    ;;

  record)
    OUTPUT="${2:?Recording output path is required}"
    if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then
      echo "Refusing to overwrite an existing capture: $OUTPUT" >&2
      exit 73
    fi
    DURATION="${3:-10}"
    if ! [[ "$DURATION" =~ ^[0-9]{1,5}$ ]] || (( 10#$DURATION < 1 || 10#$DURATION > 86400 )); then
      echo "Recording duration must be a whole number from 1 to 86400 seconds." >&2
      exit 65
    fi
    DURATION=$((10#$DURATION))
    require_camera
    if tracked_pid "$RECORD_PID_FILE" ffmpeg >/dev/null; then
      echo "A recording is already running." >&2
      exit 3
    fi
    mkdir -p "$(dirname "$OUTPUT")"
    rm -f "$RECORD_PID_FILE"
    ffmpeg -nostdin -hide_banner -loglevel warning -n \
      -f v4l2 -input_format bayer_bggr8 -video_size 640x480 -i "$DEVICE" \
      -t "$DURATION" -c:v rawvideo -pix_fmt bgr24 "$OUTPUT" &
    CHILD_PID=$!
    echo "$CHILD_PID" > "$RECORD_PID_FILE"
    cleanup_recording() {
      rm -f "$RECORD_PID_FILE"
    }
    trap cleanup_recording EXIT
    trap 'kill -INT "$CHILD_PID" 2>/dev/null || true' INT TERM
    set +e
    wait "$CHILD_PID"
    RECORD_RESULT=$?
    set -e
    if (( RECORD_RESULT != 0 && RECORD_RESULT != 130 && RECORD_RESULT != 255 )); then
      exit "$RECORD_RESULT"
    fi
    ;;

  stop)
    if stop_pid_file "$RECORD_PID_FILE" INT ffmpeg; then
      echo "Stopping recording safely..."
    else
      echo "No recording is running."
    fi
    ;;

  *)
    echo "Usage: $0 {check|controls|auto|exposure VALUE|preset NAME|preview [on|off]|stop-preview|recover|snapshot OUTPUT|record OUTPUT SECONDS|stop}" >&2
    exit 64
    ;;
esac
