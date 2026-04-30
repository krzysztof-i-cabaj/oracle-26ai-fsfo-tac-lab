> 🇬🇧 English | [🇵🇱 Polski](./FIXES_LOG_PL.md)

# FIXES LOG — FSFO+TAC Lab VMs

History of issues encountered while building the environment and the fixes that were introduced.

---

## 2026-04-24

### FIX-001 — vbox_create_vms.ps1: host-only interface name (Windows vs Linux)

**Problem:** The script used the name `vboxnet0` (Linux convention). On Windows, VirtualBox creates interfaces named `VirtualBox Host-Only Ethernet Adapter` (or `#2`, `#3`, etc.).

**Symptom:**
```
VBoxManage.exe: error: The host network interface named 'vboxnet0' could not be found
```

**Fix:** `scripts/vbox_create_vms.ps1`
- Added the variable `$HostOnlyIF = "VirtualBox Host-Only Ethernet Adapter #2"`
- Replaced all occurrences of `vboxnet0` with the variable `$HostOnlyIF`
- Removed `hostonlyif create` (the adapter already existed)

---

### FIX-002 — 02_virtualbox_setup.md: missing `$VBox` variable

**Problem:** In the PowerShell example for shared folders, the `$VBox` definition was missing.

**Fix:** `02_virtualbox_setup.md`
- Added `$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"` before `$src`

---

### FIX-003 — 02_virtualbox_setup.md: verification section — `grep` does not work in PowerShell

**Problem:** Section 7 used `grep -E` and `grep -A` which do not exist in PowerShell.

**Fix:** `02_virtualbox_setup.md`
- Section 7 split into two blocks: **Windows (PowerShell)** and **Linux/macOS**
- `grep -E "..."` → `Select-String -Pattern "..."`
- `grep -A 20 "..."` → `Select-String -Pattern "..." -Context 0,20`

---

### FIX-004 — kickstart: backslash `\` does not work as line continuation

**Problem:** The `network` directive in the kickstart was written across multiple lines using `\`. The Anaconda kickstart parser **does not support** the backslash as a line continuation — it treats it as an argument.

**Symptom:**
```
Unknown command: --ip=192.168.56.10
Unknown command: --nameserver=127.0.0.1,8.8.8.8
Unknown command: --activate
```
(every line after `\` was treated as a separate, invalid command)

**Fix:** All 5 `kickstart/ks-*.cfg` files
- Each `network` directive written on a single line

---

### FIX-005 — kickstart: `--ipv4-dns-search` is not a valid option

**Problem:** The `--ipv4-dns-search=lab.local` option used in the `network` directive — does not exist in RHEL8/OL8 kickstart.

**Fix:** All 5 `kickstart/ks-*.cfg` files
- Removed `--ipv4-dns-search=lab.local` from `network` directives
- DNS search domain is configured later via nmcli

---

### FIX-006 — 03_os_install_ol810.md: wrong address for downloading the kickstart

**Problem (iteration 1):** URL `http://192.168.56.1:8000/...` — the initrd does not configure the host-only NIC (no DHCP), so it cannot download the file.

**Problem (iteration 2):** URL `http://10.0.2.2:8000/...` — `10.0.2.2` is the VirtualBox NAT virtual router, not a real Windows interface. The Python HTTP server doesn't listen on it → `Connection refused`.

**Solution:** The `inst.ip` parameter configures a static IP on `enp0s3` **before** attempting to download the kickstart, so `192.168.56.1:8000` becomes reachable.

**Fix:** `03_os_install_ol810.md` — GRUB parameters table:
```
inst.ip=192.168.56.XX::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/kickstart/ks-<vm>.cfg
```

---

### FIX-007 — kickstart: `compat-openssl11` is not on the DVD ISO

**Problem:** The `compat-openssl11` package listed in the `%packages` section is not available on the local OL 8.10 DVD ISO. Anaconda asks an interactive question:
```
Problems in request: missing packages: compat-openssl11
Would you like to ignore this and continue installation?
```

**Workaround:** type `yes` — installation continues without interruption.

**Fix:** `kickstart/ks-prim01.cfg`, `ks-prim02.cfg`, `ks-stby01.cfg`
- Removed `compat-openssl11` from the `%packages` section
- The package will be installed automatically by `oracle-database-preinstall-23ai` in `%post` (as a dependency, after enabling the online repo)

---

### FIX-008 — 01_network_addressing.md: weak references to automation scripts

**Problem:** The `setup_dns_infra01.sh` script was mentioned only in an appendix at the end of the file. Section 3.5 (bind9 installation) showed only manual steps — the reader didn't know there was a ready-made script. For NTP there was no script at all.

**Fix:**
- `01_network_addressing.md` section 3.5 — added a prominent **⚡ AUTOMATIC method** block referencing `scripts/setup_dns_infra01.sh` **before** the manual block
- `01_network_addressing.md` section 6 — added a prominent **⚡ AUTOMATIC method** block with `scripts/setup_chrony.sh --role=server|client`
- The appendix at the end expanded from a one-liner into a table of all scripts in this document + execution order
- New script: `scripts/setup_chrony.sh` with the `--role=server|client` parameter
- `scripts/README.md` updated with `setup_chrony.sh` in the table and in the "Typical execution order" section

---

## 2026-04-24 (continued) — Cross-check and bulk fill-in

### FIX-009 — CRITICAL: `04_os_preparation.md` UID inconsistency with kickstarts and `00_architecture.md`

**Problem:** Document 04 described `preinstall-23ai` creating `oracle` with UID=54321, and that we then manually add `grid` with UID=54322. But:
- `00_architecture.md` Section 5.2 says: `grid` UID=54321, `oracle` UID=54322
- The kickstarts (`ks-prim01.cfg`, `ks-prim02.cfg`, `ks-stby01.cfg`) create exactly that: `grid` 54321, `oracle` 54322

So document 04 had the **UID convention reversed** relative to the architecture and the kickstarts. Anyone following document 04 would end up with `oracle=54321` instead of 54322 — collision with `grid=54321` after kickstart.

**Fix:** `04_os_preparation.md`
- Section 1.2 — reworked to show **target** UIDs (grid=54321, oracle=54322 — consistent with the architecture), with an explanation that user UID and group GID with the same value are **separate namespaces** in Linux (not a collision)
- Section 2 received a clear directive: "**if you used the kickstarts — skip to section 3**" (because everything is already done)
- Added section 2.1 (manual) with correct `useradd -u 54321 ... grid` + a comment on how to change `oracle` to 54322 if preinstall gave it 54321
- Removed the inconsistent comment "UID 54322 is normally for oracle in older preinstall" (misleading in our lab context)

---

### FIX-010 — CRITICAL: FRA size inconsistent between `dbca_prim.rsp` and `08_database_create_primary.md`

**Problem:** `dbca_prim.rsp` had `recoveryAreaSize=10240` (10 GB), but `08_database_create_primary.md` in the post-create section changed `db_recovery_file_dest_size` to 15G via `ALTER SYSTEM`. With no rationale. Under SYNC transport + flashback + RMAN, 10 GB filled up quickly.

**Fix:** `response_files/dbca_prim.rsp`
- `recoveryAreaSize=15360` (15 GB) — consistent with the ALTER SYSTEM in document 08
- Added a comment explaining why 15 GB (archivelog SYNC + flashback + RMAN backup)

---

### FIX-011 — Firewall ONS port 6200 missing in `04_os_preparation.md` and `12_tac_service.md`

**Problem:** Port 6200/tcp (ONS — Oracle Notification Service) is critical for TAC — without it the UCP client doesn't receive FAN events after failover and won't perform replay. It was only in `01_network_addressing.md` section 5.2 and implicitly in the `deploy_tac_service.sh` script, but nowhere clearly flagged in documents 04 and 12 as "YOU MUST OPEN THIS PORT".

**Fix:**
- `04_os_preparation.md` — new section 4.4 "Ports to open in firewalld" with a table of all lab ports (SSH, 1521, 1522, **6200 bolded**, 5500, 53, 123, 3260)
- `12_tac_service.md` — the ⚡ AUTOMATIC block contains the port 6200 requirement with an explanation of the consequences (no TAC replay)

---

### FIX-012 — STRUCTURAL: all scripts in `scripts/` were "documentation orphans"

**Problem (identified during the cross-check audit):** None of the 14 scripts in `scripts/` (apart from `setup_dns_infra01.sh` and `setup_chrony.sh` — FIX-008) had a prominent reference in the main 00–16 documents. A reader of, for example, 06_grid_infrastructure_install.md didn't know that `install_grid_silent.sh` existed — they were doing everything manually. The scripts were documented only in `scripts/README.md` (a hidden section).

**Fix:** Added a **⚡ AUTOMATIC method** block at the beginning of each document (right after Prereq):
- `04_os_preparation.md` → `prepare_host.sh --role=rac|si|infra|client`
- `05_shared_storage_iscsi.md` → `setup_iscsi_target_infra01.sh` + `setup_iscsi_initiator_prim.sh prim01|prim02`
- `06_grid_infrastructure_install.md` → `install_grid_silent.sh` (with a warning about `root.sh` being run manually and sequentially)
- `07_database_software_install.md` → `install_db_silent.sh` (RAC + SI)
- `08_database_create_primary.md` → `create_primary.sh`
- `09_standby_duplicate.md` → `duplicate_standby.sh`
- `10_data_guard_broker.md` → `configure_broker.sh`
- `11_fsfo_observer.md` → `setup_observer_infra01.sh`
- `12_tac_service.md` → `deploy_tac_service.sh`
- `14_test_scenarios.md` → `validate_env.sh` (readiness check before scenarios)

Each block contains: (1) the `bash .../script.sh` command with context (as which user/on which VM), (2) a description of what the script does, (3) verification, (4) an indication of which manual steps **remain** (such as SSH equivalency, profile, root.sh).

---

### FIX-013 — SEMANTIC: filling in 5 gaps in MAA knowledge

**Problem:** Several critical Oracle MAA mechanisms were not explained, so someone with basic Oracle knowledge didn't know **why** we do a given thing.

**Fixes (built into the ⚡ blocks or as separate notes):**

1. **SRL count per thread in RAC** (`08_database_create_primary.md`):
   Added a ⚠ note explaining that for a 2-thread RAC with 3 ORLs per thread you need **8 SRLs in total** (4 × 2), not 4. A common mistake when manually doing ADD STANDBY LOGFILE.

2. **AFFIRM verification** (`10_data_guard_broker.md`):
   In the ⚡ block, added the SQL check `SELECT affirm FROM v$archive_dest WHERE dest_id=2;` — the broker sets AFFIRM automatically for SYNC, but it's worth verifying before enabling FSFO.

3. **Broker config file SINGLE per database** (`10_data_guard_broker.md`):
   In the description of the `configure_broker.sh` script, added an explanation that `dg_broker_config_file1/2` is **one file per database** (not per instance on RAC) — on RAC we save it to `+DATA` (shared), on SI to the filesystem.

4. **Threshold vs LagLimit semantics** (`11_fsfo_observer.md`):
   In the ⚡ block, a full explanation of the difference:
   - Threshold = how long to wait for a heartbeat before failover
   - LagLimit = max apply lag tolerated before failover
   Plus a recommendation that 30s for both is the baseline for SYNC; for ASYNC the LagLimit should be 300s+.

5. **root.sh sequentially on both RAC nodes** (`06_grid_infrastructure_install.md`):
   In the ⚡ block, **a clear warning**: first the **full `root.sh` on prim01**, only then on prim02. Can be done via `ssh -t root@prim02 '...'` (with TTY), but **not in parallel** — CRS on prim01 must be active before prim02 joins the cluster.

---

### FIX-014 — kickstart: `--nodefroute` on the NAT interface blocks the internet

**Problem:** In the kickstarts (all 5) I had earlier set `--nodefroute` on the NAT interface (enp0s10 for prim/infra, enp0s8 for stby/client). This caused the VM after installation to **have no default route to the internet** — `dnf` tries to reach `yum.oracle.com`, DNS resolves (fallback 8.8.8.8), but the IP packet doesn't get through.

**Symptom on infra01 during the first `dnf install bind`:**
```
Curl error (6): Couldn't resolve host name for https://yum.oracle.com/...
Could not resolve host: yum.oracle.com
```
Even though `/etc/resolv.conf` had `8.8.8.8` — because the DNS query goes out through some interface, and without a default route Linux doesn't know which.

**Cause:** `--nodefroute` prevents the installation of a default route via DHCP NAT. Host-only (enp0s3) also had no gateway (intentionally, because 192.168.56.1 is Windows, not a router). Effect: no default route = no internet.

**Fix:** All 5 `kickstart/ks-*.cfg` kickstarts
- Removed `--nodefroute` from the `network` directive for the NAT interface
- Added a comment explaining why NAT must install a default route
- Host-only (enp0s3), priv (enp0s8), and storage (enp0s9) remain without `--gateway` — these networks are link-local (directly connected), they don't need a router

**Fix on a running VM** (for those that have already installed):
```bash
# 1. Identify the NAT subnet and gateway:
ip -4 addr show enp0s10                # or enp0s8 for stby/client
# Note the subnet, e.g. 10.0.5.0/24 -> gateway = 10.0.5.2
# (VirtualBox NAT assigns a per-VM subnet 10.0.X.0/24; gateway always at .2)

# 2. Add default route via the real gateway:
sudo ip route add default via 10.0.X.2 dev enp0s10   # substitute X (e.g. 5)

# 3. Persistent via NetworkManager (connection name is "System enp0sNN"):
sudo nmcli connection modify "System enp0s10" ipv4.never-default no
sudo nmcli connection modify "System enp0s10" ipv4.ignore-auto-routes no
sudo nmcli connection down "System enp0s10" && sudo nmcli connection up "System enp0s10"
```

---

### FIX-015 — VirtualBox NAT subnet may differ from the default `10.0.2.0/24`

**Problem:** The documentation and comments in the kickstarts assumed VirtualBox NAT gives `10.0.2.0/24` with gateway `10.0.2.2`. In practice, VirtualBox assigns a **per-VM** subnet `10.0.X.0/24` where `X` may be different (on the tester's setup: `10.0.5.0/24` → gateway `10.0.5.2`). Cause: VBox host configuration (old configuration, `--natnet` set earlier, or VBox in a newer version).

**Symptom:** `sudo ip route add default via 10.0.2.2 dev enp0s10` → `Error: Nexthop has invalid gateway` (because 10.0.2.2 is not on any subnet attached to the VM).

**Rule:** VirtualBox NAT gateway = **`.2` of the VM's local subnet**. Check: `ip -4 addr show enp0s10` → take the first 3 octets of the IP + `.2`.

**Fix:**
- `03_os_install_ol810.md` — section 3.1 "Why inst.ip..." reworked to use the generic `10.0.X.2` with a tip on how to check the subnet
- `kickstart/ks-infra01.cfg` — comment about NAT gateway updated to the generic `10.0.X.2`
- FIX-014 (previous entry) updated: the fix commands use the placeholder `10.0.X.2` with instructions on how to find X

---

### FIX-016a — `ks-infra01.cfg` and `setup_dns_infra01.sh` did not solve their own DNS problem

**Problem:** The infra01 kickstart set `--nameserver=127.0.0.1,8.8.8.8` for host-only, but after activating NAT, DHCP overwrote resolv.conf with the LAN router address (192.168.1.1) in FIRST place. The `setup_dns_infra01.sh` script tested via `dig @192.168.56.10` (directly to bind9), so it didn't detect that the system resolver behaves differently. Symptom: `nslookup scan-prim.lab.local` without `@` → `NXDOMAIN`, even though bind9 is working.

**Fix:**
- `scripts/setup_dns_infra01.sh` — added at the end: `nmcli ignore-auto-dns yes` for NAT + `dns=127.0.0.1` for host-only + connection restart. Plus verification via the system `nslookup` (not just `dig @...`).
- `kickstart/ks-infra01.cfg` — analogous fragment in `%post` (for new installations).

---

### FIX-016 — DHCP NAT overrides DNS with the LAN router address instead of infra01

**Problem:** After fixing the default route (FIX-014/FIX-015), DHCP NAT propagated upstream DNS from the user's LAN router (e.g. `192.168.1.1` — Orange Fiber) into `/etc/resolv.conf` in **first place**, **overriding** the static `192.168.56.10` from the kickstart. Effect: `nslookup scan-prim.lab.local` → `NXDOMAIN` (because the LAN router doesn't know the `lab.local` zone).

On `infra01` it didn't hurt — because the kickstart had `--nameserver=127.0.0.1,8.8.8.8` and `127.0.0.1` (local bind9) was first. But on `prim01`/`prim02`/`stby01`/`client01` the static `192.168.56.10` was pushed behind `192.168.1.1`.

**Cause:** NetworkManager by default accepts DNS from DHCP (`ipv4.ignore-auto-dns=no`). When DHCP NAT activated with a default route, its DNS "won" the ordering.

**Fix:**

