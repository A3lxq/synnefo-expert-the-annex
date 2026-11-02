#!/bin/bash
set -euo pipefail

: "${CTF_SECRET:?CTF_SECRET must be set}"
export CTF_SECRET

getflag() { python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$CTF_SECRET', $1))"; }
getsecret() { python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import secret_for; print(secret_for('$CTF_SECRET', '$1'))"; }

F4=$(getflag 4)
F5=$(getflag 5)
FS_PW=$(getsecret fileserver_password)

sed -e "s/FLAG4_PLACEHOLDER/$F4/" \
    -e "s/FLAG5_PLACEHOLDER/$F5/" \
    -e "s/FILESERVER_PASSWORD_PLACEHOLDER/$FS_PW/" \
    /opt/seed.ldif.template > /tmp/seed.ldif

# Loaded offline (slapd not running yet) directly into the OLC-configured
# backend that `apt-get install slapd` already built at image-build time
# from the preseeded debconf answers.
slapadd -F /etc/ldap/slapd.d -b "dc=halcyon,dc=local" -l /tmp/seed.ldif
chown -R openldap:openldap /var/lib/ldap
rm -f /tmp/seed.ldif

echo "[entrypoint] Directory ready."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/ctf.conf
