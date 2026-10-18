#!/usr/bin/env python3
"""Experimental Orion Alpaca camera. Standard library only; no USB rebinding.

Real capture is deliberately disabled without measured exposure calibration.
Run on Linux/WSL with ov519, or use --simulate on Windows for client testing.
"""
import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import socket
import struct
import threading
import time
from urllib.parse import parse_qs, urlsplit

VERSION = "0.1.0"
NOT_IMPLEMENTED, INVALID_VALUE, NOT_CONNECTED, INVALID_OPERATION, DRIVER_ERROR = (
    0x400, 0x401, 0x407, 0x40B, 0x500)


class CameraError(Exception):
    def __init__(self, number, message):
        super().__init__(message)
        self.number = number


def integer(value):
    try:
        return int(str(value))
    except (ValueError, TypeError):
        raise CameraError(INVALID_VALUE, "Expected an integer") from None


def boolean(value):
    if str(value).lower() not in ("true", "false"):
        raise CameraError(INVALID_VALUE, "Expected true or false")
    return str(value).lower() == "true"


class Simulator:
    width, height = 1280, 1024
    pixel_size = 3.6  # Synthetic geometry, not a claim about the physical camera.
    minimum, maximum, resolution = 0.001, 60.0, 0.001
    name = "Orion StarShoot III SIMULATOR"
    supports_start_time = True

    def connect(self):
        pass

    def capture(self, duration, cancel):
        if cancel.wait(duration):
            return None
        # Non-square, spatially varying BGGR mosaic catches axis/byte errors.
        phase = int(time.monotonic() * 10) % 32
        return bytes((x // 8 + y // 8 + phase + (40 if x % 2 == y % 2 else 0)) % 256
                     for y in range(self.height) for x in range(self.width))

    def validate_duration(self, duration):
        if duration == 0:
            return self.minimum  # ASCOM bias requests select the shortest exposure.
        if not self.minimum <= duration <= self.maximum:
            raise CameraError(INVALID_VALUE, "Simulator duration must be 0.001..60 seconds")
        return duration


class Camera:
    def __init__(self, backend):
        self.backend = backend
        self.lock = threading.RLock()
        self.connected = False
        self.worker = None
        self.cancelling = False
        self.cancel = threading.Event()
        self.image = None
        self.error = None
        self.state = 0
        self.start_x = self.start_y = 0
        self.num_x, self.num_y = backend.width, backend.height
        self.duration = None
        self.started = None
        self.monotonic_start = None
        self.image_geometry = None

    def abort(self):
        # Keep the worker reference until it finishes: reconnect cannot race I/O.
        with self.lock:
            worker = self.worker
            self.cancelling = True
            self.cancel.set()
            self.image = None
            self.error = None
            self.state = 0
        # The worker takes the same lock when publishing or discarding its result.
        # Never hold it while waiting for device/process cleanup.
        try:
            if worker and worker is not threading.current_thread():
                worker.join(timeout=15)
                if worker.is_alive():
                    with self.lock:
                        self.state = 5
                        self.error = "Camera capture did not finish cancelling; reconnect after cleanup"
                    raise CameraError(DRIVER_ERROR, self.error)
        finally:
            with self.lock:
                self.cancelling = False

    def close(self):
        self.abort()

    def require_connected(self):
        if not self.connected:
            raise CameraError(NOT_CONNECTED, "Connect the camera first")

    def require_idle(self):
        if self.cancelling or (self.worker and self.worker.is_alive()):
            raise CameraError(INVALID_OPERATION, "Capture is still running or cancelling")

    def start(self, duration):
        self.require_idle()
        try:
            duration = float(duration)
        except (ValueError, TypeError):
            raise CameraError(INVALID_VALUE, "Invalid exposure duration") from None
        if not math.isfinite(duration):
            raise CameraError(INVALID_VALUE, "Duration must be finite")
        duration = self.backend.validate_duration(duration)
        w, h = self.backend.width, self.backend.height
        x, y, nx, ny = self.start_x, self.start_y, self.num_x, self.num_y
        if x + nx > w or y + ny > h:
            raise CameraError(INVALID_VALUE, "Subframe extends beyond the sensor")
        self.image = self.error = None
        self.image_geometry = (x, y, nx, ny)
        self.duration = duration
        self.started = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]
        self.monotonic_start = time.monotonic()
        self.cancel = threading.Event()
        self.state = 2
        self.worker = threading.Thread(target=self._capture, args=(duration, self.cancel), daemon=True)
        self.worker.start()

    def _capture(self, duration, cancel):
        try:
            raw = self.backend.capture(duration, cancel)
            with self.lock:
                if cancel.is_set():
                    return
                if raw is None or len(raw) != self.backend.width * self.backend.height:
                    raise RuntimeError("Incomplete camera frame")
                x, y, nx, ny = self.image_geometry
                # ASCOM ImageArray is [x,y], unlike V4L2's [y,x].
                self.image = bytes(raw[(y + row) * self.backend.width + x + col]
                                   for col in range(nx) for row in range(ny))
                self.state = 0
        except Exception as exc:
            with self.lock:
                if not cancel.is_set():
                    self.image = None
                    self.error = str(exc)
                    self.state = 5

    def image_data(self):
        if self.error:
            raise CameraError(DRIVER_ERROR, self.error)
        if self.image is None:
            raise CameraError(INVALID_OPERATION, "No completed exposure is available")
        return self.image, self.image_geometry[2:]

    def request(self, method, member, params):
        # Abort/disconnect must join outside the main request lock, otherwise the
        # capture worker cannot finish and every cancellation would time out.
        if method == "PUT" and member == "abortexposure":
            with self.lock:
                self.require_connected()
            self.abort()
            return None
        if method == "PUT" and member == "connected" and "connected" in params:
            if not boolean(params["connected"]):
                with self.lock:
                    self.connected = False
                self.abort()
                return None
        with self.lock:
            def required(key):
                if key not in params:
                    raise CameraError(INVALID_VALUE, "Missing parameter: " + key)
                return params[key]

            common = {
                "name": self.backend.name, "description": self.backend.name,
                "driverinfo": "Experimental Orion ov519 Alpaca bridge; " + VERSION,
                "driverversion": VERSION.rsplit(".", 1)[0], "interfaceversion": 3, "supportedactions": [],
            }
            if method == "GET" and member in common:
                return common[member]
            if member == "connected":
                if method == "GET":
                    return self.connected
                connect = boolean(required("connected"))
                if connect and not self.connected:
                    self.require_idle()
                    try:
                        self.backend.connect()
                    except CameraError:
                        raise
                    except Exception as exc:
                        raise CameraError(DRIVER_ERROR, str(exc)) from exc
                self.connected = connect
                return None
            self.require_connected()
            if method == "PUT":
                if member == "startexposure":
                    boolean(required("light"))  # No mechanical shutter; ignored per ASCOM.
                    self.start(required("duration"))
                    return None
                geometry = {"startx": ("start_x", 0, self.backend.width - 1),
                            "starty": ("start_y", 0, self.backend.height - 1),
                            "numx": ("num_x", 1, self.backend.width),
                            "numy": ("num_y", 1, self.backend.height)}
                if member in geometry:
                    self.require_idle()
                    attr, minimum, maximum = geometry[member]
                    value = integer(required(member))
                    if not minimum <= value <= maximum:
                        raise CameraError(INVALID_VALUE, "Subframe value out of range")
                    # Preserve BGGR alignment for clients using a fixed Bayer pattern.
                    if member in ("startx", "starty") and value % 2:
                        raise CameraError(INVALID_VALUE, "Bayer subframe origins must be even")
                    setattr(self, attr, value)
                    return None
                if member in ("binx", "biny", "readoutmode"):
                    self.require_idle()
                    if integer(required(member)) != (0 if member == "readoutmode" else 1):
                        raise CameraError(INVALID_VALUE, "Only bin 1 and readout mode 0 are supported")
                    return None
                if member == "fastreadout" and not boolean(required(member)):
                    return None
            if method == "GET":
                values = {
                    "cameraxsize": self.backend.width, "cameraysize": self.backend.height,
                    "numx": self.num_x, "numy": self.num_y, "startx": self.start_x, "starty": self.start_y,
                    "binx": 1, "biny": 1, "maxbinx": 1, "maxbiny": 1,
                    "maxadu": 255, "sensortype": 2, "sensorname": "BGGR8 (ov519)",
                    "bayeroffsetx": 1, "bayeroffsety": 1, "hasshutter": False,
                    "canabortexposure": True, "canstopexposure": False,
                    "canasymmetricbin": False, "canfastreadout": False,
                    "cangetcoolerpower": False, "cansetccdtemperature": False,
                    "canpulseguide": False, "ispulseguiding": False, "fastreadout": False,
                    "readoutmodes": ["BGGR8 full sensor"], "readoutmode": 0,
                    "camerastate": self.state, "exposuremin": self.backend.minimum,
                    "exposuremax": self.backend.maximum, "exposureresolution": self.backend.resolution,
                }
                if member in values:
                    return values[member]
                if member in ("pixelsizex", "pixelsizey") and self.backend.pixel_size:
                    return self.backend.pixel_size
                if member == "imageready":
                    if self.error:
                        raise CameraError(DRIVER_ERROR, self.error)
                    return self.image is not None
                if member == "percentcompleted":
                    if self.image is not None:
                        return 100
                    if self.state != 2 or not self.duration:
                        return 0
                    return min(99, int(100 * (time.monotonic() - self.monotonic_start) / self.duration))
                if member in ("lastexposureduration", "lastexposurestarttime"):
                    if member == "lastexposurestarttime" and not self.backend.supports_start_time:
                        raise CameraError(NOT_IMPLEMENTED, "Hardware integration start timestamp is unavailable")
                    self.image_data()
                    return self.duration if member.endswith("duration") else self.started
                if member == "imagearray":
                    raw, (nx, ny) = self.image_data()
                    return [list(raw[x * ny:(x + 1) * ny]) for x in range(nx)]
            raise CameraError(NOT_IMPLEMENTED, member + " is not supported")


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, camera):
        self.camera = camera
        self.transaction = 0
        self.transaction_lock = threading.Lock()
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.handle_request("GET")

    def do_PUT(self):
        self.handle_request("PUT")

    def send_data(self, data, content_type="application/json", status=200):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def handle_request(self, method):
        parsed = urlsplit(self.path)
        path = parsed.path.lower().rstrip("/")
        if method == "GET" and path in ("", "/setup", "/setup/v1/camera/0/setup"):
            body = ("<html><title>Orion Alpaca</title><h1>" + self.server.camera.backend.name +
                    "</h1><p>Experimental bridge. See docs/NINA_SETUP.md in the repository. "
                    "Hardware capture requires a measured exposure profile. "
                    "Close other camera applications before connecting.</p></html>")
            return self.send_data(body.encode(), "text/html; charset=utf-8")
        with self.server.transaction_lock:
            self.server.transaction = self.server.transaction % 4294967295 + 1
            transaction = self.server.transaction
        result = {"ClientTransactionID": 0, "ServerTransactionID": transaction,
                  "ErrorNumber": 0, "ErrorMessage": ""}
        try:
            params = parse_qs(parsed.query, keep_blank_values=True)
            if method == "PUT":
                length = integer(self.headers.get("Content-Length", "0"))
                if not 0 <= length <= 8192:
                    raise CameraError(INVALID_VALUE, "Request body too large")
                params.update(parse_qs(self.rfile.read(length).decode("utf-8"), keep_blank_values=True))
            params = {key.lower(): values[-1] for key, values in params.items()}
            client_transaction = integer(params.get("clienttransactionid", 0))
            if not 0 <= client_transaction <= 4294967295:
                raise CameraError(INVALID_VALUE, "Invalid ClientTransactionID")
            result["ClientTransactionID"] = client_transaction
            if method == "GET" and path == "/management/apiversions":
                value = [1]
            elif method == "GET" and path == "/management/v1/description":
                value = {"ServerName": "Orion Alpaca", "Manufacturer": "Orion community project",
                         "ManufacturerVersion": VERSION, "Location": "Local camera computer"}
            elif method == "GET" and path == "/management/v1/configureddevices":
                value = [{"DeviceName": self.server.camera.backend.name, "DeviceType": "Camera",
                          "DeviceNumber": 0, "UniqueID": "046b625a-92aa-48ca-a05c-" +
                           ("bcb802a44001" if isinstance(self.server.camera.backend, Simulator) else "bcb802a44000")}]
            elif path.startswith("/api/v1/camera/0/"):
                member = path.rsplit("/", 1)[-1]
                camera = self.server.camera
                if method == "GET" and member == "imagearray" and "application/imagebytes" in self.headers.get("Accept", "").lower():
                    with camera.lock:
                        camera.require_connected()
                        raw, (nx, ny) = camera.image_data()
                    header = struct.pack("<iiIIiiiiiii", 1, 0, client_transaction, transaction,
                                         44, 2, 6, 2, nx, ny, 0)
                    return self.send_data(header + raw, "application/imagebytes")
                value = camera.request(method, member, params)
                if member == "imagearray" and method == "GET":
                    result.update(Type=2, Rank=2)
            else:
                return self.send_data(b'{"error":"Unknown Alpaca path"}', status=404)
            if method == "GET":
                result["Value"] = value
        except CameraError as exc:
            result.update(ErrorNumber=exc.number, ErrorMessage=str(exc))
        except (ValueError, UnicodeError) as exc:
            result.update(ErrorNumber=INVALID_VALUE, ErrorMessage=str(exc))
        except Exception as exc:
            result.update(ErrorNumber=DRIVER_ERROR, ErrorMessage=str(exc))
        self.send_data(json.dumps(result, allow_nan=False, separators=(",", ":")).encode())


def discovery(http_port, stop, address="127.0.0.1", port=32227):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            sock.bind((address, port))
        except OSError as exc:
            print("Discovery unavailable; add the HTTP address manually:", exc, flush=True)
            return
        sock.settimeout(0.5)
        while not stop.is_set():
            try:
                packet, peer = sock.recvfrom(512)
                if packet.lower() == b"alpacadiscovery1":
                    sock.sendto(json.dumps({"AlpacaPort": http_port}).encode(), peer)
            except socket.timeout:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulate", action="store_true")
    parser.add_argument("--device", default="/dev/video0")
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--port", type=int, default=11111)
    args = parser.parse_args()
    if args.simulate:
        backend = Simulator()
    else:
        from orion_v4l2 import V4L2
        backend = V4L2(args.device, args.profile)
    camera = Camera(backend)
    server = Server(("127.0.0.1", args.port), camera)
    stop = threading.Event()
    listener = threading.Thread(target=discovery, args=(server.server_port, stop), daemon=True)
    listener.start()
    print(f"{backend.name}: http://127.0.0.1:{server.server_port}/setup", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()
        camera.close()
        listener.join(timeout=1)


if __name__ == "__main__":
    main()
