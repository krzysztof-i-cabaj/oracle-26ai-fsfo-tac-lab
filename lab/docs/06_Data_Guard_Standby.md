# 06 — Creating Standby via Data Guard Broker (VMs2-install)

> 🇬🇧 English | [🇵🇱 Polski](./06_Data_Guard_Standby_PL.md)

> **Goal:** Install a physical standby database (Physical Standby `STBY`) on the `stby01` node using the latest, simplified approach based on **Data Guard Broker (DGMGRL)**. This method eliminates the need to manually write long RMAN DUPLICATE scripts — the broker itself handles all the complexity (file copy, parameter application in the background).

This document describes two deployment methods: automated (script-based) and fully manual step by step.

---

## 0. Prerequisite: DB software installation on stby01

> **Dependency:** The `create_standby_broker.sh` script copies the password file to `stby01` into the `$ORACLE_HOME/dbs/` directory. That directory exists only after the database software is installed. Without this step the script will fail with `scp: /u01/app/oracle/.../dbs/: No such file or directory`.

### Automated method (Recommended)

Log in to **`stby01`** as the **`oracle`** user:

```bash
bash /tmp/scripts/install_db_silent.sh /tmp/response_files/db_stby.rsp
```

> **Note:** We use `db_stby.rsp`, **not** `db.rsp`. The difference: `db_stby.rsp` has an empty `CLUSTER_NODES` parameter (stby01 is a Standalone Server / Oracle Restart, not a RAC cluster). With `CLUSTER_NODES=prim01,prim02` filled in, the installer would try to register the home in CRS RAC and fail.

After the installer finishes — as **`root`** on **`stby01`**:

```bash
/u01/app/oracle/product/23.26/dbhome_1/root.sh
```

### Manual method

```bash
# As oracle on stby01
export DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"
export DB_ZIP="/mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip"
export CV_ASSUME_DISTID=OEL8.10

cd $DB_HOME
unzip -q $DB_ZIP

$DB_HOME/runInstaller -silent -ignorePrereqFailure \
    -responseFile /tmp/response_files/db_stby.rsp
```

```bash
# As root on stby01 — after runInstaller completes
/u01/app/oracle/product/23.26/dbhome_1/root.sh
```

### Verification

```bash
# As oracle on stby01
ls /u01/app/oracle/product/23.26/dbhome_1/dbs/
# The dbs/ directory must exist — this signals readiness for the next steps.

cat /u01/app/oraInventory/ContentsXML/inventory.xml | grep -i "oracle.server"
# Expected: HOME NAME="OraDB23Home1" LOC="/u01/app/oracle/product/23.26/dbhome_1"
```

When `dbs/` exists and the inventory confirms registration — proceed to the section below.

---

## 1. Network Architecture and Requirements

For Data Guard Broker to autonomously "build" the database on the remote `stby01` node, three conditions must be met:
1. We have a password file (i.e. `orapwPRIM` copied as `orapwSTBY`) on the remote machine, so that `AS SYSDBA` connections over the network can be authenticated.
2. A full mesh of SSH keys is in place — this was already done in step *02_OS_Preparation*.
3. On the target server (`stby01`), the instance is running in an "empty" state, meaning `NOMOUNT` using a simple init parameter file (`initSTBY.ora`).
4. A local `LISTENER` is running on both sides along with the appropriate entries in `tnsnames.ora`.

All these pre-configurations, as well as the DGMGRL invocation itself, can be automated or performed manually.

---

## Method 1: Fast Automated Path (Recommended)

You execute this process 100% from the master node **`prim01`**. The script injects files into the `stby01` node by itself.

### Step 0: LAB_PASS password file (prim01, oracle)

The `create_standby_broker.sh` script requires the `LAB_PASS` variable (the SYS password for the DGMGRL wallet). Create the file `~/.lab_secrets` on **`prim01`** as **`oracle`**:

```bash
cat > ~/.lab_secrets << 'EOF'
export LAB_PASS='Oracle26ai_LAB!'
EOF
chmod 600 ~/.lab_secrets
cat ~/.lab_secrets
# Expected: export LAB_PASS='Oracle26ai_LAB!'
```

