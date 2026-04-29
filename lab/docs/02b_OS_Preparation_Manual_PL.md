> [🇬🇧 English](./02b_OS_Preparation_Manual.md) | 🇵🇱 Polski

# 02b — Przygotowanie OS Manualnie (bez Kickstart)

> **Kiedy używać tego dokumentu:** gdy instalujesz Oracle Linux ręcznie (przez klikanie w Anacondę, PXE bez pliku `.cfg`, reinstalację wybranego węzła lub środowisko inne niż VirtualBox). Wszystkie komendy są odpowiednikiem tego, co robią kickstarty z katalogu `kickstart/` — źródłem prawdy pozostają pliki `.cfg`.
>
> Jeśli instalujesz przez kickstart — przejdź do `02_OS_and_Network_Preparation_PL.md`.

---

## Wymagania wstępne

- Oracle Linux 8.x (testowane na 8.10) zainstalowany z grupą pakietów **"Server"** lub **"Server with GUI"**
- Sieć skonfigurowana wg topologii (patrz tabela poniżej) — co najmniej enp0s3 z dostępem do internetu lub lokalnego repozytorium DNF
- Zalogowany jako `root`
- Dla prim01/prim02: dysk `/u01` zamontowany jako osobna partycja XFS (≥ 35 GB)
- Dla stby01: `/u01` (≥ 30 GB), `/u02` (≥ 40 GB), `/u03` (reszta dysku)

### Adresy IP i role

| Host | enp0s3 (publiczny) | enp0s8 (interconnect/NAT) | enp0s9 (storage) | Rola |
|------|--------------------|---------------------------|-------------------|------|
| infra01 | 192.168.56.10 | 192.168.100.10 | 192.168.200.10 | DNS + NTP + iSCSI target + Observer |
| prim01 | 192.168.56.11 | 192.168.100.11 | 192.168.200.11 | RAC node 1 |
| prim02 | 192.168.56.12 | 192.168.100.12 | 192.168.200.12 | RAC node 2 |
| stby01 | 192.168.56.13 | DHCP/NAT | — | Standby + Oracle Restart |
| client01 | 192.168.56.15 | DHCP/NAT | — | Java UCP TestHarness |

---

## 1. infra01

### 1.1 Hostname i sieć

```bash
hostnamectl set-hostname infra01.lab.local

# Statyczne IP na enp0s3 (publiczny — Host-Only):
nmcli connection modify "System enp0s3" \
    ipv4.method manual \
    ipv4.addresses 192.168.56.10/24 \
    ipv4.gateway 192.168.56.1 \
    ipv4.dns "127.0.0.1" \
    ipv4.dns-search "lab.local" \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s3"

# Statyczne IP na enp0s8 (interconnect):
nmcli connection modify "System enp0s8" \
    ipv4.method manual \
    ipv4.addresses 192.168.100.10/24 \
    ipv4.never-default yes \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s8"

# Statyczne IP na enp0s9 (storage / iSCSI):
nmcli connection modify "System enp0s9" \
    ipv4.method manual \
    ipv4.addresses 192.168.200.10/24 \
    ipv4.never-default yes \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s9"

# Wyłącz auto-DNS z interfejsu NAT (enp0s10):
nmcli connection modify "System enp0s10" ipv4.ignore-auto-dns yes 2>/dev/null || true
```

### 1.2 Firewall — wyłącz

```bash
systemctl stop firewalld
systemctl disable firewalld
```

### 1.3 Pakiety

```bash
dnf config-manager --enable ol8_appstream ol8_addons ol8_codeready_builder 2>/dev/null || true
dnf install -y @development @system-tools @network-server \
    bind bind-utils targetcli \
    chrony vim-enhanced wget curl tar unzip net-tools \
    lsof strace tmux python3 python3-pip rsync bash-completion sshpass
dnf update -y
```

### 1.4 Grupy i użytkownicy Oracle

```bash
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54325 dgdba

useradd -u 54322 -g oinstall -G dba,dgdba -m -s /bin/bash oracle
echo "oracle:Oracle26ai_LAB!" | chpasswd
```

