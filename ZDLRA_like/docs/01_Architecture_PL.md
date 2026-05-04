# 🏛️ 01 — Architektura podprojektu Recovery Appliance

[![Doc](https://img.shields.io/badge/Doc-Architecture-blueviolet)]()
[![MAA](https://img.shields.io/badge/MAA_Stack-HA%20%2B%20DR%20%2B%20Backup-success)]()
[![Layer](https://img.shields.io/badge/Layer-Backup-red)]()
[![Type](https://img.shields.io/badge/Type-ZDLRA--like-orange)]()
[![Oracle](https://img.shields.io/badge/Oracle-26ai_23.26.1-red)]()

> 🎯 Cel: domkniecie pelnego stosu MAA (Maximum Availability Architecture) przez warstwe Backup.
> Goal: complete the MAA stack with the Backup layer.

## 🧩 Pelny stos MAA / Full MAA stack

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

## 🌐 Topologia / Topology

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
  │   - Schemat rman_cat        │                │
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

## 📊 Komponenty rcat01 / rcat01 components

| Komponent | Wartosc | Uwagi |
|---|---|---|
| OS | Oracle Linux 8.10 | spojnosc z LAB-em |
| Oracle DB | 26ai 23.26.1 EE | Single Instance, brak GI/HAS |
| Auto-start | systemd `oracle-rcat.service` | dbstart/dbshut |
| CDB | RCAT | container |
| PDB | RCATPDB | catalog tenant |
| Schemat katalogu | rman_cat | RECOVERY_CATALOG_OWNER |
| Tablespace | RCAT_DATA | dedykowany dla katalogu, autoextend |
| FRA | /u03/fra/RCAT (50 GB) | autobackup controlfile + minimal redo |
| Lokalny cache | /u04/local_arch_cache (~50 GB) | real-time redo z PRIM |
| Backup target | /mnt/rman_bck (vboxsf) | wspoldzielony z PRIM/STBY |

## 🔄 Przeplyw danych / Data flow

### Backup z PRIM do rcat01 + /mnt/rman_bck

1. **Cron** na rcat01 wywoluje `rman_*.sh` przez SSH na prim01
2. **prim01**: `rman target / catalog rman_cat/...@rcat01:1521/RCATPDB`
3. **TARGET** = PRIM (zrodlo danych) — RMAN czyta datafile/redo z PRIM
4. **CATALOG** = rcat01 — RMAN zapisuje metadane w RCATPDB
5. **Backup destination** = `/mnt/rman_bck/` (vboxsf, widoczny z PRIM i rcat01)

### Real-time redo (Sprint 3)

1. PRIM ma `LOG_ARCHIVE_DEST_3=SERVICE=rcat01_redo ASYNC NOAFFIRM`
2. Redo strumieniowo trafia do `rcat01:/u04/local_arch_cache`
3. Cron na rcat01 robi `BACKUP ARCHIVELOG ALL` co 15 min do `/mnt/rman_bck/arch/`

## 🛡️ ZDLRA-like vs prawdziwy ZDLRA / ZDLRA-like vs real

| Funkcja / Feature | ZDLRA real | ZDLRA-like (LAB) | Implementacja |
|---|---|---|---|
| Real-time redo transport | ✅ | ✅ | LOG_ARCHIVE_DEST_3 ASYNC |
| Virtual Full Backup (incremental merge) | ✅ | ✅ | RMAN `RECOVER COPY OF DATABASE` |
| Compression | ✅ (HW-accel) | ⚠️ basic | `CONFIGURE COMPRESSION ALGORITHM 'MEDIUM'` |
| Block-level deduplication | ✅ | ❌ | (closed-source w ZDLRA) |
| Tape-out integration | ✅ | ❌ | (brak biblioteki w LAB) |
| Cross-RA replication | ✅ | ❌ | (brak drugiego RA) |
| Centralized catalog | ✅ | ✅ | `rman_cat` w RCATPDB |
| Polityka retention/expiration | ✅ | ✅ | RMAN `CONFIGURE RETENTION POLICY` |

## 🔗 Powiazane / Related

- [02_Boot_Automation_PoC.md](02_Boot_Automation_PoC_PL.md) — Sprint 0 (boot kickstart)
- [03_VM_Preparation.md](03_VM_Preparation_PL.md) — Sprint 1 step 1 (VM + OS)
- [04_DB_Install_and_Auto_Start.md](04_DB_Install_and_Auto_Start_PL.md) — Sprint 1 step 2 (DB)
- [05_Catalog_Setup.md](05_Catalog_Setup_PL.md) — Sprint 1 step 3 (RMAN catalog)
- [06_Backup_Policy.md](06_Backup_Policy_PL.md) — Sprint 2 (cykle backup)
- [07_ZDLRA_Like_Simulation.md](07_ZDLRA_Like_Simulation_PL.md) — Sprint 3 (incremental merge)
- [08_Backup_Restore_Scenarios.md](08_Backup_Restore_Scenarios_PL.md) — 8 scenariuszy demo
