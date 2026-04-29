> 🇬🇧 English | [🇵🇱 Polski](./OPERATIONS_PL.md)

# OPERATIONS.md — Operator runbook for the Oracle 26ai HA MAA lab

> Startup/shutdown/status commands for the 5-VM Oracle 26ai lab (RAC + Active DG + Multi-Observer FSFO + TAC).
> All commands run on the host (Windows PowerShell) + inside VMs (Linux bash).
> Author: KCB Kris | Version: 1.0 | Date: 2026-04-28
>
> **Lab conventions** (per memory `feedback_lab_conventions.md`):
> - One password everywhere: `Oracle26ai_LAB!` (admin), root/oracle/grid/kris = `Welcome1#` (OS)
> - Persistent Active DG: STBY is always `READ ONLY WITH APPLY` (broker manages it)
> - Multi-Observer: master `obs_ext` (infra01) + backup `obs_dc` (prim01) + backup `obs_dr` (stby01)
> - stby01 = Oracle Restart (HAS `CRS_SWONLY` + `roothas.pl`) → STBY auto-starts after VM reboot
> - Auto-mode preferred: scripts from `scripts/` instead of manual commands

## Topology (reminder)

| VM | Role | RAM | Network (host-only) | ORACLE_SID |
|----|------|-----|------------------|------------|
| `infra01` | DNS bind9 + NTP + iSCSI Target + Master Observer `obs_ext` | 8 GB | 192.168.56.10 | — |
| `prim01` | RAC node 1 + Backup Observer `obs_dc` | 9 GB | 192.168.56.11 | PRIM1 (DB) / +ASM1 (grid) |
| `prim02` | RAC node 2 | 9 GB | 192.168.56.12 | PRIM2 (DB) / +ASM2 (grid) |
| `stby01` | Single Instance + Oracle Restart + Backup Observer `obs_dr` | 6 GB | 192.168.56.13 | STBY (DB) / +ASM (grid) |
| `client01` | OpenJDK 17 + Oracle Client + TestHarness UCP/TAC | 3 GB | 192.168.56.15 | — |

## Environment variables (on the host)

```powershell
# PowerShell — use in every operations session
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$VMs  = @("infra01", "prim01", "prim02", "stby01", "client01")
```

---

## 🟢 Cold START — bringing up the full environment

> **The order is critical.** Do NOT start all VMs simultaneously:
> - DNS must be ready before prim01/02 start CRS (they need to resolve SCAN names, peer nodes)
> - The iSCSI target must be listening before ASM can see the LUNs
> - The standby (stby01) needs the primary OPEN so the broker can set `READ ONLY WITH APPLY`
> - The observer registers last — the broker must have both databases available

### Step 1 — infra01 (DNS + NTP + iSCSI target + master Observer)

```powershell
# From the host
& $VBox startvm infra01 --type headless

# Wait ~60s for full boot (named, chronyd, target.service)
Start-Sleep -Seconds 60
```

**Verification on infra01 (as root):**

```bash
ssh root@infra01 "systemctl is-active named chronyd target"
# Expected: active / active / active

ssh root@infra01 "ss -ntl | grep -E ':53|:123|:3260'"
# Expected: listening on 53 (DNS), 123 (NTP UDP), 3260 (iSCSI TCP)

# DNS resolves
ssh root@infra01 "nslookup scan-prim.lab.local 127.0.0.1; nslookup stby01.lab.local 127.0.0.1"
```

### Step 2 — prim01 + prim02 (RAC nodes — can run in parallel)

```powershell
# Can be started in parallel - VirtualBox handles it
& $VBox startvm prim01 --type headless
& $VBox startvm prim02 --type headless

# Wait ~3-5 min for full boot + CRS stack start + ASM mount + DB open
Start-Sleep -Seconds 240
```

**CRS verification (as grid on prim01):**

