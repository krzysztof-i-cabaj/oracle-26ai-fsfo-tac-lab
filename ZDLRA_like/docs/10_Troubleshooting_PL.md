# 🚧 10 — Troubleshooting (FAQ + Known Issues)

[![Doc](https://img.shields.io/badge/Doc-Troubleshooting-red)]()
[![Coverage](https://img.shields.io/badge/Coverage-Sprints_0%E2%80%933-success)]()
[![FAQ](https://img.shields.io/badge/FAQ-Live-orange)]()

> 🎯 Centralna dokumentacja problemow ktore napotkasz podczas Sprintow 0-3 + ich rozwiazania.

## 📑 Spis tresci / TOC

1. [⭐ TOP — krytyczne lessons learned 2026-05-04 (iter.10-12)](#top-lessons)
2. [Sprint 0 — Boot Automation](#sprint-0)
3. [Sprint 1 — DB Install + Catalog](#sprint-1)
4. [Sprint 2 — Backup Policy](#sprint-2)
5. [Sprint 3 — ZDLRA-like + DG Integration](#sprint-3)
6. [Ogolne / General](#general)

> 💡 **Powiazane troubleshooting per-scenariusz:** [doc 08 troubleshooting tabela](08_Backup_Restore_Scenarios_PL.md#troubleshooting) — 12 wierszy z lessons #13-24 dla scenariuszy B-1..B-8.

---

## <a id="top-lessons"></a>⭐ TOP — krytyczne lessons learned 2026-05-04 (iter.10-12)

[PL] Te 8 problemów najczęściej blokowało setup w sesji 2026-05-04. Każdy znaleziony **live podczas wykonywania**, naprawiony retroactively w skryptach + dokumentacji. Sprawdź najpierw tutaj jeśli coś nie działa.

[EN] These 8 issues most frequently blocked setup in the 2026-05-04 session. Each found **live during execution**, fixed retroactively in scripts + docs. Check here first if something fails.

| Lesson | Symptom | Quick fix |
|---|---|---|
| **#17** | `ORA-00904: "DBID": invalid identifier` przy walidacji RC_SITE | W 26ai `RC_SITE` nie ma DBID/DB_NAME → JOIN do `RC_DATABASE` po `db_key`. [Detale](#sprint-1-rc-site) |
| **#18** | Skrypt `catalog_register_stby.sh` pyta wielokrotnie o hasło SSH | VM↔VM SSH equiv NIE skonfigurowane. `bash /tmp/scripts/ssh_setup.sh` z root@prim01 (wymaga rcat01 w `ORACLE_NODES`). [Detale](#general-ssh-equiv) |
| **#19** | `scp` do `/tmp/scripts/` na rcat01 → `Permission denied` | `/tmp/scripts/` owned by root. Workaround: scp do `/tmp/` + `sudo cp` do `/tmp/scripts/`. [Detale](#general-tmp-scripts) |
| **#20** | `RMAN-02001: unrecognized punctuation symbol "-"` | RMAN nie obsługuje `--` jako komentarz. Użyj `#` w plikach `.sql` ORAZ w bash heredoc-ach. [Detale](#sprint-1-rman-comments) |
| **#21** | `PLS-00201: identifier 'DBMS_LOCK' must be declared` przy każdym `rman target / catalog ...` | `RECOVERY_CATALOG_OWNER` w 26ai NIE daje EXECUTE na DBMS_LOCK. `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;`. [Detale](#sprint-1-dbms-lock) |
| **#22** | `ORA-00904: "OUTPUT_BYTES": invalid identifier` w walidacji `RC_BACKUP_SET` | W 26ai `RC_BACKUP_SET` bez kolumn bytes. JOIN do `RC_BACKUP_PIECE` po `bs_key`. [Detale](#sprint-2-rc-backup-set) |
| **#23** | `bash /tmp/scripts/rman_archivelog_only.sh` → `Permission denied /var/log/...` | Skrypt v1.0 hard-coded `/var/log/`. v1.1+ używa `${HOME}/rman_logs/`. [Detale](#sprint-2-var-log) |
| **#24** | Skrypt nic nie pokazuje, log file pusty | `set -u` + `source ~/.bash_profile` silent crash. Wrap source w `set +u; source ...; set -u`. v1.2+ ma fix. [Detale](#sprint-2-set-u) |

---

## <a id="sprint-0"></a>🔹 Sprint 0 — Boot Automation

### `e` nie wszedl w edit mode (GRUB)

**Symptom:** Po starcie VM zamiast edytora GRUB widac "Install Oracle Linux 8.10" autoboot.

**Przyczyna:** `e` zostal wyslany ZANIM GRUB sie pokazal.

**Rozwiazanie:**
```powershell
.\boot_rcat_via_scancode.ps1 -InitialDelaySec 15
# (default 10s, zwieksz na 15-20s)
```

### Kursor nie trafia w linie `linuxefi`

**Symptom:** Payload dopisuje sie do innej linii, Anaconda startuje TUI bez kickstartu.

**Przyczyna:** `Down` x 2 to za malo — grub.cfg w danej wersji ISO ma wiecej linii.

**Rozwiazanie:**
```powershell
.\boot_rcat_via_scancode.ps1 -DownArrowsCount 3
# Lub sprawdz grub.cfg: mount ISO i `cat /mnt/iso/EFI/BOOT/grub.cfg`
```

### Bufor klawiatury VBox sie przepelnia

**Symptom:** Czesc payloadu znika, GRUB cmdline ma luki.

**Przyczyna:** Wysylanie zbyt szybko (>~256 zdarzen w buforze).

**Rozwiazanie:** Domyslny `-BatchSize 80 -BatchDelayMs 50` w `Send-VBoxKeystrokes` powinien wystarczyc.
Jesli nadal: zmniejsz BatchSize do 40.

### Anaconda nie pobiera kickstart (HTTP 404)

**Symptom:** Anaconda startuje, ale rusza w trybie interaktywnym (TUI).

**Diagnostyka:**
1. Log HTTP: `_RecoveryAppliance_/kickstart/.http_server.log` — szukaj 404
2. W trybie GUI: Ctrl-Alt-F2 w VM, `curl http://192.168.56.1:8000/ks-rcat01.cfg`
3. Sprawdz Host-Only IF: `Get-NetIPAddress -InterfaceAlias "*Host-Only*#2*"`

**Rozwiazania:**
- Sprawdz czy `start_kickstart_http.ps1` faktycznie startuje serwer (`-Status`)
- Sprawdz firewall hosta (Windows Defender Firewall - moze blokowac port 8000)
- Sprawdz literowke w nazwie pliku ks-rcat01.cfg (case-sensitive)

### PS5 fail przy parsowaniu skryptu (UnicodeError)

**Symptom:** `[FAIL] Missing closing '}' in statement block` chociaz skrypt wyglada OK.

**Przyczyna:** Em-dash (—) lub polskie diakrytyki w UTF-8 sa misread przez PS5 (CP1250).

**Rozwiazanie:** Normalize do ASCII przez Python:
```python
text = path.read_text(encoding='utf-8')
fixed = text.translate(str.maketrans({'—': '-', 'ę': 'e', ...}))
path.write_bytes(fixed.encode('utf-8'))
```

---

## <a id="sprint-1"></a>🔹 Sprint 1 — DB Install + Catalog

### `runInstaller` fail prerequisites check

**Symptom:** `[INS-13013] Target environment does not meet some mandatory requirements.`

**Rozwiazanie:** `-ignorePrereqFailure` jest juz w `install_db_silent_rcat.sh`. Sprawdz logi:
```bash
tail -100 /u01/app/oraInventory/logs/installActions*.log
```
Czeste prereqs ktore mozna ignorowac w LAB-ie: SWAP_SIZE, OS_MEMORY, KERNEL_VERSION.

### `dbca` zawiesza sie / OOM

**Symptom:** dbca proces hangs, lub `ORA-04031 unable to allocate ...`

**Przyczyna:** 4 GB RAM jest minimum, dbca + sqlplus + listener moga przekroczyc limit.

**Rozwiazanie:**
```bash
# Obniz SGA target dla DBCA
dbca -silent -createDatabase ... -totalMemory 1024  # zamiast 1536
```

### `oracle-rcat.service` start fail

**Symptom:** `systemctl status oracle-rcat` -> `failed`, `journalctl` pokazuje `dbstart` exit code 1.

**Przyczyna:** Listener juz dziala lub /etc/oratab nie ma flagi Y.

**Rozwiazanie:**
```bash
# Sprawdz /etc/oratab
cat /etc/oratab
# Powinno byc: RCAT:/u01/app/oracle/product/23.26/dbhome_1:Y

# Jesli flaga N:
sudo sed -i 's|^RCAT:.*|RCAT:/u01/app/oracle/product/23.26/dbhome_1:Y|' /etc/oratab

# Sprawdz logi
journalctl -u oracle-rcat.service -n 100
```

### Po reboocie listener dziala, ale baza nie

**Symptom:** `lsnrctl status` OK, ale `sqlplus / as sysdba` -> `ORA-12162` lub `ORA-01034`.

**Diagnostyka:**
```bash
# Czy zadne procesy pmon dziala?
ps -ef | grep pmon
# Brak - znaczy baza nie wstala

# Sprawdz alert log
tail -100 /u01/app/oracle/diag/rdbms/rcat/RCAT/trace/alert_RCAT.log
```

**Rozwiazanie:** Manualnie:
```bash
sqlplus / as sysdba <<<'STARTUP;'
```

Jesli nadal blad - sprawdz czy `dbstart` skrypt nie ma problemu (dlugosc ORACLE_HOME etc).

### <a id="sprint-1-dbms-lock"></a>`PLS-00201: identifier 'DBMS_LOCK' must be declared` (Lesson #21)

**Symptom:** Każde `rman target / catalog rman_cat/...@rcat01:1521/RCATPDB` zwraca:
```
Oracle error from recovery catalog database: ORA-06550: line 1, column 7:
PLS-00201: identifier 'DBMS_LOCK' must be declared
Acquiring a lock for upgrade command has failed. Retrying to get the lock
```

Konsekwencja: `BACKUP DATABASE PLUS ARCHIVELOG` robi tylko fazę archivelog (faza database blokowana — `/mnt/rman_bck/full/` PUSTY mimo że arch jest).

**Przyczyna:** W 26ai role `RECOVERY_CATALOG_OWNER` **NIE** daje automatycznie `EXECUTE ON SYS.DBMS_LOCK`. Standardowy doc Oracle (Note 2435950.1) wymienia ten grant osobno, ale `01_create_catalog_schema.sql` v1.0 go pominął.

**Rozwiazanie:**
```bash
ssh oracle@rcat01 'bash -lc "
sqlplus -S / as sysdba <<EOF
ALTER SESSION SET CONTAINER=RCATPDB;
GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;
SELECT grantee, table_name, privilege FROM dba_tab_privs WHERE grantee=\"RMAN_CAT\" AND table_name=\"DBMS_LOCK\";
EXIT
EOF"'
# Oczekiwane: 1 wiersz RMAN_CAT / DBMS_LOCK / EXECUTE
```

Dla nowych setupów: `01_create_catalog_schema.sql` v1.1+ zawiera ten grant (zaktualizowany 2026-05-04).

---

### <a id="sprint-1-rman-comments"></a>`RMAN-02001: unrecognized punctuation symbol "-"` (Lesson #20)

**Symptom:** Skrypt `.sql` lub bash heredoc do RMAN failuje:
```
RMAN-00558: error encountered while parsing input commands
RMAN-01006: error signaled during parse
RMAN-02001: unrecognized punctuation symbol "-"
```

Często z kaskadą: `ALLOCATE CHANNEL c1 ... expecting "for"` (RUN block zerwany po `--`, każda kolejna linia interpretowana jako standalone).

**Przyczyna:** RMAN **NIE obsługuje** `--` jako komentarza. Tylko `#` jest valid. Dotyczy:
1. Plików `.sql` wywoływanych przez `@file.sql` w RMAN
2. Bash heredoc-ów do RMAN (`<<RMAN ... --komentarz... RMAN`)

**Rozwiazanie:** Audit + replace:
```bash
# Sprawdz pliki .sql idace do RMAN (header `Uzycie: rman target / @file.sql`)
grep -l '^--' /tmp/sql/*.sql

# Zamien -- na # (zachowaj wcięcia)
sed -i 's/^\(\s*\)-- /\1# /' /tmp/sql/file.sql

# Sprawdz bash heredoc-i
grep -A 100 '<<RMAN' /tmp/scripts/rman_*.sh | grep '^--'
```

Dla naszych plików: `sql/03/04/05/10/99` v1.1+ + 8 skryptów `rman_*.sh` v1.1+ mają ten fix (zaktualizowane 2026-05-04).

---

### <a id="sprint-1-rc-site"></a>`ORA-00904: "DBID": invalid identifier` w walidacji RC_SITE (Lesson #17)

**Symptom:** Po `catalog_register_stby.sh`, query walidacyjny:
```sql
SELECT db_key, db_unique_name, db_name, dbid FROM rc_site;
```
zwraca `ORA-00904: "DBID": invalid identifier`.

**Przyczyna:** W 26ai widok `RC_SITE` ma tylko 4 kolumny "publiczne":
- SITE_KEY
- DB_KEY (FK do RC_DATABASE)
- DATABASE_ROLE
- DB_UNIQUE_NAME

Brak DBID i DB_NAME (są w `RC_DATABASE`). To zredukowany schemat względem starszych wersji.

**Rozwiazanie:** JOIN do `RC_DATABASE`:
```sql
SELECT s.site_key, s.db_unique_name, s.database_role, d.name AS db_name, d.dbid
  FROM rc_site s
  JOIN rc_database d ON s.db_key = d.db_key
 ORDER BY s.db_unique_name;
-- 2 wiersze: PRIM (site=3) i STBY (site=566), ten sam DBID
```

Analogicznie inne widoki w 26ai mają zredukowany schemat — patrz lesson #22 dla `RC_BACKUP_SET`.

---

### REGISTER DATABASE z PRIM nie dziala (timeout/refused)

**Symptom:** `RMAN-04004: error from recovery catalog database: ORA-12541: TNS:no listener`

**Diagnostyka:**
```bash
# Z PRIM
tnsping rcat01:1521/RCATPDB
# Powinno byc OK

# Sprawdz reachability
ping rcat01.lab.local
nc -zv 192.168.56.16 1521
```

**Rozwiazanie:**
- Sprawdz `lsnrctl status` na rcat01 - czy serwis RCATPDB jest registered
- Sprawdz `listener.ora` na rcat01 ma poprawny HOST=rcat01 (lub IP)
- Sprawdz firewall na rcat01 (powinien byc disabled w LAB)

---

## <a id="sprint-2"></a>🔹 Sprint 2 — Backup Policy

### `ORA-19809 limit exceeded for recovery files`

**Symptom:** Backup fail, FRA na PRIM przepelnione archlogami.

**Rozwiazanie:**
```bash
# Doraznie: backup arch + delete
bash /tmp/scripts/rman_archivelog_only.sh

# Albo zwieksz FRA size
sqlplus / as sysdba <<'SQL'
ALTER SYSTEM SET db_recovery_file_dest_size=20G SCOPE=BOTH;
SQL
```

### Backup trwa znacznie dluzej niz spodziewane

**Symptom:** FULL backup 50 GB DB trwa >2h.

**Przyczyna:** vboxsf shared folder ma znacznie nizsze IOPS niz natywny dysk Linux.

**Rozwiazanie:**
- Zmniejsz PARALLELISM do 2 (zamiast 4) - paradoksalnie czasem szybciej
- Sprawdz host disk I/O (D:\ moze byc HDD nie SSD)
- Rozwaz `BACKUP AS UNCOMPRESSED BACKUPSET` - kompresja bierze CPU

### `RMAN-03002` w cron job

**Symptom:** Backup z cron failuje, ale recznie OK.

**Przyczyna:** Cron nie ma zaladowanego `~/.bash_profile`.

**Rozwiazanie:** Skrypty `rman_*.sh` maja `source /home/oracle/.bash_profile` - sprawdz czy w skrypcie cron-friendly.

```bash
# /var/spool/cron/oracle (na prim01)
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
PATH=$ORACLE_HOME/bin:$PATH

*/15 * * * * /home/oracle/scripts/rman_archivelog_only.sh
```

### <a id="sprint-2-rc-backup-set"></a>`ORA-00904: "OUTPUT_BYTES": invalid identifier` w RC_BACKUP_SET (Lesson #22)

**Symptom:** Walidacja po backupie:
```sql
SELECT input_bytes/1024/1024, output_bytes/1024/1024 FROM rc_backup_set;
```
zwraca `ORA-00904: "OUTPUT_BYTES": invalid identifier`.

**Przyczyna:** W 26ai `RC_BACKUP_SET` ma 23 kolumny ale **bez** `INPUT_BYTES`, `OUTPUT_BYTES`, `COMPRESSION_RATIO`. Bytes są agregowane per-piece w `RC_BACKUP_PIECE.BYTES`. Analogicznie do lesson #17 (RC_SITE bez DBID).

**Bonus diagnostyka:** `BACKUP DATABASE` w 26ai zwraca `BACKUP_TYPE='I' INCREMENTAL_LEVEL=0`, NIE `'D'`. Codes:
- **D** = Controlfile autobackup
- **I** = Incremental (Level 0 = klasyczne "FULL")
- **L** = Archivelog

**Rozwiazanie:** JOIN do RC_BACKUP_PIECE:
```sql
SELECT s.backup_type, COUNT(*) AS pieces,
       ROUND(SUM(p.bytes)/1024/1024,1) AS total_mb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.start_time > SYSDATE - 1/24
 GROUP BY s.backup_type
 ORDER BY 1;
```

Dla image copies (typ COPY, nie BACKUPSET) użyj `RC_DATAFILE_COPY`:
```sql
SELECT name, ROUND(blocks*block_size/1024/1024,1) AS mb FROM rc_datafile_copy WHERE tag = 'INCR_MERGE';
```

---

### <a id="sprint-2-var-log"></a>`bash rman_archivelog_only.sh: /var/log/...: Permission denied` (Lesson #23)

**Symptom:**
```
/tmp/scripts/rman_archivelog_only.sh: line 37: /var/log/rman_arch_20260504.log: Permission denied
```

**Przyczyna:** `rman_archivelog_only.sh` v1.0 zaprojektowany pod cron miał hard-coded `LOG_FILE=/var/log/rman_arch_*.log` + `exec >> "$LOG_FILE" 2>&1`. Oracle nie ma write do `/var/log/` (typowe dla restricted Linux). Dotyczy tylko tego skryptu (pozostałe rman_*.sh piszą do stdout).

**Rozwiazanie:** v1.1+ używa `LOG_DIR="${LOG_DIR:-${HOME}/rman_logs}"` z auto-mkdir. Manualny re-deploy:
```bash
scp scripts/rman_archivelog_only.sh oracle@prim01:/tmp/
ssh root@prim01 'cp /tmp/rman_archivelog_only.sh /tmp/scripts/ && chmod +x /tmp/scripts/rman_archivelog_only.sh'
```

Dla cron deployment z central log `/var/log/rman_arch.log`:
```bash
sudo touch /var/log/rman_arch.log && sudo chown oracle:oinstall /var/log/rman_arch.log
# W crontab oracle:
LOG_DIR=/var/log */15 * * * * /tmp/scripts/rman_archivelog_only.sh
```

---

### <a id="sprint-2-set-u"></a>Skrypt rman_*.sh nic nie pokazuje, log file pusty (Lesson #24)

**Symptom:**
```bash
$ bash /tmp/scripts/rman_archivelog_only.sh
$
# (prompt wraca natychmiast, brak outputu)
```

Log file `~/rman_logs/rman_arch_*.log` PUSTY (lub urywa się tuż przed `source bash_profile`).

**Przyczyna:** `set -euo pipefail` aktywne. Linia `source /home/oracle/.bash_profile 2>/dev/null || true`:
- `2>/dev/null` zjada error message
- `|| true` ratuje przed `set -e` (exit on error)
- **NIE ratuje przed `set -u`** (unset variable error)

`.bash_profile` typowo używa nieustawionych zmiennych (np. `[ -z "$ORACLE_SID" ]` gdy ORACLE_SID unset). Pod `set -u` to wywala source z `unbound variable`. Process exit przed flush bufora po `exec >> $LOG_FILE`.

**Diagnostyka silent crash-a:**
```bash
bash -x /tmp/scripts/rman_archivelog_only.sh 2>&1 | head -25
# Pokaz ostatnia udana komenda (zwykle 'source /home/oracle/.bash_profile')
```

**Rozwiazanie:** v1.2+ ma fix:
```bash
set +u
source /home/oracle/.bash_profile 2>/dev/null || true
set -u
```

Plus dodano `echo "Logging to $LOG_FILE"` PRZED `exec >> $LOG_FILE` żeby user widział lokalizację loga.

---

### Crosscheck pokazuje `EXPIRED`

**Symptom:** `LIST BACKUP` pokazuje wiele backupow ze statusem EXPIRED.

**Przyczyna:** Pliki usuniete recznie z dysku (lub vboxsf rozsynchronizowany).

**Rozwiazanie:** `rman_crosscheck.sh` zawiera `DELETE EXPIRED` - powinien to czyscic.
Sprawdz czy /mnt/rman_bck jest faktycznie zmontowany i zsynchronizowany.

---

## <a id="sprint-3"></a>🔹 Sprint 3 — ZDLRA-like + DG Integration

### LOG_ARCHIVE_DEST_3 status = ERROR

**Symptom:** `v$archive_dest` pokazuje status=ERROR, error column ma ORA-...

**Czeste bledy:**

| Error | Przyczyna | Rozwiazanie |
|---|---|---|
| `ORA-12541` | Listener na rcat01 nie dziala | `lsnrctl status` na rcat01, `lsnrctl start` |
| `ORA-12514` | Service `rcat_redo` nie zarejestrowany | Dodaj do listener.ora SID_LIST + `lsnrctl reload` |
| `ORA-1031` | LOG_ARCHIVE_DEST wymaga REDO_TRANSPORT_USER | `CREATE USER`/`GRANT SYSDG` lub uzyj static service `rcat_redo` |
| `ORA-16053` (Lesson #26) | `DB_UNIQUE_NAME rcat_redo is not in the Data Guard Configuration` przy `ALTER LOG_ARCHIVE_DEST_3` | **Najpierw** `ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(PRIM,STBY,rcat_redo)' SCOPE=BOTH;` **potem** ALTER LOG_ARCHIVE_DEST_3. Skrypt `zdlra_sim_setup.sh` v1.2+ ma fix proactively |
| `ORA-16191` (Lesson #27 revised) | `log shipping client unable to log onto target database` — **prawdziwy root cause:** pwfile binary mismatch między PRIM a rcat01. Każde `ALTER USER` generuje hash z różnym salt — nawet po Lesson #27 fix (sync plain text hasła) pwfile binary różny. DG redo transport (TT00/TT04) wymaga **literalnie identycznych pwfiles**. | **PRIM RAC ma pwfile na ASM** (`+DATA/PRIM/PASSWORD/pwdprim.*`). Eksport: `DBMS_FILE_TRANSFER.COPY_FILE` z `+DATA/PRIM/PASSWORD` do `/tmp` na PRIM. Potem scp na rcat01 + replace `$ORACLE_HOME/dbs/orapwRCAT`. Verify: md5sum musi być IDENTYCZNY. **Pełen log:** [autonomous_dest3_log_PL.md](../autonomous_dest3_log_PL.md) |
| `ORA-16009` (Lesson #29) | `invalid redo transport destination` — występuje PO fix-ie pwfile binary (Lesson #27 revised). Oracle DG redo transport wymaga **physical standby** target (identyczny db_name + dbid), nie dowolnej Oracle DB. | **Architectural limit — nie do obejścia w LAB-ie bez full standby setup-u.** RCAT (db_name=RCAT, dbid=różny od PRIM) NIE może być real-time redo destination dla PRIM. Decyzja: `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=DEFER SCOPE=BOTH;` + practical workaround = `rman_archivelog_only.sh` cron na PRIM (archlogi w shared folder). Zachowuje esencję ZDLRA-Like (image copy + L1 incremental merge). **Możliwe rozszerzenie:** physical standby PRIM na rcat01 jako Sprint 5 opcjonalny — patrz [doc 07 sekcja "Możliwe rozszerzenie LAB"](07_ZDLRA_Like_Simulation_PL.md#-możliwe-rozszerzenie-lab-sprint-5-opcjonalny--physical-standby-prim-na-rcat01). |
| `ORA-16191` (Lesson #28, kandydat #2) | `log shipping client unable to log onto target database` MIMO że SYS auth działa (Test 3.1 sqlplus -L OK). Mismatch między `DB_UNIQUE_NAME=` w `LOG_ARCHIVE_DEST_3` a faktycznym `db_unique_name` target bazy z `v$database`. | Sprawdz: `SELECT db_unique_name FROM v$database` na rcat01 (= `RCAT`, NIE `rcat_redo`). W DEST_3 zmień `DB_UNIQUE_NAME=rcat_redo` na `DB_UNIQUE_NAME=RCAT` + `DG_CONFIG=(PRIM,STBY,RCAT)`. **Naprawione w `zdlra_sim_setup.sh` v1.3+** (DB_UNIQUE_NAME=RCAT + DG_CONFIG zawiera RCAT) |

### Image copy rosnie nieproporcjonalnie

**Symptom:** Po `RECOVER COPY OF DATABASE` rozmiar /mnt/rman_bck/incr_merge nie maleje.

**Przyczyna:** Stara wersja image copy nie zostala usunieta (RMAN trzyma ja jako fallback).

**Rozwiazanie:**
```rman
RMAN> DELETE COPY OF DATABASE TAG 'incr_merge' COMPLETED BEFORE 'SYSDATE-3';
```

### Po switchover backup nie dziala

**Symptom:** Cron na prim01 nadal odpala backup, ale prim01 jest teraz STANDBY -> RMAN-06457.

**Rozwiazanie:** Dodaj pre-check role w skrypcie:
```bash
ROLE=$(sqlplus -S / as sysdba <<<'SET HEADING OFF FEEDBACK OFF; SELECT database_role FROM v$database;')
[[ "$ROLE" == *"PRIMARY"* ]] || { log "[skip] Not PRIMARY"; exit 0; }
```

I wstaw cron na **OBYDWU** hostach (prim01 i stby01). Tylko aktualnie PRIMARY uruchomi backup.

### B-7 (rebuild stby) DUPLICATE fail

**Symptom:** `RMAN-05541: no backup of the database to duplicate from`.

**Diagnostyka:**
```rman
LIST BACKUP OF DATABASE FOR DB_UNIQUE_NAME PRIM;
```

**Rozwiazanie:** Musi byc co najmniej 1 FULL backup PRIM zarejestrowany w katalogu.
Najpierw `bash rman_full_backup.sh`, potem rebuild STBY.

---

## <a id="general"></a>🔹 Ogolne / General

### <a id="general-ssh-equiv"></a>VM↔VM SSH equiv NIE skonfigurowane (Lesson #18)

**Symptom:** Skrypty wykonujące SSH/scp pomiędzy VM-ami (`catalog_register_stby.sh`, `catalog_register_prim.sh`) pytają wielokrotnie o hasło `oracle` (3+ razy per operation).

**Przyczyna:** SSH user-equivalency w głównym LAB-ie skonfigurowany dla `oracle` user na `prim01 prim02 stby01 infra01` (przez `VMs2-install/scripts/ssh_setup.sh`), ale **rcat01 nie był w `ORACLE_NODES`**. Operacje rcat01 → prim01/stby01 wymagają hasła.

**Rozwiazanie:**
1. Sprawdź czy `ssh_setup.sh` ma rcat01 (w głównym LAB):
```bash
grep ORACLE_NODES /tmp/scripts/ssh_setup.sh
# Powinno: ORACLE_NODES="prim01 prim02 stby01 infra01 rcat01"
```
2. Jeśli brak — edytuj + uruchom jako root na prim01:
```bash
ssh root@prim01 'bash /tmp/scripts/ssh_setup.sh'
# Idempotent: dorzuca tylko brakujace pary, istniejace pomija
```
3. Verify: 25 par SUCCESS dla `oracle` (5 nodes × 5).

```bash
# Test passwordless rcat01→prim01:
ssh oracle@rcat01 'ssh -o PasswordAuthentication=no oracle@prim01 hostname'
# Oczekiwane: prim01 (bez prompta hasla)
```

---

### <a id="general-tmp-scripts"></a>`/tmp/scripts/` na rcat01 owned by root (Lesson #19)

**Symptom:** `scp` do `/tmp/scripts/` na rcat01 zwraca `Permission denied`.

**Przyczyna:** `/tmp/scripts/` na rcat01 jest tworzony przez deploy z root (kickstart), oracle nie ma write.

**Rozwiazania (3 opcje):**

```bash
# Opcja A: scp do /tmp/ (oracle ma write) + sudo cp
scp file.sh oracle@rcat01:/tmp/
ssh root@rcat01 'cp /tmp/file.sh /tmp/scripts/ && chmod +x /tmp/scripts/file.sh'

# Opcja B: bezposrednio jako root (jesli root SSH equiv jest)
scp file.sh root@rcat01:/tmp/scripts/

# Opcja C: deploy_to_rcat.ps1 (z hosta Windows)
cd ZDLRA_like/scripts
.\deploy_to_rcat.ps1
```

---

### Hasła w skryptach (security concern)

LAB convention: hasło zunifikowane w `/root/.lab_secrets` jako `export LAB_PASS='...'` (chmod 600).
Plik jest tworzony przez kickstart `%post`. Wszystkie skrypty `.sh` w tym podprojekcie mają na początku
blok `[ -r /root/.lab_secrets ] && source /root/.lab_secrets` z walidacją że `$LAB_PASS` nie jest pusty.

W produkcji **nigdy** nie hardkodowac, przejscie na Oracle Wallet:

Migracja na Oracle Wallet (przyklad):
```bash
mkstore -wrl /home/oracle/wallet -create
mkstore -wrl /home/oracle/wallet -createCredential rcat01:1521/RCATPDB rman_cat 'real_password'

# Polacz przez wallet
rman target / catalog rman_cat/@rcat01:1521/RCATPDB
```

Wymaga konfiguracji `sqlnet.ora` z `WALLET_LOCATION` + `SQLNET.WALLET_OVERRIDE=TRUE`.

### Performance: shared folder vboxsf jest wolny

vboxsf w VBox jest implementowany jako FUSE - nizsze IOPS niz natywne dyski.
Dla LAB-u akceptowalne, ale **nie** uzywaj w prod.

W prod: NFS share, iSCSI, Object Storage, ASM.

### Backup files się gubią (vboxsf desync)

**Symptom:** Plik widoczny na hoscie Windows, niewidoczny w VM (lub odwrotnie).

**Rozwiazanie:** Restart Guest Additions:
```bash
sudo systemctl restart vboxadd-service
```

Lub w VM: `sudo umount /mnt/rman_bck && sudo mount /mnt/rman_bck`

### "Catalog is older than target database" (ORA-19909)

**Symptom:** REGISTER DATABASE fail z ORA-19909.

**Przyczyna:** Wersja katalogu < wersja TARGET. W naszym LAB-ie oba 23.26.1, ale jak by byl mismatch:

**Rozwiazanie:**
```bash
# Na PRIM:
rman catalog rman_cat/...@rcat01:1521/RCATPDB
RMAN> UPGRADE CATALOG;
RMAN> UPGRADE CATALOG;  -- 2 razy zgodnie z RMAN docs
```

## 📞 Gdzie szukac dalej / Where to look further

- Alert log PRIM: `/u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log`
- Alert log RCAT: `/u01/app/oracle/diag/rdbms/rcat/RCAT/trace/alert_RCAT.log`
- RMAN session log: w katalogu wywolania, plik `rman_*.log` jesli skrypt redirectuje
- Anaconda log: `/root/anaconda-ks.cfg` + `/root/ks-post.log` (po install)
- VBoxManage log: `D:\VM\rcat01\Logs\VBox.log`
- Health checks SQL: `sql/20_health_checks.sql` (6 zapytan diagnostycznych)
- **Per-scenariusz troubleshooting:** [doc 08 troubleshooting](08_Backup_Restore_Scenarios_PL.md#troubleshooting) (12 wierszy lessons #13-24 dla scenariuszy B-1..B-8)
- **EXECUTION_LOG:** [EXECUTION_LOG_PL.md](../EXECUTION_LOG_PL.md) (chronologiczny log iteracji 1-12 z lessons w kontekście)
