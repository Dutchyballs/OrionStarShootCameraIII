#!/usr/bin/env python3
"""Hardware-free regression tests for the Linux camera command's safety checks."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "orion-camera.sh"


class CameraSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="orion-safety-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = self.root / "runtime"
        self.env = dict(os.environ, ORION_RUNTIME_DIR=str(self.runtime), ORION_VIDEO_DEVICE="/dev/null")

    def run_camera(self, *arguments, expected=0):
        result = subprocess.run(
            ["bash", str(SCRIPT), *arguments], env=self.env, text=True,
            capture_output=True, timeout=10,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def mock_camera(self, vendor="0e96", product="c001"):
        usb = self.root / "usb-device"
        video = usb / "interface" / "video"
        video.mkdir(parents=True)
        (usb / "idVendor").write_text(vendor + "\n")
        (usb / "idProduct").write_text(product + "\n")
        binary_dir = self.root / "bin"
        binary_dir.mkdir()
        self.env["ORION_TEST_READLINK"] = shutil.which("readlink")
        self.env["ORION_TEST_SYSFS"] = str(video)
        scripts = {
            "readlink": '#!/usr/bin/env bash\nif [[ "${3:-}" == /sys/class/video4linux/null/device ]]; then printf "%s\n" "$ORION_TEST_SYSFS"; else exec "$ORION_TEST_READLINK" "$@"; fi\n',
            "v4l2-ctl": '#!/usr/bin/env bash\necho MOCK_CAMERA_FORMAT\n',
        }
        for name, content in scripts.items():
            executable = binary_dir / name
            executable.write_text(content)
            executable.chmod(0o755)
        self.env["PATH"] = str(binary_dir) + os.pathsep + self.env["PATH"]

    def test_orion_usb_parent_identity_is_accepted(self):
        self.mock_camera()
        self.assertIn("MOCK_CAMERA_FORMAT", self.run_camera("check").stdout)

    def test_other_usb_camera_is_rejected(self):
        self.mock_camera(vendor="1234")
        self.assertIn("not the Orion camera", self.run_camera("check", expected=2).stderr)

    def named_media_process(self, name, device):
        code = (
            "import ctypes,signal,sys,time; "
            f"ctypes.CDLL(None).prctl(15, {name.encode()!r}, 0, 0, 0); "
            "signal.signal(signal.SIGINT, lambda *_: sys.exit(0)); "
            "print('ready', flush=True); time.sleep(60)"
        )
        process = subprocess.Popen([sys.executable, "-c", code, device], stdout=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
            process.stdout.close()
        self.addCleanup(cleanup)
        self.assertEqual(process.stdout.readline().strip(), "ready")
        return process

    def test_tracked_recording_can_be_stopped(self):
        self.run_camera("stop")
        process = self.named_media_process("ffmpeg", "/dev/null")
        (self.runtime / "record.pid").write_text(str(process.pid))
        self.assertIn("Stopping recording safely", self.run_camera("stop").stdout)
        self.assertEqual(process.wait(timeout=5), 0)

    def test_reused_media_pid_for_other_device_is_not_stopped(self):
        self.run_camera("stop")
        process = self.named_media_process("ffmpeg", "/dev/other-camera")
        (self.runtime / "record.pid").write_text(str(process.pid))
        self.assertIn("No recording is running", self.run_camera("stop").stdout)
        self.assertIsNone(process.poll())

    def test_untracked_preview_does_not_stop_other_media_players(self):
        # Never allow a regression to send pkill to the developer's real players.
        binary_dir = self.root / "bin"
        binary_dir.mkdir()
        pkill = binary_dir / "pkill"
        pkill.write_text('#!/usr/bin/env bash\nprintf intercepted > "$ORION_TEST_SIGNAL_LOG"\nexit 97\n')
        pkill.chmod(0o755)
        self.env["PATH"] = str(binary_dir) + os.pathsep + self.env["PATH"]
        signal_log = self.root / "signal-attempt"
        self.env["ORION_TEST_SIGNAL_LOG"] = str(signal_log)
        process = self.named_media_process("ffplay", "/dev/other-camera")
        self.run_camera("stop-preview", expected=2)
        self.assertIsNone(process.poll())
        self.assertFalse(signal_log.exists())

    def test_recovery_does_not_stop_untracked_camera_client(self):
        self.mock_camera()
        process = self.named_media_process("ffplay", "/dev/null")
        self.env["ORION_TEST_HOLDER_PID"] = str(process.pid)
        reset_log = self.root / "reset-attempt"
        self.env["ORION_TEST_RESET_LOG"] = str(reset_log)
        for name, content in {
            "fuser": '#!/usr/bin/env bash\necho "$ORION_TEST_HOLDER_PID"\nexit 0\n',
            "sleep": '#!/usr/bin/env bash\nexit 0\n',
            "usbreset": '#!/usr/bin/env bash\nprintf intercepted > "$ORION_TEST_RESET_LOG"\nexit 97\n',
        }.items():
            binary = self.root / "bin" / name
            binary.write_text(content)
            binary.chmod(0o755)
        result = self.run_camera("recover", expected=1)
        self.assertIn("still busy", result.stderr)
        self.assertIsNone(process.poll())
        self.assertFalse(reset_log.exists())

    def test_runtime_is_private(self):
        self.run_camera("stop")
        self.assertEqual(self.runtime.stat().st_mode & 0o777, 0o700)

    def test_runtime_symlink_is_rejected(self):
        target = self.root / "target"
        target.mkdir(mode=0o700)
        self.runtime.symlink_to(target, target_is_directory=True)
        self.run_camera("stop", expected=73)
        self.assertEqual(list(target.iterdir()), [])

    def test_world_accessible_runtime_is_rejected(self):
        self.runtime.mkdir()
        self.runtime.chmod(0o755)
        self.run_camera("stop", expected=73)

    def test_unrelated_character_device_is_rejected(self):
        result = self.run_camera("check", expected=2)
        self.assertIn("not the Orion camera", result.stderr)

    def test_existing_capture_is_never_overwritten(self):
        output = self.root / "valuable capture.png"
        output.write_bytes(b"original capture")
        for command in ("snapshot", "record"):
            with self.subTest(command=command):
                self.run_camera(command, str(output), expected=73)
                self.assertEqual(output.read_bytes(), b"original capture")

    def test_dangling_output_symlink_is_rejected(self):
        output = self.root / "capture.avi"
        output.symlink_to(self.root / "missing-target")
        self.run_camera("record", str(output), expected=73)
        self.assertTrue(output.is_symlink())
        self.assertFalse(output.exists())

    def test_invalid_duration_is_rejected_before_accessing_device(self):
        for duration in ("0", "-1", "1.5", "abc", "86401", "9" * 100):
            with self.subTest(duration=duration):
                self.run_camera("record", str(self.root / "new.avi"), duration, expected=65)

    def test_invalid_exposure_is_rejected_before_accessing_device(self):
        for exposure in ("-1", "256", "1.5", "abc", "9" * 100):
            with self.subTest(exposure=exposure):
                self.run_camera("exposure", exposure, expected=65)

    def test_decimal_values_with_leading_zeroes_are_accepted(self):
        # The later identity check fails: validation itself must accept 008/009.
        self.assertIn("not the Orion camera", self.run_camera("exposure", "008", expected=2).stderr)
        self.assertIn("not the Orion camera", self.run_camera("record", str(self.root / "new.avi"), "009", expected=2).stderr)

    def test_unsafe_or_unrelated_pids_are_not_signalled(self):
        # Guard the host even if future changes reintroduce unsafe kill calls.
        guard = self.root / "signal-guard.sh"
        signal_log = self.root / "signal-attempt"
        guard.write_text('kill() { printf intercepted > "$ORION_TEST_SIGNAL_LOG"; return 97; }\n')
        self.env["BASH_ENV"] = str(guard)
        self.env["ORION_TEST_SIGNAL_LOG"] = str(signal_log)
        self.run_camera("stop")
        for value in ("-1", "0", "1", "not-a-pid", str(os.getpid())):
            with self.subTest(pid=value):
                (self.runtime / "record.pid").write_text(value)
                result = self.run_camera("stop")
                self.assertIn("No recording is running", result.stdout)
                self.assertFalse((self.runtime / "record.pid").exists())
                self.assertFalse(signal_log.exists())

    def test_pid_symlink_target_is_not_modified(self):
        self.run_camera("stop")
        target = self.root / "unrelated-file"
        target.write_text(str(os.getpid()))
        (self.runtime / "record.pid").symlink_to(target)
        self.run_camera("stop")
        self.assertEqual(target.read_text(), str(os.getpid()))
        self.assertFalse((self.runtime / "record.pid").is_symlink())


if __name__ == "__main__":
    unittest.main(verbosity=2)
