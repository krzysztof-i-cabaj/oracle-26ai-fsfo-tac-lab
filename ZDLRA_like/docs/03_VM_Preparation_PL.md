# 🖥️ 03 — VM Preparation (Sprint 1, krok 1)

[![Sprint](https://img.shields.io/badge/Sprint-1-blue)]()
[![Step](https://img.shields.io/badge/Step-1_of_4-orange)]()
[![Tool](https://img.shields.io/badge/Tool-VirtualBox_7.x-darkgreen)]()
[![OS](https://img.shields.io/badge/OS-OL_8.10-orange)]()
[![Auto](https://img.shields.io/badge/Boot-Automated_via_Sprint_0-success)]()

> 🎯 Tworzy VM rcat01 (4 GB RAM, 60+200 GB) i bootuje z ISO OL 8.10 + kickstart (zero kliknieć dzięki Sprint 0).

## 📋 Wymagania / Prerequisites

| Wymaganie [PL] | Sprawdzenie | Requirement [EN] |
|---|---|---|
| VirtualBox 7.x | `VBoxManage --version` | VirtualBox 7.x installed |
| Host RAM ≥ 64 GB | `Get-ComputerInfo CsTotalPhysicalMemory` | Host RAM |
| Disk free ≥ 300 GB | `Get-PSDrive D` | Disk free on D:\ |
| ISO OL 8.10 | `D:\ISOs\OracleLinux-R8-U10-x86_64-dvd.iso` | ISO present |
| Hostonly IF #2 | `Get-NetIPAddress -InterfaceAlias "*Host-Only*#2*"` ma 192.168.56.1 | Host-only IF configured |
| Python 3.x | `python --version` (dla http.server) | Python in PATH |
| Shared folder dla backupow | `D:\_RMAN_BCK_from_Linux_` (utworz jesli brak) | Backup destination |

## 🚀 Metoda A — Automatyczna (Sprint 0 + Sprint 1)

```powershell
cd ZDLRA_like

# 1) Utworz katalog na backupy (jednorazowo)
New-Item -Path D:\_RMAN_BCK_from_Linux_ -ItemType Directory -Force

# 2) Stworz VM rcat01 (idempotentnie)
.\scripts\vbox_create_rcat.ps1

# 3) Pre-flight test (opcjonalnie)
.\scripts\boot\boot_rcat_via_scancode.ps1 -DryRun

# 4) Pelny boot z kickstart (~15-25 min, zero kliknieć)
.\scripts\boot\boot_rcat_via_scancode.ps1
```

Po sukcesie:
- ✅ VM rcat01 zainstalowany OL 8.10
- ✅ SSH dostepny: `ssh kris@192.168.56.16` (haslo z `/root/.lab_secrets` → `$LAB_PASS`, utworzony przez kickstart `%post`)
- ✅ User `oracle` istnieje, mounty `/mnt/rman_bck`, `/mnt/oracle_binaries` skonfigurowane
- ✅ HugePages 1024 (2 GB), THP disabled

## 🛠️ Metoda B — Manualna (bez Sprint 0)

Jesli z jakiegos powodu Sprint 0 nie dziala lub chcesz recznie:

```powershell
# 1) VM creation (jak Metoda A)
.\scripts\vbox_create_rcat.ps1

# 2) Start serwera kickstart (osobne okno)
.\scripts\boot\start_kickstart_http.ps1

# 3) Start VM w GUI mode
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' startvm rcat01 --type gui
```

Na ekranie GRUB:
1. Nacisnij **TAB** lub **e**
2. Dopisz na koncu linii `linuxefi`:
   ```
    inst.ks=http://192.168.56.1:8000/ks-rcat01.cfg inst.ip=192.168.56.16::192.168.56.1:255.255.255.0::enp0s3:none inst.text
   ```
3. **Enter** (TAB) lub **Ctrl-X** (e) - boot

## ✅ Walidacja po instalacji / Post-install validation

```bash
# Z hosta
ssh kris@192.168.56.16
# Po zalogowaniu na rcat01:

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

# Storage layout (LVM na sdb)
lsblk
sudo vgs
sudo lvs
```

Oczekiwane wyniki:
- ✅ enp0s3 ma 192.168.56.16
- ✅ /u01 (40 GB), /u02 (100 GB), /u03 (50 GB), /u04 (50 GB) wszystkie xfs
- ✅ HugePages_Total >= 1024
- ✅ THP `[never]`
- ✅ chrony sync z 192.168.56.10

## 🌐 Sprint 1 step 1.5 — DNS na infra01

Po starcie rcat01 musimy dopisac wpis DNS na infra01:

```bash
# Z rcat01 (lub hosta)
scp scripts/setup_dns_rcat_on_infra01.sh root@infra01.lab.local:/tmp/
ssh root@infra01.lab.local 'bash /tmp/setup_dns_rcat_on_infra01.sh'

# Walidacja z dowolnego hosta LAB:
nslookup rcat01.lab.local
nslookup 192.168.56.16
```

## 🚧 Troubleshooting

### Sprint 0 boot nie pobral kickstart (Anaconda startuje TUI)

- Sprawdz log: `_RecoveryAppliance_/kickstart/.http_server.log`
- W GUI mode: Ctrl-Alt-F2 w VM, `curl http://192.168.56.1:8000/ks-rcat01.cfg`
- Zwieksz `-InitialDelaySec 15` lub `-DownArrowsCount 3` w `boot_rcat_via_scancode.ps1`

### VM nie startuje (boot loop)

- Sprawdz attach ISO: `VBoxManage showvminfo rcat01 | grep ISO`
- Sprawdz boot order: `--boot1 disk --boot2 dvd` (w `vbox_create_rcat.ps1`)

### Kickstart fail w `%post` (Anaconda log)

- W GUI: Ctrl-Alt-F2 -> `cat /tmp/anaconda.log` lub `/root/ks-post.log` (po reboocie)

## ⏭️ Nastepny krok / Next step

[04_DB_Install_and_Auto_Start.md](04_DB_Install_and_Auto_Start_PL.md) — instalacja Oracle DB + systemd auto-start.