```bash
ssh grid@prim01 ". ~/.bash_profile && crsctl check cluster -all"
# Expected: CRS-4537/4529/4533 ONLINE on both nodes

ssh grid@prim01 ". ~/.bash_profile && crsctl stat res -t"
# Expected (key resources):
#   ora.LISTENER.lsnr     ONLINE/ONLINE on both nodes
#   ora.LISTENER_SCAN1..3 ONLINE
#   ora.asm               ONLINE/ONLINE
#   ora.DATA.dg / ora.RECO.dg / ora.OCR.dg   MOUNTED
#   ora.prim.db           Open on prim01 and prim02 (NOTE: NOT Mounted!)
#   ora.prim.apppdb.pdb   READ WRITE on prim01 and prim02

# Check iSCSI sessions (FIX-032 from VMs/FIXES_LOG: persistent reconnect)
ssh root@prim01 "iscsiadm -m session"
ssh root@prim02 "iscsiadm -m session"
# Expected: tcp: [N] 192.168.200.10:3260,1 ... per node
```

**If iSCSI is not logged in** (rare, but happens when infra01 is slow to start):

```bash
ssh root@prim01 "iscsiadm -m node --loginall=automatic"
ssh root@prim02 "iscsiadm -m node --loginall=automatic"
sleep 30
ssh grid@prim01 ". ~/.bash_profile && crsctl start cluster -all"
# After ~3 min CRS will come up by itself (CSSD sees voting disks from +OCR)
```

**PRIM database verification (critical — both instances OPEN!):**

```bash
ssh oracle@prim01 ". ~/.bash_profile && srvctl status database -db PRIM -verbose"
# Expected:
#   Instance PRIM1 is running on node prim01 with online services PRIM_APPPDB. Instance status: Open
#   Instance PRIM2 is running on node prim02 with online services PRIM_APPPDB. Instance status: Open
#
# NOTE (lesson from S28-38): if any instance is "Mounted (Closed)" → DG broker and RMAN
# will throw ORA-01138. Fix:
#   srvctl stop instance -db PRIM -instance PRIM2 -force
#   srvctl start instance -db PRIM -instance PRIM2 -startoption OPEN
```

**LISTENER_DGMGRL (port 1522) — CRS-managed, auto-start ✓** (FIX-S28-49)

```bash
# Check status (should be ONLINE without a manual start)
ssh grid@prim01 ". ~/.bash_profile && srvctl status listener -listener LISTENER_DGMGRL"
# Expected: Listener LISTENER_DGMGRL is enabled, running on node(s): prim01,prim02

# Verify static service registration
ssh oracle@prim01 ". ~/.bash_profile && lsnrctl status LISTENER_DGMGRL | grep -E 'Service|STATUS' | head -5"
# Expected: 'Service "PRIM_DGMGRL.lab.local" has 1 instance(s)'
```

### Step 3 — stby01 (Single Instance + Oracle Restart)

> ⚠ stby01 = Oracle Restart (HAS). After VM boot:
> - The HAS daemon (ohasd) starts itself (systemd unit `oracle-ohasd.service`)
> - **CSSD requires an EXPLICIT start** (FIX-S28-48: a `CRS_SWONLY` install does not auto-start CSSD)
> - Once CSSD is UP: HAS starts the STBY database (if `-startoption READ ONLY` was set by S28-46)
> - The DMON broker comes up with the database → it picks up state from primary and maintains `READ ONLY WITH APPLY`
> - **Do NOT do a manual `STARTUP MOUNT + OPEN READ ONLY + RECOVER`** — the broker does this itself (persistent Active DG)

```powershell
& $VBox startvm stby01 --type headless
Start-Sleep -Seconds 120
```

**CSSD on stby01 — AUTO_START=always, auto-start ✓** (FIX-S28-48)

```bash
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl check css"
# Expected: CRS-4529: Cluster Synchronization Services is online
# If exceptionally OFFLINE (after the first deploy before AUTO_START was set):
#   ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl start resource ora.cssd -init"
```

**HAS + STBY verification:**

