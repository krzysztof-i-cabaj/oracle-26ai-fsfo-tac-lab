#!/bin/bash
# Skrypt do konfiguracji iSCSI Initiator na prim01 / prim02 | Script to configure iSCSI Initiator on prim01 / prim02
# Wariant WYDAJNOSCIOWY: Optymalizacje timeoutów i kolejki dla środowiska klastrowego. / PERFORMANCE variant: Timeout and queue optimizations for cluster environment.
# Uruchamiac jako root. / Run as root.

set -e

ISCSI_TARGET_IP="192.168.200.10"

echo "=========================================================="
echo "    Konfiguracja iSCSI Initiator (Wydajnosc / ASM)        "
echo "    iSCSI Initiator Configuration (Performance / ASM)     "
echo "=========================================================="

# 1. Optymalizacja pliku iscsid.conf dla klastrow (szybsze odcięcie wadliwych ścieżek) / 1. iscsid.conf optimization for clusters (faster failing of faulty paths)
# Default dla replacement_timeout to 120s, zmieniamy na 15s aby CRS szybciej reagował. / Default for replacement_timeout is 120s, changing to 15s so CRS reacts faster.
sed -i 's/^node.session.timeo.replacement_timeout.*/node.session.timeo.replacement_timeout = 15/' /etc/iscsi/iscsid.conf
sed -i 's/^node.conn\[0\].timeo.noop_out_interval.*/node.conn[0].timeo.noop_out_interval = 5/' /etc/iscsi/iscsid.conf
sed -i 's/^node.conn\[0\].timeo.noop_out_timeout.*/node.conn[0].timeo.noop_out_timeout = 10/' /etc/iscsi/iscsid.conf
# Zwiekszenie glebokosci kolejki (default 32) / Increase queue depth (default 32)
sed -i 's/^node.session.cmds_max.*/node.session.cmds_max = 128/' /etc/iscsi/iscsid.conf
sed -i 's/^node.session.queue_depth.*/node.session.queue_depth = 64/' /etc/iscsi/iscsid.conf

systemctl restart iscsid.service

# 2. Wykrywanie i podlaczanie do Targetu na infra01 / 2. Discovering and connecting to Target on infra01
echo "Wykrywanie targetu na $ISCSI_TARGET_IP... / Discovering target on $ISCSI_TARGET_IP..."
iscsiadm -m discovery -t st -p $ISCSI_TARGET_IP

echo "Logowanie do targetu... / Logging into target..."
iscsiadm -m node --loginall=automatic
systemctl enable iscsi.service

# 3. Udev Rules - Mapowanie sczek iSCSI na stale nazwy /dev/oracleasm/* / 3. Udev Rules - Mapping iSCSI paths to persistent names /dev/oracleasm/*
# Optymalizacja: ustawiamy scheduler "none" dla dyskow ASM na inicjatorze (nie chcemy podwojnego buforowania przez OS, Oracle ASM sam tym zarzadza) / Optimization: set scheduler "none" for ASM disks on initiator (we don't want double buffering by OS, Oracle ASM manages it)

echo "Tworzenie regul udev dla dyskow ASM (z optymalizacja schedulera)... / Creating udev rules for ASM disks (with scheduler optimization)..."
cat > /etc/udev/rules.d/99-oracleasm.rules <<EOF
# Dyski OCR (Voting) / OCR Disks (Voting)
KERNEL=="sd*", SUBSYSTEM=="block", ENV{ID_PATH}=="ip-$ISCSI_TARGET_IP:3260-iscsi-*-lun-0", SYMLINK+="oracleasm/OCR1", OWNER="oracle", GROUP="dba", MODE="0660", ATTR{queue/scheduler}="none"
KERNEL=="sd*", SUBSYSTEM=="block", ENV{ID_PATH}=="ip-$ISCSI_TARGET_IP:3260-iscsi-*-lun-1", SYMLINK+="oracleasm/OCR2", OWNER="oracle", GROUP="dba", MODE="0660", ATTR{queue/scheduler}="none"
KERNEL=="sd*", SUBSYSTEM=="block", ENV{ID_PATH}=="ip-$ISCSI_TARGET_IP:3260-iscsi-*-lun-2", SYMLINK+="oracleasm/OCR3", OWNER="oracle", GROUP="dba", MODE="0660", ATTR{queue/scheduler}="none"

# Dysk DATA / DATA Disk
KERNEL=="sd*", SUBSYSTEM=="block", ENV{ID_PATH}=="ip-$ISCSI_TARGET_IP:3260-iscsi-*-lun-3", SYMLINK+="oracleasm/DATA1", OWNER="oracle", GROUP="dba", MODE="0660", ATTR{queue/scheduler}="none"

# Dysk RECO / RECO Disk
KERNEL=="sd*", SUBSYSTEM=="block", ENV{ID_PATH}=="ip-$ISCSI_TARGET_IP:3260-iscsi-*-lun-4", SYMLINK+="oracleasm/RECO1", OWNER="oracle", GROUP="dba", MODE="0660", ATTR{queue/scheduler}="none"
EOF

# W przepadku RAC z rozdzielonymi rolami grid/oracle zmieniamy na uzytkownika grid: / In case of RAC with separated grid/oracle roles, change to grid user:
sed -i 's/OWNER="oracle", GROUP="dba"/OWNER="grid", GROUP="asmadmin"/g' /etc/udev/rules.d/99-oracleasm.rules

udevadm control --reload-rules
udevadm trigger

# 4. Sprawdzenie / 4. Verification
sleep 2
echo "Weryfikacja zamapowanych dyskow: / Verifying mapped disks:"
ls -l /dev/oracleasm/
