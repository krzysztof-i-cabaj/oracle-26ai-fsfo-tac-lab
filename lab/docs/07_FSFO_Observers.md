> 🇬🇧 English | [🇵🇱 Polski](./07_FSFO_Observers_PL.md)

# 07 — FSFO Observer Installation and Configuration (VMs2-install)

> **Goal:** Install the Oracle Client (23.26.1 / 26ai) on an external host (`infra01`), deploy passwordless auto-login of the Wallet SSO type, and register the `observer` process that monitors Data Guard availability and triggers an automatic failover (Fast-Start Failover - FSFO) when something goes wrong.

Compatibility is especially important in this section, because the 26ai release brings fundamental differences in handling the broker, systemd, and authentication compared to 19c.

---

## Method 1: Quick Automatic Path (Recommended)

The automated script bypasses every gotcha (the so-called "FIXes") introduced in the latest Oracle 26ai (no security flag in rsp, the proper sqlnet.ora entry for the wallet, the updated `START OBSERVER` structure in systemd without a loop).

> **Pre-req:** files from the repo copied to `/tmp/` on each of the 3 hosts (infra01/prim01/stby01) via MobaXterm SCP:
> - `<repo>/scripts/` → `/tmp/scripts/`
> - `<repo>/response_files/` → `/tmp/response_files/` (only on infra01, for `client.rsp`)

### Step 1.1 — Master Observer `obs_ext` on infra01

Log in to **`infra01`** as **`root`**:
```bash
ls /tmp/scripts/setup_observer.sh /tmp/response_files/client.rsp

# Defaults: OBSERVER_ROLE=master, OBSERVER_NAME=obs_ext, OBSERVER_HOST=infra01.lab.local
bash /tmp/scripts/setup_observer.sh
```

The script performs the whole flow (Steps 1-6 from Method 2) in a single run — Oracle Client installation, TNS, wallet with 4 credentials (PRIM_ADMIN/STBY_ADMIN/PRIM/STBY), start/stop wrappers, systemd unit, ENABLE FAST_START FAILOVER, FSFO properties.

### Step 1.2 — Backup Observer `obs_dc` on prim01

Log in to **`prim01`** as **`root`**:
```bash
OBSERVER_ROLE=backup \
OBSERVER_NAME=obs_dc \
OBSERVER_HOST=prim01.lab.local \
ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1 \
bash /tmp/scripts/setup_observer.sh
```

The backup observer reuses the existing DB_HOME (no need to install the Oracle Client). The script creates `/etc/oracle/{tns,wallet}/obs_dc`, the wrappers, the unit `dgmgrl-observer-obs_dc.service`, and a local wallet with credentials.

### Step 1.3 — Backup Observer `obs_dr` on stby01

Log in to **`stby01`** as **`root`**:
```bash
OBSERVER_ROLE=backup \
OBSERVER_NAME=obs_dr \
OBSERVER_HOST=stby01.lab.local \
ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1 \
bash /tmp/scripts/setup_observer.sh
```

### Step 1.4 — Redundancy verification

From any host, as `oracle`:
```bash
TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN "SHOW OBSERVERS"
# (on prim01/stby01 use /etc/oracle/tns/obs_dc or obs_dr)
```

Expected output — **3 observers**, one `Active`, two `Standby`:
```
Configuration - fsfo_cfg
  Primary:            PRIM
  Active Target:      stby
  Active Observer:    obs_ext
  ...
Observer "obs_ext" - Master
  Host Name: infra01.lab.local
  Last Ping to Primary: ... seconds ago
Observer "obs_dc" - Backup
  Host Name: prim01.lab.local
Observer "obs_dr" - Backup
  Host Name: stby01.lab.local
```

After success, jump straight to **2. Operation Verification**.

---

## Method 2: Manual Path (Step by Step)

For those who want to see step by step how the Observer configuration works under the latest 26ai system.

### Step 1: User and shell preparation

Log in to **`infra01`** as the **`root`** user:

```bash
# Create the oinstall, dba roles
groupadd -g 54321 oinstall 2>/dev/null || true
groupadd -g 54322 dba 2>/dev/null || true
groupadd -g 54325 dgdba 2>/dev/null || true
useradd -u 54322 -g oinstall -G dba,dgdba oracle 2>/dev/null || true
echo "oracle:Oracle26ai_LAB!" | chpasswd

mkdir -p /u01/app/oracle/product/23.26/client_1
mkdir -p /u01/app/oraInventory
chown -R oracle:oinstall /u01/app
chmod -R 775 /u01/app
```