### 1.4a Kernel sysctl dla Oracle Client (PRVG-1205)

> **Kontekst:** infra01 nie ma `oracle-database-preinstall-23ai` (to nie host DB), więc wymaga ręcznego ustawienia sysctl, których oczekuje runInstaller Klienta 26ai. Bez tego: `INS-13014` + `PRVG-1205` na `file-max`, `rmem_default`, `rmem_max`, `wmem_default`, `wmem_max`, `aio-max-nr`. Z `-ignorePrereqFailure` install się dokończy, ale dla porządku ustawiamy te parametry.

```bash
cat > /etc/sysctl.d/97-oracle-client.conf <<'EOF'
fs.file-max = 6815744
fs.aio-max-nr = 1048576
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
net.ipv4.ip_local_port_range = 9000 65500
EOF
sysctl -p /etc/sysctl.d/97-oracle-client.conf

# Weryfikacja:
sysctl fs.file-max fs.aio-max-nr net.core.rmem_max
```

### 1.5 Katalogi dla Observera (Master `obs_ext` na infra01)

```bash
mkdir -p /etc/oracle/tns/obs_ext
mkdir -p /etc/oracle/wallet/obs_ext
mkdir -p /var/log/oracle/obs_ext
chown oracle:oinstall \
    /etc/oracle/tns/obs_ext \
    /etc/oracle/wallet/obs_ext \
    /var/log/oracle/obs_ext
chmod 700 /etc/oracle/wallet/obs_ext
```

> **Uwaga:** Backup Observer (`obs_dc` na prim01, `obs_dr` na stby01) używa analogicznych ścieżek (`/etc/oracle/{tns,wallet}/obs_dc` / `obs_dr`). Skrypt `setup_observer.sh` tworzy je automatycznie przez `OBSERVER_NAME=...`.

### 1.6 VirtualBox Shared Folders (opcjonalne)

```bash
mkdir -p /mnt/oracle_binaries /mnt/rman_bck
cat >> /etc/fstab <<'EOF'
OracleBinaries        /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
_RMAN_BCK_from_Linux_  /mnt/rman_bck         vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
EOF
```

### 1.7 Wyłącz Transparent HugePages (THP)

```bash
cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now disable-thp.service

# Weryfikacja (nie czekaj na reboot):
cat /sys/kernel/mm/transparent_hugepage/enabled   # → always madvise [never]
```

### 1.8 MTU 9000 na enp0s9 (Jumbo frames dla iSCSI)

```bash
nmcli connection modify "System enp0s9" 802-3-ethernet.mtu 9000 || \
  nmcli connection modify "Wired connection 3" 802-3-ethernet.mtu 9000 || true
nmcli connection up "System enp0s9"
```

### 1.9 NTP — chrony serwer dla lab.local

```bash
cat > /etc/chrony.conf <<'EOF'
pool pool.ntp.org iburst maxsources 4
allow 192.168.56.0/24
allow 192.168.100.0/24
allow 192.168.200.0/24
local stratum 10
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
keyfile /etc/chrony.keys
logdir /var/log/chrony
EOF
systemctl enable --now chronyd

# Weryfikacja:
chronyc tracking      # → Stratum > 0
chronyc clients       # → po kilku minutach pojawią się klienty
```

### 1.10 DNS — bind9 (named) strefa lab.local

