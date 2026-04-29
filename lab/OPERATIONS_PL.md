> [🇬🇧 English](./OPERATIONS.md) | 🇵🇱 Polski

# OPERATIONS.md — Runbook operatorski lab Oracle 26ai HA MAA

> Komendy startup/shutdown/status dla 5-VM labu Oracle 26ai (RAC + Active DG + Multi-Observer FSFO + TAC).
> Wszystkie komendy na hoście (Windows PowerShell) + wewnątrz VM (Linux bash).
> Autor: KCB Kris | Wersja: 1.0 | Data: 2026-04-28
>
> **Konwencje labu** (per memory `feedback_lab_conventions.md`):
> - Jedno hasło wszędzie: `Oracle26ai_LAB!` (admin), root/oracle/grid/kris = `Welcome1#` (OS)
> - Active DG trwały: STBY zawsze `READ ONLY WITH APPLY` (broker zarządza)
> - Multi-Observer: master `obs_ext` (infra01) + backup `obs_dc` (prim01) + backup `obs_dr` (stby01)
> - stby01 = Oracle Restart (HAS `CRS_SWONLY` + `roothas.pl`) → STBY auto-startuje po reboot VM
> - Auto-mode preferred: skrypty z `scripts/` zamiast komend ręcznych

## Topologia (przypomnienie)

| VM | Rola | RAM | Sieć (host-only) | ORACLE_SID |
|----|------|-----|------------------|------------|
| `infra01` | DNS bind9 + NTP + iSCSI Target + Master Observer `obs_ext` | 8 GB | 192.168.56.10 | — |
| `prim01` | RAC node 1 + Backup Observer `obs_dc` | 9 GB | 192.168.56.11 | PRIM1 (DB) / +ASM1 (grid) |
| `prim02` | RAC node 2 | 9 GB | 192.168.56.12 | PRIM2 (DB) / +ASM2 (grid) |
| `stby01` | Single Instance + Oracle Restart + Backup Observer `obs_dr` | 6 GB | 192.168.56.13 | STBY (DB) / +ASM (grid) |
| `client01` | OpenJDK 17 + Oracle Client + TestHarness UCP/TAC | 3 GB | 192.168.56.15 | — |

## Zmienne środowiskowe (na hoście)

```powershell
# PowerShell — używaj w każdej sesji operacyjnej
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$VMs  = @("infra01", "prim01", "prim02", "stby01", "client01")
```

---

## 🟢 Cold START — uruchamianie pełnego środowiska

> **Kolejność jest krytyczna.** NIE uruchamiaj wszystkich VM jednocześnie:
> - DNS musi być gotowy zanim prim01/02 startują CRS (rozwiązują nazwy SCAN, peer node)
> - iSCSI target musi nasłuchiwać zanim ASM zobaczy LUNs
> - Standby (stby01) potrzebuje primary OPEN aby broker mógł `READ ONLY WITH APPLY`
> - Observer dopisuje się jako ostatni — broker musi mieć obie bazy dostępne

### Krok 1 — infra01 (DNS + NTP + iSCSI target + master Observer)

```powershell
# Z hosta
& $VBox startvm infra01 --type headless

# Czekaj ~60s na pełen boot (named, chronyd, target.service)
Start-Sleep -Seconds 60
```

**Weryfikacja na infra01 (jako root):**

```bash
ssh root@infra01 "systemctl is-active named chronyd target"
# Oczekiwane: active / active / active

ssh root@infra01 "ss -ntl | grep -E ':53|:123|:3260'"
# Oczekiwane: nasłuchuje na 53 (DNS), 123 (NTP UDP), 3260 (iSCSI TCP)

# DNS resolves
ssh root@infra01 "nslookup scan-prim.lab.local 127.0.0.1; nslookup stby01.lab.local 127.0.0.1"
```

### Krok 2 — prim01 + prim02 (RAC nodes — można równolegle)

