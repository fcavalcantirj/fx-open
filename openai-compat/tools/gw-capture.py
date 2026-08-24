#!/usr/bin/env python3
"""Loopback HTTP listener to capture any requests fx sends to a gateway URL."""
import http.server, sys

port = int(sys.argv[1])
logpath = sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def _capture(self, method):
        length = int(self.headers.get('Content-Length', 0) or 0)
        body = self.rfile.read(length) if length > 0 else b''
        auth = 'yes' if self.headers.get('Authorization') else 'no'
        with open(logpath, 'a') as f:
            f.write(f'{method} {self.path} auth={auth}\n')
        self.send_response(500)
        self.end_headers()
        self.wfile.write(b'{}')
    def do_GET(self): self._capture('GET')
    def do_POST(self): self._capture('POST')
    def do_PUT(self): self._capture('PUT')
    def do_DELETE(self): self._capture('DELETE')
    def do_PATCH(self): self._capture('PATCH')
    def log_message(self, *a): pass

http.server.HTTPServer(('127.0.0.1', port), Handler).serve_forever()
