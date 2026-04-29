#!/usr/bin/env bash
# ==============================================================================
# Tytul:        tune_storage_runtime.sh
# Opis:         Storage I/O tuning bez restartu VMek dla VMs2-install (block+LVM mode).
#               Dla infra01: LIO write-back cache na lun_data1/lun_reco1 (NIE OCR),
#                            mq-deadline scheduler na /dev/sdb, restart targetu.
#               Dla prim01/02: iSCSI initiator timeouts (replacement_timeout=15,
#                            noop_out 5/10, queue_depth=64), logout+login.
# Description [EN]: Block-mode storage tuning for VMs2-install. Runtime, no VM restart.
#
# Autor:        KCB Kris
# Data:         2026-04-27
# Wersja:       1.0 (VMs2-install) - port z VMs/scripts/alt/ (F-18.E),
#               odchudzony do block+LVM (VMs2-install nie ma /var/storage XFS).
#
# Wymagania [PL]:    - Root, podmontowany iSCSI target na infra01 lub session na initiator.
# Requirements [EN]: - Root; iSCSI target up on infra01 or session active on initiator.
#
# Uzycie [PL]:
#   Na infra01:        sudo bash scripts/tune_storage_runtime.sh --target=infra
#   Na prim01/prim02:  sudo bash scripts/tune_storage_runtime.sh --target=initiator
# Usage [EN]: see above.
#
# OSTRZEZENIE: emulate_write_cache=1 na DATA/RECO oznacza ze crash infra01
# bez flush moze spowodowac utrate committed transactions. OK dla labu, NIE prod.
# OCR zostaja sync (voting disks must be consistent).
# ==============================================================================

set -euo pipefail
log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "tune_storage_runtime.sh wymaga uprawnien root"

TARGET="${1:-infra}"
TARGET="${TARGET#--target=}"

case "$TARGET" in
    infra|infra01)
        log "Storage target tuning na $(hostname) (block+LVM mode)..."

        # 1. LIO write-back cache na DATA/RECO (NIE na OCR voting disks).
        log "LIO write-back cache na lun_data1, lun_reco1 (OCR zostaje sync!)..."
        for lun in lun_data1 lun_reco1; do
            if targetcli /backstores/block/$lun >/dev/null 2>&1; then
                targetcli /backstores/block/$lun set attribute emulate_write_cache=1
                log "  $lun (block): write-back ON"
            elif targetcli /backstores/fileio/$lun >/dev/null 2>&1; then
                # Backward compat dla labow w fileio.
                targetcli /backstores/fileio/$lun set attribute emulate_write_cache=1
                targetcli /backstores/fileio/$lun set attribute emulate_fua_write=1
                log "  $lun (fileio): write-back ON"
            else
                log "  WARN: $lun nie znaleziony w block ani fileio backstore"
            fi
        done

        # OCR1/2/3 jawnie sync.
        for lun in lun_ocr1 lun_ocr2 lun_ocr3; do
            log "  $lun: sync ZOSTAJE (voting disk integrity)"
        done

        targetcli / saveconfig
        log "targetcli config saved"

        # 2. mq-deadline scheduler na /dev/sdb (storage backstore device).
        if [[ -e /sys/block/sdb/queue/scheduler ]]; then
            log "I/O scheduler /dev/sdb -> mq-deadline..."
            echo mq-deadline > /sys/block/sdb/queue/scheduler 2>/dev/null || \
                log "  WARN: nie udalo sie zmienic schedulera"
            echo 64 > /sys/block/sdb/queue/nr_requests 2>/dev/null || true

            cat > /etc/udev/rules.d/60-storage-scheduler.rules <<'UDEVEOF'
# F-18.E (VMs2-install): mq-deadline lepszy dla iSCSI block backstore z concurrent writers.
KERNEL=="sdb", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/nr_requests}="64"
UDEVEOF
            udevadm control --reload-rules
            log "  Scheduler=$(cat /sys/block/sdb/queue/scheduler), nr_requests=$(cat /sys/block/sdb/queue/nr_requests)"
        fi

        # 3. Restart targetu by write-back wzielo skutek.
        log "Restart targetcli (initiatorzy moga miec ~5s przerwy iSCSI)..."
        systemctl restart target
        sleep 3
        log "DONE infra01."
        ;;

    initiator|prim|prim01|prim02)
        log "iSCSI initiator tuning na $(hostname)..."

        IQN="${IQN:-iqn.2026-04.local.lab.infra01:racstorage}"

        log "Update node.session.timeo + node.conn timeouts..."
        iscsiadm -m node -T "$IQN" --op update -n node.session.timeo.replacement_timeout -v 15
        iscsiadm -m node -T "$IQN" --op update -n node.conn[0].timeo.noop_out_interval -v 5
        iscsiadm -m node -T "$IQN" --op update -n node.conn[0].timeo.noop_out_timeout -v 10
        iscsiadm -m node -T "$IQN" --op update -n node.session.queue_depth -v 64

        log "iSCSI parameters po update:"
        iscsiadm -m node -T "$IQN" -o show | grep -E 'replacement_timeout|noop_out|queue_depth' | head -10

        log "Logout + login session (~5s przerwy, CRS to wytrzymuje)..."
        iscsiadm -m node -T "$IQN" --logout 2>/dev/null || true
        sleep 2
        iscsiadm -m node -T "$IQN" --login

        sleep 5
        log "Devices po loginie:"
        ls -la /dev/oracleasm/ 2>/dev/null || ls -la /dev/disk/by-id/ | grep iscsi || true

        log "DONE $(hostname)."
        ;;

    *)
        die "Nieznany --target=$TARGET (dozwolone: infra, initiator)"
        ;;
esac

cat <<TXT

================================================================================
Storage tuning DONE on $(hostname).

Weryfikacja:
  # Na infra01:
  cat /sys/block/sdb/queue/scheduler                            # -> mq-deadline
  targetcli /backstores/block/lun_data1 get attribute emulate_write_cache   # -> 1
  targetcli /backstores/block/lun_ocr1  get attribute emulate_write_cache   # -> 0 (OCR sync)

  # Na prim01/02:
  iscsiadm -m node -o show | grep -E 'replacement_timeout|queue_depth'      # 15 / 64

Performance test (na prim01 jako oracle):
  fio --name=randwrite --filename=/dev/oracleasm/DATA1 --direct=1 \\
      --rw=randwrite --bs=8k --size=1G --numjobs=4 --runtime=60 --group_reporting

Spodziewany efekt (block+LVM + write-back + mq-deadline):
  randwrite IOPS:  5 000-8 000  ->  15 000-25 000   (3-4x)
  latency p99:     50-100 ms    ->  5-15 ms         (5-10x)
================================================================================
TXT
