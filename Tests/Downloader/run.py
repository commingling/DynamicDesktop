#!/usr/bin/env python3
"""Run downloader integration tests against a local server and temporary files."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            (Path(directory) / "slow-started").touch()
            time.sleep(0.8)
            body, status = b"old video", 200
        elif self.path == "/success":
            body, status = b"new video", 200
        else:
            body, status = b"not found", 404
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        pass


with tempfile.TemporaryDirectory(prefix="dynamicdesktop-test-") as directory:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        executable = Path(directory) / "downloader-tests"
        subprocess.run(["swiftc", str(ROOT / "Sources/WallpaperDownloader.swift"),
                        str(ROOT / "Tests/Downloader/main.swift"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), f"http://127.0.0.1:{server.server_port}/", directory], check=True)
    finally:
        server.shutdown()
        server.server_close()
