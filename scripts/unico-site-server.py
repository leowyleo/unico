#!/usr/bin/env python3
"""Serve Unico's small public support site without a third-party framework."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SITE_ROOT = PROJECT_ROOT / "docs" / "site"


class UnicoHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(SITE_ROOT), **kwargs)

    def do_GET(self):  # noqa: N802 - required by BaseHTTPRequestHandler
        path = urlsplit(self.path).path.rstrip("/") or "/"
        routes = {
            "/privacy": "/en/privacy/index.html",
            "/support": "/en/support/index.html",
            "/zh": "/zh/index.html",
            "/zh/privacy": "/zh/privacy/index.html",
            "/zh/support": "/zh/support/index.html",
        }
        if path in routes:
            self.path = routes[path]
        super().do_GET()


def main():
    host = "127.0.0.1"
    port = 3021
    server = ThreadingHTTPServer((host, port), UnicoHandler)
    print(f"Unico site listening on http://{host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
