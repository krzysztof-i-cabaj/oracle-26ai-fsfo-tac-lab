> 🇬🇧 English | [🇵🇱 Polski](./05_Database_Primary_PL.md)

# 05 — Database Installation and Primary Creation (VMs2-install)

> **Goal:** Install Oracle Database 26ai (23.26.1) software in *Software Only* mode on the RAC cluster (`prim01`, `prim02`) and create the Primary Database on it (Primary CDB: `PRIM`) with one pluggable database PDB (`APPPDB`).
> **Dependencies:** A correctly working Grid Infrastructure and started ASM disks (`+OCR`, `+DATA`, `+RECO`).

This document describes two deployment methods: automated (script-based) and fully manual step by step.

---

## Method 1: Fast Automated Path (Recommended)

All steps have been embedded in two scripts. Log in to **`prim01`** as user **`oracle`**:

```bash
# 1. Database software installation
bash /tmp/scripts/install_db_silent.sh /tmp/response_files/db.rsp

# After completion, log in as ROOT on prim01 and prim02 and run:
# /u01/app/oracle/product/23.26/dbhome_1/root.sh
```

```bash
# 2. Primary Database creation (CDB/PDB)
su - oracle

# The process takes about 30-50 minutes — run with nohup so an SSH/MobaXterm session
# does not interrupt DBCA after disconnection.
nohup bash /tmp/scripts/create_primary.sh /tmp/response_files/dbca_prim.rsp \
    > /tmp/create_primary_$(date +%Y%m%d_%H%M).log 2>&1 &
echo "PID: $!"

# Track progress in the same or a new session:
tail -f /u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM.log
```

> **Note:** For long-running processes (DBCA, RMAN DUPLICATE, Data Guard sync) always use `nohup ... &` or `screen`/`tmux`. A dropped MobaXterm SSH session terminates the process together with DBCA, which requires cleaning up the partially created database (`dbca -deleteDatabase`) before retrying.

At the end, script #2 automatically switches the database to `MOUNT` mode and enables critical features: `ARCHIVELOG`, `FORCE LOGGING`, and `FLASHBACK ON`. If you used this method, you can jump straight to the **Verification** section.

---

## Method 2: Manual Path (Step by step)

If you prefer full control and want to understand every stage, follow the instructions below. Log in to **`prim01`** as user **`oracle`**.

### Step 1: Extract binaries to ORACLE_HOME

```bash
export DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"
export DB_ZIP="/mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip"

cd $DB_HOME
unzip -q $DB_ZIP
```

### Step 2: Silent Installation (Software-Only)

```bash
export CV_ASSUME_DISTID=OEL8.10

$DB_HOME/runInstaller -silent -ignorePrereqFailure -responseFile /tmp/response_files/db.rsp
```

After the installer completes successfully, the console will prompt you to run the root scripts. Run the following command as user **`root`** first on **`prim01`**, then on **`prim02`**:

```bash
# As root
/u01/app/oracle/product/23.26/dbhome_1/root.sh
```

### Step 3: Database creation in DBCA

We will use DBCA with the enforced template `New_Database.dbt` (this way the database is created correctly in the 26ai architecture without "Seed" errors).

```bash
# As oracle on prim01
$DB_HOME/bin/dbca -silent -createDatabase -responseFile /tmp/response_files/dbca_prim.rsp
```

This operation takes 30 to 50 minutes depending on Storage LVM performance.

### Step 4: Enable ARCHIVELOG, FORCE LOGGING and FLASHBACK

A freshly created DBCA database starts by default in `NOARCHIVELOG` mode. To configure the Data Guard service, change logging and Flashback technology are essential.

```bash
# As oracle on prim01
export ORACLE_SID=PRIM1
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# Stop the clustered database and start it in MOUNT mode
srvctl stop database -d PRIM
srvctl start database -d PRIM -startoption mount
```

Change parameters inside the database:
```bash
sqlplus / as sysdba
```
```sql
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE FORCE LOGGING;
ALTER DATABASE FLASHBACK ON;
ALTER DATABASE OPEN;
EXIT;
```

---

## 3. DBCA logs — where to look in case of problems

The script prints DBCA progress to stdout. If something goes wrong, details can be found in:

| Log | Contents |
|-----|----------|
| `/u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM.log` | **Main DBCA log** — look here first for errors |
| `/u01/app/oraInventory/logs/dbca*.log` | Prereq and inventory logs |
| `/u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log` | Instance alert log (errors after startup) |

To track progress live and keep a full log in a single file:
```bash
bash /tmp/scripts/create_primary.sh /tmp/response_files/dbca_prim.rsp \
    2>&1 | tee /tmp/create_primary_$(date +%Y%m%d_%H%M).log
```

Watch the main DBCA log while it runs (in a separate terminal):
```bash
tail -f /u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM.log
```

---

## 5. Verification

Make sure the database service is running on both cluster nodes and its server status is "Open".

```bash
# As oracle on prim01
srvctl status database -d PRIM
# Expected output: Instance PRIM1 is running on node prim01, Instance PRIM2 is running on node prim02

sqlplus / as sysdba
```
```sql
SELECT log_mode, flashback_on, force_logging FROM v$database;
```
The query results must show: `ARCHIVELOG`, `YES` (for Flashback), and `YES` (for Force Logging).

If the database meets these conditions, it is 100% ready for the Standby environment configuration.

---
**Next step:** `06_Data_Guard_Standby.md`