```bash
cat > /etc/named.conf <<'EOF'
options {
    listen-on port 53 { 127.0.0.1; 192.168.56.10; };
    listen-on-v6 port 53 { none; };
    directory     "/var/named";
    dump-file     "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    allow-query   { localhost; 192.168.56.0/24; 192.168.100.0/24; 192.168.200.0/24; };
    recursion yes;
    forwarders    { 8.8.8.8; 1.1.1.1; };
    forward first;
    dnssec-validation auto;
};
logging {
    channel default_debug { file "data/named.run"; severity dynamic; };
};
zone "." IN { type hint; file "named.ca"; };
zone "lab.local" IN {
    type master; file "db.lab.local"; allow-update { none; };
};
zone "56.168.192.in-addr.arpa" IN {
    type master; file "db.56.168.192"; allow-update { none; };
};
zone "100.168.192.in-addr.arpa" IN {
    type master; file "db.100.168.192"; allow-update { none; };
};
EOF

cat > /var/named/db.lab.local <<'EOF'
$TTL 86400
@       IN SOA  infra01.lab.local. admin.lab.local. (
                2026042801 3600 900 1209600 3600 )
        IN NS   infra01.lab.local.
infra01      IN A  192.168.56.10
prim01       IN A  192.168.56.11
prim02       IN A  192.168.56.12
stby01       IN A  192.168.56.13
client01     IN A  192.168.56.15
prim01-vip   IN A  192.168.56.21
prim02-vip   IN A  192.168.56.22
scan-prim    IN A  192.168.56.31
scan-prim    IN A  192.168.56.32
scan-prim    IN A  192.168.56.33
prim01-priv  IN A  192.168.100.11
prim02-priv  IN A  192.168.100.12
infra01-priv IN A  192.168.100.10
prim01-stor  IN A  192.168.200.11
prim02-stor  IN A  192.168.200.12
infra01-stor IN A  192.168.200.10
EOF

cat > /var/named/db.56.168.192 <<'EOF'
$TTL 86400
@  IN SOA  infra01.lab.local. admin.lab.local. (
           2026042801 3600 900 1209600 3600 )
   IN NS   infra01.lab.local.
10 IN PTR  infra01.lab.local.
11 IN PTR  prim01.lab.local.
12 IN PTR  prim02.lab.local.
13 IN PTR  stby01.lab.local.
15 IN PTR  client01.lab.local.
21 IN PTR  prim01-vip.lab.local.
22 IN PTR  prim02-vip.lab.local.
31 IN PTR  scan-prim.lab.local.
32 IN PTR  scan-prim.lab.local.
33 IN PTR  scan-prim.lab.local.
EOF

cat > /var/named/db.100.168.192 <<'EOF'
$TTL 86400
@  IN SOA  infra01.lab.local. admin.lab.local. (
           2026042801 3600 900 1209600 3600 )
   IN NS   infra01.lab.local.
10 IN PTR  infra01-priv.lab.local.
11 IN PTR  prim01-priv.lab.local.
12 IN PTR  prim02-priv.lab.local.
EOF

chown root:named /var/named/db.lab.local /var/named/db.56.168.192 /var/named/db.100.168.192
chmod 640 /var/named/db.lab.local /var/named/db.56.168.192 /var/named/db.100.168.192

named-checkconf
named-checkzone lab.local /var/named/db.lab.local
systemctl enable --now named

# Weryfikacja:
dig @127.0.0.1 prim01.lab.local +short      # → 192.168.56.11
dig @127.0.0.1 scan-prim.lab.local +short   # → 192.168.56.31, .32, .33
```

### 1.11 LVM — backstore dla iSCSI (dysk sdb)

> Wykonaj tylko jeśli infra01 ma drugi dysk (`/dev/sdb`). Sprawdź: `lsblk`.

```bash
pvcreate -ff -y /dev/sdb
vgcreate vg_iscsi /dev/sdb
lvcreate -L 5G  -n lun_ocr1  vg_iscsi
lvcreate -L 5G  -n lun_ocr2  vg_iscsi
lvcreate -L 5G  -n lun_ocr3  vg_iscsi
lvcreate -L 20G -n lun_data1 vg_iscsi
lvcreate -L 15G -n lun_reco1 vg_iscsi

# Weryfikacja:
lvs vg_iscsi
```

Dalszą konfigurację iSCSI target (targetcli) — patrz `docs/03_Storage_iSCSI.md`.

---

## 2. prim01

### 2.1 Hostname i sieć

