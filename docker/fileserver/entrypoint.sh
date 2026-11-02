#!/bin/bash
set -euo pipefail

: "${CTF_SECRET:?CTF_SECRET must be set}"
export CTF_SECRET

VENV=/opt/venv
getflag() { $VENV/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$CTF_SECRET', $1))"; }
getsecret() { $VENV/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import secret_for; print(secret_for('$CTF_SECRET', '$1'))"; }

OPS_PASSWORD=$(getsecret fileserver_password)   # same value the directory service discloses

mkdir -p /var/log/supervisor

# --- flag6: pre-auth SSH banner (shown before login, pure recon) ----------
F6=$(getflag 6)
cat > /etc/issue.net <<EOF
Halcyon Dynamics -- Annex Fileserver
Authorized access only. Reference: $F6
EOF
grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config || echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config

# --- ops account + flag7 ----------------------------------------------------
echo "ops:$OPS_PASSWORD" | chpasswd
getflag 7 > /home/ops/flag7.txt
chown ops:ops /home/ops/flag7.txt
chmod 600 /home/ops/flag7.txt

# --- INTENTIONALLY VULNERABLE: world-writable /etc/passwd (Stage 8) -------
# A genuinely common real-world misconfiguration (e.g. a broken
# permissions-fixing script). Lets `ops` add a new root-equivalent
# account by simply appending a line.
chmod 666 /etc/passwd

# --- root-only evidence, reachable only after that privesc -----------------
getflag 8 > /root/flag8.txt
DOSSIER_PW=$(getsecret dossier_password)
cat > /root/audit.log <<EOF
2024-03-11 02:14:07 session opened for priya.okonkwo-reyes (annex-fileserver)
2024-03-11 02:19:51 priya.okonkwo-reyes: encrypted dossier.enc with recovery
    passphrase "$DOSSIER_PW" per emergency-access policy -- logged here only
    because the ticketing system was down that night.
2024-03-11 02:22:03 session closed -- account disabled by IT the next morning
EOF
echo "note left by whoever reviewed this log afterward: $(getflag 9)" >> /root/audit.log
chmod 600 /root/flag8.txt /root/audit.log

F10=$(getflag 10)
echo -n "$F10" > /tmp/flag10_plain.txt
$VENV/bin/python3 /opt/shared/flagcrypto.py encrypt "$DOSSIER_PW" /tmp/flag10_plain.txt /root/dossier.enc
rm -f /tmp/flag10_plain.txt
chmod 600 /root/dossier.enc

ssh-keygen -A >/dev/null 2>&1 || true

echo "[entrypoint] Fileserver ready."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/ctf.conf
