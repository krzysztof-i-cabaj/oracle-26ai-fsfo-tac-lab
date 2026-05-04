# 🚧 10 — Troubleshooting (FAQ + Known Issues)

[![Doc](https://img.shields.io/badge/Doc-Troubleshooting-red)]()
[![Coverage](https://img.shields.io/badge/Coverage-Sprints_0%E2%80%933-success)]()
[![FAQ](https://img.shields.io/badge/FAQ-Live-orange)]()

> 🎯 Central documentation of issues you will encounter during Sprints 0-3 + their resolutions.

## 📑 Table of contents

1. [⭐ TOP — critical lessons learned 2026-05-04 (iter.10-12)](#top-lessons)
2. [Sprint 0 — Boot Automation](#sprint-0)
3. [Sprint 1 — DB Install + Catalog](#sprint-1)
4. [Sprint 2 — Backup Policy](#sprint-2)
5. [Sprint 3 — ZDLRA-like + DG Integration](#sprint-3)
6. [General](#general)

> 💡 **Related per-scenario troubleshooting:** [doc 08 troubleshooting table](08_Backup_Restore_Scenarios.md#troubleshooting) — 12 rows with lessons #13-24 for scenarios B-1..B-8.

---

## <a id="top-lessons"></a>⭐ TOP — critical lessons learned 2026-05-04 (iter.10-12)

These 8 issues most frequently blocked setup in the 2026-05-04 session. Each found **live during execution**, fixed retroactively in scripts + docs. Check here first if something fails.

| Lesson | Symptom | Quick fix |
|---|---|---|
| **#17** | `ORA-00904: "DBID": invalid identifier` in RC_SITE validation | In 26ai `RC_SITE` has no DBID/DB_NAME → JOIN `RC_DATABASE` on `db_key`. [Details](#sprint-1-rc-site) |
| **#18** | Script `catalog_register_stby.sh` prompts repeatedly for SSH password | VM↔VM SSH equiv NOT configured. `bash /tmp/scripts/ssh_setup.sh` from root@prim01 (requires rcat01 in `ORACLE_NODES`). [Details](#general-ssh-equiv) |
| **#19** | `scp` to `/tmp/scripts/` on rcat01 → `Permission denied` | `/tmp/scripts/` owned by root. Workaround: scp to `/tmp/` + `sudo cp` to `/tmp/scripts/`. [Details](#general-tmp-scripts) |
| **#20** | `RMAN-02001: unrecognized punctuation symbol "-"` | RMAN does not accept `--` as comment. Use `#` in `.sql` files AND in bash heredocs. [Details](#sprint-1-rman-comments) |
| **#21** | `PLS-00201: identifier 'DBMS_LOCK' must be declared` on every `rman target / catalog ...` | `RECOVERY_CATALOG_OWNER` in 26ai does NOT grant EXECUTE on DBMS_LOCK. `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;`. [Details](#sprint-1-dbms-lock) |
| **#22** | `ORA-00904: "OUTPUT_BYTES": invalid identifier` in `RC_BACKUP_SET` validation | In 26ai `RC_BACKUP_SET` has no byte columns. JOIN `RC_BACKUP_PIECE` on `bs_key`. [Details](#sprint-2-rc-backup-set) |
| **#23** | `bash /tmp/scripts/rman_archivelog_only.sh` → `Permission denied /var/log/...` | Script v1.0 hard-coded `/var/log/`. v1.1+ uses `${HOME}/rman_logs/`. [Details](#sprint-2-var-log) |
| **#24** | Script shows nothing, log file empty | `set -u` + `source ~/.bash_profile` silent crash. Wrap source in `set +u; source ...; set -u`. v1.2+ has the fix. [Details](#sprint-2-set-u) |

---

## <a id="sprint-0"></a>🔹 Sprint 0 — Boot Automation

### `e` did not enter edit mode (GRUB)

**Symptom:** After the VM starts, instead of the GRUB editor you see "Install Oracle Linux 8.10" autoboot.

**Cause:** `e` was sent BEFORE GRUB appeared.

**Resolution:**
```powershell
.\boot_rcat_via_scancode.ps1 -InitialDelaySec 15
# (default 10s, increase to 15-20s)
```

### Cursor does not land on the `linuxefi` line

**Symptom:** The payload is appended to a different line, Anaconda starts the TUI without kickstart.

**Cause:** `Down` x 2 is not enough — grub.cfg in the given ISO version has more lines.

**Resolution:**
```powershell
.\boot_rcat_via_scancode.ps1 -DownArrowsCount 3
# Or inspect grub.cfg: mount the ISO and `cat /mnt/iso/EFI/BOOT/grub.cfg`
```

### VBox keyboard buffer overflows

**Symptom:** Part of the payload is lost, GRUB cmdline has gaps.

**Cause:** Sending too quickly (>~256 events in the buffer).

**Resolution:** The default `-BatchSize 80 -BatchDelayMs 50` in `Send-VBoxKeystrokes` should be enough.
If the issue persists: reduce BatchSize to 40.

### Anaconda does not download the kickstart (HTTP 404)

**Symptom:** Anaconda starts, but enters interactive mode (TUI).

**Diagnostics:**
1. HTTP log: `_RecoveryAppliance_/kickstart/.http_server.log` — look for 404
2. In GUI mode: Ctrl-Alt-F2 in the VM, `curl http://192.168.56.1:8000/ks-rcat01.cfg`
3. Check the Host-Only IF: `Get-NetIPAddress -InterfaceAlias "*Host-Only*#2*"`

**Resolutions:**
- Verify that `start_kickstart_http.ps1` actually starts the server (`-Status`)
- Check the host firewall (Windows Defender Firewall — may block port 8000)
- Check for typos in the file name ks-rcat01.cfg (case-sensitive)

### PS5 fails when parsing the script (UnicodeError)

**Symptom:** `[FAIL] Missing closing '}' in statement block` even though the script looks OK.

**Cause:** Em-dash (—) or Polish diacritics in UTF-8 are misread by PS5 (CP1250).

**Resolution:** Normalize to ASCII via Python:
```python
text = path.read_text(encoding='utf-8')
fixed = text.translate(str.maketrans({'—': '-', 'ę': 'e', ...}))
path.write_bytes(fixed.encode('utf-8'))
```

---

## <a id="sprint-1"></a>🔹 Sprint 1 — DB Install + Catalog

### `runInstaller` fails the prerequisites check

**Symptom:** `[INS-13013] Target environment does not meet some mandatory requirements.`

**Resolution:** `-ignorePrereqFailure` is already in `install_db_silent_rcat.sh`. Check the logs:
```bash
tail -100 /u01/app/oraInventory/logs/installActions*.log
```
Common prereqs that can be ignored in the LAB: SWAP_SIZE, OS_MEMORY, KERNEL_VERSION.

### `dbca` hangs / OOM

**Symptom:** dbca process hangs, or `ORA-04031 unable to allocate ...`

**Cause:** 4 GB RAM is the minimum, dbca + sqlplus + listener may exceed it.

**Resolution:**
```bash
# Lower the SGA target for DBCA
dbca -silent -createDatabase ... -totalMemory 1024  # instead of 1536
```

### `oracle-rcat.service` fails to start

**Symptom:** `systemctl status oracle-rcat` -> `failed`, `journalctl` shows `dbstart` exit code 1.

**Cause:** Listener is already running, or /etc/oratab is missing the Y flag.

**Resolution:**
```bash
# Check /etc/oratab
cat /etc/oratab
# Should be: RCAT:/u01/app/oracle/product/23.26/dbhome_1:Y

# If the flag is N:
sudo sed -i 's|^RCAT:.*|RCAT:/u01/app/oracle/product/23.26/dbhome_1:Y|' /etc/oratab

# Check the logs
journalctl -u oracle-rcat.service -n 100
```

### After reboot the listener works but the DB does not

**Symptom:** `lsnrctl status` OK, but `sqlplus / as sysdba` -> `ORA-12162` or `ORA-01034`.

**Diagnostics:**
```bash
# Are any pmon processes running?
ps -ef | grep pmon
# None — means the DB did not start

# Check the alert log
tail -100 /u01/app/oracle/diag/rdbms/rcat/RCAT/trace/alert_RCAT.log
```

**Resolution:** Manually:
```bash
sqlplus / as sysdba <<<'STARTUP;'
```

If it still fails — check whether the `dbstart` script has an issue (ORACLE_HOME length etc).

### <a id="sprint-1-dbms-lock"></a>`PLS-00201: identifier 'DBMS_LOCK' must be declared` (Lesson #21)

**Symptom:** Every `rman target / catalog rman_cat/...@rcat01:1521/RCATPDB` returns:
```
Oracle error from recovery catalog database: ORA-06550: line 1, column 7:
PLS-00201: identifier 'DBMS_LOCK' must be declared
Acquiring a lock for upgrade command has failed. Retrying to get the lock
```

Consequence: `BACKUP DATABASE PLUS ARCHIVELOG` only completes the archivelog phase (database phase blocked — `/mnt/rman_bck/full/` EMPTY despite arch present).

**Cause:** In 26ai the `RECOVERY_CATALOG_OWNER` role does **NOT** auto-grant `EXECUTE ON SYS.DBMS_LOCK`. The standard Oracle doc (Note 2435950.1) lists this grant separately, but `01_create_catalog_schema.sql` v1.0 missed it.

**Resolution:**
```bash
ssh oracle@rcat01 'bash -lc "
sqlplus -S / as sysdba <<EOF
ALTER SESSION SET CONTAINER=RCATPDB;
GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;
SELECT grantee, table_name, privilege FROM dba_tab_privs WHERE grantee=\"RMAN_CAT\" AND table_name=\"DBMS_LOCK\";
EXIT
EOF"'
# Expected: 1 row RMAN_CAT / DBMS_LOCK / EXECUTE
```

For new setups: `01_create_catalog_schema.sql` v1.1+ contains this grant (updated 2026-05-04).

---

### <a id="sprint-1-rman-comments"></a>`RMAN-02001: unrecognized punctuation symbol "-"` (Lesson #20)

**Symptom:** `.sql` file or bash heredoc to RMAN fails:
```
RMAN-00558: error encountered while parsing input commands
RMAN-01006: error signaled during parse
RMAN-02001: unrecognized punctuation symbol "-"
```

Often with a cascade: `ALLOCATE CHANNEL c1 ... expecting "for"` (RUN block torn down by `--`, every following line interpreted as standalone).

**Cause:** RMAN does **NOT support** `--` as a comment. Only `#` is valid. This applies to:
1. `.sql` files invoked via `@file.sql` in RMAN
2. Bash heredocs to RMAN (`<<RMAN ... --comment... RMAN`)

**Resolution:** Audit + replace:
```bash
# Check .sql files going to RMAN (header `Usage: rman target / @file.sql`)
grep -l '^--' /tmp/sql/*.sql

# Replace -- with # (preserve indentation)
sed -i 's/^\(\s*\)-- /\1# /' /tmp/sql/file.sql

# Check bash heredocs
grep -A 100 '<<RMAN' /tmp/scripts/rman_*.sh | grep '^--'
```

For our files: `sql/03/04/05/10/99` v1.1+ + 8 `rman_*.sh` v1.1+ scripts have this fix (updated 2026-05-04).

---

### <a id="sprint-1-rc-site"></a>`ORA-00904: "DBID": invalid identifier` in RC_SITE validation (Lesson #17)

**Symptom:** After `catalog_register_stby.sh`, validation query:
```sql
SELECT db_key, db_unique_name, db_name, dbid FROM rc_site;
```
returns `ORA-00904: "DBID": invalid identifier`.

**Cause:** In 26ai the `RC_SITE` view has only 4 "public" columns:
- SITE_KEY
- DB_KEY (FK to RC_DATABASE)
- DATABASE_ROLE
- DB_UNIQUE_NAME

No DBID nor DB_NAME (those are in `RC_DATABASE`). It's a reduced schema relative to older versions.

**Resolution:** JOIN to `RC_DATABASE`:
```sql
SELECT s.site_key, s.db_unique_name, s.database_role, d.name AS db_name, d.dbid
  FROM rc_site s
  JOIN rc_database d ON s.db_key = d.db_key
 ORDER BY s.db_unique_name;
-- 2 rows: PRIM (site=3) and STBY (site=566), same DBID
```

Other views in 26ai have a similar reduced schema — see lesson #22 for `RC_BACKUP_SET`.

---

### REGISTER DATABASE from PRIM does not work (timeout/refused)

**Symptom:** `RMAN-04004: error from recovery catalog database: ORA-12541: TNS:no listener`

**Diagnostics:**
```bash
# From PRIM
tnsping rcat01:1521/RCATPDB
# Should be OK

# Check reachability
ping rcat01.lab.local
nc -zv 192.168.56.16 1521
```

**Resolution:**
- Check `lsnrctl status` on rcat01 — is the RCATPDB service registered
- Check that `listener.ora` on rcat01 has the correct HOST=rcat01 (or IP)
- Check the firewall on rcat01 (should be disabled in the LAB)

---

## <a id="sprint-2"></a>🔹 Sprint 2 — Backup Policy

### `ORA-19809 limit exceeded for recovery files`

**Symptom:** Backup fails, FRA on PRIM is full of archlogs.

**Resolution:**
```bash
# Quick fix: backup arch + delete
bash /tmp/scripts/rman_archivelog_only.sh

# Or increase FRA size
sqlplus / as sysdba <<'SQL'
ALTER SYSTEM SET db_recovery_file_dest_size=20G SCOPE=BOTH;
SQL
```

### Backup takes much longer than expected

**Symptom:** FULL backup of a 50 GB DB takes >2h.

**Cause:** vboxsf shared folder has significantly lower IOPS than a native Linux disk.

**Resolution:**
- Reduce PARALLELISM to 2 (instead of 4) — paradoxically sometimes faster
- Check host disk I/O (D:\ may be HDD, not SSD)
- Consider `BACKUP AS UNCOMPRESSED BACKUPSET` — compression consumes CPU

### `RMAN-03002` in cron job

**Symptom:** Backup from cron fails, but works manually.

**Cause:** Cron does not load `~/.bash_profile`.

**Resolution:** The `rman_*.sh` scripts include `source /home/oracle/.bash_profile` — verify the script is cron-friendly.

```bash
# /var/spool/cron/oracle (on prim01)
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
PATH=$ORACLE_HOME/bin:$PATH

*/15 * * * * /home/oracle/scripts/rman_archivelog_only.sh
```

### <a id="sprint-2-rc-backup-set"></a>`ORA-00904: "OUTPUT_BYTES": invalid identifier` in RC_BACKUP_SET (Lesson #22)

**Symptom:** Post-backup validation:
```sql
SELECT input_bytes/1024/1024, output_bytes/1024/1024 FROM rc_backup_set;
```
returns `ORA-00904: "OUTPUT_BYTES": invalid identifier`.

**Cause:** In 26ai `RC_BACKUP_SET` has 23 columns but **no** `INPUT_BYTES`, `OUTPUT_BYTES`, `COMPRESSION_RATIO`. Bytes are aggregated per-piece in `RC_BACKUP_PIECE.BYTES`. Analogous to lesson #17 (RC_SITE without DBID).

**Bonus diagnostics:** `BACKUP DATABASE` in 26ai returns `BACKUP_TYPE='I' INCREMENTAL_LEVEL=0`, NOT `'D'`. Codes:
- **D** = Controlfile autobackup
- **I** = Incremental (Level 0 = classic "FULL")
- **L** = Archivelog

**Resolution:** JOIN to RC_BACKUP_PIECE:
```sql
SELECT s.backup_type, COUNT(*) AS pieces,
       ROUND(SUM(p.bytes)/1024/1024,1) AS total_mb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.start_time > SYSDATE - 1/24
 GROUP BY s.backup_type
 ORDER BY 1;
```

For image copies (type COPY, not BACKUPSET) use `RC_DATAFILE_COPY`:
```sql
SELECT name, ROUND(blocks*block_size/1024/1024,1) AS mb FROM rc_datafile_copy WHERE tag = 'INCR_MERGE';
```

---

### <a id="sprint-2-var-log"></a>`bash rman_archivelog_only.sh: /var/log/...: Permission denied` (Lesson #23)

**Symptom:**
```
/tmp/scripts/rman_archivelog_only.sh: line 37: /var/log/rman_arch_20260504.log: Permission denied
```

**Cause:** `rman_archivelog_only.sh` v1.0, designed for cron, hard-coded `LOG_FILE=/var/log/rman_arch_*.log` + `exec >> "$LOG_FILE" 2>&1`. Oracle has no write access to `/var/log/` (typical for restricted Linux). Affects only this script (other rman_*.sh write to stdout).

**Resolution:** v1.1+ uses `LOG_DIR="${LOG_DIR:-${HOME}/rman_logs}"` with auto-mkdir. Manual re-deploy:
```bash
scp scripts/rman_archivelog_only.sh oracle@prim01:/tmp/
ssh root@prim01 'cp /tmp/rman_archivelog_only.sh /tmp/scripts/ && chmod +x /tmp/scripts/rman_archivelog_only.sh'
```

For cron deployment with central log `/var/log/rman_arch.log`:
```bash
sudo touch /var/log/rman_arch.log && sudo chown oracle:oinstall /var/log/rman_arch.log
# In oracle's crontab:
LOG_DIR=/var/log */15 * * * * /tmp/scripts/rman_archivelog_only.sh
```

---

### <a id="sprint-2-set-u"></a>Script rman_*.sh shows nothing, log file empty (Lesson #24)

**Symptom:**
```bash
$ bash /tmp/scripts/rman_archivelog_only.sh
$
# (prompt returns instantly, no output)
```

Log file `~/rman_logs/rman_arch_*.log` EMPTY (or cuts off right before `source bash_profile`).

**Cause:** `set -euo pipefail` active. Line `source /home/oracle/.bash_profile 2>/dev/null || true`:
- `2>/dev/null` swallows the error message
- `|| true` saves us from `set -e` (exit on error)
- **Does NOT save from `set -u`** (unset variable error)

`.bash_profile` typically uses unset variables (e.g. `[ -z "$ORACLE_SID" ]` when ORACLE_SID is unset). Under `set -u` that kills source with `unbound variable`. Process exits before the buffer flush after `exec >> $LOG_FILE`.

**Diagnose silent crash:**
```bash
bash -x /tmp/scripts/rman_archivelog_only.sh 2>&1 | head -25
# Shows last successful command (usually 'source /home/oracle/.bash_profile')
```

**Resolution:** v1.2+ has the fix:
```bash
set +u
source /home/oracle/.bash_profile 2>/dev/null || true
set -u
```

Plus added `echo "Logging to $LOG_FILE"` BEFORE `exec >> $LOG_FILE` so the user sees the log location.

---

### Crosscheck shows `EXPIRED`

**Symptom:** `LIST BACKUP` shows many backups with EXPIRED status.

**Cause:** Files removed manually from disk (or vboxsf out of sync).

**Resolution:** `rman_crosscheck.sh` contains `DELETE EXPIRED` — that should clean it up.
Verify that /mnt/rman_bck is actually mounted and in sync.

---

## <a id="sprint-3"></a>🔹 Sprint 3 — ZDLRA-like + DG Integration

### LOG_ARCHIVE_DEST_3 status = ERROR

**Symptom:** `v$archive_dest` shows status=ERROR, the error column has ORA-...

**Common errors:**

| Error | Cause | Resolution |
|---|---|---|
| `ORA-12541` | Listener on rcat01 is not running | `lsnrctl status` on rcat01, `lsnrctl start` |
| `ORA-12514` | Service `rcat_redo` is not registered | Add to listener.ora SID_LIST + `lsnrctl reload` |
| `ORA-1031` | LOG_ARCHIVE_DEST requires REDO_TRANSPORT_USER | `CREATE USER`/`GRANT SYSDG` or use the static service `rcat_redo` |
| `ORA-16053` (Lesson #26) | `DB_UNIQUE_NAME rcat_redo is not in the Data Guard Configuration` on `ALTER LOG_ARCHIVE_DEST_3` | **First** `ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(PRIM,STBY,rcat_redo)' SCOPE=BOTH;` **then** ALTER LOG_ARCHIVE_DEST_3. Script `zdlra_sim_setup.sh` v1.2+ has the fix proactively |
| `ORA-16191` (Lesson #27 revised) | `log shipping client unable to log onto target database` — **real root cause:** pwfile binary mismatch between PRIM and rcat01. Each `ALTER USER` generates a hash with a different salt — even after the original Lesson #27 fix (sync plaintext password) the pwfile binaries differ. DG redo transport (TT00/TT04) requires **literally identical pwfiles**. | **PRIM RAC has pwfile on ASM** (`+DATA/PRIM/PASSWORD/pwdprim.*`). Export: `DBMS_FILE_TRANSFER.COPY_FILE` from `+DATA/PRIM/PASSWORD` to `/tmp` on PRIM. Then scp to rcat01 + replace `$ORACLE_HOME/dbs/orapwRCAT`. Verify: md5sum must be IDENTICAL. **Full log:** [autonomous_dest3_log.md](../autonomous_dest3_log.md) |
| `ORA-16009` (Lesson #29) | `invalid redo transport destination` — appears AFTER pwfile binary fix (Lesson #27 revised). Oracle DG redo transport requires a **physical standby** target (identical db_name + dbid), not an arbitrary Oracle DB. | **Architectural limit — cannot be worked around in LAB without a full standby setup.** RCAT (db_name=RCAT, dbid different from PRIM) CANNOT be a real-time redo destination for PRIM. Decision: `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=DEFER SCOPE=BOTH;` + practical workaround = `rman_archivelog_only.sh` cron on PRIM (archive logs in shared folder). Preserves ZDLRA-Like essence (image copy + L1 incremental merge). **Possible extension:** physical standby of PRIM on rcat01 as optional Sprint 5 — see [doc 07 section "Possible LAB extension"](07_ZDLRA_Like_Simulation.md#-possible-lab-extension-sprint-5-optional--physical-standby-of-prim-on-rcat01). |
| `ORA-16191` (Lesson #28, candidate #2) | `log shipping client unable to log onto target database` DESPITE SYS auth working (Test 3.1 sqlplus -L OK). Mismatch between `DB_UNIQUE_NAME=` in `LOG_ARCHIVE_DEST_3` and the actual target `db_unique_name` from `v$database`. | Check: `SELECT db_unique_name FROM v$database` on rcat01 (= `RCAT`, NOT `rcat_redo`). In DEST_3 change `DB_UNIQUE_NAME=rcat_redo` to `DB_UNIQUE_NAME=RCAT` + `DG_CONFIG=(PRIM,STBY,RCAT)`. **Fixed in `zdlra_sim_setup.sh` v1.3+** (DB_UNIQUE_NAME=RCAT + DG_CONFIG contains RCAT) |

### Image copy grows disproportionately

**Symptom:** After `RECOVER COPY OF DATABASE` the size of /mnt/rman_bck/incr_merge does not shrink.

**Cause:** The old image copy version was not removed (RMAN keeps it as a fallback).

**Resolution:**
```rman
RMAN> DELETE COPY OF DATABASE TAG 'incr_merge' COMPLETED BEFORE 'SYSDATE-3';
```

### After switchover the backup does not work

**Symptom:** Cron on prim01 still triggers a backup, but prim01 is now STANDBY -> RMAN-06457.

**Resolution:** Add a role pre-check to the script:
```bash
ROLE=$(sqlplus -S / as sysdba <<<'SET HEADING OFF FEEDBACK OFF; SELECT database_role FROM v$database;')
[[ "$ROLE" == *"PRIMARY"* ]] || { log "[skip] Not PRIMARY"; exit 0; }
```

And install the cron on **BOTH** hosts (prim01 and stby01). Only the one currently PRIMARY will run the backup.

### B-7 (rebuild stby) DUPLICATE fails

**Symptom:** `RMAN-05541: no backup of the database to duplicate from`.

**Diagnostics:**
```rman
LIST BACKUP OF DATABASE FOR DB_UNIQUE_NAME PRIM;
```

**Resolution:** There must be at least 1 FULL backup of PRIM registered in the catalog.
First run `bash rman_full_backup.sh`, then rebuild STBY.

---

## <a id="general"></a>🔹 General

### <a id="general-ssh-equiv"></a>VM↔VM SSH equiv NOT configured (Lesson #18)

**Symptom:** Scripts performing SSH/scp between VMs (`catalog_register_stby.sh`, `catalog_register_prim.sh`) prompt repeatedly for the `oracle` password (3+ times per operation).

**Cause:** SSH user-equivalency in the main LAB is configured for `oracle` user on `prim01 prim02 stby01 infra01` (via `VMs2-install/scripts/ssh_setup.sh`), but **rcat01 was not in `ORACLE_NODES`**. Operations rcat01 → prim01/stby01 require a password.

**Resolution:**
1. Check whether `ssh_setup.sh` includes rcat01 (in main LAB):
```bash
grep ORACLE_NODES /tmp/scripts/ssh_setup.sh
# Should be: ORACLE_NODES="prim01 prim02 stby01 infra01 rcat01"
```
2. If missing — edit + run as root on prim01:
```bash
ssh root@prim01 'bash /tmp/scripts/ssh_setup.sh'
# Idempotent: only adds missing pairs, skips existing
```
3. Verify: 25 SUCCESS pairs for `oracle` (5 nodes × 5).

```bash
# Test passwordless rcat01→prim01:
ssh oracle@rcat01 'ssh -o PasswordAuthentication=no oracle@prim01 hostname'
# Expected: prim01 (no password prompt)
```

---

### <a id="general-tmp-scripts"></a>`/tmp/scripts/` on rcat01 owned by root (Lesson #19)

**Symptom:** `scp` to `/tmp/scripts/` on rcat01 returns `Permission denied`.

**Cause:** `/tmp/scripts/` on rcat01 is created by root deploy (kickstart), oracle has no write access.

**Resolutions (3 options):**

```bash
# Option A: scp to /tmp/ (oracle has write) + sudo cp
scp file.sh oracle@rcat01:/tmp/
ssh root@rcat01 'cp /tmp/file.sh /tmp/scripts/ && chmod +x /tmp/scripts/file.sh'

# Option B: directly as root (if root SSH equiv exists)
scp file.sh root@rcat01:/tmp/scripts/

# Option C: deploy_to_rcat.ps1 (from Windows host)
cd ZDLRA_like/scripts
.\deploy_to_rcat.ps1
```

---

### Passwords in scripts (security concern)

LAB convention: a unified password in `/root/.lab_secrets` as `export LAB_PASS='...'` (chmod 600).
The file is created by kickstart `%post`. All `.sh` scripts in this subproject have at the top
a `[ -r /root/.lab_secrets ] && source /root/.lab_secrets` block with validation that `$LAB_PASS` is not empty.

In production **never** hardcode — switch to Oracle Wallet:

Migration to Oracle Wallet (example):
```bash
mkstore -wrl /home/oracle/wallet -create
mkstore -wrl /home/oracle/wallet -createCredential rcat01:1521/RCATPDB rman_cat 'real_password'

# Connect via wallet
rman target / catalog rman_cat/@rcat01:1521/RCATPDB
```

Requires `sqlnet.ora` configuration with `WALLET_LOCATION` + `SQLNET.WALLET_OVERRIDE=TRUE`.

### Performance: vboxsf shared folder is slow

vboxsf in VBox is implemented as FUSE — lower IOPS than native disks.
Acceptable for the LAB, but **do not** use in prod.

In prod: NFS share, iSCSI, Object Storage, ASM.

### Backup files get lost (vboxsf desync)

**Symptom:** File visible on the Windows host, not visible in the VM (or vice versa).

**Resolution:** Restart Guest Additions:
```bash
sudo systemctl restart vboxadd-service
```

Or in the VM: `sudo umount /mnt/rman_bck && sudo mount /mnt/rman_bck`

### "Catalog is older than target database" (ORA-19909)

**Symptom:** REGISTER DATABASE fails with ORA-19909.

**Cause:** Catalog version < TARGET version. In our LAB both are 23.26.1, but if there were a mismatch:

**Resolution:**
```bash
# On PRIM:
rman catalog rman_cat/...@rcat01:1521/RCATPDB
RMAN> UPGRADE CATALOG;
RMAN> UPGRADE CATALOG;  -- twice per the RMAN docs
```

## 📞 Where to look further

- PRIM alert log: `/u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log`
- RCAT alert log: `/u01/app/oracle/diag/rdbms/rcat/RCAT/trace/alert_RCAT.log`
- RMAN session log: in the call directory, file `rman_*.log` if the script redirects
- Anaconda log: `/root/anaconda-ks.cfg` + `/root/ks-post.log` (after install)
- VBoxManage log: `D:\VM\rcat01\Logs\VBox.log`
- Health checks SQL: `sql/20_health_checks.sql` (6 diagnostic queries)
- **Per-scenario troubleshooting:** [doc 08 troubleshooting](08_Backup_Restore_Scenarios.md#troubleshooting) (12 rows of lessons #13-24 for scenarios B-1..B-8)
- **EXECUTION_LOG:** [EXECUTION_LOG.md](../EXECUTION_LOG.md) (chronological log of iterations 1-12 with lessons in context)