```bash
ssh grid@stby01 ". ~/.bash_profile && crsctl check has"
# Expected: CRS-4638: Oracle High Availability Services is online

ssh grid@stby01 ". ~/.bash_profile && crsctl stat res -t"
# Expected:
#   ora.LISTENER.lsnr   ONLINE
#   ora.asm             ONLINE
#   ora.DATA_STBY.dg    ONLINE (if we use ASM on stby) or /u02 mount (XFS)
#   ora.stby.db         ONLINE (Open) — NOTE: Oracle Restart auto-starts!

# Database state + DG
ssh oracle@stby01 ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<'EOF'
SET LINESIZE 200
COL open_mode FORMAT A20
COL flashback_on FORMAT A12
SELECT name, db_unique_name, open_mode, database_role, log_mode, flashback_on FROM v$database;
SELECT process, status, sequence# FROM v$managed_standby WHERE process IN ('MRP0','RFS') ORDER BY 1;
EXIT
EOF
# Expected:
#   STBY | STBY | READ ONLY WITH APPLY | PHYSICAL STANDBY | ARCHIVELOG | YES
#   MRP0 APPLYING_LOG (recovery continuous), RFS IDLE (transport ready)
#
# NOTE: flashback_on=YES is REQUIRED for FSFO (the broker enforces it). If NO:
#   srvctl stop database -db STBY
#   sqlplus / as sysdba: STARTUP MOUNT; ALTER DATABASE FLASHBACK ON;
#   srvctl start database -db STBY
```

**Listeners on stby01 — HAS-managed, auto-start ✓** (FIX-S28-49 for 1522, FIX-S28-50 for 1521)

```bash
ssh grid@stby01 ". ~/.bash_profile && srvctl status listener"
# Expected:
#   Listener LISTENER is enabled, running on node(s): stby01
#   Listener LISTENER_DGMGRL is enabled, running on node(s): stby01

ssh oracle@stby01 ". ~/.bash_profile && lsnrctl status LISTENER | grep Service | head -5"
# Expected: STBY.lab.local, STBY_DGMGRL.lab.local and dynamic ones (apppdb, PRIMXDB, PRIM_CFG)
```

### Step 4 — client01 (UCP test client)

```powershell
& $VBox startvm client01 --type headless
Start-Sleep -Seconds 60
```

**Verification:**

```bash
ssh kris@client01 "tnsping MYAPP_TAC"
# Expected: OK (a few ms) — alias from HA DNS, FAILOVER=on

ssh kris@client01 "java -cp '...:.../ojdbc11.jar:.../ucp11.jar' TestHarness --once"
# Smoke test: connection + simple SELECT
```

### Step 5 — Start Multi-Observer FSFO (if it was disabled at stop)

> Skip if the observers are already running (`systemctl is-active dgmgrl-observer-obs_ext` = active).
> After a cold VM restart the observer will **not** start by itself if it was DISABLED before shutdown.

```bash
# 1. Master observer obs_ext on infra01
ssh root@infra01 "systemctl start dgmgrl-observer-obs_ext"

# 2. Backup observers — obs_dc on prim01, obs_dr on stby01
ssh root@prim01 "systemctl start dgmgrl-observer-obs_dc"
ssh root@stby01 "systemctl start dgmgrl-observer-obs_dr"

sleep 20  # observers register with the broker

# 3. Re-enable FSFO (broker propagation ~30-60s)
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
ENABLE FAST_START FAILOVER;
SHOW FAST_START FAILOVER;
SHOW OBSERVER;
EXIT
EOF
# Expected:
#   Fast-Start Failover: Enabled in Potential Data Loss Mode
#   Observer "obs_ext" - Master, running on infra01.lab.local, status: ACTIVE
#   Observer "obs_dc" - Backup, running on prim01.lab.local, status: ACTIVE
#   Observer "obs_dr" - Backup, running on stby01.lab.local, status: ACTIVE
```

### Step 6 — Final sanity check (broker + FSFO + TAC services)

