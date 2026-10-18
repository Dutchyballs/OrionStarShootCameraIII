"""Hardware-free protocol, image orientation, cancellation and failure checks."""
import json
from pathlib import Path
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "alpaca"))
from orion_alpaca import (Camera, CameraError, Server, Simulator, discovery,
                          DRIVER_ERROR, INVALID_OPERATION, INVALID_VALUE, NOT_CONNECTED)
from orion_v4l2 import V4L2


class TinySimulator(Simulator):
    width, height = 6, 4

    def capture(self, duration, cancel):
        if cancel.wait(duration):
            return None
        return bytes(range(self.width * self.height))


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.camera = Camera(TinySimulator())
        self.server = Server(("127.0.0.1", 0), self.camera)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.camera.close()
        self.thread.join(timeout=2)

    def call(self, member, method="GET", headers=None, **params):
        path = member if member.startswith("/") else "/api/v1/camera/0/" + member
        encoded = urlencode(params).encode()
        request = Request(self.url + path + ("?" + encoded.decode() if method == "GET" else ""),
                          data=encoded if method == "PUT" else None, method=method,
                          headers=headers or {})
        with urlopen(request, timeout=3) as response:
            raw = response.read()
            return raw if response.headers.get_content_type() == "application/imagebytes" else json.loads(raw)

    def connect(self):
        result = self.call("connected", "PUT", Connected="true")
        self.assertEqual(result["ErrorNumber"], 0)

    def expose(self, duration=0.01):
        result = self.call("startexposure", "PUT", Duration=duration, Light="true")
        self.assertEqual(result["ErrorNumber"], 0, result)
        deadline = time.monotonic() + 2
        while not self.call("imageready").get("Value"):
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.005)

    def test_connection_and_transactions(self):
        result = self.call("cameraxsize", ClientTransactionID=77)
        self.assertEqual(result["ClientTransactionID"], 77)
        self.assertEqual(result["ErrorNumber"], NOT_CONNECTED)
        self.connect()
        self.assertEqual(self.call("CameraXSize")["Value"], 6)
        self.assertGreater(self.call("connected")["ServerTransactionID"], result["ServerTransactionID"])

    def test_management_and_simulator_identity(self):
        devices = self.call("/management/v1/configureddevices")["Value"]
        self.assertIn("SIMULATOR", devices[0]["DeviceName"])
        self.assertEqual(devices[0]["DeviceType"], "Camera")
        self.assertEqual(self.call("/management/apiversions")["Value"], [1])
        self.assertRegex(self.call("driverversion")["Value"], r"^\d+\.\d+$")

    def test_json_orientation_and_last_exposure(self):
        self.connect()
        self.expose()
        result = self.call("imagearray")
        self.assertEqual((result["Type"], result["Rank"]), (2, 2))
        self.assertEqual(result["Value"], [[0, 6, 12, 18], [1, 7, 13, 19], [2, 8, 14, 20],
                                            [3, 9, 15, 21], [4, 10, 16, 22], [5, 11, 17, 23]])
        self.assertEqual(self.call("lastexposureduration")["Value"], 0.01)
        self.assertIn("T", self.call("lastexposurestarttime")["Value"])

    def test_imagebytes_matches_json_and_echoes_transaction(self):
        self.connect()
        self.expose()
        raw = self.call("imagearray", headers={"Accept": "application/imagebytes"}, ClientTransactionID=123)
        header = struct.unpack("<iiIIiiiiiii", raw[:44])
        self.assertEqual(header[:3], (1, 0, 123))
        self.assertEqual(header[4:], (44, 2, 6, 2, 6, 4, 0))
        expected = bytes(value for column in self.call("imagearray")["Value"] for value in column)
        self.assertEqual(raw[44:], expected)

    def test_even_subframe_crop(self):
        self.connect()
        for member, value in (("startx", 2), ("starty", 2), ("numx", 3), ("numy", 2)):
            self.assertEqual(self.call(member, "PUT", **{member: value})["ErrorNumber"], 0)
        self.expose()
        self.assertEqual(self.call("imagearray")["Value"], [[14, 20], [15, 21], [16, 22]])

    def test_rejects_geometry_binning_and_nonfinite_durations(self):
        self.connect()
        for member, value in (("startx", 1), ("numx", 0), ("biny", 2), ("binx", "1.5")):
            self.assertEqual(self.call(member, "PUT", **{member: value})["ErrorNumber"], INVALID_VALUE)
        for duration in ("nan", "inf", "-1", "text"):
            self.assertEqual(self.call("startexposure", "PUT", Duration=duration, Light="true")["ErrorNumber"], INVALID_VALUE)
        self.call("startx", "PUT", StartX=4)
        self.assertEqual(self.call("startexposure", "PUT", Duration=0.01, Light="true")["ErrorNumber"], INVALID_VALUE)

    def test_abort_and_reconnect_never_publish_old_frame(self):
        self.connect()
        self.call("startexposure", "PUT", Duration=0.5, Light="true")
        self.assertEqual(self.call("numx", "PUT", NumX=2)["ErrorNumber"], INVALID_OPERATION)
        self.call("abortexposure", "PUT")
        self.camera.worker.join(timeout=1)
        self.assertFalse(self.call("imageready")["Value"])
        self.call("connected", "PUT", Connected="false")
        self.assertEqual(self.call("imageready")["ErrorNumber"], NOT_CONNECTED)
        self.connect()
        self.expose()
        self.assertTrue(self.call("imageready")["Value"])

    def test_abort_and_disconnect_finish_cleanup_before_returning(self):
        started = threading.Event()

        def slow_cleanup(duration, cancel):
            started.set()
            cancel.wait(1)
            time.sleep(0.05)  # A capture process needs time to close its device.
            return None

        self.connect()
        for member, parameters in (("abortexposure", {}), ("connected", {"Connected": "false"})):
            started.clear()
            self.camera.backend.capture = slow_cleanup
            self.call("startexposure", "PUT", Duration=0.5, Light="true")
            self.assertTrue(started.wait(1))
            self.call(member, "PUT", **parameters)
            self.assertFalse(self.camera.worker.is_alive(), "Cancellation returned before device cleanup finished")
            self.connect()
            self.camera.backend.capture = TinySimulator().capture
            self.expose()

    def test_error_does_not_leave_client_polling_forever(self):
        def fail(duration, cancel):
            raise OSError("camera unplugged")
        self.camera.backend.capture = fail
        self.connect()
        self.call("startexposure", "PUT", Duration=0.01, Light="true")
        self.camera.worker.join(timeout=1)
        result = self.call("imageready")
        self.assertEqual(result["ErrorNumber"], DRIVER_ERROR)
        self.assertIn("unplugged", result["ErrorMessage"])
        self.assertEqual(self.call("camerastate")["Value"], 5)

    def test_missing_image_is_an_error_not_black_pixels(self):
        self.connect()
        self.assertEqual(self.call("imagearray")["ErrorNumber"], INVALID_OPERATION)
        self.assertEqual(self.call("lastexposureduration")["ErrorNumber"], INVALID_OPERATION)

    def test_unknown_hardware_start_time_is_not_a_host_timestamp(self):
        self.connect()
        self.camera.backend.supports_start_time = False
        result = self.call("lastexposurestarttime")
        self.assertEqual(result["ErrorNumber"], 0x400)
        self.assertNotIn("Value", result)

    def test_bias_request_reports_actual_shortest_duration(self):
        self.connect()
        self.expose(0)
        self.assertEqual(self.call("lastexposureduration")["Value"], 0.001)

    def test_malformed_parameters_and_unknown_path(self):
        self.assertEqual(self.call("connected", "PUT", Connected="yes")["ErrorNumber"], INVALID_VALUE)
        self.assertEqual(self.call("connected", ClientTransactionID="abc")["ErrorNumber"], INVALID_VALUE)
        with self.assertRaises(HTTPError) as error:
            self.call("/api/v1/camera/1/name")
        self.assertEqual(error.exception.code, 404)

    def test_loopback_discovery(self):
        stop = threading.Event()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        thread = threading.Thread(target=discovery, args=(11111, stop, "127.0.0.1", port))
        thread.start()
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                client.settimeout(0.2)
                for attempt in range(10):
                    client.sendto(b"alpacadiscovery1", ("127.0.0.1", port))
                    try:
                        packet, _ = client.recvfrom(512)
                        break
                    except socket.timeout:
                        if attempt == 9:
                            raise
                self.assertEqual(json.loads(packet), {"AlpacaPort": 11111})
        finally:
            stop.set()
            thread.join(timeout=2)


