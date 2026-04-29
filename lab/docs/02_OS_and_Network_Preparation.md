> 🇬🇧 English | [🇵🇱 Polski](./02_OS_and_Network_Preparation_PL.md)

# 02 — OS, Network and Kickstart Preparation (VMs2-install)

> **Goal:** Fast, repeatable installation of Oracle Linux 8.10 on 5 virtual machines using Kickstart (`.cfg`) files plus SSH key configuration.
> **Note about IP addressing:** NAT addressing (`10.x.x.x`) can be problematic during Kickstart-based installation (running an HTTP server on the Windows host). This document explains how to work around this issue.

---

## 1. Creating virtual machines in VirtualBox

Before starting the OS installation, you must define the VM structure in VirtualBox. This is done by the `scripts/vbox_create_vms.ps1` script, run **once on the Windows host**.

### Prerequisites

| Requirement | Detail |
|-----------|----------|
| VirtualBox 7.x | Installed on the Windows host |
| Host-Only Ethernet Adapter #2 | Configured in VirtualBox Manager: `192.168.56.1/24`, DHCP disabled |
| Oracle Linux 8.10 ISO | `D:\ISOs\OracleLinux-R8-U10-x86_64-dvd.iso` |
| Oracle binaries (optional) | `D:\OracleBinaries\` — GI/DB/Client 23.26 ZIPs (see section 5) |

### Running the script

Open PowerShell **as Administrator** and execute:

```powershell
cd <repo>
.\scripts\vbox_create_vms.ps1
```

### What the script creates

For each of the 5 VMs, the script performs:
- `VBoxManage createvm` — registers the VM in VirtualBox (directory: `D:\VM\<name>\`)
- `VBoxManage modifyvm` — sets CPU, RAM, paravirt KVM, virtio-net, RTC UTC
- `VBoxManage storagectl` — creates a SATA controller (hostiocache on only for infra01)
- `VBoxManage createmedium` + `storageattach` — creates and attaches VDI disks
- `VBoxManage storageattach` — mounts the OL 8.10 ISO as DVD
- `VBoxManage modifyvm --nic*` — configures network adapters per VM role
- `VBoxManage sharedfolder add` — registers the `D:\OracleBinaries` shared folder (see section 5)

### VM parameters after running the script

| VM | CPU | RAM | OS Disk | Disk 2 | Role |
|----|-----|-----|---------|--------|------|
| `infra01` | 2 | 8 GB | 40 GB | 100 GB (LVM/iSCSI backstore) | DNS + NTP + iSCSI target + Observer |
| `prim01` | 4 | 9 GB | 60 GB | — | RAC node 1 |
| `prim02` | 4 | 9 GB | 60 GB | — | RAC node 2 |
| `stby01` | 4 | 6 GB | 100 GB | — | Standby + Oracle Restart |
| `client01` | 2 | 3 GB | 30 GB | — | Java UCP/TAC TestHarness |

> **Note:** The script is idempotent — if a VM already exists, it skips `createvm` and continues. Safe to re-run.

---

## 2. Serving Kickstart files (HTTP Server)

Instead of clicking through the Anaconda installer, we use Kickstart files. The simplest way to deliver them to virtual machines is to run a simple HTTP server in the directory containing the `.cfg` files on the host computer (Windows).

1.  Open PowerShell on the host (Windows).
2.  Change into the `kickstart/` directory (in `VMs2-install`):
    ```powershell
    cd <repo>\kickstart
    ```
3.  Start the HTTP server (port 8000):
    ```powershell
    python -m http.server 8000
    ```

---

## 3. Booting virtual machines (IP issue workaround)

### Problem with NAT (10.0.x.x) vs. Host-Only (192.168.56.1)
By default, VirtualBox assigns the `10.0.2.0/24` subnet for the NAT interface, or e.g. `10.0.5.0/24` for a NAT Network. The issue is that the Python server running on the host (Windows) may be unreachable from inside the installer's NAT environment before the network is fully configured.
That is why the **reliable solution** is to use the Host-Only interface (which has a fixed IP on the host, typically `192.168.56.1`).

### How to start the installation?
Boot the VM from the ISO (Oracle Linux 8.10), press the `TAB` key on the boot menu (boot line edit) and append the appropriate parameters **at the very end**.

> **Option A (Recommended, reliable — via Host-Only):**
> We fetch kickstart through the first network adapter (enp0s3), which is attached to `vboxnet0` (Host-Only).
> ```text
> inst.ip=192.168.56.10::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-infra01.cfg
> ```

### GRUB parameters per VM (Option A — Host-Only)

| VM | GRUB parameters (append after `quiet`) |
|----|-------------------------------------|
| `infra01` | `inst.ip=192.168.56.10::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-infra01.cfg` |
| `prim01` | `inst.ip=192.168.56.11::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-prim01.cfg` |
| `prim02` | `inst.ip=192.168.56.12::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-prim02.cfg` |
| `stby01` | `inst.ip=192.168.56.13::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-stby01.cfg` |
| `client01`| `inst.ip=192.168.56.15::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-client01.cfg` |

*(After pressing Enter, Anaconda will handle the installation, create the directory structure, disable THP and update the system — about 10 minutes per machine).*

---

## 4. DNS, NTP and memlock — verification after kickstart

> **Kickstart does this automatically.** The infra01 kickstart configures `bind9` (zone lab.local) and `chrony` (NTP server). The prim01/prim02/stby01/client01 kickstarts configure chrony as a client (IP `192.168.56.10`) and force the DNS resolver onto `enp0s3`. Sections 4a–4c are the **fallback/recovery** path — run them only if kickstart didn't work or if you reinstall a selected VM without a full kickstart.

### 4a. DNS (bind9) on infra01 — fallback

If after rebooting infra01 `dig prim01.lab.local +short` does not return `192.168.56.11`:

```bash
# infra01 (root) — configures named.conf + zone files + starts named:
sudo bash /tmp/scripts/setup_dns_infra01.sh
```

**Verification:**
```bash
dig @192.168.56.10 scan-prim.lab.local +short  # → 192.168.56.31, .32, .33
systemctl is-active named                       # → active
```

### 4b. Chrony / DNS resolver — fallback

If after rebooting any VM `cat /etc/resolv.conf` does not show `nameserver 192.168.56.10`:

```bash
# infra01 (root) — reconfigures chrony as the NTP server for lab.local:
sudo bash /tmp/scripts/setup_chrony.sh --role=server

