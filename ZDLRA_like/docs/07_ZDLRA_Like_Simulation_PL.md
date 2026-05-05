# 🛡️ 07 — ZDLRA-Like Simulation (Sprint 3)

[![Sprint](https://img.shields.io/badge/Sprint-3-blue)]()
[![Concept](https://img.shields.io/badge/Concept-Virtual_Full_Backup-purple)]()
[![Real_ZDLRA](https://img.shields.io/badge/Real_ZDLRA-Closed_Source-red)]()
[![LAB](https://img.shields.io/badge/LAB-Plain_RMAN_%2B_DG-success)]()
[![RPO](https://img.shields.io/badge/RPO-near_zero-orange)]()

> 🎯 Symulacja kluczowych funkcji **Zero Data Loss Recovery Appliance** w plain RMAN + Data Guard.
> Granica: ZDLRA-like ≠ ZDLRA. Nie symulujemy block dedup ani tape-out.

## 🧠 Co to jest ZDLRA?

[PL] Oracle **Zero Data Loss Recovery Appliance** to dedykowane urzadzenie sprzetowe (Engineered System)
oferujace:
1. **Real-time redo transport** z baz docelowych (RPO ~0)
2. **Virtual Full Backups** przez incremental-forever architecture
3. **Block-level deduplication** w warstwie storage (HW-accelerated)
4. **Tape-out integration** do Oracle Secure Backup / inne biblioteki
5. **Centralny katalog** zarzadzajacy backupami z setek baz
6. **Cross-RA replication** (Active-Active dla DR samego appliance)

[EN] ZDLRA is Oracle's purpose-built engineered system for backup. Closed-source HW + RA Software.

## 🔧 Co symulujemy w LAB-ie

| Funkcja ZDLRA | LAB simulation | Skrypt / Script | Status |
|---|---|---|---|
| Real-time redo | `LOG_ARCHIVE_DEST_3 ASYNC NOAFFIRM` PRIM -> rcat01 | `zdlra_sim_setup.sh --init` | ⚠️ **architectural limit** — patrz lesson #29 niżej |
| Virtual Full Backup | `BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY` + `RECOVER COPY OF DATABASE` | `zdlra_sim_setup.sh --merge` | ✅ |
| Compression | `CONFIGURE COMPRESSION ALGORITHM 'MEDIUM'` (basic, bez ACO) | sql/10 | ✅ |
| Centralny katalog | `rman_cat` w PDB RCATPDB na rcat01 | sql/01,02,03 | ✅ Sprint 1 |

## ❌ Czego NIE symulujemy

- **Block-level deduplication** — to wylacznie ZDLRA HW feature
- **Tape-out integration** — brak biblioteki w LAB-ie
- **Cross-RA replication** — brak drugiego appliance
- **Hardware-accelerated compression** — basic compression jest software-only
- **Real-time validation** — nasze validate jest manualne (`rman_validate.sh`)

## 🚀 Setup (jednorazowo)

[PL] Setup ZDLRA-like ma 3 etapy: (1) listener na rcat01 z static service `rcat_redo`, (2) TNS alias na PRIM, (3) init real-time redo + initial Level 0 IMAGE COPY na PRIM. Etapy 1-2 są **inherently manual** (edit plików konfiguracyjnych Oracle Net), etap 3 ma Method A/B.

[EN] ZDLRA-like setup has 3 stages: (1) listener on rcat01 with static service `rcat_redo`, (2) TNS alias on PRIM, (3) real-time redo init + initial Level 0 IMAGE COPY on PRIM. Stages 1-2 are inherently manual (edit Oracle Net config files), stage 3 has Method A/B.

### 📋 Pre-checks

- ✅ PRIM zarejestrowany w katalogu (Sprint 1 step 3a — `SELECT name, dbid FROM rc_database;` zwraca PRIM)
- ✅ Persistent RMAN config wykonany (Sprint 2 — `SHOW ALL` w RMAN pokazuje 9 CONFIGURE)
- ✅ `/mnt/rman_bck` zamontowany na prim01 (`mount | grep rman_bck`)
- ✅ Sieciowo widoczne: prim01 → rcat01:1521 (`ping rcat01.lab.local`)
- ✅ Logujesz sie jako `oracle` na prim01 (etapy 1, 3) i `oracle` na rcat01 (etap 2 — listener)

### Etap 1 — Listener na rcat01 (static service `rcat_redo`)

[PL] Real-time redo wymaga **static service registration** w listener-ze rcat01. Dynamiczna rejestracja przez DBMS dziala tylko gdy DB jest OPEN — dla redo apply musimy mieć service nawet przy DB MOUNTED.

#### 🚀 Metoda A — automatyczna (zalecane)

Jednolinijkowiec: SSH do rcat01 → append do `listener.ora` (idempotent: sprawdza czy `rcat_redo` już jest) → reload + verify.

```bash
ssh oracle@rcat01 'bash -lc "
LF=\$ORACLE_HOME/network/admin/listener.ora
if grep -q \"GLOBAL_DBNAME=rcat_redo\" \$LF 2>/dev/null; then
  echo \"[skip] rcat_redo juz w \$LF\"
else
  cat >> \$LF <<EOF

SID_LIST_LISTENER=
  (SID_LIST=
    (SID_DESC=
      (GLOBAL_DBNAME=rcat_redo)
      (ORACLE_HOME=\$ORACLE_HOME)
      (SID_NAME=RCAT)
    )
  )
EOF
  echo \"[added] rcat_redo do \$LF\"
fi
lsnrctl reload
lsnrctl status | grep -i rcat_redo
"'
# Oczekiwane na koncu: 'Service "rcat_redo" has 1 instance(s)'
```

> 💡 **Idempotencja:** skrypt sprawdza grep przed append — re-run nie duplikuje wpisu.

#### 🛠️ Metoda B — manualna (interaktywnie)

```bash
ssh oracle@rcat01
vi $ORACLE_HOME/network/admin/listener.ora
# Dodaj na koncu pliku:
```

```
SID_LIST_LISTENER=
  (SID_LIST=
    (SID_DESC=
      (GLOBAL_DBNAME=rcat_redo)
      (ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME=RCAT)
    )
  )
```

```bash
# Zapisz (:wq), potem:
lsnrctl reload
lsnrctl status | grep -i rcat_redo
# Oczekiwane: 'Service "rcat_redo" has 1 instance(s)'
```

### Etap 2 — TNS alias na PRIM

[PL] PRIM łączy się do `rcat_redo` przez TNS alias zdefiniowany w `tnsnames.ora` na prim01 (i prim02 dla RAC).

#### 🚀 Metoda A — automatyczna (zalecane)

Jednolinijkowiec: SSH do prim01 → append do `tnsnames.ora` (idempotent) → tnsping verify.

```bash
ssh oracle@prim01 'bash -lc "
TF=\$TNS_ADMIN/tnsnames.ora
if grep -q \"^RCAT01_REDO\" \$TF 2>/dev/null; then
  echo \"[skip] RCAT01_REDO juz w \$TF\"
else
  cat >> \$TF <<EOF

RCAT01_REDO =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = rcat01.lab.local)(PORT = 1521))
    (CONNECT_DATA =
      (SERVICE_NAME = rcat_redo)
      (SERVER = DEDICATED)
    )
  )
EOF
  echo \"[added] RCAT01_REDO do \$TF\"
fi
tnsping RCAT01_REDO
"'
# Oczekiwane na koncu: 'OK (XX msec)'
```

> 💡 **Dla RAC (prim02):** powtórz z `ssh oracle@prim02 ...` (tnsnames.ora jest per-host, nie shared).

> ⚠️ **Lesson #13:** `tnsping` wymaga PATH ustawionego przez `~/.bash_profile` — `bash -lc` zapewnia login shell.

#### 🛠️ Metoda B — manualna (interaktywnie)

```bash
ssh oracle@prim01
echo $TNS_ADMIN
# Sprawdz lokalizacje (zwykle /u01/app/oracle/product/23.26/dbhome_1/network/admin/)
vi $TNS_ADMIN/tnsnames.ora
# Dodaj na koncu pliku:
```

```
RCAT01_REDO =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = rcat01.lab.local)(PORT = 1521))
    (CONNECT_DATA =
      (SERVICE_NAME = rcat_redo)
      (SERVER = DEDICATED)
    )
  )
```

```bash
# Zapisz (:wq), potem verify:
tnsping RCAT01_REDO
# Oczekiwane: 'OK (XX msec)'
```

### Etap 3 — Real-time redo + initial Level 0 IMAGE COPY

[PL] To "core" konfiguracji ZDLRA-like: ustawienie `LOG_ARCHIVE_DEST_3` (ASYNC redo do rcat01) + jeden raz wykonanie `BACKUP INCREMENTAL LEVEL 0 AS COPY DATABASE` (image copy, NIE backupset). Skrypt `zdlra_sim_setup.sh --init` robi oba w sekwencji.

#### 🚀 Metoda A — automatyczna (zalecane)

```bash
# Lokalnie na prim01 jako oracle:
ssh oracle@prim01
bash /tmp/scripts/zdlra_sim_setup.sh --init

# Albo zdalnie z hosta (po ssh_setup.sh full mesh):
ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --init'
```

Skrypt wykonuje (v1.3+):
1. `ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(PRIM,STBY,RCAT)'` — dodaje **RCAT** (db_unique_name bazy targetowej) do DG (lesson #26, inaczej ORA-16053)
2. `ALTER SYSTEM SET LOG_ARCHIVE_DEST_3='SERVICE=RCAT01_REDO ASYNC NOAFFIRM ... DB_UNIQUE_NAME=RCAT'` — DB_UNIQUE_NAME musi być faktycznym `db_unique_name` baz targetowej (NIE aliasem service-u, lesson #28, inaczej ORA-16191)
3. `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE`
4. `ALTER SYSTEM SWITCH LOGFILE` (force real-time apply test)
5. `BACKUP INCREMENTAL LEVEL 0 AS COPY DATABASE FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U'` (image copy, ~1 minuta na 50GB DB)
6. `LIST COPY OF DATABASE TAG 'incr_merge'` — walidacja

#### 🛠️ Metoda B — manualna (interaktywnie)

**Krok 3.1 — Real-time redo (sqlplus jako sysdba):**

```bash
ssh oracle@prim01
sqlplus / as sysdba
```

```sql
-- KROK 3.1a: Dodaj RCAT (db_unique_name bazy targetowej) do DG_CONFIG.
-- Lesson #26: bez tego ALTER LOG_ARCHIVE_DEST_3 zwraca:
-- 'ORA-02097: parameter cannot be modified ... ORA-16053: DB_UNIQUE_NAME ...
--  is not in the Data Guard Configuration'
-- UWAGA Lesson #28: w DG_CONFIG i DB_UNIQUE_NAME (ponizej) MUSI byc faktyczny
-- db_unique_name target bazy ('SELECT db_unique_name FROM v$database' na rcat01 = 'RCAT'),
-- NIE alias TNS service-u ('rcat_redo'). Inaczej DEST_3 status=ERROR ORA-16191
-- 'log shipping client unable to log onto target database' (Oracle weryfikuje match).
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(PRIM,STBY,RCAT)' SCOPE=BOTH;

-- KROK 3.1b: Skonfiguruj LOG_ARCHIVE_DEST_3 (real-time redo do bazy RCAT na rcat01).
-- SERVICE=RCAT01_REDO -> TNS alias na prim01 mapuje na rcat01:1521 SERVICE_NAME=rcat_redo
--                       (static service w listener.ora na rcat01)
-- DB_UNIQUE_NAME=RCAT -> faktyczny db_unique_name bazy docelowej (z v$database)
ALTER SYSTEM SET LOG_ARCHIVE_DEST_3=
  'SERVICE=RCAT01_REDO ASYNC NOAFFIRM
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=RCAT' SCOPE=BOTH;

ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE SCOPE=BOTH;

ALTER SYSTEM SWITCH LOGFILE;

-- Walidacja: dest_id=3 musi byc VALID, error=null
SELECT dest_id, dest_name, status, error FROM v$archive_dest WHERE dest_id IN (1,2,3);
EXIT
```

**Krok 3.2 — Initial Level 0 IMAGE COPY (RMAN):**

```bash
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  BACKUP
    INCREMENTAL LEVEL 0
    AS COPY
    TAG 'incr_merge'
    DATABASE
    FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';
  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
}
LIST COPY OF DATABASE TAG 'incr_merge';
EXIT
```

> 💡 **Skrót:** możesz pominąć cały `RUN { }` block — RMAN użyje domyślnych kanałów z naszego `CONFIGURE DEVICE TYPE DISK PARALLELISM 4`:
> ```rman
> BACKUP INCREMENTAL LEVEL 0 AS COPY TAG 'incr_merge' DATABASE FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';
> ```

### ✅ Walidacja po setupie

```bash
# Status (przez wrapper)
ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status'

# Lub manualnie
sqlplus -S 'rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB' <<'SQL'
SET LINESIZE 150 PAGESIZE 50

-- Image copies w katalogu (file_type='X' = COPY in RMAN nazewnictwie)
SELECT s.db_unique_name, COUNT(*) AS files,
       ROUND(SUM(p.bytes)/1024/1024/1024, 2) AS total_gb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.tag = 'INCR_MERGE'
 GROUP BY s.db_unique_name;

-- Albo dla image copies (RC_BACKUP_DATAFILE, nie BACKUP_PIECE):
SELECT name, ROUND(blocks*block_size/1024/1024,1) AS mb
  FROM rc_datafile_copy
 WHERE tag = 'INCR_MERGE'
 ORDER BY name;

EXIT
SQL
```

> ⚠️ **Lesson #22:** w 26ai `RC_BACKUP_SET` nie ma kolumn bytes — JOIN do `RC_BACKUP_PIECE`. Image copies są dodatkowo widoczne w `RC_DATAFILE_COPY`.

## ⚠️ Lesson #29: Real-time redo do rcat01 — architectural limit

[PL] **Empirycznie weryfikowane 2026-05-04 iter.14 autonomous fix:** mimo poprawnej konfiguracji (TNS, listener, DG_CONFIG, DB_UNIQUE_NAME, pwfile binary sync), real-time redo do rcat01 zwraca **`ORA-16009: invalid redo transport destination`**. Powód: Oracle DG redo transport wymaga **physical standby** target — identyczny `db_name` + `dbid`. RCAT ma `db_name=RCAT/dbid=1004435869`, PRIM ma `db_name=PRIM/dbid=229119773`. Mismatch fundamentalny.

**Zatem w LAB-ie:**
- ✅ **Image copy + L1 incremental merge** (`--init` / `--merge`) → DZIAŁA, esencja ZDLRA-Like
- 🔒 **Real-time redo (`LOG_ARCHIVE_DEST_3`)** → DEFERRED, niemożliwy do uruchomienia bez full physical standby PRIM na rcat01
- ✅ **Practical workaround dla ~15 min RPO**: `rman_archivelog_only.sh` cron na PRIM (archlogi w `/mnt/rman_bck/arch/` shared folder, dostępne z rcat01)

[EN] **Empirically verified 2026-05-04 iter.14 autonomous fix:** despite correct configuration (TNS, listener, DG_CONFIG, DB_UNIQUE_NAME, pwfile binary sync), real-time redo to rcat01 returns **`ORA-16009: invalid redo transport destination`**. Reason: Oracle DG redo transport requires **physical standby** target — identical `db_name` + `dbid`. RCAT has `db_name=RCAT/dbid=1004435869`, PRIM has `db_name=PRIM/dbid=229119773`. Fundamental mismatch.

**Pełen log diagnostyki + fix-u:** [autonomous_dest3_log_PL.md](../zdlra-backup-live-test/logs/autonomous_dest3_log_PL.md) (PL) / [autonomous_dest3_log.md](../zdlra-backup-live-test/logs/autonomous_dest3_log.md) (EN).

**Aby usunąć ERROR z v$archive_dest** (po próbie setup-u DEST_3):
```sql
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=DEFER SCOPE=BOTH;
-- Status: DEFERRED (config zachowany, brak cycling errors)
```

### 🔮 Możliwe rozszerzenie LAB: Sprint 5 (opcjonalny) — physical standby PRIM na rcat01

[PL] Aby odblokować real-time redo (`DEST_3`) + scenariusz **Zero RPO recovery** (potencjalny B-9 w doc 08), można zbudować na rcat01 **drugą instancję Oracle** = physical standby bazy PRIM. Nie zastępuje ona istniejącej bazy `RCAT` (recovery catalog) — działa **obok**, na osobnym storage / osobnym SID.

[EN] To unlock real-time redo (`DEST_3`) + **Zero RPO recovery** scenario (potential B-9 in doc 08), you can build a **second Oracle instance** on rcat01 = physical standby of PRIM. It does NOT replace the existing `RCAT` (recovery catalog) — it runs **alongside**, on separate storage / separate SID.

#### 🛠️ Kroki wysokopoziomowe / High-level steps

| # | Krok [PL] | Step [EN] |
|---|---|---|
| 1 | **Storage:** drugi ASM diskgroup `+DATA_RCAT` (lub `/u02/oradata/PRIM_RCAT/`) na rcat01, ~10 GB | Second ASM diskgroup `+DATA_RCAT` (or `/u02/oradata/PRIM_RCAT/`), ~10 GB |
| 2 | **Listener:** static SID `PRIM_RCAT` w listener.ora na rcat01 + `lsnrctl reload` | Add static SID `PRIM_RCAT` in listener.ora on rcat01 + `lsnrctl reload` |
| 3 | **TNS na PRIM:** wpis `PRIM_RCAT = (HOST=rcat01)(SERVICE_NAME=PRIM_RCAT)` | Add `PRIM_RCAT = (HOST=rcat01)(SERVICE_NAME=PRIM_RCAT)` to tnsnames on PRIM |
| 4 | **PFILE na rcat01:** `db_name=PRIM`, `db_unique_name=PRIM_RCAT`, `fal_server=PRIM`, `standby_file_management=AUTO` | PFILE: `db_name=PRIM`, `db_unique_name=PRIM_RCAT`, `fal_server=PRIM`, `standby_file_management=AUTO` |
| 5 | **Pwfile sync (krytyczne — Lesson #27):** binary-identical z PRIM przez `DBMS_FILE_TRANSFER` z `+DATA/PRIM/PASSWORD/pwdprim.*` → scp → `$ORACLE_HOME/dbs/orapwPRIM_RCAT` | Pwfile binary-identical with PRIM via `DBMS_FILE_TRANSFER` from `+DATA/PRIM/PASSWORD/pwdprim.*` → scp → `$ORACLE_HOME/dbs/orapwPRIM_RCAT` |
| 6 | **Aux startup:** `STARTUP NOMOUNT PFILE='/tmp/init_prim_rcat.ora'` na rcat01 | `STARTUP NOMOUNT PFILE='/tmp/init_prim_rcat.ora'` on rcat01 |
| 7 | **DUPLICATE FOR STANDBY** (z PRIM) — patrz blok niżej | DUPLICATE FOR STANDBY (from PRIM) — see block below |
| 8 | **Data Guard:** `dgmgrl` → `ADD DATABASE PRIM_RCAT AS CONNECT IDENTIFIER IS PRIM_RCAT MAINTAINED AS PHYSICAL` | `dgmgrl` → `ADD DATABASE PRIM_RCAT AS CONNECT IDENTIFIER IS PRIM_RCAT MAINTAINED AS PHYSICAL` |
| 9 | **Aktywacja DEST_3:** `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE` na PRIM (po DG ADD broker zarządza automatycznie) | `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE` on PRIM |
| 10 | **Walidacja:** `v$archive_dest dest_id=3 STATUS=VALID`, `v$managed_standby` na PRIM_RCAT pokazuje MRP0 APPLYING_LOG, `log_apply_lag=0` | `v$archive_dest dest_id=3 STATUS=VALID`, `v$managed_standby` on PRIM_RCAT shows MRP0 APPLYING_LOG, `log_apply_lag=0` |

#### 📝 RMAN DUPLICATE FOR STANDBY (krok 7)

```rman
# Z prim01 jako oracle / From prim01 as oracle:
rman target / auxiliary sys/${LAB_PASS}@rcat01:1521/PRIM_RCAT \
     catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB

DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE
  DORECOVER
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='PRIM_RCAT'
    SET fal_server='PRIM'
    SET log_archive_config='DG_CONFIG=(PRIM,STBY,PRIM_RCAT)'
    SET log_archive_dest_2='SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM'
    SET db_file_name_convert='+DATA/PRIM','+DATA_RCAT/PRIM_RCAT'
    SET log_file_name_convert='+DATA/PRIM','+DATA_RCAT/PRIM_RCAT';
```

#### 📊 Koszt vs zysk / Cost vs benefit

| Aspekt | Wartość [PL] | Value [EN] |
|---|---|---|
| Storage | ~10 GB (datafiles + redo + archlogs) | ~10 GB (datafiles + redo + archlogs) |
| RAM | ~2 GB dla nowej instancji | ~2 GB for the new instance |
| CPU | Minimalne (apply only, nie OLTP) | Minimal (apply only, no OLTP) |
| Konfiguracja | ~2-3 h: storage + DUPLICATE (~45 min) + DG broker + pwfile sync | ~2-3 h: storage + DUPLICATE (~45 min) + DG broker + pwfile sync |
| ✅ Zysk: real-time redo do rcat01 | DEST_3 VALID, redo apply natychmiastowo | DEST_3 VALID, redo applied real-time |
| ✅ Zysk: Zero RPO recovery (B-9) | Recovery do ostatniej zatwierdzonej transakcji bez czekania na archlog switch | Recovery to last committed transaction without waiting for archlog switch |
| ✅ Zysk: ZDLRA-Like full semantics | Real-time redo + image copy = pełna ZDLRA architektura | Real-time redo + image copy = full ZDLRA architecture |

#### 🤔 Dlaczego nie robimy teraz w LAB-ie / Why not in the current LAB

- **8 scenariuszy backup/restore** (doc 08) + **Virtual Full Backup** (doc 07) **już teraz pokrywają ~80% real ZDLRA workflow** bez Sprint 5
- Practical workaround dla ~15 min RPO już istnieje (`rman_archivelog_only.sh` cron + shared folder)
- Sprint 5 jest dobrym kandydatem na **future iteration** gdy powstanie potrzeba demo Zero RPO
- W realnym ZDLRA tę funkcję pełni **dedykowany hardware** (Recovery Appliance), nie drugi standby

#### 🚫 Co NIE jest celem Sprint 5 / What is NOT a Sprint 5 goal

- ❌ **Switchover/failover** — PRIM_RCAT pozostaje **stale w roli STANDBY** (recovery storage role only) / PRIM_RCAT stays **permanently in STANDBY role** (recovery storage role only)
- ❌ **Własny observer** dla DG PRIM↔PRIM_RCAT — wystarczy istniejący observer dla PRIM↔STBY / Own observer for DG PRIM↔PRIM_RCAT — existing observer for PRIM↔STBY suffices
- ❌ **MaxProtection** — opcjonalne, i tak mamy `MaxPerformance` dla PRIM↔STBY / Optional, we already have `MaxPerformance` for PRIM↔STBY

> 💡 **Status decyzji:** Sprint 5 jest **udokumentowany ale nie zaplanowany**. Trigger do realizacji = potrzeba demo Zero RPO recovery lub real-time redo z poziomu recovery catalog host.
> **Decision status:** Sprint 5 is **documented but not planned**. Trigger for implementation = need for Zero RPO recovery demo or real-time redo from recovery catalog host.

## 🔁 Wykonywanie merge cycle / Running merge cycles

[PL] Po setupie (initial Level 0 IMAGE COPY istnieje), codziennie wykonujemy **incremental merge cycle**: aplikuj poprzedni inkrement do image copy + zrób nowy inkrement na następny dzień. W LAB-ie (wyłączane VM-y) używamy **manual on-demand**.

[EN] After setup (initial Level 0 IMAGE COPY exists), daily run **incremental merge cycle**: apply previous increment to image copy + take a new increment for the next day. In LAB (powered-off VMs) we use **manual on-demand**.

### 📋 Workflow LAB-u — manual on-demand (default)

| Akcja | Co robi | Kiedy uruchomić | Komenda |
|---|---|---|---|
| **`zdlra_sim_setup.sh --init`** | One-off: `LOG_ARCHIVE_DEST_3` + initial L0 IMAGE COPY | Raz, po wykonaniu Etapów 1-2 | `ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --init'` |
| **`zdlra_sim_setup.sh --merge`** | Daily merge: RECOVER COPY (apply prev incr) + new INCR L1 FOR RECOVER OF COPY | Raz na dzień LAB-uptime, lub przed Sprint 2 testem | `ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --merge'` |
| **`zdlra_sim_setup.sh --status`** | Diagnostyka: dest_id=3 status + LIST COPY + size na disku | Po init/merge dla potwierdzenia | `ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status'` |

> 💡 **Sugerowana sekwencja po włączeniu LAB-u** (jeśli chcesz fresh image copy + jeden cycle merge):
> ```bash
> # Tylko raz (po Etapach 1-2 manual):
> ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --init'   # Initial L0 (~5 min)
>
> # Daily merge — robisz manualnie kiedy chcesz świeży image copy:
> ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --merge'  # ~1-2 min
> ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status' # Verify
> ```

### 🚀 Production reference — cron snippet (NIE deployujemy w LAB-ie)

> ⚠️ **Tylko jako referencja — w naszym LAB-ie ten cron NIE jest deployowany.** VM-y są wyłączane, daily merge w okresach offline po prostu nigdy się nie wykona. Dla LAB-u używaj sekcji "Manual on-demand" powyżej. Snippet poniżej dokumentuje **jak wyglądałaby polityka produkcyjna**.

```cron
# /var/spool/cron/oracle (na prim01) - PRODUCTION ONLY
# Production only - NOT deployed in this LAB

# Daily merge - codziennie o 03:00 (po archivelog backup w 02:00)
0 3 * * * /home/oracle/scripts/zdlra_sim_setup.sh --merge
```

### 📝 Manualne polecenia RMAN (copy/paste, bez wrappera)

[PL] Surowe komendy RMAN dla incremental-merge pattern (Virtual Full Backup) — copy/paste do RMAN-a po `rman target / catalog ...`.

#### 🔵 Initial Level 0 IMAGE COPY (jednorazowo, po Etapie 2)

```rman
BACKUP INCREMENTAL LEVEL 0 AS COPY TAG 'incr_merge' DATABASE
  FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';
```

#### 🟡 Daily merge cycle (krok 1 z 2 — apply previous incremental)

```rman
RECOVER COPY OF DATABASE WITH TAG 'incr_merge';
```

> 💡 **Pierwszy dzień:** RECOVER COPY znajduje image copy ale **brak inkrementu** do zaaplikowania → no-op (komunikat "no incremental backup to apply"). Od drugiego dnia faktycznie aplikuje poprzedni L1.

#### 🟢 Daily merge cycle (krok 2 z 2 — new incremental for next merge)

```rman
BACKUP
  INCREMENTAL LEVEL 1
  FOR RECOVER OF COPY WITH TAG 'incr_merge'
  DATABASE
  FORMAT '/mnt/rman_bck/incr_merge/incr_%d_%U';
```

> 💡 **Klucz:** `FOR RECOVER OF COPY` zmienia semantykę — RMAN wie że ten inkrement będzie później aplikowany do image copy (nie restore-d osobno).

#### 📋 Walidacja image copy + ostatni incremental

```rman
LIST COPY OF DATABASE TAG 'incr_merge';
LIST BACKUP OF DATABASE TAG 'incr_merge';

# Ile zajmuje na dysku:
HOST 'du -sh /mnt/rman_bck/incr_merge/';
```

#### 🚪 Exit

```rman
EXIT
```

## 🔄 Jak dziala incremental-merge (Virtual Full Backup)

```
Day 0 (init):
   image_copy_v0 = pelny copy databazy (Level 0)

Day 1:
   incr_l1_d1 = zmiany od dnia 0 (Level 1 cumulative)
   RECOVER COPY OF DATABASE -> aplikuje incr_l1_d1 do image_copy
   image_copy_v0 zmienia sie w image_copy_v1 (jak swiezy L0)

Day 2:
   incr_l1_d2 = zmiany od dnia 1
   RECOVER COPY -> image_copy_v2

... i tak dalej.

Efekt: zawsze jeden swiezy image copy + maly incremental, BEZ kosztu pelnego L0.
```

To jest **core funkcji ZDLRA** w plain RMAN. Daje "Virtual Full Backup" (RMAN nazewnictwo).

## ✅ Walidacja runtime / Runtime validation

[PL] Walidacja po-setupie (czy Etap 3 zadziałał) jest w sekcji "✅ Walidacja po setupie" wyżej. Tutaj — **runtime health check**: czy real-time redo wciąż działa, czy archlogi docierają do rcat01, czy image copy + last incremental są spójne.

[EN] Post-setup validation (whether Stage 3 worked) is in "✅ Validation after setup" above. This section — **runtime health check**: whether real-time redo is still flowing, archive logs arriving at rcat01, image copy + last incremental are consistent.

### Quick check via wrapper

```bash
ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status'

# Oczekiwane:
# 1) LOG_ARCHIVE_DEST_3 status: VALID, error=(null)
# 2) LIST COPY OF DATABASE TAG 'incr_merge' pokazuje image copy
# 3) du /mnt/rman_bck/incr_merge/ ~50 GB (image copy) + ~1-3 GB (last incremental)
```

### Sql queries (na PRIM jako sysdba)

```sql
-- 1) Real-time redo destination zywy
SELECT dest_id, dest_name, status, error
  FROM v$archive_dest WHERE dest_id=3;
-- Oczekiwane: status=VALID, error=(null)

-- 2) Ostatnie archlogi przeslane do rcat01 (dest_id=3)
SELECT name, sequence#, status FROM v$archived_log
  WHERE dest_id=3 ORDER BY sequence# DESC FETCH FIRST 5 ROWS ONLY;
-- Powinno pokazac sekwencje rosnaca, status='A' (Available)

-- 3) Verify ostatni log switch trafil do dest_id=3 (lag check)
SELECT thread#, MAX(sequence#) AS max_seq,
       MAX(CASE WHEN dest_id=1 THEN sequence# END) AS local_seq,
       MAX(CASE WHEN dest_id=3 THEN sequence# END) AS rcat_seq
  FROM v$archived_log
 WHERE first_time > SYSDATE - 1/24
 GROUP BY thread#;
-- local_seq = rcat_seq -> redo apply na biezaco
-- local_seq > rcat_seq -> jest lag (ASYNC normal jesli <5)
```

### Sql queries (na rcat01 jako rman_cat)

```sql
-- 4) Image copy + incremental w katalogu (rozmiar)
SELECT name, ROUND(blocks*block_size/1024/1024, 1) AS size_mb,
       TO_CHAR(creation_time, 'YYYY-MM-DD HH24:MI') AS created
  FROM rc_datafile_copy
 WHERE tag = 'INCR_MERGE'
 ORDER BY name;

-- 5) Last incremental L1 (dla nastepnego merge)
SELECT s.bs_key, s.tag, s.incremental_level, s.pieces,
       TO_CHAR(s.completion_time, 'YYYY-MM-DD HH24:MI') AS done,
       ROUND(SUM(p.bytes)/1024/1024, 1) AS size_mb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.tag = 'INCR_MERGE' AND s.incremental_level = 1
 GROUP BY s.bs_key, s.tag, s.incremental_level, s.pieces, s.completion_time
 ORDER BY s.completion_time DESC FETCH FIRST 3 ROWS ONLY;
```

> ⚠️ **Lesson #22:** w 26ai bytes są w `RC_BACKUP_PIECE` (per-piece, JOIN po `bs_key`), NIE w `RC_BACKUP_SET`. Image copies są w `RC_DATAFILE_COPY` (osobny widok od backupset-ów).

## 🚧 Troubleshooting

| Problem | Rozwiazanie |
|---|---|
| `error 12541 TNS:no listener` | `lsnrctl status` na rcat01, sprawdz czy `rcat_redo` zarejestrowany (Etap 1) |
| `error 1031 insufficient privileges` | LOG_ARCHIVE_DEST wymaga REDO_TRANSPORT_USER albo SYS-as-sysdba ze static service |
| Image copy rosnie nieproporcjonalnie | Po `RECOVER COPY` poprzednia wersja powinna byc usunieta - sprawdz `LIST COPY` |
| Incremental merge dlugo trwa | `PARALLELISM` w 10_rman_config_persistent.sql lub w `RUN { ALLOCATE CHANNEL ... }` |
| `RMAN-02001 unrecognized punctuation symbol "-"` | RMAN nie obsluguje `--` jako komentarz, uzyj `#` (lesson #20). Sprawdz `*.sql` i bash heredoc-i |
| `PLS-00201: identifier 'DBMS_LOCK' must be declared` | Lesson #21: `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;` w PDB RCATPDB |
| Skrypt `--init` lub `--merge` nic nie pokazuje, log file pusty | Lesson #24: `set -u` + `source ~/.bash_profile` cichy crash. Wrap source w `set +u; source ...; set -u` |
| ARC0 process busy/slow | Sprawdz net latency `tnsping rcat01_redo`, redo network bottleneck — w LAB-ie zwykle <50ms |

## 📊 Porownanie: Standard backup vs Virtual Full

| Metryka | Standard (FULL co tydzien) | Virtual Full (incremental merge) |
|---|---|---|
| Czas pelnego backup | ~1h (na 50 GB DB) | ~5 min (initial), 1 min (daily merge) |
| Storage I/O | wysokie raz/tydzien | rownomierne male |
| Recovery time z najnowszego | ~30 min (FULL + arch) | ~10 min (image copy + arch) |
| Retention granularity | tydzien | dzien |
| Wymagany licensing | brak | brak (plain RMAN) |

## ⏭️ Nastepny krok / Next step

[09_DG_Integration.md](09_DG_Integration_PL.md) — integracja Backup ↔ Data Guard (rebuild standby z backupu).