> **Note:** Do not use `echo "export LAB_PASS='Oracle26ai_LAB!'"` — bash interprets `!` inside double quotes as history expansion and returns `event not found`. Always use a heredoc `<< 'EOF'` (the apostrophe around EOF disables expansions).

### Step 1: Run the script

```bash
# As oracle on prim01
# The script will take several to a dozen-plus minutes (depending on I/O performance)
# RMAN DUPLICATE will be invoked in the background by the Broker process.
nohup bash /tmp/scripts/create_standby_broker.sh > /tmp/create_standby.log 2>&1 &

# Watch the process:
tail -f /tmp/create_standby.log
```

If you used this path, you can jump straight to the **Verification** section.

---

## Method 2: Manual Path (Step by step)

For those who want to trace the commands or debug potential issues, we have prepared a complete list of steps.

### Step 1: Copy the password file to the Standby server

We perform the operation on the master node **`prim01`** as the `oracle` user:

> **GI/RAC note — `/etc/oratab` and `oraenv`:** In an Oracle Grid Infrastructure environment (11gR2+),
> RAC instances (PRIM1, PRIM2) **do not have entries in `/etc/oratab`** — CRS/OCR is the source of truth.
> `oraenv` calls `dbhome PRIM1`, which returns `/home/oracle` when the entry is missing → exit 2 → script error.
> In RAC scripts, use `ORACLE_HOME` directly or via `srvctl config database -db PRIM`.
> (Oracle GI Admin Guide: *"For Oracle RAC databases, do not use the oratab file to manage database startup"*)

```bash
# FIX-S28-27/28: orapwd rejects "oracle" in the password (OPW-00029); asmcmd pwcopy requires
# ORACLE_SID=+ASM1 and chmod 1777 on the destination directory (grid writes via the ASM process).
mkdir -p /tmp/pwd
chmod 1777 /tmp/pwd   # grid (ASM process) must have write permission
export ORACLE_SID=+ASM1
PWFILE=$(asmcmd pwget --dbuniquename PRIM)
asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f
export ORACLE_SID=PRIM1

# Copy the file via SSH to the remote stby01 machine
scp /tmp/pwd/orapwPRIM oracle@stby01:/u01/app/oracle/product/23.26/dbhome_1/dbs/orapwSTBY
```

### Step 2: Configure infrastructure on the Standby node (`stby01`)

Switch to **`stby01`** as the `oracle` user. Prepare the network files, create the required data folders, and start the empty instance.

