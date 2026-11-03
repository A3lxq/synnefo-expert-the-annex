#!/usr/bin/env bash
# boot-vms.sh — boots all three VMs in a star topology through gateway,
# standing in for docker-compose's old "internal-net" (internal: true)
# bridge: gateway has TWO extra NICs, one direct point-to-point link
# to directory and one to fileserver. directory and fileserver never
# talk to each other directly -- same connectivity the original
# design actually used (everything pivots through gateway).
set -euo pipefail
cd "$(dirname "$0")/.."

ACCEL="tcg"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL="kvm"
fi
echo "Using acceleration: $ACCEL"

LINK_A_PORT=20051   # gateway <-> directory
LINK_B_PORT=20052   # gateway <-> fileserver

boot() {
  local NAME="$1"; shift
  local DISK="$NAME/disks/$NAME.qcow2" SEED="$NAME/seed/seed.img"
  mkdir -p "$NAME/logs"
  qemu-system-x86_64 \
    -name "$NAME" \
    -machine type=q35,accel=$ACCEL \
    -cpu max -m 1536 -smp 2 \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -drive file="$SEED",if=virtio,format=raw \
    "$@" \
    -display none \
    -serial file:"$NAME/logs/vm-console.log" \
    -monitor unix:"$NAME/disks/monitor.sock",server,nowait \
    -pidfile "$NAME/disks/vm.pid" \
    -daemonize
}

echo "== Starting gateway (NAT + 2 internal-link listeners) =="
boot gateway \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2205-:22,hostfwd=tcp:127.0.0.1:8005-:5000 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:aa:00:01 \
  -netdev socket,id=net1,listen=127.0.0.1:${LINK_A_PORT} \
  -device virtio-net-pci,netdev=net1,mac=52:54:00:aa:01:01 \
  -netdev socket,id=net2,listen=127.0.0.1:${LINK_B_PORT} \
  -device virtio-net-pci,netdev=net2,mac=52:54:00:aa:02:01

sleep 1

echo "== Starting directory (NAT + link to gateway) =="
boot directory \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2215-:22 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:aa:00:02 \
  -netdev socket,id=net1,connect=127.0.0.1:${LINK_A_PORT} \
  -device virtio-net-pci,netdev=net1,mac=52:54:00:aa:01:02

echo "== Starting fileserver (NAT + link to gateway) =="
boot fileserver \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2225-:22 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:aa:00:03 \
  -netdev socket,id=net1,connect=127.0.0.1:${LINK_B_PORT} \
  -device virtio-net-pci,netdev=net1,mac=52:54:00:aa:02:02

echo "All three VMs starting."
echo "gateway:    ssh -i keys/ctfbuilder_ed25519 -p 2205 ctfbuilder@127.0.0.1   (web: http://127.0.0.1:8005)"
echo "directory:  ssh -i keys/ctfbuilder_ed25519 -p 2215 ctfbuilder@127.0.0.1   (build-only)"
echo "fileserver: ssh -i keys/ctfbuilder_ed25519 -p 2225 ctfbuilder@127.0.0.1   (build-only)"
echo "Stop with: ./scripts/stop-vms.sh"
