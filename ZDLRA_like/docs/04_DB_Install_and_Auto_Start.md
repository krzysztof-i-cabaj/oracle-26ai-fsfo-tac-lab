# 🗄️ 04 — DB Install + Auto-Start (Sprint 1, step 2)

[![Sprint](https://img.shields.io/badge/Sprint-1-blue)]()
[![Step](https://img.shields.io/badge/Step-2_of_4-orange)]()
[![DB](https://img.shields.io/badge/Oracle-26ai_23.26.1-red)]()
[![Edition](https://img.shields.io/badge/Edition-EE-purple)]()
[![Auto](https://img.shields.io/badge/Auto--start-systemd-darkgreen)]()
[![Type](https://img.shields.io/badge/Type-Single_Instance-lightblue)]()

> 🎯 Silent install of Oracle DB 26ai 23.26.1 + DBCA (CDB RCAT + PDB RCATPDB) + systemd unit for auto-start after OS reboot.

## 📋 Prerequisites

- ✅ rcat01 installed with OL 8.10 (Sprint 1 step 1)
- ✅ DNS for rcat01 working (setup_dns_rcat_on_infra01.sh)
- ✅ `/mnt/oracle_binaries` mounted with the 23.26.1 zip package
- ✅ User `oracle` with `.bash_profile` (after setup_oracle_env_rcat.sh)

## 🚀 Method A — Automated (3 steps)

```bash
# 0) Deploy: copy the entire subtree (scripts + sql + response_files) to rcat01.
#    NOTE: scripts/ AND sql/ MUST be copied together — scripts (e.g. catalog_create.sh)
#    reference the sibling sql/ (../sql/01_*.sql).
#    Lesson learned 2026-05-03: without sql/ catalog_create.sh fails with "ERROR: does not exist".
#
# From the Windows host (PowerShell):
#   .\scripts\deploy_to_rcat.ps1               # helper (idempotent)
# Or manually:
ssh kris@rcat01 'mkdir -p /tmp/scripts /tmp/sql /tmp/response_files'
scp -r scripts/*.sh scripts/systemd kris@rcat01:/tmp/scripts/
scp -r sql/*.sql kris@rcat01:/tmp/sql/
scp response_files/*.rsp kris@rcat01:/tmp/response_files/
# Optional shortcut on rcat01 so scripts find sql/ as a sibling:
ssh kris@rcat01 'cd /tmp && [ ! -L scripts/../sql ] && ln -sf /tmp/sql /tmp/sql || true'

# 1) Setup environment (as root)
ssh root@rcat01 'bash /tmp/scripts/setup_oracle_env_rcat.sh'

# 3) DB install (as oracle) — extract binaries + runInstaller + netca (LISTENER)
ssh oracle@rcat01 'bash /tmp/scripts/install_db_silent_rcat.sh /tmp/scripts/db_rcat_se2.rsp'

# 4) root.sh (as root)
# NOTE: orainstRoot.sh may not exist — kickstart pre-creates /u01/app/oraInventory + /etc/oraInst.loc,
# in which case runInstaller skips generating orainstRoot.sh. Check: ls /u01/app/oraInventory/orainstRoot.sh
ssh root@rcat01 '/u01/app/oracle/product/23.26/dbhome_1/root.sh'
ssh root@rcat01 '[ -f /u01/app/oraInventory/orainstRoot.sh ] && /u01/app/oraInventory/orainstRoot.sh || echo "orainstRoot.sh skipped (oraInventory pre-created)"'

# 5) DBCA — create CDB RCAT + PDB RCATPDB (as oracle, ~15-20 min)
ssh oracle@rcat01 'bash /tmp/scripts/dbca_create_rcat.sh'

# 6) systemd auto-start (as root)
ssh root@rcat01 'bash /tmp/scripts/setup_systemd_oracle_unit.sh'
```

## 🛠️ Method B — Manual (step by step)

### B.1) Environment setup

```bash
ssh root@rcat01

# Edit /home/oracle/.bash_profile
cat >> /home/oracle/.bash_profile <<'EOF'
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/23.26/dbhome_1
export ORACLE_SID=RCAT
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export TNS_ADMIN=$ORACLE_HOME/network/admin
EOF
chown oracle:oinstall /home/oracle/.bash_profile
```

### B.2) Silent install of Oracle DB Software

```bash
su - oracle
cd $ORACLE_HOME
unzip -q /mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip

export CV_ASSUME_DISTID=OEL8.10
./runInstaller -silent -ignorePrereqFailure -responseFile /tmp/scripts/db_rcat_se2.rsp
```

### B.3) Create LISTENER via netca (CRITICAL before DBCA)

```bash
# As oracle — DBCA requires an existing listener (-listeners LISTENER in dbca_create_rcat.sh).
# Without it DBCA throws DBT-07505 'Selected listener (LISTENER) does not exist'.
netca -silent -responseFile $ORACLE_HOME/assistants/netca/netca.rsp

# Validation
lsnrctl status
# Expected: LISTENER on port 1521, "The listener supports no services"
```

### B.4) Root scripts

```bash
# As root (in another terminal)
/u01/app/oracle/product/23.26/dbhome_1/root.sh

# orainstRoot.sh — only if the file exists. With pre-created oraInventory (kickstart)
# runInstaller does not generate it. Check:
[ -f /u01/app/oraInventory/orainstRoot.sh ] && /u01/app/oraInventory/orainstRoot.sh \
    || echo "orainstRoot.sh skipped (oraInventory pre-created by kickstart)"
```

### B.5) DBCA (CDB RCAT + PDB RCATPDB)

```bash
su - oracle
dbca -silent -createDatabase \
    -templateName General_Purpose.dbc \
    -gdbName RCAT -sid RCAT \
    -characterSet AL32UTF8 \
    -sysPassword "${LAB_PASS}" \
    -systemPassword "${LAB_PASS}" \
    -createAsContainerDatabase true \
    -numberOfPDBs 1 -pdbName RCATPDB \
    -pdbAdminPassword "${LAB_PASS}" \
    -datafileDestination /u02/oradata \
    -recoveryAreaDestination /u03/fra \
    -recoveryAreaSize 30000 \
    -enableArchive true -archiveLogMode true \
    -totalMemory 1536 \
    -emConfiguration NONE \
    -listeners LISTENER

# After DBCA: set Y in /etc/oratab
sudo sed -i 's|^RCAT:.*|RCAT:/u01/app/oracle/product/23.26/dbhome_1:Y|' /etc/oratab
```

### B.6) systemd unit (auto-start)

```bash
sudo cp /tmp/scripts/systemd/oracle-rcat.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable oracle-rcat.service
sudo systemctl start oracle-rcat.service
```

## ✅ Validation

```bash
# Service status
systemctl status oracle-rcat.service
# Expected: active (exited)

# Listener
lsnrctl status
# Expected: LISTENER + RCAT and RCATPDB services

# DB instance
sqlplus / as sysdba <<'SQL'
SELECT instance_name, status FROM v$instance;
SELECT name, open_mode FROM v$pdbs;
SELECT log_mode FROM v$database;
SQL
# Expected: STATUS=OPEN, RCATPDB OPEN=READ WRITE, log_mode=ARCHIVELOG
```

## 🔄 Reboot test (critical for Sprint 1)

```bash
sudo systemctl reboot
# Wait ~120 s
ssh oracle@rcat01

systemctl status oracle-rcat.service
# active (exited) without interaction = SUCCESS

sqlplus / as sysdba <<<'SELECT status FROM v$instance;'
# OPEN
```

## 🚧 Troubleshooting

| Problem | Resolution |
|---|---|
| `runInstaller` fails on prerequisite check | `-ignorePrereqFailure` is already in the script. Check `/u01/app/oraInventory/logs/installActions*.log`. |
| `dbca` hangs | Check `/u01/app/oracle/cfgtoollogs/dbca/RCAT/RCAT.log`. Often memory issues — lower `-totalMemory 1024`. |
| `oracle-rcat.service` fails to start | `journalctl -u oracle-rcat.service -n 100`. Make sure `/etc/oratab` has `:Y`. |
| `dbstart` does not start the listener | Check `$ORACLE_HOME/bin/dbstart` (should contain `lsnrctl start LISTENER`). |
| After reboot listener works but DB does not | `sqlplus` -> `STARTUP` manually, check logs in `$ORACLE_BASE/diag/rdbms/rcat/RCAT/trace/alert_RCAT.log`. |

## ⏭️ Next step

[05_Catalog_Setup.md](05_Catalog_Setup.md) — rman_cat schema + CREATE CATALOG + REGISTER PRIM.