```bash
# As oracle on stby01
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export ORACLE_SID=STBY
export PATH=$ORACLE_HOME/bin:$PATH

# Create physical directories on XFS (per the lab architecture)
mkdir -p $ORACLE_HOME/network/admin
mkdir -p /u01/app/oracle/admin/STBY/adump
mkdir -p /u02/oradata/STBY/onlinelog
mkdir -p /u03/fra/STBY/onlinelog

# FIX-S28-50: LISTENER (1521) on stby01 as a HAS resource — auto-start after reboot.
# By default CRS_SWONLY install + roothas.pl does NOT create ora.LISTENER.lsnr — without it after reboot
# the stby01 listener does not start → ORA-16778 (broker redo transport error). listener.ora goes into GRID_HOME.
# FIX-040 / S28-29: GLOBAL_DBNAME with the .lab.local suffix (db_domain=lab.local).
# Run as grid (root@stby01 → su - grid):
mkdir -p /u01/app/23.26/grid/network/admin
cat >> /u01/app/23.26/grid/network/admin/listener.ora <<'LORA'

LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = STBY.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = STBY)
    )
    (SID_DESC =
      (GLOBAL_DBNAME = STBY_DGMGRL.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = STBY)
    )
  )
LORA

srvctl add listener -listener LISTENER -endpoints 'TCP:1521'
srvctl start listener -listener LISTENER
srvctl status listener -listener LISTENER
# Expected: Listener LISTENER is enabled, running on node(s): stby01

# Verify
lsnrctl status LISTENER | grep -E 'STATUS|Service'
# Expected: STATUS Ready, Parameter File from the GRID_HOME path

# TNSNAMES for stby01
# FIX-040: SERVICE_NAME must have the .lab.local suffix (Oracle 23.26.1 with db_domain=lab.local)
# FIX-S28-31: ADDRESS_LIST with node IPs instead of SCAN — the SCAN listener does not see PRIM.lab.local
# when remote_listener is not set. The local listeners on prim01/prim02 have the service.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on — RMAN Active Duplicate requires a deterministic
# connect to a SINGLE RAC instance. Without it the AUX RPC back to TARGET hits different nodes →
# ORA-01138 during DBMS_BACKUP_RESTORE.RESTORESETPIECE.
cat > $ORACLE_HOME/network/admin/tnsnames.ora <<TORA
PRIM =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1521))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM.lab.local))
  )
STBY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY.lab.local))
  )
TORA

# LISTENER 1521 is already started by `srvctl start listener` (HAS) above — DO NOT start it manually.
# LISTENER_DGMGRL (1522) will be configured as a CRS/HAS resource later (step 4a/4b).

# FIX-S28-30: Oracle Restart automatically starts STBY after DB installation — stop it before NOMOUNT
srvctl stop database -db STBY 2>/dev/null || true

# FIX-S28-37: clean up leftovers from failed attempts (datafiles, controlfile, SPFILE).
# Without this, RMAN DUPLICATE can throw ORA-19660/ORA-19685 verification failures.
rm -f /u02/oradata/STBY/*.dbf /u02/oradata/STBY/*.ctl 2>/dev/null || true
rm -rf /u02/oradata/STBY/onlinelog/* 2>/dev/null || true
rm -f /u03/fra/STBY/*.ctl 2>/dev/null || true
rm -rf /u03/fra/STBY/onlinelog/* 2>/dev/null || true
rm -rf /u03/fra/STBY/STBY 2>/dev/null || true
rm -f $ORACLE_HOME/dbs/spfileSTBY.ora 2>/dev/null || true
# FIX-S28-42: remove old broker config files from STBY — leftovers from failed ENABLE
# cause ORA-16603 "member is part of another DG config" on ADD DATABASE STBY from PRIM.
rm -f $ORACLE_HOME/dbs/dr1STBY.dat $ORACLE_HOME/dbs/dr2STBY.dat 2>/dev/null || true

# Create a minimal PFILE (initSTBY.ora) and STARTUP NOMOUNT
cat > $ORACLE_HOME/dbs/initSTBY.ora <<IORA
db_name=PRIM
db_unique_name=STBY
sga_target=2048M
IORA

sqlplus -s / as sysdba <<SQL
SHUTDOWN ABORT;
STARTUP NOMOUNT PFILE='$ORACLE_HOME/dbs/initSTBY.ora';
ALTER SYSTEM SET DG_BROKER_START=TRUE;
EXIT;
SQL
```

### Step 3: Configure Primary and Broker (`prim01`)

Log back in to **`prim01`** as `oracle`. Prepare the TNSNAMES file, force the broker process to run on both RAC nodes, and invoke the duplicate database command.

