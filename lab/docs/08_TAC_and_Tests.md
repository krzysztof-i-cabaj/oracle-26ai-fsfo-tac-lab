> 🇬🇧 English | [🇵🇱 Polski](./08_TAC_and_Tests_PL.md)

# 08 — Transparent Application Continuity and Reliability Tests (VMs2-install)

> **Goal:** Run an application service on the RAC cluster prepared for **Transparent Application Continuity (TAC)**. Configure FAN (Fast Application Notification) notifications via the ONS service between the cluster and the Standby node. Finally: prepare the client environment (`client01`), run the Java client application (UCP) and test the behavior of database sessions.

This document describes two methods of configuring the service and ONS: an automated (script-based) one and a fully manual step-by-step one. The verification and test process (Java loop) is common for both paths.

---

## Method 1: Quick Automated Path (Recommended)

In order for applications to flawlessly and losslessly restore their sessions and "replay" interrupted transactions on the fly on the Standby node, they must connect through a specially prepared application service `MYAPP_TAC`. Configuration of this service and ONS notifications can be done using two provided scripts.

```bash
# 1. Create the MYAPP_TAC service (as the oracle user on prim01)
su - oracle
bash /tmp/scripts/setup_tac_services.sh

# 2. Configure Cross-Site ONS (as the grid user on prim01)
# Important: the command modifying cluster ONS must be executed as the GI owner!
su - grid
bash /tmp/scripts/setup_cross_site_ons.sh
```

> **What the scripts do under the hood (embedded lessons):**
> - **`setup_tac_services.sh`** — (a) idempotent: `srvctl config service` check → `modify` instead of `add` if it exists (F-12, lesson: re-run safe); (b) TAC flags in a bash array (`failovertype TRANSACTION`, `failover_restore LEVEL1`, `commit_outcome TRUE`, `session_state DYNAMIC`, `notification TRUE` etc.); (c) `set -euo pipefail` (fail-fast); (d) post-create verify `failover_type|failover_restore|commit_outcome` via grep; (e) auto-registration on stby01 over SSH `setup_tac_services_stby.sh` (Step 1.5 of the manual path).
> - **`setup_cross_site_ons.sh`** — (a) `srvctl modify ons -remoteservers` WITHOUT the `-clusterid` flag (removed in 26ai, VMs/FIX-040); (b) remote reconfiguration of `ons.config` on stby01 with 3 nodes `nodes=...` (VMs/FIX-082 Gap 2); (c) systemd unit `oracle-ons.service` Type=forking (VMs/FIX-083 — persistence after stby01 reboot); (d) `onsctl ping` sanity-check.

If you ran both scripts, go directly to the **Readiness Check** section.

---

## Method 2: Manual Path (Step by step)

For those wanting to implement the parameters themselves using `srvctl` tools and modify the configuration on the Standby node without scripts.

### Step 1: Create the TAC Application Service on the cluster

> **Pre-flight (before `srvctl add service`):** verify that (a) the database is running (`srvctl status database -db PRIM` → "Instance PRIM1/PRIM2 is running"), (b) the PDB is registered with the listener (`lsnrctl services | grep APPPDB`), (c) the broker is in SUCCESS state (`dgmgrl /@PRIM_ADMIN "SHOW CONFIGURATION"`). Lesson: VMs/FIX-080 — without these checks the DBA debugs TAC replay 1-2h before finding the root cause.

> **Idempotency:** if the service already exists (re-run of the procedure), `srvctl add` will return `PRCD-1126: service already exists`. Then, instead of `add`, use `srvctl modify service -db PRIM -service MYAPP_TAC <flags>`. The automated script `setup_tac_services.sh` (F-12) detects this automatically.

Log in to **`prim01`** as the **`oracle`** user and create a special service equipped with TAC (Application Continuity) mechanisms:

```bash
# As oracle on prim01
srvctl add service \
    -db PRIM \
    -service MYAPP_TAC \
    -preferred PRIM1,PRIM2 \
    -pdb APPPDB \
    -failovertype TRANSACTION \
    -failover_restore LEVEL1 \
    -commit_outcome TRUE \
    -session_state DYNAMIC \
    -retention 86400 \
    -replay_init_time 1800 \
    -drain_timeout 300 \
    -stopoption IMMEDIATE \
    -role PRIMARY \
    -notification TRUE \
    -rlbgoal SERVICE_TIME \
    -clbgoal SHORT \
    -failoverretry 30 \
    -failoverdelay 10 \
    -policy AUTOMATIC

# Start the service
srvctl start service -db PRIM -service MYAPP_TAC

# Verify the key TAC attributes
srvctl config service -db PRIM -service MYAPP_TAC | \
  grep -E 'Pluggable|Failover type|Failover restore|Commit Outcome|Retention|Drain|Session State|Notification'
# Expected: Failover type: TRANSACTION, Failover restore: LEVEL1, Commit Outcome: true, ...
```

