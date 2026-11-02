#!/bin/bash
set -euo pipefail

: "${CTF_SECRET:?CTF_SECRET must be set}"
export CTF_SECRET

mkdir -p /var/log/supervisor /opt/gateway/secret

getflag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$CTF_SECRET', $1))"; }

# Reachable only via the SSTI RCE in /welcome -- not web-exposed directly.
getflag 3 > /opt/gateway/secret/flag3.txt
chown web:web /opt/gateway/secret/flag3.txt
chmod 600 /opt/gateway/secret/flag3.txt

echo "[entrypoint] Gateway ready."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/ctf.conf