```powershell
# Można startować równolegle - VirtualBox sobie poradzi
& $VBox startvm prim01 --type headless
& $VBox startvm prim02 --type headless

# Czekaj ~3-5 min na pełen boot + start CRS stack + ASM mount + DB open
Start-Sleep -Seconds 240
```

**Weryfikacja CRS (jako grid na prim01):**

```bash
ssh grid@prim01 ". ~/.bash_profile && crsctl check cluster -all"
# Oczekiwane: CRS-4537/4529/4533 ONLINE na obu nodach

ssh grid@prim01 ". ~/.bash_profile && crsctl stat res -t"
# Oczekiwane (kluczowe zasoby):
#   ora.LISTENER.lsnr     ONLINE/ONLINE na obu nodach
#   ora.LISTENER_SCAN1..3 ONLINE
#   ora.asm               ONLINE/ONLINE
#   ora.DATA.dg / ora.RECO.dg / ora.OCR.dg   MOUNTED
#   ora.prim.db           Open na prim01 i prim02 (UWAGA: NIE Mounted!)
#   ora.prim.apppdb.pdb   READ WRITE na prim01 i prim02

# Sprawdź iSCSI sesje (FIX-032 z VMs/FIXES_LOG: persistent reconnect)
ssh root@prim01 "iscsiadm -m session"
ssh root@prim02 "iscsiadm -m session"
# Oczekiwane: tcp: [N] 192.168.200.10:3260,1 ... per node
```

**Jeśli iSCSI nie zalogowany** (rzadko, ale gdy infra01 startuje wolno):

```bash
ssh root@prim01 "iscsiadm -m node --loginall=automatic"
ssh root@prim02 "iscsiadm -m node --loginall=automatic"
sleep 30
ssh grid@prim01 ". ~/.bash_profile && crsctl start cluster -all"
# Po ~3 min CRS sam wstanie (CSSD widzi voting disks z +OCR)
```

**Weryfikacja bazy PRIM (kluczowe — obie instancje OPEN!):**

```bash
ssh oracle@prim01 ". ~/.bash_profile && srvctl status database -db PRIM -verbose"
# Oczekiwane:
#   Instance PRIM1 is running on node prim01 with online services PRIM_APPPDB. Instance status: Open
#   Instance PRIM2 is running on node prim02 with online services PRIM_APPPDB. Instance status: Open
#
# UWAGA (lekcja z S28-38): jeśli któraś instancja "Mounted (Closed)" → broker DG i RMAN
# będą rzucać ORA-01138. Fix:
#   srvctl stop instance -db PRIM -instance PRIM2 -force
#   srvctl start instance -db PRIM -instance PRIM2 -startoption OPEN
```

**LISTENER_DGMGRL (port 1522) — CRS-managed, auto-start ✓** (FIX-S28-49)

```bash
# Sprawdź status (powinno być ONLINE bez ręcznego startu)
ssh grid@prim01 ". ~/.bash_profile && srvctl status listener -listener LISTENER_DGMGRL"
# Oczekiwane: Listener LISTENER_DGMGRL is enabled, running on node(s): prim01,prim02

# Verify static service registration
ssh oracle@prim01 ". ~/.bash_profile && lsnrctl status LISTENER_DGMGRL | grep -E 'Service|STATUS' | head -5"
# Oczekiwane: 'Service "PRIM_DGMGRL.lab.local" has 1 instance(s)'
```

### Krok 3 — stby01 (Single Instance + Oracle Restart)

> ⚠ stby01 = Oracle Restart (HAS). Po boot VM:
> - HAS daemon (ohasd) startuje sam (systemd unit `oracle-ohasd.service`)
> - **CSSD wymaga JAWNEGO startu** (FIX-S28-48: `CRS_SWONLY` install nie auto-startuje CSSD)
> - Po CSSD UP: HAS uruchamia bazę STBY (jeśli `-startoption READ ONLY` ustawiony przez S28-46)
> - Broker DMON wstaje razem z bazą → odbierze stan z primary i utrzyma `READ ONLY WITH APPLY`
> - **Nie rób manualnego `STARTUP MOUNT + OPEN READ ONLY + RECOVER`** — broker to robi sam (Active DG trwały)

