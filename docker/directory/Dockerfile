FROM debian:12-slim

# Non-interactively preseed slapd's debconf questions BEFORE installing
# it, so the package's own postinst generates a real cn=config (OLC)
# tree and database for us -- same mechanism a real sysadmin's unattended
# install would use, not a hand-rolled fake.
ARG LDAP_ADMIN_PASSWORD=DirAdmin2024!
RUN apt-get update -qq && apt-get install -y --no-install-recommends -qq debconf-utils \
    && debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/domain string halcyon.local
slapd shared/organization string Halcyon Dynamics
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
slapd slapd/backend select MDB
EOF
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -qq \
        slapd ldap-utils supervisor python3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/supervisor /opt/shared /run/slapd && chown openldap:openldap /run/slapd

COPY docker/generate_flags.py /opt/shared/generate_flags.py
COPY docker/directory/entrypoint.sh /opt/entrypoint.sh
COPY docker/directory/supervisord.conf /etc/supervisor/conf.d/ctf.conf
COPY docker/directory/seed.ldif.template /opt/seed.ldif.template
RUN chmod +x /opt/entrypoint.sh

EXPOSE 389
# Never published in docker-compose.yml -- internal-only on purpose.

ENTRYPOINT ["/opt/entrypoint.sh"]
