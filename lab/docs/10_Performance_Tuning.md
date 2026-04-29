> 🇬🇧 English | [🇵🇱 Polski](./10_Performance_Tuning_PL.md)

# 10 — Performance Tuning (VirtualBox + OS + Storage) for VMs2-install

> **Goal:** Maximize performance of the Oracle 26ai HA lab on VirtualBox without sacrificing architectural fidelity. This document collects the optimizations introduced in `vbox_create_vms.ps1`, `tune_storage_runtime.sh`, the kickstarts `ks-prim01/02/infra01.cfg`, and `dbca_prim.rsp`. It builds on the lessons from `VMs/17_performance_lab.md` (F-18 in `FIXES_PLAN_v2.md`).

> **block+LVM status:** in VMs2-install, **iSCSI uses a block backstore on top of LVM** (`pvcreate /dev/sdb` → `vgcreate vg_iscsi` → `lvcreate ... lun_data1/lun_reco1/lun_ocr*`). The fileio filesystem layer between LIO and the disk **does not exist** — this is already a PROD pattern (NetApp/Pure/EMC). The optimizations below add layers on top of block+LVM.

---

## 1. Optimization map

| Layer | Before (default) | After (VMs2-install post F-18) | Component | Speedup |
|-------|------------------|--------------------------------|-----------|---------|
| **VirtualBox clock** | `--paravirtprovider default` (ad-hoc TSC) | `--paravirtprovider kvm` (guest reads host TSC) | `scripts/vbox_create_vms.ps1` | time drift < 0.5 s under 100 % I/O (vs tens of seconds) |
| **VirtualBox NIC** | `--nictype1 e1000` | `--nictype1 virtio` (paravirt) | `scripts/vbox_create_vms.ps1` | 1.5–2× interconnect throughput |
| **VirtualBox SATA cache (infra01)** | `--hostiocache off` | `--hostiocache on` (Windows page cache → iSCSI backstore) | `scripts/vbox_create_vms.ps1` | 5–10× random write |
| **Storage stack** | (already) block+LVM instead of fileio/XFS | block+LVM | `kickstart/ks-infra01.cfg` (lvcreate) | 2–3× IOPS vs fileio |
| **iSCSI scheduler** | `none`/`bfq` on `/dev/sdb` | `mq-deadline` + `nr_requests=64` | `scripts/tune_storage_runtime.sh --target=infra` | 10–20 % mixed |
| **iSCSI write cache** | sync on DATA/RECO | `emulate_write_cache=1` on `lun_data1/lun_reco1` (NOT OCR) | `tune_storage_runtime.sh --target=infra` | 5–10× random write |
| **iSCSI initiator** | `replacement_timeout=120 / queue_depth=32` (OL8 default) | `replacement_timeout=15 / noop_out 5/10 / queue_depth=64` | `tune_storage_runtime.sh --target=initiator` | 5× faster dead session detection |
| **Storage NIC** | MTU 1500 | MTU 9000 (jumbo frames) on enp0s9 | `kickstart/ks-prim01/02/infra01.cfg` (nmcli) | 1.5–2× sequential reads |
| **OS HugePages** | none (4 KB × ~1M pages for SGA) | `vm.nr_hugepages=2200` (2200 × 2 MB) | `kickstart/ks-prim01/02.cfg` | TLB miss ↓; RAC stable |
| **OS THP** | `always` (default) | `never` (FIX-033) | `kickstart/*.cfg` (systemd disable-thp) | no unpredictable latency |
| **OS memlock** | 64 KB (default) | `unlimited` for oracle/grid | `kickstart/ks-prim01/02.cfg` | required by `lock_sga=TRUE` |
| **DB SGA pinning** | `use_large_pages=AUTO`, `lock_sga=FALSE` | `use_large_pages=ONLY`, `lock_sga=TRUE` | `response_files/dbca_prim.rsp` | no SGA swapping |