```bash
# As oracle on prim01
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export ORACLE_SID=PRIM1

# Update TNSNAMES across the cluster
# FIX-040: SERVICE_NAME must have the .lab.local suffix (Oracle 23.26.1 with db_domain=lab.local)
# FIX-S28-31: ADDRESS_LIST with node IPs instead of SCAN — the SCAN listener does not see PRIM.lab.local
# when remote_listener is not set. The local listeners on prim01/prim02 have the service.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on — RMAN Active Duplicate requires a deterministic
# connect to a SINGLE RAC instance. Without it the AUX RPC back to TARGET hits different nodes →
# ORA-01138 during DBMS_BACKUP_RESTORE.RESTORESETPIECE.
cat > $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'
PRIM =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1521))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM.lab.local))
  )
STBY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY.lab.local))
  )
EOF
scp $ORACLE_HOME/network/admin/tnsnames.ora prim02:$ORACLE_HOME/network/admin/tnsnames.ora

# FIX-S28-49 (CRS-managed): LISTENER_DGMGRL on port 1522 as a CRS/HAS resource — auto-start
# after reboot without manual commands. The listener.ora goes into GRID_HOME (grid user), srvctl add
# listener registers the resource in CRS (RAC: prim01+prim02) or HAS (stby01).
# Without this, observers from infra01 will not connect via the PRIM_ADMIN alias (port 1522).

# === RAC nodes (prim01/prim02) — append to GRID_HOME listener.ora ===
for NODE in prim01 prim02; do
    case "$NODE" in
        prim01) NODE_SID=PRIM1 ;;
        prim02) NODE_SID=PRIM2 ;;
    esac
    ssh grid@${NODE} "cat >> /u01/app/23.26/grid/network/admin/listener.ora" <<LSNREOF

LISTENER_DGMGRL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${NODE}.lab.local)(PORT = 1522))
  )

SID_LIST_LISTENER_DGMGRL =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = PRIM_DGMGRL.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = ${NODE_SID})
    )
  )
LSNREOF
done

# srvctl add cluster-wide (one CRS resource ora.LISTENER_DGMGRL.lsnr on both nodes)
ssh grid@prim01 "srvctl add listener -listener LISTENER_DGMGRL -endpoints 'TCP:1522'"
ssh grid@prim01 "srvctl start listener -listener LISTENER_DGMGRL"
ssh grid@prim01 "srvctl status listener -listener LISTENER_DGMGRL"
# Expected: Listener LISTENER_DGMGRL is enabled, running on node(s): prim01,prim02

# === stby01 (Oracle Restart, HAS) — listener.ora in GRID_HOME, HAS resource ===
ssh grid@stby01 "mkdir -p /u01/app/23.26/grid/network/admin && cat >> /u01/app/23.26/grid/network/admin/listener.ora" <<'LSNREOF'

LISTENER_DGMGRL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
  )

SID_LIST_LISTENER_DGMGRL =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = STBY_DGMGRL.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = STBY)
    )
  )
LSNREOF

ssh grid@stby01 "srvctl add listener -listener LISTENER_DGMGRL -endpoints 'TCP:1522'"
ssh grid@stby01 "srvctl start listener -listener LISTENER_DGMGRL"
ssh grid@stby01 "srvctl status listener -listener LISTENER_DGMGRL"

# Verify CRS/HAS resource — STATE=ONLINE
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stat res -t | grep -B1 -A2 -i listener_dgmgrl"
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl stat res -t | grep -B1 -A2 -i listener_dgmgrl"

# === FIX-S28-48 persistent: CSSD AUTO_START=always on stby01 ===
# Without this, after a stby01 reboot CSSD is OFFLINE → srvctl throws PRCR-1055.
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl modify resource ora.cssd -attr 'AUTO_START=always' -init"
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl status resource ora.cssd -p -init | grep AUTO_START"

# Enable DG Broker for PRIM1 and PRIM2
# FIX-S28-40: dg_broker_config_file1/2 MUST be on shared storage (ASM) for RAC,
# otherwise PRIM2 won't see the broker config saved by PRIM1 → ORA-16532 in SHOW CONFIGURATION.
# We set this BEFORE the first DG_BROKER_START=TRUE — at startup the broker creates the files in ASM.
sqlplus / as sysdba
```
```sql
ALTER SYSTEM SET dg_broker_config_file1='+DATA/PRIM/dr1PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file2='+RECO/PRIM/dr2PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET DG_BROKER_START=TRUE SCOPE=BOTH SID='*';

-- FIX-S28-43: Standby Redo Logs (SRL) on PRIM — required when PRIM becomes standby
-- after switchover. 6 SRL = 3 per thread × 2 RAC threads, each sized as ORL (200M default).
-- In ASM (+DATA) because PRIM has OMF configured.
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 12 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 13 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 21 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 22 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 23 '+DATA' SIZE 200M;
EXIT;
```

Building Standby in Oracle 26ai: RMAN Duplicate → Post-RMAN setup → DGMGRL.