1. **Kickstarts** (`ks-prim01.cfg`, `ks-prim02.cfg`, `ks-stby01.cfg`, `ks-client01.cfg`) — added in `%post` an `nmcli` sequence:
   ```
   nmcli connection modify "System <NAT_IFACE>" ipv4.ignore-auto-dns yes
   nmcli connection modify "System enp0s3" ipv4.dns "192.168.56.10"
   nmcli connection modify "System enp0s3" ipv4.dns-search "lab.local"
   nmcli connection modify "System enp0s3" ipv4.ignore-auto-dns yes
   ```
   NAT interface: `enp0s10` for prim01/prim02, `enp0s8` for stby01/client01.
   (`ks-infra01.cfg` has different DNS — `127.0.0.1,8.8.8.8` — and doesn't need the change, because 127.0.0.1 is first.)

2. **`scripts/setup_chrony.sh --role=client`** — auto-fix DNS added before preflight. The script itself enforces correct DNS before trying to connect to `infra01.lab.local` via chrony. It detects the active NAT interface (enp0s10 or enp0s8) and modifies only the one that exists.

**Fix on a running VM** (for already installed prim01/prim02/stby01/client01 — before running `setup_chrony.sh --role=client`):
```bash
# prim01/prim02 (NAT = enp0s10):
nmcli connection modify "System enp0s10" ipv4.ignore-auto-dns yes
nmcli connection modify "System enp0s3" ipv4.dns "192.168.56.10"
nmcli connection modify "System enp0s3" ipv4.dns-search "lab.local"
nmcli connection modify "System enp0s3" ipv4.ignore-auto-dns yes
nmcli connection down "System enp0s10" && nmcli connection up "System enp0s10"
nmcli connection down "System enp0s3"  && nmcli connection up "System enp0s3"

# stby01/client01 (NAT = enp0s8): substitute enp0s8 for enp0s10
```

Verification: `cat /etc/resolv.conf` → must show `nameserver 192.168.56.10` as the only one (or first).

---

### FIX-017 — OL8 has the package `targetcli`, not `targetcli-fb`

**Problem:** The `setup_iscsi_target_infra01.sh` script and the documentation used the name `targetcli-fb` (Fedora-style). On Oracle Linux 8 the package is simply called `targetcli`.

**Symptom:** `dnf install -y targetcli-fb` → `No match for argument: targetcli-fb`

**Fix:**
- `scripts/setup_iscsi_target_infra01.sh` line 57 — `targetcli-fb target-restore` → `targetcli`
- `05_shared_storage_iscsi.md` lines 84, 469, 472 — same
- `00_architecture.md` line 44 — list of installed packages

**Bonus:** added a topology diagram in `05_shared_storage_iscsi.md` section 0 (ASCII: infra01 → LIO → 5 LUN → iSCSI 3260 → prim01/prim02 → `/dev/oracleasm/...`) — with an explanation of shared storage and the production alternative.

---

### FIX-018 — udev rules for iSCSI LIO: `ID_SERIAL` does not contain the backstore name

**Problem:** The `setup_iscsi_initiator_prim.sh` script used udev rules with the pattern `ENV{ID_SERIAL}=="*ocr1*"` assuming that LIO generates an `ID_SERIAL` containing the backstore name (`lun_ocr1`). **False assumption** — LIO generates random 32-character hex strings (e.g. `360014057d91cd990bb3472f8b6d6acbd`). The rules didn't match → no symlinks `/dev/oracleasm/OCR1/...`.

**Symptom on prim01:**
```
/dev/sdb LUN=0 serial=360014057d91cd990bb3472f8b6d6acbd
# udev rule: ENV{ID_SERIAL}=="*ocr1*"   ← DOES NOT MATCH
# Result: /dev/oracleasm/OCR1 does not exist
```

**Solution:** Mapping by **SCSI LUN#** instead of by name pattern. The LIO target on infra01 has a fixed assignment:
- LUN 0 → lun_ocr1
- LUN 1 → lun_ocr2
- LUN 2 → lun_ocr3
- LUN 3 → lun_data1
- LUN 4 → lun_reco1

The script reads `/sys/block/sdX/device/scsi_device/` → extracts LUN# → generates a udev rule with the specific `ID_SERIAL` (read via `/usr/lib/udev/scsi_id`).

**Fix:** `scripts/setup_iscsi_initiator_prim.sh` — section 9 (creating udev rules) rewritten from name patterns to dynamic mapping LUN# → ID_SERIAL → symlink. The generated `/etc/udev/rules.d/99-oracleasm.rules` file now has specific ID_SERIAL strings, not `*ocr1*`.

**Consequence for the user:** The `ID_SERIAL` of each LUN is **identical on prim01 and prim02** (because it's the same physical LUN over iSCSI). You can generate the rules once on prim01 and `scp` them to prim02 — or run the script on both sides (both produce the same file).

---

### FIX-019 — Shared folder `OracleBinaries` was not auto-created/auto-mounted

**Problem:** The old `vbox_create_vms.ps1` had the condition `if (Test-Path "D:\OracleBinaries")` — if the directory didn't exist on the host at the moment of VM creation, the shared folder wasn't added at all. Additionally, the kickstarts had no fstab entry for this share (only for `_RMAN_BCK_from_Linux_`). Effect: `/media/sf_OracleBinaries/` and `/mnt/oracle_binaries` didn't exist — there was nowhere to upload the Oracle binaries.

**Fix:**

1. `scripts/vbox_create_vms.ps1` — the OracleBinaries shared folder is **always** added:
   - If `D:\OracleBinaries` doesn't exist → creates it (empty)
   - Adds it via `VBoxManage sharedfolder add --automount`
   - Additionally `_RMAN_BCK_from_Linux_` (if it exists)

2. Kickstarts `ks-*.cfg` (all 5) — in `%post` an fstab entry was added:
   ```
   OracleBinaries  /mnt/oracle_binaries  vboxsf  rw,uid=<UID>,gid=<GID>,dmode=775,fmode=664,nofail  0  0
   ```
   Owner:
   - prim01/prim02/stby01/infra01 → `oracle:oinstall` (54322:54321)
   - client01 → `kris:kris` (1000:1000)

**Fix for already-running VMs (user must do manually):**
```powershell
# Windows PowerShell (shutdown + add shared folder + start)
New-Item -ItemType Directory -Path "D:\OracleBinaries" -Force
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
foreach ($vm in "prim01","prim02","stby01","infra01","client01") {
    & $VBox controlvm $vm acpipowerbutton
    # Wait for shutdown
    & $VBox sharedfolder add $vm --name "OracleBinaries" --hostpath "D:\OracleBinaries" --automount
    & $VBox startvm $vm --type headless
}
```

On each VM (after restart, as root):
```bash
mkdir -p /mnt/oracle_binaries
echo "OracleBinaries  /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0" >> /etc/fstab
mount /mnt/oracle_binaries
```

---

### FIX-020 — `prepare_host.sh` did not set limits for the `grid` user → cluvfy FAILED

**Problem:** The `oracle-database-preinstall-23ai` RPM sets `/etc/security/limits.d/oracle-database-preinstall-23ai.conf` **only for the `oracle` user**. The `grid` user (Role Separation for Grid Infrastructure) has no limits — `ulimit -s` shows OS default 8192 (required ≥ 10240), `ulimit -Hl` = 64K (required 128 MB).

**Symptom:** `runcluvfy.sh stage -pre crsinst` returns:
- `PRVG-0449 : Proper soft limit for maximum stack size was not found [Expected >= "10240" ; Found = "8192"]`
- `PRVE-0059 : no default entry or entry specific to user "grid" was found in the configuration file "/etc/security/limits.conf" when checking the maximum locked memory "HARD" limit`

**Fix:** `scripts/prepare_host.sh` — in the "Preinstall RPM (for rac/si)" section a block was added that creates `/etc/security/limits.d/99-grid-oracle.conf` with limits for `grid` (nofile, nproc, stack, memlock) and supplements stack/memlock for `oracle`.

The `04_os_preparation.md` section 3 document HAD this fragment in the manual instructions, but the ⚡ AUTOMATIC block didn't clearly flag it as a manual step — added in FIX-012, now prepare_host.sh does it automatically.

**Fix for already-running VMs (prim01, prim02):**
```bash
sudo tee /etc/security/limits.d/99-grid-oracle.conf > /dev/null <<'EOF'
grid soft nofile 1024
grid hard nofile 65536
grid soft nproc 16384
grid hard nproc 16384
grid soft stack 10240
grid hard stack 32768
grid soft memlock 134217728
grid hard memlock 134217728
oracle soft stack 10240
oracle hard stack 32768
oracle soft memlock 134217728
oracle hard memlock 134217728
EOF
# After this LOG OUT and back in, then:
su - grid -c "ulimit -s"  # 10240
```

---

### FIX-021 — `runcluvfy.sh` sees the NAT interface as cluster network (false FAILED)

**Problem:** All VMs in VirtualBox NAT have **the same DHCP IP** (e.g. `10.0.5.15`) — because NAT is per-VM isolated. Cluvfy doesn't know that, tests TCP connectivity between `10.0.5.15 → 10.0.5.15` (self-loopback) and considers it FAILED. On top of that IPv6 link-local between VMs also doesn't route in NAT.

**Symptom:**
```
PRVG-1172 : The IP address "10.0.5.15" is on multiple interfaces "enp0s10" on nodes "prim01,prim02"
PRVG-11067 : TCP connectivity from node "prim02": "10.0.5.15" to node "prim01": "10.0.5.15" failed
```

**Fix:** use the `-networks` parameter in `runcluvfy.sh` to explicitly indicate which interfaces are public/cluster_interconnect and skip enp0s10 (NAT).

**WARNING — `-networks` syntax in cluvfy 26ai:**
- Separator between interfaces: **`/`** (slash), NOT `,` (comma)
- Types: **lowercase** (`public`, `cluster_interconnect`, `asm`)
- Subnet without mask (`192.168.56.0`, NOT `192.168.56.0/24`)

The first attempt with comma+UPPERCASE syntax returned `PRVG-11089 : Could not find a valid network entry`:
```bash
# WRONG (this doesn't work):
-networks enp0s3:192.168.56.0:PUBLIC,enp0s8:192.168.100.0:cluster_interconnect
```

Correct syntax:
```bash
# OK:
./runcluvfy.sh stage -pre crsinst -n prim01,prim02 \
    -networks "enp0s3:192.168.56.0:public/enp0s8:192.168.100.0:cluster_interconnect" \
    -verbose
```

**Update `06_grid_infrastructure_install.md`** section 4 — uses the correct syntax.

---

### FIX-022 — Physical Memory warning 8GB (cosmetic in the lab)

**Problem:** cluvfy requires 8 GB physical memory, prim01/prim02 received 8 GB RAM, but Linux reports ~7.8 GB after subtracting kernel/firmware. Cluvfy marks it as FAILED.

**Fix:** **ignore** — during `gridSetup.sh -silent` use the `-ignorePrereq` flag or specify in the response file `oracle.install.option=... ignoreSysPrereqs=true`. Alternatively, bump RAM to 9 GB in VirtualBox.

---

## 2026-04-25

### FIX-023 — `grid.rsp`: invalid parameter `oracle.install.crs.config.gimrSA` (19c vs 26ai schema)

**Problem:** The response file for 23.26.1 contained the parameter `oracle.install.crs.config.gimrSA=false` from a line written for 19c. In the Oracle 26ai response file schema (`rspfmt_crsinstall_response_schema_v23.0.0`) this parameter does not exist — GIMR/MGMTDB was removed in 26ai.

**Symptom:**
```
[FATAL] [INS-10105] The given response file /home/grid/grid.rsp is not valid.
   CAUSE: Syntactically incorrect response file.
   SUMMARY:
       - cvc-complex-type.2.4.a: Invalid content was found starting with element
         'oracle.install.crs.config.gimrSA'. One of '{ ... configureBackupDG,
         oracle.install.asm.configureGIMRDataDG, ...}' is expected.
```

**Fix:** `response_files/grid.rsp` (lines 122-124)
```diff
- # GIMR (Grid Infrastructure Management Repository) - disabled to save resources
- oracle.install.crs.config.gimrSA=false
+ # GIMR Data DG (separate disk group for MGMTDB) - not used in 26ai, MGMTDB removed in 26ai
+ # NOTE: in 26ai the parameter is named 'configureGIMRDataDG' (not 'gimrSA' as in 19c)
+ oracle.install.asm.configureGIMRDataDG=false
```

**Fix for running VMs (on prim01 as grid):**
```bash
sed -i 's|^oracle.install.crs.config.gimrSA=false|oracle.install.asm.configureGIMRDataDG=false|' /home/grid/grid.rsp
grep -E "configureGIMRDataDG|gimrSA" /home/grid/grid.rsp
```

**Note for the future:** The `gridSetup.sh -silent` validator stops at the **first** XML schema error. If further messages appear about other 19c parameters → see FIX-024 (full response file rewrite).

---

### FIX-024 — `grid.rsp`: complete rewrite from 19c-style to 26ai short names (schema 23.0.0)

**Problem:** After fixing `gimrSA` (FIX-023) the validator threw further `[FATAL] [INS-10105]` errors on every "deprecated" form parameter (`oracle.install.option`, `oracle.install.crs.config.ClusterConfiguration`, `oracle.install.crs.config.gpnp.scanName`, ...). The 23.0.0 response file schema (`/oracle/install/rspfmt_crsinstall_response_schema_v23.0.0`) requires **NEW short names** consistent with the template `/u01/app/23.26/grid/install/response/gridsetup.rsp` from the 26ai installer (the `Deprecated:` comments in the template list the old names).

**Symptoms (successive fatals):**
```
[FATAL] [INS-10105] Invalid content was found starting with element
'oracle.install.crs.config.ClusterConfiguration'. One of '{installOption,
oracle.install.crs.config.clusterUsage, clusterUsage, ...}' is expected.
```

**Mapping old→new (key parameters):**

| Old name (deprecated) | New name (26ai) | Notes |
|-----------------------|-----------------|-------|
| `oracle.install.option=CRS_CONFIG` | `installOption=CRS_CONFIG` | |
| `oracle.install.crs.config.ClusterConfiguration=STANDALONE` | **REMOVED** + `clusterUsage=RAC` | DSC/Domain Services removed in 23ai/26ai |
| `oracle.install.crs.config.gpnp.configureGNS` | `configureGNS` | |
| `oracle.install.crs.config.autoConfigureClusterNodeVIP` | `configureDHCPAssignedVIPs` | |
| `oracle.install.crs.config.clusterName` | `clusterName` | |
| `oracle.install.crs.config.gpnp.scanName/scanPort` | `scanName / scanPort` | |
| `oracle.install.crs.config.clusterNodes=prim01:prim01-vip:HUB,...` | `clusterNodes=prim01:prim01-vip,prim02:prim02-vip` | **WITHOUT `:HUB`** — HUB/LEAF abolished in 23ai |
| `oracle.install.crs.config.networkInterfaceList` | `networkInterfaceList` | |
| `oracle.install.crs.config.storageOption` | `storageOption` | value `FLEX_ASM_STORAGE` still OK |
| `oracle.install.asm.SYSASMPassword` | `sysasmPassword` | |
| `oracle.install.asm.monitorPassword` | `asmsnmpPassword` | |
| `oracle.install.asm.diskGroup.name` | `diskGroupName` | |
| `oracle.install.asm.diskGroup.redundancy/AUSize/disks` | `redundancy / auSize / diskList` | |
| `oracle.install.asm.diskGroup.diskDiscoveryString` | `diskString` | |
| `oracle.install.asm.gimrDG.AUSize` | **REMOVED** | GIMR/MGMTDB removed |
| `oracle.install.asm.OSDBA/OSOPER/OSASM` | `OSDBA / OSOPER / OSASM` | |
| `oracle.install.asm.configureGIMRDataDG=false` | `configureBackupDG=false` | OCR backup DG (separate from GIMR) |
| `oracle.install.crs.config.useIPMI` | `useIPMI` | |
| `oracle.install.crs.rootconfig.executeRootScript` | `executeRootScript` | |

**Added parameters (explicitly):**
- `scanType=LOCAL_SCAN` (we have DNS on infra01, not SHARED_SCAN from another cluster)
- `clusterUsage=RAC` (instead of deprecated `ClusterConfiguration=STANDALONE`)
- `managementOption=NONE` (no Cloud Control)
- `configureBackupDG=false` (instead of `configureGIMRDataDG=false`)
- `enableAutoFixup=false` (cluvfy doesn't auto-correct)
- `INVENTORY_LOCATION=/u01/app/oraInventory` (explicitly)

**Fix:** `response_files/grid.rsp` (v1.0 → v2.0) + new file `response_files/grid_minimal.rsp` (62 lines, no comments — ready to `cp` onto the VM).

**Fix for running VMs (prim01):**
```bash
cp /home/grid/grid.rsp /home/grid/grid.rsp.bak_v1
cp /media/sf_OracleBinaries/grid.rsp /home/grid/grid.rsp
# or: cp /media/sf_OracleBinaries/grid_minimal.rsp /home/grid/grid.rsp
```

**Validation of success (2026-04-25 08:11):**
```
Launching Oracle Grid Infrastructure Setup Wizard...
[WARNING] [INS-40109] The specified Oracle base location is not empty   ← OK
[WARNING] [INS-13013] Target environment does not meet some mandatory   ← OK with -ignorePrereqFailure
INFO: Copying /u01/app/23.26/grid to remote nodes [prim02]              ← binary copy phase
```

**Lesson:** When migrating response files between major Oracle releases (19c → 26ai) **don't replace parameters one by one** — a parser that stops at the first error is a path of suffering. Generate the template from the installer (`cat $ORACLE_HOME/install/response/gridsetup.rsp`), map all values, replace the whole thing.

---

### FIX-025 — `db.rsp`: deprecated 19c-style → 26ai short names + `managementOption=DEFAULT` (not `NONE`)

**Problem:** Identical attack vector as FIX-024, this time `db.rsp` during `runInstaller -silent`. Additionally: in **the db schema** 23.0.0 (`rspfmt_dbinstall_response_schema_v23.0.0`) the value `NONE` for `managementOption` is invalid — a difference vs the grid schema where `NONE` was OK.

**Symptom 1 (deprecated names):** `[FATAL] [INS-10105]` on each of the parameters `oracle.install.option`, `oracle.install.db.InstallEdition`, `oracle.install.db.OSDBA_GROUP`, ...

**Symptom 2 (managementOption):**
```
[FATAL] [INS-10105] The given response file /home/oracle/db.rsp is not valid.
   SUMMARY:
       - cvc-enumeration-valid: Value 'NONE' is not facet-valid with respect to
         enumeration '[CLOUD_CONTROL, DEFAULT]'. It must be a value from the enumeration.
       - cvc-type.3.1.3: The value 'NONE' of element 'managementOption' is not valid.
```

**Mapping old→new (`db.rsp` v1 → v2):**

| Old name (deprecated) | New name (26ai) | Notes |
|-----------------------|-----------------|-------|
| `oracle.install.option=INSTALL_DB_SWONLY` | `installOption=INSTALL_DB_SWONLY` | |
| `oracle.install.db.InstallEdition=EE` | `installEdition=EE` | |
| `oracle.install.db.OSDBA_GROUP=dba` | `OSDBA=dba` | |
| `oracle.install.db.OSOPER_GROUP=oper` | `OSOPER=oper` | |
| `oracle.install.db.OSBACKUPDBA_GROUP=backupdba` | `OSBACKUPDBA=backupdba` | |
| `oracle.install.db.OSDGDBA_GROUP=dgdba` | `OSDGDBA=dgdba` | |
| `oracle.install.db.OSKMDBA_GROUP=kmdba` | `OSKMDBA=kmdba` | |
| `oracle.install.db.OSRACDBA_GROUP=racdba` | `OSRACDBA=racdba` | |
| `oracle.install.db.CLUSTER_NODES=prim01,prim02` | `clusterNodes=prim01,prim02` | |
| `oracle.install.db.isRACOneInstall=false` | **REMOVED** | not in schema 23.0.0 |
| `oracle.install.db.config.starterdb.*` | **REMOVED** + new `dbType, gdbName, dbSID, ...` | empty for SWONLY |
| `DECLINE_SECURITY_UPDATES, SECURITY_UPDATES_VIA_MYORACLESUPPORT` | **REMOVED** | not in schema 23.0.0 |
| (none) | `managementOption=DEFAULT` | **IMPORTANT:** `NONE` does NOT work, must be `DEFAULT` or `CLOUD_CONTROL` |

**Fix:** `response_files/db.rsp` (v1.0 → v2.0) + `response_files/db_minimal.rsp` (40 lines without comments).

**Fix for running VMs:**
```bash
# Variant A - copy the new file
cp /mnt/oracle_binaries/db.rsp /home/oracle/db.rsp
chmod 600 /home/oracle/db.rsp

# Variant B - hot-fix only managementOption (when the old version is already on the VM)
sed -i 's|^managementOption=NONE|managementOption=DEFAULT|' /home/oracle/db.rsp
```

**Lesson:** The DB and Grid schemas in 23.0.0 are **different**, despite the shared 23.0.0 version. Don't assume that a valid value in the grid schema (e.g. `managementOption=NONE`) is valid in the db schema. When the parser screams `cvc-enumeration-valid`, the list of allowed values is in the message `'[VALUE1, VALUE2, ...]'`.

---

### FIX-026 — `db.rsp`: inline comments after the value are NOT supported (`OSDBA=dba    # SYSDBA` → FATAL)

**Problem:** In the commented version of `db.rsp` v2.0 (FIX-025), **inline comments** were unwittingly placed after OS group values:
```
OSDBA=dba                # SYSDBA
OSOPER=oper              # SYSOPER
...
```
The response file parser treats **everything after `=`** (including whitespace and `#`) as the parameter value — so `OSDBA=dba                # SYSDBA` means "the oracle user must be in a group named `dba                # SYSDBA`", which of course doesn't exist.

**Symptom:**
```
[FATAL] [INS-35341] The installation user is not a member of the following groups:
[dba                # SYSDBA, backupdba    # SYSBACKUP (RMAN), dgdba            # SYSDG (Data Guard), ...]
```

**Rule:** Comments in Oracle response files must be on **separate lines** starting with `#` in column 1. You CANNOT do inline `KEY=VALUE # comment`.

**Exception:** `#` in **a value without whitespace** (e.g. `sysasmPassword=Welcome1#ASM`) is OK — that's part of the string, not a comment.

**Fix:** `response_files/db.rsp` — comments moved BEFORE the group definitions, the line itself contains only `KEY=VALUE`.

**Fix for running VMs (on prim01 as oracle):**
```bash
# Variant A - copy clean db_minimal.rsp from the shared folder
cp /mnt/oracle_binaries/db_minimal.rsp /home/oracle/db.rsp
chmod 600 /home/oracle/db.rsp

# Variant B - hot-fix sed (removes inline #-comments from OS groups)
sed -i -E 's/^(OS[A-Z]*=[a-z]+)[[:space:]]+#.*$/\1/' /home/oracle/db.rsp
grep "^OS" /home/oracle/db.rsp
# Should: OSDBA=dba | OSOPER=oper | ... with nothing after the value
```

**Note when writing new response files:** Oracle rsp parsers (gridSetup, runInstaller, dbca) **don't trim whitespace** or **truncate at `#`**. The entire tail after `=` is the value. A comment goes only on a separate line.

---

### FIX-026b — Mass cleanup: `/media/sf_OracleBinaries/` → `/mnt/oracle_binaries/` + ZIP names with space → `_`

**Problem:** The kickstarts mount the VirtualBox shared folder as `/mnt/oracle_binaries` (with `fmode=664,uid=oracle`), but **9 files in the project** (MD + `.sh` scripts) had references to `/media/sf_OracleBinaries/` (the default Guest Additions auto-mount path, which we don't use). Additionally, the ZIP file name on eDelivery is `V1054592-...forLinux x86-64.zip` with **a space**, but after downloading/copying to the shared folder it was renamed with `_` (underscore) — all occurrences in MD + scripts had a space, so the `unzip` commands from the documentation did NOT work without modification.

**Files fixed (mass replace):**
- MD: `02_virtualbox_setup.md`, `06_grid_infrastructure_install.md`, `07_database_software_install.md`, `11_fsfo_observer.md`, `13_client_ucp_test.md`, `README.md`, `LOG.md`, `PLAN-dzialania.md`
- Scripts: `scripts/install_db_silent.sh`, `scripts/install_grid_silent.sh`

**Rule:**
- VirtualBox shared folder host `D:\OracleBinaries` → mount point in VM: **`/mnt/oracle_binaries`** (consistent with the fstab in the kickstarts)
- ZIP file names: **with `_`** (`forLinux_x86-64.zip`), not with a space

**Lesson:** always check the actual mount point (`mount | grep oracle` or `/etc/fstab`) and the actual file name (`ls /mnt/oracle_binaries/`) before trusting the documentation.

---

### FIX-027 — `db_si.rsp`: `OSRACDBA=` (empty) FATAL even in Single Instance install + install_db_silent.sh script unaware of the mode

**Problem (1/2):** In the Oracle 26ai schema `rspfmt_dbinstall_response_schema_v23.0.0` the parameter `OSRACDBA` is **required regardless of mode** (RAC vs SI). For the Single Instance install on stby01 we set `OSRACDBA=` (empty — functionally unused since there's no RAC), but the validating parser did not accept that.

**Symptom:**
```
[FATAL] [INS-35344] The value is not specified for Real Application Cluster
administrative (OSRACDBA) group.
   ACTION: Specify a valid group name for Real Application Cluster
           administrative (OSRACDBA) group.
```

**Fix:** `response_files/db_si.rsp` (and `db_si_minimal.rsp`)
```diff
- OSRACDBA=
+ OSRACDBA=dba
```
The choice of `dba`: safe (the group exists on every Oracle host), the oracle user doesn't have to be formally a member of `racdba` on stby01 (no RAC), the parser only needs an **existing** group to pass validation. Functionally unused.

**Fix for running VMs (on stby01 as oracle):**
```bash
sed -i 's|^OSRACDBA=$|OSRACDBA=dba|' /home/oracle/db_si.rsp
grep "^OSRACDBA" /home/oracle/db_si.rsp
```

**Problem (2/2):** The `install_db_silent.sh` v2.0 script assumed RAC mode in messages ("copying to prim02 via SSH...", "root.sh sequentially on both nodes..."). For an SI install on stby01, these messages were misleading.

**Fix:** `scripts/install_db_silent.sh` — added mode detection based on `clusterNodes=` in the response file:
- `clusterNodes=prim01,prim02` → RAC mode, ETA 25-40 min, instructions for root.sh sequentially
- `clusterNodes=` (empty) → SI mode, ETA 15-25 min, one root.sh locally

**Lesson:** Schema 23.0.0 formally requires all OS group parameters, even when logically unused in the given mode. If the validator complains `INS-35344` about a group "it shouldn't need" — fill in any existing group (`dba`/`oinstall`), it doesn't affect functionality.

---

## 2026-04-25 (cont.) — DBCA primary

### FIX-028 — `dbca_prim.rsp`: 8 illegal keys schema 23.0.0 + missing archivelog conversion

**Problem:** The `dbca_prim.rsp` v1.0 file contained keys that **do not exist** in the template `$ORACLE_HOME/assistants/dbca/dbca.rsp` for 26ai (schema `rspfmt_dbca_response_schema_v23.0.0`). Analogous to FIX-024 (grid.rsp) and FIX-025 (db.rsp) — leftovers from 19c.

**Diff template 26ai vs our v1.0 — 8 illegal keys:**

| Key in v1.0 | Status in schema 23.0.0 | Repair in v2.0 |
|---|---|---|
| `createUserTableSpace=true` | ❌ doesn't exist | removed |
| `asmSysPassword=Welcome1#ASM` | ❌ template has `asmsnmpPassword` | `asmsnmpPassword=Welcome1#ASMSNMP` |
| `recoveryAreaSize=15360` | ❌ doesn't exist | moved into `initParams=...,db_recovery_file_dest_size=15G` |
| `useSameAdminPassword=true` | ❌ doesn't exist | removed (sysPassword + systemPassword sufficient) |
| `memoryMgmtType=AUTO_SGA` | ❌ doesn't exist | removed (template has only `totalMemory` + `automaticMemoryManagement`) |
| `enableArchive=true` | ❌ doesn't exist | removed → archivelog conversion in `create_primary.sh` post-create |
| `archiveLogMode=true` | ❌ doesn't exist | same |
| `archiveLogDest=+RECO` | ❌ doesn't exist | same (archivelog goes to FRA = `+RECO`) |
| `emExpressPort=` | ❌ template has `emConfiguration` | `emConfiguration=NONE` |

**Missing in v1.0 (new in 26ai schema 23.0.0), added in v2.0:**
- `useLocalUndoForPDBs=true` (recommended for CDB in 23ai+)
- `policyManaged=false` (admin-managed RAC)
- `runCVUChecks=FALSE`
- full set of empty keys from the template (DV, OLS, dirService, EM Cloud Control, oracleHomeUserPassword, ...)

**Fix 1 — `response_files/dbca_prim.rsp` v2.0:** full rewrite based on `$ORACLE_HOME/assistants/dbca/dbca.rsp` from 26ai. Sensible values from v1.0 retained (gdbName, sid, RAC, ASM disk groups, passwords, characterSet, totalMemory, sampleSchema=false, initParams).

**Fix 2 — `scripts/create_primary.sh` v2.0:**
- Pre-flight checks: whoami=oracle, ORACLE_HOME, dbca, RSP exists.
- **Auto-detection of 8 deprecated keys** in the response file (analogous to `install_db_silent.sh` FIX-027).
- Idempotent: `srvctl status database -db PRIM` → skip DBCA if the DB is already there.
- **Post-create archivelog conversion** — because `templateName=General_Purpose.dbc` creates the DB in `NOARCHIVELOG`. In RAC the sequence: `srvctl stop database -db PRIM` → `STARTUP MOUNT` on PRIM1 (`cluster_database=true` in 23ai+ alone allows mount on 1 instance) → `ALTER DATABASE ARCHIVELOG` → `SHUTDOWN IMMEDIATE` → `srvctl start database -db PRIM`.
- Idempotent `ALTER DATABASE ADD STANDBY LOGFILE` (`WHENEVER SQLERROR CONTINUE` because of ORA-01515 on a re-run).
- Full post-create in one pass: FORCE_LOGGING (CDB+APPPDB), Flashback, SRL (8 = 4×2 thread), `log_archive_config`, `log_archive_dest_1=USE_DB_RECOVERY_FILE_DEST`, `standby_file_management=AUTO`, `app_user`/`test_log` in APPPDB, `utlrp.sql`, export `orapwPRIM` from ASM to `/tmp/pwd/`.

**Expected symptom for v1.0 (if run):**
```
[FATAL] [DBT-XXXXX] Invalid response file parameter: createUserTableSpace
```
or
```
[FATAL] [DBT-XXXXX] Invalid value for parameter recoveryAreaSize
```

**Fix for running VMs:**
```bash
# On prim01 as oracle:
cp /tmp/response_files/dbca_prim.rsp /home/oracle/dbca_prim.rsp
chmod 600 /home/oracle/dbca_prim.rsp
bash /tmp/scripts/create_primary.sh
```

**Lesson:** For every response file in 26ai (`grid.rsp`, `db.rsp`, `db_si.rsp`, **`dbca_prim.rsp`**, in the future `client.rsp`) **first compare keys against the installer template** (`$ORACLE_HOME/.../assistants/.../*.rsp` or `$ORACLE_HOME/install/response/*.rsp`) before running it. Schema 23.0.0 rejects every unknown key with `[FATAL] [DBT-/INS-]`. For DBCA in particular: `enableArchive` (known from 19c) **does not exist** in schema 23.0.0 — archivelog is set up manually in post-create RAC stop/mount/alter/restart.

---

### FIX-029 — `dbca_prim.rsp`: `db_recovery_file_dest_size=15G` exceeds free space on +RECO

**Problem:** The `+RECO` disk group in our lab has 15 GB EXTERN, but ASM reserves ~140 MB for metadata (header, ACD, COD, freespace). Free space for the database = 15220 MB. With `db_recovery_file_dest_size=15G` (15360 MB), DBCA checks `free_mb >= dest_size` and aborts.

**Symptom:**
```
[FATAL] [DBT-06604] The location specified for 'Fast Recovery Area Location' has insufficient free space.
   CAUSE: Only (15,220MB) free space is available on the location (+RECO/PRIM/).
   ACTION: Choose a 'Fast Recovery Area Location' that has enough space (minimum of (15,360MB)) or free up space on the specified location.
```

**Fix:** `response_files/dbca_prim.rsp` — `db_recovery_file_dest_size=15G` → `14G` (14336 MB; ~880 MB reserve under metadata + safety buffer). For a lab with 15 GB +RECO this is enough: archivelogs after SYNC redo transport + flashback logs + 1 RMAN backup set will fit in 14 GB within a single FSFO test cycle.

**For a larger lab / production:** increase the +RECO disk group to 25-50 GB in `05_shared_storage_iscsi.md` (additional LUN) and set `db_recovery_file_dest_size` to 20-40 GB.

**Fix for an in-progress run (on prim01 as oracle, after DBT-06604):**
```bash
sed -i 's|db_recovery_file_dest_size=15G|db_recovery_file_dest_size=14G|' /home/oracle/dbca_prim.rsp
grep db_recovery_file_dest_size /home/oracle/dbca_prim.rsp
bash /tmp/scripts/create_primary.sh   # restart - DBCA detects no DB and starts from the beginning
```

**Lesson:** Check **actual** `FREE_MB` from `asmcmd lsdg` before setting `db_recovery_file_dest_size` — ASM reserves ~1% or a minimum of a few dozen MB for metadata, so the parameter value should always be < `FREE_MB`, not `TOTAL_MB`.

---

### FIX-030 — `dbca_prim.rsp`: `General_Purpose.dbc` → `New_Database.dbt` (ORA-00201 controlfile version mismatch)

**Problem:** The image-based install of Oracle Database 26ai 23.26.1 contains in `$ORACLE_HOME/assistants/dbca/templates/`:
- `General_Purpose.dbc` (pre-built CDB, uses `Seed_Database.ctl` + `Seed_Database.dfb1..7`)
- `Data_Warehouse.dbc` (pre-built, ditto)
- `New_Database.dbt` (definition — DBCA executes CREATE DATABASE from scratch)

`Seed_Database.ctl` is in version **23.6.0.0.0**, but the RDBMS library after OPatch RU 23.26.1 reports the baseline as **23.4.0.0.0** (`opatch lsinventory`: "Oracle Database 26ai 23.0.0.0.0" + RU 38743669/38743688 from 2026-01-18). Version inconsistency within the same image — Oracle probably didn't update `Seed_Database.ctl` when building image 23.26.1.

**Symptom (DBCA `templateName=General_Purpose.dbc`):**
```
[WARNING] ORA-00201: control file version 23.6.0.0.0 incompatible with ORACLE version 23.4.0.0.0
ORA-00202: control file: '.../tempControl.ctl'

[WARNING] ORA-01507: database not mounted

[FATAL] ORA-01503: CREATE CONTROLFILE failed
ORA-01565: Error identifying file +DATA/PRIM/sysaux01.dbf.
ORA-15001: disk group "DATA" does not exist or is not mounted
```

ORA-15001 is a **cascade** from ORA-00201 — the instance didn't mount, so it has no connection to ASM. The DATA disk group is mounted in ASM (confirmed via `asmcmd lsdg`), there's no problem with ASM itself.

**Fix:** `response_files/dbca_prim.rsp` v2.1 — `templateName=General_Purpose.dbc` → `New_Database.dbt`. The `.dbt` (definition) file makes DBCA generate the SQL `CREATE DATABASE ...` from scratch without using `Seed_Database.ctl`. Creation of all datafiles via `CREATE TABLESPACE` from inside the instance in OPEN mode (not from pre-built backup files).

**Side effects:**
- DBCA time: ~30-50 min (CREATE from scratch) instead of ~20-40 min (pre-built copy). For the lab the difference is small.
- More I/O during create (ASM writes all SYSTEM/SYSAUX/UNDO/USERS blocks) — in our lab with LIO iSCSI on local SSD no problem.
- Functionally identical result: CDB + PDB APPPDB + standard schemas (PDB$SEED, SYS, SYSTEM).

**Cleanup before retry (important):**

```bash
# As grid on prim01 (ASM admin)
asmcmd <<'EOF'
ls +DATA/PRIM
rm -rf +DATA/PRIM
ls +RECO/PRIM 2>/dev/null
rm -rf +RECO/PRIM
EOF
```

After a failed DBCA with ORA-00201 there's `+DATA/PRIM/PASSWORD/` left (the password file created early in the flow). Need to remove — DBCA on retry doesn't overwrite existing files, fail.

**Fix for running VMs:**

```bash
# Step 1: ASM cleanup (as grid on prim01)
sudo su - grid -c "asmcmd rm -rf +DATA/PRIM; asmcmd rm -rf +RECO/PRIM 2>/dev/null"

# Step 2: update response file (as oracle on prim01)
sed -i 's|^templateName=General_Purpose.dbc|templateName=New_Database.dbt|' /home/oracle/dbca_prim.rsp
grep templateName /home/oracle/dbca_prim.rsp
# should: templateName=New_Database.dbt

# Step 3: retry
bash /tmp/scripts/create_primary.sh
```

**Lesson:** The Oracle 23ai/26ai image-based install can have **inconsistent versions** of files within the same ZIP (RDBMS baseline vs assistants templates). `New_Database.dbt` is **a safe default choice** for DBCA labs — about 50% slower but bypasses all seed controlfile / pre-built datafile pitfalls. `General_Purpose.dbc` is worth using only when version consistency of `Seed_Database.ctl` with RDBMS has been confirmed (e.g. `strings $ORACLE_HOME/assistants/dbca/templates/Seed_Database.ctl | grep -i "version"` before the first DBCA).

---

### FIX-031 — `oracle` user in 23ai/26ai Flex ASM Direct Storage Access requires the `asmadmin` group

**Problem:** In our kickstart and `prepare_host.sh` v1.0 the `oracle` user was added only to `asmdba` + `asmoper` (as in standard 19c without Flex ASM):

```
oracle: oinstall, dba, oper, backupdba, dgdba, kmdba, racdba, asmdba, asmoper
                                                              ^^^^^^^ ^^^^^^
                                              missing: asmadmin (54327)!
```

In Oracle 23ai/26ai the default `cluster_database_mode=flex` + `Flex ASM Direct Storage Access` (`asmcmd showclustermode` → `Flex mode enabled - Direct Storage Access`) the DB client **directly does I/O on the block devices** representing ASM disks. Standard udev rules (from `setup_iscsi_initiator_prim.sh`/`fix_udev_asm_rules.sh`) create:

```
KERNEL=="sd*", ENV{ID_SERIAL}=="...", SYMLINK+="oracleasm/DATA1",
    OWNER="grid", GROUP="asmadmin", MODE="0660"
```

`MODE=0660` = owner+group rw, others nothing. `oracle` not in `asmadmin` → **Permission denied** on `/dev/oracleasm/DATA1` → DBCA CREATE DATABASE throws ORA-15001.

**Symptom (DBCA `templateName=New_Database.dbt`):**
```
[FATAL] ORA-01501: CREATE DATABASE failed
ORA-00200: control file could not be created
ORA-00202: control file: '+DATA'
ORA-17502: (4)Failed to create file +DATA
ORA-15001: disk group "DATA" does not exist or is not mounted
ORA-59069: Oracle ASM file operation failed.
```

From the ASM perspective (`asmcmd lsdg` as `grid`) the disk groups are MOUNTED. From the `oracle` user's perspective, `dd if=/dev/oracleasm/DATA1 of=/dev/null` → `Permission denied` — direct confirmation of the root cause.

**Diagnostics (saved into the sanity check script):**
```bash
# As grid:
ls -la /dev/oracleasm/                          # symlinks owned by root
cat /etc/udev/rules.d/99*.rules | grep -E "GROUP|MODE"   # GROUP="asmadmin" MODE="0660"
groups oracle                                   # does it contain 'asmadmin'?
# As oracle:
dd if=/dev/oracleasm/DATA1 of=/dev/null bs=4096 count=1   # OK or Permission denied
```

**Fix:**

1. **`scripts/prepare_host.sh` v1.1** — `usermod -a -G asmadmin,asmdba,asmoper oracle` (added `asmadmin`).

2. **`kickstart/ks-prim01.cfg` + `ks-prim02.cfg`**:
   ```bash
   useradd -u 54322 -g oinstall \
       -G dba,oper,backupdba,dgdba,kmdba,racdba,asmadmin,asmdba,asmoper \
       -m -s /bin/bash -c "Oracle Database" oracle
   ```

3. **`04_os_preparation.md`** — section "Check after kickstart" + section 2.1 (manual installation) — `oracle` must have `asmadmin` as a secondary group.

4. **`stby01` does NOT require the change** — single instance without ASM (local XFS for datafiles).

**Fix for running VMs:**

```bash
# On prim01 and prim02 as root
sudo usermod -aG asmadmin oracle

# WARNING: after `usermod -aG asmadmin oracle` MANUALLY on a running cluster
# (instead of via kickstart before Grid Install) it's recommended to RESTART CRS on
# the given node. Reason: oraagent.bin/orarootagent.bin sometimes holds stale
# ASM IPC state, and a forked DB instance may get a stale view of ASM disk
# groups (ORA-15001 even though 'id oracle' and '/proc/<pid>/status' show 54327
# correctly). Empirically: restarting 'crsctl stop/start crs' on the given node
# fixes the 'stuck' ASM IPC state after a groups change in oracle. Safe procedure,
# won't hurt.

# Restart CRS on the node where you changed groups (best on both):
sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
sleep 10
sudo /u01/app/23.26/grid/bin/crsctl start crs
# Wait ~3-5 min for full bring-up

# Verification that oraagent has asmadmin (54327) in the groupset:
cat /proc/$(pgrep -f oraagent.bin | head -1)/status | grep ^Groups:

# Re-login oracle (groups loaded at login)
exit  # from the current oracle session
sudo su - oracle
groups | grep asmadmin   # verification

# Test direct access to block device
dd if=/dev/oracleasm/DATA1 of=/dev/null bs=4096 count=1
# should: "1+0 records in/out"

# Cleanup of leftovers from the failed DBCA (as grid)
sudo su - grid -c 'asmcmd rm -rf +DATA/PRIM 2>/dev/null'

# Retry DBCA (as oracle)
bash /tmp/scripts/create_primary.sh
```

**Lesson:** The Oracle Role Separation convention from 19c (`oracle` in `asmdba`+`asmoper`, `asmadmin` only for `grid`) **changed** in 23ai/26ai with Flex ASM Direct Storage Access. For **a DB client in Direct Storage Access mode**, `asmadmin` (or at minimum udev `MODE=0664`) is required. Alternative: change the ASM cluster mode to **ASM Proxy** (the client connects to ASM over the network through the ASMNET listener) instead of Direct Storage Access — but it requires a separate setup and is slower. For the lab it's simpler to add `oracle` to `asmadmin`.

---

### FIX-032 — `iscsi.service` race condition with the network at boot → CRS doesn't come up after (auto-)reboot

**Problem:** The systemd unit `iscsi.service` (which logs into the iSCSI target at boot) starts **before** full initialization of the 192.168.200.0/24 network. On a fast boot (or after a kernel panic auto-reboot) the `enp0s9` interface (storage network) doesn't yet have an IP/route when `iscsiadm -m node --loginall=automatic` tries to connect to `192.168.200.10:3260`.

```
14:24:23 systemd: Starting Login and scanning of iSCSI devices...
14:24:23 iscsid: cannot make connection to 192.168.200.10:3260 (-1,101)   ← errno 101 = Network unreachable
14:27:26 iscsid: Giving up after 120 seconds                              ← timeout, storage network not ready
14:27:26 systemd: iscsi.service exited (code=8)                           ← FAIL, no retry
```

Effect: `/dev/oracleasm/OCR{1,2,3}`, `DATA1`, `RECO1` don't exist after boot. CSSD can't read voting disks from `+OCR` → CRS hangs on `RESOURCE_START[ora.cssd 1 1]`. The cluster as a whole lives (the second node has sessions), but prim01 is "out".

**Context — what triggered the reboot:** during DBCA on 26ai (`New_Database.dbt`, ~50% progress, Oracle Text + OLAP stage), intensive synchronous I/O to ASM via VirtualBox iSCSI caused massive **time drift** (`Time drifted forward by 7823240 µs` = 7.8 s in one tick, `hrtimer: interrupt took 643132 ns`). The Linux kernel watchdog deemed the system hung and triggered panic + auto-reboot. After the reboot, iSCSI didn't log in → CRS didn't come up → DBCA had no way to continue.

**Diagnostics:**
```bash
systemctl status iscsi iscsid
iscsiadm -m session              # "No active sessions" = confirms
ls -la /dev/oracleasm/           # empty (apart from .., .)
journalctl -u iscsi.service --no-pager
```

**Hot-fix for the current state (after crash + reboot):**
```bash
# As root
ping -c 2 192.168.200.10                                 # confirm storage network UP
iscsiadm -m discovery -t st -p 192.168.200.10
iscsiadm -m node --loginall=automatic
sleep 5
iscsiadm -m session                                       # should show sessions
ls -la /dev/oracleasm/                                    # OCR1..3, DATA1, RECO1

# CRS comes up by itself after ~30-60s (CSSD sees voting disks)
sleep 60
sudo su - grid -c '. ~/.bash_profile; crsctl check cluster -all'

# If CRS is still down - force restart stack
sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
sleep 10
sudo /u01/app/23.26/grid/bin/crsctl start crs
```

**Permanent fix:** `scripts/setup_iscsi_initiator_prim.sh` v1.1 — creates a systemd override `/etc/systemd/system/iscsi.service.d/00-wait-network.conf`:

```ini
[Unit]
After=network-online.target NetworkManager-wait-online.service
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=300
StartLimitBurst=10
```

Effects:
- `After=network-online.target` — iscsi.service won't start until NetworkManager reports "online" (all interfaces with IP).
- `Restart=on-failure` + `RestartSec=15` — if the first login fails (e.g. target still starting on infra01), retry every 15s, up to 10× in 5 min.

Plus: `systemctl enable NetworkManager-wait-online` ensures that `network-online.target` is actually reached (on OL 8.10 this unit is disabled by default).

**For running VMs (prim01, prim02) — apply override without re-running the whole script:**
```bash
sudo mkdir -p /etc/systemd/system/iscsi.service.d
sudo tee /etc/systemd/system/iscsi.service.d/00-wait-network.conf > /dev/null <<'EOF'
[Unit]
After=network-online.target NetworkManager-wait-online.service
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=300
StartLimitBurst=10
EOF
sudo systemctl daemon-reload
sudo systemctl enable NetworkManager-wait-online
```

**Additionally — FIX-033 (sysctl tolerance) recommended together:** so the next VirtualBox time drift doesn't trigger panic + reboot:
```bash
sudo tee /etc/sysctl.d/99-vm-tolerance.conf > /dev/null <<'EOF'
kernel.softlockup_panic = 0
kernel.hung_task_panic = 0
kernel.unknown_nmi_panic = 0
kernel.watchdog_thresh = 30
EOF
sudo sysctl --system
```

**Lesson:** The default `iscsi.service` in OL 8.x is a **fire-and-forget oneshot** — one Try, no retry, no wait for the network. For iSCSI-on-internal-VirtualBox-network this is too little. Every iSCSI ASM lab **must** have an override with `After=network-online.target` + `Restart=on-failure`, otherwise every reboot is a roulette of whether CRS comes up.

---

### FIX-033 — VirtualBox VM kernel panic with time drift during DBCA → auto-reboot

**Problem:** During DBCA `New_Database.dbt` (Oracle Text + OLAP, ~50% progress), intensive synchronous I/O to ASM via VirtualBox iSCSI caused enormous time drift in the guest OS. The Linux kernel (5.15) has a watchdog which after `softlockup_thresh` (default 20s) without CPU progress panics. Time drift > 5s in one tick = false-positive softlockup.

**Symptom in primary instance alert log + dmesg:**
```
Time drifted forward by (7823240) micro seconds at 24660716215 whereas allowed drift is 1000000
hrtimer: interrupt took 643132 ns
[then no further entries]
[VM auto-reboot]
```

`last reboot` shows a fresh boot. The crash triggered a cascade: VM reboot → iSCSI fail (FIX-032) → CRS down → DBCA died irrevocably (orphan `ora.prim.db` in CRS).

**Fix:** `/etc/sysctl.d/99-vm-tolerance.conf` — disable panic on softlockup (the VM kernel should be **TOLERANT** of time skew, not aggressively reset):

```
kernel.softlockup_panic = 0       # default: 0 — explicit for safety
kernel.hung_task_panic = 0        # default: 0 — same
kernel.unknown_nmi_panic = 0      # default: 0 — same
kernel.watchdog_thresh = 30       # default: 10 — extending from 10 to 30 sec
```

`watchdog_thresh=30` gives 30 seconds of tolerance before the kernel deems a CPU "stuck". For a VirtualBox VM where the host occasionally freezes the guest for 5-10s during intensive I/O, that's enough to survive.

**For running VMs (prim01 + prim02):**
```bash
sudo tee /etc/sysctl.d/99-vm-tolerance.conf > /dev/null <<'EOF'
kernel.softlockup_panic = 0
kernel.hung_task_panic = 0
kernel.unknown_nmi_panic = 0
kernel.watchdog_thresh = 30
EOF
sudo sysctl --system
```

**Additional considerations (NOT necessary, only optional optimization):**

1. **Paravirt clock in VirtualBox** (from the host with VM stopped):
   ```powershell
   & $VBox modifyvm prim01 --paravirtprovider kvm
   & $VBox modifyvm prim02 --paravirtprovider kvm
   ```
   `kvm` (or `hyperv` on Windows host) gives the guest OS direct access to the host TSC — drastically reduces time drift.

2. **Tickless kernel + chrony aggressive sync** (on the guest):
   ```bash
   sudo grubby --update-kernel=ALL --args="nohz=off"   # optional
   # In /etc/chrony.conf: makestep 1.0 -1   # always step instead of slew
   sudo systemctl restart chronyd
   ```

**Context why it didn't work earlier (despite early chrony setup):** chrony does *slew* (slow correction of clock frequency) instead of *step* (jumping to the right time). With time drift of 7s in one tick, slew can't keep up — the kernel watchdog reacts faster than chrony.

**Lesson:** A VM Linux with default sysctl is **panic-happy** for intensive I/O scenarios (DBCA, RMAN backup, RDBMS startup). For labs on VirtualBox/VMware with nominal CPU but intensive storage, it's safer to set `softlockup_panic=0` + `watchdog_thresh=30` right after OS install — this doesn't reduce reliability, just gives the kernel more patience.

**Plus:** updated `scripts/create_primary.sh` v2.1:
- Idempotency check: checks `srvctl status database -db PRIM | grep "is running"` (not just whether a resource is registered), so an OFFLINE orphan from a previous crash is **not** treated as "DB already exists"
- Auto-recovery: if it detects an orphan PRIM (registered but OFFLINE), tries `srvctl remove database -db PRIM -force -noprompt` before starting the full DBCA
- Better parsing of `sqlplus log_mode` output (without `tr -d ' \n'` which lumped ORA-01034 into one string) — uses `grep -oE 'ARCHIVELOG|NOARCHIVELOG'` with explicit error when the instance is down

---

### FIX-035 — `create_primary.sh`: utlrp.sql Error 45 / asmcmd hang post-create

**Problem 1 — utlrp.sql exit code despite success:**

After `sqlplus / as sysdba @?/rdbms/admin/utlrp.sql` the utlrp script **finishes successfully** (`UTLRP_END timestamp = ...`, `OBJECTS WITH ERRORS = 0`), but then at the end sqlplus prints:
```
Error 45 initializing SQL*Plus
Internal error
```
and returns a **non-zero exit code**. `set -e` in the wrapper script kills the rest of the flow before exporting the pwfile. Effect: the script dies on `[hh:mm:ss] Recompile invalid objects (utlrp.sql)...` as the last line in `/tmp/dbca3.out`, even though utlrp ran OK.

The cause of `Error 45` is unclear — probably sqlplus 23ai post-utlrp drops a TEMPORARY function (part of utlrp cleanup) and returns an err code when closing the session.

**Problem 2 — `asmcmd pwcopy` hang from DB home:**

`asmcmd` as user `oracle` with the variables `ORACLE_HOME=$DB_HOME` + `ORACLE_SID=PRIM1` can **hang without timeout** during `pwcopy` (or other operations requiring connect to the ASM instance). The correct way: as user `grid` with `ORACLE_HOME=$GRID_HOME` + `ORACLE_SID=+ASM1` — then asmcmd direct-connects to the local ASM instance.

**Symptom:** the script hung on the line `asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f` for >5 min with no exit.

**Fix `scripts/create_primary.sh` v2.2:**

```bash
# 1. utlrp with '|| true' + validation via log file
sqlplus / as sysdba @?/rdbms/admin/utlrp.sql > /tmp/utlrp_prim.log 2>&1 || true
ERRORS_FOUND=$(grep -A1 "^OBJECTS WITH ERRORS" /tmp/utlrp_prim.log | tail -1 | tr -d ' ')
if [[ -n "$ERRORS_FOUND" && "$ERRORS_FOUND" != "0" ]]; then
    warn "utlrp detected $ERRORS_FOUND invalid objects"
fi

# 2. asmcmd via sudo grid (with fallback timeout 30s on asmcmd as oracle)
if sudo -n -u grid bash -c '. ~/.bash_profile && asmcmd pwcopy '"$PWFILE"' /tmp/pwd/orapwPRIM -f' 2>/dev/null; then
    sudo chown oracle:oinstall /tmp/pwd/orapwPRIM
    log "Password file copied via grid"
else
    timeout 30 asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f || \
        warn "Manually: sudo su - grid -c 'asmcmd pwcopy $PWFILE /tmp/pwd/orapwPRIM -f'"
fi
```

**Hot-fix for the current situation** (utlrp DONE, but the script died with Error 45):

```bash
# 1. Kill any leftover nohup process
ps -ef | grep create_primary | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null

# 2. Manually export pwfile as grid
sudo su - grid <<'EOF'
. ~/.bash_profile
PWFILE=$(asmcmd pwget --dbuniquename PRIM)
mkdir -p /tmp/pwd
asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f
ls -la /tmp/pwd/orapwPRIM
EOF
sudo chown oracle:oinstall /tmp/pwd/orapwPRIM
sudo chmod 640 /tmp/pwd/orapwPRIM
```

**Lesson:**
- **Teach `set -e`-friendly tolerance** for tools with known false-positive errors (sqlplus exit 45, some known buggy scenarios).
- **`asmcmd` always via grid user** — that's its "native" home. Calling from DB home works **sometimes** but hangs in unpredictable moments.
- **Wrap every `asmcmd` in long-running scripts with `timeout` or run as grid** — eliminates a whole class of intermittent hangs.

**Addendum 2026-04-26 — `asmcmd pwcopy` flags in 23ai:**

In 19c, `asmcmd pwcopy` accepted `--force`, in 23ai it accepts **only `-f`** (short form). Trying to use `--force` returns:
```
ASMCMD-9412: Invalid option: force
usage: pwcopy [ --dbuniquename <string> | --asm ][-f][--local]
        <source_path> <destination_path>
```

Updated in 5 files (12 occurrences): `08_database_create_primary.md`, `09_standby_duplicate.md`, `FIXES_LOG.md`, `SESSION_STATE.md`, `scripts/create_primary.sh`. Everywhere `--force` → `-f`.

---

## 2026-04-26

### FIX-036 — Storage tuning applied by default in the install pipeline

**Context:** After the 25.04 session, 5 storage optimizations were identified that give a **5–10× speedup** for random write (DBCA, RMAN, archivelog) and that are **safe for the lab**. Earlier they existed only as post-install runtime tune in `scripts/alt/tune_storage_runtime.sh` — they required conscious invocation after installation. Now they are built into the install-time scripts.

**Optimizations (5 of them):**

| # | Optimization | Safe? | Where applied |
|---|--------------|-------|---------------|
| 1 | VBox `--hostiocache on` on SATA infra01 | Only for infra01 (NOT prim/stby/client) | `vbox_create_vms.ps1` + `vbox_create_vms_block.ps1` |
| 2 | XFS opts: `noatime,nodiratime,largeio,inode64,logbufs=8,logbsize=256k` | Pure win | `setup_iscsi_target_infra01.sh` (fstab) |
| 3 | LIO `emulate_write_cache=1` on DATA/RECO LUNs (NOT OCR!) | Lab OK; OCR sync for CSSD voting | `setup_iscsi_target_infra01.sh` + `setup_iscsi_target_block.sh` |
| 4 | iSCSI initiator: `replacement_timeout=15`, `noop_out_*=5/10`, `queue_depth=64` | Pure win | `setup_iscsi_initiator_prim.sh` (iscsid.conf) |
| 5 | `mq-deadline` scheduler on `/dev/sdb` + udev rule | Pure win for concurrent writers | `setup_iscsi_target_infra01.sh` + `setup_iscsi_target_block.sh` |

**Critical rules that must be maintained:**
- **`hostiocache=on` ONLY on infra01.** On prim01/02/stby01 = datafiles corruption on host crash. The scripts have explicit `--hostiocache off` for the other VMs.
- **OCR LUNs without `emulate_write_cache`.** Voting disks require sync semantics for CSSD.
- **iscsid.conf modified BEFORE `iscsiadm --discovery`** — discovery saves a per-node config from the current default. Modifying after `--discovery` requires `iscsiadm -m node --op update` (complicated).

**Expected effect for a user rebuilding the lab from scratch:**

| Operation | Before (default fileio) | After FIX-036 (default fileio + tune) | After variant 17 |
|-----------|-------------------------|----------------------------------------|------------------|
| DBCA `New_Database.dbt` | 50–90 min | **20–40 min** | 30–50 min |
| RMAN duplicate (4 GB DB) | 15–25 min | **5–12 min** | 8–15 min |
| Random write IOPS | 5–8k | **15–25k** | 20–35k |
| CRS recovery after iSCSI fail | 120 s (default replacement_timeout) | **15 s** | 15 s |

**Risk profile:**
- In case of **BSOD/power loss of the Windows host**: writes lost from page cache → corruption of `/var/storage/*.img` → re-create LUNs + RMAN restore (~30 min). **Acceptable in the lab.**
- For PROD: **DO NOT ENABLE** `hostiocache=on`, **DO NOT ENABLE** `emulate_write_cache` on DATA. A real SAN/NetApp has battery-backed cache — that's a different class of solution.

**Lesson:**
- **Runtime tuning lessons should migrate to install-time** when they are safe in the given context. Leaving them only as "advanced post-tune" means 90% of users won't trigger them.
- **Explicitly mark `hostiocache=off` for VMs with database datafiles.** Relying only on the default risks someone later modifying the script and turning it on globally.
- **OCR ALWAYS sync.** Cluster voting disks **must** have a consistent state on crash — that's the heart of the cluster (split-brain prevention).

---

### FIX-037 — HugePages 2MB in pipeline default (for both variants)

**Context:** In variant B (`prepare_host_block.sh`) HugePages 768×2MB were there from the start, in variant A there were none at all. This caused the SGA (~1.5 GB) to be scattered across ~392k 4K pages → frequent TLB misses, ~10–15% performance loss for the database. The optimization is **safe and effective in both variants** — doesn't depend on storage backend.

**Decision:** Migrate HugePages config from the wrapper `prepare_host_block.sh` into the main `prepare_host.sh` as the default for `--role=rac` and `--role=si`. The wrapper remains as a thin shim for compatibility (new installations don't need it).

**Fix `scripts/prepare_host.sh` v1.3 (section 7c):**

```bash
if [[ "$ROLE" == "rac" || "$ROLE" == "si" ]]; then
    HUGEPAGES_NUM="${HUGEPAGES_NUM:-768}"  # 768 * 2 MB = 1536 MB will cover SGA_TARGET
    cat > /etc/sysctl.d/99-hugepages.conf <<EOF
vm.nr_hugepages = $HUGEPAGES_NUM
EOF
    # memlock unlimited for oracle + grid (needed so processes can pin HugePages)
    if ! grep -q "memlock.*unlimited" /etc/security/limits.d/99-grid-oracle.conf; then
        cat >> /etc/security/limits.d/99-grid-oracle.conf <<'LIMITS_EOF'
oracle  soft  memlock  unlimited
oracle  hard  memlock  unlimited
grid    soft  memlock  unlimited
grid    hard  memlock  unlimited
LIMITS_EOF
    fi
    sysctl --system
    echo "$HUGEPAGES_NUM" > /proc/sys/vm/nr_hugepages
fi
```

**Override for larger DBs:** `HUGEPAGES_NUM=1024 sudo bash prepare_host.sh --role=rac` (= 2 GB SGA), `HUGEPAGES_NUM=2048` (= 4 GB).

**Gain:**
- ~10–15% generic speedup of the entire database (fewer TLB misses → fewer cycles per operation)
- SGA pinned in memory (memlock unlimited) — not subject to swapping even under RAM pressure
- No fragmentation of 392k 4K pages → 768 2MB pages

**DB restart required** after the first run of `prepare_host.sh`, so the SGA allocates from hugepages. In the install pipeline this is not a problem (DBCA creates the DB after prepare_host.sh — straight away with hugepages).

**Live application 2026-04-26:** applied to a working lab before Step F (09 RMAN duplicate). Restart `srvctl stop/start database -db PRIM` took the SGA onto hugepages.

**Verification:**
```bash
# /proc/meminfo - HugePages_Free ~0 means SGA took hugepages
grep -i huge /proc/meminfo
# HugePages_Total:    768
# HugePages_Free:       0    ← SGA took
# Hugepagesize:       2048 kB

# Oracle - parameter use_large_pages (default 23ai = TRUE = best-effort)
SHOW PARAMETER use_large_pages   # TRUE (recommended) / ONLY (hard fail) / FALSE
```

**Lesson:**
- **Optimization independent of storage backend = single source of truth.** `prepare_host_block.sh` separated something that applies to both variants — a design error. After the refactor the wrapper is legacy, can be left, but new installations use only `prepare_host.sh`.
- **`use_large_pages=TRUE` (default 23ai)** = best-effort fallback. Don't use `ONLY` in the lab — at a momentary lack of hugepages the DB won't start.
- **memlock unlimited critical** — without it oracle processes can't pin HugePages, allocation fails, DB falls back to 4K.

---

### FIX-038 — `duplicate_standby.sh` audit pre-09 (8 fixes)

**Context:** After Step C (primary health check) the audit of the `duplicate_standby.sh` v1.0 script revealed 8 issues — 3 critical (script **won't move**), 4 important (risks and slow execution), 1 nice-to-have. Plus the user has an Active Data Guard license (issue ADG #3 from the plan drops out).

**Issue #1 (CRITICAL) — No tnsnames.ora generation on stby01.**
The script lines use `sqlplus sys/...@PRIM` and `CONNECT TARGET ...@PRIM` / `CONNECT AUXILIARY ...@STBY`. Without aliases in `$TNS_ADMIN/tnsnames.ora` both connects fail with `ORA-12154`. The script didn't generate tnsnames as an internal step — it assumed an external prerequisite.

**Issue #2 (CRITICAL) — No listener.ora SID_LIST static generation for STBY.**
RMAN AUXILIARY connect to `STBY` in nomount state requires static registration in the listener (an instance in nomount won't register dynamically — PMON only does this after MOUNT). Without `SID_LIST_LISTENER` with an entry for `STBY` → `ORA-12514 listener does not currently know of service requested`.

**Issue #3 (CRITICAL) — No `lsnrctl start` before RMAN.**
Even with a correct listener.ora, the listener must be UP before the RMAN duplicate section.

**Issue #4 (IMPORTANT) — `SHUTDOWN ABORT` without `WHENEVER SQLERROR CONTINUE`.**
The first `STARTUP NOMOUNT` section starts with `SHUTDOWN ABORT` (idempotency). If the STBY instance **has never started**, `SHUTDOWN ABORT` returns ORA-01034. With `set -euo pipefail` it can kill the script on the first run (clean environment).

**Issue #5 (IMPORTANT) — No primary sanity check.**
The script doesn't verify that the primary is ready. If `FORCE_LOGGING != YES`, `< 8 SRL`, `log_archive_config doesn't include STBY` → duplicate will succeed, but apply won't work / there will be data divergence. Safer: SQL `@PRIM` at the start, abort with a clear message.

**Issue #6 (IMPORTANT) — RMAN without channels parallelism.**
Single channel duplicate ~10-15 min for a 5 GB lab DB. With 4 target + 4 auxiliary channels: ~3-5 min. Syntax 23.26.1: `RUN { ALLOCATE CHANNEL c1..c4 + ALLOCATE AUXILIARY CHANNEL aux1..aux4; DUPLICATE ...; }`.

**Issue #7 (NICE-TO-HAVE) — `sga_target=2048M` in initSTBY.ora vs primary 1.5 GB.**
Primary has `sga_target=1536M` (Maximum SGA Size 1533 MB confirmed via `v$sgainfo`). STBY with 2048M = 2 GB **won't fit in HugePages 768×2MB = 1.5 GB** — Oracle falls back to 4K, no benefit from FIX-037. Plus inconsistency after switchover. Synced to `sga_target=1536M`.

**Issue #8 (NICE-TO-HAVE) — `log_archive_dest_2=''` (empty string in RMAN SET).**
In 23.26.1 some composer versions register an empty string as a parsing error. Safer to set right away to `'SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILE,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM'` — ready for switchover, no need to update in doc 10.

**Fix `scripts/duplicate_standby.sh` v2.0:**

Full rewrite with 9 numbered sections:
- Section 0: Primary sanity check (Issue #5) — 9 checks via `ssh oracle@prim01 sqlplus`, abort with `die` if FAIL
- Section 1: Directories /u01/app/oracle/admin/STBY/adump, /u02/oradata/STBY, /u03/fra/STBY + /etc/oratab
- Section 2: initSTBY.ora with `sga_target=1536M` (Issue #7)
- Section 3: tnsnames.ora generation (Issue #1) — PRIM (scan-prim:1521), STBY (locally), PRIM_DGMGRL/STBY_DGMGRL (UR=A)
- Section 4: listener.ora SID_LIST static + `lsnrctl start` (Issue #2 + #3)
- Section 5: scp pwfile from prim01:/tmp/pwd/orapwPRIM
- Section 6: STARTUP NOMOUNT with `WHENEVER SQLERROR CONTINUE` before `SHUTDOWN ABORT` (Issue #4) + sleep 10s for PMON listener registration
- Section 7: Test connection sys@PRIM
- Section 8: RMAN DUPLICATE with `RUN { ALLOCATE CHANNEL c1..c4 + aux1..aux4 ... }` (Issue #6) + `log_archive_dest_2=` immediately correctly (Issue #8)
- Section 9: Post-duplicate `OPEN READ ONLY` + `RECOVER MANAGED STANDBY USING CURRENT LOGFILE` (Active Data Guard real-time apply — user has ADG license)

**What's preserved unchanged (verified OK):**
- `compatible=23.0.0` — matches baseline 23.26.1
- `cluster_database=FALSE` — OK (stby01 is SI)
- `NOFILENAMECHECK` — OK (we have `db_file_name_convert`)
- `dg_broker_start=FALSE` — OK (will enable in doc 10)
- `OPEN READ ONLY` — OK (user has ADG license)

**Expected duplicate time:** ~3-5 min for 5 GB DB (with 4+4 channels) instead of ~10-15 min (single channel). Combined with FIX-036 (TCP buffer tuning would be the next step) and FIX-037 (HugePages) — full 09 pipeline = ~5-8 min.

**Lesson:**
- **ALWAYS audit scripts before a greenfield run.** Scripts from 19c→23ai documentation can have hidden external prerequisites (like tnsnames/listener) that the author assumed but didn't program in.
- **`set -euo pipefail` + idempotency** require explicit `WHENEVER SQLERROR CONTINUE` in sqlplus heredocs.
- **RMAN parallelism in the lab is worth it** — 4+4 channels don't load even small hardware (single VM read+write), time gain ~3x.
- **Sanity check primary BEFORE long-running operation** — 30s of SQL eliminates 15 min of duplicate execution that would go wrong.

---

### FIX-039 — `sudo` in a nohup-ed script halts the process (SIGTTOU)

**Problem:** First run of `duplicate_standby.sh v2.0` via `nohup ... &` halted **immediately** in section 1 with the message:

```
We trust you have received the usual lecture from the local System
Administrator. It usually boils down to these three things:
    #1) Respect the privacy of others.
    #2) Think before you type.
    #3) With great power comes great responsibility.

[1]+  Stopped                 nohup bash /tmp/scripts/duplicate_standby.sh > /tmp/dup.out 2>&1
```

**Cause:** Section 1 did `echo "STBY:..." | sudo tee -a /etc/oratab`. The first invocation of `sudo` in a session shows the "lecture" + a password prompt. `nohup` redirects stdin to `/dev/null`, so sudo **has no source for the password** → tries to read from the controlling terminal → bash controls the terminal and the nohup-ed process gets SIGTTOU (try-to-read-from-tty in background) → status `Stopped`.

**General lesson:** Oracle scripts (run as the oracle user, not root) **should never use `sudo` at runtime**. All modifications of system files (`/etc/oratab`, `/etc/hosts`, `/etc/sysctl.d/...`) must be done **proactively at install time** by `prepare_host.sh` (as root) or manually by the admin.

**Fix 1 — `scripts/duplicate_standby.sh` v2.1 (section 1):**

```bash
# Old version (PROBLEM):
if ! grep -q "^STBY:" /etc/oratab 2>/dev/null; then
    echo "STBY:$ORACLE_HOME:N" | sudo tee -a /etc/oratab >/dev/null || \
        warn "Failed to append to /etc/oratab (continuing)"
fi

# New version (FIX-039) - only checks, doesn't modify:
if ! grep -q "^STBY:" /etc/oratab 2>/dev/null; then
    warn "No 'STBY:...' entry in /etc/oratab. Script continues, but 'oraenv' won't find STBY."
    warn "Add manually as root: echo 'STBY:$ORACLE_HOME:N' >> /etc/oratab"
fi
```

**Fix 2 — `scripts/prepare_host.sh` v1.4 (new section 7d):**

Proactively adding the entry to `/etc/oratab` in `prepare_host.sh` (run as root at OS prep, **doesn't require sudo**):

```bash
if [[ "$ROLE" == "rac" ]]; then
    case "$(hostname -s)" in
        prim01) SID=PRIM1 ;;
        prim02) SID=PRIM2 ;;
    esac
    [[ -n "$SID" ]] && grep -qE "^${SID}:" /etc/oratab 2>/dev/null || \
        echo "${SID}:/u01/app/oracle/product/23.26/dbhome_1:N" >> /etc/oratab
elif [[ "$ROLE" == "si" ]]; then
    grep -qE "^STBY:" /etc/oratab 2>/dev/null || \
        echo "STBY:/u01/app/oracle/product/23.26/dbhome_1:N" >> /etc/oratab
fi
```

**Hot-fix for the current situation (session 26.04):**

```bash
# On stby01 as root (1 time)
echo "STBY:/u01/app/oracle/product/23.26/dbhome_1:N" >> /etc/oratab
```

After this `duplicate_standby.sh` v2.1 + nohup will no longer hang in section 1.

**Fix 3 — `09_standby_duplicate.md`:**
- Added pattern `nohup bash ... > /tmp/dup.out 2>&1 &` as recommended (instead of plain bash)
- Explanation of why nohup is critical (5 min script + risk of SSH disconnect)
- Pre-existing `/etc/oratab` STBY entry requirement in the "Requirements (external)" section

**Lesson (universal):**
- **`sudo` + `nohup` (or any background) = always a problem** — sudo requires a tty for the password prompt; background processes have no tty. Solution: NOPASSWD in sudoers (complicates setup) **or a better option** — move the logic that needs root into a script run as root at install (e.g. `prepare_host.sh`).
- **Oracle user-space scripts should be pure `oracle`-context.** Every `sudo` in a script that's supposed to be run by oracle = code smell. Refactor into prepare_host.sh.
- **For nohup ALWAYS test on `< /dev/null`** — if the process tries to read from stdin somewhere (sudo password, interactive prompts), it hangs.

---

### FIX-040 — `service_names` in 23ai DBCA `New_Database.dbt` has a `.db_domain` suffix

**Problem:** `duplicate_standby.sh v2.1` in section 7 (test connection sys@PRIM) failed:

```
ORA-12514: Cannot connect to database. Service PRIM is not registered with the
listener at host 192.168.56.32 port 1521.
```

Even though:
- `remote_listener=scan-prim.lab.local:1521` ✅
- SCAN listener up and ONLINE (3 listeners on 2 nodes via `srvctl status scan_listener`) ✅
- PMONs registered ✅
- `tnsping scan-prim.lab.local:1521` → OK ✅

**Diagnosis:**

```sql
SQL> SHOW PARAMETER service_names
NAME             VALUE
---------------- ------------------------
service_names    PRIM.lab.local        ← WITH DOMAIN!
```

```bash
$ lsnrctl status LISTENER_SCAN3 | grep Service
Service "PRIM.lab.local" has 2 instance(s).        ← ONLY WITH DOMAIN!
Service "PRIMXDB.lab.local" has 2 instance(s).
# NO "PRIM" as a bare name
```

In the script's tnsnames.ora was:
```
PRIM = (... (SERVICE_NAME = PRIM) ...)        ← ERROR, no .lab.local
```

**Cause:** Oracle 23ai DBCA with the `New_Database.dbt` template (FIX-030) **automatically appends `db_domain` to `service_names`**. In 19c and earlier 23ai patch sets it varied (often `db_domain=''` was the default, so service_names without suffix). In 23.26.1 from January 2026 — **db_domain ='lab.local' is added automatically** during DBCA if `oracleHomeName` or network config suggests a domain (lab.local is in the `db.lab.local` zone on infra01 bind9).

**Fix `scripts/duplicate_standby.sh` v2.2:**

1. **`tnsnames.ora`** — `SERVICE_NAME=PRIM` → `SERVICE_NAME=PRIM.lab.local`. Analogously for STBY: `SERVICE_NAME=STBY.lab.local` (post-duplicate STBY will also have a suffix because we add `db_domain=lab.local` to initSTBY.ora — see point 2).

2. **`initSTBY.ora`** — added `db_domain=lab.local` (consistency with primary). Additionally removed deprecated `audit_file_dest`, `audit_trail` (in 23ai legacy audit is deprecated, Unified Audit is default-on; ORA-32006 warnings from the previous run).

3. **`listener.ora` SID_LIST_LISTENER** — added a 3rd `SID_DESC` with `GLOBAL_DBNAME=STBY.lab.local` (matches dynamic registration after DB starts with db_domain). The first `SID_DESC` with `GLOBAL_DBNAME=STBY` is preserved (RMAN AUXILIARY connect uses the alias `STBY` from tnsnames, which pre-duplicate is still without domain — the STBY instance in nomount does NOT have db_domain set until RMAN sets the SPFILE).

4. **DGMGRL services** (`PRIM_DGMGRL`, `STBY_DGMGRL`) **PRESERVED without domain** — that's a conscious decision: static registration in `SID_LIST_LISTENER` uses the `GLOBAL_DBNAME` parameter directly, doesn't respect `db_domain`. The DG broker in doc 10 will connect through these aliases.

**Hot-fix for the current 26.04 session (before re-running the script):**

```bash
# On stby01 as oracle - cleanup nomount instance
sqlplus / as sysdba <<<"SHUTDOWN ABORT;"
ps -ef | grep ora_pmon_STBY | grep -v grep    # should: nothing

# Copy v2.2 from the host
scp <repo>/VMs/scripts/duplicate_standby.sh oracle@stby01:/tmp/scripts/duplicate_standby.sh

# Run again
nohup bash /tmp/scripts/duplicate_standby.sh > /tmp/dup.out 2>&1 &
tail -f /tmp/dup.out
```

**Lesson (universal for 23ai/26ai):**
- **Don't assume that `service_names = db_unique_name`** — check **SHOW PARAMETER service_names** instead of relying on convention.
- **DBCA in 23ai/26ai automatically adds `db_domain`** to service_names. If you have DNS zone configured for the lab and bind9 reverse zone, DBCA may "guess" the domain and add it — even when no explicit `--databaseDomain` parameter was passed.
- **Static SID_LIST in listener.ora** doesn't respect `db_domain` — `GLOBAL_DBNAME` parameter is used literally. This is good for DGMGRL services (connect by literal name) but requires duplicating entries (with and without domain) for instances that should respond both ways.

---


---

### FIX-041 — RMAN DUPLICATE in 26ai: `cluster_database_instances` not supported in SET clause

**Problem:** `duplicate_standby.sh v2.2` reached RMAN section 8, allocated 4+4 channels, but immediately after `Starting Duplicate Db at 2026-04-26 16:35:18` failed:

```
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-03002: failure of Duplicate Db command at 04/26/2026 16:35:19
RMAN-05501: aborting duplication of target database
RMAN-06581: option cluster_database_instances not supported
```

All channels released, RMAN session dropped.

**Diagnosis:** In 26ai (confirmed on 23.26.1 January 2026) RMAN `DUPLICATE TARGET DATABASE FOR STANDBY ... SPFILE SET ...` clause **does not support** the `cluster_database_instances` parameter. The list of supported SET parameters was changed in 23ai/26ai (exact diff vs 19c not available in MOS, but empirically confirmed — `cluster_database_instances` removed from supported list).

In 19c and earlier 23ai patches, `SET cluster_database_instances='1'` in RMAN duplicate **worked** for SI standby (changes from RAC primary 2-instance to SI 1-instance). In 26ai you need **post-duplicate ALTER SYSTEM** + bounce.

**Fix `scripts/duplicate_standby.sh` v2.3:**

1. **Section 8 (RMAN DUPLICATE)** — removed **2 SET parameters**:
   ```diff
   -    SET cluster_database_instances='1'    # RMAN-06581 not supported in 26ai
   -    SET audit_file_dest='/u01/app/oracle/admin/STBY/adump'  # deprecated in 26ai
   ```
   Retained: `cluster_database='FALSE'` (works in SET clause).

2. **Section 8b NEW — post-duplicate ALTER SYSTEM SCOPE=SPFILE:**
   ```sql
   ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
   ALTER SYSTEM SET audit_file_dest='/u01/app/oracle/admin/STBY/adump' SCOPE=SPFILE;
   ```

3. **Section 9 — refactor: bounce + open RO + MRP:**
   ```diff
   -ALTER DATABASE OPEN READ ONLY;        # db in MOUNTED after duplicate, can go directly
   +SHUTDOWN IMMEDIATE;                    # bounce to apply SPFILE params
   +STARTUP MOUNT;
   +ALTER DATABASE OPEN READ ONLY;
    ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
   ```
   Bounce required so that `cluster_database=FALSE` and `cluster_database_instances=1` actually take effect (without bounce the database still sees `cluster_database=TRUE` from the initSPFILE from RMAN duplicate).

**Hot-fix for current session 2026-04-26 (after RMAN-06581):**

```bash
# 1. STBY was left in nomount after failed duplicate - shutdown
sqlplus / as sysdba <<<"SHUTDOWN ABORT;"

# 2. Copy v2.3
scp <repo>/VMs/scripts/duplicate_standby.sh oracle@stby01:/tmp/scripts/

# 3. Re-run
nohup bash /tmp/scripts/duplicate_standby.sh > /tmp/dup.out 2>&1 &
```

**Lesson:**
- **In 26ai RMAN DUPLICATE SET clause has a restricted list of parameters** vs 19c. General rule: in SET clause only parameters **critical for building the clone database** (db_unique_name, file_name_convert, controlfiles, log_archive_*, fal_*). Everything related to cluster, audit, monitoring → post-duplicate ALTER SYSTEM SCOPE=SPFILE + bounce.
- **Test rule:** if a parameter is not required for DUPLICATE to start at all (i.e. it affects RECOVERY, db identity, or destination paths), it probably isn't in the SET whitelist. Cluster params, audit dest, monitoring dest → ALWAYS post-duplicate.
- **Bounce after post-duplicate ALTER SYSTEM SCOPE=SPFILE** is often necessary — RMAN creates SPFILE from target+SET, but the runtime SGA from duplicate has old values (from target). Only a bounce reloads the SPFILE.

---

### FIX-042 — RAC primary → SI standby cleanup (instance_number, remote_listener, NOT thread)

**Context:** After FIX-041 (removing `cluster_database_instances` from RMAN SET clause) a second Claude suggested additional parameters. Critical analysis revealed 4 items:

| Suggestion | Verdict | Why |
|------------|---------|-----|
| `SET cluster_database_instances='1'` | ❌ NO | RMAN-06581 — this is exactly what threw the error (FIX-041); not supported in 26ai SET clause |
| `SET thread='1'` | ❌ NO | **Dangerous for SI standby with RAC primary.** SI standby applies redo from BOTH threads (thread 1 from PRIM1, thread 2 from PRIM2). `thread=1` would block applying thread 2 → data divergence. Parameter only makes sense for SI primary → SI standby. |
| `SET instance_number='1'` | ✅ YES | SPFILE from RMAN duplicate inherits `instance_number` from the target instance (1 or 2 — depends on which node duplicate target connected to). Forcing =1 is good practice for SI. **BUT** post-duplicate (not in RMAN SET — safer). |
| `UNSET remote_listener` in SPFILE | ✅ YES | Primary has `remote_listener='scan-prim.lab.local:1521'` (RAC for SCAN registration). SI standby has no SCAN → pointless on stby01. **BUT** post-duplicate `RESET remote_listener` (cleaner than UNSET in SET clause). |

**Empirical verification that "thread=1 would be a mistake":**

```sql
SELECT thread#, COUNT(*) FROM v$standby_log GROUP BY thread#;
-- thread 1: 4 SRL
-- thread 2: 4 SRL
-- TOTAL: 8 SRL = 4 per thread x 2 threads (RAC primary)
```

Standby has 8 SRL (FIX-038 #5 sanity check) because it must have separate SRL for each primary thread. Standby with `thread=1` applies only thread 1 redo; thread 2 redo would remain in SRL without being applied → MRP gap → data loss on switchover.

**General rule:** For **Physical Standby SI with RAC primary** the thread parameter **MUST remain UNSET** (default means "all threads"). Only when primary is also SI (1-thread) can you explicitly set `thread=1` for full symmetry.

**Fix `scripts/duplicate_standby.sh` v2.4 (section 8b):**

```sql
-- v2.3 (after FIX-041)
ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
ALTER SYSTEM SET audit_file_dest='/u01/app/oracle/admin/STBY/adump' SCOPE=SPFILE;

-- v2.4 (FIX-042) - added:
ALTER SYSTEM SET instance_number=1 SCOPE=SPFILE;       -- SI uses instance 1
ALTER SYSTEM RESET remote_listener SCOPE=SPFILE;        -- SI doesn't use SCAN
-- NOTE: We do NOT set thread=1 (data divergence risk)
```

Bounce in section 9 (already from FIX-041) will apply everything.

**Lesson (universal):**
- **Critically verify every suggestion from another source** — even "Claude" may have 19c knowledge for a 26ai problem. Empirically: `SHOW PARAMETER thread`, `v$standby_log GROUP BY thread#`, `lsnrctl status SCAN | grep Service`.
- **RAC primary → SI standby asymmetry:** RAC parameters (cluster_database, cluster_database_instances, instance_number) ALWAYS change on the SI side; but redo flow parameters (thread, log_file_name_convert) leave at SI default so MRP isn't restricted to one thread.
- **Post-duplicate ALTER SYSTEM SCOPE=SPFILE** is a cleaner mechanism than RMAN SET clause — supports **all** parameters, not just RMAN whitelist.

---

### FIX-043 — Active Duplicate in 26ai: primary node needs auxiliary alias in ITS OWN tnsnames.ora

**Problem:** `duplicate_standby.sh v2.4` passed sections 0–7, started RMAN section 8, allocated 8 channels (4+4), began `Starting Duplicate Db at 2026-04-26 16:46:55`, but immediately after the first Memory Script failed:

```
contents of Memory Script:
{
   backup as copy reuse
   passwordfile auxiliary format '/u01/app/oracle/product/23.26/dbhome_1/dbs/orapwSTBY';
   restore clone from service 'PRIM' spfile to '...';
   sql clone "alter system set spfile= ...";
}
executing Memory Script

Starting backup at 2026-04-26 16:46:55
RMAN-03002: failure of Duplicate Db command at 04/26/2026 16:46:57
RMAN-03009: failure of backup command on c1 channel at 04/26/2026 16:46:57
ORA-17627: ORA-12154: Cannot connect to database. Cannot find alias STBY in
  /u01/app/oracle/product/23.26/dbhome_1/network/admin/tnsnames.ora.
ORA-17629: cannot connect to the remote database server
```

**Diagnosis:** Key: error references **prim01/prim02 path** (`PRIM2_ora_65686.trc` in server diagnostic trace). Not an error on stby01. This means **the target instance (PRIM2 from RAC primary)** is trying to connect to **auxiliary STBY** using ITS OWN tnsnames.ora — but the `STBY` alias isn't there.

**Active Database Duplicate in 26ai workflow:**
1. RMAN client (running on stby01) connects to TARGET (PRIM via SCAN) and AUXILIARY (STBY local)
2. RMAN target side (PRIM2 instance — selected by SCAN load balancing) **opens a direct connection to auxiliary** to stream datafiles directly
3. PRIM2 looks in `$ORACLE_HOME/network/admin/tnsnames.ora` on node prim02 → searches for alias `STBY`
4. **Alias missing** → ORA-12154 → RMAN-03009 backup fail

In 19c and earlier 23ai, Active Duplicate sometimes worked differently (RMAN client mediating everything). In 26ai/23.26.1, the active duplicate architecture **requires** that primary nodes have an alias to auxiliary, because they make their own connection.

**Why our `duplicate_standby.sh` didn't work:**
- Script v2.0–v2.4 generated tnsnames.ora **only on stby01** (section 3)
- prim01/prim02 had no STBY alias → ORA-12154 during active duplicate

**Fix `scripts/duplicate_standby.sh` v2.5 — NEW section 3b:**

```bash
deploy_stby_alias() {
    local PRIM_NODE="$1"
    ssh oracle@$PRIM_NODE bash -c "'
        TNS_FILE=\$ORACLE_HOME/network/admin/tnsnames.ora
        [[ -f \$TNS_FILE.orig ]] || cp \$TNS_FILE \$TNS_FILE.orig
        if ! grep -qE \"^STBY[[:space:]]*=\" \$TNS_FILE; then
            cat >> \$TNS_FILE <<TNS_EOF

STBY = (... HOST=stby01.lab.local PORT=1521 SERVICE_NAME=STBY (UR=A) ...)
STBY_DGMGRL = (... HOST=stby01.lab.local PORT=1522 SERVICE_NAME=STBY_DGMGRL (UR=A) ...)
TNS_EOF
        fi
    '"
}
deploy_stby_alias prim01
deploy_stby_alias prim02
```

Additionally added `tnsping STBY` from prim01 as a pre-RMAN sanity check.

**SERVICE_NAME=STBY (WITHOUT .lab.local):**
- Static registration in `SID_LIST_LISTENER` (section 4) has `GLOBAL_DBNAME=STBY` as the first SID_DESC
- In nomount mode `db_domain` is not yet applied (pfile→memory, but dynamic registration inactive)
- After duplicate (when `db_domain=lab.local` from initSTBY.ora is in effect) dynamic registration will add `STBY.lab.local`, but during duplicate only the static SID_LIST is active

**`(UR=A)` — Use Restricted = Allow:**
- Requires acceptance of connect to a database in `RESTRICTED SESSION` mode (auxiliary in nomount often has this)
- Without it: ORA-12526 "TNS:listener: all appropriate instances are in restricted mode"

**SSH equivalency requirement:**
Section 3b requires ssh oracle@stby01 → oracle@prim01 and prim02 (without password). FIX-038 (section 5) already required oracle@stby01 → oracle@prim01 for scp pwfile. Section 3b additionally requires prim02 (analogously). User must set up SSH key for both primary nodes.

**Lesson (universal for Active Duplicate):**
- **Active Duplicate ≠ pure client-server** — primary nodes (target) make their own outbound connections to auxiliary. They require local TNS resolution for auxiliary.
- **If primary is RAC, deploy alias on every node** — RMAN doesn't know which node target will stream from (load balancing via SCAN).
- **Pre-RMAN test: `tnsping <auxiliary>` from every primary node.** If timeout/no resolve → fix tnsnames BEFORE starting duplicate.
- **In 19c era this problem was rarer** — RMAN client was often on primary + faster form of duplicate (image copy). In 26ai service-based active duplicate with service-based restore requires peer-to-peer connection.

---

### FIX-044 — RMAN duplicate ASM→XFS: `db_create_file_dest` must be in SET (not just `db_file_name_convert`)

**Problem:** `duplicate_standby.sh v2.5/v2.6` in section 8 RMAN duplicate. RMAN `restore clone from service 'PRIM' spfile` succeeded, RMAN aux instance restarted with cloned SPFILE, allocated 4+4 channels, **began restoring datafiles**:

```
channel aux1: starting datafile restore from service ...
channel aux4: restoring datafile 00004 to +DATA      ← TARGET STILL +DATA!
dbms_backup_restore.restoreCancel() failed
RMAN-03002: failure of Duplicate Db command at 04/26/2026 17:04:20
ORA-19660: some files in the backup set could not be verified
ORA-19661: datafile 1 could not be verified due to corrupt blocks
ORA-19849: error while reading backup piece from service PRIM
ORA-19504: failed to create file "+DATA"
ORA-17502: (4)Failed to create file +DATA
ORA-15001: disk group "DATA" does not exist or is not mounted
ORA-15374: invalid cluster configuration
```

**Diagnosis:** stby01 (SI with local XFS, **without ASM**) is trying to create a datafile at path `+DATA` — the ASM disk group from primary. Even though RMAN SET contains `db_file_name_convert='+DATA/PRIM','/u02/oradata/STBY'` in SPFILE.

**Why convert wasn't enough:** `db_file_name_convert` maps **existing file names** during restore (matching prefix → replace). But primary has **`db_create_file_dest='+DATA'`** in SPFILE (Oracle Managed Files for ASM). The clone inherits from primary, so **when creating new files** (controlfile mirror, online redo logs, even some datafiles that RMAN creates with OMF semantics) RMAN uses **`db_create_file_dest`** as the destination, ignoring `db_file_name_convert`.

Result: RMAN tries to create datafile in `+DATA` (from `db_create_file_dest` copied from primary) → ORA-15001 disk group not mounted (no ASM on stby01).

**Workflow in 26ai active duplicate (key):**
1. `restore clone from service 'PRIM' spfile` — copy SPFILE from primary
2. `alter system set db_unique_name='STBY' ...` + other SET parameters **in the clone's new SPFILE**
3. Bounce auxiliary with new SPFILE
4. **`restore datafile`** — here RMAN uses **the clone's current SPFILE**:
   - `db_create_file_dest` → destination for CREATE
   - `db_file_name_convert` → mapping existing names (from target)
   - If `db_create_file_dest` from primary wasn't overridden in SET → clone tries to write to `+DATA`

**Fix `scripts/duplicate_standby.sh` v2.7:**

Added **2 new parameters** to RMAN SET:
```diff
       SET db_unique_name='STBY'
-      SET db_file_name_convert='+DATA/PRIM','/u02/oradata/STBY'
-      SET log_file_name_convert='+DATA/PRIM','/u02/oradata/STBY'
+      SET db_file_name_convert='+DATA/PRIM','/u02/oradata/STBY','+RECO/PRIM','/u03/fra/STBY'
+      SET log_file_name_convert='+DATA/PRIM','/u02/oradata/STBY','+RECO/PRIM','/u03/fra/STBY'
+      SET db_create_file_dest='/u02/oradata/STBY'
+      SET db_create_online_log_dest_1='/u02/oradata/STBY'
       SET cluster_database='FALSE'
```

Changes:
- **`db_create_file_dest='/u02/oradata/STBY'`** — Oracle Managed Files destination (CREATE of new OMF goes here instead of +DATA)
- **`db_create_online_log_dest_1='/u02/oradata/STBY'`** — destination for online redo logs on CREATE (primary has in +DATA)
- **`db_file_name_convert` extended with pair `'+RECO/PRIM','/u03/fra/STBY'`** — some primary files (e.g. flashback logs, archivelog) may be in +RECO, not +DATA. 4-element list = 2 pairs (source→target).
- **`log_file_name_convert` analogously** — online redo and SRL.

**Rule of thumb for RMAN duplicate ASM→XFS:**

| Parameter | What it does | Required? |
|-----------|-------------|-----------|
| `db_file_name_convert` | Name mapping when restoring existing files | ✅ YES |
| `log_file_name_convert` | Name mapping for redo/SRL on restore | ✅ YES |
| `db_create_file_dest` | Destination for CREATE (OMF) — new datafiles, controlfile mirror | ✅ **YES (often forgotten)** |
| `db_create_online_log_dest_1` | Destination for online redo logs on CREATE | ✅ YES |
| `db_recovery_file_dest` | FRA destination (archivelog, flashback) | ✅ YES |
| `control_files` | List of controlfile paths on clone | ✅ YES |

Missing any of `db_create_file_dest` / `db_create_online_log_dest_*` when duplicating from ASM primary to non-ASM standby = ORA-15001 / ORA-19504.

**Lesson:**
- **`db_file_name_convert` ≠ catch-all for ASM→XFS migration.** Convert only does mapping during restore. CREATE uses `db_create_file_dest` (OMF) — and that must be overridden separately.
- **Check ALL `*_dest` parameters on primary before duplicate.** `SHOW PARAMETER dest` on primary and every ASM-pointing parameter must have an override in SET (or `RESET ... SCOPE=SPFILE` post-duplicate).
- **Rule: if primary uses OMF with ASM, the SI clone must have the complete set of destination overrides** in RMAN SET clause.

---

### FIX-045 — Missing onlinelog dir + ORL/SRL recreate post-duplicate

**Problem:** RMAN duplicate v2.7 **completed** (`Finished Duplicate Db at 2026-04-26 17:15:57`), datafiles copied to `/u02/oradata/STBY/STBY/datafile/`, BUT during the cleanup phase RMAN returned **12 times** ORA-00344:

```
Oracle error from auxiliary database: ORA-00344: unable to re-create online log
  '/u02/oradata/STBY/onlinelog/group_1.276.1231537649'
ORA-27040: file create error, unable to create file
Linux-x86_64 Error: 2: No such file or directory

RMAN-05535: warning: All redo log files were not defined properly.
```

12 logs: 4 ORL (groups 1–4) + 8 SRL (groups 11–14, 21–24). All with pattern `+DATA/PRIM/onlinelog/group_X.YYY.ZZZZ` on primary (ASM-style names) → after convert should be at `/u02/oradata/STBY/onlinelog/...`.

**Diagnosis:** **Subdirectory `/u02/oradata/STBY/onlinelog/` DOES NOT EXIST**. Script v2.7 section 1 only did:
```bash
mkdir -p /u01/app/oracle/admin/STBY/adump
mkdir -p /u02/oradata/STBY
mkdir -p /u03/fra/STBY
```

Convert maps the **prefix** `+DATA/PRIM` → `/u02/oradata/STBY`. The full primary path `+DATA/PRIM/onlinelog/group_X` after convert gives `/u02/oradata/STBY/onlinelog/group_X`. RMAN tries to create → parent dir doesn't exist → ORA-27040.

**Why RMAN doesn't auto-create the dir:** for **datafiles** RMAN auto-creates subdirectories on CREATE OMF (visible after success `/u02/oradata/STBY/STBY/datafile/o1_mf_*.dbf`). But for **online logs / SRL** OMF mode is restrictive — creates the file only if the parent dir exists. With `db_file_name_convert` (not OMF auto-naming for logs), the parent must be pre-created.

**Result:** Standby is MOUNTED with datafiles, **BUT without ORL and SRL**. `ALTER DATABASE OPEN READ ONLY` may open (datafiles OK), BUT `RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE` → **fail without SRL** (real-time apply requires SRL).

**Plus 2 non-critical errors in section 8b (cleanup):**

```
ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
ERROR at line 1: ORA-02065: illegal option for ALTER SYSTEM
```

**SI standby does not have the `cluster_database_instances` parameter** (RAC only). Default implicit = 1. The line is redundant. Tolerated by `WHENEVER SQLERROR CONTINUE`, but cleaner to omit.

```
ALTER SYSTEM RESET remote_listener SCOPE=SPFILE;
ERROR at line 1: ORA-32010: cannot find entry to delete in SPFILE
```

**RMAN convert zeroed out `remote_listener` in clone SPFILE** (or primary didn't have an explicit SPFILE value). RESET has nothing to remove. OK, non-critical.

**Fix `scripts/duplicate_standby.sh` v2.8:**

1. **Section 1:** added `mkdir -p /u02/oradata/STBY/onlinelog`

2. **Section 8b:** removed `ALTER SYSTEM SET cluster_database_instances=1` and unconditional `RESET remote_listener`. Replaced with conditional RESET via PL/SQL block:
   ```sql
   DECLARE v_count NUMBER;
   BEGIN
     SELECT COUNT(*) INTO v_count FROM v$spparameter
       WHERE name='remote_listener' AND isspecified='TRUE';
     IF v_count > 0 THEN
       EXECUTE IMMEDIATE 'ALTER SYSTEM RESET remote_listener SCOPE=SPFILE';
     END IF;
   END;
   /
   ```

3. **NEW section 8c — recreate ORL and SRL** (after section 8b, before section 9 bounce+open RO):
   - SHUTDOWN ABORT + STARTUP MOUNT
   - `CLEAR UNARCHIVED LOGFILE GROUP X` + `DROP LOGFILE GROUP X` for 4 ORL (1,2,3,4) and 8 SRL (11–14, 21–24)
   - `ADD LOGFILE THREAD N GROUP X ('/u02/oradata/STBY/onlinelog/redo0X.log') SIZE 200M REUSE` × 4 ORL
   - `ADD STANDBY LOGFILE THREAD N GROUP X ('...srlXY.log') SIZE 200M REUSE` × 8 SRL

**Hot-fix for current session 2026-04-26 (after duplicate v2.7 with errors):**

```bash
# Manual recreate (script v2.8 has this built-in, but duplicate already done here)
ssh oracle@stby01 "mkdir -p /u02/oradata/STBY/onlinelog"

ssh oracle@stby01 ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus / as sysdba" <<'EOF'
SHUTDOWN ABORT;
STARTUP MOUNT;
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 1;
-- (... drop ORL 1-4 + SRL 11-14, 21-24 ...)
ALTER DATABASE ADD LOGFILE THREAD 1 GROUP 1 ('/u02/oradata/STBY/onlinelog/redo01.log') SIZE 200M REUSE, ...;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 ('/u02/oradata/STBY/onlinelog/srl11.log') SIZE 200M REUSE, ...;
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
EXIT
EOF
```

**Lesson (universal):**
- **`db_file_name_convert` maps the prefix, but the parent dir must exist.** For datafiles RMAN OMF semantics creates directories. For online logs/SRL — it doesn't. Pre-create the `onlinelog/` subdirectory in the OS prep script.
- **RMAN `Finished Duplicate Db` ≠ success.** Check for `RMAN-05535: warning: All redo log files were not defined properly.` as a signal that logs/SRL weren't created — because without them MRP USING CURRENT LOGFILE won't start.
- **SI doesn't have `cluster_database_instances` parameter.** Attempting ALTER SYSTEM SET on SI = ORA-02065. Default implicit = 1, don't set it.
- **`ALTER SYSTEM RESET <param>` returns ORA-32010 if `<param>` is not in SPFILE.** Check `v$spparameter WHERE name=... AND isspecified='TRUE'` before RESET, or use PL/SQL block with exception handling.

---

### FIX-046 — Logical bug: tnsping STBY in section 3b BEFORE listener start (section 4)

**Problem:** `duplicate_standby.sh v2.8` on a clean rebuild failed at the end of section 3b:

```
[17:27:54]   Test tnsping STBY from prim01 (sanity before RMAN)...
TNS-12541: Cannot connect. No listener at host 192.168.56.13 port 1521.
 TNS-12560: Database communication protocol error.
  TNS-00511: No listener
   Linux Error: 111: Connection refused
[17:27:54] ERROR: tnsping STBY from prim01 FAIL - alias missing or stby01 listener not available
```

**Diagnosis:** Logical bug in section ordering in v2.6+:
- Section 3: tnsnames.ora local on stby01
- **Section 3b**: deploy STBY alias on prim01/02 + **tnsping STBY from prim01** ← HERE
- Section 4: listener.ora + **lsnrctl start** on stby01 ← LISTENER STARTS ONLY HERE

`tnsping STBY` from prim01 connects to `stby01.lab.local:1521`. stby01 listener has not yet started (section 4 after section 3b) → connection refused.

In v2.6 the assumption was that alias deploy + tnsping could be done together. In practice alias deploy works (copies file, grep verify OK), but tnsping requires a **physically listening listener** at the other end — which starts only in section 4.

**Fix `scripts/duplicate_standby.sh` v2.9:**

1. **Section 3b**: tnsping removed. Only `deploy_stby_alias prim01/prim02` + grep verify remains.

2. **Section 4** (after `lsnrctl start`): tnsping STBY from prim01 added as post-listener-start sanity:
   ```bash
   log "  Test tnsping STBY from prim01 (sanity before RMAN)..."
   TNSPING_OUT=$(ssh oracle@prim01 ". ~/.bash_profile && tnsping STBY 2>&1" || true)
   echo "$TNSPING_OUT" | tail -5
   echo "$TNSPING_OUT" | grep -q "^OK" || \
       die "tnsping STBY from prim01 FAIL after lsnrctl start - check alias prim01 or network"
   ```

Rationale: tnsping tests 2 things — (a) tnsnames.ora alias resolve, (b) network to listener. (a) is tested by grep in section 3b. (b) requires listener up, so the test must come AFTER section 4. Separating the sanity for two layers into two places (alias verify, network verify) eliminates false-fail.

**Lesson (universal):**
- **`tnsping` tests 2 layers: TNS resolution + TCP connect.** If alias is deployed but listener is not up → false-fail. Separate tests: `grep` on alias file (TNS resolution OK), `tnsping` after listener startup (TCP+listener OK).
- **Section ordering in long DBA scripts** must respect dependencies. Listing dependencies for each section in a comment at the start of the script helps find such buggy reorderings.
- **If a sanity check consistently fails after script reordering** — check whether a dependency (e.g. listener up) was provided in an earlier section.

---

### FIX-047 — Missing `/u03/fra/STBY/onlinelog/` + `standby_file_management=AUTO` blocks DROP LOGFILE

**Problem:** `duplicate_standby.sh v2.9` in section 8c (recreate ORL/SRL) failed 12× on CLEAR + DROP:

```
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 1
ORA-00344: unable to re-create online log '/u03/fra/STBY/onlinelog/group_1.263.1231537653'
ORA-27040: file create error, unable to create file
Linux-x86_64 Error: 2: No such file or directory

ALTER DATABASE DROP LOGFILE GROUP 1
ORA-01275: Operation DROP LOGFILE is not allowed if standby file management is automatic.
```

**Diagnosis:** Two problems met in section 8c:

1. **Missing directory `/u03/fra/STBY/onlinelog/`.** FIX-045 created only `/u02/oradata/STBY/onlinelog/`. The convert pair in RMAN SET is `+DATA/PRIM,/u02/oradata/STBY,+RECO/PRIM,/u03/fra/STBY` — RMAN when creating online log for each group places member 1 in `/u02/...` and member 2 in `/u03/fra/STBY/onlinelog/...` (multiplexed). Member 2 has no parent dir → ORA-27040.

2. **`standby_file_management=AUTO` blocks manual DROP LOGFILE.** RMAN SET set `SET standby_file_management='AUTO'`. With AUTO, Oracle does not allow manual DROP LOGFILE (ORA-01275) — requires switching to MANUAL during the operation.

**Fix `scripts/duplicate_standby.sh` v3.0:**

1. **Section 1**: added `mkdir -p /u03/fra/STBY/onlinelog`:
   ```bash
   mkdir -p /u02/oradata/STBY/onlinelog        # FIX-045
   mkdir -p /u03/fra/STBY
   mkdir -p /u03/fra/STBY/onlinelog            # FIX-047: convert maps +RECO -> /u03/fra
   ```

2. **Section 8c**: added `ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH` BEFORE CLEAR/DROP, and `=AUTO` AFTER ADD LOGFILE (restoring because AUTO is required during apply when primary adds a new datafile):
   ```sql
   ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH;
   ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 1; ... GROUP 4;
   ALTER DATABASE DROP LOGFILE GROUP 1; ... GROUP 4;
   ALTER DATABASE DROP STANDBY LOGFILE GROUP 11; ... GROUP 24;
   -- ADD LOGFILE THREAD 1/2 + ADD STANDBY LOGFILE THREAD 1/2
   ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH;
   ```

**Manual runbook (after FIX-047 applied to a database that already ran RMAN duplicate, to avoid repeating 5-min restore):**

```bash
# On stby01 as oracle
mkdir -p /u03/fra/STBY/onlinelog
sqlplus -s / as sysdba <<'SQL'
ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH;
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 1;
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 2;
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 3;
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 4;
ALTER DATABASE DROP LOGFILE GROUP 1;
ALTER DATABASE DROP LOGFILE GROUP 2;
ALTER DATABASE DROP LOGFILE GROUP 3;
ALTER DATABASE DROP LOGFILE GROUP 4;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 11;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 12;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 13;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 14;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 21;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 22;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 23;
ALTER DATABASE DROP STANDBY LOGFILE GROUP 24;

ALTER DATABASE ADD LOGFILE THREAD 1
  GROUP 1 ('/u02/oradata/STBY/onlinelog/redo01.log') SIZE 200M REUSE,
  GROUP 2 ('/u02/oradata/STBY/onlinelog/redo02.log') SIZE 200M REUSE;
ALTER DATABASE ADD LOGFILE THREAD 2
  GROUP 3 ('/u02/oradata/STBY/onlinelog/redo03.log') SIZE 200M REUSE,
  GROUP 4 ('/u02/oradata/STBY/onlinelog/redo04.log') SIZE 200M REUSE;

ALTER DATABASE ADD STANDBY LOGFILE THREAD 1
  GROUP 11 ('/u02/oradata/STBY/onlinelog/srl11.log') SIZE 200M REUSE,
  GROUP 12 ('/u02/oradata/STBY/onlinelog/srl12.log') SIZE 200M REUSE,
  GROUP 13 ('/u02/oradata/STBY/onlinelog/srl13.log') SIZE 200M REUSE,
  GROUP 14 ('/u02/oradata/STBY/onlinelog/srl14.log') SIZE 200M REUSE;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2
  GROUP 21 ('/u02/oradata/STBY/onlinelog/srl21.log') SIZE 200M REUSE,
  GROUP 22 ('/u02/oradata/STBY/onlinelog/srl22.log') SIZE 200M REUSE,
  GROUP 23 ('/u02/oradata/STBY/onlinelog/srl23.log') SIZE 200M REUSE,
  GROUP 24 ('/u02/oradata/STBY/onlinelog/srl24.log') SIZE 200M REUSE;

ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH;

-- Section 9 manually: open + start MRP
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;

-- Verify
SELECT name, db_unique_name, database_role, open_mode, protection_mode FROM v$database;
SELECT process, status FROM v$managed_standby WHERE process IN ('MRP0','RFS') ORDER BY process;
SQL
```

**Lesson (universal):**
- **`db_file_name_convert` with pair `+RECO/PRIM,/u03/fra/STBY` causes Oracle to place multiplexed online log members in `/u03/fra/STBY/onlinelog/` on CREATE.** Must prepare this directory together with `/u02/.../onlinelog/`. RMAN auto-creates parent dirs for datafiles during restore, but NOT for online logs on CREATE LOGFILE.
- **`standby_file_management=AUTO` during manual logfile operations → ORA-01275.** Safe pattern: `MANUAL` before manipulation, `AUTO` after. Do NOT leave it as MANUAL — primary may add a datafile in the future (e.g. ALTER TABLESPACE ... ADD DATAFILE) and with MANUAL on standby Oracle won't create the local datafile → MRP stalls.

---

### FIX-048 — ORA-00918 STATUS column ambiguously specified in section 8c verify query

**Problem:** `duplicate_standby.sh v3.0` after successful recreate of ORL+SRL (FIX-045+047) failed on the verify query:

```sql
SELECT thread#, group#, type, status FROM v$logfile l, v$log lv
                              *
ERROR at line 1:
ORA-00918: STATUS: column ambiguously specified - appears in V$LOG and V$LOGFILE
```

`WHENEVER SQLERROR EXIT FAILURE` was active → sqlplus exit code 1 → `set -e` in the script killed it BEFORE section 9 (bounce + OPEN RO + start MRP). Database state was OK (recreate completed, AUTO restored), but the open + apply was missing.

**Diagnosis:** column `status` exists in **both** views:
- `v$logfile` has `status` (INVALID/STALE/DELETED/IN USE) — info about the file
- `v$log` has `status` (UNUSED/CURRENT/ACTIVE/INACTIVE) — info about the group

Join `v$logfile l, v$log lv WHERE l.group#=lv.group#` leaves ambiguity about which `status` to select.

**Fix `scripts/duplicate_standby.sh` v3.1:**

Split into 2 queries without join (cleaner than alias prefixes; ORL and SRL are two different views, easier to treat separately):

```sql
SELECT thread#, group#, bytes/1024/1024 AS mb, status FROM v$log ORDER BY thread#, group#;
SELECT thread#, group#, bytes/1024/1024 AS mb, status FROM v$standby_log ORDER BY thread#, group#;
SELECT COUNT(*) AS srl_total FROM v$standby_log;
```

**Recovery for current run (when script already failed on FIX-048):** database state is OK (MOUNT, ORL/SRL recreated, AUTO restored). Just manually run section 9:

```sql
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;   -- if MRP running from previous attempt (ORA-10456)
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
```

**Lesson (universal):**
- **Verify queries under `WHENEVER SQLERROR EXIT FAILURE` must be tested.** A bug in SELECT (ORA-00918, ORA-00904, ORA-00942) kills the script — and that's after executing transactional changes (recreate in this case), so there's no "rollback to safe state". Better to place verify under `WHENEVER SQLERROR CONTINUE` (verify is read-only, shouldn't kill the script).
- **Join on `v$log + v$logfile` via `group#` always provokes ORA-00918 if SELECT contains columns sharing names.** Safer: 2 separate queries or alias prefixes.
- **`v$log.status` vs `v$logfile.status` are different enumerations** — easy to confuse during quick debugging. `v$log` is about the group (CURRENT/ACTIVE), `v$logfile` is about the file (INVALID/STALE).

---

### FIX-049 — `log_archive_dest_2` on primary not automated by script → MRP `WAIT_FOR_LOG` forever

**Problem:** After DONE of `duplicate_standby.sh v3.1`, MRP on stby01 was stuck in state:
```
PROCESS   STATUS                  THREAD#  SEQUENCE#
MRP0      WAIT_FOR_LOG                  1         30
```

No RFS process, `v$archived_log` empty, `v$dataguard_stats apply lag` empty. Diagnostics on primary:

```sql
SELECT dest_id, status FROM v$archive_dest_status WHERE dest_id IN (1,2);
   DEST_ID STATUS
         1 VALID
         2 INACTIVE        ← log_archive_dest_2 empty

SHOW PARAMETER log_archive_dest_2
log_archive_dest_2                   string         ← no value
```

Primary had no transport configured → MRP was waiting for sequence 30 that primary never sent.

**Diagnosis:** Script `duplicate_standby.sh` automated only the **auxiliary** (STBY) side: tnsnames, listener.ora, init.ora, RMAN duplicate, ORL/SRL recreate, OPEN+MRP. The **primary** (PRIM) side must have:
```sql
ALTER SYSTEM SET log_archive_dest_2='SERVICE=STBY ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILE,PRIMARY_ROLE) DB_UNIQUE_NAME=STBY' SCOPE=BOTH SID='*';
ALTER SYSTEM SET log_archive_dest_state_2='ENABLE' SCOPE=BOTH SID='*';
```

Doc 09 section 4.2 described this, but as a **manual step** BEFORE RMAN duplicate. That was wrong for two reasons:
1. Easy to skip when running the script quickly
2. Executing BEFORE RMAN duplicate → STBY listener not yet started → `v$archive_dest_status STATUS=ERROR` (misleading message)

**Fix `scripts/duplicate_standby.sh` v3.2:**

New **section 9b** AFTER start MRP on STBY (section 9), BEFORE final DONE log:

```bash
log "Section 9b — Configure log_archive_dest_2 on primary (FIX-049)..."
ssh -o StrictHostKeyChecking=no oracle@prim01 \
    ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<'EOF'
ALTER SYSTEM SET log_archive_dest_2='SERVICE=STBY ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILE,PRIMARY_ROLE) DB_UNIQUE_NAME=STBY' SCOPE=BOTH SID='*';
ALTER SYSTEM SET log_archive_dest_state_2='ENABLE' SCOPE=BOTH SID='*';
ALTER SYSTEM ARCHIVE LOG CURRENT;
SELECT dest_id, status, error, gap_status FROM v$archive_dest_status WHERE dest_id IN (1,2);
EOF
```

Why ASYNC NOAFFIRM, not SYNC AFFIRM? **MaxPerformance baseline** is standard for a fresh standby (apply lag tolerable, primary doesn't block on commit). MaxAvailability (SYNC AFFIRM) will be enabled in doc 10 via DG broker `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability` — broker changes parameters itself. Manual SYNC AFFIRM before broker enable → management conflict.

**Fix to `09_standby_duplicate.md` section 4.2:**
- Box `📌 FIX-049`: "Script v3.2+ does this automatically in section 9b. If doing manually — execute AFTER RMAN duplicate + start MRP, not before."
- Changed SYNC AFFIRM → ASYNC NOAFFIRM (with rationale: doc 10 will switch it)
- Added SID='*' (RAC: distributes to both instances)

**Result in user environment** after manually running section 9b:
```
DEST_ID    STATUS    GAP_STATUS
2          VALID     NO GAP
MRP0       APPLYING_LOG       1   33
RFS        IDLE               1   33
RFS        IDLE               2    9
transport lag    +00 00:00:00
apply lag        +00 00:00:00
OPEN_MODE        READ ONLY WITH APPLY
```

**Lesson (universal):**
- **Active duplicate scripts by default configure only the aux side.** Easy to miss that primary also needs configuration (`log_archive_dest_2`, optionally `db_file_name_convert` on primary for switchover-readiness). A cluster script must handle **both sides**.
- **Order: STBY OPEN+MRP ready → ONLY THEN configure primary log_archive_dest_2.** If reversed (dest_2 ENABLE before STBY OPEN) → primary ARCH/LGWR can't connect → STATUS=ERROR, alert.log spammed with ORA-12541. Looks like a failure but it's just wrong ordering.
- **MaxPerformance (ASYNC NOAFFIRM) baseline, MaxAvailability (SYNC AFFIRM) via DG broker.** Don't set SYNC AFFIRM manually before broker enable — broker manages this parameter and will overwrite, but during the conflict possible commit blocking.

---

### FIX-050 — `duplicate_standby.sh` v3.3: `PRIM_ADMIN`/`STBY_ADMIN` aliases + `LISTENER_DGMGRL` 1522

**Problem:** After `duplicate_standby.sh` v3.2, stby01 and prim01/02 did not have `PRIM_ADMIN`/`STBY_ADMIN` aliases in tnsnames, nor listener `LISTENER_DGMGRL` on port 1522 — required by `configure_broker.sh` (doc 10) and `setup_observer_infra01.sh` (doc 11). Script v3.2 overwrote listener.ora and tnsnames.ora without these elements (doc 07 section 8 left them in fresh DB software install, but RMAN flow lost them).

**Diagnosis after doc 09 17:55:**
- tnsnames stby01: `PRIM`, `STBY`, `PRIM_DGMGRL`, `STBY_DGMGRL` — missing `PRIM_ADMIN`, `STBY_ADMIN`
- tnsnames prim01/02: `STBY`, `STBY_DGMGRL` (from section 3b v3.2) — missing `PRIM_ADMIN`, `STBY_ADMIN`
- listener stby01: only `LISTENER` on 1521, missing `LISTENER_DGMGRL` 1522 (doc 07 section 8.1 had it)
- `configure_broker.sh` v1.0 calls `dgmgrl @PRIM_ADMIN` and `sqlplus @STBY_ADMIN` → TNS-12154 alias not found

**Fix `scripts/duplicate_standby.sh` v3.3:**

1. **Section 3** (tnsnames stby01) — added `PRIM_ADMIN` (port 1522, prim01+prim02 ADDRESS_LIST, SERVICE_NAME=PRIM_DGMGRL UR=A) and `STBY_ADMIN` (port 1522, stby01, SERVICE_NAME=STBY_DGMGRL UR=A). Pattern from doc 07 section 8.

2. **Section 3b** — `STBY_ALIAS_FRAGMENT` → `DGMGRL_ALIAS_FRAGMENT` (extended with `PRIM_ADMIN` and `STBY_ADMIN`). Function `deploy_stby_alias` renamed to `deploy_dgmgrl_aliases`. Idempotency check now on `^STBY_ADMIN[[:space:]]*=` (full set instead of just STBY).

3. **Section 4** (listener.ora stby01) — added second section `LISTENER_DGMGRL` on port 1522 + `SID_LIST_LISTENER_DGMGRL` with GLOBAL_DBNAME=STBY_DGMGRL. Added `lsnrctl start LISTENER_DGMGRL` after `lsnrctl start`.

**Firewall:** disabled in lab (user decision 2026-04-26). Script does not call `firewall-cmd`. For production, uncomment the comment in the script (port 1522).

**Patch runbook (running environment after doc 09):**

```bash
# 1. tnsnames stby01 + prim01/02 (as oracle, append to $ORACLE_HOME/network/admin/tnsnames.ora)
ssh oracle@stby01 "cat >> \$ORACLE_HOME/network/admin/tnsnames.ora <<'TNS_EOF'
PRIM_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1522))
    (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM_DGMGRL)(UR = A))
  )
STBY_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY_DGMGRL)(UR = A))
  )
TNS_EOF"
# Analogously for prim01 and prim02 — append to /u01/app/oracle/product/23.26/dbhome_1/network/admin/tnsnames.ora

# 2. listener.ora stby01 + start LISTENER_DGMGRL (as oracle)
ssh oracle@stby01 "cat >> \$ORACLE_HOME/network/admin/listener.ora <<'LSN_EOF'
LISTENER_DGMGRL =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    )
  )
SID_LIST_LISTENER_DGMGRL =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = STBY_DGMGRL)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = STBY)
    )
  )
LSN_EOF
lsnrctl start LISTENER_DGMGRL"

# 3. listener.ora prim01/02 (as grid, Grid Home) — manual in doc 10 section 1.1
```

**Lesson (universal):**
- **"Rebuild from scratch" scripts must leave the environment ready for the NEXT pipeline step**, not just the one they describe. `duplicate_standby.sh` was scoped for doc 09 (RMAN duplicate) and left state good for doc 09 — but lost elements needed in doc 10 (broker). Today the final listener.ora and tnsnames.ora are 50% of the script scope — tnsnames and listener config are **shared resources** used by all subsequent documents.
- **`SERVICE_NAME` in SID_LIST_LISTENER doesn't respect db_domain** — uses `GLOBAL_DBNAME` literally. Therefore `STBY_DGMGRL` (without `.lab.local`) is correct here, as opposed to `STBY.lab.local` which required db_domain handling.

---

### FIX-051 — `configure_broker.sh` v2.0: pre-flight + verify SUCCESS + die-on-fail

**Problem:** v1.0 (64 lines) had a safety gap:
- No pre-flight (tnsping aliases, listener 1522 status, role check, FORCE_LOGGING)
- `dgmgrl <<EOF ... EOF` without capturing stdout → no verify "Configuration Status: SUCCESS"
- No verify SYNC AFFIRM after `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability`
- Silent fail on ORA-12154 (PRIM_ADMIN doesn't exist) — exit 0 + `log "DONE"`

**Fix `scripts/configure_broker.sh` v2.0 (rewrite, ~250 lines):**

1. **Section 0 — pre-flight (HARD die-on-fail):**
   - `whoami=oracle`, `hostname=prim01`
   - `SQL_DIR=${SQL_DIR:-/tmp/sql}` exists + `fsfo_check_readiness.sql` in it
   - `tnsping PRIM_ADMIN` and `STBY_ADMIN` — die with hint to doc 10 section 1.1 (manual deploy listener Grid Home)
   - Call `<repo>/sql/fsfo_check_readiness.sql` → grep FAIL on critical checks (force_logging, archivelog, flashback, broker)
   - SSH oracle@stby01 sanity: PHYSICAL STANDBY, READ ONLY WITH APPLY

2. **Section 1 — dg_broker_start=TRUE** on PRIM (SID='*', RAC) and STBY (via `@STBY_ADMIN`). Sleep 15. Verify DMON via `gv$managed_standby` count ≥ 1.

3. **Section 2 — CREATE/ADD/ENABLE with verify**:
   - Idempotently: if `SHOW CONFIGURATION` returns SUCCESS, skip CREATE+ADD+ENABLE (verify-only mode).
   - Output to `/tmp/dgmgrl_enable.log`, `grep -q "Configuration Status:.*SUCCESS"` → die if missing.

4. **Section 3 — MaxAvailability + verify SYNC AFFIRM**:
   - `EDIT DATABASE PRIM/STBY SET PROPERTY LogXptMode='SYNC'` + `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability`
   - Output to `/tmp/dgmgrl_maxavail.log`
   - Two-level verify: dgmgrl SHOW CONFIGURATION contains "Protection Mode: MaxAvailability" + "Configuration Status: SUCCESS"
   - SQL verify: `v$archive_dest dest_id=2 transmit_mode=SYNCHRONOUS, affirm=YES` — die if broker didn't change automatically

**Lesson (universal):**
- **Pre-flight must die-on-fail** — `set -e` in bash isn't enough, because `dgmgrl` returns exit 0 despite ORA-12154 in stdout. Must capture to log and grep for expected pattern.
- **Broker idempotency** — `SHOW CONFIGURATION` before `CREATE` allows re-running the script after partial failure without REMOVE CONFIGURATION.
- **DG broker manages `log_archive_dest_2` automatically after `SET PROTECTION MODE`** — don't set SYNC AFFIRM manually before broker (FIX-049 sets ASYNC NOAFFIRM as MaxPerformance baseline, broker switches to SYNC AFFIRM at MaxAvailability).

---

### FIX-052 — `deploy_tac_service.sh` v1.1: pre-flight `tac_full_readiness.sql` + de-hardcode + post-flight verify

**Problem:** v1.0 (71 lines):
- No pre-flight (PRIM OPEN check, APPPDB registered, TAC readiness)
- Hardcoded `stby01.lab.local:6200` in `srvctl modify ons -remoteservers`
- No post-flight verify that TAC parameters were actually saved

**Fix `scripts/deploy_tac_service.sh` v1.1:**

1. **Section 0 pre-flight:**
   - `srvctl status database -db PRIM` → "Instance PRIM1/PRIM2 is running" (die if missing)
   - `lsnrctl services | grep -E "Service \"APPPDB"` (die if PDB not registered)
   - `sqlplus @${SQL_DIR}/tac_full_readiness.sql` (12 checks) — heuristic: ≥8 PASS for go-live, die if critical checks (FORCE_LOGGING, archivelog, EE, broker, TAC service, commit_outcome) FAIL

2. **De-hardcode** STBY_HOST:
   ```bash
   STBY_HOST=$(ssh oracle@stby01 hostname -f 2>/dev/null || echo stby01.lab.local)
   srvctl modify ons -clusterid PRIM -remoteservers "${STBY_HOST}:6200"
   ```

3. **Post-flight verify** (section 3):
   - `srvctl config service -db PRIM -service MYAPP_TAC` → grep `failover_type:.*TRANSACTION` + `commit_outcome:.*true` (case-insensitive). Die if missing.

**Lesson (universal):**
- **`srvctl add service` returns exit 0 even when a parameter was ignored** (e.g. `-failovertype` in an older srvctl version). Post-flight `srvctl config service` + grep on expected values is the only reliable validation.
- **De-hardcode hostnames** — even in lab the habit of `$(ssh node hostname -f)` protects against mistakes when hostname changes (rebrand / migration).

---

### FIX-053 — `setup_observer_infra01.sh` v1.1: die-on-fail + observer name variable + post-flight verify

**Problem:** v1.0 (193 lines):
- `|| log "WARN"` at dgmgrl commands (FSFO properties, ADD OBSERVER, ENABLE FAST_START FAILOVER) → silent fail, script returns exit 0 even when FSFO Status=DISABLED
- Hardcoded `obs_ext` in 6 places — makes it difficult to set up backup observers (`obs_dc`, `obs_dr`) from doc 16 (where previously had to manually copy+sed the script)
- No post-flight verify (FSFO ENABLED, systemctl active)

**Fix `scripts/setup_observer_infra01.sh` v1.1:**

1. **All `|| log "WARN"` → `|| die`** for critical commands (FSFO properties, ADD OBSERVER, SET MASTEROBSERVER, ENABLE FAST_START FAILOVER, sqlplus connectivity test).

2. **Pre-flight tnsping** (after wallet setup):
   - `tnsping PRIM_ADMIN` and `STBY_ADMIN` from infra01 — die with hint to doc 10 section 1.1 (listener Grid Home) and `duplicate_standby.sh` v3.3+ (listener stby01 + aliases).

3. **Observer name variable**:
   ```bash
   OBSERVER_NAME="${OBSERVER_NAME:-obs_ext}"
   ```
   All `obs_ext` in ADD OBSERVER, SET MASTEROBSERVER, systemd unit name, log file path, ExecStart/ExecStop → `${OBSERVER_NAME}`. Override-able for doc 16:
   ```bash
   OBSERVER_NAME=obs_dc sudo bash setup_observer_infra01.sh   # backup observer on infra01 or another VM
   ```

4. **Post-flight verify** (section 9):
   - `dgmgrl SHOW FAST_START FAILOVER` contains `Status: ENABLED` (regex also matches variant "Fast-Start Failover: ENABLED")
   - `systemctl is-active --quiet dgmgrl-observer-${OBSERVER_NAME}` (boolean check)
   - Die with hint `journalctl -u <unit>` if systemd not active.

**Lesson (universal):**
- **`|| log "WARN"` in a production script is debt** — either the error is harmless and shouldn't be a warning, or it's serious and should die. "warn-and-continue" masks problems that will surface in doc 14 tests (e.g. "FSFO doesn't failover — but the script said DONE!").
- **Variables instead of hardcode** — even if the default is sufficient 99% of the time, the override-able pattern eliminates all duplicate-and-modify boilerplate.

---

### FIX-054 — `validate_env.sh` v1.1: SQL_DIR wrapper + `--quick`/`--full`

**Problem:** v1.0 (44 lines) called a non-existent `bash/validate_all.sh` from `PROJECT_DIR/bash/`. Dead link.

**Fix `scripts/validate_env.sh` v1.1 (rewrite ~70 lines):**

- Thin wrapper on `<repo>/sql/*.sql` with `SQL_DIR=${SQL_DIR:-/tmp/sql}`
- Argument parsing: `--quick` (default) / `--full`, `-t PRIM|STBY` (default PRIM)
- **--quick:** `validate_environment.sql` (12 combined FSFO+TAC checks). Exit heuristic: count `\bFAIL\b` in output, die if ≥1.
- **--full:** additionally `tac_full_readiness.sql` + `fsfo_monitor.sql` + `fsfo_broker_status.sql` → `${REPORTS_DIR:-/tmp/reports}/<sql>_<target>_<timestamp>.log`.
- Connect: PRIM = `/ as sysdba`, STBY = `sys/Welcome1#SYS@STBY_ADMIN as sysdba`.

**Lesson:** **Dead links in MD have a cognitive cost** — the operator sees a reference to a script that doesn't exist and loses 10 minutes checking. Clean up during MD-script sync.

---

### FIX-055 — Rename HH→DC, OE→DR in 4 MD files under VMs/

**Goal:** Unify site naming (Data Center / Disaster Recovery / EXT) with production convention. Whitelist: `08_database_create_primary.md:210` (`Without HR/SH/OE/PM` refers to Sample Schemas Order Entry, not a site name).

**Files changed:**
- `00_architecture.md` (section 2.1 sites): `Site HH` → `Site DC`, `Site OE` → `Site DR`, `obs_hh` → `obs_dc`, `obs_oe` → `obs_dr`
- `LOG.md`: 3-site MAA topology mentions
- `PLAN-dzialania.md`: 6 occurrences (VM3 description, mapping table, observers row, sample schemas, branching diagram)
- `16_extensions.md`: section A (backup observers) — all `obs_hh`/`obs_oe` → `obs_dc`/`obs_dr` in mkdir/wallet/systemd/dgmgrl commands

**Out of scope (deliberate):** renames in `<repo>/sql/`, `<repo>/docs/`, `<repo>/README.md`. These retain `HH`/`OE` (lab documents a simplification from production, where names may differ). User: "Treat only VMs/, sql/ as `<repo>` read-only".

**Lesson:** Global sed renames in narrative-heavy MDs are risky. The whitelist line (Sample Schema OE) shows that terms like HH/OE/DR/DC have multiple contexts. Safer: targeted Edit with clear before/after context.

---

### FIX-056 — `<repo>/sql/` integration in VMs/scripts/ + SQL_DIR convention

**Goal:** Use 8 mature SQL files (`fsfo_check_readiness`, `fsfo_configure_broker`, `tac_full_readiness`, `validate_environment`, `fsfo_monitor`, `fsfo_broker_status`, `tac_replay_monitor`, `tac_configure_service_rac`) as pre-flight + post-flight engines in bash scripts. Without duplicating logic.

**Convention:**

- **Bash scripts (on VM):** `SQL_DIR="${SQL_DIR:-/tmp/sql}"` — default `/tmp/sql`, override-able. Each script validates `[[ -d $SQL_DIR ]]` and dies with hint to doc 04 section 0.
- **MD documents (on host):** `<repo>/sql/` (where `<repo>` = `D:/__AI__/_oracle_/20260423-FSFO-TAC-guide/`).

**Mapping:**

| SQL | Used in | Purpose |
|---|---|---|
| `fsfo_check_readiness.sql` | `configure_broker.sh` v2.0 section 0 | Pre-flight broker (6 sections) |
| `tac_full_readiness.sql` | `deploy_tac_service.sh` v1.1 section 0 | Pre-flight TAC (12 checks) |
| `validate_environment.sql` | `validate_env.sh --quick` | 12 combined FSFO+TAC checks |
| `fsfo_monitor.sql`, `fsfo_broker_status.sql` | `validate_env.sh --full` | Post-deploy diagnostics |
| `fsfo_configure_broker.sql`, `tac_configure_service_rac.sql` | (potential `--dry-run`) | dgmgrl/srvctl command generators |
| `tac_replay_monitor.sql` | (manual in doc 14) | Replay statistics |

**Deployment:** manual SCP `<repo>/sql/` → `/tmp/sql/` on **prim01** and **infra01** (new section 0 in doc 04). Existing workflow `<repo>/VMs/scripts/` → `/tmp/scripts/` via MobaXterm unchanged — adds 1 directory.

**Lesson:** **Code reuse via SQL calls from bash instead of copying** maintains single-source-of-truth. SQL scripts in `<repo>/sql/` are documented, have DEFINE parameters, work standalone in sqlplus for manual debugging — bash scripts enrich them with orchestration (SSH, capture+grep, exit codes). No duplication.

---

### FIX-057 — `sqlplus @file.sql` hangs when file has no `EXIT` at the end

**Problem:** `configure_broker.sh` v2.0 (FIX-051) hung at section 0.3 pre-flight when calling `<repo>/sql/fsfo_check_readiness.sql`:

```
[20:43:50]   Running /tmp/sql/fsfo_check_readiness.sql...
(no further output for 6+ minutes)
```

**Diagnosis** via second sqlplus session on primary:

```sql
SELECT sid, status, event, seconds_in_wait FROM v$session
WHERE program LIKE 'sqlplus%' AND username='SYS';

-- Result:
-- SID 298 INACTIVE 'SQL*Net message from client' 403 sec
```

`INACTIVE` with `SQL*Net message from client` for 403s = sqlplus executed the SQL script and **is waiting for the next command from the client**, the session didn't end. The bash wrapper reading the output (`$(sqlplus ... )`) hung on `wait`.

**Cause:** All SQL scripts in `<repo>/sql/` (`fsfo_check_readiness.sql`, `tac_full_readiness.sql`, `validate_environment.sql`, `fsfo_monitor.sql`, `fsfo_broker_status.sql`, `tac_replay_monitor.sql`, `fsfo_configure_broker.sql`, `tac_configure_service_rac.sql`) **end with a `PROMPT` sequence** (without `EXIT`/`QUIT`/`/`):

```sql
PROMPT  Readiness check complete. Review results above.
PROMPT  ================================================================================
-- (end of file)
```

This is intentional — files are designed to run **interactively in sqlplus** (where the operator wants to stay in session to drill down further). User confirmed: treat `<repo>/sql/` as read-only.

Calling `sqlplus @file.sql` never ends — sqlplus after processing the file waits for input from STDIN (which is empty here because called via `$(...)` with no heredoc).

**Fix — call via heredoc with explicit `EXIT`:**

```bash
# Old version (hangs):
RES=$(sqlplus -s / as sysdba @"$SQL_DIR/fsfo_check_readiness.sql" 2>&1)

# New version (works):
RES=$(sqlplus -s / as sysdba <<SQLEOF 2>&1
@$SQL_DIR/fsfo_check_readiness.sql
EXIT
SQLEOF
)
```

The `<<SQLEOF ... SQLEOF` pattern (unquoted heredoc tag — variables expand) allows injecting `EXIT` after `@file.sql`. sqlplus executes the file (path resolved from `$SQL_DIR`) then gets `EXIT` from STDIN and exits.

**Scripts updated:**
- `configure_broker.sh` v2.0 → **v2.1** (section 0.3 fsfo_check_readiness)
- `deploy_tac_service.sh` v1.1 → **v1.2** (section 0 tac_full_readiness)
- `validate_env.sh` v1.1 → **v1.2** (--quick and --full path)

**Lesson (universal):**
- **`sqlplus @file.sql` from bash only works if the file ends with `EXIT`.** Otherwise — heredoc with explicit `EXIT`. Same applies to `sqlplus / as sysdba @file` from command line.
- **Don't modify project SQL files (read-only, not ours)** to add `EXIT` — wrap the call in a bash wrapper.
- **"Script hung" diagnosis**: always check `v$session WHERE program LIKE 'sqlplus%'`. `INACTIVE + SQL*Net message from client = sqlplus idle, waiting for input`. `ACTIVE + any event = legitimate query execution`.

---

### FIX-058 — `configure_broker.sh` pre-flight chicken-and-egg on `dg_broker_start=FALSE`

**Problem:** After FIX-057 (sqlplus heredoc EXIT), `fsfo_check_readiness.sql` ran quickly, output was 95% healthy, but section 6 summary of the script returned:

```
DG Broker    FAIL    dg_broker_start=FALSE
```

This is the **expected** state before enable (script `configure_broker.sh` only enables broker in section 1). Heuristic in v2.1 section 0.3:

```bash
if echo "$READINESS_OUT" | grep -E 'FAIL.*(force_logging|archivelog|flashback|broker)' -i >/dev/null; then
    die "Critical checks FAIL..."
fi
```

→ matched `FAIL.*broker` → die **before** section 1 (where broker is enabled). Classic chicken-and-egg.

**Fix `scripts/configure_broker.sh` v2.2:**

Removed `broker` from the critical patterns. Remaining is a sensible set of things that **MUST** be in place before broker makes any sense:

```bash
if echo "$READINESS_OUT" | grep -E 'FAIL.*(force[_ ]logging|archivelog|flashback|standby[_ ]file[_ ]management)' -i >/dev/null; then
    die "..."
fi
```

`standby_file_management=AUTO` stays — because broker `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability` assumes standby auto-creates datafiles from primary.

**Lesson:** **Pre-flight should not check what the script itself is about to set** — that's a logical design error (gate checks the effect of its own action). Pre-flight = checks **prereqs from the previous doc** (doc 08 pre-broker), not its own output.

---

### FIX-059 — Missing SSH equivalency `oracle@prim01` → `oracle@stby01` blocks `configure_broker.sh` section 0.4

**Problem:** After SCP of `configure_broker.sh` v2.2 and running it, section 0 pre-flight passed ✓ (tnsping, fsfo_check_readiness), but the script **died silently** after:

```
[hh:mm:ss]   ✓ fsfo_check_readiness.sql passed
[hh:mm:ss]   Sanity check STBY (via ssh oracle@stby01)...
(prompt returns, no further lines)
```

**Diagnosis:**
```bash
su - oracle -c 'ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no oracle@stby01 hostname'
# Permission denied, please try again.
# oracle@stby01: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password).
```

Missing SSH equivalency `oracle@prim01` → `oracle@stby01`. Doc 04 section 6 historically covered only **prim01 ↔ prim02** (Grid + oracle, for Grid Infrastructure). FIX-038 #3 added `oracle@stby01` → `oracle@prim01` (for duplicate_standby.sh sanity primary + scp pwfile). The **reverse direction `prim01` → `stby01`** was considered unnecessary — because doc 09 and 10 manual steps didn't require it (only scripts did).

**Section 0.4 of `configure_broker.sh` v2.0+ does:**
```bash
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 oracle@stby01 \
    ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<EOF
SELECT 'ROLE='||database_role... FROM v\$database;
EOF
```

Without SSH keys this command returns "Permission denied" → grep doesn't match `ROLE=PHYSICAL STANDBY` → `die "STBY not in role..."`. The `die` output should go to stderr and be visible in `tee /tmp/broker_run.log` — but in some edge cases (`set -euo pipefail` + ssh exit code) the script dies without a readable message.

**Fix to `04_os_preparation.md` section 6 (rewritten):**

1. **Title** changed from "prim01 ↔ prim02" to **"full mesh for 3 DB nodes"**.
2. **Table of 5 SSH sets** with explicit "which doc requires it" — Grid (set 1+2 prim↔prim), duplicate_standby.sh (set 3 stby→prim), configure_broker.sh / deploy_tac_service.sh (set 4 prim01→stby01), optional set 5 (prim02→stby01).
3. **New section 6.4** "SSH oracle ↔ stby01 (full mesh DB nodes)" — Step A (stby→prim, FIX-038 #3), Step B (prim01→stby, FIX-059), Step C (prim02→stby, optional). Each with `ssh-copy-id` + test.
4. **New section 6.5** verification — bash loop testing all required directions.
5. Added tip: when operator doesn't know `oracle@stby01` password → `passwd oracle` as root, after `ssh-copy-id` password can be locked (`passwd -l oracle`).

**Cross-refs added:**
- `09_standby_duplicate.md` Prereq — link to doc 04 section 6.4 Step A
- `10_data_guard_broker.md` Prereq — link to doc 04 section 6.4 Step B + FIX-059 note

**Lesson (universal):**
- **SSH equivalency is a graph, not a line.** Start with cluster (prim01 ↔ prim02) because that's a Grid requirement. Each new script that does `ssh user@host` adds a **new direction** to the mesh. Must treat it as a matrix — each cell documented, each direction tested.
- **Scripts CANNOT automate ssh-copy-id** — requires the target user's password. This is deliberate Oracle security (security by design). Manual step always, once.
- **Silent fail with `set -euo pipefail` + `2>&1 | tee`**: when script dies inside `$(ssh ... <<EOF)` heredoc, stderr output may not always reach tee. Better to add `set -x` in critical sections for debug.

---

### FIX-060 — `configure_broker.sh` v2.2 false "DMON not started" (wrong view: `v$managed_standby` instead of `gv$process`)

**Problem:** After FIX-058/059 script v2.2 reached section 1, `ALTER SYSTEM SET dg_broker_start=TRUE` succeeded (output shows `dg_broker_start TRUE` on PRIM and STBY), but after sleep 15s the script died:

```
[hh:mm:ss]   ✓ dg_broker_start=TRUE on STBY
[hh:mm:ss]   Sleep 15s — waiting for DMON process to start...
[hh:mm:ss] ERROR: DMON process did not start on PRIM (count=0)
```

**Diagnosis:** Query in v2.2:
```sql
SELECT COUNT(*) FROM gv$managed_standby WHERE process='DMON';
```

`v$managed_standby` (`gv$managed_standby` on RAC) is a view with **redo transport / apply** processes — `MRP0`, `RFS`, `LNS`, `NSS`, `ARCH`, `LGWR`. **DMON does not exist there** — DMON is a **Data Guard Broker background process**, listed in `v$process` / `v$bgprocess`.

After `ALTER SYSTEM SET dg_broker_start=TRUE`, Oracle starts DMON automatically (one per instance) — visible in:
```sql
SELECT inst_id, pname FROM gv$process WHERE pname='DMON';
-- or
SELECT inst_id, name FROM gv$bgprocess WHERE name='DMON' AND paddr<>'00';
-- or less restrictively
SELECT inst_id, program FROM gv$process WHERE program LIKE '%(DMON)%';
```

**Fix `scripts/configure_broker.sh` v2.3:**

Instead of a single query against the wrong view — two parallel checks:

```bash
DMON_OUT=$(sqlplus -s / as sysdba <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'DMON_PROC=' || COUNT(*) FROM gv$process WHERE program LIKE '%(DMON%)%' OR pname='DMON';
SELECT 'BROKER_PARAM=' || COUNT(*) FROM gv$parameter WHERE name='dg_broker_start' AND UPPER(value)='TRUE';
EXIT
EOF
)
```

Logic:
- `BROKER_PARAM` = number of RAC instances with `dg_broker_start=TRUE` (expected 2 for 2-node RAC). This is **must-pass**.
- `DMON_PROC` = number of active DMON background processes (expected 2). If <2 → only warn + extra sleep 10s (not die). First broker enable may need 20–30s before DMON stabilizes.

**Lesson (universal):**
- **Oracle views layered:** `v$managed_standby` = redo transport/apply. `v$process` = all DB processes (server + background). `v$bgprocess` = named background processes (DMON, MMON, SMON, PMON, LGWR…). DMON is type BG, not standby.
- **Verify boolean parameter is safer fallback** than checking the process — parameter is set deterministically after `ALTER SYSTEM`, process starts asynchronously with slight delay.

---

### FIX-061 — DGMGRL `ADD DATABASE ... MAINTAINED AS PHYSICAL` syntax error in 23ai/26ai

**Problem:** v2.3 section 2 executed:
```
DGMGRL> CREATE CONFIGURATION PRIM_DG AS PRIMARY DATABASE IS PRIM CONNECT IDENTIFIER IS PRIM_ADMIN;
Configuration "prim_dg" created with primary database "prim"

DGMGRL> ADD DATABASE STBY AS CONNECT IDENTIFIER IS STBY_ADMIN MAINTAINED AS PHYSICAL;
                                                              ^
Syntax error before or at "MAINTAINED"

DGMGRL> ENABLE CONFIGURATION;
Enabled.
(but ENABLE went through with only PRIM - STBY was never added)
```

Result: configuration in WARNING state:
```
Configuration - prim_dg
  Protection Mode: MaxPerformance
  Members:
  PRIM - Primary database
    Warning: ORA-16532: Oracle Data Guard broker configuration does not exist.
Configuration Status: WARNING
```

**Diagnosis:** `MAINTAINED AS LOGICAL|PHYSICAL` was used in 19c/12c to distinguish Logical vs Physical Standby in ADD DATABASE. In 23ai/26ai the syntax changed — the `MAINTAINED` clause was **removed** (Physical is the default; for Logical/Snapshot dedicated commands `ADD LOGICAL STANDBY` / `CONVERT DATABASE` are used). Oracle 23ai DGMGRL Reference gives:
```
ADD DATABASE database-name [AS CONNECT IDENTIFIER IS connect-identifier]
```
without `MAINTAINED AS`.

**Fix `scripts/configure_broker.sh` v2.4:**

Removed `MAINTAINED AS PHYSICAL`:
```sql
-- v2.3 (broken in 26ai):
ADD DATABASE STBY AS CONNECT IDENTIFIER IS STBY_ADMIN MAINTAINED AS PHYSICAL;

-- v2.4 (works in 26ai):
ADD DATABASE STBY AS CONNECT IDENTIFIER IS STBY_ADMIN;
```

**Cleanup after failed run (manual before re-running script):**

```sql
-- On prim01 as oracle
dgmgrl /
DISABLE CONFIGURATION;
REMOVE CONFIGURATION PRESERVE DESTINATIONS;
EXIT
```

`PRESERVE DESTINATIONS` retains `log_archive_dest_2` on PRIM (FIX-049 set ASYNC NOAFFIRM) — without it REMOVE would also clear log transport.

After cleanup → SCP `configure_broker.sh` v2.4+ → run again. Section 2 idempotency check will see `ORA-16532 configuration does not exist` → runs `CREATE/ADD/ENABLE` fresh.

**Lesson (universal):**
- **DGMGRL syntax migration 19c → 23ai/26ai** — Oracle removed several clauses (`MAINTAINED AS`, `INSTANCE` for static services). Scripts written for 19c won't run on 26ai without adjustment. Always test syntax when migrating versions.
- **Partial fail in `dgmgrl <<EOF` heredoc** is the worst class of error — sub-commands execute sequentially, one fails, next ones **proceed with broken configuration status**. dgmgrl exit code in a heredoc ends as 0 despite syntax error → bash wrapper sees "OK" and only dies at verify SUCCESS. A configuration in WARNING/ERROR remains — requires manual REMOVE.
- **REMOVE CONFIGURATION PRESERVE DESTINATIONS** — safe for cleanup, doesn't lose log_archive_dest_2 on primary (FIX-049 work).

---

### FIX-062 — `ENABLE CONFIGURATION` ORA-16905 requires retry (broker synchronizes members ~30–60s)

**Problem:** v2.4 section 2 executed correctly:
```
Configuration "prim_dg" created with primary database "prim"
Database "stby" added
Enabled.
```

But immediate `SHOW CONFIGURATION` returned:
```
Configuration - prim_dg
  Members:
  PRIM - Primary database
    Warning: ORA-16905: The member was not enabled.
  stby - Physical standby database
    Warning: ORA-16905: The member was not enabled.
Configuration Status: WARNING
```

Script died with "ENABLE CONFIGURATION failed".

**Diagnosis:** ORA-16905 = **transient state** of configuration propagation. `ENABLE CONFIGURATION` in dgmgrl returns immediately after committing to the broker config file (`+DATA/PRIM/dr1PRIM.dat`). The actual activation of members (DMON sends config to RFS on each node, members ack, broker sets state to `ENABLED`) takes **30–60s** in background.

`SHOW CONFIGURATION` during this window shows WARNING with ORA-16905 for each member. After ~30s it changes to `Configuration Status: SUCCESS`.

**Fix `scripts/configure_broker.sh` v2.5 — retry loop:**

```bash
log "  Waiting for broker to synchronize members (max 90s)..."
SUCCESS=0
for i in 1 2 3 4 5 6; do
    sleep 15
    STATUS_OUT=$(dgmgrl sys/...@PRIM_ADMIN <<EOF
SHOW CONFIGURATION;
EXIT
EOF
    )
    if echo "$STATUS_OUT" | grep -q "Configuration Status:.*SUCCESS"; then
        log "    ✓ Members enabled after ${i}x15s = $((i*15))s"
        SUCCESS=1
        break
    fi
    log "    Sample $i/6: not SUCCESS yet (waiting 15s)..."
done
[[ "$SUCCESS" -eq 1 ]] || die "..."
```

Max 90s to reach SUCCESS. Typically broker completes in 30–45s, so 1–3 iterations.

**Lesson (universal):**
- **DGMGRL commands of type ENABLE/DISABLE/EDIT are asynchronous** — they return OK after commit to config file, but actual propagation to members takes time. Verify must have retry with timeout.
- **ORA-16905 'member was not enabled'** is not an error, just a transient state. Never treat it as blocking in a script.
- **Other async dgmgrl ops where retry is worthwhile:** `EDIT CONFIGURATION SET PROTECTION MODE`, `ENABLE FAST_START FAILOVER`, `SWITCHOVER`. Each needs a sleep + verify loop.

---

### FIX-063 — `dg_broker_config_file{1,2}` on RAC primary must be shared (`+DATA`), not local FS

**Problem:** After FIX-061+062 broker passed CREATE+ADD+ENABLE, but `Configuration Status: WARNING` persisted >90s. STATUSREPORT showed the diagnosis:

```
DGMGRL> SHOW DATABASE prim STATUSREPORT;
       INSTANCE_NAME   SEVERITY   ERROR_TEXT
               PRIM1   (no error)
               PRIM2   ERROR      ORA-16532: Oracle Data Guard broker configuration does not exist.

DGMGRL> SHOW DATABASE stby STATUSREPORT;
       INSTANCE_NAME   SEVERITY   ERROR_TEXT
                STBY   (no error)
```

**Only PRIM2** reported ORA-16532. PRIM1 and STBY were OK. STBY could read/write its own `dr1STBY.dat` (local FS, SI), STBY also saw the remote config via DMON↔DMON. But **PRIM2 had no access to files written by PRIM1**.

**Diagnosis:** Broker parameters:
```sql
SHOW PARAMETER dg_broker_config_file
-- dg_broker_config_file1   /u01/app/oracle/product/23.26/dbhome_1/dbs/dr1PRIM.dat
-- dg_broker_config_file2   /u01/app/oracle/product/23.26/dbhome_1/dbs/dr2PRIM.dat
```

**These are local paths `$ORACLE_HOME/dbs/`** — **DBCA 26ai leaves them as default instead of setting `+DATA/<DB_UNIQUE_NAME>/`**. On **RAC**, broker config is **one file per database** (not per instance) — must be on shared storage so both RAC nodes can see it. PRIM1 created the file locally → PRIM2 had no access → ORA-16532.

Doc 10 section 2.1 mentioned this:
> "dg_broker_config_file{1,2} — on RAC +DATA, on SI /u01/app/oracle. NOTE: broker config file is SINGLE per database, not per instance!"

But nobody enforced this setting in the script or DBCA response file (FIX-028..035 didn't cover it).

**Fix `scripts/configure_broker.sh` v2.6:**

New **section 0.5** (between pre-flight and section 1 enable broker) — auto-detect + auto-fix for RAC primary:

```bash
DBCFG_OUT=$(sqlplus -s / as sysdba <<EOF
SELECT 'CFG1=' || value FROM v$parameter WHERE name='dg_broker_config_file1';
SELECT 'INSTANCES=' || COUNT(*) FROM gv$instance;
EOF
)
INSTANCES=$(echo "$DBCFG_OUT" | grep -oE 'INSTANCES=[0-9]+' | cut -d= -f2)
CFG1=$(echo "$DBCFG_OUT" | grep -oE 'CFG1=.*' | sed 's/^CFG1=//')

if [[ "$INSTANCES" -gt 1 ]] && [[ ! "$CFG1" =~ ^\+ ]]; then
    # RAC + local FS → fix
    dgmgrl ... 'DISABLE CONFIGURATION; REMOVE CONFIGURATION PRESERVE DESTINATIONS;'
    sqlplus / as sysdba <<EOF
ALTER SYSTEM SET dg_broker_start=FALSE SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file1='+DATA/PRIM/dr1PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file2='+DATA/PRIM/dr2PRIM.dat' SCOPE=BOTH SID='*';
EOF
    # Section 1 will then do ALTER SYSTEM SET dg_broker_start=TRUE
fi
```

**Manual cleanup + fix for user in WARNING state:**

```sql
-- On prim01 as oracle
dgmgrl /
DISABLE CONFIGURATION;
REMOVE CONFIGURATION PRESERVE DESTINATIONS;
EXIT

-- Sqlplus
ALTER SYSTEM SET dg_broker_start=FALSE SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file1='+DATA/PRIM/dr1PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file2='+DATA/PRIM/dr2PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_start=TRUE SCOPE=BOTH SID='*';
EXIT

-- (on STBY we leave local FS - SI, single instance)
```

After that CREATE CONFIGURATION again. Now both RAC instances will have access to the same file → enable members will pass to SUCCESS.

**Lesson (universal):**
- **RAC defaults vs requirements** — Oracle DBCA for RAC doesn't always set RAC-specific parameters (e.g. `dg_broker_config_file*`, `cluster_database_instances` for SI rebuild post-duplicate). Every parameter that has shared/per-instance significance MUST be explicit.
- **`SCOPE=BOTH SID='*'` as standard for RAC ALTER SYSTEM** — without `SID='*'` the change goes only to the current instance in SPFILE; with `SID='*'` to all instances. Critical here because RAC members must have the same parameter.
- **STATUSREPORT is the first debug step for broker WARNING** — shows per-instance errors, not just per-member. Without it we wouldn't see that only PRIM2 has the problem (PRIM1 and STBY OK).

---

### FIX-064 — `ENABLE CONFIGURATION` retry timeout 90s too short for VirtualBox lab

**Problem:** v2.5/v2.6 retry max 6×15s = 90s — broker in VirtualBox lab needed longer. Script died at "Sample 6/6: not SUCCESS yet", but 30–60 seconds later `SHOW CONFIGURATION` showed `Configuration Status: SUCCESS`. STATUSREPORT without errors.

**Diagnosis:** Broker internal loop (`drcSTBY.log`):

```
2026-04-26T21:35:55  Deleting broker configuration data on this member
2026-04-26T21:35:55  Contents of dr1STBY.dat / dr2STBY.dat has been deleted
2026-04-26T21:35:55  Starting task: ENABLE CONFIGURATION
2026-04-26T21:35:57  Apply Instance for Database stby set to STBY
2026-04-26T21:35:58  Updated broker configuration file (miv=5)
...
~21:39:00 (3 minutes after ENABLE) — Configuration Status: SUCCESS
```

VirtualBox with fileio iSCSI backstore (variant A) has slower IO than production — broker config-file roundtrip + member ack takes 90–150s instead of Oracle-doc-typical 30–45s.

**Fix `scripts/configure_broker.sh` v2.7:**

```bash
# v2.6 - 90s timeout (too short for lab):
for i in 1 2 3 4 5 6; do sleep 15; ... done

# v2.7 - 180s timeout:
for i in $(seq 1 12); do sleep 15; ... done
```

**Idempotency safety:** v2.7 (like all since v2.0) has in section 2 detection of existing SUCCESS and skips CREATE+ENABLE. So die after first timeout → re-run script → idempotency sees `Configuration Status: SUCCESS` → skip CREATE → proceeds to section 3 (MaxAvailability). Operator can safely retry without clearing configuration.

**Lesson (universal):**
- **Lab VirtualBox ≠ production** for async broker operations. Timeouts calibrated for production are often too short. 2–3× margin for lab is a safe default.
- **Idempotency = redundancy as safety** — when timeout is too aggressive, re-running saves the situation without losing work done so far.

---

### FIX-065 — Idempotency grep in `configure_broker.sh` doesn't match multiline dgmgrl output

**Problem:** After DONE in section 2 (Configuration Status: SUCCESS — manual verify confirmed), re-run of script v2.7 hit the branch:

```
[hh:mm:ss] WARN: Ambiguous broker state. Output:
Configuration - prim_dg
  Protection Mode: MaxPerformance
  Members:
  PRIM - Primary database
    stby - Physical standby database
Fast-Start Failover:  Disabled
Configuration Status:
SUCCESS   (status updated 19 seconds ago)
[hh:mm:ss] ERROR: Check manual SHOW CONFIGURATION and possibly REMOVE CONFIGURATION before retry.
```

**Diagnosis:** dgmgrl 23.26.1 outputs `SHOW CONFIGURATION` in multiline format:

```
Configuration Status:
SUCCESS   (status updated 19 seconds ago)
```

`Configuration Status:` on one line, `SUCCESS` on the **next**. My grep:

```bash
grep -q "Configuration Status:.*SUCCESS"
```

by default matches **within a single line** (without `-z` or multiline). So doesn't find SUCCESS, goes to `else` branch ("ambiguous state").

In 19c dgmgrl wrote on one line: `Configuration Status: SUCCESS (status...)`. **In 23ai/26ai the format changed to multiline.**

**Fix `scripts/configure_broker.sh` v2.8:**

Flatten output with `tr '\n' ' '` before grep, plus added branch for WARNING (transient state with extra 30s retry):

```bash
EXIST_FLAT=$(echo "$EXIST_OUT" | tr '\n' ' ' | tr -s ' ')

if echo "$EXIST_FLAT" | grep -qE "Configuration Status:[[:space:]]*SUCCESS"; then
    log "  Configuration already exists with SUCCESS status — skip CREATE/ADD/ENABLE"
elif echo "$EXIST_FLAT" | grep -qE "Configuration Status:[[:space:]]*WARNING"; then
    warn "WARNING — waiting 30s..."
    # ... retry ...
elif echo "$EXIST_FLAT" | grep -qE "ORA-16532|configuration does not exist"; then
    # CREATE
fi
```

Plus fixed grep in retry loop (section 2 ENABLE) and in section 3 verify (Protection Mode + Status). All 3 greps on dgmgrl output now use `tr | tr -s ' ' | grep -qE` pattern.

Section 3 verify for Status: SUCCESS also got a **retry loop** (max 90s) — because after `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability` the broker must propagate the protection mode change and SYNC+AFFIRM to members similarly to CREATE.

**Lesson (universal):**
- **dgmgrl 23ai/26ai output is multiline** — `SHOW CONFIGURATION`, `SHOW DATABASE`, `SHOW FAST_START FAILOVER` print "Field:" on one line and the value on the next. All bash scripts using grep on dgmgrl output must have `tr '\n' ' '` before grep (or `grep -z` for NULL-separated).
- **Idempotency = re-run safety** — good idempotency means "run again" always saves the situation. Here sections 0/0.5/1/2 v2.8 are idempotent (no-op when target state achieved), section 3 EDIT too (broker ignores overwriting the same LogXptMode).
- **`tr '\n' ' ' | tr -s ' '`** — first converts newline to space, second `tr -s ' '` collapses consecutive spaces into one (cleaner output for regex).

---

### FIX-066 — `v$archive_dest.transmit_mode` in 26ai = `PARALLELSYNC`, not `SYNCHRONOUS`

**Date:** 2026-04-26 21:46 | **File:** `VMs/scripts/configure_broker.sh` v2.8 → **v2.9**

**Symptom:**
```
[21:46:54]   Verify v$archive_dest dest_id=2 transmit_mode=SYNCHRONOUS, affirm=YES...
[21:46:54] ERROR: log_archive_dest_2 is NOT SYNCHRONOUS after MaxAvailability:
          D2_TRANSMIT=PARALLELSYNC,D2_AFFIRM=YES
```

Script v2.8 died on the final verify even though broker correctly set **MaxAvailability + Configuration Status: SUCCESS + AFFIRM=YES**. The run was otherwise ideal:

```
[21:46:43] Section 2 — CREATE/ADD/ENABLE configuration...
[21:46:43]   Configuration already exists with SUCCESS status — skip CREATE/ADD/ENABLE   <-- FIX-065 OK
[21:46:43] Section 3 — Change Protection Mode to MaxAvailability...
DGMGRL> Property "logxptmode" updated for member "prim".
DGMGRL> Property "logxptmode" updated for member "stby".
DGMGRL> Succeeded.
  Protection Mode: MaxAvailability
  Configuration Status: SUCCESS
[21:46:54]     ✓ Status SUCCESS after 1x15s
[21:46:54]   ✓ Protection Mode = MaxAvailability + Status SUCCESS
[21:46:54] ERROR: log_archive_dest_2 is NOT SYNCHRONOUS: D2_TRANSMIT=PARALLELSYNC   <-- FIX-066
```

**Diagnosis:** In Oracle 23ai/26ai, broker for `LogXptMode=SYNC` sets `v$archive_dest.transmit_mode='PARALLELSYNC'` (enhanced multi-stream SYNC mode introduced in 21c+) instead of the classic `SYNCHRONOUS` known from 19c.

`PARALLELSYNC` is the **correct** SYNC mode for MaxAvailability — Oracle uses multiple redo streams in parallel for better throughput, but `AFFIRM` guarantees (commit returned only after ack from standby) are preserved.

**Fix v2.9:**

```bash
# Accept both: SYNCHRONOUS (19c-style) or PARALLELSYNC (23ai/26ai-style)
echo "$ARCHDEST_OUT" | grep -qE "D2_TRANSMIT=(SYNCHRONOUS|PARALLELSYNC)" \
    || die "log_archive_dest_2 is NOT in SYNC mode after MaxAvailability: $ARCHDEST_OUT"
```

**Expected after fix:**
```
[..]   ✓ log_archive_dest_2: SYNC + AFFIRM=YES (broker configured automatically):
       D2_TRANSMIT=PARALLELSYNC,D2_AFFIRM=YES
[..] DONE — DG Broker enabled, Protection Mode = MaxAvailability (SYNC+AFFIRM)
```

**Lesson:**
- In 23ai/26ai `v$archive_dest.transmit_mode` has 4 possible values: `ASYNCHRONOUS`, `SYNCHRONOUS`, `PARALLELSYNC`, `PARALLELSYNC_NOAFFIRM`. **`PARALLELSYNC` is the default** for LogXptMode=SYNC.
- Verifying SYNC mode in 23ai/26ai: `transmit_mode IN ('SYNCHRONOUS','PARALLELSYNC') AND affirm='YES'`.
- MAA diagnostic scripts ported from 19c must account for `PARALLELSYNC` in grep/regex.

---

### FIX-067 — `SHOW FAST_START FAILOVER` multiline grep in 26ai

**Date:** 2026-04-26 22:30 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.1 → **v1.2**

**Symptom:** Script v1.1 section "Enable FSFO + post-flight verify" (line 208):

```bash
echo "$FSFO_OUT" | grep -qE "(Status|Fast-Start Failover):.*ENABLED" \
    || die "FSFO Status != ENABLED after ENABLE FAST_START FAILOVER."
```

In 23ai/26ai output of `SHOW FAST_START FAILOVER` is multiline:
```
Fast-Start Failover:
ENABLED

  Threshold:           30 seconds
  ...
```

`Fast-Start Failover:` on one line, `ENABLED` on the **next**. Single-line grep doesn't match → script dies even though FSFO is actually ENABLED. **Identical pattern to FIX-065** in `configure_broker.sh`.

**Fix v1.2:**
```bash
FSFO_FLAT=$(echo "$FSFO_OUT" | tr '\n' ' ' | tr -s ' ')
if echo "$FSFO_FLAT" | grep -qE "Fast-Start Failover:[[:space:]]*ENABLED"; then
    log "  ✓ Fast-Start Failover: ENABLED"
fi
```

All 2 greps on dgmgrl output (section 4.5 pre-flight + section 9 retry verify) now use `tr | tr -s ' ' | grep -qE`.

**Lesson:** dgmgrl 23ai/26ai output is multiline for **all** `SHOW *` commands (`SHOW CONFIGURATION`, `SHOW DATABASE`, `SHOW FAST_START FAILOVER`, `SHOW PROPERTIES`). Every bash grep on dgmgrl output must have `tr '\n' ' '` flatten or `grep -z` (NULL-separated). Universal rule for all scripts executing dgmgrl heredoc.

---

### FIX-068 — Pre-flight must check broker `Configuration Status: SUCCESS` before ENABLE FSFO

**Date:** 2026-04-26 22:30 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.1 → **v1.2**

**Problem:** Script v1.1 only checked `tnsping` and `sqlplus connect`, but did **NOT** verify that broker is in `SUCCESS` state before calling:
1. `EDIT CONFIGURATION SET PROPERTY FastStartFailoverThreshold=30;` (and 4 more)
2. `ADD OBSERVER ${OBSERVER_NAME} ON ${OBSERVER_HOST};`
3. `ENABLE FAST_START FAILOVER;`

If broker was in `WARNING` state (e.g. apply lag > 30s, ORA-16532 from RAC config_file, fresh re-build), these EDITs returned `ORA-16664 unable to receive the result from a member` or `ORA-16830 primary is not ready for failover` with **unclear messages** (script logged `dgmgrl output` without indicating that the root cause is broker WARNING, not observer setup).

**Fix v1.2 — section 4.5 pre-flight:**

```bash
CFG_OUT=$(... dgmgrl /@PRIM_ADMIN <<DGEOF ... SHOW CONFIGURATION ... DGEOF)
CFG_FLAT=$(echo "$CFG_OUT" | tr '\n' ' ' | tr -s ' ')

if echo "$CFG_FLAT" | grep -qE "Configuration Status:[[:space:]]*SUCCESS"; then
    log "  ✓ Configuration Status: SUCCESS"
elif echo "$CFG_FLAT" | grep -qE "ORA-16532|configuration does not exist"; then
    die "Broker configuration does not exist. Run configure_broker.sh first (doc 10)."
elif echo "$CFG_FLAT" | grep -qE "Configuration Status:[[:space:]]*WARNING"; then
    die "Broker WARNING — observer setup suspended. Check: SHOW CONFIGURATION VERBOSE + SHOW DATABASE * STATUSREPORT."
fi
```

Plus warn-only check `Protection Mode: MaxAvailability` (FSFO can be enabled in MaxPerformance, but no zero data loss guarantee — better to let user decide consciously).

**Lesson:** Every script executing `EDIT CONFIGURATION` or `ENABLE *` must pre-flight `SHOW CONFIGURATION` with multiline-aware grep and 3 branches (SUCCESS / WARNING / does not exist). Otherwise downstream error masks root cause.

---

### FIX-069 — `ENABLE FAST_START FAILOVER` async in 26ai — retry 180s

**Date:** 2026-04-26 22:30 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.1 → **v1.2**

**Problem:** Analogous to `ENABLE CONFIGURATION` (FIX-062 / FIX-064), `ENABLE FAST_START FAILOVER` in 26ai is **async**. The command returns `Enabled in Zero Data Loss Mode.` immediately after commit to `dr*PRIM.dat`, but broker propagates state `ENABLED` to members + observer over **30–150s** (VBox lab; prod 30–45s).

Script v1.1 did `ENABLE FSFO` + `SHOW FAST_START FAILOVER` in **one dgmgrl heredoc** (lines 201–205) — without sleep or retry. First `SHOW` immediately after enable may show `DISABLED` even though the commit succeeded.

**Fix v1.2 — section 9 retry loop:**

```bash
FSFO_OK=0
for i in $(seq 1 12); do
    sleep 15
    FSFO_OUT=$(... dgmgrl /@PRIM_ADMIN <<DGEOF ... SHOW FAST_START FAILOVER ... DGEOF)
    FSFO_FLAT=$(echo "$FSFO_OUT" | tr '\n' ' ' | tr -s ' ')

    if echo "$FSFO_FLAT" | grep -qE "Fast-Start Failover:[[:space:]]*ENABLED"; then
        log "    ✓ ENABLED after ${i}x15s"
        FSFO_OK=1
        break
    fi
    log "    [${i}/12] FSFO not yet ENABLED, continuing to wait..."
done
[[ "$FSFO_OK" -eq 1 ]] || die "FSFO != ENABLED after 180s."
```

Plus additional verify that Observer name in SHOW FAST_START FAILOVER matches `${OBSERVER_NAME}` (sanity check — observer actually registered with the broker).

**Lesson:** All `ENABLE *` commands in dgmgrl 23ai/26ai are async (broker.config write + propagation to members). Automating scripts must have retry loop **180s for VBox lab / 90s for prod** + multiline grep. Rule same as for `ENABLE CONFIGURATION` — propagation via `dr*PRIM.dat` in +DATA requires a second coordination round after commit.

**Additional housekeeping in v1.2:**

| # | What | Detail |
|---|------|--------|
| #4 | systemd `START OBSERVER` **without** `IN BACKGROUND` with `Type=simple` | `IN BACKGROUND` forks observer and exits; systemd considers it a crash → Restart=on-failure loop. Without `IN BACKGROUND` dgmgrl holds the process until observer stops. |
| #5 | Reordering: `ADD OBSERVER` → `systemctl start` → wait 15s → `SET MASTEROBSERVER` → `ENABLE FSFO` | `SET MASTEROBSERVER` in 26ai requires running observer (broker pings). v1.1 did `SET MASTEROBSERVER` before `systemctl start` — silent fail. |
| #6 | mkstore `-createCredential` idempotency | `mkstore -listCredential \| grep -c PRIM_ADMIN` before create. Without this re-run died with `set -e` because mkstore returned exit 1 on "credential already exists". |
| #7 | Cleanup `/tmp/setup_wallet.$$.sh` via `trap` | File contains wallet password (`Welcome1#Wallet`). v1.1 left it on disk. v1.2 removes even on die. |
| ALLOW_HOST | Override for `ALLOW_HOST=any OBSERVER_NAME=obs_dc` | Doc 16 backup observers (`obs_dc` on prim01, `obs_dr` on stby01). v1.1 required `hostname == infra01` hardcoded. |

---

### FIX-070 — `DECLINE_SECURITY_UPDATES` invalid in `client.rsp` schema 23.0.0

**Date:** 2026-04-26 22:25 | **File:** `VMs/response_files/client.rsp` v1.1 → **v1.2**, `VMs/11_fsfo_observer.md` section 1.3

**Symptom:**
```
[oracle@infra01 client]$ ./runInstaller -silent -responseFile /tmp/scripts/client.rsp -ignorePrereqFailure
[FATAL] [INS-10105] The given response file /tmp/scripts/client.rsp is not valid.
   CAUSE: Syntactically incorrect response file. Either unexpected variables are
          specified or expected variables are not specified in the response file.
   SUMMARY:
       - cvc-complex-type.2.4.a: Invalid content was found starting with element
         'DECLINE_SECURITY_UPDATES'. One of '{SELECTED_LANGUAGES, ORACLE_HOSTNAME,
         oracle.install.IsBuiltInAccount, oracle.install.OracleHomeUserName,
         oracle.install.OracleHomeUserPassword, oracle.install.client.oramtsPortNumber,
         oracle.install.client.customComponents, ..., PROXY_HOST, PROXY_PORT,
         PROXY_USER, PROXY_PWD, PROXY_REALM}' is expected.
```

**Diagnosis:** Schema `rspfmt_clientinstall_response_schema_v23.0.0` in Oracle Client 23ai/26ai is **strict** and does not accept legacy keys from 19c. `DECLINE_SECURITY_UPDATES=true` was a standard key in 19c response files (told OUI we don't want MOS account for security alerts) — in 23.0.0 schema it was removed (MOS account configuration moved to account level).

**List of allowed keys in 23.0.0 client schema** (from error message):
- `SELECTED_LANGUAGES`
- `ORACLE_HOSTNAME`
- `oracle.install.IsBuiltInAccount`, `OracleHomeUserName`, `OracleHomeUserPassword`
- `oracle.install.client.oramtsPortNumber`
- `oracle.install.client.customComponents`
- `oracle.install.client.schedulerAgentHostName`, `schedulerAgentPortNumber`
- `oracle.install.client.drdaas.*` (DRDA AS settings — DB2 compat)
- `PROXY_HOST`, `PROXY_PORT`, `PROXY_USER`, `PROXY_PWD`, `PROXY_REALM`

Plus base keys that work (from standard response file format):
- `oracle.install.responseFileVersion`
- `UNIX_GROUP_NAME`, `INVENTORY_LOCATION`, `ORACLE_HOME`, `ORACLE_BASE`
- `oracle.install.client.installType`

**Fix v1.2:** removed `DECLINE_SECURITY_UPDATES=true` from `client.rsp`. After fix:

```
[oracle@infra01 client]$ ./runInstaller -silent -responseFile /tmp/scripts/client.rsp -ignorePrereqFailure
Starting Oracle Universal Installer...
Checking Temp space: OK
Checking swap space: OK
...
Successfully Setup Software.
```

**Related:** FIX-028 (`asmSysPassword` in dbca rsp — removed in 23.0.0 schema), FIX-029 (`recoveryAreaSize` — removed, replaced by `db_recovery_file_dest_size` in `initParams`). **Universal pattern:** all `*_response_schema_v23.0.0` are strict — they reject any key outside the list. Migration from 19c rsp requires key-by-key audit.

**Operational lesson:** for every INS-10105 start with the list of allowed keys in the SUMMARY error message — Oracle prints the full schema content. Match key-by-key and remove all keys not on the list.

---

### FIX-071 — `PWD` in wallet helper script collides with bash builtin

**Date:** 2026-04-26 22:37 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.2 → **v1.3**

**Symptom:**
```
[22:37:24] Section 3 — Creating/updating Oracle Wallet...
Creating new wallet...
Enter password:           ← INTERACTIVE (heredoc didn't supply password)
Enter password again:
Adding PRIM_ADMIN credential...
Enter wallet password:    ← INTERACTIVE
Adding STBY_ADMIN credential...
Enter wallet password:    ← INTERACTIVE
Auto-login (cwallet.sso) already exists - skip
Wallet configured
[22:37:27] Section 4 — Pre-flight: tnsping PRIM_ADMIN and STBY_ADMIN OK
[22:37:27]   Test connectivity sqlplus /@PRIM_ADMIN...
[22:37:27] ERROR: Test PRIM_ADMIN sqlplus FAIL — check wallet credentials or broker readiness.
```

3× `Enter password:` when heredoc should have automatically supplied `Welcome1#Wallet`. Wallet was created with **wrong password** (or timeout). `sqlplus /@PRIM_ADMIN` in section 4 found no credentials.

**Diagnosis:** v1.2 helper script used:
```bash
PWD='Welcome1#Wallet'    # FIX-071: PWD is a bash BUILTIN (current working directory)
SYS='Welcome1#SYS'

mkstore -wrl $WL -create <<EOF
$PWD                     # bash interpolates builtin /home/oracle, NOT 'Welcome1#Wallet'
$PWD
EOF
```

In heredoc bash interpolates `$PWD` in **inner shell context**. The assignment `PWD='Welcome1#Wallet'` in the script did not override the builtin in heredoc evaluation — bash used `/home/oracle` (oracle user's current working dir) as the "password". mkstore rejected it as too-short and prompted interactively. After 3 timeouts wallet was created with empty/junk password.

`Auto-login (cwallet.sso) already exists - skip` — because `cwallet.sso` was created automatically with `mkstore -create` in 23ai (auto-SSO enabled by default on create). Script skipped the `mkstore -autoLogin` step.

**Fix v1.3:**

```bash
# Rename PWD->WP, SYS->SP, WALLET->WL (no collision with bash builtins PWD/OLDPWD)
WL=$WALLET_DIR
WP='$WALLET_PWD'   # interpolated in outer = 'Welcome1#Wallet'
SP='$SYS_PWD'      # = 'Welcome1#SYS'

mkstore -wrl $WL -create <<EOF
$WP
$WP
EOF
```

Plus:
- **Outer pre-check** (outside heredoc): if wallet exists but `mkstore -listCredential` with correct password fails → wipe (`rm -f $WL/*`) & recreate. Without this stale wallet from previous run blocks the fix.
- **Final verify**: `mkstore -listCredential | grep -cE "(PRIM|STBY)_ADMIN"` must return 2 — otherwise die with credential dump.
- `mkstore -autoLogin` → `-createSSO` (preferred syntax in 23ai, `-autoLogin` is backward-compat alias).

**Recovery for existing wallet with stale password:**
```bash
sudo rm -f /etc/oracle/wallet/observer-ext/*
sudo bash /tmp/scripts/setup_observer_infra01.sh   # v1.3
```

**Universal lesson:** In bash NEVER use `PWD`, `OLDPWD`, `IFS`, `PATH`, `HOME`, `USER`, `UID`, `EUID`, `RANDOM`, `SECONDS`, `LINENO`, `BASH_*` as local variable names — all are built-in. Heredoc + builtin = silent override in unexpected places. Rule: variable names in bash heredoc-helpers should be 2-letter non-obvious abbreviations (WP/SP/WL) — no collision.

**Additionally (UX):** mkstore in 23ai/26ai has `-createSSO`, `-createLSSO`, `-createALO` in help instead of `-autoLogin` — though backward-compat for `-autoLogin` is preserved.

---

### FIX-072 — `SQLNET.AUTHENTICATION_SERVICES = (TCPS, NTS, BEQ)` blocks wallet auto-login

**Date:** 2026-04-26 22:45 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.3 → **v1.4**, `VMs/11_fsfo_observer.md` section 2.3

**Symptom:** After FIX-071 (wallet with correct credentials, `mkstore -listCredential` returned `1: PRIM_ADMIN sys, 2: STBY_ADMIN sys` with password `Welcome1#Wallet`) section 4 still died:

```
[..]   Test connectivity sqlplus /@PRIM_ADMIN...
[..] ERROR: Test PRIM_ADMIN sqlplus FAIL — check wallet credentials or broker readiness.
```

Diagnosing why wallet was OK but sqlplus failed:

`sqlnet.ora` deployed by script v1.3 section 2 contained:
```
SQLNET.AUTHENTICATION_SERVICES = (TCPS, NTS, BEQ)
```

**Values and their meanings:**
- `TCPS` = SSL/TLS authentication (requires TLS certificates on both sides)
- `NTS` = NT Native Service (Windows-only — Active Directory pass-through)
- `BEQ` = Bequeath protocol (local IPC, NOT network — only `sqlplus / as sysdba` from local host)
- `NONE` = allows **password authentication** (including wallet auto-login)

**Wallet auto-login** for `sqlplus /@PRIM_ADMIN as sysdba`:
1. sqlplus reads `cwallet.sso` (auto-login) → finds credential `PRIM_ADMIN sys/Welcome1#SYS`
2. **Sends password `Welcome1#SYS` to server in standard way (password auth)**
3. Server validates against password file (orapwd)

With `(TCPS, NTS, BEQ)` in sqlnet.ora — sqlplus says "only TCPS, NTS or BEQ allowed" → password auth blocked → **ORA-01017 invalid username/password** (even though wallet has the correct password).

**Internet pattern is misleading:** `(TCPS, NTS, BEQ)` is a typical "secure config" in DBA blogs — but this configuration **completely disables password auth**. For wallet-based observers / application clients always use:

```
SQLNET.AUTHENTICATION_SERVICES = (NONE)
# or no line at all (default = all methods including password)
```

**Fix v1.4:**
```diff
- SQLNET.AUTHENTICATION_SERVICES = (TCPS, NTS, BEQ)
+ SQLNET.AUTHENTICATION_SERVICES = (NONE)
```

Plus: removed `>/dev/null` from sqlplus test command, capture to `SQLPLUS_OUT` and echo on fail. Without this, die didn't show the exact ORA-XXXXX (FIX-071 and FIX-072 were invisible on first attempt).

**Recovery for existing infra01 (after v1.3):**
```bash
# 1. Manual edit sqlnet.ora (AUTHENTICATION_SERVICES section):
sudo sed -i 's/(TCPS, NTS, BEQ)/(NONE)/' /etc/oracle/tns/ext/sqlnet.ora

# 2. Test:
su - oracle -c 'export TNS_ADMIN=/etc/oracle/tns/ext && sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT database_role FROM v\$database;
EXIT
EOF'
# Expected: PRIMARY (or PHYSICAL STANDBY for STBY_ADMIN)

# 3. Or full re-run v1.4:
sudo bash /tmp/scripts/setup_observer_infra01.sh
```

**Universal lesson:**
- `SQLNET.AUTHENTICATION_SERVICES` is an often misunderstood directive. Rules:
  - **Wallet-based password auth** (typical for observers, JDBC apps, automation) → `(NONE)` or no line
  - **TLS-only deployment** (mTLS with certificates) → `(TCPS)` (and only TCPS)
  - **Windows AD integration** → `(NTS)` plus `(NONE)` as fallback
  - **Local BEQ** (sqlplus / as sysdba on DB host) → `(BEQ, NONE)` — BEQ first, password fallback
- **Default is safest:** no line = all methods accepted → wallet auto-login works.
- Every `INS-*` or `ORA-01017` with wallet = **first check sqlnet.ora `SQLNET.AUTHENTICATION_SERVICES`** before digging into mkstore.

**Related earlier fixes:**
- FIX-071 (wallet stale password) — I thought it was the root cause, but it was a distractor
- FIX-053 (pre-flight tnsping) — catches ORA-12154/12541, but NOT ORA-01017 (because tnsping doesn't log in, only checks alias resolve)

---

### FIX-073 — Heredoc + `su - oracle -c` double-shell escape loses `\$`

**Date:** 2026-04-26 22:50 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.4 → **v1.5**, `VMs/11_fsfo_observer.md` section 3.5

**Symptom:** After FIX-072 (sqlnet.ora `(NONE)`) section 4 sqlplus wallet test returned:
```
[..]   Test connectivity sqlplus /@PRIM_ADMIN...
SELECT database_role FROM v
                          *
ERROR at line 1:
ORA-00942: table or view "SYS"."V" does not exist
```

Wallet OK (manual `sqlplus /@PRIM_ADMIN` as oracle returns `PRIMARY`), but through script (`su - oracle -c "..."`) heredoc loses the escape — SQL arrives as `SELECT database_role FROM v;` instead of `... FROM v$database;`.

**Diagnosis:** v1.4 section 4 sqlplus test:
```bash
su - oracle -c "export TNS_ADMIN=$TNS_DIR && $ORACLE_HOME/bin/sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE
SELECT database_role FROM v\$database;
EXIT
EOF"
```

Expansion flow through **2 shell levels**:

1. **Outer bash** (root) sees `"...v\$database..."` in double quotes:
   - In double quotes, `\$` is an **escape sequence** for literal `$` (bash man: "The backslash retains its special meaning only when followed by one of the following characters: $, `, \", \\, or <newline>")
   - After expansion: `"...v$database..."`
   - Argument passed to `bash -c`: string containing `v$database`

2. **Inner bash** (oracle, from `su - oracle -c "..."`) executes the string:
   - Heredoc `<<EOF` (unquoted tag) → bash interpolates variables inside
   - `$database` → undefined variable → empty string
   - SQL after expansion: `SELECT database_role FROM v;`

3. **sqlplus** receives `SELECT database_role FROM v;` → ORA-00942.

**Manual test as oracle (single-shell)** doesn't have this problem:
```bash
[oracle@infra01 ~]$ sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT database_role FROM v\$database;
EXIT
EOF
# OK: returns PRIMARY
```
Here there is **one level of expansion** — bash sees `\$database` in heredoc context, escape works, SQL = `v$database`.

**Fix v1.5 — SQL via temporary file with quoted heredoc:**

```bash
SQLF=/tmp/test_sqlplus.$$.sql
cat > "$SQLF" <<'SQL_EOF'        # 'SQL_EOF' (quoted) = does NOT interpolate
WHENEVER SQLERROR EXIT FAILURE
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT database_role FROM v$database;
EXIT
SQL_EOF
chown oracle:oinstall "$SQLF"
chmod 644 "$SQLF"

SQLPLUS_OUT=$(su - oracle -c "export TNS_ADMIN=$TNS_DIR && $ORACLE_HOME/bin/sqlplus -s /@PRIM_ADMIN as sysdba @$SQLF" 2>&1) || {
    echo "$SQLPLUS_OUT"
    rm -f "$SQLF"
    die "..."
}
rm -f "$SQLF"
echo "$SQLPLUS_OUT" | grep -qE "PRIMARY" || die "Output doesn't contain PRIMARY"
```

Quoted heredoc `<<'SQL_EOF'` blocks interpolation — `$database` written to file **literally**. sqlplus run with `@$SQLF` (SQL script) — safe for all object names (`v$session`, `gv$instance`, `dba_dg_broker_config_properties` etc).

**Alternative — triple escape `\\\$database`** in outer:
```bash
su - oracle -c "...sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT database_role FROM v\\\$database;
EOF"
```
Works, but **unreadable** (3 escape levels: `\\\$` → outer `\$` → inner literal `$` in heredoc). SQL file is cleaner and less prone to regression when editing.

**Universal lesson:**
- In bash NEVER inline heredoc with `$variable references` through `su - user -c "..."` (or `ssh user@host "..."`, `bash -c "..."`). Each shell level consumes one level of escaping.
- **Practical rule for wrapper scripts:** SQL/PL/SQL with `$` references → temporary file with quoted heredoc (`<<'EOF'`) → run via `sqlplus @file`.
- Manual run in a single shell (one user, no `su -c`) — regular `\$` escape works.
- **Diagnostics:** ORA-00942 with `*` pointing to `v` (instead of `v$database`) = classic shell escape bug. Check if SQL is called in double-shell context.

**Related:** FIX-072 (sqlnet.ora AUTHENTICATION_SERVICES) — was the true root cause of sqlplus connect fail. FIX-073 is a second bug **in the same piece of code** (section 4 sqlplus test) — it revealed itself only after FIX-072 was fixed.

---

### FIX-074 — DGMGRL syntax/flag changes in 23ai/26ai (3 changes in one pipeline)

**Date:** 2026-04-26 22:55 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.5 → **v1.6**, `VMs/11_fsfo_observer.md` sections 6.2/6.3/6.4

**Symptom:** After FIX-073 (section 4 sqlplus passed, sections 5/6 partial), sections 6 + 7 gave three separate errors:

```
DGMGRL> ADD OBSERVER obs_ext ON infra01.lab.local;
    ^
Syntax error before or at "OBSERVER"
...
Configuration - prim_dg
  ...
[..]   ✓ FSFO properties + ADD OBSERVER applied (re-run safe)   ← false success
[..] Section 7 — Starting systemd observer...

# journalctl:
Apr 26 22:51:25 dgmgrl[9009]: Unknown option: -logfile
Apr 26 22:51:25 dgmgrl[9009]: Usage: dgmgrl [<options>] [<logon> [<command>]]
Apr 26 22:51:25 dgmgrl[9009]:   <options> ::= -silent | -echo

# ExecStop tries to STOP observer:
Apr 26 22:51:27 dgmgrl[9013]: Error: ORA-16873: The observer with the specified name is not started.
Apr 26 22:51:27 systemd[1]: dgmgrl-observer-obs_ext.service: Succeeded.

[22:51:40] ERROR: systemd dgmgrl-observer-obs_ext is not active.
```

**Three separate 23ai/26ai breaking changes in one pipeline:**

#### #1 — `ADD OBSERVER` syntax change

| | 19c | 23ai/26ai |
|---|---|---|
| Syntax | `ADD OBSERVER name ON host_name` | `ADD OBSERVER 'name' ON HOST 'host_name'` |
| `HOST` keyword | absent | **required** |
| Quotes | optional | required around names |

19c-style in 26ai returns: `Syntax error before or at "OBSERVER"` (parser doesn't recognize OBSERVER token because `ADD` in 26ai expects different followers with keyword HOST).

Reference: `docs.oracle.com/en/database/oracle/oracle-database/23/dgbkr/oracle-data-guard-broker-commands.html`

```
ADD OBSERVER ['observer_name'] ON HOST 'host_name' [TO CONFIGURATION 'configname']
```

#### #2 — `dgmgrl -logfile` flag REMOVED

dgmgrl help in 23ai/26ai shows **only 2 flags**:
```
<options> ::= -silent | -echo
```

`-logfile path` was available in 19c — in 23ai/26ai it was removed. Observer logging goes exclusively through the **`LOGFILE='...'` clause in the `START OBSERVER` command** (already there, but `-logfile` as outer dgmgrl flag kills the process before `START OBSERVER` executes).

Effect with `-logfile` in systemd ExecStart:
1. dgmgrl sees `-logfile path` → exit with `Unknown option` + usage
2. systemd considers it a startup crash
3. systemd tries cleanup via ExecStop: `dgmgrl /@PRIM_ADMIN "STOP OBSERVER 'obs_ext'"`
4. ExecStop returns ORA-16873 "observer not started" (because it never started)
5. systemd: `Succeeded` (from stop perspective OK), service: inactive (dead)
6. Script: `systemctl is-active --quiet` → 1 → die

#### #3 — Quotes in `SET MASTEROBSERVER` and `STOP OBSERVER`

Consistent with `ADD OBSERVER 'name'` — all commands operating on observer name should use quotes:
```
SET MASTEROBSERVER TO 'obs_ext';
STOP OBSERVER 'obs_ext';
```

Without quotes in some edge cases (name starting with a number, containing a dash) the parser may not accept it. In lab with `obs_ext` can skip — but for consistency.

**Fix v1.6:**

```bash
# Section 5 (systemd unit ExecStart):
# v1.5: dgmgrl -echo -logfile $LOG_DIR/${OBSERVER_NAME}.log /@PRIM_ADMIN "START..."
# v1.6: dgmgrl -echo /@PRIM_ADMIN "START OBSERVER '${OBSERVER_NAME}' FILE='...' LOGFILE='...'"

# Section 6 (ADD OBSERVER):
# v1.5: ADD OBSERVER ${OBSERVER_NAME} ON ${OBSERVER_HOST};
# v1.6: ADD OBSERVER '${OBSERVER_NAME}' ON HOST '${OBSERVER_HOST}';

# Section 8 (SET MASTEROBSERVER):
# v1.5: SET MASTEROBSERVER TO ${OBSERVER_NAME};
# v1.6: SET MASTEROBSERVER TO '${OBSERVER_NAME}';
```

**Plus fix for idempotency check (section 6 false success):**

v1.5 idempotency check after dgmgrl heredoc:
```bash
if echo "$DGMGRL_FLAT" | grep -qiE "ORA-(16664|16606|16672)"; then
    die "FSFO properties FAIL ..."
fi
log "  ✓ FSFO properties + ADD OBSERVER applied"   ← false success
```

`ADD OBSERVER` syntax error doesn't return ORA-XXXX (it's a parser error, not SQL error). Script didn't detect failure → continue. **TODO v1.7:** add grep on `Syntax error before or at` as die-pattern.

**Recovery for current state on infra01:**
```bash
# 1. Stop systemd (already inactive, but performs daemon-reload for new unit)
sudo systemctl stop dgmgrl-observer-obs_ext 2>/dev/null || true
sudo systemctl disable dgmgrl-observer-obs_ext 2>/dev/null || true

# 2. Cleanup observer dat/log from previous failed run
sudo rm -f /var/log/oracle/observer/obs_ext.dat /var/log/oracle/observer/obs_ext.log

# 3. SCP v1.6 and re-run
scp <repo>/VMs/scripts/setup_observer_infra01.sh root@infra01:/tmp/scripts/
ssh root@infra01 "bash /tmp/scripts/setup_observer_infra01.sh"
```

**Universal lesson:** every dgmgrl/sqlplus command from 19c scripts requires audit in 23ai/26ai. Pattern for wrapper script:
1. **Syntax keywords** — in 23ai keywords were added (HOST, MAINTAINED AS removed) or removed (DECLINE_SECURITY_UPDATES, asmSysPassword)
2. **Flags** — tools have fewer flags (`dgmgrl -logfile` removed, `dgmgrl -v` removed — use `dgmgrl` without args for version)
3. **Quoting** — 23ai requires quotes around identifier names in many places
4. **Multiline output** — `SHOW *` all multiline (FIX-065/067)
5. **Async behavior** — `ENABLE *` async, retry loops (FIX-062/064/069)

**Cumulative DGMGRL fixes in current session:**
- FIX-061 — `ADD DATABASE` without `MAINTAINED AS PHYSICAL`
- FIX-065 — multiline grep for `SHOW CONFIGURATION`
- FIX-067 — multiline grep for `SHOW FAST_START FAILOVER`
- **FIX-074 — `ADD OBSERVER` with `ON HOST`, `dgmgrl -logfile` removed, quotes around names**

---

### FIX-075 — DGMGRL true 26ai syntax (obtained from `HELP`; FIX-074 guesses were wrong)

**Date:** 2026-04-26 23:00 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.6 → **v1.7**, `VMs/11_fsfo_observer.md` sections 6.2/6.3/6.4

**Symptom:** After FIX-074 (syntax guessed from 19c→23ai migration patterns), script still died:

```
DGMGRL> ADD OBSERVER 'obs_ext' ON HOST 'infra01.lab.local';
    ^
Syntax error before or at "OBSERVER"

# systemd ExecStart:
dgmgrl[9535]: START OBSERVER 'obs_ext' FILE='/var/log/oracle/observer/obs_ext.dat' LOGFILE='/var/log/oracle/observer/obs_ext.log'
                              ^
dgmgrl[9535]: Syntax error before or at "FILE"
```

**Empirical diagnosis (via `dgmgrl HELP`):** instead of guessing syntax from internet/blogs, I used the built-in `HELP` in dgmgrl 26ai:

#### `HELP START OBSERVER` (actual 26ai syntax):

```
START OBSERVER [<observer-name>]
[FILE IS <observer-file>]
[LOGFILE IS <observer-log-file>]
[TRACE_LEVEL IS { USER | SUPPORT }];

START OBSERVER [<observer-name>]
IN BACKGROUND
CONNECT IDENTIFIER IS <connect-identifier>
[FILE IS <observer-file>]
...
```

| | 19c | 23ai/26ai |
|---|---|---|
| FILE clause | `FILE='<file>'` | `FILE IS <file>` (keyword `IS`, not `=`) |
| LOGFILE clause | `LOGFILE='<file>'` | `LOGFILE IS <file>` |
| observer-name | without quotes | without quotes (regular identifier) |
| dgmgrl `-logfile` flag | available | removed (only `-silent`/`-echo`) |

#### `HELP ADD OBSERVER` (actual in 26ai):

```
ADD CONFIGURATION [<configuration-name>] CONNECT IDENTIFIER IS <connect-identifier>;
ADD { DATABASE | FAR_SYNC | MEMBER | RECOVERY_APPLIANCE } <db-unique-name> ...;
ADD PLUGGABLE DATABASE <pdb-name> AT <target-db-unique-name> ...;
```

**`ADD OBSERVER` REMOVED.** Only `ADD CONFIGURATION/DATABASE/MEMBER/PLUGGABLE DATABASE` remain. Observer is added **automatically** on `START OBSERVER` — broker creates a persistent record after first successful start.

#### `HELP SHOW OBSERVER` (confirms no ADD):

```
SHOW OBSERVER;
SHOW OBSERVERS [FOR <configuration-group-name>];
SHOW OBSERVERCONFIGFILE;
```

`SHOW` has 3 observer variants, but `ADD OBSERVER` has no counterpart.

#### `SET MASTEROBSERVER` in single-observer 26ai

In 26ai the first started observer **automatically becomes master**. `SET MASTEROBSERVER TO name` only required for multi-observer quorum (3-of-3 FSFO — doc 16). Single observer = not needed.

**Fix v1.7 (4 changes):**

```diff
# Section 5 systemd ExecStart:
- ExecStart=... dgmgrl -echo /@PRIM_ADMIN "START OBSERVER 'obs_ext' FILE='...' LOGFILE='...'"
+ ExecStart=... dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_ext FILE IS '...' LOGFILE IS '...'"

# Section 6 (REMOVED completely):
- ADD OBSERVER 'obs_ext' ON HOST 'infra01.lab.local';

# Section 8 (REMOVED):
- SET MASTEROBSERVER TO 'obs_ext';
  ENABLE FAST_START FAILOVER;

# Section 6 idempotency check (ADDED):
+ if echo "$DGMGRL_FLAT" | grep -qiE "Syntax error before or at"; then
+     die "FSFO properties: dgmgrl SYNTAX ERROR — check output above."
+ fi
```

**Universal lesson:** instead of guessing 23ai/26ai syntax from 19c→23ai migration blogs/internet snippets — **first `dgmgrl HELP <command>`**. dgmgrl has built-in help for every command with the exact syntax for its version. It's a 60-second diagnostic that saves iterations of "FIX-074, FIX-074a, FIX-074b...".

**Pattern to record:**
```
dgmgrl /@PRIM_ADMIN
DGMGRL> HELP <command>          # for a specific command
DGMGRL> HELP <verb>             # for the main verb (HELP ADD shows all ADD *)
DGMGRL> HELP                    # full command list
```

Record for future (universal for any wrapper script on dgmgrl/sqlplus): **at every first run on a new Oracle version, execute `HELP <key-command>` as a sanity check**.

**Cumulative DGMGRL syntax fixes for 26ai (FIX-074 → FIX-075):**
- ❌ `ADD OBSERVER` — removed
- ❌ `dgmgrl -logfile` — removed (only `-silent`/`-echo`)
- ❌ `dgmgrl -v` — removed (version in banner at plain launch)
- ✅ `START OBSERVER name FILE IS '<f>' LOGFILE IS '<f>'` — with keyword `IS`, no quotes around name
- ✅ `STOP OBSERVER name` — without quotes (like in `START`)
- ➕ Single observer = auto-master, `SET MASTEROBSERVER` optional (only multi-observer quorum)
- ➕ All `SHOW *` multiline output → `tr '\n' ' '` before grep (FIX-065/067)
- ➕ All `ENABLE *` async → retry loop 180s in VBox lab (FIX-062/064/069)

---

### FIX-076 — FSFO Zero Data Loss Mode requires Flashback Database on PRIM + STBY

**Date:** 2026-04-26 23:07 | **File:** `VMs/scripts/setup_observer_infra01.sh` v1.7 → **v1.8**, `VMs/11_fsfo_observer.md` prereq + section 5 noticebox, `VMs/09_standby_duplicate.md` TODO v3.4

**Symptom:**
```
[23:06:56] Section 8 — ENABLE FAST_START FAILOVER (single observer = auto-master)...
DGMGRL> ENABLE FAST_START FAILOVER;
Warning: ORA-16827: Flashback Database is disabled.

Enabled in Potential Data Loss Mode.   ← NOT Zero Data Loss
```

Script v1.7 section 9 verify found `Fast-Start Failover: ENABLED` (status OK) → DONE. But **Mode = Potential Data Loss** instead of `Zero Data Loss` — without zero data loss guarantee on failover.

**Diagnosis:** `ORA-16827: Flashback Database is disabled` — broker didn't find flashback YES on both sides. Test:
```sql
-- On prim01:
SELECT db_unique_name, flashback_on FROM v$database;
-- PRIM, YES   ← OK (enabled in doc 08 / fsfo_check_readiness PASS)

-- On stby01:
SELECT db_unique_name, flashback_on FROM v$database;
-- STBY, NO    ← problem (NOT enabled post-duplicate)
```

**Root cause:** `duplicate_standby.sh` v3.3 section 9b sets `log_archive_dest_2` (FIX-049), but does **NOT** enable flashback on STBY. Flashback is a per-database setting (not replicated by RMAN duplicate) — must be enabled separately on each side.

`fsfo_check_readiness.sql` section 0 checks only **local PRIM** (script runs from prim01) — STBY is not in scope.

**Why flashback is required on STBY:**
1. **REINSTATE DATABASE after failover** — broker rewinds old primary to SCN before failover, opens it as standby. Without flashback → must recreate via RMAN duplicate (lengthy, doc 09 procedure).
2. **FSFO Zero Data Loss Mode** — broker can guarantee zero data loss only if both sites can "roll back" to a consistent state in case of split-brain.
3. **Switchback** — after switching back to original primary, flashback speeds up convergence.

**Fix v1.8 (2 sections, warn-only):**

```bash
# Section 4.6 (NEW) — pre-flight verify Flashback Database on PRIM + STBY
# Does sqlplus via wallet to PRIM_ADMIN and STBY_ADMIN, checks FLASHBACK_ON.
# Warn-only (script continues with hint to recovery procedure).

# Section 9 (UPDATE) — verify Mode in SHOW FAST_START FAILOVER:
if echo "$FSFO_FLAT" | grep -qE "Mode:[[:space:]]*ZERO DATA LOSS"; then
    log "  ✓ FSFO Mode: ZERO DATA LOSS"
elif echo "$FSFO_FLAT" | grep -qE "Mode:[[:space:]]*POTENTIAL DATA LOSS"; then
    warn "FSFO Mode: POTENTIAL DATA LOSS - flashback database disabled..."
    warn "Recovery: enable flashback on both sides, then DISABLE/ENABLE FSFO"
fi
```

**Recovery procedure for existing deployment:**

1. **Verify both sides:**
   ```sql
   -- From infra01 (via wallet):
   sqlplus /@PRIM_ADMIN as sysdba <<EOF
   SELECT flashback_on FROM v\$database;
   EOF

   sqlplus /@STBY_ADMIN as sysdba <<EOF
   SELECT flashback_on FROM v\$database;
   EOF
   ```

2. **Enable flashback on STBY (PRIM usually YES after doc 08):**
   ```bash
   ssh oracle@stby01
   sqlplus / as sysdba
   ```
   ```sql
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
   SHUTDOWN IMMEDIATE;
   STARTUP MOUNT;
   ALTER DATABASE FLASHBACK ON;
   ALTER DATABASE OPEN READ ONLY;
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION USING CURRENT LOGFILE;

   SELECT flashback_on FROM v$database;
   -- YES
   ```

3. **Re-enable FSFO in Zero Data Loss Mode:**
   ```
   DGMGRL> DISABLE FAST_START FAILOVER;
   DGMGRL> ENABLE FAST_START FAILOVER;
   # Enabled in Zero Data Loss Mode.   ← without ORA-16827 warning

   DGMGRL> SHOW FAST_START FAILOVER;
   # Mode: ZERO DATA LOSS
   ```

**Conditions for `ALTER DATABASE FLASHBACK ON`:**
- Database in MOUNT mode (NOT OPEN — bounce required on STBY in 19c and 23ai/26ai)
- `db_recovery_file_dest` configured (FRA) — in our lab `/u03/fra` from FIX-049
- `db_recovery_file_dest_size` >= 14G (default in FIX-049)
- `db_flashback_retention_target` optional (default 1440 min = 24h)

**TODO v3.4 for `duplicate_standby.sh`:** add section 9c:
```bash
# After section 9b (log_archive_dest_2 FIX-049):
log "Section 9c — Enable Flashback Database on STBY (FIX-076)..."
sqlplus / as sysdba <<EOF
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE FLASHBACK ON;
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION USING CURRENT LOGFILE;
EXIT
EOF
```

This will automate recovery — the next clean rebuild will have Zero Data Loss Mode on first attempt.

**Universal lesson:**
- **FSFO != ENABLE OK.** ENABLE FAST_START FAILOVER may return success but in `Potential Data Loss Mode` (warning, not error). Script verify must check **Mode**, not just Status.
- **Flashback is per-database**, NOT replicated by RMAN duplicate. Must be enabled separately on each side (PRIM via DBCA/manual, STBY post-duplicate).
- **`ALTER DATABASE FLASHBACK ON` on STBY requires MOUNT** (bounce from OPEN READ ONLY). Plus stop apply → enable flashback → start apply with USING CURRENT LOGFILE.
- **Pre-flight in FSFO scripts** must check flashback on **both** sides, not just local.

---

### FIX-077 — `Potential Data Loss Mode` in MaxAvailability is BY DESIGN (not a bug)

**Status:** **RESOLVED empirically** (2026-04-26 23:37, ORA-16903).

#### TL;DR

In Oracle 23ai/26ai, broker FSFO Mode is **strictly determined** by Protection Mode:

| Protection Mode | LagLimit allowed | FSFO Mode (SHOW FSFO) |
|---|---|---|
| **MaxProtection** | 0 or > 0 | **Zero Data Loss Mode** |
| **MaxAvailability** | **MUST be > 0** (broker rejects 0 with ORA-16903) | **Potential Data Loss Mode** (always) |
| MaxPerformance | any | Potential Data Loss Mode (always) |

**MaxAvailability + LagLimit=0 = ORA-16903** (broker enforces, not a configuration oversight).

#### Empirical proof

Session 23:37 — all pre-conditions OK:
- LogXptMode=SYNC on PRIM + stby
- protection_mode = MAXIMUM AVAILABILITY
- protection_level = MAXIMUM AVAILABILITY (matches, no downgrade)
- transmit_mode = PARALLELSYNC, affirm = YES, status = VALID, error = empty
- Apply Lag 0s, Transport Lag 0s, Database Status SUCCESS on both
- flashback_on = YES on both
- LagLimit = 30 (Oracle default)

`SHOW FAST_START FAILOVER` → `Enabled in Potential Data Loss Mode`. Attempting to change LagLimit:
```
DGMGRL> EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
Error: ORA-16903: change of FastStartFailoverLagLimit property violates configuration protection mode
```

**Conclusion:** broker **enforces** that MaxAvailability MUST have LagLimit > 0. Consequence: in MaxAvailability the FSFO Mode is **always** "Potential Data Loss Mode" in SHOW, regardless of SYNC+AFFIRM+Flashback.

#### What "Potential Data Loss Mode" actually means

**`Potential` ≠ actual data loss.** This is broker's theoretical classification:
- With SYNC+AFFIRM: primary doesn't commit until standby acks → real-world zero data loss
- Apply lag = 0s consistently (real-time apply with SRL) → at every failover decision lag=0
- Broker allows that *theoretically* with LagLimit > 0 it could accept failover with lag > 0 → "potential"
- In lab/production with stable SYNC → "potential" never materializes

#### Hypothesis 1 (my initial FIX-077) — partially correct, partially wrong

**Correct:** LagLimit does affect FSFO Mode classification.
**Wrong:** I assumed this could be "fixed" by `LagLimit=0`. Broker enforces protection mode rules → ORA-16903. Fix is not possible in MaxAvailability.

#### Hypothesis 2 (second agent — transport ASYNC) — incorrect

**Empirically disproved:** transport is PARALLELSYNC + AFFIRM (SYNC), protection_level matches protection_mode. From a transport perspective everything is OK. "Potential Data Loss Mode" doesn't originate from transport mode.

#### Design decision

Lab MAA Oracle 26ai stays with:
- **Protection Mode: MaxAvailability** (production standard)
- **LagLimit: 30** (Oracle default, mandatory > 0)
- **FSFO Mode: Potential Data Loss Mode** (display) — accepted as correct steady-state

**Alternative for educational "Zero Data Loss Mode" in SHOW:**

Migrate to MaxProtection (caveat: primary shuts down when standby unreachable):
```
DGMGRL> EDIT CONFIGURATION SET PROTECTION MODE AS MaxProtection;
DGMGRL> EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
DGMGRL> DISABLE FAST_START FAILOVER;
DGMGRL> ENABLE FAST_START FAILOVER;
# Enabled in Zero Data Loss Mode.
```

Not doing this in lab (want production-realistic config). Doc 14 switchover/failover tests work identically in both modes.

#### Script v1.9 (rollback FIX-077 partial fix, acceptance of steady-state)

```bash
# Section 6 dgmgrl heredoc (NO changes from v1.8):
EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=30;   # mandatory > 0 for MaxAvail
EDIT DATABASE PRIM SET PROPERTY LogXptMode='SYNC';   # sanity re-set (defensive after flashback recovery)
EDIT DATABASE stby SET PROPERTY LogXptMode='SYNC';
```

**Section 9 verify Mode:** info-only logging (not warn or die):
- `Mode: ZERO DATA LOSS` → log "✓ Zero Data Loss Mode"
- `Mode: POTENTIAL DATA LOSS` → log "ℹ EXPECTED for MaxAvailability + LagLimit > 0; actual risk = 0 with SYNC+AFFIRM"

#### Universal lessons

1. **`Potential Data Loss Mode` ≠ ASYNC transport.** Empirically disproved popular hypothesis (second agent). Transport can be SYNC+AFFIRM and Mode still "Potential" — depends on Protection Mode.
2. **Can't "fix" Mode in MaxAvailability** with LagLimit=0 — broker enforces ORA-16903.
3. **MaxProtection** = only path to "Zero Data Loss Mode" in SHOW — caveat primary shutdown.
4. **In production MAA** Oracle: MaxAvailability + LagLimit > 0 + "Potential Data Loss Mode" is standard. Real zero loss with SYNC+AFFIRM.
5. **FSFO Mode anomaly diagnostics** — check protection_mode, LagLimit, broker enforces:
   - MaxAvailability MUST LagLimit > 0 → Mode = Potential (always)
   - MaxProtection MAY LagLimit = 0 → Mode = Zero Data Loss
   - MaxPerformance → Mode = Potential (always)

---

## 2026-04-27

### FIX-078 — Custom listeners 1522 and STBY DB don't auto-start after VM reboot (broker `ORA-16664/16631` after cold restart)

**Problem:** After cold STOP + cold START of the whole lab (3 listeners + STBY DB gracefully shutdown in session #1, then VM reboot in session #2), broker showed:

```
stby - (*) Physical standby database (disabled)
  ORA-16906: The member was shutdown.
ENABLE DATABASE stby; → ORA-16626: failed to enable specified member
                       ORA-16631: operation requires shutdown of database or instance ""

# After STARTUP MOUNT on STBY + ENABLE DATABASE stby:
stby - (*) Physical standby database
  Error: ORA-16664: unable to receive the result from a member
Configuration Status: ERROR
```

**Diagnostics (actual, step by step):**

```bash
# 3 listeners 1522 — all DOWN after VM reboot
ssh oracle@stby01 "lsnrctl status LISTENER_DGMGRL"
# TNS-12541: Cannot connect. No listener at host stby01.lab.local port 1522.
ssh grid@prim01 "lsnrctl status LISTENER_PRIM_DGMGRL"
# TNS-12541: Cannot connect. No listener at host prim01.lab.local port 1522.
ssh grid@prim02 "lsnrctl status LISTENER_PRIM_DGMGRL"
# TNS-12541: Cannot connect. No listener at host prim02.lab.local port 1522.

# Verify these are static listeners (not CRS resources):
ssh grid@prim01 "crsctl stat res -t | grep -i dgmgrl"
# (empty - no CRS resource ora.listener_prim_dgmgrl.lsnr)
```

**Root cause (3 separate gaps in the auto-start mechanism):**

1. **`LISTENER_PRIM_DGMGRL` on prim01/02** added by manual patch FIX-050 as a *static entry in listener.ora* in Grid Home. Grid CRS auto-starts **only** listeners registered as CRS resources (`ora.LISTENER.lsnr`, `ora.LISTENER_SCAN1.lsnr` etc.). Static entries added directly to `listener.ora` are unnoticed by Grid on CRS boot — require manual `lsnrctl start` or a separate auto-start mechanism.

2. **`LISTENER_DGMGRL` on stby01** added by `duplicate_standby.sh` v3.3 section 4 — DB Home, no Grid on stby01 (Single Instance), no systemd unit. Script does `lsnrctl start` once at duplication time, but after VM reboot the listener doesn't come up on its own.

3. **STBY DB** — Single Instance without Grid, no systemd unit, no `dbstart` in `/etc/oratab` with Y flag. After VM reboot the database stays DOWN. Broker (if it managed the member before shutdown) remembers state as `ORA-16906 was shutdown` and on `ENABLE DATABASE` requires the member to be at minimum in MOUNT (DMON active) — without DMON on STBY, broker DMON on PRIM gets `ORA-16664/16631` (empty instance name = "can't establish contact with target DMON").

**Fix — two-level:**

**(A) Immediate workaround** (in `OPERATIONS.md` v1.2 → v1.3, step 2.5 + step 3 prefix cold START):

```bash
# After step 2 (start prim01/02):
ssh grid@prim01 "lsnrctl start LISTENER_PRIM_DGMGRL"
ssh grid@prim02 "lsnrctl start LISTENER_PRIM_DGMGRL"

# After startvm stby01 (before STARTUP DB):
ssh oracle@stby01 "lsnrctl start LISTENER_DGMGRL"
```

**(B) Permanent fix** (2 new scripts in `VMs/scripts/`):

1. **`enable_listener_autostart_prim.sh`** (one-time, as grid on prim01 + prim02):
   - `srvctl add listener -listener LISTENER_PRIM_DGMGRL -endpoints "TCP:1522" -oraclehome $ORACLE_HOME`
   - `srvctl modify listener -listener LISTENER_PRIM_DGMGRL -autostart always`
   - Static `SID_LIST_LISTENER_PRIM_DGMGRL` in listener.ora stays (Grid honors SID_LIST static on start)
   - After deploy, listener is a CRS resource (`ora.listener_prim_dgmgrl.lsnr`) with `AUTO_START=ALWAYS` → starts on every `crsctl start crs`

2. **`enable_autostart_stby.sh`** (one-time, as root on stby01) — installs 2 systemd units:
   - `oracle-listener-dgmgrl.service` (Type=forking, User=oracle, ExecStart `lsnrctl start LISTENER_DGMGRL`, ExecStop `lsnrctl stop`)
   - `oracle-database-stby.service` (After=oracle-listener-dgmgrl, ExecStart `STARTUP MOUNT;`, ExecStop `RECOVER ... CANCEL; SHUTDOWN IMMEDIATE;`)
   - Both `systemctl enable` → auto-start on reboot
   - DB starts only to `MOUNT` (broker takes control via `ENABLE DATABASE` or auto-recovery if FSFO ENABLED and member registered)

**Why STBY DB only to `MOUNT`, not `OPEN READ ONLY`?**

Data Guard Broker requires managed restart via DMON for a member in `disabled` state. If systemd does full `OPEN READ ONLY + RECOVER MANAGED STANDBY USING CURRENT LOGFILE`, the database is UP but **without broker control** — broker still sees the `disabled` flag in metadata. `ENABLE DATABASE stby` then gives `ORA-16631 operation requires shutdown` (broker wants to start it itself). With `STARTUP MOUNT`-only, DMON is active, broker touches the member and does OPEN+RECOVER itself according to properties.

**Fix test:**

```bash
# 1. Deploy both scripts (once)
ssh grid@prim01 "bash /tmp/scripts/enable_listener_autostart_prim.sh"
ssh grid@prim02 "bash /tmp/scripts/enable_listener_autostart_prim.sh"
ssh root@stby01 "bash /tmp/scripts/enable_autostart_stby.sh"

# 2. Verify CRS + systemd
ssh grid@prim01 "crsctl stat res ora.listener_prim_dgmgrl.lsnr -t"
# Expected: STATE=ONLINE, AUTO_START=always
ssh root@stby01 "systemctl is-enabled oracle-listener-dgmgrl.service oracle-database-stby.service"
# Expected: enabled / enabled

# 3. Test: cold STOP + cold START whole lab
# After reboot everything comes up automatically:
#   - LISTENER_PRIM_DGMGRL via Grid (CRS)
#   - LISTENER_DGMGRL + STBY MOUNT via systemd
# Broker DMON STBY active, ENABLE FSFO takes over member without ORA-16631/16664
```

**Files:** `VMs/scripts/enable_listener_autostart_prim.sh` (NEW), `VMs/scripts/enable_autostart_stby.sh` (NEW), `VMs/OPERATIONS.md` v1.3 (step 2.5 + step 3 + section "Permanent fix")

**Impact for reinstalls:** ideally `duplicate_standby.sh` v3.4 should call both scripts at the end (as root + grid). Currently they remain as manual deploy steps after doc 09.

**Lesson:** In RAC everything that should start after reboot **must** be a CRS resource (auto-start) or systemd unit. Static entries in `listener.ora` are honored by the listener after startup, but **don't start themselves** — Grid auto-starts only listeners that are CRS resources. Single Instance without Grid requires systemd. **Audit:** every port/service created manually (outside standard Grid/DBCA flow) must be explicitly provided with an auto-start mechanism — otherwise cold restart loses it.

---

### FIX-079 — `configure_broker.sh` v2.10 enforces auto-start pre-flight (DRY enforcement without cross-user sudo)

**Problem:** After FIX-078 we have 2 separate scripts (`enable_listener_autostart_prim.sh` as grid, `enable_autostart_stby.sh` as root) that MUST be run before `configure_broker.sh`. But nothing in `configure_broker.sh` v2.9 enforces this — user can forget and broker gets configured without auto-start, losing itself at the first cold restart.

**Why not integrate directly?** `configure_broker.sh` runs as `oracle`, while `srvctl add listener` requires `grid`. Full integration would require:
- sudoers `oracle ALL=(grid) NOPASSWD:` or
- SSH equivalency `oracle@prim01 → grid@prim01` (cross-user, non-standard)
- Mixing lifecycles (auto-start = once per cluster; broker enable = single-shot)

All 3 above are new complications bigger than the problem.

**Solution (compromise):** `configure_broker.sh` v2.10 section 0.2b adds pre-flight check **without** cross-user sudo:

1. **LISTENER_PRIM_DGMGRL CRS check** — `$GRID_HOME/bin/srvctl config listener -listener LISTENER_PRIM_DGMGRL` (oracle with group `osdba`/`asmdba` has srvctl read permission in 23ai/26ai). Detect Grid Home via `awk -F: '/^\+ASM[0-9]*:/{print $2}' /etc/oratab`. **Hard die** if FAIL with hint to run `enable_listener_autostart_prim.sh`.

2. **stby01 systemd check** — `ssh -o BatchMode=yes oracle@stby01 "systemctl is-enabled oracle-listener-dgmgrl.service oracle-database-stby.service"` (oracle SSH equivalency exists from Grid install; `systemctl is-enabled` is read-only, doesn't require sudo). **Soft warn** if FAIL with hint to `enable_autostart_stby.sh` — because tnsping STBY_ADMIN above already verified the **live state** of the listener (it's UP now, only persistence after reboot is in question).

**Symptom before FIX-079:** broker enabled + FSFO armed → cold restart → 1522 listeners down → broker `Configuration Status: ERROR (ORA-16664)` → user doesn't know why, digs for 1h.

**Symptom after FIX-079:** broker enable fails immediately with the exact command to run. User reads die-message, does 1 SSH, restarts script. Broker SUCCESS in fully armed state, cold restart auto-recovery works.

**Files:** `VMs/scripts/configure_broker.sh` v2.9 → v2.10 (+~30 lines in section 0.2b NEW).

**Lesson:** Cross-script dependency without integration = pre-flight enforcement in the *consumer* script. Better than integration with cross-user sudo or than plain documentation "remember to run X before Y". Similar pattern in `setup_observer_infra01.sh` (section 4 checks Configuration Status SUCCESS before ENABLE FSFO — FIX-068).

---

### FIX-080 — `deploy_tac_service.sh` v1.3 — production hardening patch (6 fixes before doc 12 deploy)

**Problem:** `deploy_tac_service.sh` v1.2 (FIX-052+057) was 90% ready but an audit before deploy (session 2026-04-27, Explore agent) found 8 gaps. 6 of them (HIGH+MED) addressed in v1.3 (LOW skipped: F6 CRLF encoding, F8 doc-script drift handled separately).

**Audit findings (from Explore agent report):**

| ID | Sev | Problem | Location |
|---|---|---|---|
| F1 | HIGH | Missing `-failover_restore LEVEL1` (present in `bash/tac_deploy.sh` v1.0, but not in VMs/scripts/deploy_tac_service.sh) | `deploy_tac_service.sh:106` |
| F3 | HIGH | Missing pre-flight DG Broker SUCCESS check — TAC without working broker = TAC without purpose (broker triggers failover) | section 0 |
| F2 | MED | Post-flight doesn't call `tac_replay_monitor.sql` — blind spot for replay sanity | section 3 |
| F4 | MED | Idempotency incomplete — service exists → log instead of warn (attribute drift hidden) | line 97 |
| F5 | MED | Port 6200 (ONS) prim→stby not validated — FAN events may not reach clients | section 0 |
| F7 | MED | ONS daemon on stby01 (Single Instance without Grid) not checked — requires manual `onsctl start` | section 0 |

**Fix (v1.3, +~100 lines):**

1. **F1 — `-failover_restore LEVEL1`** (line 106 srvctl add service):
   - LEVEL1 = auto-restore session on same instance after its restart. Oracle default = NONE → client must reconnect manually.
   - Oracle TAC standard since 19c. Consistency with `bash/tac_deploy.sh` v1.0 and `docs/TAC-GUIDE.md` § 4.2.

2. **F3 — Section 0.5 NEW DG Broker SUCCESS check**:
   - Wallet `/@PRIM_ADMIN` is ONLY on infra01 (from `setup_observer_infra01.sh`). From prim01 no wallet → `dgmgrl /@PRIM_ADMIN` returns auth error.
   - Workaround: `ssh -o BatchMode=yes oracle@infra01 "dgmgrl /@PRIM_ADMIN 'SHOW CONFIGURATION'"`. Multiline grep via `tr '\n' ' '` (FIX-065 pattern).
   - **Hard die** if `Configuration Status: WARNING/ERROR`. **Soft warn** if SSH to infra01 unreachable (continue).

3. **F2 — Section 3b NEW post-flight replay monitor**:
   - For freshly-created service expected `requests_total=0` → evaluated as IDLE.
   - After failovers/replays should be PASS (>=95% success rate).
   - Heuristic: warn if grep `\bCRIT\b` in output of `tac_replay_monitor.sql` section 1.

4. **F4 — `log` → `warn` on idempotency** (line 97):
   - Service exists → warn with hint to `srvctl remove` if attributes drifted (e.g. missing `-failover_restore LEVEL1` from v1.2).
   - Without this, re-running script after upgrade to v1.3 won't fix the service — DBA must manually remove + re-add.

5. **F5 — `nc -zv -w5 ${STBY_HOST} 6200`** (section 0.7):
   - Port 6200 (ONS) required for cross-site FAN events to UCP clients.
   - Soft warn (not die) — in lab firewall disabled, issue is ONS daemon (F7), not firewall.

6. **F7 — `ssh oracle@stby01 "onsctl ping"`** (section 0.6):
   - Single Instance without Grid → ONS starts manually. After reboot stby01 ONS stopped.
   - Soft warn with hint `onsctl start`. **TODO v1.2 enable_autostart_stby.sh:** add systemd unit `oracle-ons.service` (analogous to FIX-078 for listener + DB) — then F7 becomes redundant.

**Symptom before FIX-080:** TAC service deployed without `failover_restore` and without broker/ONS verification → UCP client after failover fails without replay (Oracle default failover_restore=NONE), or replay gives intermittent errors because broker doesn't respond. DBA debugging 1–2h before finding root cause.

**Symptom after FIX-080:** script blocks deploy if broker WARNING/ERROR (F3 hard die), warns for ONS/port 6200 issues (F5/F7 — user sees immediately what to fix). Service deployed with LEVEL1 + post-flight sanity via replay monitor.

**Files:**
- `VMs/scripts/deploy_tac_service.sh` v1.2 → v1.3 (+~100 lines, sections 0.5/0.6/0.7 + 3b)
- `VMs/12_tac_service.md` — section 1.1 srvctl add with `-failover_restore LEVEL1` (drift fix F8 highlighted)
- `VMs/12_tac_service.md` — prereq list extended (DG Broker SUCCESS, ONS daemon, port 6200 — items 2/6/7) + intro noticebox with description of v1.3 changes

**Lesson:** Pre-deploy audit by subagent (Explore) with specific questions ("parameter parity vs alternative scripts", "post-flight coverage", "cross-script deps") catches gaps that linear script reading would miss. Time: 5-min audit report → 30-min patch v1.3. Without audit: deploy v1.2 + 1–2h debugging during doc 14 tests.

---

### FIX-081 — `deploy_tac_service.sh` v1.3 hotfixes (4 issues during first run)

**Problem:** First run of script v1.3 exposed 4 issues hidden in v1.2 (which the old script also had, but without pre-flight enforcement they weren't felt):

1. **PDB lowercase service registration:** `lsnrctl services` in 23ai/26ai shows service as `apppdb.lab.local` (lowercase). Script `grep -qE "Service \"$PDB(\.lab\.local)?\""` with `$PDB="APPPDB"` (uppercase) **doesn't match**. False die "PDB not registered" even though `v$pdbs` shows OPEN READ WRITE. Fix: `grep -qiE` (case-insensitive).

2. **`srvctl modify ons -clusterid` PRKO-2002:** flag `-clusterid` was removed in 26ai. Single-cluster default — `-remoteservers` suffices. Fix: remove flag + soft-fail (`||true`) because ONS modify is not a blocker.

3. **CRS-0245 oracle vs grid:** `srvctl modify ons` modifies CRS resource `ora.ons` managed by Grid (grid user). Oracle gets `CRS-0245: doesn't have enough privilege`. Fix: hint to `ssh grid@prim01 "srvctl modify ons ..."` in warn.

4. **`retention_seconds` ORA-00904 (column name changed in 26ai):** column `retention_seconds` (19c) → `retention_timeout` (23ai/26ai). Plus `commit_outcome_enabled` → `commit_outcome`. Fix: SELECT with correct names.

5. **CRIT grep false positive:** v1.3 section 3b post-flight searches for `\bCRIT\b` in output of `tac_replay_monitor.sql` to detect replay failure. Output has section 6 "Summary" with legend `CRIT  = < 80% (non-replayable...)`. Grep matched the legend instead of status. Fix: stricter heuristic — extract only lines looking like result rows from section 1 (`^[[:space:]]*[0-9]+[[:space:]]+[0-9]+.*\b(IDLE|PASS|WARN|CRIT)\b`).

**Files:** `VMs/scripts/deploy_tac_service.sh` (5 inline hotfixes within v1.3, header note "FIX-081 hotfix"). `VMs/12_tac_service.md` sections 1.3 + 3.1 — columns `commit_outcome` + `retention_timeout` instead of 19c.

**Lesson:** Migration 19c → 23ai/26ai changes columns in `dba_services` (`retention_seconds → retention_timeout`, `commit_outcome_enabled → commit_outcome`) and srvctl options (`-clusterid` removed). Plus default service registration in 26ai is **lowercase** (differs from 19c uppercase). Every script that greps Oracle output must be case-insensitive or accept both variants.

---

### FIX-082 — 26ai SQL variants + ONS configuration on stby01 (cross-site FAN)

**Problem:** After FIX-081 the script deploys TAC service OK, but 3 separate gaps blocked cross-site FAN events and TAC readiness checks:

#### Gap 1: GV$REPLAY_STAT_SUMMARY removed in 23ai/26ai

`<repo>/sql/tac_full_readiness.sql` section 11 and `tac_replay_monitor.sql` section 1 use `GV$REPLAY_STAT_SUMMARY` — a view that **was removed** in 23ai/26ai. After `desc all_views WHERE name LIKE '%REPLAY%'` in 26ai only per-context views are visible (`GV$REPLAY_CONTEXT`, `GV$REPLAY_CONTEXT_LOB`, `GV$REPLAY_CONTEXT_SEQUENCE`, `GV$REPLAY_CONTEXT_SYSDATE`, `GV$REPLAY_CONTEXT_SYSGUID`, `GV$REPLAY_CONTEXT_SYSTIMESTAMP`). No aggregated summary view.

**Fix:** Created two `_26ai` variants with patched sections 11/1 — aggregation per-instance from `GV$REPLAY_CONTEXT`:
- `<repo>/sql/tac_full_readiness_26ai.sql` (copy + patch section 11)
- `<repo>/sql/tac_replay_monitor_26ai.sql` (copy + patch section 1)

Status logic in 26ai variant:
- `IDLE` = no replay contexts (fresh service, no traffic)
- `PASS` = all *_REPLAYED >= *_CAPTURED (100% replay rate)
- `WARN` = some category *_REPLAYED < *_CAPTURED (partial replay)

`deploy_tac_service.sh` v1.3+ has helper `pick_sql()` which auto-prefers `_26ai` variant with fallback to original. User uploads both files, script selects automatically.

#### Gap 2: `ons.config` on stby01 — custom ports + missing `nodes=` directive

Default `ons.config` post-Oracle 23.26 install (Single Instance without Grid) has:
```
usesharedinstall=true
localport=6199    # NON-STANDARD (PRIM RAC uses 6100)
remoteport=6299   # NON-STANDARD (PRIM RAC uses 6200)
                  # MISSING 'nodes=' → ONS binds only 127.0.0.1
```

Plus `useocr=off` — this is a **deprecated key** in 26ai (throws `[ERROR:1] [parse] unknown key: useocr`, non-fatal but ugly).

**Fix (manual):**
```bash
ssh oracle@stby01 'cat > $ORACLE_HOME/opmn/conf/ons.config <<EOF
usesharedinstall=true
localport=6100
remoteport=6200
nodes=stby01.lab.local:6200,prim01.lab.local:6200,prim02.lab.local:6200
EOF
onsctl stop 2>/dev/null; onsctl start && onsctl ping'
```

After fix: `ss -ntlp | grep 6200` shows `LISTEN *:6200` (external bind). Cross-site FAN events work.

#### Gap 3: `nc -zv` heuristic — ncat vs BSD nc + `set -e + pipefail` kill

Script v1.3 used `grep -qiE "succeeded|open"` on output of `nc -zv`. But on OL8 nc is **ncat from nmap-package**, output:
- `Connected to stby01.lab.local.` (success — doesn't contain "succeeded" or "open")
- `Ncat: Connection refused` (fail)

**Fix 1:** Extended grep `succeeded|open|connected to` (case-insensitive).
**Fix 2:** Fallback `bash /dev/tcp/${host}/6200` — always available in bash 4+ (doesn't require nc/ncat). More reliable check.

Plus discovered **`set -o pipefail`** bug in section 3b: `SECTION1_STATUS=$(echo $REPLAY_OUT | grep -E '...' | head -5)`. When grep doesn't match (0 rows), returns exit 1, pipefail propagates exit to command substitution, set -e kills script **before** printing final DONE. **Fix:** add `|| true` at end of pipe.

#### Gap 4: `srvctl modify ons` PRKO-2396 false-warn

Output PRKO-2396 "The list of remote host/port ONS pairs matches the current list" is **idempotency success** (no-op when config already matches). Script `grep -q "PRKO-\|PRCR-\|CRS-"` treated it as fail. **Fix:** explicit branch for PRKO-2396 → log success.

**Files:**
- `<repo>/sql/tac_full_readiness_26ai.sql` (NEW, ~590 lines)
- `<repo>/sql/tac_replay_monitor_26ai.sql` (NEW, ~270 lines)
- `VMs/scripts/deploy_tac_service.sh`: `pick_sql()` helper + 4 hotfixes (PRKO-2396 success branch, ncat/dev-tcp fallback, section 0.6 grep "is not running", pipefail `|| true`)
- `VMs/12_tac_service.md`: section 2.1 (grid + without `-clusterid`), section 2.2 (ons.config without `useocr`, mesh `nodes=`), section 1.3 (lowercase noticebox), section 6 (`_26ai` variant preferred)
- `VMs/04_os_preparation.md`: SQL_DIR table with `_26ai` variants + `pick_sql()` reference

**Lesson:** Migration 19c → 23ai/26ai removes some views (`GV$REPLAY_STAT_SUMMARY` → per-context views). Strategy of `_26ai` suffix for SQL files + `pick_sql()` helper for scripts = clean version separation without modifying the original (preserves 19c/21c compat). Plus `bash /dev/tcp/host/port` is a portable replacement for `nc -zv` (differences ncat vs BSD nc) — reliable on OL8.

---

### FIX-083 — `enable_autostart_stby.sh` v1.2 — `oracle-ons.service` systemd unit (3 units instead of 2)

**Problem:** After FIX-082 ONS on stby01 is running (`onsctl start` after patching `ons.config`), but **`onsctl start` is one-shot** — after every stby01 reboot it must be started manually. Cross-site FAN events to UCP clients **won't work** after cold restart without manual intervention. Identical auto-start gap pattern as FIX-078 for LISTENER_DGMGRL/STBY DB.

**Fix:** `enable_autostart_stby.sh` v1.1 → v1.2 — adding a 3rd systemd unit:

#### Structure v1.2 (3 units instead of 2)

```
oracle-listener-dgmgrl.service (port 1522)
    ↓ After=
oracle-ons.service (port 6100/6200, FAN events)        [NEW v1.2]
    ↓ After=
oracle-database-stby.service (STARTUP MOUNT)
```

Full boot ordering: `network → listener → ONS → DB MOUNT`. Listener must be first (DGMGRL uses it), ONS before DB (broker DMON publishes FAN events via ONS), DB last.

#### Implementation

**Section 2b NEW — helper scripts:**
```bash
/usr/local/bin/oracle-ons-start.sh:
    export ORACLE_HOME=...
    $ORACLE_HOME/opmn/bin/onsctl start
/usr/local/bin/oracle-ons-stop.sh:
    $ORACLE_HOME/opmn/bin/onsctl stop
```

**Section 2c NEW — `ons.config` pre-flight:**
- Checks existence of `$ORACLE_HOME/opmn/conf/ons.config`
- Checks `localport=6100` (default 23.26 has non-standard `6199`)
- Checks `nodes=` directive (without this ONS binds only localhost)
- Soft warn with hint to doc 12 section 2.2 if config needs adjustment

**Section 3a NEW — `oracle-ons.service` systemd unit:**
```ini
[Unit]
After=oracle-listener-dgmgrl.service network-online.target

[Service]
Type=forking
User=oracle
ExecStart=/usr/local/bin/oracle-ons-start.sh
ExecStop=/usr/local/bin/oracle-ons-stop.sh
ExecReload=$ORACLE_HOME/opmn/bin/onsctl reload    ← reload without dropping FAN events
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Update `oracle-database-stby.service`:** `After=` and `Wants=` extended with `oracle-ons.service` — DB won't start until ONS is UP.

#### After deploy (cold restart test)

```bash
# After reboot stby01:
ssh root@stby01 "systemctl status oracle-listener-dgmgrl oracle-ons oracle-database-stby --no-pager"
# Expected: 3 × active (running) + status: SUCCESS

# Sanity check ONS external bind
ssh root@stby01 "ss -ntlp | grep -E ':6[12]00'"
# Expected: LISTEN *:6200 (external) + 127.0.0.1:6100 (local)

# Connectivity from prim01
ssh oracle@prim01 "timeout 5 bash -c 'echo > /dev/tcp/stby01.lab.local/6200' && echo OK"
```

**Files:**
- `VMs/scripts/enable_autostart_stby.sh` v1.1 → v1.2 (~80 lines added: 2 helper scripts + ons.config pre-flight + ONS unit + dependency in DB unit)
- `VMs/09_standby_duplicate.md` section 9b — mention of 3 units (was 2)
- `VMs/12_tac_service.md` section 2.2 — remove TODO + note about `systemctl reload` for runtime ons.config changes

**Lesson:** Every daemon/service that should persist after reboot must be under systemd or CRS. After FIX-078 (1522 listeners + STBY DB) and FIX-083 (ONS) we have a complete self-healing cold restart on stby01: VM boot → 3 units start in correct order → broker takes DB → cross-site FAN to UCP clients. **TODO doc 16:** consider moving all 3 units to a separate role-deployment (`prepare_host.sh --role=si-standby` could install systemd units from the start).

---

### FIX-084 — `13_client_ucp_test.md` patch (TestHarness.java replay-capable + cross-references)

**Problem:** Doc 13 audit (Explore agent, session 2026-04-27) found a **CRITICAL bug** in TestHarness.java that would block TAC replay in the UCP client test. Plus cross-references to server-side prereqs (FIX-080/081/082/083) set up in docs 09–12 were missing.

**Audit findings:**

| ID | Sev | Problem | Location |
|---|---|---|---|
| F1 | **CRITICAL** | `pds.setConnectionFactoryClassName("oracle.jdbc.pool.OracleDataSource")` — standard DataSource **does NOT support replay**. After failover client gets ORA-03113 instead of transparent replay | `13_client_ucp_test.md:182` |
| V_C_O_B | LOW | Missing `setValidateConnectionOnBorrow(true)` — UCP best practice for TAC (filters stale connections post-failover) | section 5 TestHarness |
| F3 | MED | Missing prereq context about `failover_restore=LEVEL1` from doc 12 (FIX-080). Operator doesn't know that without it replay won't work | section 7 |
| F6 | LOW | Troubleshooting references `gv$replay_stat_summary` (removed in 26ai, FIX-082) | section 10 |
| F8 (own) | LOW | Missing mention that PDB/service registered **lowercase** in listener (FIX-081). Operator searching for "Service \"MYAPP_TAC\"" in `lsnrctl services` may not find it (lowercase) | section 10 |

**Skipped findings (agent's report was overenthusiastic):**
- F4 (stby02 missing from ONS): agent assumed "2-node STBY RAC" from `INTEGRATION-GUIDE.md`, but **our lab has SI stby01 (Single Instance without Grid)** — 3 nodes in ONS mesh (`prim01,prim02,stby01`) are correct.
- F2/F5 (compatibility note 23.x vs 19.x): cosmetic, low priority.
- F7 (`OracleReplayDriverContext`): advanced use case, not needed for baseline test.

**Fix (5 edits in doc 13):**

#### Edit 1 — section 5 TestHarness.java (F1 CRITICAL):
```java
// BEFORE (broken):
pds.setConnectionFactoryClassName("oracle.jdbc.pool.OracleDataSource");

// AFTER (FIX-084):
pds.setConnectionFactoryClassName("oracle.jdbc.replay.OracleDataSourceImpl");
```
Without this change: UCP doesn't know LTXID, client gets ORA-03113 after failover, replay doesn't work.

#### Edit 2 — section 5 (V_C_O_B):
```java
pds.setValidateConnectionOnBorrow(true);   // NEW: UCP filters stale connections
```

#### Edit 3 — section 5 noticebox about lab topology:
Added comment that ONS mesh `prim01,prim02,stby01` (3 nodes, NOT 4 with stby02) is correct for SI standby. Plus reference to `enable_autostart_stby.sh` v1.2 (FIX-083) for persistence.

#### Edit 4 — section 7 noticebox prereq server-side:
4-point checklist to run BEFORE test:
1. `srvctl config service` contains all TAC params (TRANSACTION + LEVEL1 + TRUE + DYNAMIC + 86400 + 1800)
2. `oracle-ons.service` active on stby01 (FIX-083 systemd)
3. Cross-site ONS on PRIM (`srvctl config ons` as grid, FIX-082)
4. Broker SUCCESS + FSFO ENABLED

Without this client gets ORA-03113 WITHOUT replay (cosmetic for DBA — points directly to what's wrong).

#### Edit 5 — section 10 troubleshooting:
- ORA-12514 problem: note about **lowercase service registration** (FIX-081). `lsnrctl services | grep -i myapp_tac` (case-insensitive).
- Replay not working: extended checklist (server-side: `failover_restore=LEVEL1`, client-side: `OracleDataSourceImpl`, `ValidateConnectionOnBorrow=true`, `FastConnectionFailoverEnabled=true`)
- NEW problem entry: `gv$replay_stat_summary` ORA-00942 → use `_26ai` variant from FIX-082

**Files:** `VMs/13_client_ucp_test.md` (5 edits, ~60 lines added).

**Lesson:** TAC has **2 separate requirements** for replay — server-side (`failover_type=TRANSACTION + commit_outcome=TRUE + failover_restore=LEVEL1`) plus client-side (`OracleDataSourceImpl` factory, NOT `OracleDataSource`). Missing either = replay disabled. Client-side bug is "silent" — UCP connects OK, transactions commit OK, only failover reveals that factory doesn't have replay support. Pre-deploy audit by subagent caught this before test (15 min) instead of 2–3h debugging during doc 14 tests.

---

### FIX-085 — TNS structure fix (LOAD_BALANCE=ON on top level + 2 ADDRESS_LIST randomly picked group) + LISTENER:1521 stby01 manual start

**Problem 1 (TNS):** First version of `tnsnames.ora` in doc 13 had 2 separate `ADDRESS_LIST` entries (each with one ADDRESS — first `scan-prim`, second `stby01`) with `LOAD_BALANCE=ON` and `FAILOVER=ON` on top-level `DESCRIPTION`. Oracle Net treats this as 2 address groups and with `LOAD_BALANCE=ON` **randomly picks which group** to use. Client could end up on `stby01:1521` (second group) even though PRIM RAC is active — `ORA-12541: No listener` (if LISTENER:1521 stby01 is down) or `ORA-12514` (if up but no service).

**Problem 2 (LISTENER stby01):** After reboot stby01 this morning `LISTENER:1521` (DB Home, port 1521) was **DOWN**. `enable_autostart_stby.sh` v1.2 (FIX-083) has systemd units only for:
- `oracle-listener-dgmgrl.service` (port 1522)
- `oracle-ons.service` (port 6100/6200)
- `oracle-database-stby.service` (DB MOUNT)

No unit for `LISTENER:1521`. After failover MYAPP_TAC service will register with `LISTENER:1521` on stby01 → client needs listener:1521 UP. Currently requires manual `lsnrctl start LISTENER`.

**Fix Problem 1:** doc 13 section 4 — single `ADDRESS_LIST` with `LOAD_BALANCE=OFF` + `FAILOVER=ON` (deterministic order: SCAN-PRIM first, stby01 second as post-failover fallback):
```
(ADDRESS_LIST =
    (LOAD_BALANCE = OFF)
    (FAILOVER = ON)
    (ADDRESS = (HOST = scan-prim.lab.local)(PORT = 1521))
    (ADDRESS = (HOST = stby01.lab.local)(PORT = 1521))
)
```

**Fix Problem 2 (DONE in FIX-089 — `enable_autostart_stby.sh` v1.3):** added 4th systemd unit `oracle-listener-stby.service` for LISTENER:1521 (DB Home as oracle, ExecStart `lsnrctl start LISTENER`, ExecStop `lsnrctl stop LISTENER`). Analogous to FIX-078/083 pattern. See FIX-089 for full context.

**Files:** `VMs/13_client_ucp_test.md` section 4 (TNS structure fix). Part of v1.3 script — see FIX-089.

**Lesson:** `LOAD_BALANCE=ON` on top-level `DESCRIPTION` with multiple `ADDRESS_LIST` randomly picks **address groups**. For deterministic failover (prefer one, fall back to other) use a **single** `ADDRESS_LIST` with `LOAD_BALANCE=OFF` + `FAILOVER=ON` + addresses in preferred order.

---

### FIX-086 — `SERVICE_NAME` in TNS must include `db_domain` suffix (`.lab.local`) in 26ai

**Problem:** After TNS structure fix (FIX-085) client from client01 still got `ORA-12514: Service MYAPP_TAC is not registered with the listener at host 192.168.56.13`. Even though:
- SCAN VIPs OK (192.168.56.31/32/33:1521 reachable)
- SCAN listeners running (LISTENER_SCAN1/2/3)
- After `ALTER SYSTEM REGISTER` on PRIM1+PRIM2, service `myapp_tac.lab.local` visible in SCAN listeners
- Another service `PRIM_APPPDB.lab.local` connects OK (with domain)

**Root cause:** In Oracle 23ai/26ai DBCA with `New_Database.dbt` template auto-appends `db_domain` to every service registered in the listener. Service `MYAPP_TAC` is registered as **`myapp_tac.lab.local`** (lowercase + domain `lab.local`). Client TNS with `(SERVICE_NAME = MYAPP_TAC)` (without domain) doesn't match:

```bash
# Verify db_domain
sqlplus / as sysdba <<EOF
SHOW PARAMETER db_domain
EOF
# db_domain                  string   lab.local

# Verify service registration in listener
lsnrctl services | grep -i myapp
# Service "myapp_tac.lab.local" has 1 instance(s)
```

**Fix:** `SERVICE_NAME = MYAPP_TAC.lab.local` (with domain) in TNS:
```
(CONNECT_DATA =
    (SERVER = DEDICATED)
    (SERVICE_NAME = MYAPP_TAC.lab.local)   ← FIX-086: must have .lab.local
)
```

**Symptom before fix:** `ORA-12514: Service MYAPP_TAC is not registered` (client looks for `MYAPP_TAC` in listener, listener has `MYAPP_TAC.lab.local`). False negative — service is active, just under a different name.

**Symptom after fix:** client connects OK via SCAN to PRIM RAC.

**Relation to FIX-040** (from previous session, `feedback_26ai_db_domain.md`): "26ai DBCA appends db_domain — service_names after DBCA New_Database.dbt is 'PRIM.lab.local'; tnsnames.ora MUST have fully qualified SERVICE_NAME". FIX-086 is the same pattern for a **custom service** (`MYAPP_TAC` created by `srvctl add service` in doc 12) — Grid also appends `db_domain` to the name registered in the listener.

**Files:** `VMs/13_client_ucp_test.md`:
- section 4 (TNS) — `SERVICE_NAME = MYAPP_TAC.lab.local` (instead of `MYAPP_TAC`)
- section 10 troubleshooting — entry "ORA-12514 Service ... is not registered" with 3 causes: (1) missing `db_domain`, (2) service not cross-registered to SCAN (requires `ALTER SYSTEM REGISTER`), (3) TNS_ADMIN drift

**Lesson:** In Oracle 23ai/26ai **all** services are registered in the listener with `db_domain` as suffix. Client TNS MUST use fully qualified service name (`<service>.<db_domain>`). Quick check: `lsnrctl services | grep -i <service>` shows full name with domain — copy 1:1 to TNS. Don't rely on uppercase aliasing — Oracle is case-insensitive but name lookup requires exact match after normalization (case-folded).

---

### FIX-087 — Java 17+ requires `--add-opens` for UCP TAC bytecode proxy generation

**Problem:** After compiling `TestHarness.java` (doc 13 section 5) on client01 with JDK 17, runtime fails on first `pds.getConnection()`:

```
Exception in thread "main" java.lang.IllegalStateException: cannot resolve or generate proxy
    at oracle.ucp.proxy.ProxyFactory.prepareProxy(ProxyFactory.java:512)
    at oracle.ucp.jdbc.PoolDataSourceImpl.getConnection(PoolDataSourceImpl.java:2117)
    at TestHarness.main(TestHarness.java:71)
```

**Root cause:** Java 17 introduced **JEP 396 (Strong encapsulation by default)** — reflective access to `java.base` modules (`java.lang`, `java.util`, `jdk.internal.misc`, `sun.nio.ch`) is **blocked by default**. UCP TAC uses bytecode proxy generation (CGLib-style) which injects dynamic classes implementing `java.sql.Connection` with additional methods for replay tracking. This requires deep reflection to internal classes that Java 17 closed.

In JDK 8/11 this was only a warning (`WARNING: An illegal reflective access operation has occurred`) — in JDK 17+ it's a **hard error**.

**Fix:** run `java` with 4 `--add-opens` flags:

```bash
java \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/java.util=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
  --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
  -cp '/opt/lab/jars/*:.' TestHarness
```

Each flag opens a specific package for `ALL-UNNAMED` (classes not in a module — typical for classpath-loaded apps).

**Alternative solutions (rejected):**

1. **JDK 11 instead of JDK 17** — works without flags, but Java 11 has EOL Sep 2026 for Oracle Premier Support. JDK 17 LTS is preferred for new deployments.

2. **`--enable-native-access=ALL-UNNAMED`** — only for JEP 442 (Foreign Function), won't help here.

3. **`-Djdk.module.illegalAccess=permit`** — removed in JDK 17 (worked in 9-16).

4. **Module-based deployment** (jpms) — would require module-info.java + remodeling UCP jars which don't support this out-of-box.

**Files:**
- `VMs/13_client_ucp_test.md` section 6 — compile + run with `--add-opens` block + helper script `/opt/lab/run_testharness.sh`
- `VMs/src/TestHarness.java` — header comment with hint about `--add-opens`

**Lesson:** Classic JDK 17 + legacy enterprise library problem (UCP, Hibernate, Spring < 6, EJB containers, etc.). Oracle UCP 23.x officially supports JDK 17 only with added `--add-opens` flags (Oracle JDBC docs § "Java 17 Compatibility"). Helper script `/opt/lab/run_testharness.sh` is the standard production pattern — wrapping 4 flag lines into one executable. Alternatively, add `JAVA_OPTS` with these flags to `/etc/profile.d/` and UCP picks them up automatically.

---

## FIX-088 — UCP `autoCommit=true` default + explicit `commit()` = `ORA-17273`

**Problem:** After fixing FIX-087 (`--add-opens`) and `ucp/lib/ucp11.jar` (instead of sqlcl-stripped variant), UCP TAC connection established correctly but every `conn.commit()` in the loop returns:

```
[1] ERROR: ORA-17273: Could not commit with auto-commit enabled.
[2] ERROR: ORA-17273: Could not commit with auto-commit enabled.
...
```

**Root cause:** UCP 23.x **default `autoCommit=true`** (change vs UCP 19.x where default was `false`). With auto-commit each DML is auto-committed by the driver, so explicit `conn.commit()` has nothing to commit — JDBC throws `ORA-17273` as "you can't manually commit when auto-commit handles it".

**Second layer of the problem:** **TAC replay requires explicit transaction control**. Auto-commit treats each statement as a separate transaction — TAC then replays individual INSERTs, not the whole logical unit. For complex transactions (e.g., A→B transfer in 2 INSERTs) auto-commit replays halves independently, breaking atomicity.

**Fix:** After `pds.getConnection()` add `conn.setAutoCommit(false)`:

```java
try (Connection conn = pds.getConnection()) {
    conn.setAutoCommit(false);   // FIX-088: explicit transaction control for TAC
    // ... INSERTs ...
    conn.commit();                // now works
}
```

**Alternative solution:** set globally on PoolDataSource via properties (Java 17+):
```java
java.util.Properties props = new java.util.Properties();
props.put("autoCommit", "false");
pds.setConnectionProperties(props);
```

In TestHarness the **per-connection** approach was chosen (clear and readable) as it is a lab demo. Production typically wraps in try-with-resources + connection helper.

**Files:**
- `VMs/src/TestHarness.java` — added `conn.setAutoCommit(false)` in try block
- `VMs/13_client_ucp_test.md` section 5 — TestHarness inline with setAutoCommit(false) + FIX-088 comment

**Lesson:** UCP 19.x → 23.x changed the default `autoCommit=false` → `autoCommit=true` — undocumented breaking change. TAC replay design also assumes explicit transaction control (multi-statement units). Treat auto-commit as a "second anti-pattern" alongside wrong factory class (FIX-084) — both are "silent failure" traps caught only at first runtime, not at compile time. Pre-deploy audit (Explore agent) caught only the factory issue; the setAutoCommit gotcha required an actual runtime test.

---

## FIX-089 — `enable_autostart_stby.sh` v1.2 → v1.3 — 4th systemd unit `oracle-listener-stby.service` (LISTENER:1521)

**Problem:** v1.2 installed 3 systemd units (`oracle-listener-dgmgrl.service` 1522, `oracle-ons.service`, `oracle-database-stby.service`), but **did not cover `LISTENER:1521`** (default DB listener on stby01 from DB Home). After stby01 reboot the listener:1521 stayed DOWN — required manual `lsnrctl start LISTENER`. This was an open TODO from FIX-085.

**Why critical before doc 14 scenario 2:** scenario 2 tests failover STBY → PRIMARY. After failover service `MYAPP_TAC` registers in `LISTENER:1521` on stby01 (db_unique_name=STBY, local default listener). A UCP client connecting via TNS (single ADDRESS_LIST with fallback `stby01.lab.local:1521`) hits that listener. If it is down after reboot — `ORA-12541: No listener at stby01:1521`, TAC replay will NOT execute, scenario 2 fails.

**Fix — `enable_autostart_stby.sh` v1.3:**

1. New unit `/etc/systemd/system/oracle-listener-stby.service`:
   ```
   [Unit]
   Description=Oracle Default Listener stby01 (LISTENER on port 1521 - DB + MYAPP_TAC after failover)
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=forking
   User=oracle
   Group=oinstall
   Environment=ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
   Environment=ORACLE_SID=STBY
   ExecStart=${ORACLE_HOME}/bin/lsnrctl start LISTENER
   ExecStop=${ORACLE_HOME}/bin/lsnrctl stop LISTENER
   RemainAfterExit=yes
   TimeoutStartSec=60
   TimeoutStopSec=30

   [Install]
   WantedBy=multi-user.target
   ```

2. Ordering extended:
   - `oracle-ons.service` — `After=oracle-listener-stby.service oracle-listener-dgmgrl.service network-online.target`
   - `oracle-database-stby.service` — `After=oracle-listener-stby.service oracle-listener-dgmgrl.service oracle-ons.service network-online.target`
   - Full boot ordering: `network → listener:1521 + listener:1522 → ONS → DB MOUNT`

3. Enable section 4: `systemctl enable oracle-listener-stby.service` (before the other 3).

4. Verify section 5: `systemctl is-enabled` on all 4 units.

5. Final summary (step 1 changed, step 8 added):
   - `1. oracle-listener-stby (FIX-085) will start LISTENER (port 1521)`
   - `8. After STBY->PRIMARY failover: MYAPP_TAC registers in LISTENER:1521 (UP)`

**Files:**
- `VMs/scripts/enable_autostart_stby.sh` v1.2 → v1.3 (header + section 1a NEW + ordering in 3a/3b + section 4/5 + final summary)
- `VMs/09_standby_duplicate.md` section 9b — heading "FIX-078, FIX-085", "**4 systemd units**" with bullet `oracle-listener-stby.service` first, verify with 4 units, helper scripts wildcard `oracle-{stby,ons}-{start,stop}.sh`
- `VMs/11_fsfo_observer.md` prereq section 3 — stby01 bullet with 4 units, criticality for doc 14 scenario 2 highlighted
- `VMs/FIXES_LOG.md` — FIX-085 update (TODO marked DONE in FIX-089) + this entry

**Lesson:** systemd auto-start for Single Instance without Grid requires **all** components in the chain network → listeners → ONS → DB. Missing default port 1521 listener in v1.0/v1.1/v1.2 was because only port 1522 was needed for DG broker; but TAC service on primary uses 1521 — and after failover STBY becomes primary. Pattern: **every port-bound Oracle service must have its own systemd unit or CRS resource** for auto-start, even if it "normally starts by itself" (LISTENER doesn't manage itself on reboot without systemd/CRS).

---

## FIX-090 — `validate_env.sh` v1.2 → v1.3 + NEW `fsfo_monitor_26ai.sql` (doc 14 vs 26ai audit)

**Problem:** Doc 14 audit before test scenarios detected that `validate_env.sh` v1.2 and `<repo>/sql/fsfo_monitor.sql` would throw `ORA-00942: table or view does not exist` on 26ai in `--full` mode. Additionally doc 14 sections had 19c-isms incompatible with the 26ai environment.

**Three root causes:**

1. **`fsfo_monitor.sql:281`** uses `gv$replay_stat_summary` — REMOVED in 23ai/26ai (replaced by per-context views: `GV$REPLAY_CONTEXT_*`). No `_26ai` variant existed — analogous to `tac_full_readiness.sql` → `tac_full_readiness_26ai.sql` from FIX-082.

2. **`validate_env.sh` v1.2** calls hardcoded names (`tac_full_readiness.sql`, `fsfo_monitor.sql`, `fsfo_broker_status.sql`) without auto-picking `_26ai` variants. Even though `tac_full_readiness_26ai.sql` existed, the script ignored it.

3. **Doc 14** not synchronized with 26ai findings from the session (FIX-072, 077, 082, 084-089) and referenced outdated column names / non-existent scripts.

**Fix — 3 files:**

### A. NEW `<repo>/sql/fsfo_monitor_26ai.sql` (313 lines)

1:1 copy of `fsfo_monitor.sql` with patched section 7:

```sql
-- BEFORE (gv$replay_stat_summary REMOVED in 26ai):
SELECT inst_id, requests_total, requests_replayed, ...
FROM gv$replay_stat_summary;

-- AFTER (aggregate from per-context views):
WITH agg AS (
    SELECT inst_id,
           COUNT(*) AS active_contexts,
           NVL(SUM(sequence_values_captured),0) AS seq_capt,
           NVL(SUM(sequence_values_replayed),0) AS seq_repl,
           NVL(SUM(sysdate_values_captured),0)  AS sd_capt,
           NVL(SUM(sysdate_values_replayed),0)  AS sd_repl,
           ...
    FROM gv$replay_context
    GROUP BY inst_id
)
SELECT ..., CASE
   WHEN seq_capt + sd_capt + sg_capt + lobs_capt = 0 THEN 'IDLE'
   WHEN seq_repl >= seq_capt AND ... THEN 'PASS'
   ELSE 'WARN'
END AS tac_assessment
FROM agg ORDER BY inst_id;
```

Rest of the script (sections 1-6) bit-identical to `fsfo_monitor.sql`. Pattern analogous to `tac_full_readiness_26ai.sql:543-572` from FIX-082.

### B. `<repo>/VMs/scripts/validate_env.sh` v1.2 → v1.3

Added `pick_sql()` helper (copy from `deploy_tac_service.sh` v1.3 section 0):

```bash
pick_sql() {
    local base="$1"
    if [[ -f "$SQL_DIR/${base}_26ai.sql" ]]; then
        echo "$SQL_DIR/${base}_26ai.sql"
    elif [[ -f "$SQL_DIR/${base}.sql" ]]; then
        echo "$SQL_DIR/${base}.sql"
    else
        echo ""
    fi
}
```

Calls in the script:
- Quick: `QUICK_SQL=$(pick_sql validate_environment)` — prefers `_26ai` if ever added
- Full: loop `for BASE in tac_full_readiness fsfo_monitor fsfo_broker_status` — each through `pick_sql`

Filenames in `/tmp/reports/` use `$(basename ${SQL_FILE%.sql})` — output is `tac_full_readiness_26ai_PRIM_<ts>.log` (self-documenting).

### C. `<repo>/VMs/14_test_scenarios.md` — full document refresh

| # | Section | Change |
|---|---|---|
| D1 | Intro | `validate_env.sh v1.1` → `v1.3`, description of `_26ai` auto-pick added |
| D9 | NEW "Pre-flight before scenarios" | 6-point checklist server+client (FIX-080/082/083/085/089), wallet location notice (FIX-072), multiline grep gotcha (FIX-067) |
| D5 | Scenario 1 + 2 + 3 | TestHarness → `/opt/lab/run_testharness.sh` (with 4 `--add-opens` flags, FIX-087) |
| D7 | Scenario 1 + 2 + 4 | sqlplus/dgmgrl everywhere with `ssh oracle@infra01` prefix (wallet only there, FIX-072) |
| D8 | Scenario 2 | Multiline `tr '\n' ' '` flatten for grep through dgmgrl output (FIX-067) |
| - | Scenario 2 | sqlplus heredoc with `EXIT;` (FIX-057), CRS stop as `root@` instead of `sudo` |
| D6 | Scenario 3 | `conn.setAutoCommit(false)` in batch loop (FIX-088 — without it ORA-17273) |
| - | Scenario 3 | Find specific server process foreground `(LOCAL=NO)` instead of `head -3` |
| - | Scenario 4 | Notice about Potential Data Loss Mode (FIX-077 — not a regression in MaxAvail+LagLimit=30) |
| D2 | Scenario 5 | Expected output: `commit_outcome=TRUE` (26ai) instead of `commit_outcome_enabled=YES` (19c) |
| D3 | Scenario 5 | Removed placeholder paths `/path/to/project/...` |
| D4 | Scenario 5 | Rewritten — uses `validate_env.sh` v1.3 instead of direct `sqlplus @fsfo_check_readiness.sql` (and non-existent `bash/validate_all.sh`) |

**Files:**
- NEW `<repo>/sql/fsfo_monitor_26ai.sql` (313 lines, section 7 patched)
- `<repo>/VMs/scripts/validate_env.sh` v1.2 → v1.3 (pick_sql helper, 9 changed lines in body)
- `<repo>/VMs/14_test_scenarios.md` — intro + 5 scenarios + scenario 5 fully rewritten
- `<repo>/VMs/FIXES_LOG.md` — this entry

**Lesson:** **The test document must be audited together with the scripts it calls**. Doc 14 had been referencing tools (`validate_all.sh`, `commit_outcome_enabled`, `/path/to/project/...`) that never existed or were changed during 7 documents (08-13). Without the audit, an operator running the scenarios would encounter 5+ misleading errors (ORA-00942, ORA-17273, "no such file", FAIL on PASS expected output) instead of a clean run. Pattern: **before each direction (next document) cross-check against accumulated findings**, even if the document "looks ready" in repo. Compiling the findings list is the audit; the fix is the second step.

---

## FIX-091 — `validate_env.sh` v1.3 → v1.4 — `SET SQLBLANKLINES ON` + parse_summary() (first run output)

**Problem:** First run of `validate_env.sh` v1.3 on prim01 produced two parallel errors:

```
[oracle@prim01 ~]$ bash /tmp/scripts/validate_env.sh
[13:31:35] [quick] Running validate_environment.sql on PRIM...
SP2-0042: unknown command "UNION ALL" - rest of line ignored.   ← x11
ORA-03048: SQL reserved word ')' is not syntactically valid following '...END FROM dual'

Status   Count % of 12
WARN          1 8.3%
N/A           3 25.0%
PASS          8 66.7%

[13:31:35] [quick] Result: PASS=3, WARN=3, FAIL=1                ← false!
[13:31:35] ERROR: Quick: FAIL found in validate_environment.sql
```

**Diagnosis of the two parallel errors:**

### Error 1 — `SP2-0042 + ORA-03048`

`validate_environment.sql:40-200` has one large `WITH checks AS ( ... ) SELECT ...` with multiple `UNION ALL` separated by blank lines for readability:

```sql
WITH checks AS (
    SELECT 1, 'FSFO', ... FROM dual
    UNION ALL
    SELECT 2, 'FSFO', ... FROM dual

    UNION ALL                            ← blank line before = sqlplus treats as end of statement
    SELECT 3, 'TAC', ... FROM dual
    ...
)
SELECT * FROM checks ORDER BY ...;
```

sqlplus default `SET SQLBLANKLINES OFF` — **a blank line in the middle of a SQL statement terminates it**. So sqlplus treats each fragment before a blank line as a separate command. `UNION ALL` on the first line of the new "statement" → `SP2-0042: unknown command`. After processing all UNION ALLs the parser gets a fragment without a closing `)` → `ORA-03048: SQL reserved word ')' is not syntactically valid`.

### Error 2 — false `FAIL=1` despite PASS=8

v1.3 heuristic:
```bash
PASS_N=$(echo "$QUICK_OUT" | grep -cE '\bPASS\b' || true)
FAIL_N=$(echo "$QUICK_OUT" | grep -cE '\bFAIL\b' || true)
WARN_N=$(echo "$QUICK_OUT" | grep -cE '\bWARN\b' || true)
```

Counts occurrences of words PASS/WARN/FAIL **in the entire output** including the legend:

```
Interpretation:
- PASS  = environment ready for FSFO/TAC deployment
- WARN  = works, but improvement recommended before production
- FAIL  = blocks deployment, must be fixed   ← grep matches 'FAIL' here
- N/A   = not applicable (e.g. TAC checks on DB without services)
```

Each of the 4 words appears +/- 3 times in output (table header, summary, legend) → false `FAIL=1`. Also even though summary shows `WARN 1 8.3%`, grep returns `WARN=3`.

**Fix v1.4:**

### A. `SET SQLBLANKLINES ON` in heredoc

Least invasive: add to heredoc BEFORE `@<sql_file>`. Covers all SQL scripts (validate_environment, tac_full_readiness_26ai, fsfo_monitor_26ai, fsfo_broker_status). Files in `<repo>/sql/` remain untouched.

```bash
QUICK_OUT=$(sqlplus -s "$CONNECT" <<SQLEOF 2>&1
SET SQLBLANKLINES ON
@$QUICK_SQL
EXIT
SQLEOF
)

# Also in --full loop:
sqlplus -s "$CONNECT" <<SQLEOF > "$OUT_FILE" 2>&1
SET SQLBLANKLINES ON
@$SQL_FILE
EXIT
SQLEOF
```

### B. `parse_summary()` helper instead of grep -c

```bash
parse_summary() {
    local out="$1"
    local status="$2"
    # Exact match line "STATUS<spaces>N<spaces>X.X%" in summary table
    echo "$out" | awk -v s="$status" '$1==s && $2 ~ /^[0-9]+$/ { print $2; exit }'
}

PASS_N=$(parse_summary "$QUICK_OUT" PASS)
FAIL_N=$(parse_summary "$QUICK_OUT" FAIL)
WARN_N=$(parse_summary "$QUICK_OUT" WARN)
NA_N=$(parse_summary "$QUICK_OUT"  N/A)
PASS_N="${PASS_N:-0}"; FAIL_N="${FAIL_N:-0}"; ...
```

`awk '$1==s && $2 ~ /^[0-9]+$/'` matches only lines that:
1. Start exactly with the status string (PASS/WARN/FAIL/N/A) as first field
2. Have a number as second field (i.e. summary table, not legend)

### Smoke test on prim01 after SCP v1.4 (expected output):

```
[13:35:22] validate_env.sh v1.4 — mode=quick, target=PRIM, SQL_DIR=/tmp/sql
[13:35:22] [quick] Running validate_environment.sql on PRIM...
================================================================================
   FSFO + TAC Environment Validation (12 checks)
================================================================================
( ... 12 table rows ... )

Status   Count % of 12
PASS          8 66.7%
WARN          1 8.3%
FAIL          0 0.0%
N/A           3 25.0%

[13:35:22] [quick] Result: PASS=8, WARN=1, FAIL=0, N/A=3
[13:35:22] DONE — quick validation OK (8 PASS, 1 WARN, 3 N/A)
```

**Files:** `<repo>/VMs/scripts/validate_env.sh` v1.3 → v1.4 (header + parse_summary helper + SQLBLANKLINES ON in 2 heredocs + parse calls + log msg).

**Lesson:**
1. **`SET SQLBLANKLINES ON` as default for wrappers calling `<repo>/sql/`** — SQL files written "human-friendly" with blank lines for readability are standard practice, but sqlplus default OFF breaks them. The external solution (heredoc setting) is more conservative than editing the SQL file which may be reused in other contexts (e.g. run from SQLcl where SQLBLANKLINES may have a different default).
2. **Exit code heuristic in CI/CD wrapper must exclude legend and descriptions** — use awk with two conditions (`$1==status && $2 ~ /^[0-9]+$/`) instead of `grep -c`. Same recommendation applies to all scripts that parse diagnostic output: `deploy_tac_service.sh`, `setup_observer_infra01.sh`, etc. — TODO in next audit.

---

## FIX-092 — NEW `validate_environment_26ai.sql` (CDB-aware TAC checks)

**Problem:** After FIX-091 v1.4 smoke test showed that TAC checks (#9-12) returned `0 service(s)` even though `MYAPP_TAC` exists and works (doc 13 section 6 smoke test PASS — PRIM1/PRIM2 loop). Reason: `validate_environment.sql` all 4 checks use `dba_services` in CDB$ROOT, while `MYAPP_TAC` is a **PDB-level service** in `APPPDB`.

**In CDB-multitenant `dba_services` sees only CDB-level services** (typically `PRIM.lab.local`, `PRIM_DGMGRL`). Services in PDBs are invisible to `dba_services` from root scope. This is an Oracle multitenant feature, not a 26ai-specific bug — but in 23ai/26ai TAC services are **standardly PDB-level** (design assumption — PDB isolates application workloads), so `dba_services` in CDB$ROOT will always show 0 TAC.

**Fix: NEW `<repo>/sql/validate_environment_26ai.sql`** (original `validate_environment.sql` remains untouched per user request). Follows the `_26ai` variants pattern from FIX-082/090.

### What is changed in the `_26ai` variant

1. **TAC checks (#9, 10, 11, 12)** — replaced `FROM dba_services WHERE failover_type='TRANSACTION'` with `FROM cdb_services WHERE failover_type='TRANSACTION' AND con_id > 1` (PDB-only; con_id=1 is CDB$ROOT, con_id>1 is PDB).

   ```sql
   -- BEFORE (CDB$ROOT-only):
   SELECT COUNT(*) FROM dba_services WHERE failover_type = 'TRANSACTION';

   -- AFTER (PDB-aware):
   SELECT COUNT(*) FROM cdb_services WHERE failover_type = 'TRANSACTION' AND con_id > 1;
   ```

   Check headings also marked `[PDB]` so the operator sees the scope.

2. **NEW "TAC services per PDB" section** — additional diagnostic SELECT after the main 12 checks showing breakdown per container:

   ```sql
   SELECT
       (SELECT name FROM v$containers c WHERE c.con_id = s.con_id) AS pdb_name,
       s.name, s.failover_type, s.commit_outcome,
       s.session_state_consistency, s.aq_ha_notifications
   FROM cdb_services s
   WHERE s.failover_type IS NOT NULL OR s.commit_outcome = 'TRUE'
      OR s.session_state_consistency IS NOT NULL
   ORDER BY s.con_id, s.name;
   ```

   After doc 12 deploy operator sees in output:
   ```
   PDB                  Service          Failover     Commit  SessionSt  FAN
   APPPDB               MYAPP_TAC        TRANSACTION  TRUE    DYNAMIC    TRUE
   ```

3. **Sections 1-8 FSFO** — bit-identical to original (FSFO checks are CDB-level and `v$database`/`v$parameter`/`v$standby_log` return the same value regardless of container scope).

4. **Summary section** — updated accordingly: 4 TAC checks parsed from `cdb_services WHERE con_id > 1` instead of `dba_services`. Notice added: "TAC checks scope: cdb_services WHERE con_id > 1 (PDB-level). CDB$ROOT services (con_id=1) ignored."

5. **Script header** — author 2026-04-27, version 1.0, 2-paragraph description of why `_26ai` (based on 1:1 original, 4 TAC sections patched + PDB breakdown section added).

### Auto-pick by `validate_env.sh` v1.4

No changes to the script — `pick_sql() validate_environment` automatically selects `_26ai` if it exists (per FIX-090 pattern). Output:

```
[HH:MM:SS] [quick] Running validate_environment_26ai.sql on PRIM...
================================================================================
   FSFO + TAC Environment Validation (12 checks) — 26ai CDB-aware variant
   TAC checks (#9-12) scope: cdb_services WHERE con_id > 1 (PDB-level)
================================================================================
( ... 12 table rows — now #9-12 see TAC services from APPPDB ... )

TAC services per PDB / per container (cdb_services WHERE con_id > 1)
  PDB                  Service          Failover     Commit  SessionSt  FAN
  APPPDB               MYAPP_TAC        TRANSACTION  TRUE    DYNAMIC    TRUE
```

**Files:**
- NEW `<repo>/sql/validate_environment_26ai.sql` (~340 lines — copy of original + 4 TAC sections patched + PDB breakdown section + summary patched)
- `<repo>/VMs/scripts/validate_env.sh` — no changes, `pick_sql()` from FIX-090 handles it automatically
- `<repo>/VMs/FIXES_LOG.md` — this entry

**Re-deploy:** SCP `<repo>/sql/validate_environment_26ai.sql` → `oracle@prim01:/tmp/sql/`, re-run `validate_env.sh` (auto-preferred).

**Lesson:**
1. **CDB-multitenant scope in validation queries** — in 23ai/26ai (and earlier in 19c+ multitenant) **no diagnostic tool should use `dba_services` in CDB$ROOT** for TAC/application services. Standard scope is `cdb_services WHERE con_id > 1` (PDB-only) or `cdb_services` (all containers). Same applies to `dba_users`, `dba_tablespaces`, `dba_data_files`, etc. — `cdb_*` views are a superset.

2. **`_26ai` variants are becoming the norm for read-only repo SQL** — FIX-082 (`tac_full_readiness_26ai`, `tac_replay_monitor_26ai`), FIX-090 (`fsfo_monitor_26ai`), FIX-092 (`validate_environment_26ai`). Pattern: original stays, NEW `_26ai` with patch + two-paragraph header "WHY 26ai variant". `validate_env.sh` v1.3+ has `pick_sql()` that auto-prefers. This pattern is now closed for all 4 SQL files used by `validate_env.sh`.

---

## FIX-093 — `commit_outcome`/`aq_ha_notifications` value `YES`/`NO` (not `TRUE`/`FALSE`) + formatting

**Problem:** After FIX-092 the per-PDB section showed `MYAPP_TAC` in `APPPDB` correctly, but check #10 returned **FAIL** even though MYAPP_TAC has `commit_outcome=TRUE` according to srvctl. Additionally:
1. `check_name FORMAT A40` was too narrow for `commit_outcome=YES on TAC service(s) [PDB]` (43 chars) — wrap in output
2. `PROMPT --------------------------------------------------------------------------------` separators after the breakdown section were **glued** to the next `PROMPT TAC services per PDB...` line — output looked like `------- PROMPT TAC services...`

**Diagnosis of FAIL #10:**

In `cdb_services` per-PDB output:
```
PDB         Service     Failover     Commit  SessionSt  FAN
APPPDB      MYAPP_TAC   TRANSACTION  YES     DYNAMIC    YES
```

The `commit_outcome` value is **`YES`**, not `TRUE`. The validation SQL used `commit_outcome='TRUE'` → 0 hits → `FAIL`. Same for `aq_ha_notifications='YES'` (not `'TRUE'`).

**26ai gotcha (and earlier 19c+ multitenant):**
- `srvctl config service -db PRIM -service MYAPP_TAC` shows `Commit Outcome: TRUE` (boolean presentation in the CRS tool)
- `cdb_services.commit_outcome` is VARCHAR2 with values **`YES`/`NO`**

Same for `aq_ha_notifications`: srvctl shows `AQ HA notifications: TRUE`, dictionary view returns `YES`. Only `failover_type` (`TRANSACTION`/`SELECT`/`NONE`) and `session_state_consistency` (`STATIC`/`DYNAMIC`) use explicit string values in both presentations.

This was a pre-existing bug in the original `validate_environment.sql` since FIX-082 (and earlier in v1.0 from 2026-04-23) — a bug **not visible** until the CDB scope was fixed in FIX-092 (with `dba_services` in CDB$ROOT always returning 0 hits → check jumped to N/A not FAIL).

**Fix — 4 changes in `validate_environment_26ai.sql`:**

1. **`commit_outcome='TRUE'` → `commit_outcome='YES'`** (4 occurrences: check #10 twice + summary #10 twice)
2. **`aq_ha_notifications='TRUE'` → `aq_ha_notifications='YES'`** (4 occurrences: check #11 twice + summary #11 twice)
3. **`COLUMN check_name FORMAT A40` → `A50`** — so `commit_outcome=YES on TAC service(s) [PDB]` (43 chars) and other names with `[PDB]` suffix fit without wrapping
4. **`PROMPT ---...---` separators → `===...===`** — `--` at the start of a PROMPT argument with `SET SQLBLANKLINES ON` active (FIX-091) causes sqlplus to treat it as "SQL comment continuation" → the next PROMPT line becomes literal text appended to the separator. `==` has no such interpretation.

**Parallel fix in `tac_full_readiness_26ai.sql`** (also uses these conditions):
- line 228: `commit_outcome = 'TRUE'` → `'YES'`
- line 262: `aq_ha_notifications = 'TRUE'` → `'YES'`

Original `validate_environment.sql` and `tac_full_readiness.sql` **remain untouched** (per user request — only `_26ai` variants are modified). For 19c `'TRUE'` may work (?) or if not, that is a separate task.

**Updated check #10 description in `_26ai` variant:**
```sql
'commit_outcome=TRUE on TAC service(s) [PDB]'
-- →
'commit_outcome=YES on TAC service(s) [PDB]'
-- + SQL comment: "Column `commit_outcome` in cdb_services is VARCHAR2 with
-- values YES/NO. srvctl shows 'Commit Outcome: TRUE' (boolean) but
-- dictionary view returns YES/NO."
```

**Files:**
- `<repo>/sql/validate_environment_26ai.sql` — 4 fixes (TRUE→YES x 8 occurrences + A40→A50 + 2 separators)
- `<repo>/sql/tac_full_readiness_26ai.sql` — 2 fixes (TRUE→YES in TAC service properties section)
- `<repo>/VMs/FIXES_LOG.md` — this entry

**Smoke test after SCP (expected output):**
```
[HH:MM:SS] [quick] Running validate_environment_26ai.sql on PRIM...
================================================================================
   FSFO + TAC Environment Validation (12 checks) — 26ai CDB-aware variant
================================================================================
( ... 12 rows, # 9-12 with [PDB] suffix without wrap ... )

  9 TAC  TAC service (failover_type=TRANSACTION) [PDB]      1 service(s) in PDBs   PASS
 10 TAC  commit_outcome=YES on TAC service(s) [PDB]         1 of 1 TAC services    PASS
 11 TAC  FAN enabled on TAC service(s) [PDB]                1 service(s)           PASS
 12 TAC  session_state_consistency=DYNAMIC [PDB]            1 service(s)           PASS

================================================================================
   TAC services per PDB / per container (cdb_services WHERE con_id > 1)
================================================================================
PDB         Service       Failover     Commit  SessionSt  FAN
APPPDB      MYAPP_TAC     TRANSACTION  YES     DYNAMIC    YES
APPPDB      PRIM_APPPDB   NONE         NO      [null]     NO     ← default service, OK

================================================================================
   Summary
================================================================================
Status   Count % of 12
PASS         12 100.0%

[HH:MM:SS] DONE — quick validation OK (12 PASS, 0 WARN, 0 N/A)
```

**Lesson:**
1. **`srvctl config` ↔ `dba_services`/`cdb_services` have different value formats** for boolean attributes. srvctl uses `TRUE`/`FALSE` (CLI-friendly), dictionary views use `YES`/`NO` (legacy from 9i/10g). Always verify the value format empirically with `SELECT DISTINCT commit_outcome, aq_ha_notifications FROM cdb_services WHERE failover_type='TRANSACTION'` before writing conditions.
2. **`SET SQLBLANKLINES ON` (from FIX-091) requires avoiding `--` at the start of PROMPTs** because sqlplus may try to interpret them as comment continuation. Safe separators: `===`, `:::`, `~~~`. Old `---` separators worked without SQLBLANKLINES (blank-line separators).
3. **Pre-existing bug revealed only after an earlier fix** — `commit_outcome='TRUE'` was in the original `validate_environment.sql` since 2026-04-23 but the problem was invisible because `dba_services` in CDB$ROOT always returned 0 hits (FIX-092 fixed that layer). Pattern: every fix may expose another bug one layer deeper. Don't assume "PASS after fix" = "system correct" — always verify values against reality.

---

## 2026-04-27 (before scenario 1 from doc 14)

## FIX-094 — Open PDB in READ ONLY on STBY (Active Data Guard)

**Problem:** After doc 09 STBY had `database_role=PHYSICAL STANDBY`, `open_mode=MOUNTED` (CDB) and all PDBs in `MOUNTED` (`SHOW PDBS`: `PDB$SEED MOUNTED`, `APPPDB MOUNTED`). Detected during scenario 1 pre-flight (planned switchover):

**Symptoms:**
1. `bash /tmp/scripts/validate_env.sh -t STBY` — ORA-01219 on every query to `cdb_services`:
   ```
   ORA-01219: Database or pluggable database not open. Queries allowed on fixed tables or views only.
   ```
   3 SQL sections (main check 9-12, per-PDB breakdown, summary with #9-12 union all) — all crash. Result `PASS=0, WARN=0, FAIL=0, N/A=0` (noise data).
2. ADG read-only offload does not work — APPPDB cannot be queried read-only from standby.
3. Failover for scenario 2 itself would work (PDB opens RW after promote anyway), but during lab work APPPDB on STBY should be OPEN RO.

**Root cause:** Doc 09 section 8 (line 640) and section 6 post-duplicate sqlplus block (line 495) had `ALTER DATABASE OPEN READ ONLY` (opens CDB) **without** `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` (opens PDB). Script `duplicate_standby.sh` v3.3 section 9 also ends without opening PDB. In 23ai/26ai PDB does not auto-open on CDB OPEN — requires explicit ALTER PLUGGABLE DATABASE.

**Diagnostics (during scenario 1 pre-flight):**
```sql
SQL> SELECT database_role, open_mode FROM v$database;
PHYSICAL STANDBY MOUNTED                ← CDB itself is MOUNTED, not OPEN RO

SQL> SHOW PDBS;
2 PDB$SEED  MOUNTED                     ← PDBs also MOUNTED
3 APPPDB    MOUNTED

SQL> ALTER PLUGGABLE DATABASE APPPDB OPEN READ ONLY;
ORA-01109: database not open            ← because CDB is MOUNTED
```

**Runtime fix (applied during session 2026-04-27 ~15:30):**
```bash
# Step 1 — broker APPLY-OFF (from infra01 wallet location FIX-072)
ssh oracle@infra01
dgmgrl /@PRIM_ADMIN
EDIT DATABASE STBY SET STATE='APPLY-OFF';
EXIT

# Step 2 — open CDB+PDB (on stby01)
ssh oracle@stby01
sqlplus / as sysdba
ALTER DATABASE OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
SHOW PDBS;
-- 2 PDB$SEED  READ ONLY  NO
-- 3 APPPDB    READ ONLY  NO
EXIT

# Step 3 — broker APPLY-ON
ssh oracle@infra01
dgmgrl /@PRIM_ADMIN
EDIT DATABASE STBY SET STATE='APPLY-ON';
EXIT
```

**`SAVE STATE` does not work on STBY:**
```sql
SQL> ALTER PLUGGABLE DATABASE ALL SAVE STATE;
ORA-16000: Attempting to modify database or pluggable database that is open for read-only access.
```
Standby has read-only dictionary — PDB state cannot be saved. Persistence after reboot requires a separate mechanism (see FIX-095 TODO).

**After fix:**
```bash
ssh oracle@prim01 "bash /tmp/scripts/validate_env.sh -t STBY"
# [quick] Result: PASS=12, WARN=0, FAIL=0, N/A=0
# Plus breakdown: APPPDB / MYAPP_TAC / TRANSACTION / YES / DYNAMIC / YES
```

**Permanent fix:**
1. **`VMs/09_standby_duplicate.md`:**
   - Section 6 post-duplicate sqlplus (line ~495): after `ALTER DATABASE OPEN READ ONLY` added `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY`.
   - Section 8 standby OPEN + start MRP (line ~640): identical addition + `SHOW PDBS` verification + comment about SAVE STATE limitation.
2. **`VMs/scripts/duplicate_standby.sh` v3.3 → v3.4:**
   - Section 9 sqlplus block: after `ALTER DATABASE OPEN READ ONLY` added `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` with FIX-094 comment.
   - Header bump v3.4 + change description.
3. **TODO (FIX-095):** persistence of PDB state after stby01 reboot — candidates:
   - **A)** `AFTER STARTUP ON DATABASE` trigger in CDB$ROOT (executes `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` on every standby open, replicates via DG, also works on primary as RW open).
   - **B)** Modify systemd unit `oracle-database-stby.service` (FIX-085 v1.3) — add ExecStartPost that runs sqlplus with `STARTUP` (full open instead of `STARTUP MOUNT`) + `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY`.
   - **C)** Broker property `StandbyPDBState` (if available in 26ai broker — check).
   - Recommendation: A) least invasive, single source of truth for both sites.

**Lesson:**
1. **CDB OPEN ≠ PDB OPEN in 23ai/26ai.** `ALTER DATABASE OPEN READ ONLY` opens only CDB$ROOT — PDBs remain in MOUNTED until `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` or `SAVE STATE` (on primary). Doc 09 missed this — easy to overlook because on primary `STARTUP` in DBCA scripts auto-opens PDBs, but on standby it does NOT.
2. **`SAVE STATE` is illegal on standby** — read-only dictionary blocks all state modifications. Persistence requires a separate mechanism (trigger, systemd, broker).
3. **`validate_environment_26ai.sql` should be resilient to MOUNTED PDB** — graceful N/A with message "PDB not open, skipped TAC checks" instead of crash. Candidate for FIX-095/096 (but does not block FIX-094).
4. **Pre-flight before test scenarios caught this bug** — without STBY validation (FIX-090..093) this problem would have gone unnoticed until failover scenario 4 (apply lag exceeded — requires queries to APPPDB in installed-but-not-running state). Conclusion: full pre-flight (both PRIM and STBY) is a must-have, even if doc 09 "looked fine" because MRP applies.

---

## FIX-095 — Service `MYAPP_TAC` does not auto-start on non-Grid standby after promote (scenario 1 forward)

**Problem:** After SWITCHOVER TO STBY the broker completed successfully (`Switchover succeeded, new primary is "stby"`), but TestHarness on client01 received `UCP-29: Failed to get a connection` for ~60s and did not reconnect on its own. Diagnosis showed that service `MYAPP_TAC` **was not started** on the new primary (stby01):

```sql
SQL> ALTER SESSION SET CONTAINER=APPPDB;
SQL> SELECT con_id, name FROM gv$active_services WHERE name LIKE '%myapp%';
no rows selected   ← service not running
```

**Root cause:** Service `MYAPP_TAC` created by `srvctl add service ... -role PRIMARY` in doc 12 is **CRS-managed on PRIM**. Grid Infrastructure Auto-Start mechanism reacts to role change and starts the `-role PRIMARY` service on the new primary side. **But stby01 is SI without Grid Infrastructure** — no CRS, no `srvctl`, no auto-start mechanism. After promote to PRIMARY the service exists in `cdb_services` (replicated via DG) but nobody starts it.

**Client symptoms:**
- TestHarness loop [37..97] = `ERROR: UCP-29: Failed to get a connection` (~60s)
- Reason: TNS fallback `prim-scan → stby01:1521` finds listener, but listener does not know `myapp_tac.lab.local` (service not started) → ORA-12514 → UCP retry → exhaustion → UCP-29.

**Runtime fix (applied during session 16:11):**
```sql
-- On stby01 after SWITCHOVER, as sysdba in CDB$ROOT:
ALTER SESSION SET CONTAINER=APPPDB;     -- ⚠️ MUST be in PDB context (DBMS_SERVICE is container-scoped)
EXEC DBMS_SERVICE.START_SERVICE('myapp_tac');   -- ⚠️ LOWERCASE, NO db_domain (.lab.local)
-- PL/SQL procedure successfully completed.
```

**Name pitfalls:**
- `'MYAPP_TAC'` (uppercase, as in `cdb_services.network_name`) → ORA-44773 "Cannot perform requested service operation" (misleading message — NOT about a CRS-managed lock, but about case mismatch)
- `'myapp_tac.lab.local'` (with domain) → ORA-44304 "service does not exist"
- `'myapp_tac'` (lowercase, internal name) → SUCCESS

26ai/23ai gotcha: `cdb_services.network_name` stores uppercase, but `DBMS_SERVICE.START_SERVICE` uses the internal lowercase name (as registered in listener with db_domain auto-suffix).

**After fix:** TestHarness client started receiving `[98] OK: STBY SID=397 ...` — connection reuse and replay.

**Client drain:** ~60s (lines [37]→[97] in log). With proper service auto-start the drain would be ~5-15s (UCP receives FAN UP event via ONS immediately after service start).

**Permanent fix (candidate — long-term, FIX-097/098):**
1. **`AFTER STARTUP ON DATABASE` trigger in CDB$ROOT** (replicates via DG to stby01):
   ```sql
   CREATE OR REPLACE TRIGGER sys.start_role_services
   AFTER STARTUP ON DATABASE
   DECLARE
     v_role VARCHAR2(30);
     v_pdb  VARCHAR2(128);
   BEGIN
     SELECT database_role INTO v_role FROM v$database;
     IF v_role = 'PRIMARY' THEN
       FOR rec IN (SELECT pdb, name FROM cdb_services
                   WHERE network_name LIKE 'MYAPP%' AND con_id > 1)
       LOOP
         BEGIN
           EXECUTE IMMEDIATE
             'ALTER SESSION SET CONTAINER=' || rec.pdb;
           DBMS_SERVICE.START_SERVICE(LOWER(rec.name));
         EXCEPTION
           WHEN OTHERS THEN NULL;  -- ignore "already running"
         END;
       END LOOP;
     END IF;
   END;
   /
   ```
   ⚠️ Trigger reacts to STARTUP (cold restart), **NOT to role change**. For switchover/failover an explicit step is also needed.

2. **Doc 14 scenario 1+2 — post-switchover/failover housekeeping:**
   ```bash
   # Conditional — only if new primary == stby01 (SI without Grid)
   NEW_PRIMARY=$(ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION'" | tr '\n' ' ' | grep -oP '\w+(?= - Primary database)')
   if [[ "$NEW_PRIMARY" == "stby" ]]; then
       ssh oracle@stby01 "sqlplus -s / as sysdba <<EOF
       ALTER SESSION SET CONTAINER=APPPDB;
       EXEC DBMS_SERVICE.START_SERVICE('myapp_tac');
       EXIT
   EOF"
   fi
   ```

3. **Long-term better fix:** doc 12 should create the service via `DBMS_SERVICE.CREATE_SERVICE` (PDB-level) instead of `srvctl add service` (CRS-managed) — works on both database types (RAC + Grid and SI without Grid). Also requires manual setup of `dba_pdbs.failover_role` instead of the srvctl `-role PRIMARY` flag. This is a larger change — candidate for a separate task after doc 14.

**Lesson:**
1. **Mixed RAC+SI MAA requires attention: CRS-managed services on primary do not auto-transfer to non-Grid standby.** Standard MAA guide assumes both sides have Grid (Symmetric MAA). Asymmetric setup (RAC primary, SI standby) requires additional mechanisms for service availability.
2. **`DBMS_SERVICE.START_SERVICE` requires PDB context and lowercase name.** Error messages are misleading: ORA-44773 suggests "use SRVCTL" (confuses with CRS-managed), but the real reason is a case or container mismatch.
3. **Pre-flight FIX-090..094 did not detect this.** Validation checked that the service is configured in `cdb_services` with correct attributes — but did NOT test whether it can start on the second site. Candidate for pre-flight enhancement: post-switchover sanity-check `gv$active_services` on new primary.

---

## FIX-096 — `StaticConnectIdentifier` explicit per-instance after ENABLE CONFIGURATION (broker auto-derive takes PORT=1521)

**Problem:** During SWITCHOVER TO PRIM (rollback) the broker tried to restart STBY instance as the new standby, but received:
```
Unable to connect to database using (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))
ORA-12514: Cannot connect to database. Service STBY_DGMGRL.lab.local is not registered with the listener at host 192.168.56.13 port 1521.
```

The connection string has **PORT=1521**, but `STBY_DGMGRL.lab.local` is a static SID_DESC in `LISTENER_DGMGRL` on **PORT=1522** (FIX-050).

**Root cause:** For each instance the broker auto-derives `StaticConnectIdentifier` from the `local_listener` SPFILE parameter. On stby01:
- `local_listener` = `(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))` (default LISTENER)
- `LISTENER_DGMGRL` on 1522 is a separate entry in `listener.ora`, not registered in `local_listener`
- Broker derive takes PORT=1521 → wrong

**Diagnosis:**
```
DGMGRL> SHOW DATABASE 'stby' StaticConnectIdentifier;
StaticConnectIdentifier = '(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521)) ...'
                                                                              ^^^^^^^^^ WRONG

DGMGRL> SHOW DATABASE 'PRIM' StaticConnectIdentifier;
ORA-16606: unable to find property "staticconnectidentifier"
```

PRIM has no explicit one; broker uses default (works accidentally because Grid CRS registers `PRIM_DGMGRL` in SCAN+local).

**Runtime fix (applied ~16:25):**
```
DGMGRL> EDIT DATABASE 'stby' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))';
Property "StaticConnectIdentifier" updated for member "stby".

DGMGRL> EDIT DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='...';
ORA-16582: Cannot change an instance-specific property.   ← RAC: per-instance!

DGMGRL> EDIT INSTANCE 'PRIM1' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM1)(SERVER=DEDICATED)))';
Property "StaticConnectIdentifier" updated for member "PRIM".

DGMGRL> EDIT INSTANCE 'PRIM2' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim02.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM2)(SERVER=DEDICATED)))';
Property "StaticConnectIdentifier" updated for member "PRIM".
```

**Syntax:**
- **SI standby:** `EDIT DATABASE '<dbname>' SET PROPERTY 'StaticConnectIdentifier'='...'`
- **RAC (per-instance):** `EDIT INSTANCE '<inst>' ON DATABASE '<dbname>' SET PROPERTY 'StaticConnectIdentifier'='...'`
- **Property name** must be in quotes (`'StaticConnectIdentifier'`); without quotes ORA-16606.

**Impact on doc 10 / configure_broker.sh v3.0 (candidate FIX-097):**

`configure_broker.sh` v2.x ends with `ENABLE CONFIGURATION` + verify `Configuration Status: SUCCESS`. **No step to set explicit `StaticConnectIdentifier`.** Effect: config appears to work (`SHOW CONFIGURATION = SUCCESS`), first switchover also succeeds (broker uses other connection paths for initial role change), but **second switchover** fails when restarting instance. SWITCHOVER test must pass in both directions (forward+rollback) as a sanity check before go-live.

**FIX-097 plan (configure_broker.sh v3.0):**

Add section 2b "Set StaticConnectIdentifier per-instance" after section 2 (ENABLE CONFIGURATION):
```bash
dgmgrl /@PRIM_ADMIN <<DGEOF
EDIT DATABASE 'stby' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM1' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM1)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM2' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim02.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM2)(SERVER=DEDICATED)))';
EXIT
DGEOF
```

**Lesson:**
1. **Broker auto-derive does not know about LISTENER_DGMGRL on 1522** — always takes port from `local_listener` (i.e. LISTENER:1521). If the setup has a separate static listener on a non-default port, **explicit `StaticConnectIdentifier` is mandatory**.
2. **First switchover success ≠ broker config healthy.** Both directions must be tested (forward+rollback) before declaring go-live. The first switchover may use incremental connection paths (DGConnectIdentifier vs StaticConnectIdentifier), the second already requires full static.
3. **`StaticConnectIdentifier` on RAC is per-instance** — `EDIT DATABASE` throws ORA-16582. Must use `EDIT INSTANCE 'PRIMx' ON DATABASE 'PRIM'`.

---

## Open / for verification

| # | What to check | When |
|---|-------------|-------|
| 1 | Whether `oracle-database-preinstall-23ai` installs correctly in `%post` (requires NAT + repo ol8_appstream) | After first VM restart |
| 2 | Whether interface names (`enp0s3`, `enp0s8`, `enp0s9`, `enp0s10`) are correct with virtio cards in VirtualBox | After login: `ip -br link show` |
| 3 | Whether `compat-openssl11` is installed as a preinstall RPM dependency | `rpm -q compat-openssl11` after installation |
| 4 | Whether `setup_observer_infra01.sh` v1.2 with FIX-067/068/069 + #4-7 passes end-to-end on a running broker (post doc 10) | After SCP v1.2 → infra01 |
| 5 | Whether there are other legacy 19c keys in `client.rsp` (PROXY_*, ORACLE_HOSTNAME) that 23.0.0 also does not accept | Check when INS-10105 appears on new installs |