### Step 2: Oracle Client 26ai installation

```bash
# As oracle on infra01
su - oracle
mkdir -p /tmp/client
cd /tmp/client

# Unpack the installer
unzip -q /mnt/oracle_binaries/V1054587-01-OracleDatabaseClient23.26.1.0.0forLinux_x86-64.zip

# Silent installation in "Administrator" mode (it ships the mkstore and dgmgrl we need)
# NOTE (S28-52): the rspfmt_clientinstall_response_schema_v23.0.0 schema in 26ai is STRICT.
# Accepted keys: oracle.install.responseFileVersion, UNIX_GROUP_NAME, INVENTORY_LOCATION,
# ORACLE_HOME, ORACLE_BASE, oracle.install.client.installType. Any extra key
# (e.g. oracle.install.option, executeRootScript, DECLINE_SECURITY_UPDATES) -> INS-10105.
# See response_files/client.rsp v2.2 and VMs/FIXES_LOG FIX-070.
./client/runInstaller -silent -responseFile /tmp/response_files/client.rsp -ignorePrereqFailure
```

Once the installer finishes, switch back to the ROOT account (or use a second terminal window) and run the post-installation script:
```bash
# As root
/u01/app/oraInventory/orainstRoot.sh
```

Switch back to the `oracle` account and update the environment variables:
```bash
# As oracle on infra01
cat >> /home/oracle/.bash_profile <<'EOF'
export ORACLE_HOME=/u01/app/oracle/product/23.26/client_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
export TNS_ADMIN=/etc/oracle/tns/obs_ext
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
umask 022
EOF

source /home/oracle/.bash_profile
```

### Step 3: TNSNAMES and SQLNET (26ai specifics)

Create the appropriate structure for logs, credentials, and tnsnames:

```bash
# As root (and hand over ownership to the oracle user)
mkdir -p /etc/oracle/tns/obs_ext
mkdir -p /etc/oracle/wallet/obs_ext
mkdir -p /var/log/oracle/obs_ext

chown -R oracle:oinstall /etc/oracle/tns
chown -R oracle:oinstall /etc/oracle/wallet
chown -R oracle:oinstall /var/log/oracle
chmod -R 755 /etc/oracle/tns
chmod -R 700 /etc/oracle/wallet
chmod -R 755 /var/log/oracle
```

Now configure the connection entries to the databases:

```bash
# As oracle on infra01
cat > /etc/oracle/tns/obs_ext/tnsnames.ora <<'EOF'
# FIX-040 / S28-29: SERVICE_NAME must carry the .lab.local suffix — Oracle 23.26.1 with db_domain=lab.local
# registers services as NAME.lab.local. Without the suffix → ORA-12514.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on (deterministic connect, fallback failover).
# _ADMIN aliases: port 1522 (LISTENER_DGMGRL) — used by `dgmgrl /@PRIM_ADMIN` (broker control).
PRIM_ADMIN =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1522))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1522))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM_DGMGRL.lab.local)(UR = A))
  )
STBY_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY_DGMGRL.lab.local)(UR = A))
  )

# S28-56: PRIM/STBY aliases = the observer's DGConnectIdentifier. After START OBSERVER, the broker
# returns the DGConnectIdentifier to the observer (default = db_unique_name) and the observer tries
# `connect /@PRIM` and `connect /@STBY`. Without these aliases, ORA-12154 in the observer log.
# Port 1521 (LISTENER), SERVICE_NAME = db_unique_name.lab.local.
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
```

And now the most important part: the SQLNET parameter for the Oracle 26ai wallet (FIX-072):

```bash
cat > /etc/oracle/tns/obs_ext/sqlnet.ora <<'EOF'
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = /etc/oracle/wallet/obs_ext)))
SQLNET.WALLET_OVERRIDE = TRUE
# FIX-072: Must be (NONE), so that NTS authentication is not forced instead of using the local Wallet file
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNET.EXPIRE_TIME = 1
EOF
```

### Step 4: Auto-Login Wallet creation