```powershell
& $VBox startvm stby01 --type headless
Start-Sleep -Seconds 120
```

**CSSD na stby01 — AUTO_START=always, auto-start ✓** (FIX-S28-48)

```bash
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl check css"
# Oczekiwane: CRS-4529: Cluster Synchronization Services is online
# Jeśli wyjątkowo OFFLINE (po pierwszym deployu zanim AUTO_START został ustawiony):
#   ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl start resource ora.cssd -init"
```

**Weryfikacja HAS + STBY:**

```bash
ssh grid@stby01 ". ~/.bash_profile && crsctl check has"
# Oczekiwane: CRS-4638: Oracle High Availability Services is online

ssh grid@stby01 ". ~/.bash_profile && crsctl stat res -t"
# Oczekiwane:
#   ora.LISTENER.lsnr   ONLINE
#   ora.asm             ONLINE
#   ora.DATA_STBY.dg    ONLINE (jeśli używamy ASM na stby) lub /u02 mount (XFS)
#   ora.stby.db         ONLINE (Open) — UWAGA: Oracle Restart auto-starts!

# Stan bazy + DG
ssh oracle@stby01 ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<'EOF'
SET LINESIZE 200
COL open_mode FORMAT A20
COL flashback_on FORMAT A12
SELECT name, db_unique_name, open_mode, database_role, log_mode, flashback_on FROM v$database;
SELECT process, status, sequence# FROM v$managed_standby WHERE process IN ('MRP0','RFS') ORDER BY 1;
EXIT
EOF
# Oczekiwane:
#   STBY | STBY | READ ONLY WITH APPLY | PHYSICAL STANDBY | ARCHIVELOG | YES
#   MRP0 APPLYING_LOG (recovery continuous), RFS IDLE (transport ready)
#
# UWAGA: flashback_on=YES jest WYMAGANE dla FSFO (broker wymusza). Jeśli NO:
#   srvctl stop database -db STBY
#   sqlplus / as sysdba: STARTUP MOUNT; ALTER DATABASE FLASHBACK ON;
#   srvctl start database -db STBY
```

**Listenery na stby01 — HAS-managed, auto-start ✓** (FIX-S28-49 dla 1522, FIX-S28-50 dla 1521)

```bash
ssh grid@stby01 ". ~/.bash_profile && srvctl status listener"
# Oczekiwane:
#   Listener LISTENER is enabled, running on node(s): stby01
#   Listener LISTENER_DGMGRL is enabled, running on node(s): stby01

ssh oracle@stby01 ". ~/.bash_profile && lsnrctl status LISTENER | grep Service | head -5"
# Oczekiwane: STBY.lab.local, STBY_DGMGRL.lab.local i dynamiczne (apppdb, PRIMXDB, PRIM_CFG)
```

### Krok 4 — client01 (klient testowy UCP)

```powershell
& $VBox startvm client01 --type headless
Start-Sleep -Seconds 60
```

**Weryfikacja:**

```bash
ssh kris@client01 "tnsping MYAPP_TAC"
# Oczekiwane: OK (kilka ms) — alias z DNS HA, FAILOVER=on

ssh kris@client01 "java -cp '...:.../ojdbc11.jar:.../ucp11.jar' TestHarness --once"
# Smoke test: connection + simple SELECT
```

### Krok 5 — Start Multi-Observer FSFO (jeśli był wyłączony przy stop)

> Skip jeśli observers już chodzą (`systemctl is-active dgmgrl-observer-obs_ext` = active).
> Po cold restart VM observer **nie** wystartuje sam jeśli był DISABLED przed shutdown.

