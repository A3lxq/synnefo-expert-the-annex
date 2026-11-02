"""
The Annex — gateway. Flask, port 5000 (published). INTENTIONALLY
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
    # Honeypot: a plausible path, nothing behind it.
    return Response("Not implemented yet.\n", status=501)


@app.route("/welcome", methods=["GET", "POST"])
def welcome():
    name = request.args.get("name") or request.form.get("name") or "Guest"
    # INTENTIONALLY VULNERABLE: user input rendered as a TEMPLATE, not a
    # variable. Classic Jinja2 SSTI -> RCE via sandbox escape.
    try:
        rendered = render_template_string(f"<p>Hello, {name}!</p>")
        return Response(rendered, mimetype="text/html")
    except Exception as e:
        return Response(f"Render error: {e}\n", status=400, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