The observer uses the wallet to log in as "SYS" without typing passwords.

**Interactive variant** — the installer will prompt for the password (type `Oracle26ai_LAB!`):

```bash
# As oracle on infra01
mkstore -wrl /etc/oracle/wallet/obs_ext -create
# Enter password: Oracle26ai_LAB!
# Enter password again: Oracle26ai_LAB!

mkstore -wrl /etc/oracle/wallet/obs_ext -createCredential PRIM_ADMIN sys 'Oracle26ai_LAB!'
# Enter wallet password: Oracle26ai_LAB!

mkstore -wrl /etc/oracle/wallet/obs_ext -createCredential STBY_ADMIN sys 'Oracle26ai_LAB!'
# Enter wallet password: Oracle26ai_LAB!

# NOTE (S28-53): in 26ai mkstore creates cwallet.sso AUTOMATICALLY on `-create`,
# so `-autoLogin` / `-createSSO` is optional. Verify:
ls -la /etc/oracle/wallet/obs_ext/    # → cwallet.sso, ewallet.p12
```

**Non-interactive variant** — password via stdin (recommended for scripts, idempotent):

```bash
# As oracle on infra01
WP='Oracle26ai_LAB!'
WL='/etc/oracle/wallet/obs_ext'

# 1. Wallet — skip if it already exists
if [ ! -f "$WL/cwallet.sso" ]; then
    printf '%s\n%s\n' "$WP" "$WP" | mkstore -wrl "$WL" -create -nologo
fi

# 2. Idempotent helper (list -> create OR modify)
ensure_cred() {
    local ALIAS=$1
    # -qw (word-boundary) — without it, grep "PRIM" also catches "PRIM_ADMIN" (S28-57-bis)
    if printf '%s\n' "$WP" | mkstore -wrl "$WL" -listCredential -nologo 2>/dev/null | grep -qw "$ALIAS"; then
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -modifyCredential "$ALIAS" sys "$WP" -nologo
    else
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -createCredential "$ALIAS" sys "$WP" -nologo
    fi
}

ensure_cred PRIM_ADMIN
ensure_cred STBY_ADMIN
# S28-57: PRIM/STBY aliases must also live in the wallet — after START, the observer logs
# in to PRIM/STBY (DGConnectIdentifier); without credentials → DGM-16979 Authentication failed.
ensure_cred PRIM
ensure_cred STBY
```

> **Gotcha (S28-53 / FIX-071 from VMs):** the `-p <pwd>` flag in `mkstore -create` does NOT work in 26ai — the tool still prompts interactively. If the script passes `-p ""` (e.g. after `su -p oracle <<'EOF'` with apostrophes blocking expansion), you will get `PKI-01003: Passwords did not match` after a few timeouts. Always use stdin (heredoc without apostrophes).

### Step 5: SystemD configuration and Observer start

To keep the observer running in the background, we will create a `systemd` service. The 26ai release (FIX-074, FIX-075) forbids the `-logfile` parameter outside the process and the use of `IN BACKGROUND` with `Type=simple`.

> **Gotcha (S28-54):** `START OBSERVER ... FILE IS '...' LOGFILE IS '...'` contains apostrophes. Pasting that directly into `ExecStart=` produces `status=203/EXEC` (the systemd parser does not handle embedded single-quotes in a double-quoted argument). The fix: a wrapper script `/usr/local/bin/start-observer-obs_ext.sh` that uses `bash` (where quoting works) and runs `exec dgmgrl ...`.

**Step 5a — Wrapper scripts (as root):**

```bash
cat > /usr/local/bin/start-observer-obs_ext.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/client_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_ext
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
exec $ORACLE_HOME/bin/dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_ext FILE IS '/var/log/oracle/obs_ext/obs_ext.dat' LOGFILE IS '/var/log/oracle/obs_ext/obs_ext.log'"
EOF

cat > /usr/local/bin/stop-observer-obs_ext.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/client_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_ext
exec $ORACLE_HOME/bin/dgmgrl /@PRIM_ADMIN "STOP OBSERVER obs_ext"
EOF

chmod 755 /usr/local/bin/start-observer-obs_ext.sh /usr/local/bin/stop-observer-obs_ext.sh
```

**Step 5b — systemd unit:**