```bash
# 1. Master observer obs_ext na infra01
ssh root@infra01 "systemctl start dgmgrl-observer-obs_ext"

# 2. Backup observers — obs_dc na prim01, obs_dr na stby01
ssh root@prim01 "systemctl start dgmgrl-observer-obs_dc"
ssh root@stby01 "systemctl start dgmgrl-observer-obs_dr"

sleep 20  # observers rejestrują się w brokerze

# 3. Re-enable FSFO (broker propagacja ~30-60s)
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
ENABLE FAST_START FAILOVER;
SHOW FAST_START FAILOVER;
SHOW OBSERVER;
EXIT
EOF
# Oczekiwane:
#   Fast-Start Failover: Enabled in Potential Data Loss Mode
#   Observer "obs_ext" - Master, running on infra01.lab.local, status: ACTIVE
#   Observer "obs_dc" - Backup, running on prim01.lab.local, status: ACTIVE
#   Observer "obs_dr" - Backup, running on stby01.lab.local, status: ACTIVE
```

### Krok 6 — Final sanity check (broker + FSFO + TAC services)

```bash
# Broker status
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
SHOW CONFIGURATION VERBOSE;
SHOW DATABASE PRIM;
SHOW DATABASE STBY;
SHOW FAST_START FAILOVER;
EXIT
EOF
# Oczekiwane:
#   Configuration Status: SUCCESS (NO ERRORS REPORTED)
#   Protection Mode: MaxAvailability lub MaxPerformance (per architektura)
#   Apply Lag: 0 seconds
#   Fast-Start Failover: Enabled
#   Master Observer: obs_ext

# FSFO armed na PRIM
ssh oracle@prim01 ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<'EOF'
SELECT fs_failover_status, fs_failover_current_target FROM v$database;
EXIT
EOF
# Oczekiwane: TARGET UNDER LAG LIMIT, STBY (FSFO armed)

# TAC service status (per role)
ssh oracle@prim01 ". ~/.bash_profile && srvctl status service -db PRIM -service MYAPP_TAC"
# Oczekiwane: Service MYAPP_TAC is running on instance(s) PRIM1, PRIM2 (jeśli PRIMARY na obu)
```

---

## 🔴 Cold STOP — graceful shutdown całego środowiska

> Reverse order: client/observer/standby/RAC/storage. Cel: brak corruption + spójność DG.

### Krok 1 — DISABLE FSFO + Stop wszystkich Observerów (KRYTYCZNE)

> ⚠ **Z włączonym FSFO observer może próbować wywołać failover gdy primary zniknie.** Sekwencja MUSI być:
> 1. DISABLE FSFO
> 2. Stop wszystkich observerów
> 3. Stop primary
>
> Inaczej ryzykujesz niezamierzony failover przy graceful shutdown.

```bash
# 1. DISABLE FSFO (broker nie inicjuje failover po stop primary)
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
DISABLE FAST_START FAILOVER;
SHOW FAST_START FAILOVER;
EXIT
EOF
# Oczekiwane: Fast-Start Failover: Disabled

# 2. Stop wszystkich observerów (master + backups)
ssh root@infra01 "systemctl stop dgmgrl-observer-obs_ext"
ssh root@prim01  "systemctl stop dgmgrl-observer-obs_dc"
ssh root@stby01  "systemctl stop dgmgrl-observer-obs_dr"

# Weryfikacja
for h in infra01 prim01 stby01; do
  ssh root@$h "systemctl is-active dgmgrl-observer-obs_*"
done
# Oczekiwane: inactive na każdym
```

### Krok 2 — Stop client01 (najpierw, by nie wisiał na bazie)

```powershell
& $VBox controlvm client01 acpipowerbutton
do {
    Start-Sleep -Seconds 5
    $running = & $VBox list runningvms | Select-String "client01"
} while ($running)
Write-Host "client01 stopped"
```

### Krok 3 — Stop stby01 (Active DG: NIE rób manualnego CANCEL/SHUTDOWN)

> Active DG trwały + Oracle Restart: wystarczy `srvctl stop database -db STBY`.
> Broker stop apply automatycznie. Bez manualnego `RECOVER MANAGED STANDBY ... CANCEL`.

