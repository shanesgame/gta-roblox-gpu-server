"""
Local host for the browser GTA port.

  python serve.py [--port 8765] [--proxy-data]

Serves ./ with COOP/COEP (SharedArrayBuffer). Missing /data/* files are fetched
from the upstream host when --proxy-data is on (default).
"""
from __future__ import annotations

import argparse
import mimetypes
import os
import sys
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UPSTREAM = "https://gta.deloskiyt.pl"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) gta-local-mirror/1.0"


import threading

_ZSTD_LOCK = threading.Lock()
_ZSTD = None


def _zstd_frame(rgba: bytes, drop_bits: int) -> bytes:
    """RGBA -> zstd. drop_bits zeroes the low bits of each colour channel (smaller frames, slight banding)."""
    global _ZSTD
    src = rgba
    if drop_bits > 0:
        import numpy as np

        mask = (0xFF << min(drop_bits, 7)) & 0xFF
        buf = bytearray(rgba)  # single copy; numpy edits it in place
        px = np.frombuffer(buf, np.uint8).reshape(-1, 4)
        px[:, :3] &= mask
        src = buf
    # ZstdCompressor is NOT thread-safe (concurrent use = access violation): one instance, serialized.
    with _ZSTD_LOCK:
        if _ZSTD is None:
            import zstandard

            _ZSTD = zstandard.ZstdCompressor(level=1)
        return _ZSTD.compress(src)