> **FIX-061 / FIX-075 / FIX-S28-35:** In Oracle 26ai the DGMGRL syntax and the Physical Standby creation flow have changed:
> - `ADD DATABASE ... MAINTAINED AS PHYSICAL` → removed (Physical is the default, the option is unnecessary)
> - `CREATE PHYSICAL STANDBY DATABASE` → **does not exist** in 26ai (confirmed: `help create` returns only `CREATE CONFIGURATION` and `CREATE FAR_SYNC`)
> - `CREATE CONFIGURATION` **must be invoked AFTER RMAN Duplicate** — the broker starts asynchronously (~20-30s after `DG_BROKER_START=TRUE`). Calling it before RMAN → ORA-16525.
>
> Correct flow: wait for the broker → RMAN DUPLICATE → POST-RMAN ALTER SYSTEM → DGMGRL CREATE CONFIG + ADD + ENABLE.

**Step 6 — Wait for DG Broker readiness (~30s)**

```bash
# The broker starts asynchronously after DG_BROKER_START=TRUE was set on prim01 in step 3
sleep 30
```

**Step 6a — RMAN Active Duplicate (a dozen-plus minutes)**

> **FIX-043:** RMAN Auxiliary connects to STBY using `SID=STBY` (not `SERVICE_NAME`), because in NOMOUNT mode `db_domain` is not active — `SERVICE_NAME=STBY.lab.local` does not match the listener.  
> **FIX-042:** The `remote_listener` parameter is reset (`SET remote_listener = ''`) — the RAC primary has `scan-prim.lab.local`, but the SI standby does not have a SCAN.  
> **FIX-041:** `SET cluster_database = 'FALSE'` — RMAN DUPLICATE copies the SPFILE from the RAC primary which has `cluster_database=TRUE`. On the SI standby (stby01) Oracle RAC is unavailable → `ORA-00439: feature not enabled: Real Application Clusters` at startup. The SET clause in the SPFILE clause is required.  
> **FIX-041 post-RMAN:** `cluster_database_instances` and `instance_number` — they CANNOT be in the RMAN SET clause (RMAN-06581 in 26ai). We set them via ALTER SYSTEM after the standby starts.  
> **FIX-S28-36:** `SET use_large_pages = 'FALSE'` — the RAC primary may have `use_large_pages=ONLY` or `TRUE` (HugePages configured on RAC nodes). stby01 has no HugePages configured → after restarting with the new SPFILE: `ORA-27106: system pages not available to allocate memory`.  
> **FIX-S28-37:** `SET db_create_file_dest`, `db_recovery_file_dest`, `db_recovery_file_dest_size`, `control_files` — the RAC primary uses OMF with `db_create_file_dest='+DATA'` and `db_recovery_file_dest='+RECO'`. The clone inherits these settings → on stby01 (XFS, no ASM) verify backupset fails: `ORA-19660: some files in the backup set could not be verified`, `ORA-19685: SPFILE could not be verified`, `ORA-19845: error in backupSetDatafile`, `ORA-01138: database must either be open in this instance or not at all`. Override all OMF-related parameters.  
> **FIX-S28-37 cleanup:** Step 3 (NOMOUNT) must clean `/u02/oradata/STBY/`, `/u03/fra/STBY/` and `$ORACLE_HOME/dbs/spfileSTBY.ora` from previous failed attempts (RMAN does not overwrite — it refuses with conflicts).  
> **FIX-S28-38:** The PRIM tnsnames must have `LOAD_BALANCE=off` + `FAILOVER=on` (NOT `LOAD_BALANCE=on`). Active Duplicate in 26ai with a RAC primary requires a deterministic connect to a single instance — the AUX channels do an RPC back to TARGET, and a load-balanced alias hits different RAC nodes → `ORA-01138: database must either be open in this instance or not at all` during `DBMS_BACKUP_RESTORE.RESTORESETPIECE` (a sign of PRIM1/PRIM2 state inconsistency seen by DBMS_BACKUP_RESTORE). Pin to prim01, fall back to prim02 if prim01 is down. Pattern known from VMs/FIXES_LOG FIX-085.

