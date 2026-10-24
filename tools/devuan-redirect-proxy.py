#!/usr/bin/env python3
# Local pass-through for packages.devuan.org that follows redirects (curl-style),
# because apt's https method stalls on the sandbox egress proxy for the
# deb.debian.org redirect target. Spike-only workaround.
import subprocess, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
UP = "https://packages.devuan.org"
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def do_GET(self):
        url = UP + self.path
        p = subprocess.Popen(["curl","-sS","-L","--fail","--retry","5","--retry-all-errors","--connect-timeout","15","--max-time","300","-D","-","-o","-" if False else "/dev/stdout",url],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # simpler: buffer whole response (files are small enough)
        data, err = p.communicate()
        # strip header blocks (last header block precedes body)
        body = data
        status = 200
        while body.startswith(b"HTTP/"):
            i = body.find(b"\r\n\r\n")
            if i < 0: break
            hdr = body[:i].split(b"\r\n")[0]
            try: status = int(hdr.split()[1])
            except Exception: pass
            body = body[i+4:]
        if p.returncode != 0:
            self.send_response(404 if b"404" in err else 502); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_HEAD(self):
        p = subprocess.run(["curl","-sS","-L","-I","--fail","--max-time","60",UP+self.path],capture_output=True)
        self.send_response(200 if p.returncode==0 else 404)
        self.end_headers()
    def log_message(self,*a): pass
ThreadingHTTPServer(("127.0.0.1",8099),H).serve_forever()
