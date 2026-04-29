> [🇬🇧 English](./02_OS_and_Network_Preparation.md) | 🇵🇱 Polski

# 02 — Przygotowanie OS, Sieci i Kickstart (VMs2-install)

> **Cel:** Szybka, powtarzalna instalacja Oracle Linux 8.10 na 5 maszynach wirtualnych przy użyciu plików Kickstart (`.cfg`) oraz konfiguracja kluczy SSH.
> **Uwaga odnośnie IP:** Adresacja NAT (`10.x.x.x`) bywa problematyczna przy instalacji z użyciem Kickstart (uruchamianie serwera HTTP na hoście Windows). Dokument ten wyjaśnia, jak rozwiązać ten problem.

---

## 1. Tworzenie maszyn wirtualnych w VirtualBox

Zanim zaczniesz instalację OS, musisz zdefiniować strukturę VM-ek w VirtualBox. Robi to skrypt `scripts/vbox_create_vms.ps1` uruchamiany **raz na hoście Windows**.

### Wymagania wstępne

| Wymaganie | Szczegół |
|-----------|----------|
| VirtualBox 7.x | Zainstalowany na hoście Windows |
| Host-Only Ethernet Adapter #2 | Skonfigurowany w VirtualBox Manager: `192.168.56.1/24`, DHCP wyłączony |
| ISO Oracle Linux 8.10 | `D:\ISOs\OracleLinux-R8-U10-x86_64-dvd.iso` |
| Binarki Oracle (opcjonalne) | `D:\OracleBinaries\` — ZIP-y GI/DB/Client 23.26 (patrz sekcja 5) |

### Uruchomienie skryptu

Otwórz PowerShell **jako Administrator** i wykonaj:

```powershell
cd <repo>
.\scripts\vbox_create_vms.ps1
```

### Co tworzy skrypt

Dla każdej z 5 VM skrypt wykonuje:
- `VBoxManage createvm` — rejestruje VM w VirtualBox (katalog: `D:\VM\<nazwa>\`)
- `VBoxManage modifyvm` — ustawia CPU, RAM, paravirt KVM, virtio-net, RTC UTC
- `VBoxManage storagectl` — tworzy kontroler SATA (hostiocache on tylko dla infra01)
- `VBoxManage createmedium` + `storageattach` — tworzy i podpina dyski VDI
- `VBoxManage storageattach` — montuje ISO OL 8.10 jako DVD
- `VBoxManage modifyvm --nic*` — konfiguruje karty sieciowe wg roli VM
- `VBoxManage sharedfolder add` — rejestruje shared folder `D:\OracleBinaries` (patrz sekcja 5)

### Parametry VM po uruchomieniu skryptu

| VM | CPU | RAM | Dysk OS | Dysk 2 | Rola |
|----|-----|-----|---------|--------|------|
| `infra01` | 2 | 8 GB | 40 GB | 100 GB (LVM/iSCSI backstore) | DNS + NTP + iSCSI target + Observer |
| `prim01` | 4 | 9 GB | 60 GB | — | RAC node 1 |
| `prim02` | 4 | 9 GB | 60 GB | — | RAC node 2 |
| `stby01` | 4 | 6 GB | 100 GB | — | Standby + Oracle Restart |
| `client01` | 2 | 3 GB | 30 GB | — | Java UCP/TAC TestHarness |

> **Uwaga:** Skrypt jest idempotentny — jeśli VM już istnieje, pomija `createvm` i przechodzi dalej. Bezpieczny do ponownego uruchomienia.

---

## 2. Pobieranie plików Kickstart (HTTP Server)

Zamiast przeklikiwać instalatora (Anaconda), użyjemy plików Kickstart. Najprostszym sposobem dostarczenia ich do maszyn wirtualnych jest uruchomienie prostego serwera HTTP w katalogu z plikami `.cfg` na komputerze hosta (Windows).

1.  Otwórz PowerShell na hoście (Windows).
2.  Przejdź do utworzonego katalogu `kickstart/` (w `VMs2-install`):
    ```powershell
    cd <repo>\kickstart
    ```
3.  Uruchom serwer HTTP (port 8000):
    ```powershell
    python -m http.server 8000
    ```

---

## 3. Bootowanie maszyn wirtualnych (Rozwiązanie problemu IP)

### Problem z NAT (10.0.x.x) a Host-Only (192.168.56.1)
Wirtualizator VirtualBox dla interfejsu NAT domyślnie przydziela podsieć `10.0.2.0/24` lub w przypadku NAT Network np. `10.0.5.0/24`. Problem polega na tym, że serwer Python uruchomiony na hoście (Windows) może być niewidoczny z wnętrza środowiska NAT instalatora przed pełnym skonfigurowaniem sieci. 
Dlatego **niezawodnym rozwiązaniem** jest użycie interfejsu Host-Only (który ma stały adres IP na hoście, zazwyczaj `192.168.56.1`).

### Jak zainicjować instalację?
Uruchom VM z ISO (Oracle Linux 8.10), na ekranie wyboru naciśnij klawisz `TAB` (edycja linii boot) i dopisz **na samym końcu** odpowiednie parametry.

> **Opcja A (Rekomendowana, niezawodna - via Host-Only):**
> Pobieramy kickstart przez pierwszą kartę sieciową (enp0s3), która jest podpięta do `vboxnet0` (Host-Only).
> ```text
> inst.ip=192.168.56.10::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-infra01.cfg
> ```

### Parametry GRUB dla poszczególnych VM (Opcja A - Host-Only)

| VM | Parametry GRUB (dopisz po `quiet`) |
|----|-------------------------------------|
| `infra01` | `inst.ip=192.168.56.10::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-infra01.cfg` |
| `prim01` | `inst.ip=192.168.56.11::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-prim01.cfg` |
| `prim02` | `inst.ip=192.168.56.12::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-prim02.cfg` |
| `stby01` | `inst.ip=192.168.56.13::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-stby01.cfg` |
| `client01`| `inst.ip=192.168.56.15::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/ks-client01.cfg` |

*(Po wciśnięciu Enter Anaconda sama zajmie się instalacją, utworzy strukturę katalogów, wyłączy THP i zaktualizuje system - ok. 10 minut na maszynę).*

---

## 4. DNS, NTP i memlock — weryfikacja po kickstart

> **Kickstart robi to automatycznie.** Kickstart infra01 konfiguruje `bind9` (strefa lab.local) i `chrony` (serwer NTP). Kickstarty prim01/prim02/stby01/client01 konfigurują chrony jako klient (IP `192.168.56.10`) i wymuszają DNS resolver na `enp0s3`. Sekcje 4a–4c to ścieżka **fallback/recovery** — uruchom je tylko gdy kickstart nie zadziałał lub gdy reinsstalujesz wybraną VM bez pełnego kickstartu.

### 4a. DNS (bind9) na infra01 — fallback

Jeśli po restarcie infra01 `dig prim01.lab.local +short` nie zwraca `192.168.56.11`:

```bash
# infra01 (root) — konfiguruje named.conf + zone files + startuje named:
sudo bash /tmp/scripts/setup_dns_infra01.sh
```

**Weryfikacja:**
```bash
dig @192.168.56.10 scan-prim.lab.local +short  # → 192.168.56.31, .32, .33
systemctl is-active named                       # → active
```

### 4b. Chrony / DNS resolver — fallback

Jeśli po restarcie którejś VM `cat /etc/resolv.conf` nie pokazuje `nameserver 192.168.56.10`:

```bash
# infra01 (root) — rekonfiguruje chrony jako serwer NTP dla lab.local:
sudo bash /tmp/scripts/setup_chrony.sh --role=server