```bash
# On prim01 as oracle — RMAN connects via wallet to primary and directly to auxiliary
RMAN_AUX="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))(CONNECT_DATA=(SID=STBY)(UR=A)))"
TNS_ADMIN=~/tns_dgmgrl rman \
    target "/@PRIM" \
    auxiliary "sys/Oracle26ai_LAB!@\"$RMAN_AUX\""
```
```rman
DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE
NOFILENAMECHECK
SPFILE
  SET db_unique_name = 'STBY'
  SET cluster_database = 'FALSE'
  SET db_file_name_convert = '+DATA/PRIM/','/u02/oradata/STBY/','+RECO/PRIM/','/u03/fra/STBY/'
  SET log_file_name_convert = '+DATA/PRIM/','/u02/oradata/STBY/','+RECO/PRIM/','/u03/fra/STBY/'
  SET db_create_file_dest = '/u02/oradata/STBY'
  SET db_recovery_file_dest = '/u03/fra/STBY'
  SET db_recovery_file_dest_size = '14G'
  SET control_files = '/u02/oradata/STBY/control01.ctl','/u03/fra/STBY/control02.ctl'
  SET sga_target = '2048M'
  SET pga_aggregate_target = '512M'
  SET dg_broker_start = 'TRUE'
  SET remote_listener = ''
  SET local_listener = '(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))'
  SET fal_server = 'PRIM'
  SET fal_client = 'STBY'
  SET standby_file_management = 'AUTO'
  SET use_large_pages = 'FALSE';
```

**Step 6b — Post-RMAN setup on stby01 (FIX-041)**

```bash
# FIX-041: cluster_database_instances and instance_number CANNOT be in the RMAN SET clause
# (RMAN-06581 in 26ai) — we set them via ALTER SYSTEM after RMAN Duplicate
ssh oracle@stby01 "
export ORACLE_SID=STBY
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=\$ORACLE_HOME/bin:\$PATH
sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR CONTINUE;
-- ORA-02065 in SI (cluster_database=FALSE) — ignore, instance_number is enough
ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
WHENEVER SQLERROR EXIT FAILURE;
ALTER SYSTEM SET instance_number=1 SCOPE=SPFILE;
ALTER SYSTEM REGISTER;
EXIT;
SQL
"
```

**Step 6c — Standby Redo Logs (SRL) on STBY**

> **FIX-S28-43:** Real-time apply + FSFO require SRL on the standby. Without SRL, transport happens only after archiving → Apply Lag grows linearly, FSFO refuses to ENABLE. **6 SRL = 3 per thread × 2 RAC PRIM threads**, each sized as ORL (200M DBCA default). stby01 has no ASM — files go to XFS `/u02/oradata/STBY/onlinelog/`.

```bash
ssh oracle@stby01 "
export ORACLE_SID=STBY
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=\$ORACLE_HOME/bin:\$PATH
sqlplus -s / as sysdba <<SQL
ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 '/u02/oradata/STBY/onlinelog/srl_t1g11.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 12 '/u02/oradata/STBY/onlinelog/srl_t1g12.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 13 '/u02/oradata/STBY/onlinelog/srl_t1g13.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 21 '/u02/oradata/STBY/onlinelog/srl_t2g21.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 22 '/u02/oradata/STBY/onlinelog/srl_t2g22.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 23 '/u02/oradata/STBY/onlinelog/srl_t2g23.log' SIZE 200M;
ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH;
EXIT;
SQL
"
```

**Step 6d — DGMGRL: CREATE CONFIGURATION + ADD DATABASE + ENABLE**

```bash
TNS_ADMIN=~/tns_dgmgrl dgmgrl /@PRIM
```
```sql
CREATE CONFIGURATION fsfo_cfg AS PRIMARY DATABASE IS PRIM CONNECT IDENTIFIER IS "PRIM";
ADD DATABASE STBY AS CONNECT IDENTIFIER IS "STBY";
-- FIX-096: StaticConnectIdentifier with PORT=1522 (DGMGRL listener on the nodes).
EDIT DATABASE 'stby' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM1' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM1)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM2' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim02.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM2)(SERVER=DEDICATED)))';
ENABLE CONFIGURATION;
SHOW CONFIGURATION;
EXIT;
```

**Step 6e — MaxAvailability + LogXptMode=SYNC (FIX-S28-51)**