### Step 1.5: Register the service in Oracle Restart on `stby01` (in parallel with RAC)

> **Critical for post-failover auto-start.** `stby01` has **Grid Infrastructure for a Standalone Server (Oracle Restart)** — it is not a "bare" Single Instance. CRS at the host level manages the database and its services **analogously** to a Grid Cluster on RAC. If we register `MYAPP_TAC` with `-role PRIMARY` on Oracle Restart stby01, **CRS will start the service itself after a failover** (when STBY changes role to PRIMARY) — without the need for a manual `DBMS_SERVICE.START_SERVICE`.

```bash
# As oracle on stby01
srvctl add service \
    -db STBY \
    -service MYAPP_TAC \
    -pdb APPPDB \
    -failovertype TRANSACTION \
    -failover_restore LEVEL1 \
    -commit_outcome TRUE \
    -session_state DYNAMIC \
    -retention 86400 \
    -replay_init_time 1800 \
    -drain_timeout 300 \
    -stopoption IMMEDIATE \
    -role PRIMARY \
    -notification TRUE \
    -rlbgoal SERVICE_TIME \
    -clbgoal SHORT \
    -failoverretry 30 \
    -failoverdelay 10 \
    -policy AUTOMATIC

# NOTE: the service does NOT start now (stby01 has the PHYSICAL_STANDBY role) — the
# -role PRIMARY attribute tells Oracle Restart "start me only when this database is PRIMARY".
# After promotion (failover/switchover STBY→PRIMARY) Oracle Restart detects the change
# and automatically starts the service in 5–15 s.
srvctl status service -db STBY -service MYAPP_TAC
# Service MYAPP_TAC is not running.   ← expected before failover.
```

> **Idempotency:** as in Step 1, if the service already exists (re-run) → `PRCD-1126`. Use `srvctl modify service -db STBY -service MYAPP_TAC <flags>` instead of `add`.

> 💡 In the automated path `setup_tac_services.sh` invokes `setup_tac_services_stby.sh` over SSH — Step 1.5 happens automatically.

### Step 2: Configure FAN (ONS) notifications on the cluster

After a failure of the main cluster, clients must learn within a fraction of a second that Primary has failed and redirect their signal to `stby01`.

> **Note (VMs/FIX-040 / 26ai):** the `-clusterid` flag has been **removed** in 26ai. In 19c the correct form was `srvctl modify ons -clusterid <ONS_id> -remoteservers ...`. In 26ai we pass **only** `-remoteservers`.

> **Firewall pre-req (VMs/FIX-011):** port **6200/tcp** must be reachable between prim01/02 ↔ stby01. In our lab the firewall is disabled (kickstart); in production make sure to open it: `firewall-cmd --permanent --add-port=6200/tcp && firewall-cmd --reload`. Without this the UCP client will not receive FAN events → no TAC replay.

```bash
# As grid on prim01 — re-run safe (modify replaces the configuration)
srvctl modify ons -remoteservers stby01.lab.local:6200

# Verification
srvctl config ons | grep -E 'Cluster|Remote'
```

### Step 3: Configure ONS on the Standby node (`stby01`) — Oracle Restart

> **F-13:** `stby01` is Single Instance + Oracle Restart (NOT a GI Cluster), so `ons` is **not a CRS resource** and cannot be managed via `srvctl modify ons` like on a RAC cluster. The configuration is file-based + manual `onsctl`.

```bash
# As oracle on stby01
mkdir -p /u01/app/oracle/product/23.26/dbhome_1/opmn/conf

cat > /u01/app/oracle/product/23.26/dbhome_1/opmn/conf/ons.config <<EOF
usesharedinstall=true
localport=6100
remoteport=6200
nodes=stby01.lab.local:6200,prim01.lab.local:6200,prim02.lab.local:6200
EOF
# S28-62: in 26ai the keys 'loglevel' and 'useocr' are UNKNOWN (warning in onsctl ping).
# If you see "unkown key: loglevel" in the log - remove these lines from ons.config.

export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

onsctl stop 2>/dev/null || true
onsctl start
onsctl ping        # Expected: "Number of ons configured = 3" + "ons is running"
```

