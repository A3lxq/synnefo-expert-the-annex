# Tools you'll use in this box

| Tool | What it's for here |
|---|---|
| curl / browser | Recon, login, triggering the SSTI payload. |
| Jinja2 SSTI payloads | `/welcome?name=...` renders your input as a template, not a variable — escalate from a math-expression proof (`{{7*7}}`) to a sandbox-escape RCE payload. |
| `ldapsearch -x` | Anonymous-bind enumeration of the internal directory service, run through your RCE on Gateway (it can't reach you directly — you have to reach it). |
| `ssh` / `sshpass` | Log into the file server once you have real credentials, again from inside your RCE session. |
| Manual enumeration (`ls -la /etc/passwd`) | Spot the world-writable `/etc/passwd` misconfiguration. |
| `docker/flagcrypto.py` (ships with this repo) | Decrypt the final dossier once you have its passphrase. |
