# 🖥️ 03 — VM Preparation (Sprint 1, step 1)

[![Sprint](https://img.shields.io/badge/Sprint-1-blue)]()
[![Step](https://img.shields.io/badge/Step-1_of_4-orange)]()
[![Tool](https://img.shields.io/badge/Tool-VirtualBox_7.x-darkgreen)]()
[![OS](https://img.shields.io/badge/OS-OL_8.10-orange)]()
[![Auto](https://img.shields.io/badge/Boot-Automated_via_Sprint_0-success)]()

> 🎯 Creates the rcat01 VM (4 GB RAM, 60+200 GB) and boots from the OL 8.10 ISO + kickstart (zero clicks thanks to Sprint 0).

## 📋 Prerequisites

| Requirement | Check |
|---|---|
| VirtualBox 7.x installed | `VBoxManage --version` |
| Host RAM ≥ 64 GB | `Get-ComputerInfo CsTotalPhysicalMemory` |
| Disk free ≥ 300 GB on D:\ | `Get-PSDrive D` |
| ISO OL 8.10 present | `D:\ISOs\OracleLinux-R8-U10-x86_64-dvd.iso` |
| Host-only IF #2 configured | `Get-NetIPAddress -InterfaceAlias "*Host-Only*#2*"` has 192.168.56.1 |
| Python 3.x in PATH | `python --version` (for http.server) |
| Backup destination folder | `D:\_RMAN_BCK_from_Linux_` (create if missing) |

## 🚀 Method A — Automated (Sprint 0 + Sprint 1)

```powershell
cd ZDLRA_like

# 1) Create the backup directory (one-off)
New-Item -Path D:\_RMAN_BCK_from_Linux_ -ItemType Directory -Force

# 2) Create the rcat01 VM (idempotent)
.\scripts\vbox_create_rcat.ps1

# 3) Pre-flight test (optional)
.\scripts\boot\boot_rcat_via_scancode.ps1 -DryRun

# 4) Full kickstart boot (~15-25 min, zero clicks)
.\scripts\boot\boot_rcat_via_scancode.ps1
```

After success:
- ✅ VM rcat01 installed with OL 8.10
- ✅ SSH available: `ssh kris@192.168.56.16` (password from `/root/.lab_secrets` → `$LAB_PASS`, created by kickstart `%post`)
- ✅ User `oracle` exists, mounts `/mnt/rman_bck`, `/mnt/oracle_binaries` configured
- ✅ HugePages 1024 (2 GB), THP disabled

## 🛠️ Method B — Manual (without Sprint 0)

If for some reason Sprint 0 does not work or you want to do it manually:

```powershell
# 1) VM creation (same as Method A)
.\scripts\vbox_create_rcat.ps1

# 2) Start the kickstart server (separate window)
.\scripts\boot\start_kickstart_http.ps1

# 3) Start the VM in GUI mode
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' startvm rcat01 --type gui
```

On the GRUB screen:
1. Press **TAB** or **e**
2. Append to the `linuxefi` line:
   ```
    inst.ks=http://192.168.56.1:8000/ks-rcat01.cfg inst.ip=192.168.56.16::192.168.56.1:255.255.255.0::enp0s3:none inst.text
   ```
3. **Enter** (TAB) or **Ctrl-X** (e) — boot

## ✅ Post-install validation

```bash
# From the host
ssh kris@192.168.56.16
# After logging in to rcat01:

# Network
ip addr show enp0s3 | grep '192.168.56.16'
ping -c 2 infra01.lab.local

# Hostname & DNS
hostname -f                    # rcat01.lab.local
cat /etc/resolv.conf | grep nameserver  # 192.168.56.10

# Mounts
df -hT | grep -E '/u0|/mnt'    # /u01..u04 + /mnt/rman_bck + /mnt/oracle_binaries

# HugePages & THP
grep -E 'HugePages_Total|HugePages_Free' /proc/meminfo
cat /sys/kernel/mm/transparent_hugepage/enabled  # [never]

# User oracle
id oracle
sudo grep oracle /etc/security/limits.d/*.conf | grep memlock  # unlimited

# NTP
chronyc sources | grep '^\^'

# Storage layout (LVM on sdb)
lsblk
sudo vgs
sudo lvs
```

Expected results:
- ✅ enp0s3 has 192.168.56.16
- ✅ /u01 (40 GB), /u02 (100 GB), /u03 (50 GB), /u04 (50 GB) all xfs
- ✅ HugePages_Total >= 1024
- ✅ THP `[never]`
- ✅ chrony sync with 192.168.56.10

## 🌐 Sprint 1 step 1.5 — DNS on infra01

After rcat01 starts, we need to add a DNS entry on infra01:

```bash
# From rcat01 (or the host)
scp scripts/setup_dns_rcat_on_infra01.sh root@infra01.lab.local:/tmp/
ssh root@infra01.lab.local 'bash /tmp/setup_dns_rcat_on_infra01.sh'

# Validation from any LAB host:
nslookup rcat01.lab.local
nslookup 192.168.56.16
```

## 🚧 Troubleshooting

### Sprint 0 boot did not download the kickstart (Anaconda starts TUI)

- Check the log: `_RecoveryAppliance_/kickstart/.http_server.log`
- In GUI mode: Ctrl-Alt-F2 in the VM, `curl http://192.168.56.1:8000/ks-rcat01.cfg`
- Increase `-InitialDelaySec 15` or `-DownArrowsCount 3` in `boot_rcat_via_scancode.ps1`

### VM does not start (boot loop)

- Check ISO attach: `VBoxManage showvminfo rcat01 | grep ISO`
- Check boot order: `--boot1 disk --boot2 dvd` (in `vbox_create_rcat.ps1`)

### Kickstart fails in `%post` (Anaconda log)

- In GUI: Ctrl-Alt-F2 -> `cat /tmp/anaconda.log` or `/root/ks-post.log` (after reboot)

## ⏭️ Next step

[04_DB_Install_and_Auto_Start.md](04_DB_Install_and_Auto_Start.md) — Oracle DB installation + systemd auto-start.