```bash
# Broker status
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
SHOW CONFIGURATION VERBOSE;
SHOW DATABASE PRIM;
SHOW DATABASE STBY;
SHOW FAST_START FAILOVER;
EXIT
EOF
# Expected:
#   Configuration Status: SUCCESS (NO ERRORS REPORTED)
#   Protection Mode: MaxAvailability or MaxPerformance (per architecture)
#   Apply Lag: 0 seconds
#   Fast-Start Failover: Enabled
#   Master Observer: obs_ext

# FSFO armed on PRIM
ssh oracle@prim01 ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<'EOF'
SELECT fs_failover_status, fs_failover_current_target FROM v$database;
EXIT
EOF
# Expected: TARGET UNDER LAG LIMIT, STBY (FSFO armed)

# TAC service status (per role)
ssh oracle@prim01 ". ~/.bash_profile && srvctl status service -db PRIM -service MYAPP_TAC"
# Expected: Service MYAPP_TAC is running on instance(s) PRIM1, PRIM2 (if PRIMARY on both)
```

---

## 🔴 Cold STOP — graceful shutdown of the entire environment

> Reverse order: client/observer/standby/RAC/storage. Goal: no corruption + DG consistency.

### Step 1 — DISABLE FSFO + Stop all Observers (CRITICAL)

> ⚠ **With FSFO enabled, an observer can attempt to trigger a failover when the primary disappears.** The sequence MUST be:
> 1. DISABLE FSFO
> 2. Stop all observers
> 3. Stop primary
>
> Otherwise you risk an unintended failover during a graceful shutdown.

```bash
# 1. DISABLE FSFO (broker will not initiate failover after primary stops)
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
DISABLE FAST_START FAILOVER;
SHOW FAST_START FAILOVER;
EXIT
EOF
# Expected: Fast-Start Failover: Disabled

# 2. Stop all observers (master + backups)
ssh root@infra01 "systemctl stop dgmgrl-observer-obs_ext"
ssh root@prim01  "systemctl stop dgmgrl-observer-obs_dc"
ssh root@stby01  "systemctl stop dgmgrl-observer-obs_dr"

# Verification
for h in infra01 prim01 stby01; do
  ssh root@$h "systemctl is-active dgmgrl-observer-obs_*"
done
# Expected: inactive on each
```

### Step 2 — Stop client01 (first, so it does not hang on the database)

```powershell
& $VBox controlvm client01 acpipowerbutton
do {
    Start-Sleep -Seconds 5
    $running = & $VBox list runningvms | Select-String "client01"
} while ($running)
Write-Host "client01 stopped"
```

### Step 3 — Stop stby01 (Active DG: do NOT do manual CANCEL/SHUTDOWN)

> Persistent Active DG + Oracle Restart: `srvctl stop database -db STBY` is enough.
> The broker stops apply automatically. No manual `RECOVER MANAGED STANDBY ... CANCEL`.

```bash
ssh oracle@stby01 ". ~/.bash_profile && srvctl stop database -db STBY"
# Oracle Restart: graceful shutdown immediate via HAS
```

```powershell
& $VBox controlvm stby01 acpipowerbutton
do {
    Start-Sleep -Seconds 5
    $running = & $VBox list runningvms | Select-String "stby01"
} while ($running)
Write-Host "stby01 stopped"
```

### Step 4 — Stop the PRIM database + CRS on prim01/prim02

```bash
# As oracle - stop the database (on both nodes automatically through Grid)
ssh oracle@prim01 ". ~/.bash_profile && srvctl stop database -db PRIM"

# As root - stop the CRS cluster (stops ASM, listeners, SCAN VIPs)
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stop cluster -all"
# Wait ~2-3 min until all resources have stopped
```

```powershell
# Shutdown VM (sequentially - prim02 first, then prim01)
& $VBox controlvm prim02 acpipowerbutton
Start-Sleep -Seconds 60
& $VBox controlvm prim01 acpipowerbutton

# Wait for the actual shutdown
foreach ($vm in @("prim01", "prim02")) {
    do {
        Start-Sleep -Seconds 5
        $running = & $VBox list runningvms | Select-String $vm
    } while ($running)
    Write-Host "$vm stopped"
}
```

### Step 5 — Stop infra01 (last)

```powershell
& $VBox controlvm infra01 acpipowerbutton
do {
    Start-Sleep -Seconds 5
    $running = & $VBox list runningvms | Select-String "infra01"
} while ($running)
Write-Host "infra01 stopped"
Write-Host "===  Full lab stopped ==="
```

### Quick stop (one-liner, NOT graceful)

