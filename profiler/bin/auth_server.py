#!/usr/bin/env python3
"""
Minimal HTTP server with HTTP Basic auth, serving the profiler data dir with
directory autoindex so you can click down day -> hour -> flamegraph.

Config via env:
  PROFILER_DIR   directory to serve            (default: .)
  PROFILER_PORT  listen port                   (default: 8400)
  PROFILER_USER  basic-auth username           (default: admin)
  PROFILER_PASS  basic-auth password           (required)
"""
import base64
import hmac
import os
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

USER = os.environ.get("PROFILER_USER", "charm")
PASS = os.environ.get("PROFILER_PASS")
if not PASS:
    sys.exit("PROFILER_PASS not set")

EXPECTED = "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode()


class AuthHandler(SimpleHTTPRequestHandler):
    # The port is public: a client that connects and never sends a request
    # line must not hold a handler thread forever.
    timeout = 30

    def _authorized(self):
        got = self.headers.get("Authorization", "")
        return hmac.compare_digest(got, EXPECTED)

    def _deny(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="profiler"')
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if not self._authorized():
            return self._deny()
        return super().do_GET()

    def do_HEAD(self):
        if not self._authorized():
            return self._deny()
        return super().do_HEAD()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    port = int(os.environ.get("PROFILER_PORT", "8400"))
    directory = os.environ.get("PROFILER_DIR", ".")
    handler = partial(AuthHandler, directory=directory)
    # Threaded so one slow or stuck connection cannot block every other request.
    httpd = ThreadingHTTPServer(("0.0.0.0", port), handler)
    print(f"Serving {directory} on :{port}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