#### Step 3.a — Persistence via systemd (after stby01 reboot)

> **Gotcha (S28-62):** ExecStart pointing directly to `onsctl start` gives `status=203/EXEC` — onsctl requires the full env (`LD_LIBRARY_PATH`, `PATH`), not just `ORACLE_HOME` as in the systemd `Environment=` directive. Identical problem to S28-54 for the observer. Solution: a wrapper script.

So that `ons` starts automatically after a `stby01` restart:

**Step 3.a.1 — Wrapper scripts (as root):**
```bash
cat > /usr/local/bin/start-ons.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
exec $ORACLE_HOME/bin/onsctl start
EOF

cat > /usr/local/bin/stop-ons.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
exec $ORACLE_HOME/bin/onsctl stop
EOF

chmod 755 /usr/local/bin/start-ons.sh /usr/local/bin/stop-ons.sh
```

**Step 3.a.2 — systemd Unit:**
```bash
# As root
cat > /etc/systemd/system/oracle-ons.service <<'EOF'
[Unit]
Description=Oracle ONS daemon (FAN events for Standby)
After=network-online.target

[Service]
Type=forking
User=oracle
Group=oinstall
ExecStart=/usr/local/bin/start-ons.sh
ExecStop=/usr/local/bin/stop-ons.sh
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now oracle-ons.service

# Verification
systemctl status oracle-ons.service --no-pager -l | head -10
su - oracle -c 'export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1; export LD_LIBRARY_PATH=$ORACLE_HOME/lib; $ORACLE_HOME/bin/onsctl ping'
# Expected: "ons is running ..."
```

> After failover the UCP client receives the FAN event "service moved to standby" in < 1 s instead of waiting for the TCP timeout.

---

## 3.0 Pre-flight: application user and `test_log` table (F-10)

The `TestHarness.java` application performs `INSERT INTO app_user.test_log (instance, session_id, message)` — **the table must exist in the `APPPDB` PDB** before the client starts. One-time DDL:

```bash
# As oracle on prim01
sqlplus -s / as sysdba <<'EOF'
ALTER SESSION SET CONTAINER=APPPDB;

-- Lab convention: all passwords = Oracle26ai_LAB! (see 01_Architecture section 2).
CREATE USER app_user IDENTIFIED BY "Oracle26ai_LAB!";
GRANT CREATE SESSION, CREATE TABLE, UNLIMITED TABLESPACE TO app_user;
-- KEEP grants are required for full TAC replay (transaction guard).
GRANT KEEP DATE TIME, KEEP SYSGUID TO app_user;

ALTER SESSION SET CURRENT_SCHEMA=app_user;
CREATE TABLE app_user.test_log (
    id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    instance    VARCHAR2(16),
    session_id  NUMBER,
    message     VARCHAR2(1000),
    created     TIMESTAMP DEFAULT SYSTIMESTAMP
);
GRANT INSERT, SELECT ON app_user.test_log TO app_user;
EOF
```

> **Security:** in the **lab** we keep the convention of a single password `Oracle26ai_LAB!` for all accounts (a diagnostic simplification — never in production). In **production**, replace the password above with a value from a secret store and set `APP_PASSWORD` (or `LAB_PASS`) as an environment variable before starting `TestHarness`. The client itself has a three-step fallback: `APP_PASSWORD` env → `LAB_PASS` env → built-in lab default `Oracle26ai_LAB!`.

---

## 3. Readiness Check

Before letting client applications in, let's make sure the database is ready for TAC.

### 3.1 Pre-flight network/daemon (VMs/FIX-080 F5/F7)

```bash
# From prim01 as oracle: ONS reachability on stby01
nc -zv -w 5 stby01.lab.local 6200
# Expected: "Connection to stby01.lab.local 6200 port [tcp/*] succeeded!"

# Check the ONS daemon on stby01
ssh oracle@stby01 'onsctl ping'
# Expected: "Number of ons configured = 3" + "ons is running"
```

### 3.2 Full readiness check (TAC + broker + FSFO + Flashback)

From the project repository we will upload to the machine all the scripts contained in the `/tmp/sql/` directory.
(Where `<repo>` denotes the main folder of our new `VMs2-install` project.)

