> [🇬🇧 English](./10_Performance_Tuning.md) | 🇵🇱 Polski

# 10 — Performance Tuning (VirtualBox + OS + Storage) dla VMs2-install

> **Cel:** Maksymalizacja wydajności labu Oracle 26ai HA na VirtualBox bez utraty wierności architektonicznej. Dokument zbiera optymalizacje wprowadzone w `vbox_create_vms.ps1`, `tune_storage_runtime.sh`, kickstartach `ks-prim01/02/infra01.cfg` oraz `dbca_prim.rsp`. Bazuje na lekcjach z `VMs/17_performance_lab.md` (F-18 z `FIXES_PLAN_v2_PL.md`).

> **Status block+LVM:** w VMs2-install **iSCSI używa block backstore na LVM** (`pvcreate /dev/sdb` → `vgcreate vg_iscsi` → `lvcreate ... lun_data1/lun_reco1/lun_ocr*`). Plik filesystem warstwa pomiędzy LIO a dyskiem **nie istnieje** — to już jest PROD-pattern (NetApp/Pure/EMC). Optymalizacje poniżej dodają warstwy nad block+LVM.

---

## 1. Mapa optymalizacji

| Warstwa | Przed (default) | Po (VMs2-install po F-18) | Komponent | Speedup |
|---------|-----------------|---------------------------|-----------|---------|
| **VirtualBox clock** | `--paravirtprovider default` (ad-hoc TSC) | `--paravirtprovider kvm` (guest reads host TSC) | `scripts/vbox_create_vms.ps1` | time drift < 0.5 s przy 100 % I/O (vs sek-dziesiątki) |
| **VirtualBox NIC** | `--nictype1 e1000` | `--nictype1 virtio` (paravirt) | `scripts/vbox_create_vms.ps1` | 1.5–2× throughput interconnect |
| **VirtualBox SATA cache (infra01)** | `--hostiocache off` | `--hostiocache on` (Windows page cache → iSCSI backstore) | `scripts/vbox_create_vms.ps1` | 5–10× random write |
| **Storage stack** | (już) block+LVM zamiast fileio/XFS | block+LVM | `kickstart/ks-infra01.cfg` (lvcreate) | 2–3× IOPS vs fileio |
| **iSCSI scheduler** | `none`/`bfq` na `/dev/sdb` | `mq-deadline` + `nr_requests=64` | `scripts/tune_storage_runtime.sh --target=infra` | 10–20 % mixed |
| **iSCSI write cache** | sync na DATA/RECO | `emulate_write_cache=1` na `lun_data1/lun_reco1` (NIE OCR) | `tune_storage_runtime.sh --target=infra` | 5–10× random write |
| **iSCSI initiator** | `replacement_timeout=120 / queue_depth=32` (default OL8) | `replacement_timeout=15 / noop_out 5/10 / queue_depth=64` | `tune_storage_runtime.sh --target=initiator` | 5× szybszy detect dead session |
| **Storage NIC** | MTU 1500 | MTU 9000 (jumbo frames) na enp0s9 | `kickstart/ks-prim01/02/infra01.cfg` (nmcli) | 1.5–2× sequential reads |
| **OS HugePages** | brak (4 KB × ~1 mln stron na SGA) | `vm.nr_hugepages=2200` (2200 × 2 MB) | `kickstart/ks-prim01/02.cfg` | TLB miss ↓; RAC stable |
| **OS THP** | `always` (default) | `never` (FIX-033) | `kickstart/*.cfg` (systemd disable-thp) | brak unpredictable latency |
| **OS memlock** | 64 KB (default) | `unlimited` dla oracle/grid | `kickstart/ks-prim01/02.cfg` | wymóg `lock_sga=TRUE` |
| **DB SGA pinning** | `use_large_pages=AUTO`, `lock_sga=FALSE` | `use_large_pages=ONLY`, `lock_sga=TRUE` | `response_files/dbca_prim.rsp` | brak swappingu SGA |