```bash
# As root
cat > /etc/systemd/system/dgmgrl-observer-obs_ext.service <<'EOF'
[Unit]
Description=Oracle Data Guard Observer obs_ext (FSFO master)
After=network-online.target chronyd.service

[Service]
Type=simple
User=oracle
Group=oinstall
WorkingDirectory=/var/log/oracle/obs_ext

ExecStart=/usr/local/bin/start-observer-obs_ext.sh
ExecStop=/usr/local/bin/stop-observer-obs_ext.sh

Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dgmgrl-observer-obs_ext
```

### Step 6: Fast-Start Failover (FSFO) activation

After 15 seconds, the Observer will fully connect to the configuration. All that remains is to activate FSFO mode at the broker level.
(Taking into account FIX-077, which enforces `FastStartFailoverLagLimit=0` to guarantee Zero Data Loss.)

> **F-22 — Threshold vs LagLimit (understand the difference before changing):**
> - `FastStartFailoverThreshold=30` → how many seconds the Observer + Standby wait for the Primary to recover before triggering a failover. Lower = faster failover, but more false alarms (e.g. a brief network blip).
> - `FastStartFailoverLagLimit=0` → the maximum allowed standby **apply lag** at the moment of failover.
>   - `0` = **Zero Data Loss** (requires **MaxAvailability** / SYNC); FSFO blocks the failover if the standby is behind the primary on apply.
>   - `> 0` (e.g. 30 s) = "Potential Data Loss" mode, for **MaxPerformance** / ASYNC; we accept the potential loss of 30 s of redo so that the failover can proceed.
> The LAB configuration uses SYNC + `LagLimit=0`. Before changing this in production, confirm the DG Protection mode (`SHOW CONFIGURATION` → `Protection Mode`) and the RPO consequences.

```bash
# As oracle
dgmgrl /@PRIM_ADMIN
```
```sql
EDIT CONFIGURATION SET PROPERTY FastStartFailoverThreshold=30;
EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
EDIT CONFIGURATION SET PROPERTY FastStartFailoverAutoReinstate=TRUE;
EDIT CONFIGURATION SET PROPERTY ObserverOverride=TRUE;

ENABLE FAST_START FAILOVER;
EXIT;
```

---

## 6. Backup Observers Deployment (`obs_dc` + `obs_dr`) — STEP BY STEP

> **Rationale:** the Master Observer (`obs_ext`) is a single point of failure. The architecture in `01_Architecture_and_Assumptions.md` assumes redundancy — `obs_dc` on `prim01` and `obs_dr` on `stby01`. If `infra01` fails, one of the Backup Observers automatically takes over the Active role within ~10–60 s.

> **Key prerequisite:** the Backup Observer must run the same `dgmgrl` version as the Master. On prim01/stby01 we do NOT install the Oracle Client — we use the existing `dgmgrl` from the DB Home (`/u01/app/oracle/product/23.26/dbhome_1/bin/dgmgrl`).

> **Pattern:** the procedure below is analogous for both observers. The differences — only the name (`obs_dc` vs `obs_dr`) and the host (`prim01` vs `stby01`).

### Step 6.1 — Backup Observer `obs_dc` on `prim01`

**6.1.a — Directories (root@prim01):**
```bash
mkdir -p /etc/oracle/tns/obs_dc /etc/oracle/wallet/obs_dc /var/log/oracle/obs_dc
chown -R oracle:oinstall /etc/oracle/tns/obs_dc /etc/oracle/wallet/obs_dc /var/log/oracle/obs_dc
chmod 700 /etc/oracle/wallet/obs_dc
chmod 755 /etc/oracle/tns/obs_dc /var/log/oracle/obs_dc
```

**6.1.b — tnsnames.ora and sqlnet.ora (oracle@prim01):**
```bash
cat > /etc/oracle/tns/obs_dc/tnsnames.ora <<'EOF'
PRIM_ADMIN =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1522))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1522))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM_DGMGRL.lab.local)(UR = A))
  )
STBY_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY_DGMGRL.lab.local)(UR = A))
  )
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

cat > /etc/oracle/tns/obs_dc/sqlnet.ora <<'EOF'
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = /etc/oracle/wallet/obs_dc)))
SQLNET.WALLET_OVERRIDE = TRUE
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNET.EXPIRE_TIME = 1
EOF
```