```bash
hostnamectl set-hostname prim01.lab.local

nmcli connection modify "System enp0s3" \
    ipv4.method manual \
    ipv4.addresses 192.168.56.11/24 \
    ipv4.gateway 192.168.56.1 \
    ipv4.dns "192.168.56.10" \
    ipv4.dns-search "lab.local" \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s3"

nmcli connection modify "System enp0s8" \
    ipv4.method manual \
    ipv4.addresses 192.168.100.11/24 \
    ipv4.never-default yes \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s8"

nmcli connection modify "System enp0s9" \
    ipv4.method manual \
    ipv4.addresses 192.168.200.11/24 \
    ipv4.never-default yes \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s9"

# NAT — wyłącz auto-DNS żeby enp0s10 nie nadpisał resolv.conf:
nmcli connection modify "System enp0s10" ipv4.ignore-auto-dns yes 2>/dev/null || true
```

### 2.2 Firewall — wyłącz

```bash
systemctl stop firewalld
systemctl disable firewalld
```

### 2.3 Pakiety

```bash
dnf config-manager --enable ol8_appstream ol8_addons ol8_codeready_builder 2>/dev/null || true
dnf install -y @development @system-tools \
    chrony vim-enhanced wget curl tar unzip net-tools \
    lsof strace tmux python3 rsync bash-completion sshpass \
    oracle-database-preinstall-23ai \
    iscsi-initiator-utils
dnf update -y
```

> `oracle-database-preinstall-23ai` automatycznie konfiguruje część parametrów kernela i limitów. Kroki 2.7 i 2.8 są nadrzędne — nadpisują ustawienia preinstall.

### 2.4 Grupy i użytkownicy Oracle

```bash
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
groupadd -g 54324 backupdba
groupadd -g 54325 dgdba
groupadd -g 54326 kmdba
groupadd -g 54327 asmadmin
groupadd -g 54328 asmdba
groupadd -g 54329 asmoper
groupadd -g 54330 racdba

useradd -u 54321 -g oinstall -G asmadmin,asmdba,asmoper,dba,racdba \
    -m -s /bin/bash grid
useradd -u 54322 -g oinstall \
    -G dba,oper,backupdba,dgdba,kmdba,racdba,asmadmin,asmdba,asmoper \
    -m -s /bin/bash oracle

echo "grid:Oracle26ai_LAB!"   | chpasswd
echo "oracle:Oracle26ai_LAB!" | chpasswd
```

### 2.5 Katalogi i uprawnienia

```bash
mkdir -p /u01/app/grid
mkdir -p /u01/app/23.26/grid
mkdir -p /u01/app/oracle/product/23.26/dbhome_1
mkdir -p /u01/app/oraInventory

chown -R grid:oinstall   /u01/app/grid
chown -R grid:oinstall   /u01/app/23.26/grid
chown -R oracle:oinstall /u01/app/oracle
chown    grid:oinstall   /u01/app/oraInventory
chmod -R 775 /u01
chmod 770    /u01/app/oraInventory

# Weryfikacja:
ls -la /u01/app/
```

### 2.6 /etc/oraInst.loc

```bash
cat > /etc/oraInst.loc <<'EOF'
inventory_loc=/u01/app/oraInventory
inst_group=oinstall
EOF
chown root:root /etc/oraInst.loc
chmod 644 /etc/oraInst.loc
```

### 2.7 VirtualBox Shared Folders (opcjonalne)

```bash
mkdir -p /mnt/oracle_binaries /mnt/rman_bck
cat >> /etc/fstab <<'EOF'
OracleBinaries        /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
_RMAN_BCK_from_Linux_  /mnt/rman_bck         vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
EOF
```

### 2.8 Wyłącz THP

```bash
cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now disable-thp.service
```

### 2.9 HugePages dla SGA

```bash
# 2200 x 2 MB = 4,4 GB — pokrywa SGA ~4 GB RAC node z marginesem.
cat > /etc/sysctl.d/99-oracle-hugepages.conf <<'EOF'
vm.nr_hugepages = 2200
vm.hugetlb_shm_group = 54322
EOF
sysctl -p /etc/sysctl.d/99-oracle-hugepages.conf

# Weryfikacja:
grep HugePages_Total /proc/meminfo    # → HugePages_Total: 2200
```