```powershell
# WARNING: no graceful database shutdown. Risk of crash recovery on startup + apply gap.
# Use ONLY when graceful is not working (e.g. a hung database)
foreach ($vm in @("client01", "stby01", "prim02", "prim01", "infra01")) {
    & $VBox controlvm $vm poweroff 2>$null
    Start-Sleep -Seconds 3
}
```

---

## 🔄 Restart of a single VM (rolling)

### Restart prim01 (RAC member — no service outage)

```bash
# 1. Migrate TAC service to prim02 (if running on prim01)
ssh oracle@prim01 ". ~/.bash_profile && srvctl relocate service -db PRIM -service MYAPP_TAC \
    -oldinst PRIM1 -newinst PRIM2 -force 2>/dev/null || true"

# 2. Stop instance PRIM1 (PRIM2 stays active — rolling availability)
ssh oracle@prim01 ". ~/.bash_profile && srvctl stop instance -db PRIM -instance PRIM1"

# 3. Stop CRS on prim01
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stop crs"
```

```powershell
# 4. Reboot VM
& $VBox controlvm prim01 acpipowerbutton
Start-Sleep -Seconds 60
& $VBox startvm prim01 --type headless
Start-Sleep -Seconds 240   # CRS starts in 3-5 min
```

```bash
# 5. Verification - CRS and instance PRIM1 came up (auto-start)
ssh grid@prim01 ". ~/.bash_profile && crsctl check cluster -all"
ssh oracle@prim01 ". ~/.bash_profile && srvctl status database -db PRIM"

# 6. Restart LISTENER_DGMGRL (no auto-start — see step 2 of cold START; oracle, NOT grid)
ssh oracle@prim01 ". ~/.bash_profile && lsnrctl start LISTENER_DGMGRL"

# 7. Restart obs_dc if it was ENABLED
ssh root@prim01 "systemctl start dgmgrl-observer-obs_dc"
```

### Restart stby01 (Single Instance — short Active DG outage)

```bash
# 1. Stop the database (Oracle Restart graceful)
ssh oracle@stby01 ". ~/.bash_profile && srvctl stop database -db STBY"
```

```powershell
# 2. Reboot VM
& $VBox controlvm stby01 acpipowerbutton
Start-Sleep -Seconds 60
& $VBox startvm stby01 --type headless
Start-Sleep -Seconds 120
```

```bash
# 3. STBY auto-starts via Oracle Restart (no need to do it manually)
ssh grid@stby01 ". ~/.bash_profile && crsctl stat res ora.stby.db -t"
# Expected: STATE=ONLINE, STATUS=Open

# 4. Listeners — auto-start via HAS (S28-49/50). Verify (if any are OFFLINE):
ssh grid@stby01 ". ~/.bash_profile && srvctl start listener -listener LISTENER 2>/dev/null || true"
ssh grid@stby01 ". ~/.bash_profile && srvctl start listener -listener LISTENER_DGMGRL 2>/dev/null || true"

# 5. obs_dr restart
ssh root@stby01 "systemctl start dgmgrl-observer-obs_dr"

# 6. Apply verification
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
SHOW CONFIGURATION;
SHOW DATABASE STBY;
EXIT
EOF
# Expected: Apply Lag returns to ~0s within 1-2 min
```

### Restart infra01 (storage + DNS — more invasive)

```bash
# 1. Stop the database + CRS on prim01/prim02 (because they will lose iSCSI + DNS)
ssh oracle@prim01 ". ~/.bash_profile && srvctl stop database -db PRIM"
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stop cluster -all"
# NOTE: stby01 also uses DNS — if infra01 is down >5min stby01 loses tnsnames resolution
ssh oracle@stby01 ". ~/.bash_profile && srvctl stop database -db STBY"
```

```powershell
# 2. Restart infra01
& $VBox controlvm infra01 acpipowerbutton
Start-Sleep -Seconds 30
& $VBox startvm infra01 --type headless
Start-Sleep -Seconds 90   # named + chrony + iSCSI target boot
```