# prim01 / prim02 / stby01 / client01 (root on each) — forces DNS resolver + chrony client:
sudo bash /tmp/scripts/setup_chrony.sh --role=client
```

**Verification:**
```bash
dig prim02.lab.local +short     # → 192.168.56.12
dig scan-prim.lab.local +short  # → 192.168.56.31, .32, .33
cat /etc/resolv.conf            # → nameserver 192.168.56.10
chronyc sources                 # → infra01 as the source (or IP 192.168.56.10)
```

### 4c. memlock — verification

The kickstarts create `zz-oracle-memlock.conf` (the `zz-` prefix > `oracle-database-preinstall-23ai.conf` — always wins). Check after the first login:

```bash
su - oracle -c 'ulimit -l'   # → unlimited
su - grid   -c 'ulimit -l'   # → unlimited

# If NOT (old kickstart with 99-oracle-memlock.conf) — one-time fix:
cat > /etc/security/limits.d/zz-oracle-memlock.conf <<'EOF'
oracle  soft  memlock  unlimited
oracle  hard  memlock  unlimited
grid    soft  memlock  unlimited
grid    hard  memlock  unlimited
EOF
```

### 4d. Firewall — configuration before GI installation (required)

> **The new VM kickstart does this automatically** (`firewall --disabled`). This section applies to existing VMs or reinstalls without a full kickstart.

**Why this is critical:** Oracle Grid Infrastructure runs `cluvfy` (CVU) before installation and tests **full TCP connectivity** between nodes — not only port 22. CRS uses dynamic ports (CSS, OHASd, agents) in the ranges 27015–27025, 42424 and ephemeral. Firewalld in the `public` zone blocks them all → `FATAL PRVG-11067 No route to host` and the installation aborts.

---

#### Option A — Disable firewalld (recommended for LAB)

The fastest and safe option in an isolated VirtualBox environment. Run on **all five VMs** as root:

```bash
systemctl stop firewalld
systemctl disable firewalld
```

Verification:
```bash
systemctl is-active firewalld    # → inactive
systemctl is-enabled firewalld   # → disabled
```

---

#### Option B — Configure firewalld per-VM

For those who want to keep firewalld. Private interfaces (interconnect, storage) go to the `trusted` zone (no filtering). On the public interface of RAC nodes we accept all traffic from the LAB subnet (`192.168.56.0/24`) — cluvfy tests dynamic ports, an explicit list of which would be too long.

**prim01 and prim02:**
```bash
# Private — no filtering:
firewall-cmd --zone=trusted --add-interface=enp0s8 --permanent  # interconnect 192.168.100.x
firewall-cmd --zone=trusted --add-interface=enp0s9 --permanent  # storage 192.168.200.x

# Public (host-only 192.168.56.x) — accept all traffic from the LAB subnet
# (equivalent to disabling for cluvfy, while still filtering external traffic via NAT):
firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="192.168.56.0/24" accept' --permanent
firewall-cmd --zone=public --add-service=ssh --permanent

firewall-cmd --reload
firewall-cmd --list-all  # verification
```

**stby01:**
```bash
firewall-cmd --zone=public --add-service=ssh --permanent
firewall-cmd --zone=public --add-port=1521/tcp --permanent   # listener
firewall-cmd --zone=public --add-port=1522/tcp --permanent   # DGMGRL
firewall-cmd --zone=public --add-port=6200/tcp --permanent   # ONS remote
firewall-cmd --zone=public --add-port=6101/tcp --permanent   # ONS local