### 2.10 memlock unlimited

```bash
# Prefix zz- gwarantuje, że ten plik wygrywa alfabetycznie z oracle-database-preinstall-23ai.conf.
cat > /etc/security/limits.d/zz-oracle-memlock.conf <<'EOF'
oracle  soft  memlock  unlimited
oracle  hard  memlock  unlimited
grid    soft  memlock  unlimited
grid    hard  memlock  unlimited
EOF

# Weryfikacja (po wylogowaniu i zalogowaniu):
su - oracle -c 'ulimit -l'   # → unlimited
su - grid   -c 'ulimit -l'   # → unlimited
```

### 2.11 MTU 9000 na enp0s9 (Jumbo frames)

```bash
nmcli connection modify "System enp0s9" 802-3-ethernet.mtu 9000 || \
  nmcli connection modify "Wired connection 3" 802-3-ethernet.mtu 9000 || true
nmcli connection up "System enp0s9"

# Weryfikacja (po konfiguracji iSCSI i infra01):
# ping -M do -s 8972 192.168.200.10   # → brak fragmentacji = OK
```

### 2.12 NTP — chrony klient

```bash
cat > /etc/chrony.conf <<'EOF'
server 192.168.56.10 iburst prefer
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
keyfile /etc/chrony.keys
logdir /var/log/chrony
EOF
systemctl enable --now chronyd

# Weryfikacja (po ~30 sek):
chronyc tracking    # → Reference ID: infra01 (lub 192.168.56.10)
```

### 2.13 Sekret laboratoryjny

```bash
tee /root/.lab_secrets >/dev/null <<'EOF'
export LAB_PASS='Oracle26ai_LAB!'
EOF
chmod 600 /root/.lab_secrets
```

### 2.14 Profile środowiskowe użytkowników (grid / oracle)

```bash
# grid — GI home + ORACLE_SID dla ASM (prim01=+ASM1, prim02=+ASM2, stby01=+ASM)
cat >> /home/grid/.bash_profile <<'EOF'

export ORACLE_BASE=/u01/app/grid
export ORACLE_HOME=/u01/app/23.26/grid
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=$ORACLE_HOME/network/admin
export ORACLE_SID=+ASM1
EOF

# oracle — DB home (ORACLE_SID ustawiany osobno w kroku 05 — po DBCA)
cat >> /home/oracle/.bash_profile <<'EOF'

export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=$ORACLE_HOME/network/admin
EOF
```

---

## 3. prim02

Identycznie jak `prim01` — zmień tylko adresy IP i hostname.

### 3.1 Różnice względem prim01

| Element | prim01 | prim02 |
|---------|--------|--------|
| Hostname | `prim01.lab.local` | `prim02.lab.local` |
| enp0s3 | `192.168.56.11/24` | `192.168.56.12/24` |
| enp0s8 | `192.168.100.11/24` | `192.168.100.12/24` |
| enp0s9 | `192.168.200.11/24` | `192.168.200.12/24` |
| `ORACLE_SID` (grid) | `+ASM1` | `+ASM2` |

Wykonaj kroki 2.1–2.14 z powyższymi adresami. Wszystkie pozostałe wartości (UID/GID, katalogi, HugePages, memlock, THP) są identyczne. W sekcji 2.14 dla `grid` użyj `ORACLE_SID=+ASM2` zamiast `+ASM1`.

---

## 4. stby01

### 4.1 Hostname i sieć

```bash
hostnamectl set-hostname stby01.lab.local

nmcli connection modify "System enp0s3" \
    ipv4.method manual \
    ipv4.addresses 192.168.56.13/24 \
    ipv4.gateway 192.168.56.1 \
    ipv4.dns "192.168.56.10" \
    ipv4.dns-search "lab.local" \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s3"

# enp0s8 — DHCP/NAT, wyłącz tylko jego auto-DNS:
nmcli connection modify "System enp0s8" ipv4.ignore-auto-dns yes 2>/dev/null || true
```