# prim01 / prim02 / stby01 / client01 (root każda) — wymusza DNS resolver + chrony klient:
sudo bash /tmp/scripts/setup_chrony.sh --role=client
```

**Weryfikacja:**
```bash
dig prim02.lab.local +short     # → 192.168.56.12
dig scan-prim.lab.local +short  # → 192.168.56.31, .32, .33
cat /etc/resolv.conf            # → nameserver 192.168.56.10
chronyc sources                 # → infra01 jako źródło (lub IP 192.168.56.10)
```

### 4c. memlock — weryfikacja

Kickstarty tworzą `zz-oracle-memlock.conf` (prefix `zz-` > `oracle-database-preinstall-23ai.conf` — zawsze wygrywa). Sprawdź po pierwszym zalogowaniu:

```bash
su - oracle -c 'ulimit -l'   # → unlimited
su - grid   -c 'ulimit -l'   # → unlimited

# Jeśli NIE (stary kickstart z 99-oracle-memlock.conf) — jednorazowo:
cat > /etc/security/limits.d/zz-oracle-memlock.conf <<'EOF'
oracle  soft  memlock  unlimited
oracle  hard  memlock  unlimited
grid    soft  memlock  unlimited
grid    hard  memlock  unlimited
EOF
```

### 4d. Firewall — konfiguracja przed instalacją GI (wymagane)

> **Kickstart nowych VM robi to automatycznie** (`firewall --disabled`). Sekcja ta dotyczy istniejących VM lub reinstalacji bez pełnego kickstartu.

**Dlaczego to jest krytyczne:** Oracle Grid Infrastructure uruchamia `cluvfy` (CVU) przed instalacją i testuje **pełną łączność TCP** między węzłami — nie tylko port 22. CRS używa portów dynamicznych (CSS, OHASd, agenty) w zakresach 27015–27025, 42424 i efemerycznych. Firewalld w strefie `public` blokuje je wszystkie → `FATAL PRVG-11067 No route to host` i przerwanie instalacji.

---

#### Opcja A — Wyłącz firewalld (zalecane dla LAB)

Najszybsze i bezpieczne w izolowanym środowisku VirtualBox. Wykonaj na **wszystkich pięciu VM** jako root:

```bash
systemctl stop firewalld
systemctl disable firewalld
```

Weryfikacja:
```bash
systemctl is-active firewalld    # → inactive
systemctl is-enabled firewalld   # → disabled
```

---

#### Opcja B — Skonfiguruj firewalld per-VM

Dla osób, które chcą zachować firewalld. Interfejsy prywatne (interconnect, storage) trafiają do strefy `trusted` (brak filtrowania). Na interfejsie publicznym węzłów RAC dopuszczamy cały ruch z podsieci LAB (`192.168.56.0/24`) — cluvfy testuje porty dynamiczne, których jawna lista byłaby za długa.

**prim01 i prim02:**
```bash
# Prywatne — brak filtrowania:
firewall-cmd --zone=trusted --add-interface=enp0s8 --permanent  # interconnect 192.168.100.x
firewall-cmd --zone=trusted --add-interface=enp0s9 --permanent  # storage 192.168.200.x