firewall-cmd --reload
```

**infra01:**
```bash
firewall-cmd --zone=public --add-service=ssh --permanent
firewall-cmd --zone=public --add-service=dns --permanent     # 53/tcp + 53/udp (bind9)
firewall-cmd --zone=public --add-service=ntp --permanent     # 123/udp (chrony server)
firewall-cmd --zone=public --add-port=3260/tcp --permanent   # iSCSI target (LIO)
firewall-cmd --zone=public --add-port=1521/tcp --permanent   # Observer — DGMGRL outbound
firewall-cmd --zone=public --add-port=1522/tcp --permanent   # Observer — DGMGRL
firewall-cmd --zone=public --add-port=6200/tcp --permanent   # ONS

firewall-cmd --reload
```

**client01:**
```bash
# Client01 initiates outbound connections to the cluster — it does not accept inbound Oracle connections.
firewall-cmd --zone=public --add-service=ssh --permanent

firewall-cmd --reload
```

---

## 5. SSH login configuration (passwordless)

After completing the installation of all 5 machines, you must configure SSH authorization without passwords (User-Equivalency).

### Method 1: Quick Automated Path (Recommended)

The script uses `sshpass` to set up the full mesh of connections for the `grid` and `oracle` users automatically.

1.  Log in to `prim01` as `root` (password: `Oracle26ai_LAB!`).
2.  Run the script:
    ```bash
    bash /tmp/scripts/ssh_setup.sh
    ```

### Method 2: Manual Path (Step by step)

For those who want to generate and distribute the keys themselves without additional scripts.

**GRID user (RAC cluster only)**
1. Log in to `prim01` as the `grid` user.
2. Generate a key and copy it to the second node:
    ```bash
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    ssh-copy-id grid@prim01
    ssh-copy-id grid@prim02
    ```
3. Log in to `prim02` as the `grid` user.
4. Generate a key and copy it to the first node:
    ```bash
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    ssh-copy-id grid@prim01
    ssh-copy-id grid@prim02
    ```
5. Test from `prim01` (without entering a password): `ssh prim02 date`.

**ORACLE user (full mesh across all databases and the observer)**
On each node (`prim01`, `prim02`, `stby01`, `infra01`), while logged in as `oracle`, generate a key with `ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa`.
Then, from each of these nodes, exchange the key with every other (forming a full mesh), most easily achieved by manually issuing 16 `ssh-copy-id` operations:
```bash
ssh-copy-id oracle@prim01
ssh-copy-id oracle@prim02
ssh-copy-id oracle@stby01
ssh-copy-id oracle@infra01
```

This makes the environment ready for cluster installation.

---

## 6. Shared folder `/mnt/oracle_binaries` (Oracle binaries)

The script from section 1 (`vbox_create_vms.ps1`) and the kickstart together configure access to the `D:\OracleBinaries` directory from the Windows host:

- `vbox_create_vms.ps1` registers the shared folder in each VM:
  ```powershell
  VBoxManage sharedfolder add <vm> --name OracleBinaries --hostpath "D:\OracleBinaries" --automount
  ```
- Each kickstart adds an entry to `/etc/fstab`:
  ```
  OracleBinaries  /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
  ```

### Are VirtualBox Guest Additions required?

**On Oracle Linux 8.10 with UEK — NO.** OL 8 boots `kernel-uek` (Unbreakable Enterprise Kernel) by default. The `kernel-uek-modules-extra` package contains the `vboxguest.ko` and `vboxsf.ko` modules built in by Oracle (which develops both OL and VirtualBox). The kernel will load the module on its own at the first `mount -t vboxsf`.

**On other distributions / RHCK — YES.** If you use:
- RHEL / CentOS / AlmaLinux / Rocky Linux with the default RHCK kernel
- OL 8 explicitly switched to RHCK (`grub2-set-default`)
- OL 9 (check that `vboxsf.ko` is present: `modinfo vboxsf`)

...you must install Guest Additions from the ISO. From the host (Windows, the VM must be powered off):
```powershell
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $VBox storageattach prim01 --storagectl "SATA" --port 2 --device 0 `
    --type dvddrive --medium "C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso"
```
In the VM after reboot (as root):
```bash
dnf install -y kernel-devel kernel-headers gcc make perl
mkdir -p /mnt/vboxga && mount /dev/sr1 /mnt/vboxga
sh /mnt/vboxga/VBoxLinuxAdditions.run --nox11
usermod -aG vboxsf oracle
usermod -aG vboxsf grid
```

### Verification after kickstart (on each VM)

```bash
# Should return the list of ZIPs from D:\OracleBinaries
ls /mnt/oracle_binaries/

# If the directory is empty — manual mount (boot-time race condition):
mount /mnt/oracle_binaries
ls /mnt/oracle_binaries/
```

> **Note:** The `nofail` option in fstab ensures that a failed mount does not block VM boot. If `/mnt/oracle_binaries` is empty after a reboot, `mount /mnt/oracle_binaries` is enough — no reboot is required.
