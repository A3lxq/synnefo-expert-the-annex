FROM debian:12-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends -qq \
        python3 python3-venv python3-pip supervisor \
        ldap-utils curl openssh-client sshpass \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/supervisor /opt/shared

RUN python3 -m venv /opt/venv
COPY docker/gateway/requirements.txt /opt/app/requirements.txt
RUN /opt/venv/bin/pip install -q --no-cache-dir --retries 10 --timeout 120 \
        -r /opt/app/requirements.txt

COPY docker/generate_flags.py /opt/shared/generate_flags.py
COPY docker/gateway/app.py /opt/app/app.py
COPY docker/gateway/entrypoint.sh /opt/entrypoint.sh
COPY docker/gateway/supervisord.conf /etc/supervisor/conf.d/ctf.conf
RUN chmod +x /opt/entrypoint.sh

# The app (and anything the SSTI RCE runs) executes as this unprivileged
# account -- ldap-utils is installed here specifically so the intended
# path (ldapsearch against the internal directory service) works once
# you have code execution.
RUN useradd -m -s /bin/bash web

EXPOSE 5000

ENTRYPOINT ["/opt/entrypoint.sh"]