```bash
ssh oracle@stby01 ". ~/.bash_profile && srvctl stop database -db STBY"
# Oracle Restart: graceful shutdown immediate przez HAS
```

```powershell
& $VBox controlvm stby01 acpipowerbutton
do {
    Start-Sleep -Seconds 5
    $running = & $VBox list runningvms | Select-String "stby01"
} while ($running)
Write-Host "stby01 stopped"
```

### Krok 4 — Stop bazy PRIM + CRS na prim01/prim02

```bash
# Jako oracle - stop bazy (na obu nodach automatycznie przez Grid)
ssh oracle@prim01 ". ~/.bash_profile && srvctl stop database -db PRIM"

# Jako root - stop CRS cluster (zatrzymuje ASM, listenery, SCAN VIPs)
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stop cluster -all"
# Czekaj ~2-3 min aż wszystkie zasoby się zatrzymają
```

```powershell
# Shutdown VM (kolejno - prim02 najpierw, potem prim01)
& $VBox controlvm prim02 acpipowerbutton
Start-Sleep -Seconds 60
& $VBox controlvm prim01 acpipowerbutton

# Czekaj na faktyczny shutdown
foreach ($vm in @("prim01", "prim02")) {
    do {
        Start-Sleep -Seconds 5
        $running = & $VBox list runningvms | Select-String $vm
    } while ($running)
    Write-Host "$vm stopped"
}
```

### Krok 5 — Stop infra01 (last)

```powershell
& $VBox controlvm infra01 acpipowerbutton
do {
    Start-Sleep -Seconds 5
    $running = & $VBox list runningvms | Select-String "infra01"
} while ($running)
Write-Host "infra01 stopped"
Write-Host "===  Pełen lab zatrzymany ==="
```

### Quick stop (one-liner, NIE graceful)

```powershell
# UWAGA: bez gracefulnego shutdown bazy. Ryzyko crash recovery przy starcie + apply gap.
# Używaj TYLKO gdy graceful nie idzie (np. wisząca baza)
foreach ($vm in @("client01", "stby01", "prim02", "prim01", "infra01")) {
    & $VBox controlvm $vm poweroff 2>$null
    Start-Sleep -Seconds 3
}
```

---

## 🔄 Restart pojedynczej VM (rolling)

### Restart prim01 (RAC member — bez przerwy w usłudze)

```bash
# 1. Migracja TAC service na prim02 (jeśli running na prim01)
ssh oracle@prim01 ". ~/.bash_profile && srvctl relocate service -db PRIM -service MYAPP_TAC \
    -oldinst PRIM1 -newinst PRIM2 -force 2>/dev/null || true"

# 2. Stop instance PRIM1 (PRIM2 zostaje active — rolling availability)
ssh oracle@prim01 ". ~/.bash_profile && srvctl stop instance -db PRIM -instance PRIM1"

# 3. Stop CRS na prim01
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stop crs"
```

```powershell
# 4. Reboot VM
& $VBox controlvm prim01 acpipowerbutton
Start-Sleep -Seconds 60
& $VBox startvm prim01 --type headless
Start-Sleep -Seconds 240   # CRS startuje 3-5 min
```

```bash
# 5. Weryfikacja - CRS i instance PRIM1 wstały (auto-start)
ssh grid@prim01 ". ~/.bash_profile && crsctl check cluster -all"
ssh oracle@prim01 ". ~/.bash_profile && srvctl status database -db PRIM"

# 6. Restart LISTENER_DGMGRL (nie auto-start — patrz krok 2 cold START; oracle, NIE grid)
ssh oracle@prim01 ". ~/.bash_profile && lsnrctl start LISTENER_DGMGRL"

# 7. Restart obs_dc jeśli był ENABLED
ssh root@prim01 "systemctl start dgmgrl-observer-obs_dc"
```

### Restart stby01 (Single Instance — krótka przerwa w Active DG)

