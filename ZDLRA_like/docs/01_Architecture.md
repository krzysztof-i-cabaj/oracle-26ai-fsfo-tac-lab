# 🏛️ 01 — Recovery Appliance Subproject Architecture

[![Doc](https://img.shields.io/badge/Doc-Architecture-blueviolet)]()
[![MAA](https://img.shields.io/badge/MAA_Stack-HA%20%2B%20DR%20%2B%20Backup-success)]()
[![Layer](https://img.shields.io/badge/Layer-Backup-red)]()
[![Type](https://img.shields.io/badge/Type-ZDLRA--like-orange)]()
[![Oracle](https://img.shields.io/badge/Oracle-26ai_23.26.1-red)]()

> 🎯 Goal: complete the full MAA (Maximum Availability Architecture) stack with the Backup layer.

## 🧩 Full MAA stack

```
┌─────────────────────────────────────────────────────────────┐
│                    LAB Oracle 26ai HA MAA                   │
├─────────────────────────────────────────────────────────────┤
│  HA  (RAC 2-node)         │  prim01  prim02     ✓ existing  │
│  DR  (Active Data Guard)  │  stby01             ✓ existing  │
│  FSFO/TAC                 │  obs_ext, obs_dr    ✓ existing  │
│  ───────────────────────────────────────────────            │
│  BACKUP (RMAN catalog +   │  rcat01             ★ NEW       │
│         ZDLRA-like)       │                                  │
└─────────────────────────────────────────────────────────────┘
```

## 🌐 Topology

```
                    ┌─────────────┐
                    │   infra01   │ DNS, NTP, iSCSI Target
                    │ 192.168.56.10│ obs_ext (master observer)
                    └──────┬──────┘
                           │ host-only 192.168.56.0/24
        ┌──────────────────┼──────────────────────┐
        │                  │                      │
        v                  v                      v
  ┌──────────┐      ┌──────────┐         ┌────────────┐
  │  prim01  │ RAC  │  prim02  │         │   stby01   │ Active DG
  │ 11       │◄────►│ 12       │         │ 13         │ obs_dr
  └────┬─────┘      └────┬─────┘         └──────┬─────┘
       │                 │                       │
       │  RMAN backups (TARGET=PRIM)             │
       │  + real-time redo (LOG_ARCHIVE_DEST_3)  │
       v                 v                       │
  ┌─────────────────────────────┐                │
  │   rcat01 (NEW)              │                │
  │   192.168.56.16             │                │
  │   - DB RCAT (Single Inst)   │                │
  │   - Schema rman_cat         │                │
  │   - Local archlog cache     │                │
  └──────────┬──────────────────┘                │
             │                                   │
             v                                   │
  ┌──────────────────────────┐                   │
  │  /mnt/rman_bck (vboxsf)  │ ◄─────────────────┘
  │  Host: D:\_RMAN_BCK_...  │
  │  - Full backups          │
  │  - Incremental backups   │
  │  - Archivelog backups    │
  │  - Controlfile autobkp   │
  └──────────────────────────┘
```

## 📊 rcat01 components

| Component | Value | Notes |
|---|---|---|
| OS | Oracle Linux 8.10 | consistent with the LAB |
| Oracle DB | 26ai 23.26.1 EE | Single Instance, no GI/HAS |
| Auto-start | systemd `oracle-rcat.service` | dbstart/dbshut |
| CDB | RCAT | container |
| PDB | RCATPDB | catalog tenant |
| Catalog schema | rman_cat | RECOVERY_CATALOG_OWNER |
| Tablespace | RCAT_DATA | dedicated for the catalog, autoextend |
| FRA | /u03/fra/RCAT (50 GB) | controlfile autobackup + minimal redo |
| Local cache | /u04/local_arch_cache (~50 GB) | real-time redo from PRIM |
| Backup target | /mnt/rman_bck (vboxsf) | shared with PRIM/STBY |

## 🔄 Data flow

### Backup from PRIM to rcat01 + /mnt/rman_bck

1. **Cron** on rcat01 invokes `rman_*.sh` via SSH on prim01
2. **prim01**: `rman target / catalog rman_cat/...@rcat01:1521/RCATPDB`
3. **TARGET** = PRIM (data source) — RMAN reads datafiles/redo from PRIM
4. **CATALOG** = rcat01 — RMAN stores metadata in RCATPDB
5. **Backup destination** = `/mnt/rman_bck/` (vboxsf, visible from PRIM and rcat01)

### Real-time redo (Sprint 3)

1. PRIM has `LOG_ARCHIVE_DEST_3=SERVICE=rcat01_redo ASYNC NOAFFIRM`
2. Redo is streamed to `rcat01:/u04/local_arch_cache`
3. Cron on rcat01 runs `BACKUP ARCHIVELOG ALL` every 15 min to `/mnt/rman_bck/arch/`

## 🛡️ ZDLRA-like vs real ZDLRA

| Feature | ZDLRA real | ZDLRA-like (LAB) | Implementation |
|---|---|---|---|
| Real-time redo transport | ✅ | ✅ | LOG_ARCHIVE_DEST_3 ASYNC |
| Virtual Full Backup (incremental merge) | ✅ | ✅ | RMAN `RECOVER COPY OF DATABASE` |
| Compression | ✅ (HW-accel) | ⚠️ basic | `CONFIGURE COMPRESSION ALGORITHM 'MEDIUM'` |
| Block-level deduplication | ✅ | ❌ | (closed-source in ZDLRA) |
| Tape-out integration | ✅ | ❌ | (no library in LAB) |
| Cross-RA replication | ✅ | ❌ | (no second RA) |
| Centralized catalog | ✅ | ✅ | `rman_cat` in RCATPDB |
| Retention/expiration policy | ✅ | ✅ | RMAN `CONFIGURE RETENTION POLICY` |

## 🔗 Related

- [02_Boot_Automation_PoC.md](02_Boot_Automation_PoC.md) — Sprint 0 (boot kickstart)
- [03_VM_Preparation.md](03_VM_Preparation.md) — Sprint 1 step 1 (VM + OS)
- [04_DB_Install_and_Auto_Start.md](04_DB_Install_and_Auto_Start.md) — Sprint 1 step 2 (DB)
- [05_Catalog_Setup.md](05_Catalog_Setup.md) — Sprint 1 step 3 (RMAN catalog)
- [06_Backup_Policy.md](06_Backup_Policy.md) — Sprint 2 (backup cycles)
- [07_ZDLRA_Like_Simulation.md](07_ZDLRA_Like_Simulation.md) — Sprint 3 (incremental merge)
- [08_Backup_Restore_Scenarios.md](08_Backup_Restore_Scenarios.md) — 8 demo scenarios
