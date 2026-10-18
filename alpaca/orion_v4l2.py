"""Linux ov519 backend. Requires v4l2-ctl and fuser; never resets USB."""
import json
import math
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import tempfile
import time

from orion_alpaca import CameraError, INVALID_OPERATION, INVALID_VALUE


class V4L2:
    width, height = 1280, 1024
    name = "Orion StarShoot III (experimental)"
    supports_start_time = False
    pixel_size = None
    minimum = maximum = 0.0
    resolution = 0.001

    def __init__(self, device, profile_path=None):
        self.device = str(Path(device).resolve())
        self.profile = None
        self.entries = []
        if profile_path:
            profile = json.loads(Path(profile_path).read_text(encoding="utf-8"))
            expected = {"usb_id": "0e96:c001", "width": self.width, "height": self.height,
                        "pixel_format": "BA81"}
            if any(profile.get(key) != value for key, value in expected.items()):
                raise ValueError("Exposure profile does not match this camera and full-resolution mode")
            if not profile.get("evidence") or not profile.get("kernel_release"):
                raise ValueError("Profile needs measurement evidence and the measured kernel release")
            entries = profile.get("exposures", [])
            for entry in entries:
                seconds, register = entry["seconds"], entry["register"]
                if (isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or
                        not math.isfinite(seconds) or not 0 < seconds <= 60 or
                        type(register) is not int or not 0 <= register <= 255):
                    raise ValueError("Invalid measured exposure entry")
            if not entries or len({e["seconds"] for e in entries}) != len(entries):
                raise ValueError("Profile needs unique measured exposure entries")
            pixel = profile.get("pixel_size_um")
            if pixel is not None and (isinstance(pixel, bool) or not isinstance(pixel, (int, float)) or
                                      not math.isfinite(pixel) or pixel <= 0):
                raise ValueError("Invalid measured pixel size")
            self.pixel_size = pixel
            self.profile = profile
            self.entries = sorted(entries, key=lambda item: item["seconds"])
            self.minimum, self.maximum = self.entries[0]["seconds"], self.entries[-1]["seconds"]
            # Requests select the nearest measured entry, never an invented time.
            self.resolution = min((b["seconds"] - a["seconds"] for a, b in
                                   zip(self.entries, self.entries[1:])), default=self.minimum)

    def validate_duration(self, duration):
        if not self.profile:
            raise CameraError(INVALID_OPERATION,
                              "Sensor integration time is uncalibrated. Supply a measured "
                              "--profile; a frame wait is not an exposure. See docs/NINA_SETUP.md")
        if duration == 0:
            return self.minimum
        if not math.isfinite(duration) or not self.minimum <= duration <= self.maximum:
            raise CameraError(INVALID_VALUE, f"Duration must be {self.minimum}..{self.maximum} seconds")
        return min(self.entries, key=lambda entry: (abs(entry["seconds"] - duration), entry["seconds"]))["seconds"]

    def _run(self, arguments):
        result = subprocess.run(arguments, capture_output=True, timeout=5, check=False)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace").strip() or
                               "Camera command failed: " + arguments[0])
        return result.stdout.decode(errors="replace")

    def connect(self):
        if not self.profile:
            raise CameraError(INVALID_OPERATION, "Measured --profile is required before connecting the physical Alpaca camera")
        if platform.system() != "Linux":
            raise RuntimeError("Real camera backend runs inside Linux/WSL; use --simulate on Windows")
        for command in ("v4l2-ctl", "fuser"):
            if not shutil.which(command):
                raise RuntimeError("Install required tool: " + command)
        device = Path(self.device)
        if not stat.S_ISCHR(device.stat().st_mode):
            raise RuntimeError("Camera path must be a character device")
        usb = (Path("/sys/class/video4linux") / device.name / "device").resolve()
        identity = None
        for parent in (usb, *usb.parents):
            if (parent / "idVendor").is_file() and (parent / "idProduct").is_file():
                identity = ((parent / "idVendor").read_text().strip().lower() + ":" +
                            (parent / "idProduct").read_text().strip().lower())
                break
        if identity != "0e96:c001":
            raise RuntimeError("Refusing camera: USB identity is not 0e96:c001")
        info = self._run(["v4l2-ctl", "-d", self.device, "--info"])
        if not re.search(r"Driver name\s*:\s*(?:gspca_)?ov519\b", info):
            raise RuntimeError("Camera is not using the ov519 driver")
        if self.profile and platform.release() != self.profile["kernel_release"]:
            raise RuntimeError("Kernel differs from measured profile; revalidate exposure timing")

    def capture(self, duration, cancel):
        # Recheck identity on every exposure, including after unplug/replug.
        duration = self.validate_duration(duration)
        self.connect()
        busy = subprocess.run(["fuser", self.device], capture_output=True, timeout=5, check=False)
        if busy.returncode != 1:
            raise RuntimeError("Camera is busy or ownership check failed; close other capture apps")
        register = next(e["register"] for e in self.entries if e["seconds"] == duration)
        if cancel.is_set():
            return None
        self._run(["v4l2-ctl", "-d", self.device, "--set-ctrl", f"gain_automatic=0,exposure={register}"])
        with tempfile.TemporaryDirectory(prefix="orion-alpaca-") as directory:
            target = Path(directory) / "frame.raw"
            args = ["v4l2-ctl", "-d", self.device, "--silent",
                    "--set-fmt-video=width=1280,height=1024,pixelformat=BA81",
                    "--stream-mmap=4", "--stream-skip=3", "--stream-count=1",
                    "--stream-to=" + str(target)]
            # Output goes to a file so pipes cannot deadlock the worker.
            with (Path(directory) / "capture.log").open("wb") as log:
                process = subprocess.Popen(args, stdout=log, stderr=log)
                deadline = time.monotonic() + max(12.0, 4 * duration + 5)
                try:
                    while process.poll() is None:
                        if cancel.wait(0.05):
                            return None
                        if time.monotonic() > deadline:
                            raise RuntimeError("Timed out waiting for camera frame")
                    if process.returncode:
                        raise RuntimeError("Camera frame capture failed; reconnect and inspect v4l2-ctl")
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=2)
            if cancel.is_set():
                return None
            fmt = self._run(["v4l2-ctl", "-d", self.device, "--get-fmt-video"])
            if not (re.search(r"Width/Height\s*:\s*1280/1024", fmt) and
                    re.search(r"Pixel Format\s*:\s*'BA81'", fmt) and
                    re.search(r"Bytes per Line\s*:\s*1280\b", fmt)):
                raise RuntimeError("Unexpected camera geometry, stride or pixel format")
            controls = self._run(["v4l2-ctl", "-d", self.device, "--get-ctrl=gain_automatic,exposure"])
            if not (re.search(r"gain_automatic\s*:\s*0\b", controls) and
                    re.search(r"exposure\s*:\s*" + str(register) + r"\b", controls)):
                raise RuntimeError("Manual exposure controls did not read back correctly")
            raw = target.read_bytes()
            if len(raw) != self.width * self.height:
                raise RuntimeError("Camera returned an incomplete or padded BGGR8 frame")
            return raw
