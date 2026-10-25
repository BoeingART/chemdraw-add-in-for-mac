# SPDX-License-Identifier: Apache-2.0
"""Loopback-only HTTPS task pane. All mutations join the bridge's serial queue."""
import concurrent.futures
import hmac
import json
import secrets
import ssl
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 17524
ORIGIN = f'https://localhost:{PORT}'


def start_office_ui(root: Path, bridge, events, port=PORT):
    tls = root / 'work/tls'
    if not (tls/'localhost.pem').exists() or not (tls/'localhost-key.pem').exists():
        return None
    token = secrets.token_urlsafe(32)
    static = root/'office/addin'

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass

        def send(self, status, data, content_type='application/json'):
            if isinstance(data, dict): data = json.dumps(data).encode()
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.end_headers()
            self.wfile.write(data)

        def allowed_host(self):
            return self.headers.get('Host') in (f'localhost:{self.server.server_port}', f'127.0.0.1:{self.server.server_port}')

        def do_GET(self):
            if not self.allowed_host(): return self.send(403, {'error':'Invalid local host'})
            path = self.path.split('?',1)[0]
            if path == '/api/status':
                return self.send(200, {'ready':True, 'editing':bool(bridge.session)})
            routes = {'/':'taskpane.html','/taskpane.html':'taskpane.html','/help':'taskpane.html',
                      '/taskpane.js':'taskpane.js','/style.css':'style.css'}
            if path.startswith('/icon-') and path in ('/icon-16.png','/icon-32.png','/icon-80.png'):
                routes[path] = path[1:]
            filename = routes.get(path)
            if not filename: return self.send(404, {'error':'Not found'})
            data = (static/filename).read_bytes()
            if filename.endswith('.html'): data = data.replace(b'__CFM_TOKEN__', token.encode())
            kind = 'text/html; charset=utf-8' if filename.endswith('.html') else 'text/javascript; charset=utf-8' if filename.endswith('.js') else 'text/css' if filename.endswith('.css') else 'image/png'
            self.send(200, data, kind)

        def do_POST(self):
            if not self.allowed_host() or self.path != '/api/edit':
                return self.send(403, {'error':'Invalid local request'})
            origin = f'https://localhost:{self.server.server_port}'
            if self.headers.get('Origin',origin) != origin or not hmac.compare_digest(self.headers.get('X-ChemOffice-Token',''),token):
                return self.send(403, {'error':'Open this action from the ChemOffice panel'})
            try:
                length = int(self.headers.get('Content-Length','0'))
                if not 0 < length <= 128: raise ValueError('Invalid request')
                body = json.loads(self.rfile.read(length))
                if body.get('host') not in ('word','powerpoint'): raise ValueError('Select a drawing in Word or PowerPoint')
                future = concurrent.futures.Future()
                events.put(({'event':'edit-selection','host':body['host']}, future))
                future.result(timeout=100)
                self.send(200, {'opened':True})
            except Exception as error:
                self.send(400, {'error':str(error) or 'The drawing could not be opened'})

    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(tls/'localhost.pem', tls/'localhost-key.pem')
    server.socket = context.wrap_socket(server.socket, server_side=True)
    threading.Thread(target=server.serve_forever, daemon=True, name='ChemOffice panel').start()
    return server