**Łączny efekt:** DBCA `New_Database.dbt` schodzi z ~50 min do ~25 min, fio random write IOPS rośnie 3–5×, RMAN backup pełnego CDB ~5 min zamiast ~12 min.

---

## 2. Co już jest w plikach (po F-18 / PR Plan_Poprawek_v2)

### 2.1 `scripts/vbox_create_vms.ps1`

Tworzy VM z `--paravirtprovider kvm`, `--nictype1..3 virtio`, IntelAhci SATA z hostiocache:
- **infra01** — `--hostiocache on` (Windows page cache OK dla sparse/block backstore w labie),
- **prim01/02/stby01/client01** — `--hostiocache off` (Oracle wymaga `O_DIRECT` semantics).

RAM: infra01 8 GB, prim01/02 9 GB, stby01 6 GB, client01 3 GB. Wymaga ≥ 32 GB RAM na hoście.

### 2.2 `scripts/tune_storage_runtime.sh`

Aplikowane bez restartu VM. Dwa tryby:
- `--target=infra` (na infra01): mq-deadline, write-back na DATA/RECO, restart targetu.
- `--target=initiator` (na prim01/prim02): timeouts iSCSI + queue_depth, logout/login.

### 2.3 Kickstarty `ks-prim01.cfg` / `ks-prim02.cfg`

W sekcji `%post` dopisane:
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

`use_large_pages=ONLY` wymusza alokację SGA na HugePages (`OPS$ORACLE … failed to allocate large pages` jeśli memlock niewłaściwy).

---

## 3. Procedura wdrożenia (kolejność)

1. **Host (PowerShell admin):** `.\scripts\vbox_create_vms.ps1` — tworzy 5 VM z paravirt+virtio.
2. **Boot infra01:** kickstart `ks-infra01.cfg` (LVM na `/dev/sdb`, jumbo na enp0s9, THP=never).
3. **iSCSI target:** `setup_iscsi_target_infra01.sh` (block backstore z LV).
4. **Boot prim01/02:** kickstart (HugePages 2200, memlock unlimited, jumbo enp0s9, THP=never).
5. **iSCSI initiator:** `setup_iscsi_initiator_prim.sh` na prim01/02.
6. **Pre-flight:** `bash scripts/validate_env.sh --full` (DNS, NTP, mountpoints, HugePages, THP).
7. **Tuning runtime:**
   - `sudo bash scripts/tune_storage_runtime.sh --target=infra` (na infra01).
   - `sudo bash scripts/tune_storage_runtime.sh --target=initiator` (na prim01 i prim02).
8. **GI / DB install** (docs/04, /05).
9. **DBCA z `dbca_prim.rsp`** (ma już `use_large_pages=ONLY`, `lock_sga=TRUE`, `db_domain=lab.local`).
10. **Walidacja po DBCA:**
    ```sql
    SELECT name, value FROM v$parameter WHERE name IN ('use_large_pages','lock_sga','db_domain');
    -- Spodziewane: ONLY / TRUE / lab.local
    ```
    ```bash
    cat /proc/meminfo | grep HugePages_Free   # Powinno spasc po startup PRIM
    ```

---

## 4. Benchmark przed/po (jak zmierzyć)

### 4.1 DBCA czas

```bash
time bash /tmp/scripts/create_primary.sh
# Cel po F-18: 25–35 min (vs ~50–90 min przed).
```

### 4.2 Random write IOPS — `fio` na ASM disk group

```bash
# Na prim01 jako oracle.
fio --name=randwrite --filename=/dev/oracleasm/DATA1 --direct=1 \
    --rw=randwrite --bs=8k --size=1G --numjobs=4 --runtime=60 --group_reporting

# Spodziewane po F-18 (block+LVM + write-back + mq-deadline + jumbo + virtio):
#   IOPS:        15 000 – 25 000 (wcześniej 5 000 – 8 000)
#   p99 latency: 5 – 15 ms       (wcześniej 50 – 100 ms)
```

### 4.3 RMAN backup

