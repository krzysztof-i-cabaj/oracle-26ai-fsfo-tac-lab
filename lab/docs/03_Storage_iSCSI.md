> 🇬🇧 English | [🇵🇱 Polski](./03_Storage_iSCSI_PL.md)

# 03 — iSCSI Storage Configuration (VMs2-install)

> **Goal:** Configure shared disks for the RAC cluster (nodes `prim01` and `prim02`). We use a **performance-oriented configuration (Block Backstore + LVM)** on the `infra01` machine and apply advanced parameters in the iSCSI Initiator to squeeze maximum performance out of the VirtualBox environment.

This document describes two deployment methods: an automated (script-based) one and a fully manual step-by-step one.

---

## Method 1: Automated Fast Path (Recommended)

### 1. iSCSI Target on infra01 (LIO Block Performance)

1.  Log in to `infra01` as `root` (password: `Oracle26ai_LAB!`).
2.  Copy the `setup_iscsi_target_infra01.sh` script from the repository to the `/tmp/` directory.
3.  Run the script:
    ```bash
    bash /tmp/scripts/setup_iscsi_target_infra01.sh
    ```

### 2. iSCSI Initiator on prim01 and prim02

1.  Log in to `prim01` as `root`.
2.  Run the script:
    ```bash
    bash /tmp/scripts/setup_iscsi_initiator_prim.sh
    ```
3.  **Repeat the script execution for the `prim02` machine.**

Proceed directly to the **Shared disk verification** section.

---

## Method 2: Manual Path (Step by step)

For those who want to thoroughly understand the iSCSI Storage layer and how the optimizations are applied.

### 1. iSCSI Target Configuration (`infra01`)

Log in to `infra01` as `root`. Change the I/O scheduler for the second disk to support parallel cluster writes:
```bash
echo mq-deadline > /sys/block/sdb/queue/scheduler
```

Now launch the `targetcli` interface to manually define the LIO target (using Logical Volumes on LVM directly):

```bash
targetcli
```
In the `/>` console, paste the following one by one (line by line):
```text
cd backstores/block
create name=ocr1 dev=/dev/vg_iscsi/lun_ocr1
create name=ocr2 dev=/dev/vg_iscsi/lun_ocr2
create name=ocr3 dev=/dev/vg_iscsi/lun_ocr3
create name=data1 dev=/dev/vg_iscsi/lun_data1
create name=reco1 dev=/dev/vg_iscsi/lun_reco1

# Performance optimization (Write Cache = 1) for the DATA and RECO tiers
set attribute emulate_write_cache=1 name=data1
set attribute emulate_write_cache=1 name=reco1

cd /iscsi
create iqn.2026-04.local.lab:infra01.target01
cd iqn.2026-04.local.lab:infra01.target01/tpg1/luns
create /backstores/block/ocr1
create /backstores/block/ocr2
create /backstores/block/ocr3
create /backstores/block/data1
create /backstores/block/reco1

cd ../acls
# Access authorization by IP and node name
create iqn.1994-05.com.redhat:prim01
create iqn.1994-05.com.redhat:prim02
cd ../a_cls/iqn.1994-05.com.redhat:prim01
set auth userid=oracle
set auth password=Oracle26ai_LAB!
cd ../iqn.1994-05.com.redhat:prim02
set auth userid=oracle
set auth password=Oracle26ai_LAB!

cd ../../..
saveconfig
exit
```

Make sure the target is running and enabled in systemd:
```bash
systemctl enable target
systemctl restart target
```

### 2. iSCSI Initiator Configuration (`prim01` and `prim02`)

Perform the same steps for `prim01` and `prim02`. Log in as `root`.

Modify the iscsid service configuration file to improve RAC cluster stability (faster eviction of faulty disks):
```bash
sed -i 's/^node.session.timeo.replacement_timeout.*/node.session.timeo.replacement_timeout = 15/' /etc/iscsi/iscsid.conf
sed -i 's/^node.session.cmds_max.*/node.session.cmds_max = 64/' /etc/iscsi/iscsid.conf
sed -i 's/^node.session.queue_depth.*/node.session.queue_depth = 64/' /etc/iscsi/iscsid.conf
```

Save the node identity (iqn) corresponding to the node and restart iSCSI:
```bash
# On prim01:
echo "InitiatorName=iqn.1994-05.com.redhat:prim01" > /etc/iscsi/initiatorname.iscsi
# NOTE: on prim02 enter prim02 instead of prim01!

systemctl restart iscsid
```

Connect to the iSCSI server and save the password:
```bash
iscsiadm -m discovery -t sendtargets -p 10.0.5.15
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.session.auth.authmethod -v CHAP
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.session.auth.username -v oracle
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.session.auth.password -v Oracle26ai_LAB!

# Automatic target startup and login
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --op update -n node.startup -v automatic
iscsiadm -m node -T iqn.2026-04.local.lab:infra01.target01 -p 10.0.5.15 --login
```

Now configure static aliases (Udev) so that ASM paths are unambiguous:
```bash
cat > /etc/udev/rules.d/99-oracle-asmdevices.rules << 'EOF'
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="36001405a41eaae900134440bbb7bcadd", SYMLINK+="oracleasm/OCR1", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="3600140590c6198f8cc048689baee433d", SYMLINK+="oracleasm/OCR2", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="360014056291a18241474ed9bacf8f2be", SYMLINK+="oracleasm/OCR3", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="36001405ee6efaa3fb3045cb97d8bcf51", SYMLINK+="oracleasm/DATA1", OWNER="grid", GROUP="asmadmin", MODE="0660"
KERNEL=="sd*", BUS=="scsi", PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", RESULT=="36001405e3ec4f9bcf01460a8cf9bf0b7", SYMLINK+="oracleasm/RECO1", OWNER="grid", GROUP="asmadmin", MODE="0660"
# Disable IO scheduler on the initiator for maximum ASM performance
ACTION=="add|change", KERNEL=="sd*", ENV{DEVTYPE}=="disk", RUN+="/bin/sh -c 'echo none > /sys/block/$name/queue/scheduler'"
EOF

udevadm control --reload-rules
udevadm trigger --type=devices --action=change
```

---

## 3. Shared disk verification

After installing and logging in to the targets on both RAC nodes (`prim01` and `prim02`), you must verify that sharing works and that permissions are consistent.

On BOTH nodes run the command:
```bash
ls -l /dev/oracleasm/
```

The output must look identical on both machines (in terms of names, permissions, and owners):
```text
lrwxrwxrwx. 1 root root 4 Apr 24 15:00 DATA1 -> ../sdb
lrwxrwxrwx. 1 root root 4 Apr 24 15:00 OCR1 -> ../sdc
...
```
*(The letters `sdb`, `sdc`, etc. may differ between servers — that is normal. What matters is that the final owner shown by `ls -lL /dev/oracleasm/` belongs to `grid:asmadmin` with rw-rw---- permissions)*:
```bash
ls -lL /dev/oracleasm/
```

Only after a successful verification can you proceed to the Grid Infrastructure layer configuration.

---
**Next step:** `04_Grid_Infrastructure.md`
