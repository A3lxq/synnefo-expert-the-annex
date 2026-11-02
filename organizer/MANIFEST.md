# Organizer manifest — The Annex (Expert)

Keep this file (and this whole `organizer/` directory) off any
player-facing host. Flag *values* are never written here — re-derive them
from the deployment's `CTF_SECRET` (HMAC-SHA256("expert-the-annex:N",
secret), first 10 hex chars, wrapped `HLC{...}`). Non-flag derived
secrets use `secret:<label>`, first 20 hex chars (see
`docker/generate_flags.py`).

Three hosts: **Gateway** (published), **Directory** (an OpenLDAP server,
internal-only), **Fileserver** (SSH, internal-only). Only Gateway has any
published port — the other two are reachable exclusively by pivoting
through a shell/RCE on Gateway.

| # | Host | Difficulty | Concept taught | Primary tool(s) | Where it lives |
|---|---|---|---|---|---|
| 1 | Gateway | Easy | Reading page source | curl/browser | HTML comment on `/` |
| 2 | Gateway | Easy | Default/weak credentials | curl/browser | `annex_staff`/`welcome2024` on `/login` |
| 3 | Gateway | Medium/Hard | Server-Side Template Injection (Jinja2) -> RCE | hand-crafted `{{ }}` sandbox-escape payload | `/welcome?name=...` |
| 4 | Directory | Medium | LDAP anonymous-bind enumeration | `ldapsearch -x`, via the pivot | `ou=people,dc=halcyon,dc=local` |
| 5 | Directory | Medium | Same enumeration, a second entry discloses real creds | `ldapsearch -x` | `cn=svc-fileserver` entry's `description` |
| 6 | Fileserver | Easy (once pivoted) | Reading an SSH pre-auth banner | `ssh` (banner shown before login) | `/etc/issue.net` |
| 7 | Fileserver | Medium | Credential reuse (creds disclosed via LDAP) | `ssh`/`sshpass`, via the pivot | `ops`'s home directory |
| 8 | Fileserver | Hard | World-writable `/etc/passwd` privilege escalation | manual enumeration (`ls -la /etc/passwd`), append a UID-0 account | `/root/flag8.txt` |
| 9 | Fileserver | Hard | Reading a forensic log for a story payoff + the final passphrase | `cat` once root | `/root/audit.log` |
| 10 | Fileserver | Capstone | Decrypting the final artifact with a recovered passphrase | `flagcrypto.py` (ships to players) | `/root/dossier.enc` |

## Honeypots (never flag-shaped, cost time only)
- Gateway `/admin` — a plausible path, 501, nothing behind it.
- Directory `cn=legacy-vpn` entry — a real, anonymously-readable LDAP
  entry with explicitly inert decoy credentials.

## Fixed design constants (intentional, not secret-derived)
- Gateway's SSTI sandbox-escape payload (give players room to find this
  themselves rather than spoiling it here — see `docs/writeup/WRITEUP.md`
  for the exact string used to verify this box).
- LDAP: anonymous bind is Debian slapd's own shipped default (this box
  does not touch ACLs at all) — `userPassword` stays protected by
  default; the "vulnerability" is that real secrets were put in an
  anonymously-readable attribute (`description`) instead.
- `ops`'s Fileserver password: disclosed only via the LDAP
  `svc-fileserver` entry (`secret_for(..., "fileserver_password")`).
- Privesc: `chmod 666 /etc/passwd` on Fileserver (a real-world-plausible
  broken permissions-fixing script).
- Final dossier passphrase: disclosed only via `/root/audit.log`, once root
  (`secret_for(..., "dossier_password")`).
- `docker-compose.yml`'s `internal-net` has `internal: true` — neither
  Directory nor Fileserver has any route to the internet, not just no
  published ports.

## Build notes (so a rebuild doesn't rediscover these)
- Directory's `Dockerfile` preseeds `slapd`'s debconf questions BEFORE
  installing the package, so its postinst generates a real OLC
  (`cn=config`) tree + MDB database non-interactively — the standard,
  correct way to script an OpenLDAP install, not a hand-rolled config.
- Flags 4/5 are loaded offline via `slapadd` (not `ldapadd` against a
  running `slapd`) at container start, then ownership is fixed
  (`chown -R openldap:openldap /var/lib/ldap`) before `slapd` itself starts.
