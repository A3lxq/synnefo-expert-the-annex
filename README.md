# Case File 5 (Expert) — The Annex

Part of **The Halcyon Protocol** CTF series. This box stands alone — you do
not need any other box in the series to play it.

> See [`STORY.md`](STORY.md) for the full case file.

## What this is

**Three hosts**: a public Gateway, and two internal-only systems reachable
only by pivoting through it — a small directory service (LDAP) and a
file server (SSH). 10 flags, no decoys, split across all three. The
first two are easy; everything else requires escalating from a web bug
to real remote code execution, then using that foothold to enumerate and
attack systems your own machine can never reach directly.

**This machine is intentionally vulnerable. Run it only on an isolated
network.**

## Requirements

- Docker + Docker Compose
- A player machine with: `curl`, a browser, basic familiarity with
  Server-Side Template Injection payloads (Jinja2), `ldapsearch` (handy
  to have locally too, though the intended path runs it through the
  pivot), an SSH client

## Starting the box

```
./start.sh
```
Generates a fresh `.env` with a random per-deployment secret and brings
all three containers up.

- Gateway: http://localhost:8005
- Directory and Fileserver: **not reachable from your host at all** —
  that's intentional, and part of the challenge.

## Flag format

`HLC{xxxxxxxxxx}` — submit exactly as found.

## Rules

- No decoy flags: everything matching the flag format is real and counts.
- Some things in this box are honeypots — red herrings that cost you time,
  not flags.
- Don't attack this box over a shared or public network.

## More

- [`STORY.md`](STORY.md) — the in-universe case file
- [`docs/hints.md`](docs/hints.md) — progressive hints
- [`docs/tools.md`](docs/tools.md) — what each tool is for
- [`docs/writeup/WRITEUP.md`](docs/writeup/WRITEUP.md) — full spoiler walkthrough
