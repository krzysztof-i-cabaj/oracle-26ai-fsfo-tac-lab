#!/bin/bash
# Skrypt do konfiguracji iSCSI Target (LIO) na infra01 / Script to configure iSCSI Target (LIO) on infra01
# Wariant WYDAJNOSCIOWY: uzywa Block Backstore (LVM) zamiast FileIO. / PERFORMANCE variant: uses Block Backstore (LVM) instead of FileIO.
# Uruchamiac jako root na infra01. / Run as root on infra01.

set -e

# IP na ktorym bedzie nasluchiwac iSCSI target / IP on which the iSCSI target will listen
ISCSI_IP="192.168.200.10"
IQN="iqn.2026-04.local.lab:infra01.target"

echo "=========================================================="
echo "    Konfiguracja iSCSI Target (Block Backstore + LVM)     "
echo "    iSCSI Target Configuration (Block Backstore + LVM)    "
echo "=========================================================="

# 1. Weryfikacja obecnosci LVM (z kickstartu) / 1. Verify LVM presence (from kickstart)
if ! lvs | grep -q "vg_iscsi"; then
    echo "[BŁĄD] Nie znaleziono grupy wolumenow 'vg_iscsi'. LVM nie zostal poprawnie utworzony z kickstart. / [ERROR] Volume group 'vg_iscsi' not found. LVM was not created correctly by kickstart."
    exit 1
fi

echo "1. Optymalizacja I/O dla urzadzenia blokowego (/dev/sdb) / 1. I/O optimization for block device (/dev/sdb)"
# Ustawienie schedulera na mq-deadline dla lepszej obsługi równoległych żądań iSCSI / Set scheduler to mq-deadline for better handling of parallel iSCSI requests
echo mq-deadline > /sys/block/sdb/queue/scheduler 2>/dev/null || true
echo "ACTION==\"add|change\", KERNEL==\"sdb\", ATTR{queue/scheduler}=\"mq-deadline\"" > /etc/udev/rules.d/99-iscsi-scheduler.rules
udevadm control --reload-rules
udevadm trigger

echo "2. Konfiguracja LIO za pomoca targetcli / 2. LIO configuration using targetcli"

# Usuwamy stara konfiguracje jesli istnieje / Remove old configuration if exists
targetcli clearconfig confirm=True 2>/dev/null || true

# Uruchamiamy tryb wsadowy w targetcli / Run batch mode in targetcli
targetcli <<EOF
# --- Tworzenie block backstores / Creating block backstores ---
/backstores/block create name=lun_ocr1 dev=/dev/vg_iscsi/lun_ocr1
/backstores/block create name=lun_ocr2 dev=/dev/vg_iscsi/lun_ocr2
/backstores/block create name=lun_ocr3 dev=/dev/vg_iscsi/lun_ocr3
/backstores/block create name=lun_data1 dev=/dev/vg_iscsi/lun_data1
/backstores/block create name=lun_reco1 dev=/dev/vg_iscsi/lun_reco1

# --- Optymalizacja Cache (Emulate Write Cache) dla DATA i RECO / Cache Optimization (Emulate Write Cache) for DATA and RECO ---
# Przyspiesza zapisy random writes na ASM ok. 5-10x / Speeds up random writes on ASM approx 5-10x
# UWAGA: Na dyskach OCR pozostawiamy default (sync), gdyz voting disks wymagaja restrykcyjnej zgodnosci znoszenia awarii. / NOTE: Leave default (sync) on OCR disks, as voting disks require strict crash consistency.
/backstores/block/lun_data1 set attribute emulate_write_cache=1
/backstores/block/lun_reco1 set attribute emulate_write_cache=1

# --- Utworzenie Targetu i Portalu / Target and Portal Creation ---
/iscsi create $IQN
/iscsi/$IQN/tpg1/portals create $ISCSI_IP 3260

# --- Mapowanie LUNow do Targetu / Mapping LUNs to Target ---
/iscsi/$IQN/tpg1/luns create /backstores/block/lun_ocr1
/iscsi/$IQN/tpg1/luns create /backstores/block/lun_ocr2
/iscsi/$IQN/tpg1/luns create /backstores/block/lun_ocr3
/iscsi/$IQN/tpg1/luns create /backstores/block/lun_data1
/iscsi/$IQN/tpg1/luns create /backstores/block/lun_reco1

# --- Wylaczenie autoryzacji (tylko w LAB) / Disable authorization (LAB only) ---
/iscsi/$IQN/tpg1 set attribute authentication=0 generate_node_acls=1 demo_mode_write_protect=0 cache_dynamic_acls=1
saveconfig
exit
EOF

systemctl enable target.service
systemctl restart target.service
firewall-cmd --permanent --add-port=3260/tcp
firewall-cmd --reload

echo "Gotowe! iSCSI Target skonfigurowany w trybie Block + Optymalizacje I/O. / Done! iSCSI Target configured in Block mode + I/O Optimizations."