### 4.2 Firewall — wyłącz

```bash
systemctl stop firewalld
systemctl disable firewalld
```

### 4.3 Pakiety

```bash
dnf config-manager --enable ol8_appstream ol8_addons ol8_codeready_builder 2>/dev/null || true
dnf install -y @development @system-tools \
    chrony vim-enhanced wget curl tar unzip net-tools \
    lsof strace tmux python3 rsync bash-completion sshpass \
    oracle-database-preinstall-23ai
dnf update -y
```

### 4.4 Grupy i użytkownicy Oracle

```bash
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
groupadd -g 54324 backupdba
groupadd -g 54325 dgdba
groupadd -g 54326 kmdba
groupadd -g 54327 asmadmin
groupadd -g 54328 asmdba
groupadd -g 54329 asmoper

useradd -u 54321 -g oinstall -G asmadmin,asmdba,asmoper,dba \
    -m -s /bin/bash grid
useradd -u 54322 -g oinstall \
    -G dba,oper,backupdba,dgdba,kmdba,asmdba \
    -m -s /bin/bash oracle

echo "grid:Oracle26ai_LAB!"   | chpasswd
echo "oracle:Oracle26ai_LAB!" | chpasswd
```

> **Uwaga:** stby01 nie ma grupy `racdba` (54330) — to węzeł SI, nie RAC. Użytkownik `oracle` nie ma `asmadmin`/`asmoper`.

### 4.5 Katalogi i uprawnienia

```bash
mkdir -p /u01/app/grid
mkdir -p /u01/app/23.26/grid
mkdir -p /u01/app/oracle/product/23.26/dbhome_1
mkdir -p /u01/app/oraInventory
mkdir -p /u02/oradata/STBY
mkdir -p /u03/fra/STBY

chown -R grid:oinstall   /u01/app/grid
chown -R grid:oinstall   /u01/app/23.26/grid
chown -R oracle:oinstall /u01/app/oracle
chown    grid:oinstall   /u01/app/oraInventory
chown -R oracle:oinstall /u02
chown -R oracle:oinstall /u03
chmod -R 775 /u01 /u02 /u03
chmod 770    /u01/app/oraInventory
```

### 4.6 /etc/oraInst.loc

```bash
cat > /etc/oraInst.loc <<'EOF'
inventory_loc=/u01/app/oraInventory
inst_group=oinstall
EOF
chown root:root /etc/oraInst.loc
chmod 644 /etc/oraInst.loc
```

### 4.7 VirtualBox Shared Folders (opcjonalne)

```bash
mkdir -p /mnt/oracle_binaries /mnt/rman_bck
cat >> /etc/fstab <<'EOF'
OracleBinaries        /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
_RMAN_BCK_from_Linux_  /mnt/rman_bck         vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
EOF
```

### 4.8 Wyłącz THP

```bash
cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now disable-thp.service
```

### 4.9 HugePages dla SGA

```bash
# stby01 = Oracle Restart (SI) — SGA mniejsze niż RAC, 1100 x 2 MB = 2,2 GB.
cat > /etc/sysctl.d/99-oracle-hugepages.conf <<'EOF'
vm.nr_hugepages = 1100
vm.hugetlb_shm_group = 54322
EOF
sysctl -p /etc/sysctl.d/99-oracle-hugepages.conf
```

### 4.10 memlock unlimited

```bash
cat > /etc/security/limits.d/zz-oracle-memlock.conf <<'EOF'
oracle  soft  memlock  unlimited
oracle  hard  memlock  unlimited
grid    soft  memlock  unlimited
grid    hard  memlock  unlimited
EOF
```

### 4.11 NTP — chrony klient

```bash
cat > /etc/chrony.conf <<'EOF'
server 192.168.56.10 iburst prefer
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
keyfile /etc/chrony.keys
logdir /var/log/chrony
EOF
systemctl enable --now chronyd
```

### 4.12 Sekret laboratoryjny

