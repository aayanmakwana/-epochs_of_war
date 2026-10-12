import http.server
import sys

class CORSHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

print("Serving Epochs of War at http://localhost:8060")
print("Press Ctrl+C to stop")
sys.stdout.flush()
http.server.HTTPServer(("", 8060), CORSHandler).serve_forever()