> Required for **Zero Data Loss** — consistent with `setup_observer.sh` setting `FastStartFailoverLagLimit=0`, the broker must operate in `MaxAvailability` with `SYNC` redo transport. Without this, ASYNC apply always has some lag → FSFO is blocked on every failure. The architecture in `docs/01` and scenario 4 in `docs/09` assume this configuration.

```bash
sleep 5  # the broker stabilizes after ENABLE CONFIGURATION
TNS_ADMIN=~/tns_dgmgrl dgmgrl /@PRIM <<'EOF'
EDIT DATABASE 'PRIM' SET PROPERTY 'LogXptMode'='SYNC';
EDIT DATABASE 'stby' SET PROPERTY 'LogXptMode'='SYNC';
EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;
SHOW CONFIGURATION;
EXIT
EOF
# Expected: Protection Mode: MaxAvailability, Configuration Status: SUCCESS
```

---

## 3. Verification

Once the Standby creation is complete, while still on `prim01` (as oracle), invoke DGMGRL to check the state of our topology:

```bash
dgmgrl sys/Oracle26ai_LAB!@PRIM
```

In the DGMGRL prompt issue the command:
```text
DGMGRL> SHOW CONFIGURATION;
```

The expected result should look like this (Status: SUCCESS):
```text
Configuration - fsfo_cfg

  Protection Mode: MaxPerformance
  Members:
  PRIM - Primary database
    STBY - Physical standby database

Fast-Start Failover:  Disabled

Configuration Status:
SUCCESS   (status updated 15 seconds ago)
```

When you see this status, it means Redo Transport is shipping data continuously and the Standby is applying it locally.

You can also verify it by connecting directly to the database on `stby01`:
```bash
ssh oracle@stby01
sqlplus / as sysdba
```
```sql
SELECT open_mode, database_role FROM v$database;
```
The Standby database will be in the role `PHYSICAL STANDBY` with mode `READ ONLY WITH APPLY` (Active Data Guard).

---

## Persistent Active Data Guard configuration (READ ONLY WITH APPLY survives STARTUP)

> **Goal:** STBY should **always** open in `READ ONLY WITH APPLY` (Real-Time Query), including after a stby01 reboot and after `SWITCHOVER TO PRIM` (when it is reinstated as standby). Without this, after every restart the operator has to manually `ALTER DATABASE OPEN READ ONLY` (a divergence vs the automated path).
>
> **Required license:** Active Data Guard option (see `01_Architecture` section 4.1).

In the automated path `create_standby_broker.sh` does this on its own (step 7). Manually:

```bash
# 1. Broker APPLY-OFF — we must stop MRP in order to save the PDB state.
#    From infra01 (where the SSO wallet lives):
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-OFF'"

# 2. Open CDB + all PDBs in READ ONLY and SAVE the state.
#    Directly on stby01 (as oracle):
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<EOF
-- If MOUNTED, open in READ ONLY.
DECLARE
    v_mode VARCHAR2(20);
BEGIN
    SELECT open_mode INTO v_mode FROM v\\\$database;
    IF v_mode = 'MOUNTED' THEN
        EXECUTE IMMEDIATE 'ALTER DATABASE OPEN READ ONLY';
    END IF;
END;
/

ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
-- SAVE STATE: persistent save — after every STARTUP the PDB comes back in READ ONLY automatically.
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
EXIT
EOF"

# FIX-S28-64: Modernization — register PDB as a CRS resource policy=AUTOMATIC + role=PRIMARY.
# In 26ai there is `srvctl modify pdb` (PDB as a CRS resource). After this CRS itself opens APPPDB
# in READ WRITE on every startup when `database_role='PRIMARY'`. In the standby role CRS
# leaves the PDB alone — Active DG manages READ ONLY itself.
# Without this: after every switchover/failover you must manually ALTER PLUGGABLE DATABASE OPEN
# READ WRITE + SAVE STATE (a relic of the previous role remains).
ssh oracle@prim01 ". ~/.bash_profile && srvctl modify pdb -db PRIM -pdb APPPDB -policy AUTOMATIC -role PRIMARY"
ssh oracle@stby01 ". ~/.bash_profile && srvctl modify pdb -db STBY -pdb APPPDB -policy AUTOMATIC -role PRIMARY"
# Verification:
ssh oracle@prim01 "srvctl config pdb -db PRIM -pdb APPPDB | grep -E 'Management|role'"
# Expected:
#   Management policy: AUTOMATIC
#   Pluggable database role: PRIMARY

# FIX-S28-48: Make sure CSSD on stby01 is ONLINE.
# CRS_SWONLY install + roothas.pl does NOT auto-start CSSD after boot. Without CSSD, srvctl
# throws PRCR-1055 "Cluster membership check failed for node stby01".
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl check css 2>&1 | grep -q 'is online' || \
    /u01/app/23.26/grid/bin/crsctl start resource ora.cssd -init"
sleep 15
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl check css"
# Expected: CRS-4529: Cluster Synchronization Services is online

# FIX-S28-46: Register STBY in HAS (Oracle Restart) on stby01.
# RMAN DUPLICATE does NOT register the database in HAS automatically. Without this step:
#   - srvctl status -db STBY → PRCD-1120 / PRCR-1001
#   - srvctl modify (below) throws PRCD-1120 — startoption is not set
#   - after a stby01 reboot the database does not start, crsctl stat res -t shows only ora.evmd + ora.ons
ssh oracle@stby01 "srvctl add database -db STBY \
    -oraclehome /u01/app/oracle/product/23.26/dbhome_1 \
    -spfile /u01/app/oracle/product/23.26/dbhome_1/dbs/spfileSTBY.ora \
    -role PHYSICAL_STANDBY \
    -startoption MOUNT \
    -policy AUTOMATIC \
    -domain lab.local"
ssh oracle@stby01 "srvctl config database -db STBY"
# Expected: full dump of database configuration in HAS (Database name: STBY, Role: PHYSICAL_STANDBY...)

# 3. Oracle Restart startoption — after a stby01 reboot the database opens immediately in RO
#    (instead of the default 'mount' for PHYSICAL_STANDBY).
ssh oracle@stby01 "srvctl modify database -db STBY -startoption 'READ ONLY'"
ssh oracle@stby01 "srvctl config database -db STBY | grep -i 'Start option'"
# Expected: Start option: read only

# FIX-S28-47: Hand off the database to HAS. After srvctl add the database is still running outside HAS — crsctl
# shows `ora.stby.db OFFLINE OFFLINE` even though the instance is alive. We need shutdown +
# srvctl start so that HAS takes control (otherwise after the first stby01 reboot the database will not start).
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-OFF'"
sleep 5
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<<'SHUTDOWN IMMEDIATE'"
ssh oracle@stby01 "srvctl start database -db STBY"
sleep 10

# Sanity check — HAS should now show ONLINE ONLINE
ssh grid@stby01 "crsctl stat res ora.stby.db -t"
# Expected: ora.stby.db ONLINE ONLINE stby01 Open Read Only,STABLE

# 4. Broker APPLY-ON — we resume Redo Apply, the database is in Real-Time Query mode under HAS.
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-ON'"
```

### Active DG configuration verification

```bash
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<'EOF'
SELECT name, open_mode, database_role FROM v\$database;
SELECT name, open_mode FROM v\$pdbs WHERE name <> 'PDB\$SEED';
EXIT
EOF"
# Expected:
#   STBY / READ ONLY WITH APPLY / PHYSICAL STANDBY
#   APPPDB / READ ONLY
```

```bash
# Restart resilience test — the database should come back in READ ONLY WITH APPLY.
ssh oracle@stby01 "srvctl stop database -db STBY && srvctl start database -db STBY"
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<<\"SELECT open_mode FROM v\\\$database;\""
# READ ONLY WITH APPLY    <- without manual commands, thanks to SAVE STATE + startoption
```

> 💡 After `SWITCHOVER TO PRIM` (Scenario 1 in docs/09) STBY returns to the PHYSICAL_STANDBY role, and `SAVE STATE` + `startoption=READ ONLY` ensure the broker does NOT ask the operator for `STARTUP`. This is key for switchover test automation (the divergence vs manual disappears).

---
**Next step:** `07_FSFO_Observers.md`