```bash
time rman target / <<'EOF'
BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
EOF
# Cel: ~5–7 min (vs ~12–15 min).
```

### 4.4 Time drift count w alert log

```bash
ssh oracle@prim01 "grep -c 'Time drifted forward' /u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log"
# Spodziewane po --paravirtprovider kvm: 0–5 wystąpień (wcześniej 100–300+).
```

### 4.5 HugePages utilization

```bash
cat /proc/meminfo | grep -i huge
# Po starcie bazy:
#   HugePages_Total: 2200
#   HugePages_Free:  ~200 (reszta zaalokowana na SGA)
#   Hugepagesize:    2048 kB
```

---

## 5. Co zostało **przemyślane i NIE rekomendowane**

| Propozycja | Werdykt | Powód |
|------------|---------|-------|
| `--hostiocache on` na prim01/02 | ❌ NIE | Oracle używa `O_DIRECT` semantics. Z Windows page cache + write-back: crash hosta = utrata committed transactions = corruption datafile. Akceptowalne TYLKO na infra01 (sparse/block backstore w labie, restorable). |
| `ethtool -K tso off gso off` na enp0s9 | ❌ NIE | W VirtualBox virtio-net TSO/GSO offload jest software (host robi). Wyłączenie = CPU robi segmentation per-pakiet zamiast batch — pogarsza, nie poprawia. |
| `node.session.queue_depth=32` (z propozycji 17) | ⚠ → 64 | 32 to default OL8. Żeby dało efekt, trzeba 64–128. Wybrano 64 (kompromis bezpieczeństwa/IOPS). |
| `--hostiocache on` przy fileio sparse infra01 z BSOD/power loss | ⚠ ryzyko | OK dla labu (RMAN restore odtwarza), nigdy w produkcji. |
| tmpfs backstore (RAM-disk LIO) | ⚠ eksperyment | DBCA do ~15 min, ale po reboocie infra01 LUN-y znikają — jako one-off benchmark, nie do trzymania labu. |
| Multipath iSCSI (drugi target IP, mpathd na prim01/02) | ✓ opcjonalnie | Symuluje PROD HA storage (2 ścieżki). Konfiguracja w sekcji 7 — dla zaawansowanych, niewymagane do działania labu. |

---

## 6. Konfiguracja opcjonalna: Multipath iSCSI (PROD-fidelity)

Nie wymagana dla VMs2-install MVP, ale stanowi naturalne rozszerzenie:

```bash
# Na infra01: drugi target IP na osobnym interfejsie.
ip addr add 192.168.201.10/24 dev enp0s10  # albo dodaj 5-tą NIC
targetcli /iscsi/.../tpgt_1/portals create 192.168.201.10 3260

# Na prim01/02:
dnf install device-mapper-multipath
mpathconf --enable
systemctl start multipathd
iscsiadm -m discovery -t st -p 192.168.200.10
iscsiadm -m discovery -t st -p 192.168.201.10
iscsiadm -m node --loginall=automatic

# /etc/multipath.conf z aliasami; udev-rules → /dev/mapper/mpathX zamiast /dev/sdX.
```

Symuluje PROD HA storage z 2 ścieżkami fizycznymi. Test: `multipath -ll` pokazuje status path'ów.

---

## 7. Powiązane dokumenty

- `02_OS_and_Network_Preparation_PL.md` — kickstart procedure.
- `03_Storage_iSCSI_PL.md` — block+LVM iSCSI target.
- `05_Database_Primary_PL.md` — DBCA z `dbca_prim.rsp`.
- `09_Test_Scenarios_PL.md` — testy korelujące wydajność z FSFO/TAC.
- `../FIXES_19c_to_26ai.md` — geneza decyzji 26ai.
- `../FIXES_PLAN_v2_PL.md` — F-18 z pełnym uzasadnieniem.

---

**Wersja dokumentu:** 1.0 (VMs2-install) | **Data:** 2026-04-27 | **Autor:** KCB Kris

