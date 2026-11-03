#!/usr/bin/env bash
# remote-provision-gateway.sh — deploys the Gateway host of the
# Expert (The Annex) CTF box onto an already-booted Ubuntu 24.04
# guest (run over SSH as ctfbuilder, with sudo). Native build: real
# Flask app via systemd, running as an unprivileged account (the SSTI
# RCE below executes as this same account). No Docker anywhere.
# Public, so never hardcode the release secret here -- it must only
# ever arrive via the SSH session's own environment.
set -euo pipefail

: "${RELEASE_SECRET:?RELEASE_SECRET must be passed in (never hardcode it here -- this script is public)}"

echo "== Gateway: packages & venv =="
sudo apt-get install -y -qq python3-venv >/dev/null 2>&1 || true
sudo python3 -m venv /opt/venv
sudo /opt/venv/bin/pip install -q --no-cache-dir flask==3.1.0

sudo mkdir -p /opt/shared /opt/app /opt/gateway/secret

echo "== Gateway: shared flag module =="
sudo tee /opt/shared/generate_flags.py >/dev/null <<'EOF'
import hmac
import hashlib

BOX_ID = "expert-the-annex"


def flag_for(secret: str, n: int) -> str:
    digest = hmac.new(secret.encode(), f"{BOX_ID}:{n}".encode(), hashlib.sha256).hexdigest()
    return f"HLC{{{digest[:10]}}}"


def secret_for(secret: str, label: str) -> str:
    digest = hmac.new(secret.encode(), f"{BOX_ID}:secret:{label}".encode(), hashlib.sha256).hexdigest()
    return digest[:20]
EOF

getflag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$RELEASE_SECRET', $1))"; }

echo "== Gateway: app.py =="
sudo tee /opt/app/app.py >/dev/null <<'PYEOF'
"""
The Annex -- gateway. Flask, port 5000 (published). INTENTIONALLY
VULNERABLE: Server-Side Template Injection in /welcome (user input is
passed straight into render_template_string, not as a variable).
"""
import os
import sys

from flask import Flask, request, Response, render_template_string

sys.path.insert(0, "/opt/shared")
from generate_flags import flag_for  # noqa: E402

SECRET = os.environ["CTF_SECRET"]
app = Flask(__name__)


def flag(n):
    return flag_for(SECRET, n)


@app.route("/")
def index():
    return f"""<!DOCTYPE html><html><head><title>The Annex</title></head><body>
    <!-- {flag(1)} -->
    <h1>Halcyon Dynamics — The Annex</h1>
    <p>Departmental portal. See <a href="/login">staff login</a> or
    <a href="/welcome">customize your welcome message</a>.</p>
    </body></html>"""


@app.route("/login", methods=["GET", "POST"])
def login():
    error = ""
    if request.method == "POST":
        if request.form.get("username") == "annex_staff" and request.form.get("password") == "welcome2024":
            return f"<h2>Welcome.</h2><p>{flag(2)}</p>"
        error = "Invalid credentials."
    return f"""<!DOCTYPE html><html><body><h2>Staff Login</h2>
    <p style="color:red">{error}</p>
    <form method="post">
      Username: <input name="username"><br>
      Password: <input name="password" type="password"><br>
      <button type="submit">Log in</button>
    </form></body></html>"""


@app.route("/admin")
def admin_decoy():
    return Response("Not implemented yet.\n", status=501)


@app.route("/welcome", methods=["GET", "POST"])
def welcome():
    name = request.args.get("name") or request.form.get("name") or "Guest"
    try:
        rendered = render_template_string(f"<p>Hello, {name}!</p>")
        return Response(rendered, mimetype="text/html")
    except Exception as e:
        return Response(f"Render error: {e}\n", status=400, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYEOF

echo "== Gateway: unprivileged 'web' account (app + SSTI RCE run as this) =="
if ! id web >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash web
fi

echo "== Gateway: systemd service (runs as web, not root) =="
sudo tee /etc/systemd/system/gateway-app.service >/dev/null <<EOF
[Unit]
Description=Gateway Flask app
After=network.target

[Service]
User=web
Environment=CTF_SECRET=$RELEASE_SECRET
ExecStart=/opt/venv/bin/python3 /opt/app/app.py
WorkingDirectory=/opt/app
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now gateway-app.service

echo "== Gateway: secret reachable only via the SSTI RCE =="
getflag 3 | sudo tee /opt/gateway/secret/flag3.txt >/dev/null
sudo chown web:web /opt/gateway/secret/flag3.txt
sudo chmod 600 /opt/gateway/secret/flag3.txt

echo "== Gateway: /etc/hosts entries for the internal links =="
if ! grep -q '^10\.10\.20\.2 directory' /etc/hosts; then
  echo "10.10.20.2 directory" | sudo tee -a /etc/hosts >/dev/null
fi
if ! grep -q '^10\.10\.30\.2 fileserver' /etc/hosts; then
  echo "10.10.30.2 fileserver" | sudo tee -a /etc/hosts >/dev/null
fi

echo "== Gateway: restart sshd (clean, no orphaned listeners) =="
sudo pkill -9 -f 'sshd: /usr/sbin/sshd -D \[listener\]' 2>/dev/null || true
sleep 1
sudo systemctl restart ssh

echo "[remote-provision-gateway] Gateway ready."