# Publiczny (host-only 192.168.56.x) — akceptuj cały ruch z podsieci LAB
# (odpowiednik disable dla cluvfy, przy zachowaniu filtrowania ruchu zewnętrznego przez NAT):
firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="192.168.56.0/24" accept' --permanent
firewall-cmd --zone=public --add-service=ssh --permanent

firewall-cmd --reload
firewall-cmd --list-all  # weryfikacja
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
# Client01 inicjuje połączenia wychodzące do klastra — nie przyjmuje przychodzących Oracle.
firewall-cmd --zone=public --add-service=ssh --permanent

firewall-cmd --reload
```

---

## 5. Konfiguracja logowania SSH (Bezhasłowe)

Po zakończeniu instalacji wszystkich 5 maszyn, konieczne jest skonfigurowanie autoryzacji SSH bez użycia haseł (User-Equivalency). 

### Metoda 1: Szybka Ścieżka Automatyczna (Zalecana)

Skrypt wykorzystuje `sshpass`, dzięki czemu nawiązuje pełną siatkę połączeń dla użytkownika `grid` i `oracle` automatycznie.

1.  Zaloguj się na `prim01` jako `root` (hasło: `Oracle26ai_LAB!`).
2.  Uruchom skrypt:
    ```bash
    bash /tmp/scripts/ssh_setup.sh
    ```

### Metoda 2: Ścieżka Manualna (Krok po kroku)

Dla osób, które chcą samodzielnie wygenerować i rozesłać klucze bez dodatkowych skryptów.

**Użytkownik GRID (tylko klaster RAC)**
1. Zaloguj się na `prim01` jako użytkownik `grid`.
2. Wygeneruj klucz i wyślij na drugi węzeł:
    ```bash
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    ssh-copy-id grid@prim01
    ssh-copy-id grid@prim02
    ```
3. Zaloguj się na `prim02` jako użytkownik `grid`.
4. Wygeneruj klucz i wyślij na pierwszy węzeł:
    ```bash
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    ssh-copy-id grid@prim01
    ssh-copy-id grid@prim02
    ```
5. Przetestuj z `prim01` (bez podawania hasła): `ssh prim02 date`.

**Użytkownik ORACLE (pełna siatka na wszystkie bazy i observera)**
Wykonaj na każdym węźle (`prim01`, `prim02`, `stby01`, `infra01`) będąc zalogowanym jako `oracle` generowanie klucza `ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa`.
Następnie z każdego z tych węzłów wymień się kluczem z każdym innym (tworząc tzw. Full Mesh), co najłatwiej osiągnąć rozsyłając ręcznie 16 relacji `ssh-copy-id`:
```bash
ssh-copy-id oracle@prim01
ssh-copy-id oracle@prim02
ssh-copy-id oracle@stby01
ssh-copy-id oracle@infra01
```

Dzięki temu środowisko jest gotowe do instalacji klastra.

---

## 6. Shared Folder `/mnt/oracle_binaries` (binarki Oracle)

Skrypt z sekcji 1 (`vbox_create_vms.ps1`) i kickstart wspólnie konfigurują dostęp do katalogu `D:\OracleBinaries` z hosta Windows:

- `vbox_create_vms.ps1` rejestruje shared folder w każdej VM:
  ```powershell
  VBoxManage sharedfolder add <vm> --name OracleBinaries --hostpath "D:\OracleBinaries" --automount
  ```
- Każdy kickstart dodaje wpis do `/etc/fstab`:
  ```
  OracleBinaries  /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0
  ```

### Czy potrzebne są VirtualBox Guest Additions?

**Na Oracle Linux 8.10 z UEK — NIE.** OL 8 domyślnie bootuje z `kernel-uek` (Unbreakable Enterprise Kernel). Pakiet `kernel-uek-modules-extra` zawiera moduły `vboxguest.ko` i `vboxsf.ko` wbudowane przez Oracle (który rozwija jednocześnie OL i VirtualBox). Kernel sam załaduje moduł przy pierwszym `mount -t vboxsf`.

**Na innych dystrybucjach / RHCK — TAK.** Jeśli używasz:
- RHEL / CentOS / AlmaLinux / Rocky Linux z domyślnym kernel RHCK
- OL 8 z jawnie przełączonym na RHCK (`grub2-set-default`)
- OL 9 (sprawdź obecność `vboxsf.ko`: `modinfo vboxsf`)

...musisz zainstalować Guest Additions z ISO. Z hosta (Windows, VM musi być wyłączona):
```powershell
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $VBox storageattach prim01 --storagectl "SATA" --port 2 --device 0 `
    --type dvddrive --medium "C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso"
```
W VM po reboot (jako root):
```bash
dnf install -y kernel-devel kernel-headers gcc make perl
mkdir -p /mnt/vboxga && mount /dev/sr1 /mnt/vboxga
sh /mnt/vboxga/VBoxLinuxAdditions.run --nox11
usermod -aG vboxsf oracle
usermod -aG vboxsf grid
```

### Weryfikacja po kickstart (na każdej VM)

```bash
# Powinno zwrócić listę ZIP-ów z D:\OracleBinaries
ls /mnt/oracle_binaries/

# Jeśli katalog jest pusty — ręczne zamontowanie (race condition przy boot):
mount /mnt/oracle_binaries
ls /mnt/oracle_binaries/
```

> **Uwaga:** Opcja `nofail` w fstab sprawia, że brak montowania nie blokuje bootu VM. Jeśli `/mnt/oracle_binaries` jest puste po restarcie, wystarczy `mount /mnt/oracle_binaries` — nie jest potrzebny restart.

