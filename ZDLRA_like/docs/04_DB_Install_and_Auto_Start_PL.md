# 🗄️ 04 — DB Install + Auto-Start (Sprint 1, krok 2)

[![Sprint](https://img.shields.io/badge/Sprint-1-blue)]()
[![Step](https://img.shields.io/badge/Step-2_of_4-orange)]()
[![DB](https://img.shields.io/badge/Oracle-26ai_23.26.1-red)]()
[![Edition](https://img.shields.io/badge/Edition-EE-purple)]()
[![Auto](https://img.shields.io/badge/Auto--start-systemd-darkgreen)]()
[![Type](https://img.shields.io/badge/Type-Single_Instance-lightblue)]()

> 🎯 Silent install Oracle DB 26ai 23.26.1 + DBCA (CDB RCAT + PDB RCATPDB) + systemd unit dla auto-startu po reboocie OS.

## 📋 Wymagania / Prerequisites

- ✅ rcat01 zainstalowany OL 8.10 (Sprint 1 krok 1)
- ✅ DNS dla rcat01 dziala (setup_dns_rcat_on_infra01.sh)
- ✅ `/mnt/oracle_binaries` zamontowany z paczka 23.26.1 zip
- ✅ User `oracle` z `.bash_profile` (po setup_oracle_env_rcat.sh)

## 🚀 Metoda A — Automatyczna (3 kroki)

```bash
# 0) Deploy: skopiuj caly subtree (scripts + sql + response_files) na rcat01.
#    UWAGA: scripts/ I sql/ MUSZA byc kopiowane razem - skrypty (np. catalog_create.sh)
#    odwoluja sie do siostrzanego sql/ (../sql/01_*.sql).
#    Lesson learned 2026-05-03: bez sql/ catalog_create.sh wyrzuca "BLAD: nie istnieje".
# IMPORTANT: scripts/ AND sql/ must be copied together - scripts reference sibling sql/.
#
# Z hosta Windows (PowerShell):
#   .\scripts\deploy_to_rcat.ps1               # helper (idempotent)
# Lub manualnie:
ssh kris@rcat01 'mkdir -p /tmp/scripts /tmp/sql /tmp/response_files'
scp -r scripts/*.sh scripts/systemd kris@rcat01:/tmp/scripts/
scp -r sql/*.sql kris@rcat01:/tmp/sql/
scp response_files/*.rsp kris@rcat01:/tmp/response_files/
# Opcjonalny shortcut na rcat01 zeby skrypty znajdowaly sql/ jako sibling:
ssh kris@rcat01 'cd /tmp && [ ! -L scripts/../sql ] && ln -sf /tmp/sql /tmp/sql || true'

# 1) Setup environment (jako root)
ssh root@rcat01 'bash /tmp/scripts/setup_oracle_env_rcat.sh'

# 3) DB install (jako oracle) - wypakowanie binariow + runInstaller + netca (LISTENER)
ssh oracle@rcat01 'bash /tmp/scripts/install_db_silent_rcat.sh /tmp/scripts/db_rcat_se2.rsp'

# 4) root.sh (jako root)
# UWAGA: orainstRoot.sh moze nie istniec - kickstart pre-tworzy /u01/app/oraInventory + /etc/oraInst.loc,
# wtedy runInstaller pomija generowanie orainstRoot.sh. Sprawdz: ls /u01/app/oraInventory/orainstRoot.sh
ssh root@rcat01 '/u01/app/oracle/product/23.26/dbhome_1/root.sh'
ssh root@rcat01 '[ -f /u01/app/oraInventory/orainstRoot.sh ] && /u01/app/oraInventory/orainstRoot.sh || echo "orainstRoot.sh skipped (oraInventory pre-created)"'

# 5) DBCA - utworz CDB RCAT + PDB RCATPDB (jako oracle, ~15-20 min)
ssh oracle@rcat01 'bash /tmp/scripts/dbca_create_rcat.sh'

# 6) systemd auto-start (jako root)
ssh root@rcat01 'bash /tmp/scripts/setup_systemd_oracle_unit.sh'
```

## 🛠️ Metoda B — Manualna (krok po kroku)

### B.1) Setup srodowiska

```bash
ssh root@rcat01

# Edytuj /home/oracle/.bash_profile
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

### B.2) Silent install Oracle DB Software

```bash
su - oracle
cd $ORACLE_HOME
unzip -q /mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip

export CV_ASSUME_DISTID=OEL8.10
./runInstaller -silent -ignorePrereqFailure -responseFile /tmp/scripts/db_rcat_se2.rsp
```

### B.3) Utworz LISTENER przez netca (KRYTYCZNE przed DBCA)

```bash
# Jako oracle - DBCA wymaga istniejacego listenera (-listeners LISTENER w dbca_create_rcat.sh).
# Bez tego DBCA wyrzuca DBT-07505 'Selected listener (LISTENER) does not exist'.
netca -silent -responseFile $ORACLE_HOME/assistants/netca/netca.rsp

# Walidacja
lsnrctl status
# Spodziewane: LISTENER na porcie 1521, "The listener supports no services"
```

### B.4) Root scripts

```bash
# Jako root (na innym terminalu)
/u01/app/oracle/product/23.26/dbhome_1/root.sh

# orainstRoot.sh - tylko jesli plik istnieje. Przy pre-utworzonym oraInventory (kickstart)
# runInstaller go nie generuje. Sprawdz:
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

# Po DBCA: dopisz Y do /etc/oratab
sudo sed -i 's|^RCAT:.*|RCAT:/u01/app/oracle/product/23.26/dbhome_1:Y|' /etc/oratab
```

### B.6) systemd unit (auto-start)

```bash
sudo cp /tmp/scripts/systemd/oracle-rcat.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable oracle-rcat.service
sudo systemctl start oracle-rcat.service
```

## ✅ Walidacja / Validation

```bash
# Service status
systemctl status oracle-rcat.service
# Oczekiwane: active (exited)

# Listener
lsnrctl status
# Powinno byc: LISTENER + serwisy RCAT i RCATPDB

# DB instance
sqlplus / as sysdba <<'SQL'
SELECT instance_name, status FROM v$instance;
SELECT name, open_mode FROM v$pdbs;
SELECT log_mode FROM v$database;
SQL
# Oczekiwane: STATUS=OPEN, RCATPDB OPEN=READ WRITE, log_mode=ARCHIVELOG
```

## 🔄 Test reboot (krytyczny dla Sprintu 1)

```bash
sudo systemctl reboot
# Czekaj ~120 s
ssh oracle@rcat01

systemctl status oracle-rcat.service
# active (exited) bez interakcji = SUKCES

sqlplus / as sysdba <<<'SELECT status FROM v$instance;'
# OPEN
```

## 🚧 Troubleshooting

| Problem | Rozwiazanie |
|---|---|
| `runInstaller` fail z prerequisite check | `-ignorePrereqFailure` jest juz w skrypcie. Sprawdz `/u01/app/oraInventory/logs/installActions*.log`. |
| `dbca` zawiesza sie | Sprawdz `/u01/app/oracle/cfgtoollogs/dbca/RCAT/RCAT.log`. Czesto memory issues - obniz `-totalMemory 1024`. |
| `oracle-rcat.service` start fail | `journalctl -u oracle-rcat.service -n 100`. Sprawdz `/etc/oratab` ma `:Y`. |
| `dbstart` nie startuje listenera | Sprawdz `$ORACLE_HOME/bin/dbstart` (powinien zawierac `lsnrctl start LISTENER`). |
| Po reboocie listener dziala, ale baza nie | `sqlplus` -> `STARTUP` reczny, sprawdz logi w `$ORACLE_BASE/diag/rdbms/rcat/RCAT/trace/alert_RCAT.log`. |

## ⏭️ Nastepny krok / Next step

[05_Catalog_Setup.md](05_Catalog_Setup_PL.md) — schemat rman_cat + CREATE CATALOG + REGISTER PRIM.