class GameHandler(SimpleHTTPRequestHandler):
    proxy_data = True

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, fmt: str, *args) -> None:
        if args and isinstance(args[0], str):
            p = args[0]
            if p.startswith("GET /data/") or p.startswith("GET /roblox-gpu/") or p.startswith("POST /roblox-gpu/input"):
                return  # quiet hot path
        super().log_message(fmt, *args)

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/log":
            length = int(self.headers.get("Content-Length", 0))
            if length:
                self.rfile.read(length)
            self.send_response(204)
            self.end_headers()
            return
        if path == "/roblox-gpu/input":
            self._roblox_gpu_input()
            return
        self.send_error(404)

    def _roblox_gpu_input(self) -> None:
        import json

        from roblox_gpu.input_bridge import apply_input

        length = int(self.headers.get("Content-Length", 0))
        if length <= 0 or length > 256_000:
            self.send_error(400, "bad body")
            return
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_error(400, "invalid json")
            return
        url = body.get("url")
        events = body.get("events")
        if not isinstance(url, str) or not isinstance(events, list):
            self.send_error(400, "need url and events[]")
            return
        if len(events) > 200:
            events = events[-200:]
        try:
            apply_input(url, events)
        except Exception as e:
            self.send_error(500, str(e))
            return
        payload = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        query = self.path.split("?", 1)[1] if "?" in self.path else ""
        if path == "/roblox-gpu/frame":
            self._roblox_gpu_frame(query)
            return
        if path in ("/roblox-gpu/eval", "/roblox-gpu/reload"):
            self._roblox_gpu_debug(path, query)
            return
        if path.startswith("/roblox-port/") and path.endswith(".lua"):
            rel = path[len("/roblox-port/") :]
            if ".." not in rel and rel.endswith(".lua"):
                lua = ROOT / "roblox-port" / rel.replace("/", os.sep)
                if lua.is_file():
                    data = lua.read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain; charset=utf-8")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
        if (path.startswith("/data/") or path.startswith("/b/")) and GameHandler.proxy_data:
            local = ROOT / path.lstrip("/").replace("/", os.sep)
            if not local.is_file():
                if self._proxy_upstream(local):
                    return
        super().do_GET()

    def do_HEAD(self) -> None:
        # The Roblox loading screen probes the engine files with HEAD; answer from upstream when there is no local mirror.
        path = self.path.split("?", 1)[0]
        if (path.startswith("/data/") or path.startswith("/b/")) and GameHandler.proxy_data:
            local = ROOT / path.lstrip("/").replace("/", os.sep)
            if not local.is_file():
                req = urllib.request.Request(UPSTREAM + path, method="HEAD", headers={"User-Agent": UA})
                try:
                    with urllib.request.urlopen(req, timeout=30) as resp:
                        self.send_response(200)
                        self.send_header("Content-Type", resp.headers.get("Content-Type") or "application/octet-stream")
                        self.send_header("Content-Length", resp.headers.get("Content-Length") or "0")
                        self.end_headers()
                except urllib.error.HTTPError as e:
                    self.send_error(e.code, e.reason)
                except OSError as e:
                    self.send_error(502, str(e))
                return
        super().do_HEAD()

    def _roblox_gpu_debug(self, path: str, query: str) -> None:
        """Local diagnostics: /roblox-gpu/eval?url=&js= runs JS in the game tab; /roblox-gpu/reload restarts the tab."""
        import json
        from urllib.parse import parse_qs

        from roblox_gpu import browser_capture

        q = parse_qs(query)
        try:
            if path == "/roblox-gpu/reload":
                browser_capture.reload_page()
                result = {"ok": True, "reloaded": True}
            else:
                url = q.get("url", [""])[0]
                js = q.get("js", ["1"])[0]
                result = {"ok": True, "value": browser_capture.evaluate_js(url, js)}
        except Exception as e:
            result = {"ok": False, "error": f"{type(e).__name__}: {e}"}
        payload = json.dumps(result, default=str).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _roblox_gpu_frame(self, query: str) -> None:
        from urllib.parse import parse_qs

        from roblox_gpu.render import render_url_to_rgba

        params = parse_qs(query)
        url = (params.get("url") or ["http://127.0.0.1:8765/"])[0]
        try:
            w = int((params.get("w") or ["256"])[0])
            h = int((params.get("h") or ["144"])[0])
            tick = int((params.get("t") or ["0"])[0])
        except ValueError:
            self.send_error(400, "bad w/h/t")
            return
        try:
            rgba, rw, rh = render_url_to_rgba(url, w, h, tick)
        except ValueError as e:
            self.send_error(403, str(e))
            return
        except MemoryError:
            self.send_error(503, "PC out of memory - close other apps (Discord, browser tabs, extra Cursor windows)")
            return
        except Exception as e:
            import traceback

            traceback.print_exc()
            self.send_error(500, str(e)[:200])
            return
        fmt = (params.get("format") or ["raw"])[0].lower()
        if fmt == "zstd":
            try:
                payload = _zstd_frame(rgba, int((params.get("q") or ["0"])[0] or 0))
            except MemoryError:
                self.send_error(503, "PC out of memory - close other apps (Discord, browser tabs, extra Cursor windows)")
                return
            except Exception as e:
                import traceback

                traceback.print_exc()
                self.send_error(500, f"zstd: {e}"[:200])
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("X-Gpu-Width", str(rw))
            self.send_header("X-Gpu-Height", str(rh))
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if fmt in ("b64", "json", "base64"):
            import base64
            import json

            payload = json.dumps(
                {"w": rw, "h": rh, "b64": base64.standard_b64encode(rgba).decode("ascii")}
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("X-Gpu-Width", str(rw))
        self.send_header("X-Gpu-Height", str(rh))
        self.send_header("Content-Length", str(len(rgba)))
        self.end_headers()
        self.wfile.write(rgba)

    def _proxy_upstream(self, local: Path) -> bool:
        url = UPSTREAM + self.path
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
                ctype = (
                    resp.headers.get("Content-Type")
                    or mimetypes.guess_type(local.name)[0]
                    or "application/octet-stream"
                )
        except urllib.error.HTTPError as e:
            self.send_error(e.code, e.reason)
            return True
        except OSError as e:
            self.send_error(502, str(e))
            return True

        local.parent.mkdir(parents=True, exist_ok=True)
        tmp = local.with_suffix(local.suffix + ".part")
        tmp.write_bytes(data)
        tmp.replace(local)
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-proxy-data", action="store_true")
    args = parser.parse_args()
    GameHandler.proxy_data = not args.no_proxy_data

    host = "127.0.0.1"

    class QuietServer(ThreadingHTTPServer):
        daemon_threads = True

        def handle_error(self, request, client_address):
            # The browser cancels/aborts fetches constantly while loading the game; those aren't server errors.
            exc = sys.exc_info()[1]
            if isinstance(exc, (ConnectionResetError, ConnectionAbortedError, BrokenPipeError)):
                return
            if isinstance(exc, MemoryError):
                print(f"[serve] MemoryError serving {client_address} - the PC is out of memory", file=sys.stderr)
                return
            super().handle_error(request, client_address)

    httpd = QuietServer((host, args.port), GameHandler)
    print(f"Serving {ROOT}")
    print(f"Open http://{host}:{args.port}/  (proxy data: {GameHandler.proxy_data})")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        try:  # close the capture browser so it does not linger holding gigabytes of RAM
            from roblox_gpu import browser_capture

            browser_capture.shutdown()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