> **Note (VMs/FIX-082 Gap 1):** we use the `_26ai` variant of the script, because in 23ai/26ai the `GV$REPLAY_STAT_SUMMARY` view has been removed — the original `tac_full_readiness.sql` (19c) would throw ORA-00942.

```bash
# As oracle on prim01, run the validation script:
sqlplus -s / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql
```
If you see **PASS** in the notification columns, the system is 100% ready for environmental faults.

---

## 4. Preparing the Client Environment (`client01`)

Before we run the test application in Java, we must prepare the client machine. In a production environment these would be application machines (Application Servers).

Log in to **`client01`** as the **`root`** user.

### Step 4.1. Install the runtime environment (Java 17)

```bash
# Install OpenJDK 17
dnf install -y java-17-openjdk java-17-openjdk-devel

# Set the new Java as default
JAVA17=$(ls -d /usr/lib/jvm/java-17-openjdk-*/bin/java | head -1)
alternatives --set java "$JAVA17"

# Create directory structure for the application and libraries
mkdir -p /opt/lab/jars
mkdir -p /opt/lab/src
mkdir -p /opt/lab/tns
chown -R oracle:oinstall /opt/lab
```

### Step 4.2. Install JDBC and UCP libraries

Re-log in to **`client01`** as the **`oracle`** user. Copy the database drivers from any other cluster machine (e.g. `prim01`):

```bash
# Copy the required libraries from the main machine
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/jdbc/lib/ojdbc11.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/ucp/lib/ucp11.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/opmn/lib/ons.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/jlib/oraclepki.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/jdbc/lib/simplefan.jar /opt/lab/jars/
```

### Step 4.3. Configure the network connection

```bash
cat > /opt/lab/tns/tnsnames.ora <<'EOF'
MYAPP_TAC =
  (DESCRIPTION =
    (CONNECT_TIMEOUT=10)(RETRY_COUNT=20)(RETRY_DELAY=3)
    (TRANSPORT_CONNECT_TIMEOUT=3)
    (ADDRESS_LIST =
      (LOAD_BALANCE = OFF)
      (FAILOVER = ON)
      (ADDRESS = (PROTOCOL = TCP)(HOST = scan-prim.lab.local)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = MYAPP_TAC.lab.local)
    )
  )
EOF

# Export the environment variable
export TNS_ADMIN=/opt/lab/tns
echo "export TNS_ADMIN=/opt/lab/tns" >> ~/.bash_profile
```

---

## 5. Java application test (UCP + TAC)

The project in the `/tmp/src/` directory contains a test application in Java: `TestHarness.java`.

> **CRITICAL (VMs/FIX-084 F1):** the UCP client MUST use `oracle.jdbc.replay.OracleDataSourceImpl` as `setConnectionFactoryClassName(...)`. The standard `oracle.jdbc.pool.OracleDataSource` **does NOT support replay** — after a failover the client will get `ORA-03113: end-of-file on communication channel` instead of a transparent replay. Check in `TestHarness.java`:
> ```java
> pds.setConnectionFactoryClassName("oracle.jdbc.replay.OracleDataSourceImpl");  // ← TAC
> pds.setValidateConnectionOnBorrow(true);                                       // ← UCP best practice (FIX-084 V_C_O_B)
> ```

### Step 5.1. Compilation and run

While on **`client01`** as the **`oracle`** user, upload the Java file:
```bash
# Assuming you copied the file from /tmp/src/TestHarness.java to /opt/lab/src/
cp /tmp/src/TestHarness.java /opt/lab/src/
cd /opt/lab/src

# Compile
javac -cp '/opt/lab/jars/*' TestHarness.java

# Run (module workarounds required for Java 17+ to generate proxies for TAC classes in 23.x)
# NOTE (S28-63): -Doracle.net.tns_admin=... IS REQUIRED — JDBC thin does not read the TNS_ADMIN env.
# Without this: `ORA-17868: Unknown host specified.: MYAPP_TAC: Name or service not known`.
java -Doracle.net.tns_admin=/opt/lab/tns \
     --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
     --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
     -cp '/opt/lab/jars/*:.' TestHarness
```

You should see the result of Load Balancer communication (jumping between `PRIM1` and `PRIM2`):
```text
[1] SUCCESS: PRIM1  SID=502  rows=1
[2] SUCCESS: PRIM2  SID=212  rows=1
...
```

Further variants of testing this code (including triggering real faults, brutally killing instance processes on the fly and Data Guard mechanism blocks) are described in detail in **Step 09**.

---
**Next step:** `09_Test_Scenarios.md`
