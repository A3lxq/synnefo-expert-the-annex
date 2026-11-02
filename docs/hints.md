# Hints (progressive — try to only read as far as you need)

**Flag 1** — View page source on `/`.

**Flag 2** — A generic staff-login guess works here too.

**Flag 3** — `/welcome?name=...` renders what you send as a Jinja2
*template*, not a variable. Try `{{7*7}}` first to confirm — if you get
`49` back instead of literal `{{7*7}}`, you have template injection.
From there, Jinja2 sandbox-escape payloads that reach
`__builtins__.__import__('os')` are widely documented.

**Flag 4/5** — Once you have command execution, you're inside this
department's own network. Something with its own query language lives
on it, reachable by a plain hostname. Anonymous enumeration (no
credentials at all) gets you further than you'd expect.

**Flag 6** — Another host lives on the same internal network. Its SSH
service shows you something before you even try to log in.

**Flag 7** — One of the directory entries you already pulled wasn't just
a note — read it again.

**Flag 8** — You're in, but not as root. Check basic file permissions
you'd check on any Linux box: `ls -la /etc/passwd`. If you can write to
it...

**Flag 9** — Once you're root, there's a log file that was clearly left
for you to find, not hidden at all.

**Flag 10** — The log told you more than just a flag.