class CalibrationTests(unittest.TestCase):
    def test_no_profile_cannot_trigger_camera_capture(self):
        backend = V4L2("/dev/video0")
        with self.assertRaises(CameraError) as error:
            backend.capture(1, threading.Event())
        self.assertEqual(error.exception.number, INVALID_OPERATION)
        self.assertIn("uncalibrated", str(error.exception))
        with self.assertRaises(CameraError) as error:
            backend.connect()
        self.assertEqual(error.exception.number, INVALID_OPERATION)

    def test_profile_validation_and_no_interpolation(self):
        profile = {"usb_id": "0e96:c001", "width": 1280, "height": 1024,
                   "pixel_format": "BA81", "evidence": "SYNTHETIC UNIT TEST ONLY",
                   "kernel_release": "test", "exposures": [{"seconds": 0.01, "register": 20},
                                                            {"seconds": 0.02, "register": 40}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "profile.json"
            path.write_text(json.dumps(profile), encoding="utf-8")
            backend = V4L2("/dev/video0", path)
            self.assertEqual(backend.validate_duration(0.02), 0.02)
            self.assertEqual((backend.minimum, backend.maximum), (0.01, 0.02))
            self.assertEqual(backend.validate_duration(0.015), 0.01)
            self.assertEqual(backend.validate_duration(0.019), 0.02)
            self.assertEqual(backend.validate_duration(0), 0.01)
            with self.assertRaises(CameraError):
                backend.validate_duration(0.03)
            for key, bad_value in (("usb_id", "1234:5678"), ("width", 640), ("exposures", []),
                                   ("pixel_size_um", float("nan"))):
                invalid = dict(profile, **{key: bad_value})
                path.write_text(json.dumps(invalid), encoding="utf-8")
                with self.assertRaises(ValueError):
                    V4L2("/dev/video0", path)


class BackendLifecycleTests(unittest.TestCase):
    def backend(self):
        backend = V4L2("/dev/video0")
        backend.profile = {"kernel_release": "SYNTHETIC TEST ONLY"}
        backend.entries = [{"seconds": 0.01, "register": 20}]
        backend.minimum = backend.maximum = 0.01
        backend.connect = lambda: None  # No physical device in these process tests.
        backend.commands = []

        def command(args):
            backend.commands.append(args)
            if "--get-fmt-video" in args:
                return "Width/Height : 1280/1024\nPixel Format : 'BA81'\nBytes per Line : 1280"
            if "--get-ctrl=gain_automatic,exposure" in args:
                return "gain_automatic: 0\nexposure: 20"
            return ""
        backend._run = command
        return backend

    def test_busy_camera_is_not_reconfigured(self):
        backend = self.backend()
        with patch("orion_v4l2.subprocess.run", return_value=SimpleNamespace(returncode=0)):
            with self.assertRaisesRegex(RuntimeError, "busy"):
                backend.capture(0.01, threading.Event())
        self.assertEqual(backend.commands, [])

    def test_incomplete_frame_is_rejected(self):
        backend = self.backend()

        def captured_process(args, **kwargs):
            target = next(arg.split("=", 1)[1] for arg in args if arg.startswith("--stream-to="))
            Path(target).write_bytes(b"incomplete")
            return SimpleNamespace(poll=lambda: 0, returncode=0)

        with patch("orion_v4l2.subprocess.run", return_value=SimpleNamespace(returncode=1)), \
                patch("orion_v4l2.subprocess.Popen", side_effect=captured_process):
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                backend.capture(0.01, threading.Event())

    def test_cancel_terminates_only_its_capture_child(self):
        backend = self.backend()
        cancel = threading.Event()
        actions = []

        class CaptureChild:
            returncode = None

            def poll(self):
                return self.returncode

            def terminate(self):
                actions.append("terminate")
                self.returncode = -15

            def wait(self, timeout):
                actions.append("wait")
                return self.returncode

        def launch(*args, **kwargs):
            cancel.set()
            return CaptureChild()

        with patch("orion_v4l2.subprocess.run", return_value=SimpleNamespace(returncode=1)), \
                patch("orion_v4l2.subprocess.Popen", side_effect=launch):
            self.assertIsNone(backend.capture(0.01, cancel))
        self.assertEqual(actions, ["terminate", "wait"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
