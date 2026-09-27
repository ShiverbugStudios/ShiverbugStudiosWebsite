"""Serve the site locally the way GitHub Pages does.

    python tools/serve.py [port]

/out-of-water finds out-of-water.html, /team/ finds team/index.html, and a
missing path gets 404.html with a 404 status. The folders _config.yml keeps
off the published site are refused here too, so a link into them fails
locally rather than in production.
"""

import http.server
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ("source", "src", "data", "tools", ".github", ".claude", ".git")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def send_head(self):
        path = self.path.split("?", 1)[0].split("#", 1)[0]
        first = path.lstrip("/").split("/", 1)[0]
        if first in PRIVATE or first.startswith("_"):
            return self.not_found()
        local = Path(self.translate_path(path))
        if not local.exists() and not path.endswith("/") and local.with_suffix(".html").is_file():
            self.path = path + ".html"
        elif local.is_dir() and not (local / "index.html").is_file():
            return self.not_found()
        elif not local.exists():
            return self.not_found()
        return super().send_head()

    def not_found(self):
        body = (ROOT / "404.html").read_bytes()
        self.send_response(404)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        return None

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


Handler.extensions_map.update({".webp": "image/webp", ".woff2": "font/woff2", ".mp4": "video/mp4", ".svg": "image/svg+xml"})

if __name__ == "__main__":
    port = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PORT", 5173))
    print(f"Serving {ROOT} at http://localhost:{port}/")
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