```bash
# 3. After infra01 is UP - iSCSI sessions return (FIX-032 Restart=on-failure)
sleep 30
ssh root@prim01 "iscsiadm -m session"
ssh grid@prim01 ". ~/.bash_profile && asmcmd lsdg" | head -5

# 4. Start CRS + databases
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl start cluster -all"
sleep 240
ssh oracle@prim01 ". ~/.bash_profile && srvctl start database -db PRIM"

# 5. Start STBY (HAS auto-start, but if it was stopped you have to do it manually)
ssh oracle@stby01 ". ~/.bash_profile && srvctl start database -db STBY"
```

---

## 📊 Status check — quick diagnostics

### One-shot health check (from the host)

```powershell
# Save as: D:\__AI__\_oracle_\20260423-FSFO-TAC-guide\VMs2-install\scripts\check_lab.ps1
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

Write-Host "=== Running VMs ===" -ForegroundColor Cyan
& $VBox list runningvms

Write-Host "`n=== Connectivity ===" -ForegroundColor Cyan
$ips = @{
    "infra01" = "192.168.56.10"
    "prim01"  = "192.168.56.11"
    "prim02"  = "192.168.56.12"
    "stby01"  = "192.168.56.13"
    "client01"= "192.168.56.15"
}
foreach ($vm in $ips.Keys) {
    $up = Test-Connection $ips[$vm] -Count 1 -Quiet
    Write-Host "  $vm ($($ips[$vm])): $(if($up){'UP'}else{'DOWN'})"
}

Write-Host "`n=== CRS prim01 ===" -ForegroundColor Cyan
ssh grid@prim01 ". ~/.bash_profile && crsctl check cluster" 2>&1 | Select-Object -First 5

Write-Host "`n=== Database PRIM (verbose - both OPEN!) ===" -ForegroundColor Cyan
ssh oracle@prim01 ". ~/.bash_profile && srvctl status database -db PRIM -verbose" 2>&1

Write-Host "`n=== Database STBY ===" -ForegroundColor Cyan
ssh oracle@stby01 ". ~/.bash_profile && srvctl status database -db STBY" 2>&1

Write-Host "`n=== DG broker ===" -ForegroundColor Cyan
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl -silent /@PRIM 'SHOW CONFIGURATION'" 2>&1
```

### Per-VM quick checks

```bash
# infra01
ssh root@infra01 "systemctl is-active named chronyd target; nslookup scan-prim.lab.local 127.0.0.1; ss -ntl | grep -E ':53|:3260'"

# prim01 / prim02
ssh grid@prim01 ". ~/.bash_profile && crsctl stat res -t | head -40"
ssh grid@prim02 ". ~/.bash_profile && crsctl stat res -t | head -40"
ssh oracle@prim01 ". ~/.bash_profile && srvctl status database -db PRIM -verbose"

# stby01
ssh grid@stby01 ". ~/.bash_profile && crsctl stat res -t"
ssh oracle@stby01 ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<'EOF'
SELECT name, open_mode, database_role, log_mode, flashback_on FROM v$database;
SELECT process, status, sequence# FROM v$managed_standby WHERE process IN ('MRP0','RFS');
EXIT
EOF

# Data Guard broker (if LISTENER_DGMGRL is UP, alias /@PRIM via wallet)
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl -silent /@PRIM 'SHOW CONFIGURATION'"

# Multi-Observer status
for h in infra01:obs_ext prim01:obs_dc stby01:obs_dr; do
  IFS=: read host obs <<< "$h"
  echo "=== $obs on $host ==="
  ssh root@$host "systemctl is-active dgmgrl-observer-$obs"