```bash
# 1. Stop bazy (Oracle Restart graceful)
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
# 3. STBY auto-start przez Oracle Restart (nie trzeba ręcznie)
ssh grid@stby01 ". ~/.bash_profile && crsctl stat res ora.stby.db -t"
# Oczekiwane: STATE=ONLINE, STATUS=Open

# 4. Listenery — auto-start przez HAS (S28-49/50). Verify (jeśli któryś OFFLINE):
ssh grid@stby01 ". ~/.bash_profile && srvctl start listener -listener LISTENER 2>/dev/null || true"
ssh grid@stby01 ". ~/.bash_profile && srvctl start listener -listener LISTENER_DGMGRL 2>/dev/null || true"

# 5. obs_dr restart
ssh root@stby01 "systemctl start dgmgrl-observer-obs_dr"

# 6. Weryfikacja apply
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
SHOW CONFIGURATION;
SHOW DATABASE STBY;
EXIT
EOF
# Oczekiwane: Apply Lag wraca do ~0s w ciągu 1-2 min
```

### Restart infra01 (storage + DNS — bardziej inwazyjny)

```bash
# 1. Stop bazy + CRS na prim01/prim02 (bo stracą iSCSI + DNS)
ssh oracle@prim01 ". ~/.bash_profile && srvctl stop database -db PRIM"
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stop cluster -all"
# UWAGA: stby01 też używa DNS — jeśli infra01 down >5min stby01 traci tnsnames resolution
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
# 3. Po infra01 UP - iSCSI sesje wracają (FIX-032 Restart=on-failure)
sleep 30
ssh root@prim01 "iscsiadm -m session"
ssh grid@prim01 ". ~/.bash_profile && asmcmd lsdg" | head -5

# 4. Start CRS + bazy
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl start cluster -all"
sleep 240
ssh oracle@prim01 ". ~/.bash_profile && srvctl start database -db PRIM"

# 5. Start STBY (HAS auto-start ale jeśli było stopped trzeba ręcznie)
ssh oracle@stby01 ". ~/.bash_profile && srvctl start database -db STBY"
```

---

## 📊 Status check — szybka diagnostyka

### One-shot health check (z hosta)

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

Write-Host "`n=== Database PRIM (verbose - oba OPEN!) ===" -ForegroundColor Cyan
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

# Data Guard broker (jeśli LISTENER_DGMGRL UP, alias /@PRIM przez wallet)
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

### Refresh DNS (jeśli DHCP NAT nadpisał — FIX-016 z VMs/FIXES_LOG)

```bash
# Na każdej VM (oprócz infra01)
sudo nmcli connection modify "System enp0s10" ipv4.ignore-auto-dns yes 2>/dev/null
sudo nmcli connection modify "System enp0s8"  ipv4.ignore-auto-dns yes 2>/dev/null
sudo nmcli connection modify "System enp0s3"  ipv4.dns "192.168.56.10"
sudo nmcli connection modify "System enp0s3"  ipv4.dns-search "lab.local"
sudo nmcli connection down "System enp0s3" && sudo nmcli connection up "System enp0s3"
```

### Sprawdź dyski ASM (jeśli /dev/oracleasm/* znikło po reboot)

```bash
ssh root@prim01 "ls -la /dev/oracleasm/"
# Jeśli puste:
ssh root@prim01 "iscsiadm -m node --loginall=automatic; sleep 5; ls -la /dev/oracleasm/"
```

### Switchover (Primary ↔ Standby) — przygotowanie

```bash
# Pełna procedura w docs/09_Test_Scenarios_PL.md
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl /@PRIM" <<'EOF'
VALIDATE DATABASE STBY;
SHOW CONFIGURATION VERBOSE;
EXIT
EOF
# Po VALIDATE bez warnings:
# DGMGRL> SWITCHOVER TO STBY;
# Po switchover: TAC service auto-fail-over (srvctl modify -role)
```

### Backup szybki (RMAN level 0 do FRA)