**Combined effect:** DBCA `New_Database.dbt` drops from ~50 min to ~25 min, fio random write IOPS grows 3–5×, RMAN backup of the full CDB takes ~5 min instead of ~12 min.

---

## 2. What is already in the files (post F-18 / Plan_Poprawek_v2 PR)

### 2.1 `scripts/vbox_create_vms.ps1`

Creates VMs with `--paravirtprovider kvm`, `--nictype1..3 virtio`, IntelAhci SATA with hostiocache:
- **infra01** — `--hostiocache on` (Windows page cache OK for sparse/block backstore in the lab),
- **prim01/02/stby01/client01** — `--hostiocache off` (Oracle requires `O_DIRECT` semantics).

RAM: infra01 8 GB, prim01/02 9 GB, stby01 6 GB, client01 3 GB. Requires ≥ 32 GB RAM on the host.

### 2.2 `scripts/tune_storage_runtime.sh`

Applied without VM restart. Two modes:
- `--target=infra` (on infra01): mq-deadline, write-back on DATA/RECO, target restart.
- `--target=initiator` (on prim01/prim02): iSCSI timeouts + queue_depth, logout/login.

### 2.3 Kickstarts `ks-prim01.cfg` / `ks-prim02.cfg`

The `%post` section adds:
```bash
cat > /etc/sysctl.d/99-oracle-hugepages.conf <<EOF
vm.nr_hugepages = 2200
vm.hugetlb_shm_group = 54322
EOF

cat > /etc/security/limits.d/99-oracle-memlock.conf <<EOF
oracle  soft/hard  memlock  unlimited
grid    soft/hard  memlock  unlimited
EOF

nmcli connection modify "System enp0s9" 802-3-ethernet.mtu 9000
```

Plus systemd `disable-thp.service` (THP=never).

### 2.4 `response_files/dbca_prim.rsp`

```
initParams=...,db_domain=lab.local,use_large_pages=ONLY,lock_sga=TRUE,...
```

`use_large_pages=ONLY` forces SGA allocation on HugePages (`OPS$ORACLE … failed to allocate large pages` if memlock is wrong).

---

## 3. Deployment procedure (order)

1. **Host (PowerShell admin):** `.\scripts\vbox_create_vms.ps1` — creates 5 VMs with paravirt+virtio.
2. **Boot infra01:** kickstart `ks-infra01.cfg` (LVM on `/dev/sdb`, jumbo on enp0s9, THP=never).
3. **iSCSI target:** `setup_iscsi_target_infra01.sh` (block backstore from LV).
4. **Boot prim01/02:** kickstart (HugePages 2200, memlock unlimited, jumbo enp0s9, THP=never).
5. **iSCSI initiator:** `setup_iscsi_initiator_prim.sh` on prim01/02.
6. **Pre-flight:** `bash scripts/validate_env.sh --full` (DNS, NTP, mountpoints, HugePages, THP).
7. **Runtime tuning:**
   - `sudo bash scripts/tune_storage_runtime.sh --target=infra` (on infra01).
   - `sudo bash scripts/tune_storage_runtime.sh --target=initiator` (on prim01 and prim02).
8. **GI / DB install** (docs/04, /05).
9. **DBCA with `dbca_prim.rsp`** (already has `use_large_pages=ONLY`, `lock_sga=TRUE`, `db_domain=lab.local`).
10. **Validation after DBCA:**
    ```sql
    SELECT name, value FROM v$parameter WHERE name IN ('use_large_pages','lock_sga','db_domain');
    -- Expected: ONLY / TRUE / lab.local
    ```
    ```bash
    cat /proc/meminfo | grep HugePages_Free   # Should drop after PRIM startup
    ```

---

## 4. Before/after benchmark (how to measure)

### 4.1 DBCA time

```bash
time bash /tmp/scripts/create_primary.sh
# Target after F-18: 25–35 min (vs ~50–90 min before).
```

### 4.2 Random write IOPS — `fio` on the ASM disk group