**6.1.c — Wallet with 4 credentials (oracle@prim01):**
```bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=/etc/oracle/tns/obs_dc

WP='Oracle26ai_LAB!'
WL='/etc/oracle/wallet/obs_dc'

if [ ! -f "$WL/cwallet.sso" ]; then
    printf '%s\n%s\n' "$WP" "$WP" | mkstore -wrl "$WL" -create -nologo
fi

ensure_cred() {
    local ALIAS=$1
    if printf '%s\n' "$WP" | mkstore -wrl "$WL" -listCredential -nologo 2>/dev/null | grep -qw "$ALIAS"; then
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -modifyCredential "$ALIAS" sys "$WP" -nologo
    else
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -createCredential "$ALIAS" sys "$WP" -nologo
    fi
}
ensure_cred PRIM_ADMIN
ensure_cred STBY_ADMIN
ensure_cred PRIM
ensure_cred STBY
```

**6.1.d — start/stop wrappers (root@prim01):**
```bash
cat > /usr/local/bin/start-observer-obs_dc.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dc
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
exec $ORACLE_HOME/bin/dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_dc FILE IS '/var/log/oracle/obs_dc/obs_dc.dat' LOGFILE IS '/var/log/oracle/obs_dc/obs_dc.log'"
EOF

cat > /usr/local/bin/stop-observer-obs_dc.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dc
exec $ORACLE_HOME/bin/dgmgrl /@PRIM_ADMIN "STOP OBSERVER obs_dc"
EOF

chmod 755 /usr/local/bin/start-observer-obs_dc.sh /usr/local/bin/stop-observer-obs_dc.sh
```

**6.1.e — systemd unit (root@prim01):**
```bash
cat > /etc/systemd/system/dgmgrl-observer-obs_dc.service <<'EOF'
[Unit]
Description=Oracle Data Guard Observer obs_dc (FSFO backup)
After=network-online.target chronyd.service

[Service]
Type=simple
User=oracle
Group=oinstall
WorkingDirectory=/var/log/oracle/obs_dc
ExecStart=/usr/local/bin/start-observer-obs_dc.sh
ExecStop=/usr/local/bin/stop-observer-obs_dc.sh
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dgmgrl-observer-obs_dc
```

> **Note (S28-59):** the Backup Observer does NOT run `EDIT CONFIGURATION SET PROPERTY` or `ADD OBSERVER` — in 26ai the broker auto-registers the observer on `START OBSERVER` (called via the wrapper). Master is already Active → the broker automatically registers it as Backup. The legacy `ADD OBSERVER ... ON HOST '...'` from 19c throws `Syntax error before or at "OBSERVER"` in 26ai.

### Step 6.2 — Backup Observer `obs_dr` on `stby01`

The procedure is analogous to 6.1. All commands run on **stby01** (not prim01); the observer name is `obs_dr`.

**6.2.a — Directories (root@stby01):**
```bash
mkdir -p /etc/oracle/tns/obs_dr /etc/oracle/wallet/obs_dr /var/log/oracle/obs_dr
chown -R oracle:oinstall /etc/oracle/tns/obs_dr /etc/oracle/wallet/obs_dr /var/log/oracle/obs_dr
chmod 700 /etc/oracle/wallet/obs_dr
chmod 755 /etc/oracle/tns/obs_dr /var/log/oracle/obs_dr
```

**6.2.b — tnsnames.ora and sqlnet.ora (oracle@stby01):**
```bash
cat > /etc/oracle/tns/obs_dr/tnsnames.ora <<'EOF'
PRIM_ADMIN =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1522))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1522))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM_DGMGRL.lab.local)(UR = A))
  )
STBY_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY_DGMGRL.lab.local)(UR = A))
  )
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

cat > /etc/oracle/tns/obs_dr/sqlnet.ora <<'EOF'
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = /etc/oracle/wallet/obs_dr)))
SQLNET.WALLET_OVERRIDE = TRUE
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNET.EXPIRE_TIME = 1
EOF
```