```bash
tee /root/.lab_secrets >/dev/null <<'EOF'
export LAB_PASS='Oracle26ai_LAB!'
EOF
chmod 600 /root/.lab_secrets
```

### 4.13 Profile środowiskowe użytkowników (grid / oracle)

```bash
# grid — GI home + ORACLE_SID=+ASM (Oracle Restart — instancja standalone)
cat >> /home/grid/.bash_profile <<'EOF'

export ORACLE_BASE=/u01/app/grid
export ORACLE_HOME=/u01/app/23.26/grid
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=$ORACLE_HOME/network/admin
export ORACLE_SID=+ASM
EOF

# oracle — DB home (ORACLE_SID ustawiany osobno po DBCA/duplikacji standby)
cat >> /home/oracle/.bash_profile <<'EOF'

export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=$ORACLE_HOME/network/admin
EOF
```

---

## 5. client01

### 5.1 Hostname i sieć

```bash
hostnamectl set-hostname client01.lab.local

nmcli connection modify "System enp0s3" \
    ipv4.method manual \
    ipv4.addresses 192.168.56.15/24 \
    ipv4.gateway 192.168.56.1 \
    ipv4.dns "192.168.56.10" \
    ipv4.dns-search "lab.local" \
    ipv4.ignore-auto-dns yes
nmcli connection up "System enp0s3"

# enp0s8 — DHCP/NAT, wyłącz auto-DNS:
nmcli connection modify "System enp0s8" ipv4.ignore-auto-dns yes 2>/dev/null || true
```

### 5.2 Firewall — wyłącz

```bash
systemctl stop firewalld
systemctl disable firewalld
```

### 5.3 Pakiety

```bash
dnf config-manager --enable ol8_appstream ol8_addons ol8_codeready_builder 2>/dev/null || true
dnf install -y @headless-management \
    chrony vim-enhanced wget curl tar unzip net-tools \
    python3 bash-completion sshpass \
    java-17-openjdk java-17-openjdk-devel
dnf update -y
```

### 5.4 Grupy i użytkownicy Oracle

```bash
groupadd -g 54321 oinstall

useradd -u 54322 -g oinstall -m -s /bin/bash oracle
echo "oracle:Oracle26ai_LAB!" | chpasswd
```

### 5.5 Katalogi

```bash
mkdir -p /u01/app/oracle/product/23.26/client_1
mkdir -p /opt/lab/jars

chown -R oracle:oinstall /u01
chown -R kris:kris /opt/lab 2>/dev/null || chown -R oracle:oinstall /opt/lab
chmod -R 775 /u01
```

### 5.6 VirtualBox Shared Folders (opcjonalne)

```bash
mkdir -p /mnt/oracle_binaries /mnt/rman_bck
cat >> /etc/fstab <<'EOF'
OracleBinaries        /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
_RMAN_BCK_from_Linux_  /mnt/rman_bck         vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
EOF
```

### 5.7 NTP — chrony klient

```bash
cat > /etc/chrony.conf <<'EOF'
server 192.168.56.10 iburst prefer
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
keyfile /etc/chrony.keys
logdir /var/log/chrony
EOF
systemctl enable --now chronyd
```

---

## 6. Weryfikacja końcowa

Po skonfigurowaniu wszystkich hostów uruchom na **prim01** jako oracle lub grid:

```bash
bash /tmp/scripts/validate_env.sh --full
```

Oczekiwany wynik: **16 PASS, 3 WARN (porty — pre-install), 0 FAIL**.

Jeśli pojawią się FAIL — patrz komentarze w `validate_env.sh` lub sekcja 4 w `02_OS_and_Network_Preparation_PL.md`.

> **Uwaga:** `/etc/oraInst.loc` nie jest weryfikowany przez `validate_env.sh`. Sprawdź ręcznie przed GI install:
> ```bash
> cat /etc/oraInst.loc           # na prim01 i prim02
> ls -la /u01/app/oraInventory   # drwxrwx--- grid oinstall
> ```
