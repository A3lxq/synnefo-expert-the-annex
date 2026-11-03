#!/usr/bin/env bash
# remote-provision-directory.sh — deploys the Directory host of the
# Expert (The Annex) CTF box onto an already-booted Ubuntu 24.04
# guest (run over SSH as ctfbuilder, with sudo). Real OpenLDAP
# (slapd), preseeded non-interactively via debconf BEFORE install, so
# the package's own postinst builds a real cn=config (OLC) tree --
# same mechanism a real sysadmin's unattended install would use, not
# a hand-rolled fake. No Docker anywhere. Public, so never hardcode
# the release secret here -- it must only ever arrive via the SSH
# session's own environment.
set -euo pipefail

: "${RELEASE_SECRET:?RELEASE_SECRET must be passed in (never hardcode it here -- this script is public)}"

LDAP_ADMIN_PASSWORD="DirAdmin2024!"

echo "== Directory: preseed debconf, then install slapd =="
sudo debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password $LDAP_ADMIN_PASSWORD
slapd slapd/internal/adminpw password $LDAP_ADMIN_PASSWORD
slapd slapd/password1 password $LDAP_ADMIN_PASSWORD
slapd slapd/password2 password $LDAP_ADMIN_PASSWORD
slapd slapd/domain string halcyon.local
slapd shared/organization string Halcyon Dynamics
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
slapd slapd/backend select MDB
EOF
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq slapd ldap-utils >/dev/null

sudo mkdir -p /opt/shared

echo "== Directory: shared flag module =="
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

getflag() { python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$RELEASE_SECRET', $1))"; }
getsecret() { python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import secret_for; print(secret_for('$RELEASE_SECRET', '$1'))"; }

F4=$(getflag 4)
F5=$(getflag 5)
FS_PW=$(getsecret fileserver_password)

echo "== Directory: seeding LDAP entries =="
cat > /tmp/seed.ldif <<EOF
dn: ou=people,dc=halcyon,dc=local
objectClass: organizationalUnit
ou: people

dn: cn=branch-note,ou=people,dc=halcyon,dc=local
objectClass: organizationalRole
cn: branch-note
description: $F4

dn: cn=svc-fileserver,ou=people,dc=halcyon,dc=local
objectClass: organizationalRole
cn: svc-fileserver
description: $F5 -- fileserver account ops / $FS_PW

dn: cn=legacy-vpn,ou=people,dc=halcyon,dc=local
objectClass: organizationalRole
cn: legacy-vpn
description: decommissioned 2021, credentials below genuinely don't work anywhere -- vpn_svc / Tunnel-Legacy-04
EOF

sudo systemctl stop slapd
sudo slapadd -F /etc/ldap/slapd.d -b "dc=halcyon,dc=local" -l /tmp/seed.ldif
sudo chown -R openldap:openldap /var/lib/ldap
rm -f /tmp/seed.ldif
sudo systemctl start slapd

echo "== Directory: allow slapd to listen on the internal link, not just loopback =="
sudo sed -i 's|^SLAPD_SERVICES=.*|SLAPD_SERVICES="ldap:/// ldapi:///"|' /etc/default/slapd 2>/dev/null || true
sudo systemctl restart slapd

echo "[remote-provision-directory] Directory ready."