```bash
ssh oracle@prim01 ". ~/.bash_profile && rman target /" <<'EOF'
BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
DELETE NOPROMPT OBSOLETE;
EXIT
EOF
```

### Cheat sheet: scope komend `stop`/`start` w stacku Oracle

W RAC + Grid masz **kilka warstw "stop/start"** które różnią się scope. Dobierz właściwą do sytuacji.

**Hierarchia (od góry — najmniejszy scope, do dołu — największy):**

```
┌─ srvctl stop database -db PRIM         ← tylko DB, ASM/CRS/listenery up
│   ├─ srvctl stop instance -db PRIM -instance PRIM1   ← tylko jedna instancja
│   └─ srvctl stop service -db PRIM -service MYAPP_TAC ← tylko service
│
├─ crsctl stop cluster -all              ← cały cluster, ohasd zostaje up (cluster-wide)
│
├─ crsctl stop crs -f                    ← cały stack jednego node (force)
│
└─ crsctl stop has                       ← cały HAS stack jednego node (DB+ASM+CRS+ohasd)
```

**Tabela porównawcza:**

| Komenda (jako root) | Scope | Co zatrzymuje | Co zostaje up | Czas | Kiedy używać |
|---------------------|-------|---------------|---------------|------|--------------|
| `srvctl stop database -db PRIM` | tylko DB | DB instances PRIM1+PRIM2 | ASM, CRS, listenery, VIP-y, ohasd | ~30s | Maintenance bazy bez ruszania klastra |
| `srvctl stop instance -db PRIM -instance PRIM1` | jedna instancja | tylko PRIM1 | wszystko inne (PRIM2 OPEN, klienci pracują) | ~20s | Patch rolling per-node |
| `crsctl stop cluster` (jeden node) | jeden node | DB instance + ASM + CRS na tym node | ohasd na tym node | ~1-2 min | Restart klastra na pojedynczym nodzie |
| `crsctl stop cluster -all` | wszystkie nody | jak wyżej × wszystkie | ohasd na każdym nodzie | ~2-3 min | Cluster-wide restart |
| `crsctl stop crs -f` | jeden node | wszystko z `stop cluster` + force | nic | ~2-3 min | Gdy `stop cluster` się zacina |
| **`crsctl stop has`** | jeden node | **wszystko od DB w dół + ohasd** | nic — tylko procesy spoza Oracle | ~3-4 min | Pełen reset stacka (po `usermod`/limits change/group refresh) |

**Korespondujące komendy `start`:**

| Komenda | Co startuje |
|---------|-------------|
| `srvctl start database -db PRIM` | DB na obu nodach (jeśli ASM+CRS już są) |
| `srvctl start instance -db PRIM -instance PRIM1` | tylko jedna instancja |
| `crsctl start cluster` (jeden node) | CRS+ASM+DB na tym node |
| `crsctl start cluster -all` | CRS+ASM+DB na wszystkich nodach |
| `crsctl start crs` lub `crsctl start has` | pełen stack od ohasd w górę |

**Reboot OS = automatyczny `stop has`:** systemd-unit `oracle-ohasd.service` (instalowany przez Grid root.sh) wywołuje `crsctl stop has` przy `shutdown`/`reboot`. Nie trzeba ręcznie zatrzymywać klastra przed `shutdown -r now`.

---

## 📁 Logs — gdzie szukać problemów

