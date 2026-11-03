#!/usr/bin/env bash
# remote-provision-fileserver.sh — deploys the Fileserver host of the
# Expert (The Annex) CTF box onto an already-booted Ubuntu 24.04
# guest (run over SSH as ctfbuilder, with sudo). Native build: real
# openssh-server, a world-writable /etc/passwd privesc, final dossier
# decrypt. No Docker anywhere. Public, so never hardcode the release
# secret here -- it must only ever arrive via the SSH session's own
# environment.
set -euo pipefail

: "${RELEASE_SECRET:?RELEASE_SECRET must be passed in (never hardcode it here -- this script is public)}"

echo "== Fileserver: packages & venv =="
sudo apt-get install -y -qq python3-venv >/dev/null 2>&1 || true
sudo python3 -m venv /opt/venv
sudo /opt/venv/bin/pip install -q --no-cache-dir cryptography==43.0.3

sudo mkdir -p /opt/shared

echo "== Fileserver: shared flag/crypto modules =="
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

sudo tee /opt/shared/flagcrypto.py >/dev/null <<'EOF'
#!/usr/bin/env python3
"""
flagcrypto.py -- ships to players unchanged. scrypt for password-based
key derivation, AES-256-GCM for authenticated encryption.

File format (binary): b"HLCX1" + 16-byte salt + 12-byte nonce + ciphertext||tag
"""
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b"HLCX1"
SALT_LEN = 16
NONCE_LEN = 12
KEY_LEN = 32


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    kdf = Scrypt(salt=salt, length=KEY_LEN, n=2**14, r=8, p=1)
    return kdf.derive(passphrase.encode("utf-8"))


def encrypt_bytes(passphrase: str, plaintext: bytes) -> bytes:
    import os
    salt = os.urandom(SALT_LEN)
    nonce = os.urandom(NONCE_LEN)
    key = _derive_key(passphrase, salt)
    ct = AESGCM(key).encrypt(nonce, plaintext, None)
    return MAGIC + salt + nonce + ct


def decrypt_bytes(passphrase: str, blob: bytes) -> bytes:
    if not blob.startswith(MAGIC):
        raise ValueError("Not a recognized flagcrypto file (bad magic).")
    rest = blob[len(MAGIC):]
    salt, nonce, ct = rest[:SALT_LEN], rest[SALT_LEN:SALT_LEN + NONCE_LEN], rest[SALT_LEN + NONCE_LEN:]
    key = _derive_key(passphrase, salt)
    return AESGCM(key).decrypt(nonce, ct, None)


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[1] not in ("encrypt", "decrypt"):
        print(__doc__)
        sys.exit(1)
    mode, passphrase, infile, outfile = sys.argv[1:5]
    with open(infile, "rb") as f:
        data = f.read()
    result = encrypt_bytes(passphrase, data) if mode == "encrypt" else decrypt_bytes(passphrase, data)
    if outfile == "-":
        sys.stdout.buffer.write(result)
    else:
        with open(outfile, "wb") as f:
            f.write(result)
EOF

getflag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$RELEASE_SECRET', $1))"; }
getsecret() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import secret_for; print(secret_for('$RELEASE_SECRET', '$1'))"; }

OPS_PASSWORD=$(getsecret fileserver_password)   # same value the directory service discloses

echo "== Fileserver: pre-auth SSH banner (flag6, pure recon) =="
F6=$(getflag 6)
sudo tee /etc/issue.net >/dev/null <<EOF
Halcyon Dynamics -- Annex Fileserver
Authorized access only. Reference: $F6
EOF
grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config || echo "Banner /etc/issue.net" | sudo tee -a /etc/ssh/sshd_config >/dev/null

echo "== Fileserver: ops account + flag7 =="
if ! id ops >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash ops
fi
echo "ops:$OPS_PASSWORD" | sudo chpasswd
getflag 7 | sudo tee /home/ops/flag7.txt >/dev/null
sudo chown ops:ops /home/ops/flag7.txt
sudo chmod 600 /home/ops/flag7.txt

sudo tee /etc/ssh/sshd_config.d/90-ops-password-auth.conf >/dev/null <<'EOF'
Match User ops
    PasswordAuthentication yes
EOF

echo "== Fileserver: INTENTIONALLY VULNERABLE world-writable /etc/passwd (Stage 8) =="
sudo chmod 666 /etc/passwd

echo "== Fileserver: root-only evidence, reachable only after that privesc =="
getflag 8 | sudo tee /root/flag8.txt >/dev/null
DOSSIER_PW=$(getsecret dossier_password)
F9=$(getflag 9)
sudo tee /root/audit.log >/dev/null <<EOF
2024-03-11 02:14:07 session opened for priya.okonkwo-reyes (annex-fileserver)
2024-03-11 02:19:51 priya.okonkwo-reyes: encrypted dossier.enc with recovery
    passphrase "$DOSSIER_PW" per emergency-access policy -- logged here only
    because the ticketing system was down that night.
2024-03-11 02:22:03 session closed -- account disabled by IT the next morning
note left by whoever reviewed this log afterward: $F9
EOF
sudo chmod 600 /root/flag8.txt /root/audit.log

F10=$(getflag 10)
echo -n "$F10" > /tmp/flag10_plain.txt
/opt/venv/bin/python3 /opt/shared/flagcrypto.py encrypt "$DOSSIER_PW" /tmp/flag10_plain.txt /tmp/dossier.enc
rm -f /tmp/flag10_plain.txt
sudo mv /tmp/dossier.enc /root/dossier.enc
sudo chmod 600 /root/dossier.enc

echo "== Fileserver: restart sshd (clean, no orphaned listeners) =="
sudo pkill -9 -f 'sshd: /usr/sbin/sshd -D \[listener\]' 2>/dev/null || true
sleep 1
sudo systemctl restart ssh

echo "[remote-provision-fileserver] Fileserver ready."
