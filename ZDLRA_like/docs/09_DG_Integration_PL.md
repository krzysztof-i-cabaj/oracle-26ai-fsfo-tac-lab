# 🔗 09 — DG Integration (Sprint 3)

[![Sprint](https://img.shields.io/badge/Sprint-3-blue)]()
[![Topic](https://img.shields.io/badge/Topic-Backup_↔_DG-purple)]()
[![Layer](https://img.shields.io/badge/MAA_Stack-Complete-success)]()
[![Pattern](https://img.shields.io/badge/Pattern-Switchover_Aware-orange)]()

> 🎯 Jak warstwa Backup wspolpracuje z istniejacym Data Guard (PRIM ↔ STBY01).

## 📋 Pre-checks (warunki dla scenariuszy DG-aware)

[PL] Zanim zaczniesz dowolny scenariusz integracji backup ↔ DG (B-7 rebuild, switchover-aware backup, real-time redo do RA):

```bash
# 1) DG broker SUCCESS, role spójne z naming convention
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'SHOW CONFIGURATION'"
# Oczekiwane: Configuration Status SUCCESS, prim01=primary, stby01=physical standby

# 2) Aktualna rola PRIM (czy nie po FSFO failover)
ssh oracle@prim01 'bash -lc "sqlplus -S / as sysdba <<<\"SET HEADING OFF FEEDBACK OFF; SELECT database_role FROM v\\\$database;\""'
# Oczekiwane: PRIMARY (jeśli STANDBY → wykonaj switchover do PRIM przed scenariuszami)

# 3) Observer-y aktywne (jeśli używasz FSFO)
ssh infra01 'pgrep -af "dgmgrl.*observer" | wc -l'
# Oczekiwane: >= 1 (jeśli FSFO MaxAvailability)

# 4) APPLY-ON na stby01
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'SHOW DATABASE STBY'" | grep -i 'apply state'
# Oczekiwane: Apply state: APPLY-ON (lub Apply state: REDO_APPLY)

# 5) Sprint 1 + 2 setup (z doc 08 pre-checks)
# Patrz: docs/08_Backup_Restore_Scenarios_PL.md sekcja 'Wspolne pre-checks'
```

> ⚠️ **Lessons learned do pamiętania:** [#17 RC_SITE bez DBID](08_Backup_Restore_Scenarios_PL.md#troubleshooting), [#21 DBMS_LOCK grant](08_Backup_Restore_Scenarios_PL.md#troubleshooting). Pełna tabela: [doc 08 troubleshooting](08_Backup_Restore_Scenarios_PL.md#troubleshooting).

## 🧩 Architektura: Backup w obecnosci DG

```
┌──────────────────────────────────────────────────────────────────┐
│                      Data Guard Configuration                     │
├──────────────────────────────────────────────────────────────────┤
│   PRIMARY            STANDBY               OBSERVER(S)            │
│   PRIM (RAC 2-node)  STBY (Oracle Restart) obs_ext (infra01)      │
│                                            obs_dr (stby01)        │
│                                                                   │
│   Data Guard Broker   FSFO   TAC                                  │
└──────────────────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────────────────┐
│                     RMAN Recovery Catalog                         │
│   rcat01: rman_cat schema in PDB RCATPDB                          │
│                                                                   │
│   - Rejestruje PRIM (dbid)                                        │
│   - STBY automatycznie znany przez DG broker integration          │
│   - Backupy mozna robic z PRIMARY lub STANDBY                     │
└──────────────────────────────────────────────────────────────────┘
```

## ⚖️ Backup z PRIM czy STBY?

### Opcja A: Backup z PRIMARY (current PRIM)

**Plusy:**
- ✅ Najlatwiejsze do skonfigurowania (TARGET=/, current primary)
- ✅ Nie wymaga oddzielnej konfiguracji RMAN na STBY
- ✅ Standardowy pattern dla mniejszych baz

**Minusy:**
- ❌ Obciaza PRIM (I/O, CPU, network do /mnt/rman_bck)
- ❌ W sytuacji wysokiego obciazenia produkcji - widoczne degradacje
- ❌ Po failover (PRIM -> STBY) trzeba dostosowac cron

### Opcja B: Backup z PHYSICAL STANDBY

**Plusy:**
- ✅ ZERO obciazenia PRIM (krytyczne w prod systems)
- ✅ STBY i tak ma kompletna kopie danych - moze robic backup
- ✅ Active DG (Open Read-Only) pozwala na queryowanie + backup

**Minusy:**
- ❌ Wymaga dodatkowej konfiguracji RMAN na STBY
- ❌ DBID jest ten sam co PRIM - katalog widzi backupy z STBY jak by byly z PRIM

### Rekomendacja dla LAB-u

W LAB-ie wybieramy **Opcja A (backup z PRIM)** dla prostoty. W docs/06_Backup_Policy.md cron na prim01.

W produkcji warto rozwazyc **Opcja B**, ale wymaga to dodatkowej konfiguracji ktorej w LAB-ie nie pokazujemy.

## 🔄 Co sie dzieje przy switchover (PRIM <-> STBY)

### Przed switchover

```
PRIM (db_unique_name=PRIM, role=PRIMARY)  - tu robimy backupy
STBY (db_unique_name=STBY, role=PHYSICAL_STANDBY)  - apply only
```

### Po switchover

```
PRIM (db_unique_name=PRIM, role=PHYSICAL_STANDBY)  - juz nie primary!
STBY (db_unique_name=STBY, role=PRIMARY)  - tu teraz powinien byc backup
```

**Problem:** cron na "prim01" odpala backup, ale prim01 nie jest juz primary.
Rozwiazanie: w skryptach sprawdzamy role bazy zanim odpalimy backup.

```bash
# W rman_full_backup.sh dodajemy pre-check
ROLE=$(sqlplus -S / as sysdba <<<'SET HEADING OFF FEEDBACK OFF; SELECT database_role FROM v$database;')
if [[ "$ROLE" != *"PRIMARY"* ]]; then
    log "[skip] Ten host nie jest PRIMARY (role=$ROLE). Backup powinien isc z drugiego site."
    exit 0
fi
```

**Lepsza opcja**: cron na **obu** hostach (prim01 i stby01), oba z tym pre-checkiem.
Ten ktorzy aktualnie jest PRIMARY uruchomi backup, drugi pominie.

## 🛠️ B-7 deep dive: Rebuild STBY z backupu

Scenariusz B-7 (z `08_Backup_Restore_Scenarios.md`) jest szczegolnie waznym przypadkiem
integracji Backup ↔ DG.

### Kiedy uzywac DUPLICATE FROM BACKUPSET zamiast Active Duplicate?

| Sytuacja | Active Duplicate | FROM BACKUPSET |
|---|---|---|
| STBY rozsynchronizowany ale dziala | ✅ (online resync) | ❌ (overkill) |
| STBY uszkodzony - kompletny rebuild | ⚠️ (obciaza PRIM live) | ✅ (preferowane) |
| Brak sieci PRIM<->STBY tymczasowo | ❌ | ✅ (offline-friendly) |
| Bardzo duza baza (TB+) | ❌ (network bottleneck) | ✅ (read z dysku lokalnego) |

### Sekwencja kroków

#### 🚀 Metoda A — wrapper script (bez wrappera póki co — TODO)

> 💡 **Status:** dedykowanego wrappera `rman_rebuild_standby.sh` jeszcze **nie ma**. B-7 rebuild jest na razie wykonywany manualnie (Metoda B poniżej). To jest świadoma decyzja — rebuild standby to operacja "dla DBA", nie cykliczna. Manual control = świadomość każdego kroku. Wrapper można dorobić jeśli rebuild jest częsty (np. test environments).

#### 🛠️ Metoda B — manualna (sekwencja kroków)

```bash
# 1) Pre-state: STBY uszkodzony
ssh oracle@stby01
sqlplus / as sysdba <<<'SHUTDOWN ABORT;'

# 2) Wyczysc datafile (symulacja - albo realny disaster)
sudo rm -rf /u02/oradata/STBY/*

# 3) Startup NOMOUNT z minimal initfile
cat > /tmp/init_stby_nomount.ora <<'INIT'
db_name='STBY'
db_unique_name='STBY'
INIT
sqlplus / as sysdba <<'SQL'
STARTUP NOMOUNT PFILE='/tmp/init_stby_nomount.ora';
SQL

# 4) Z PRIM: DUPLICATE FOR STANDBY FROM BACKUPSET (manual RMAN ponizej)
ssh oracle@prim01
```

#### 📝 Manual RMAN commands (DUPLICATE FOR STANDBY)

```bash
# Connect: TARGET=PRIM, AUXILIARY=stby01 NOMOUNT, CATALOG=rcat01
rman target / \
     auxiliary "sys/${LAB_PASS}@stby01:1521/STBY" \
     catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
DUPLICATE TARGET DATABASE FOR STANDBY
  FROM BACKUPSET
  DORECOVER
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='STBY'
    SET fal_server='PRIM'
    SET log_archive_config='DG_CONFIG=(PRIM,STBY)'
    SET log_archive_dest_2='SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM'
    SET standby_file_management='AUTO'
    SET dg_broker_start='TRUE';
```

> 💡 **Kluczowe parametry SPFILE SET:**
> - `db_unique_name='STBY'` — identyfikator dla DG broker
> - `fal_server='PRIM'` — fetch archive logs source przy gap recovery
> - `log_archive_config` — DG configuration list (must match na PRIM i STBY)
> - `log_archive_dest_2` — w razie gdy STBY zostaje PRIMARY (po switchover), redo idzie do PRIM
> - `standby_file_management='AUTO'` — automatyczne tworzenie datafile po `ADD DATAFILE` na PRIM
> - `dg_broker_start='TRUE'` — włącza broker procesy

```bash
# 5) Re-enable w DG broker (po DUPLICATE skończonym)
ssh oracle@prim01 'dgmgrl /@PRIM_ADMIN'
```

```dgmgrl
ENABLE DATABASE STBY;
SHOW CONFIGURATION;
SHOW DATABASE STBY;

# Powinno pokazać Status: SUCCESS, Apply Lag/Transport Lag = 0
```

```bash
# 6) Walidacja apply na stby01
ssh oracle@stby01 'sqlplus / as sysdba <<<"SELECT process, status, sequence# FROM v\$managed_standby ORDER BY 1;"'

# Oczekiwane procesy:
# ARCH (multiple) - archive log fetcher
# MRP0           - Managed Recovery Process (apply)
# RFS            - Remote File Server (receive z PRIM)
```

### Krytyczne ustawienia po rebuild

```sql
-- Na stby01 po DUPLICATE
ALTER SYSTEM SET STANDBY_FILE_MANAGEMENT=AUTO;
ALTER SYSTEM SET DG_BROKER_START=TRUE;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='SERVICE=PRIM ASYNC ...';
```

## 🔌 Real-time redo z PRIM do RA (Sprint 3, ZDLRA-like)

To **trzecia rola** dla rcat01 (poza katalogiem i appliance):

```
PRIM redo stream:
  LOG_ARCHIVE_DEST_1 = local (online redo files)
  LOG_ARCHIVE_DEST_2 = STBY (DG transport, SYNC AFFIRM dla MAX_AVAILABILITY)
  LOG_ARCHIVE_DEST_3 = rcat01 (ZDLRA-like, ASYNC NOAFFIRM)
```

`LOG_ARCHIVE_DEST_3` daje rcat01 strumien redo niezaleznie od DG.

### Czy to konflikt z DG?

Nie. DG (DEST_2) i RA-redo (DEST_3) sa niezalezne:
- DEST_2 jest SYNC AFFIRM dla zerowego data loss przy switchover
- DEST_3 jest ASYNC NOAFFIRM dla minimalnego overhead na PRIM
- Oba sa skonfigurowane przez `VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)`
- Po switchover (PRIM -> STBY), DEST_3 musi byc reconfigured na nowym primary

## ⏭️ Powiazane / Related

- [07_ZDLRA_Like_Simulation_PL.md](07_ZDLRA_Like_Simulation_PL.md) — szczegoly LOG_ARCHIVE_DEST_3
- [08_Backup_Restore_Scenarios_PL.md#b-7](08_Backup_Restore_Scenarios_PL.md#b-7) — scenariusz B-7
- [08_Backup_Restore_Scenarios_PL.md#troubleshooting](08_Backup_Restore_Scenarios_PL.md#troubleshooting) — pełna tabela lessons learned dla scenariuszy
- `../../docs/07_FSFO_Observery.md` — Data Guard Broker config (parent project)
- `../../docs/06_Data_Guard_Standby.md` — DG initial setup (parent project)