| Co | Gdzie |
|----|-------|
| CRS startup issues | `/u01/app/grid/diag/crs/<node>/crs/trace/alert<node>.log` |
| ASM problemy (RAC) | `/u01/app/grid/diag/asm/+asm/+ASM<N>/trace/alert_+ASM<N>.log` |
| ASM stby01 (HAS) | `/u01/app/grid/diag/asm/+asm/+ASM/trace/alert_+ASM.log` |
| RDBMS PRIM1/2 | `/u01/app/oracle/diag/rdbms/prim/PRIM<N>/trace/alert_PRIM<N>.log` |
| RDBMS STBY | `/u01/app/oracle/diag/rdbms/stby/STBY/trace/alert_STBY.log` |
| iSCSI sessions | `journalctl -u iscsi -u iscsid` |
| systemd services | `journalctl -b 0` |
| DBCA last run | `/u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM*.log` |
| Listener (1521) | `$ORACLE_HOME/network/log/listener.log` lub `/u01/app/grid/diag/tnslsnr/<node>/listener/trace/listener.log` |
| LISTENER_DGMGRL (1522) | `$ORACLE_HOME/network/log/listener_dgmgrl.log` |
| Broker DMON | `/u01/app/oracle/diag/rdbms/prim/PRIM<N>/trace/drcPRIM<N>.log` (na PRIM) lub `/u01/app/oracle/diag/rdbms/stby/STBY/trace/drcSTBY.log` |
| Observer | `journalctl -u dgmgrl-observer-<obs_name>` lub `/u01/app/oracle/observer/<obs_name>.log` |
| RMAN duplicate | `/tmp/create_standby.log` (skrypt) lub `/u01/app/oracle/diag/clients/user_oracle/RMAN_*/trace/` |

---

## 🎯 Kolejność uruchamiania — szybki cheat sheet

```
┌──────────────────────────────────────────────────────────┐
│  COLD START (z hosta PowerShell):                        │
│  ──────────────────────────────────────────────────────  │
│  1.  & $VBox startvm infra01  --type headless            │
│      Start-Sleep 60                                       │
│      → DNS+NTP+iSCSI+master observer up                   │
│  2.  & $VBox startvm prim01   --type headless            │
│      & $VBox startvm prim02   --type headless            │
│      Start-Sleep 240                                      │
│      → CRS+ASM+PRIM1+PRIM2 OPEN                           │
│      → lsnrctl start LISTENER_DGMGRL na obu (1522)        │
│  3.  & $VBox startvm stby01   --type headless            │
│      Start-Sleep 120                                      │
│      → Oracle Restart auto-startuje STBY (READ ONLY+APPLY)│
│      → lsnrctl start LISTENER_DGMGRL na stby01 (1522)     │
│  4.  & $VBox startvm client01 --type headless            │
│  5.  systemctl start dgmgrl-observer-obs_ext (infra01)    │
│      systemctl start dgmgrl-observer-obs_dc  (prim01)     │
│      systemctl start dgmgrl-observer-obs_dr  (stby01)     │
│      ENABLE FAST_START FAILOVER (przez /@PRIM)            │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  COLD STOP (z hosta + z VM):                             │
│  ──────────────────────────────────────────────────────  │
│  1.  DISABLE FAST_START FAILOVER (dgmgrl /@PRIM)         │
│      systemctl stop dgmgrl-observer-* na 3 hostach        │
│  2.  acpipowerbutton client01                             │
│  3.  srvctl stop database -db STBY                        │
│      acpipowerbutton stby01                               │
│  4.  srvctl stop database -db PRIM                        │
│      crsctl stop cluster -all (jako root z prim01)        │
│      acpipowerbutton prim02, prim01                       │
│  5.  acpipowerbutton infra01                              │
└──────────────────────────────────────────────────────────┘
```

---

## 📚 Powiązane dokumenty

- `docs/01_Architecture_and_Assumptions_PL.md` — topologia, hasła, sieci, decyzje
- `docs/06_Data_Guard_Standby.md` — pełny setup Data Guard (RMAN DUPLICATE + broker)
- `docs/07_FSFO_Observers_PL.md` — Multi-Observer (master/backup) deployment
- `docs/08_TAC_and_Tests_PL.md` — TAC services + UCP + role-aware fail-over
- `docs/09_Test_Scenarios_PL.md` — switchover, failover, awarie
- `EXECUTION_LOG_PL.md` — historia fix-ów (S28-30..S28-38 dla create_standby_broker.sh)
- `VMs/FIXES_LOG.md` (poprzedni projekt) — knowledge base 100+ FIX-ów