**6.2.c — Wallet with 4 credentials (oracle@stby01):**
```bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=/etc/oracle/tns/obs_dr

WP='Oracle26ai_LAB!'
WL='/etc/oracle/wallet/obs_dr'

if [ ! -f "$WL/cwallet.sso" ]; then
    printf '%s\n%s\n' "$WP" "$WP" | mkstore -wrl "$WL" -create -nologo
fi

ensure_cred() {
    local ALIAS=$1
    if printf '%s\n' "$WP" | mkstore -wrl "$WL" -listCredential -nologo 2>/dev/null | grep -qw "$ALIAS"; then
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -modifyCredential "$ALIAS" sys "$WP" -nologo
    else
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -createCredential "$ALIAS" sys "$WP" -nologo
    fi
}
ensure_cred PRIM_ADMIN
ensure_cred STBY_ADMIN
ensure_cred PRIM
ensure_cred STBY
```

**6.2.d — start/stop wrappers (root@stby01):**
```bash
cat > /usr/local/bin/start-observer-obs_dr.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dr
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
exec $ORACLE_HOME/bin/dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_dr FILE IS '/var/log/oracle/obs_dr/obs_dr.dat' LOGFILE IS '/var/log/oracle/obs_dr/obs_dr.log'"
EOF

cat > /usr/local/bin/stop-observer-obs_dr.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dr
exec $ORACLE_HOME/bin/dgmgrl /@PRIM_ADMIN "STOP OBSERVER obs_dr"
EOF

chmod 755 /usr/local/bin/start-observer-obs_dr.sh /usr/local/bin/stop-observer-obs_dr.sh
```

**6.2.e — systemd unit (root@stby01):**
```bash
cat > /etc/systemd/system/dgmgrl-observer-obs_dr.service <<'EOF'
[Unit]
Description=Oracle Data Guard Observer obs_dr (FSFO backup)
After=network-online.target chronyd.service

[Service]
Type=simple
User=oracle
Group=oinstall
WorkingDirectory=/var/log/oracle/obs_dr
ExecStart=/usr/local/bin/start-observer-obs_dr.sh
ExecStop=/usr/local/bin/stop-observer-obs_dr.sh
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dgmgrl-observer-obs_dr
```

### Step 6.3 — Redundancy verification

```bash
su - oracle
dgmgrl /@PRIM_ADMIN
```
```text
DGMGRL> SHOW OBSERVERS;

Configuration - fsfo_cfg
   Primary:            PRIM
   Active Target:      STBY

Observer "obs_ext" - Master
   Host Name:                    infra01.lab.local
   Last Ping to Primary:         1 second ago
   Last Ping to Target:          1 second ago

Observer "obs_dc" - Backup
   Host Name:                    prim01.lab.local
   Last Ping to Primary:         2 seconds ago
   Last Ping to Target:          2 seconds ago

Observer "obs_dr" - Backup
   Host Name:                    stby01.lab.local
   Last Ping to Primary:         2 seconds ago
   Last Ping to Target:          2 seconds ago
```

> After an `obs_ext` outage (e.g. `infra01` crash), DGMGRL will promote one of the Backups to **Master** within 10–60 s. `SHOW FAST_START FAILOVER` still reports `ENABLED`. Scenario test in `09_Test_Scenarios.md`.

---

## 2. Operation Verification

Log in to **`infra01`** (or any other cluster node) as `oracle` and start DGMGRL using the new Wallet SSO (i.e. without supplying the password on the command line):

```bash
su - oracle
dgmgrl /@PRIM_ADMIN
```

In the `DGMGRL>` shell, issue the command:
```text
DGMGRL> SHOW FAST_START FAILOVER;
```

The expected output should clearly indicate that the mechanism is enabled and the Observer is registered:
```text
Fast-Start Failover: ENABLED

  Threshold:           30 seconds
  Target:              STBY
  Observer:            obs_ext
  Lag Limit:           0 seconds
  Shutdown Primary:    TRUE
  Auto-reinstate:      TRUE
  Observer Reconnect:  10 seconds
  Observer Override:   TRUE
```

Remember to confirm the status of the broker as a whole:
```text
DGMGRL> SHOW CONFIGURATION;
```
If `Configuration Status` shows `SUCCESS` and no `Warnings` appear, your Maximum Availability architecture with FSFO is working correctly, and in case of a sudden `SHUTDOWN ABORT` on `prim01/prim02` the system will move production roles to `stby01` within 30–40 seconds.

---
**Next step:** `08_TAC_and_Tests.md`