done
```

---

## 🛠 Common operations

### Refresh DNS (if NAT DHCP overwrote it — FIX-016 from VMs/FIXES_LOG)

```bash
# On every VM (except infra01)
sudo nmcli connection modify "System enp0s10" ipv4.ignore-auto-dns yes 2>/dev/null
sudo nmcli connection modify "System enp0s8"  ipv4.ignore-auto-dns yes 2>/dev/null
sudo nmcli connection modify "System enp0s3"  ipv4.dns "192.168.56.10"
sudo nmcli connection modify "System enp0s3"  ipv4.dns-search "lab.local"
sudo nmcli connection down "System enp0s3" && sudo nmcli connection up "System enp0s3"
```

### Check ASM disks (if /dev/oracleasm/* disappeared after a reboot)

```bash
ssh root@prim01 "ls -la /dev/oracleasm/"
# If empty:
ssh root@prim01 "iscsiadm -m node --loginall=automatic; sleep 5; ls -la /dev/oracleasm/"
```

### Switchover (Primary ↔ Standby) — preparation

```bash
# Full procedure in docs/09_Test_Scenarios.md
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
VALIDATE DATABASE STBY;
SHOW CONFIGURATION VERBOSE;
EXIT
EOF
# After VALIDATE without warnings:
# DGMGRL> SWITCHOVER TO STBY;
# After switchover: TAC service auto-fails-over (srvctl modify -role)
```

### Quick backup (RMAN level 0 to FRA)

```bash
ssh oracle@prim01 ". ~/.bash_profile && rman target /" <<'EOF'
BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
DELETE NOPROMPT OBSOLETE;
EXIT
EOF
```

### Cheat sheet: scope of `stop`/`start` commands in the Oracle stack

In RAC + Grid you have **several "stop/start" layers** with different scope. Pick the right one for the situation.

**Hierarchy (top — smallest scope, bottom — largest):**

```
┌─ srvctl stop database -db PRIM         ← only DB, ASM/CRS/listeners up
│   ├─ srvctl stop instance -db PRIM -instance PRIM1   ← only one instance
│   └─ srvctl stop service -db PRIM -service MYAPP_TAC ← only the service
│
├─ crsctl stop cluster -all              ← entire cluster, ohasd stays up (cluster-wide)
│
├─ crsctl stop crs -f                    ← entire stack on a single node (force)
│
└─ crsctl stop has                       ← entire HAS stack on a single node (DB+ASM+CRS+ohasd)
```

**Comparison table:**

| Command (as root) | Scope | What it stops | What stays up | Time | When to use |
|---------------------|-------|---------------|---------------|------|--------------|
| `srvctl stop database -db PRIM` | DB only | DB instances PRIM1+PRIM2 | ASM, CRS, listeners, VIPs, ohasd | ~30s | Database maintenance without touching the cluster |
| `srvctl stop instance -db PRIM -instance PRIM1` | one instance | only PRIM1 | everything else (PRIM2 OPEN, clients keep working) | ~20s | Rolling per-node patching |
| `crsctl stop cluster` (one node) | one node | DB instance + ASM + CRS on that node | ohasd on that node | ~1-2 min | Cluster restart on a single node |
| `crsctl stop cluster -all` | all nodes | as above × all | ohasd on every node | ~2-3 min | Cluster-wide restart |
| `crsctl stop crs -f` | one node | everything from `stop cluster` + force | nothing | ~2-3 min | When `stop cluster` hangs |
| **`crsctl stop has`** | one node | **everything from DB downward + ohasd** | nothing — only non-Oracle processes | ~3-4 min | Full stack reset (after `usermod`/limits change/group refresh) |

**Corresponding `start` commands:**

| Command | What it starts |
|---------|-------------|
| `srvctl start database -db PRIM` | DB on both nodes (if ASM+CRS are already up) |
| `srvctl start instance -db PRIM -instance PRIM1` | only one instance |
| `crsctl start cluster` (one node) | CRS+ASM+DB on that node |
| `crsctl start cluster -all` | CRS+ASM+DB on all nodes |
| `crsctl start crs` or `crsctl start has` | full stack from ohasd upward |

**OS reboot = automatic `stop has`:** the systemd unit `oracle-ohasd.service` (installed by Grid root.sh) calls `crsctl stop has` on `shutdown`/`reboot`. You do not need to stop the cluster manually before `shutdown -r now`.

---

## 📁 Logs — where to look for problems

| What | Where |
|----|-------|
| CRS startup issues | `/u01/app/grid/diag/crs/<node>/crs/trace/alert<node>.log` |
| ASM problems (RAC) | `/u01/app/grid/diag/asm/+asm/+ASM<N>/trace/alert_+ASM<N>.log` |
| ASM stby01 (HAS) | `/u01/app/grid/diag/asm/+asm/+ASM/trace/alert_+ASM.log` |
| RDBMS PRIM1/2 | `/u01/app/oracle/diag/rdbms/prim/PRIM<N>/trace/alert_PRIM<N>.log` |
| RDBMS STBY | `/u01/app/oracle/diag/rdbms/stby/STBY/trace/alert_STBY.log` |
| iSCSI sessions | `journalctl -u iscsi -u iscsid` |
| systemd services | `journalctl -b 0` |
| DBCA last run | `/u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM*.log` |
| Listener (1521) | `$ORACLE_HOME/network/log/listener.log` or `/u01/app/grid/diag/tnslsnr/<node>/listener/trace/listener.log` |
| LISTENER_DGMGRL (1522) | `$ORACLE_HOME/network/log/listener_dgmgrl.log` |
| Broker DMON | `/u01/app/oracle/diag/rdbms/prim/PRIM<N>/trace/drcPRIM<N>.log` (on PRIM) or `/u01/app/oracle/diag/rdbms/stby/STBY/trace/drcSTBY.log` |
| Observer | `journalctl -u dgmgrl-observer-<obs_name>` or `/u01/app/oracle/observer/<obs_name>.log` |
| RMAN duplicate | `/tmp/create_standby.log` (script) or `/u01/app/oracle/diag/clients/user_oracle/RMAN_*/trace/` |

---

## 🎯 Startup order — quick cheat sheet

```
┌──────────────────────────────────────────────────────────┐
│  COLD START (from the host PowerShell):                  │
│  ──────────────────────────────────────────────────────  │
│  1.  & $VBox startvm infra01  --type headless            │
│      Start-Sleep 60                                       │
│      → DNS+NTP+iSCSI+master observer up                   │
│  2.  & $VBox startvm prim01   --type headless            │
│      & $VBox startvm prim02   --type headless            │
│      Start-Sleep 240                                      │
│      → CRS+ASM+PRIM1+PRIM2 OPEN                           │
│      → lsnrctl start LISTENER_DGMGRL on both (1522)       │
│  3.  & $VBox startvm stby01   --type headless            │
│      Start-Sleep 120                                      │
│      → Oracle Restart auto-starts STBY (READ ONLY+APPLY)  │
│      → lsnrctl start LISTENER_DGMGRL on stby01 (1522)     │
│  4.  & $VBox startvm client01 --type headless            │
│  5.  systemctl start dgmgrl-observer-obs_ext (infra01)    │
│      systemctl start dgmgrl-observer-obs_dc  (prim01)     │
│      systemctl start dgmgrl-observer-obs_dr  (stby01)     │
│      ENABLE FAST_START FAILOVER (via /@PRIM)              │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  COLD STOP (from the host + from the VM):                │
│  ──────────────────────────────────────────────────────  │
│  1.  DISABLE FAST_START FAILOVER (dgmgrl /@PRIM)         │
│      systemctl stop dgmgrl-observer-* on 3 hosts          │
│  2.  acpipowerbutton client01                             │
│  3.  srvctl stop database -db STBY                        │
│      acpipowerbutton stby01                               │
│  4.  srvctl stop database -db PRIM                        │
│      crsctl stop cluster -all (as root from prim01)       │
│      acpipowerbutton prim02, prim01                       │
│  5.  acpipowerbutton infra01                              │
└──────────────────────────────────────────────────────────┘
```

---

## 📚 Related documents

- `docs/01_Architecture_and_Assumptions.md` — topology, passwords, networks, decisions
- `docs/06_Data_Guard_Standby.md` — full Data Guard setup (RMAN DUPLICATE + broker)
- `docs/07_FSFO_Observers.md` — Multi-Observer (master/backup) deployment
- `docs/08_TAC_and_Tests.md` — TAC services + UCP + role-aware fail-over
- `docs/09_Test_Scenarios.md` — switchover, failover, outages
- `EXECUTION_LOG.md` — fix history (S28-30..S28-38 for create_standby_broker.sh)
- `VMs/FIXES_LOG.md` (previous project) — knowledge base 100+ FIXes
