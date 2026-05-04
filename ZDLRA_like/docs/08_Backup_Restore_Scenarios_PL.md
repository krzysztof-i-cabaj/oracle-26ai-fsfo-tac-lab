# 🧪 08 — Backup / Restore Scenarios (Sprint 2 + 3)

[![Sprint](https://img.shields.io/badge/Sprint-2%20%2B%203-blue)]()
[![Scenarios](https://img.shields.io/badge/Scenarios-8-success)]()
[![Type](https://img.shields.io/badge/Type-Demo_%2F_Validation-orange)]()
[![Pattern](https://img.shields.io/badge/Pattern-Diagnose%20→%20Action%20→%20Verify-purple)]()

> 🎯 8 scenariuszy demo backup/restore pokazujace pelnia mozliwosci Recovery Appliance LAB-u.
> 8 demo scenarios showcasing the lab's backup/restore capabilities.

## 📋 Lista scenariuszy / Scenario list

| ID | Tytul [PL] | Title [EN] | Sprint | Skrypty |
|---|---|---|---|---|
| [B-1](#b-1) | Pelny cykl: REGISTER -> FULL -> CROSSCHECK -> LIST | Basic catalog cycle | 2 | rman_full_backup.sh, rman_crosscheck.sh |
| [B-2](#b-2) | Tygodniowy cykl: L0 + L1 + arch co 15 min | Weekly cycle | 2 | rman_full_backup.sh, rman_incremental_l1.sh, rman_archivelog_only.sh |
| [B-3](#b-3) | Incremental Merge / Virtual Full Backup | Virtual Full Backup | 3 | zdlra_sim_setup.sh |
| [B-4](#b-4) | PITR po DROP TABLE w PDB | PITR after DROP TABLE | 2 | rman_restore_pitr.sh |
| [B-5](#b-5) | Online tablespace recovery | Tablespace recovery | 2 | rman_restore_tablespace.sh |
| [B-6](#b-6) | Loss of CONTROLFILE + SPFILE -> autobackup | Controlfile loss | 2 | rman_restore_controlfile.sh |
| [B-7](#b-7) | Rebuild STBY01 z backupu (DUPLICATE FROM BACKUPSET) | DG rebuild from backup | 3 | (DGMGRL + RMAN) |
| [B-8](#b-8) | Test environment refresh przez DUPLICATE | Test env refresh | 3 | rman_duplicate_for_test.sh |

---

## 📋 Wspólne pre-checks (przed dowolnym scenariuszem)

[PL] Większość scenariuszy zakłada że Sprint 1 + Sprint 2 setup jest zakończony. Sprawdź jednorazowo przed pierwszą sesją:

[EN] Most scenarios assume Sprint 1 + Sprint 2 setup is complete. Verify once before the first session:

```bash
# 1) PRIM zarejestrowany w katalogu (Sprint 1 step 3a)
ssh oracle@prim01 'bash -lc "sqlplus -S \"rman_cat/\${LAB_PASS}@rcat01:1521/RCATPDB\" <<<\"SELECT name, dbid FROM rc_database;\""'
# Oczekiwane: PRIM 229119773 (lub inny DBID Twojego LAB-u)

# 2) Persistent RMAN config aktywny (Sprint 2 — 9 CONFIGURE)
ssh oracle@prim01 'rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" <<<"SHOW ALL;" 2>/dev/null | grep -c CONFIGURE'
# Oczekiwane: >= 9

# 3) Pierwszy FULL backup wykonany (potrzebny dla B-3..B-8 jako baseline)
ssh oracle@prim01 'ls -lh /mnt/rman_bck/full/ | head -10'
# Oczekiwane: pliki backupset bp_* lub df_*

# 4) SSH equivalency rcat01 ↔ prim01 / prim02 / stby01 (po ssh_setup.sh full mesh)
ssh oracle@rcat01 'ssh -o PasswordAuthentication=no oracle@prim01 hostname'
# Oczekiwane: prim01 (bez prompta hasla)

# 5) /mnt/rman_bck zamontowany na prim01
ssh oracle@prim01 'mount | grep rman_bck'
# Oczekiwane: vboxsf z D:\_RMAN_BCK_from_Linux_

# 6) LAB_PASS w /root/.lab_secrets na hostach gdzie skrypty sa uruchamiane
ssh root@prim01 'cat /root/.lab_secrets | grep -c LAB_PASS'
# Oczekiwane: 1
```

> ⚠️ **Lessons learned do pamietania (z dnia iter.12):** [#20](#troubleshooting) RMAN: `#` nie `--` w komentarzach (sql + bash heredocs). [#21](#troubleshooting) `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat`. [#22](#troubleshooting) `RC_BACKUP_SET` w 26ai bez bytes — JOIN do `RC_BACKUP_PIECE`. [#24](#troubleshooting) `set -u` + `source ~/.bash_profile` = silent crash w skryptach.

---

## <a id="b-1"></a>🔹 B-1: Pelny cykl katalogu RMAN

**Cel:** Zademonstrowac podstawowy workflow: REGISTER -> FULL backup -> CROSSCHECK -> LIST.

### Kroki / Steps

```bash
# Na prim01 jako oracle (zaklada katalog gotowy ze Sprintu 1)

# 1) Sprawdz status katalogu
sqlplus rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<<'SELECT name, dbid FROM rc_database;'
# Oczekiwane: PRIM widoczny

# 2) FULL backup (do 30 min)
bash /tmp/scripts/rman_full_backup.sh

# 3) Crosscheck + cleanup
bash /tmp/scripts/rman_crosscheck.sh

# 4) Lista backupow w katalogu
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<<'LIST BACKUP SUMMARY;'
```

### 📝 Manual RMAN commands (alternative to scripts)

Bez wrappera — surowe komendy do skopiowania po `rman target / catalog ...`:

```rman
# FULL L0 + ARCHIVELOG (zamiast rman_full_backup.sh)
BACKUP INCREMENTAL LEVEL 0 AS COMPRESSED BACKUPSET TAG 'manual_b1' DATABASE PLUS ARCHIVELOG;

# Crosscheck + cleanup (zamiast rman_crosscheck.sh)
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
DELETE NOPROMPT OBSOLETE;

# Lista
LIST BACKUP SUMMARY;
REPORT SCHEMA;
EXIT
```

### Oczekiwane wyniki

- ✅ FULL backup zakonczony bez bledow
- ✅ /mnt/rman_bck/full/ ma pliki backupset
- ✅ LIST BACKUP pokazuje rekordy z TAG=`weekly_l0_YYYYMMDD`
- ✅ W `RC_BACKUP_SET`: typ `I lvl=0` (database) + `L` (archivelog) + `D` (controlfile autobackup) — **wszystkie STATUS=A** (lesson #22)

---

## <a id="b-2"></a>🔹 B-2: Tygodniowy cykl backupow

**Cel:** Zasymulowac 7-dniowy cykl: niedziela L0 + Pn-Sb L1 + arch co 15 min.

### Kroki — szybka demonstracja (1h zamiast 7 dni)

```bash
# Modyfikujemy cron dla demo (tymczasowo):
# zamiast '0 2 * * 0' uzyj 'NOW' dla 1 wykonania

# 1) FULL L0 (jeden raz)
bash /tmp/scripts/rman_full_backup.sh

# 2) Wymus rotacje 5 archlogow zeby cos bylo do backupu
sqlplus / as sysdba <<'SQL'
ALTER SYSTEM SWITCH LOGFILE; ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE; ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
SQL

# 3) ARCHIVELOG backup
bash /tmp/scripts/rman_archivelog_only.sh

# 4) Symulacja "dzien 1" - L1 incremental
bash /tmp/scripts/rman_incremental_l1.sh

# 5) Health check
sqlplus rman_cat/...@rcat01:1521/RCATPDB @/tmp/sql/20_health_checks.sql
```

### Oczekiwane wyniki

- ✅ 3 typy backupow widoczne (full, incr, arch) w `LIST BACKUP SUMMARY`
- ✅ Ratio sukcesu w health_check #6 = 100%
- ✅ Rozmiar /mnt/rman_bck mozna policzyc per typ

---

## <a id="b-3"></a>🔹 B-3: Incremental Merge (Virtual Full Backup)

**Cel:** Pokazac ZDLRA-like incremental-forever pattern.

### Kroki

```bash
# Na prim01 jako oracle

# 1) Init (jeden raz)
bash /tmp/scripts/zdlra_sim_setup.sh --init

# 2) Symulacja "dzien 2" — wykonaj merge
# Wymus jakies zmiany w bazie (UPDATE jakiejs tabeli)
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
INSERT INTO test_table VALUES (...) WHERE rownum <= 1000;
COMMIT;
SQL

bash /tmp/scripts/zdlra_sim_setup.sh --merge

# 3) Status
bash /tmp/scripts/zdlra_sim_setup.sh --status

# 4) Validate (ze sprawdzeniem ze image copy jest aktualny)
rman target / catalog rman_cat/...@rcat01:1521/RCATPDB <<'RMAN'
LIST COPY OF DATABASE TAG 'incr_merge';
RESTORE DATABASE PREVIEW SUMMARY;
RMAN
```

### 📝 Manual RMAN commands

> 💡 **Pełen wzorzec virtual full backup w manualnej formie jest opisany w [doc 07 sekcja "Manualne polecenia RMAN"](07_ZDLRA_Like_Simulation_PL.md#-manualne-polecenia-rman-copypaste-bez-wrappera).** Tutaj skrót:

```rman
# Initial L0 IMAGE COPY (jednorazowo zamiast --init):
BACKUP INCREMENTAL LEVEL 0 AS COPY TAG 'incr_merge' DATABASE
  FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';

# Daily merge cycle (zamiast --merge):
RECOVER COPY OF DATABASE WITH TAG 'incr_merge';
BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'incr_merge'
  DATABASE FORMAT '/mnt/rman_bck/incr_merge/incr_%d_%U';

# Validate
LIST COPY OF DATABASE TAG 'incr_merge';
RESTORE DATABASE PREVIEW SUMMARY;
```

### Oczekiwane wyniki

- ✅ Po init: image copy ma rozmiar bazy (~50 GB nieskompresowane)
- ✅ Po merge: image copy ma nowy timestamp (jak swiezy L0)
- ✅ RESTORE PREVIEW pokazuje image copy jako PRIMARY source
- ✅ W katalogu (lesson #22): `RC_DATAFILE_COPY` ma wpis z `TAG='INCR_MERGE'` i biezacy `creation_time`

---

## <a id="b-4"></a>🔹 B-4: PITR po DROP TABLE

**Cel:** "Klasyczny scenariusz" - user przypadkowo usunal tabele, recovery do SCN przed.

### Kroki

```bash
# 1) Pre-state: notuj SCN przed DROP
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
SELECT current_scn FROM v$database;  -- np. 1234567
EXIT
SQL
SCN_BEFORE=1234567  # ZAPISZ TO

# 2) Backup state przed
bash /tmp/scripts/rman_full_backup.sh
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
ALTER SYSTEM SWITCH LOGFILE; ALTER SYSTEM SWITCH LOGFILE;
SQL
bash /tmp/scripts/rman_archivelog_only.sh

# 3) "Akcydent" - DROP TABLE (jako user, nie sys!)
sqlplus app_user/...@prim:1521/APPPDB <<'SQL'
DROP TABLE critical_data;
SQL

# 4) PITR do SCN_BEFORE
bash /tmp/scripts/rman_restore_pitr.sh --pdb APPPDB --scn $SCN_BEFORE

# 5) Walidacja
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
SELECT COUNT(*) FROM critical_data;  -- powinno byc dane
SQL
```

### 📝 Manual RMAN commands (PITR pojedynczego PDB)

```rman
# Krok 1: Zamknij PDB (ale nie cala instancje!)
ALTER PLUGGABLE DATABASE APPPDB CLOSE IMMEDIATE;

# Krok 2: PITR do SCN_BEFORE (np. 1234567)
RUN {
  SET UNTIL SCN 1234567;
  RESTORE PLUGGABLE DATABASE APPPDB;
  RECOVER PLUGGABLE DATABASE APPPDB;
}

# Krok 3: Open RESETLOGS (wymagane po PITR)
ALTER PLUGGABLE DATABASE APPPDB OPEN RESETLOGS;
```

> 💡 **Alternatywnie do timestamp** (bardziej intuicyjne):
> ```rman
> SET UNTIL TIME "TO_DATE('2026-05-04 14:30:00','YYYY-MM-DD HH24:MI:SS')";
> ```

> ⚠️ **PITR pojedynczego PDB w 23ai/26ai** wymaga `BACKUP DATABASE INCLUDE CURRENT CONTROLFILE` (default w naszym `rman_full_backup.sh`). Bez tego CDB nie ma snapshot controlfile-a dla tego PDB.

### Oczekiwane wyniki

- ✅ Tabela `critical_data` istnieje po PITR
- ✅ Dane do SCN_BEFORE zachowane
- ✅ Wszystkie zmiany PO SCN_BEFORE utracone (RESETLOGS)
- ✅ Nowy `incarnation#` w `v$pdb_incarnation` (per-PDB resetlogs)

---

## <a id="b-5"></a>🔹 B-5: Online tablespace recovery

**Cel:** Pokazac ze pojedynczy tablespace mozna odzyskac BEZ zatrzymania PDB.

### Kroki

```bash
# 1) Symuluj uszkodzenie pliku (jako root)
sudo dd if=/dev/zero of=/u02/oradata/PRIM/apppdb/users01.dbf bs=8192 count=10 conv=notrunc
# (zniszczone pierwsze 80 KB - blok corruption)

# 2) Sprawdz alert log - powinny byc bledy ORA-1578 (corrupt block)
sudo tail -50 /u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log | grep -i corrupt

# 3) Tablespace recovery
bash /tmp/scripts/rman_restore_tablespace.sh --pdb APPPDB --ts USERS

# 4) Walidacja
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
SELECT name, status FROM v$datafile WHERE name LIKE '%users01%';
-- STATUS=ONLINE
SQL
```

### Oczekiwane wyniki

- ✅ Tablespace USERS znow ONLINE
- ✅ Inne tablespaces NIE byly dotkniete
- ✅ APPPDB pozostal otwarty caly czas

---

## <a id="b-6"></a>🔹 B-6: Disaster recovery — utrata controlfile + spfile

**Cel:** Najgorszy scenariusz - tracimy oba krytyczne pliki konfiguracyjne.

### Kroki

```bash
# 1) Zapisz DBID (krytyczne!)
DBID=$(sqlplus -S / as sysdba <<<'SET HEADING OFF FEEDBACK OFF; SELECT dbid FROM v$database;')
echo "DBID = $DBID"  # ZAPISZ TO

# 2) Symuluj loss
sqlplus / as sysdba <<'SQL'
SHUTDOWN ABORT;
EXIT
SQL
sudo rm /u02/oradata/PRIM/control01.ctl
sudo rm /u01/app/oracle/product/23.26/dbhome_1/dbs/spfilePRIM*.ora

# 3) Restore z autobackup
bash /tmp/scripts/rman_restore_controlfile.sh --dbid $DBID

# 4) Walidacja
sqlplus / as sysdba <<'SQL'
SELECT name, open_mode FROM v$database;
SELECT count(*) FROM v$datafile;
SQL
```

### 📝 Manual RMAN commands (najgorszy scenariusz — pełny restore)

```rman
# Krok 1: Connect bez TARGET (bo CDB jeszcze nie istnieje)
# z hosta uruchom: rman catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"

SET DBID 229119773;   # podstaw swoj DBID z $DBID

# Krok 2: Startup nomount z restored spfile
STARTUP NOMOUNT FORCE;
RESTORE SPFILE FROM AUTOBACKUP;

# Krok 3: Restartuj NOMOUNT z restored spfile
STARTUP FORCE NOMOUNT;
RESTORE CONTROLFILE FROM AUTOBACKUP;

# Krok 4: Mount + restore + recover
ALTER DATABASE MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN RESETLOGS;
```

> 💡 **Klucz do sukcesu:** musisz znać DBID **przed** awarią (`SELECT dbid FROM v$database`). Bez DBID restore z autobackup jest niemożliwy. **Zapisuj DBID po każdej zmianie struktury** (np. w `${HOME}/dbid.txt`).

> ⚠️ **Lesson #21:** rman_cat user potrzebuje EXECUTE na DBMS_LOCK (pre-check w sekcji wspólnej powyżej), inaczej RESTORE CONTROLFILE failuje na catalog connection.

### Oczekiwane wyniki

- ✅ Baza otwarta w trybie RESETLOGS
- ✅ Wszystkie datafiles widoczne
- ✅ Nowa incarnation w v$database_incarnation
- ✅ `RC_DATABASE_INCARNATION` na rcat01 ma nowy wpis z `RESETLOGS_TIME` ostatniego openu

---

## <a id="b-7"></a>🔹 B-7: Rebuild STBY01 z backupu

**Cel:** Pokazac ze gdy stby01 padnie kompletnie, mozna go odbudowac z backupu RMAN
(zamiast Active Duplicate ktory wymaga sieciowego transferu z PRIM).

### Kroki

```bash
# 1) Symuluj catastrophic failure stby01
ssh root@stby01 'systemctl stop oracle-rcat || true; rm -rf /u02/oradata/STBY/*'

# 2) Na stby01: startup NOMOUNT z dummy initfile
ssh oracle@stby01 << 'EOF'
cat > /tmp/init_dummy.ora <<INIT
db_name='STBY'
db_unique_name='STBY'
INIT
sqlplus / as sysdba <<SQL
STARTUP NOMOUNT PFILE='/tmp/init_dummy.ora';
EXIT
SQL
EOF

# 3) Z prim01: DUPLICATE FOR STANDBY FROM BACKUPSET
ssh oracle@prim01 << 'EOF'
rman target / auxiliary sys/${LAB_PASS}@stby01:1521/STBY catalog rman_cat/...@rcat01:1521/RCATPDB <<RMAN
DUPLICATE TARGET DATABASE FOR STANDBY FROM BACKUPSET;
RMAN
EOF

# 4) Re-enable Data Guard
ssh oracle@stby01 'dgmgrl sys/...@stby <<<"ENABLE DATABASE STBY;"'

# 5) Walidacja apply
ssh oracle@stby01 'sqlplus / as sysdba <<<"SELECT process, status FROM v\$managed_standby;"'
```

### 📝 Manual RMAN commands (DUPLICATE FOR STANDBY)

```rman
# Connect z prim01: TARGET=PRIM, AUXILIARY=stby01 NOMOUNT, CATALOG=rcat01
# rman target / auxiliary "sys/${LAB_PASS}@stby01:1521/STBY" \
#                catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"

DUPLICATE TARGET DATABASE FOR STANDBY
  FROM BACKUPSET
  DORECOVER
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='STBY'
    SET local_listener=''
    SET fal_server='PRIM'
    SET log_archive_dest_2='SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM';
```

> 💡 **`FROM BACKUPSET` vs Active Duplicate:** różnica = źródło danych. BACKUPSET czyta z `/mnt/rman_bck/full/` (offline-friendly, brak obciążenia PRIM). Active ciągnie blok-po-bloku przez sieć z aktywnej bazy PRIM (online).

> ⚠️ **DORECOVER** jest kluczowe — bez tego standby będzie behind PRIM o czas trwania DUPLICATE. DORECOVER aplikuje archlogi do recovery point z momentu uruchomienia DUPLICATE.

### Oczekiwane wyniki

- ✅ stby01 odbudowany BEZ obciazenia PRIM (Active Duplicate by ciagnal data z PRIM live)
- ✅ Data Guard apply RESUMED
- ✅ Switchover test po rebuild dzialá

### Roznica vs Active Duplicate

| Metoda | I/O na PRIM | Czas | Szansa na blad |
|---|---|---|---|
| Active Duplicate (existing) | wysokie (50 GB read z PRIM) | wolniej | sredni (network glitches) |
| Duplicate FROM BACKUPSET | brak (read z /mnt/rman_bck) | szybciej | nizsze (offline-friendly) |

---

## <a id="b-8"></a>🔹 B-8: Test environment refresh

**Cel:** Realny use-case DBA - co tydzien refreshujemy srodowisko TEST z najnowszego PROD backup.

### Kroki

```bash
# Pre-reqs:
# - Aux VM 'test01' (192.168.56.17, ORACLE_HOME pusty)
# - test01:1521/TEST dostepny

# 1) Aux VM startup NOMOUNT
ssh oracle@test01 << 'EOF'
sqlplus / as sysdba <<SQL
STARTUP NOMOUNT PFILE='/tmp/init_test.ora';
EXIT
SQL
EOF

# 2) DUPLICATE FROM BACKUPSET (PRIM -> TEST)
bash /tmp/scripts/rman_duplicate_for_test.sh \
    --aux test01:1521/TEST \
    --target_db PRIM \
    --new_name TEST

# 3) Walidacja
ssh oracle@test01 'sqlplus / as sysdba <<<"SELECT name, db_unique_name FROM v\$database;"'
# Oczekiwane: NAME=TEST, db_unique_name=TEST
```

### 📝 Manual RMAN commands (DUPLICATE TARGET = test refresh)

```rman
# Connect z prim01: TARGET=PRIM, AUXILIARY=test01 NOMOUNT, CATALOG=rcat01

DUPLICATE TARGET DATABASE TO TEST
  FROM BACKUPSET
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='TEST'
    SET db_name='TEST'
    SET log_archive_dest_2=''
    SET fal_server=''
    SET log_archive_dest_1='LOCATION=/u02/oradata/TEST/arch';
```

> 💡 **Różnica vs B-7 (FOR STANDBY):** brak `FOR STANDBY` + `DORECOVER` → RMAN tworzy nową bazę (nowy DBID, nowa role=PRIMARY). Idealne dla test/dev refresh.

### Oczekiwane wyniki

- ✅ Nowa baza TEST otwarta
- ✅ Schemat danych identyczny z PRIM (na moment backup)
- ✅ Cykliczne odswiezanie mozliwe (DELETE TEST + DUPLICATE)
- ✅ TEST ma własny DBID (NIE ten sam co PRIM, w przeciwieństwie do FOR STANDBY)

---

## 📊 Podsumowanie / Summary

Po wykonaniu wszystkich 8 scenariuszy mamy validated full backup/restore workflow:
- ✅ Cykl backup (B-1, B-2)
- ✅ Optymalizacja storage (B-3)
- ✅ Logical recovery (B-4)
- ✅ Granular recovery (B-5)
- ✅ Disaster recovery (B-6)
- ✅ DG integration (B-7)
- ✅ Real-world DBA tasks (B-8)

To pokrywa **80%** typowych scenariuszy ktore real ZDLRA tez obsluguje.

## 🔮 Out of Scope: Zero RPO recovery (B-9 — opcjonalny)

[PL] Pozostałe **~20%** funkcjonalności real ZDLRA to **Zero RPO recovery** — recovery do ostatniej zatwierdzonej transakcji *bez* czekania na archivelog switch. W tym LAB-ie ten scenariusz **NIE jest uruchomiony**, bo wymaga real-time redo do rcat01 (ORA-16009 — patrz [Lesson #29](07_ZDLRA_Like_Simulation_PL.md#-lesson-29-real-time-redo-do-rcat01--architectural-limit)).

[EN] The remaining **~20%** of real ZDLRA functionality is **Zero RPO recovery** — recovery to the last committed transaction *without* waiting for an archivelog switch. In this LAB this scenario is **NOT enabled** because it requires real-time redo to rcat01 (ORA-16009 — see [Lesson #29](07_ZDLRA_Like_Simulation.md#-lesson-29-real-time-redo-to-rcat01--architectural-limit)).

> 💡 **Możliwe rozszerzenie / Possible extension:** zbudowanie physical standby PRIM na rcat01 (Sprint 5 opcjonalny) odblokowuje DEST_3 + scenariusz **B-9 Zero RPO recovery**. Pełen plan kroków + RMAN DUPLICATE block + cost/benefit:
> [doc 07 sekcja "Możliwe rozszerzenie LAB"](07_ZDLRA_Like_Simulation_PL.md#-możliwe-rozszerzenie-lab-sprint-5-opcjonalny--physical-standby-prim-na-rcat01) (PL) /
> [doc 07 section "Possible LAB extension"](07_ZDLRA_Like_Simulation.md#-possible-lab-extension-sprint-5-optional--physical-standby-of-prim-on-rcat01) (EN).
>
> **Decyzja / Decision:** udokumentowane ale **nie zaplanowane** — practical workaround dla ~15 min RPO (`rman_archivelog_only.sh` cron) wystarcza dla obecnych celów LAB-u. / Documented but **not planned** — practical workaround for ~15 min RPO (`rman_archivelog_only.sh` cron) suffices for current LAB goals.

## <a id="troubleshooting"></a>🚧 Troubleshooting (lessons learned dla scenariuszy)

[PL] Najczęstsze problemy które mogą wystąpić podczas wykonywania scenariuszy B-1..B-8. Wszystkie zostały zweryfikowane empirycznie podczas Iter.10-12 (2026-05-03/04).

| Problem | Rozwiazanie | Lesson |
|---|---|---|
| `RMAN-02001 unrecognized punctuation symbol "-"` | RMAN nie obsluguje `--` jako komentarza. Uzyj `#` w plikach `.sql` ORAZ w bash heredoc-ach | #20 |
| `PLS-00201: identifier 'DBMS_LOCK' must be declared` | `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat` w PDB RCATPDB | #21 |
| `BACKUP DATABASE PLUS ARCHIVELOG` robi tylko archivelogi, baza NIE | Lesson #21 (DBMS_LOCK) — catalog rejestracja blokowana, RMAN nie kontynuuje do DATABASE phase | #21 |
| `RMAN-20002 target database already registered` | OK przy re-run REGISTER. `UNREGISTER DATABASE x NOPROMPT` + ponowny REGISTER albo zostaw (idempotent skip) | #16 |
| Skrypt rman_*.sh nic nie pokazuje, log file pusty | `set -u` + `source ~/.bash_profile` cichy crash. Wrap source w `set +u; source ...; set -u` (v1.2 fix) | #24 |
| `bash /tmp/scripts/...` failuje z `Permission denied` | `/tmp/scripts/` owned by root. Workaround: scp do `/tmp/` + sudo cp do `/tmp/scripts/` | #19 |
| `RC_BACKUP_SET` query failuje z `OUTPUT_BYTES invalid identifier` | W 26ai `RC_BACKUP_SET` nie ma kolumn bytes. JOIN do `RC_BACKUP_PIECE` po `bs_key` | #22 |
| `RC_SITE` query failuje z `DBID invalid identifier` | W 26ai `RC_SITE` nie ma DBID/DB_NAME. JOIN do `RC_DATABASE` po `db_key` | #17 |
| `BACKUP_TYPE='D'` oczekiwany dla FULL ale jest `'I' lvl=0` | W 26ai "FULL" = `INCREMENTAL_LEVEL=0`. Codes: D=Controlfile, I=Incremental, L=Archivelog | #22 |
| Skrypt pyta wielokrotnie o haslo SSH | VM↔VM SSH equiv NIE skonfigurowane. Uruchom `bash /tmp/scripts/ssh_setup.sh` jako root na prim01 | #18 |
| `tnsping rcat01_redo` zwraca "command not found" | W non-login SSH shell PATH nie jest ustawiony. Uzyj `bash -lc 'tnsping ...'` | #13 |
| FSFO failover wykonany — role PRIM/STBY odwrocone | Sprawdz `database_role` na obu nodach. Jesli stby01=PRIMARY a prim01=STANDBY: `dgmgrl 'SWITCHOVER TO PRIM'` przed scenariuszami | (DG) |

## ⏭️ Zobacz takze / See also

- [09_DG_Integration.md](09_DG_Integration_PL.md) — szczegoly integracji Backup ↔ DG
- [10_Troubleshooting.md](10_Troubleshooting_PL.md) — FAQ + znane bledy