```bash
# On prim01 as oracle.
fio --name=randwrite --filename=/dev/oracleasm/DATA1 --direct=1 \
    --rw=randwrite --bs=8k --size=1G --numjobs=4 --runtime=60 --group_reporting

# Expected after F-18 (block+LVM + write-back + mq-deadline + jumbo + virtio):
#   IOPS:        15 000 – 25 000 (previously 5 000 – 8 000)
#   p99 latency: 5 – 15 ms       (previously 50 – 100 ms)
```

### 4.3 RMAN backup

```bash
time rman target / <<'EOF'
BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
EOF
# Target: ~5–7 min (vs ~12–15 min).
```

### 4.4 Time drift count in alert log

```bash
ssh oracle@prim01 "grep -c 'Time drifted forward' /u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log"
# Expected after --paravirtprovider kvm: 0–5 occurrences (previously 100–300+).
```

### 4.5 HugePages utilization

```bash
cat /proc/meminfo | grep -i huge
# After database startup:
#   HugePages_Total: 2200
#   HugePages_Free:  ~200 (rest allocated to SGA)
#   Hugepagesize:    2048 kB
```

---

## 5. What was **considered and NOT recommended**

| Proposal | Verdict | Reason |
|----------|---------|--------|
| `--hostiocache on` on prim01/02 | ❌ NO | Oracle uses `O_DIRECT` semantics. With Windows page cache + write-back: a host crash = loss of committed transactions = datafile corruption. Acceptable ONLY on infra01 (sparse/block backstore in the lab, restorable). |
| `ethtool -K tso off gso off` on enp0s9 | ❌ NO | In VirtualBox, virtio-net TSO/GSO offload is software (the host does it). Disabling = CPU performs per-packet segmentation instead of batching — makes things worse, not better. |
| `node.session.queue_depth=32` (from proposal 17) | ⚠ → 64 | 32 is the OL8 default. To produce an effect, 64–128 is required. Picked 64 (safety/IOPS compromise). |
| `--hostiocache on` with fileio sparse infra01 under BSOD/power loss | ⚠ risk | OK for the lab (RMAN restore recovers), never in production. |
| tmpfs backstore (RAM-disk LIO) | ⚠ experiment | DBCA down to ~15 min, but after infra01 reboot the LUNs disappear — fine as a one-off benchmark, not for a persistent lab. |
| Multipath iSCSI (second target IP, mpathd on prim01/02) | ✓ optional | Simulates PROD HA storage (2 paths). Configuration in section 7 — for advanced users, not required for the lab to function. |

---

## 6. Optional configuration: Multipath iSCSI (PROD-fidelity)

Not required for the VMs2-install MVP, but it is a natural extension:

```bash
# On infra01: second target IP on a separate interface.
ip addr add 192.168.201.10/24 dev enp0s10  # or add a 5th NIC
targetcli /iscsi/.../tpgt_1/portals create 192.168.201.10 3260

# On prim01/02:
dnf install device-mapper-multipath
mpathconf --enable
systemctl start multipathd
iscsiadm -m discovery -t st -p 192.168.200.10
iscsiadm -m discovery -t st -p 192.168.201.10
iscsiadm -m node --loginall=automatic

# /etc/multipath.conf with aliases; udev-rules → /dev/mapper/mpathX instead of /dev/sdX.
```

Simulates PROD HA storage with 2 physical paths. Test: `multipath -ll` shows path status.

---

## 7. Related documents

- `02_OS_and_Network_Preparation.md` — kickstart procedure.
- `03_Storage_iSCSI.md` — block+LVM iSCSI target.
- `05_Database_Primary.md` — DBCA with `dbca_prim.rsp`.
- `09_Test_Scenarios.md` — tests correlating performance with FSFO/TAC.
- `../FIXES_19c_to_26ai.md` — origin of the 26ai decisions.
- `../FIXES_PLAN_v2.md` — F-18 with full justification.

---

**Document version:** 1.0 (VMs2-install) | **Date:** 2026-04-27 | **Author:** KCB Kris
