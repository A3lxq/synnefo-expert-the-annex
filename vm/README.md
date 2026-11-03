# VM / OVA — The Annex

**Three separate VM appliances**, not one: `gateway-the-annex-ctf.ova`
(published to your host), `directory-the-annex-ctf.ova` (OpenLDAP,
never published), and `fileserver-the-annex-ctf.ova` (SSH, never
published). Both internal-only hosts are reachable only by pivoting
through Gateway — a star topology, same as the original design. All
three are Ubuntu Server 24.04 LTS via QEMU/KVM + cloud-init (NoCloud).
Native build — real Flask/OpenLDAP/openssh-server managed by systemd.
No Docker anywhere.

- **Gateway** has three network adapters: NAT (its published web app,
  port 5000), a private link to Directory, and a separate private
  link to Fileserver.
- **Directory** and **Fileserver** each have two: NAT (build-only,
  locked to a key you don't have) and their one private link back to
  Gateway. They never talk to each other directly — the same
  connectivity the original design actually used.

Flags are **static**, baked in once at provisioning time from a fixed
release secret — every copy of the exported OVAs has the same flags.
The release secret is never committed; `organizer/release-secret.txt`
(gitignored) holds it.

## Using the pre-built OVAs

Download **all three** `.ova` files from this repo's Releases page,
then in VirtualBox (File > Import Appliance), import all three:

1. Import `gateway-the-annex-ctf.ova`. Leave adapter 1 as **NAT**.
   After import, open Settings > Network:
   - Adapter 2 -> **Internal Network**, name `halcyon-annex-directory-link`.
   - Adapter 3 -> **Internal Network**, name `halcyon-annex-fileserver-link`.
2. Import `directory-the-annex-ctf.ova`. Adapter 2 ->
   **Internal Network**, name `halcyon-annex-directory-link` (must
   match Gateway's adapter 2 exactly).
3. Import `fileserver-the-annex-ctf.ova`. Adapter 2 ->
   **Internal Network**, name `halcyon-annex-fileserver-link` (must
   match Gateway's adapter 3 exactly).
4. Power on all three (order doesn't matter) and wait about a minute
   for boot. Browse to Gateway's forwarded web port — check
   VirtualBox's Adapter 1 port-forwarding rules (or open the VM's
   console and `curl localhost:5000`) to confirm the NAT-forwarded
   port.
5. Everything else happens inside the challenge — see `STORY.md` and
   `docs/hints.md` in the repo root.

VMware Workstation/Fusion: File > Open each `.ova`, then set the
matching adapters to "LAN segment" (VMware's equivalent of
VirtualBox's Internal Network) with the same segment name across the
VMs that share a link.

**This is an intentionally vulnerable trio of machines. Import them
only on an isolated network/host.**

## Build from source

```
cd vm
# put ubuntu-24.04-server-cloudimg-amd64.img in images/ first
# put your own ed25519 keypair in keys/ctfbuilder_ed25519[.pub],
# and reference the .pub in all three hosts' cloud-init/user-data.yaml
# generate a release secret: openssl rand -hex 32 > ../organizer/release-secret.txt
./scripts/create-disks.sh
./scripts/boot-vms.sh        # wait a few minutes for first boot + cloud-init on all three
RELEASE_SECRET=$(cat ../organizer/release-secret.txt)
scp -i keys/ctfbuilder_ed25519 -P 2215 scripts/remote-provision-directory.sh ctfbuilder@127.0.0.1:/tmp/
scp -i keys/ctfbuilder_ed25519 -P 2225 scripts/remote-provision-fileserver.sh ctfbuilder@127.0.0.1:/tmp/
scp -i keys/ctfbuilder_ed25519 -P 2205 scripts/remote-provision-gateway.sh ctfbuilder@127.0.0.1:/tmp/
ssh -i keys/ctfbuilder_ed25519 -p 2215 ctfbuilder@127.0.0.1 "RELEASE_SECRET='$RELEASE_SECRET' bash /tmp/remote-provision-directory.sh"
ssh -i keys/ctfbuilder_ed25519 -p 2225 ctfbuilder@127.0.0.1 "RELEASE_SECRET='$RELEASE_SECRET' bash /tmp/remote-provision-fileserver.sh"
ssh -i keys/ctfbuilder_ed25519 -p 2205 ctfbuilder@127.0.0.1 "RELEASE_SECRET='$RELEASE_SECRET' bash /tmp/remote-provision-gateway.sh"
./scripts/verify.sh           # proves all 10 flags before you export anything
./scripts/export-vms.sh
./scripts/export-ovas.sh
```

## Build note: the internal links

During build/test, Gateway's two internal NICs are connected directly
to Directory's and Fileserver's single internal NIC via two separate
QEMU "socket" netdev pairs (Gateway listens on both, the other two
connect) — a software crossover cable with no host route at all,
proving the exact star topology the exported OVAs recreate via
VirtualBox's Internal Network / VMware's LAN segment feature. All
NICs are matched by interface name (`enp0s2`/`enp0s3`/`enp0s4`), not
MAC — see the single-host boxes' own `network-config.yaml` for why
that matters across hypervisors.
