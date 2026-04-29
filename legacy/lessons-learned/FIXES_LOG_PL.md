> [🇬🇧 English](./FIXES_LOG.md) | 🇵🇱 Polski

# FIXES LOG — FSFO+TAC Lab VMs

Historia problemów napotkanych podczas budowania środowiska i wprowadzonych poprawek.

---

## 2026-04-24

### FIX-001 — vbox_create_vms.ps1: nazwa interfejsu host-only (Windows vs Linux)

**Problem:** Skrypt używał nazwy `vboxnet0` (konwencja Linux). Na Windows VirtualBox tworzy interfejsy o nazwie `VirtualBox Host-Only Ethernet Adapter` (lub `#2`, `#3` itd.).

**Objaw:**
```
VBoxManage.exe: error: The host network interface named 'vboxnet0' could not be found
```

**Poprawka:** `scripts/vbox_create_vms.ps1`
- Dodano zmienną `$HostOnlyIF = "VirtualBox Host-Only Ethernet Adapter #2"`
- Zastąpiono wszystkie wystąpienia `vboxnet0` zmienną `$HostOnlyIF`
- Usunięto `hostonlyif create` (adapter już istniał)

---

### FIX-002 — 02_virtualbox_setup.md: brakująca zmienna `$VBox`

**Problem:** W przykładzie PowerShell dla shared folders brakowało definicji `$VBox`.

**Poprawka:** `02_virtualbox_setup.md`
- Dodano `$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"` przed `$src`

---

### FIX-003 — 02_virtualbox_setup.md: sekcja weryfikacji — `grep` nie działa w PowerShell

**Problem:** Sekcja 7 używała `grep -E` i `grep -A` które nie istnieją w PowerShell.

**Poprawka:** `02_virtualbox_setup.md`
- Sekcja 7 podzielona na dwa bloki: **Windows (PowerShell)** i **Linux/macOS**
- `grep -E "..."` → `Select-String -Pattern "..."`
- `grep -A 20 "..."` → `Select-String -Pattern "..." -Context 0,20`

---

### FIX-004 — kickstart: backslash `\` nie działa jako kontynuacja linii

**Problem:** Dyrektywa `network` w kickstarcie zapisana wieloliniowo z `\`. Anaconda kickstart parser **nie obsługuje** backslasha jako kontynuacji linii — traktuje go jako argument.

**Objaw:**
```
Unknown command: --ip=192.168.56.10
Unknown command: --nameserver=127.0.0.1,8.8.8.8
Unknown command: --activate
```
(każda linia po `\` była traktowana jako osobna, nieprawidłowa komenda)

**Poprawka:** Wszystkie 5 plików `kickstart/ks-*.cfg`
- Każda dyrektywa `network` zapisana w jednej linii

---

### FIX-005 — kickstart: `--ipv4-dns-search` nie jest prawidłową opcją

**Problem:** Opcja `--ipv4-dns-search=lab.local` użyta w dyrektywie `network` — nie istnieje w kickstart RHEL8/OL8.

**Poprawka:** Wszystkie 5 plików `kickstart/ks-*.cfg`
- Usunięto `--ipv4-dns-search=lab.local` z dyrektyw `network`
- DNS search domain konfigurowany jest później przez nmcli

---

### FIX-006 — 03_os_install_ol810.md: błędny adres do pobrania kickstartu

**Problem (iteracja 1):** URL `http://192.168.56.1:8000/...` — initrd nie konfiguruje karty host-only (brak DHCP), więc nie może pobrać pliku.

**Problem (iteracja 2):** URL `http://10.0.2.2:8000/...` — `10.0.2.2` to wirtualny router VirtualBox NAT, nie jest prawdziwym interfejsem Windows. Python HTTP server na nim nie nasłuchuje → `Connection refused`.

**Rozwiązanie:** Parametr `inst.ip` konfiguruje statyczny IP na `enp0s3` **przed** próbą pobrania kickstartu, dzięki czemu `192.168.56.1:8000` jest osiągalne.

**Poprawka:** `03_os_install_ol810.md` — tabela parametrów GRUB:
```
inst.ip=192.168.56.XX::192.168.56.1:255.255.255.0::enp0s3:none inst.ks=http://192.168.56.1:8000/kickstart/ks-<vm>.cfg
```

---

### FIX-007 — kickstart: `compat-openssl11` nie ma na DVD ISO

**Problem:** Pakiet `compat-openssl11` wymieniony w sekcji `%packages` nie jest dostępny na lokalnym DVD ISO OL 8.10. Anaconda zadaje pytanie interaktywne:
```
Problems in request: missing packages: compat-openssl11
Would you like to ignore this and continue installation?
```

**Doraźnie:** wpisać `yes` — instalacja kontynuuje bez przerywania.

**Poprawka:** `kickstart/ks-prim01.cfg`, `ks-prim02.cfg`, `ks-stby01.cfg`
- Usunięto `compat-openssl11` z sekcji `%packages`
- Pakiet zostanie doinstalowany automatycznie przez `oracle-database-preinstall-23ai` w `%post` (jako zależność, po włączeniu repo online)

---

### FIX-008 — 01_network_addressing.md: słabe odwołania do skryptów automatyzujących

**Problem:** Skrypt `setup_dns_infra01.sh` był wspomniany tylko w aneksie na końcu pliku. Sekcja 3.5 (instalacja bind9) pokazywała tylko kroki ręczne — czytelnik nie wiedział, że jest gotowy skrypt. Dla NTP nie było żadnego skryptu.

**Poprawka:**
- `01_network_addressing.md` sekcja 3.5 — dodano prominentny blok **⚡ Metoda AUTOMATYCZNA** odwołujący się do `scripts/setup_dns_infra01.sh` **przed** blokiem ręcznym
- `01_network_addressing.md` sekcja 6 — dodano prominentny blok **⚡ Metoda AUTOMATYCZNA** z `scripts/setup_chrony.sh --role=server|client`
- Aneks na końcu rozszerzony z jednej linijki do tabeli ze wszystkimi skryptami z tego dokumentu + kolejność wykonywania
- Nowy skrypt: `scripts/setup_chrony.sh` z parametrem `--role=server|client`
- `scripts/README.md` zaktualizowany o `setup_chrony.sh` w tabeli i w sekcji "Typowa kolejność uruchamiania"

---

## 2026-04-24 (kontynuacja) — Cross-check i masowe uzupełnienie

### FIX-009 — KRYTYCZNE: `04_os_preparation.md` niespójność UID z kickstartami i `00_architecture.md`

**Problem:** Dokument 04 opisywał że `preinstall-23ai` tworzy `oracle` z UID=54321, a my potem ręcznie dodajemy `grid` z UID=54322. Ale:
- `00_architecture.md` Sekcja 5.2 mówi: `grid` UID=54321, `oracle` UID=54322
- Kickstarty (`ks-prim01.cfg`, `ks-prim02.cfg`, `ks-stby01.cfg`) tworzą dokładnie tak: `grid` 54321, `oracle` 54322

Czyli dokument 04 miał **odwróconą konwencję UID** względem architektury i kickstartów. Osoba idąca wg dokumentu 04 kończyła z `oracle=54321` zamiast 54322 — kolizja z `grid=54321` po kickstarcie.

**Poprawka:** `04_os_preparation.md`
- Sekcja 1.2 — przerobiona na pokazanie **docelowych** UID (grid=54321, oracle=54322 — zgodnie z architekturą), z wyjaśnieniem że UID usera i GID grupy o tej samej wartości to **osobne namespace'y** w Linuksie (nie kolizja)
- Sekcja 2 dostała jasną dyrektywę: "**jeśli używałeś kickstartów — przeskocz do sekcji 3**" (bo wszystko już jest)
- Dodana sekcja 2.1 (ręczna) z prawidłowym `useradd -u 54321 ... grid` + komentarzem jak zmienić `oracle` na 54322 jeśli preinstall dał 54321
- Usunięty niespójny komentarz "UID 54322 jest normalnie dla oracle w starszych preinstall" (mylący w kontekście naszego lab)

---

### FIX-010 — KRYTYCZNE: FRA size niespójna między `dbca_prim.rsp` a `08_database_create_primary.md`

**Problem:** `dbca_prim.rsp` miał `recoveryAreaSize=10240` (10 GB), ale `08_database_create_primary.md` w sekcji post-create zmieniał `db_recovery_file_dest_size` na 15G przez `ALTER SYSTEM`. Bez uzasadnienia. Przy SYNC transport + flashback + RMAN 10 GB szybko się przepełniało.

**Poprawka:** `response_files/dbca_prim.rsp`
- `recoveryAreaSize=15360` (15 GB) — spójne z ALTER SYSTEM w dokumencie 08
- Dodany komentarz wyjaśniający dlaczego 15 GB (archivelog SYNC + flashback + RMAN backup)

---

### FIX-011 — Firewall ONS port 6200 brakuje w `04_os_preparation.md` i `12_tac_service.md`

**Problem:** Port 6200/tcp (ONS — Oracle Notification Service) jest krytyczny dla TAC — bez niego UCP klient nie dostaje FAN events po failover i nie wykonuje replay. Był tylko w `01_network_addressing.md` sekcja 5.2 i implicit w skrypcie `deploy_tac_service.sh`, ale nigdzie wyraźnie zaznaczony w dokumentach 04 i 12 jako "MUSISZ OTWORZYĆ TEN PORT".

**Poprawka:**
- `04_os_preparation.md` — nowa sekcja 4.4 "Porty do otwarcia w firewalld" z tabelą wszystkich portów lab (SSH, 1521, 1522, **6200 wyboldowane**, 5500, 53, 123, 3260)
- `12_tac_service.md` — blok ⚡ AUTOMATYCZNA zawiera wymaganie portu 6200 z wyjaśnieniem konsekwencji (brak replay TAC)

---

### FIX-012 — STRUKTURALNE: wszystkie skrypty w `scripts/` były "sierotami dokumentacyjnymi"

**Problem (zidentyfikowany w cross-check audit):** Żaden z 14 skryptów w `scripts/` (poza `setup_dns_infra01.sh` i `setup_chrony.sh` — FIX-008) nie miał prominentnej referencji w głównych dokumentach 00–16. Czytelnik dokumentu np. 06_grid_infrastructure_install.md nie wiedział że istnieje `install_grid_silent.sh` — wykonywał wszystko ręcznie. Skrypty były udokumentowane tylko w `scripts/README.md` (sekcja schowana).

**Poprawka:** Dodano blok **⚡ Metoda AUTOMATYCZNA** na początku każdego z dokumentów (zaraz po Prereq):
- `04_os_preparation.md` → `prepare_host.sh --role=rac|si|infra|client`
- `05_shared_storage_iscsi.md` → `setup_iscsi_target_infra01.sh` + `setup_iscsi_initiator_prim.sh prim01|prim02`
- `06_grid_infrastructure_install.md` → `install_grid_silent.sh` (z ostrzeżeniem o `root.sh` ręcznie sekwencyjnie)
- `07_database_software_install.md` → `install_db_silent.sh` (RAC + SI)
- `08_database_create_primary.md` → `create_primary.sh`
- `09_standby_duplicate.md` → `duplicate_standby.sh`
- `10_data_guard_broker.md` → `configure_broker.sh`
- `11_fsfo_observer.md` → `setup_observer_infra01.sh`
- `12_tac_service.md` → `deploy_tac_service.sh`
- `14_test_scenarios.md` → `validate_env.sh` (readiness check przed scenariuszami)

Każdy blok zawiera: (1) komendę `bash .../script.sh` z kontekstem (jako kto/na której VM), (2) opis co skrypt robi, (3) weryfikację, (4) wskazanie kroków ręcznych które **pozostają** (jak SSH equivalency, profile, root.sh).

---

### FIX-013 — SEMANTYCZNE: uzupełnienie 5 luk w wiedzy MAA

**Problem:** Kilka krytycznych mechanizmów Oracle MAA nie było wyjaśnionych, przez co osoba z podstawową wiedzą Oracle nie wiedziała **dlaczego** robimy daną rzecz.

**Poprawki (wbudowane w bloki ⚡ lub osobne notatki):**

1. **SRL count per thread w RAC** (`08_database_create_primary.md`):
   Dodana notatka ⚠ wyjaśniająca że dla 2-thread RAC z 3 ORL per thread potrzeba **8 SRL razem** (4 × 2), nie 4. Częsty błąd przy ręcznym ADD STANDBY LOGFILE.

2. **AFFIRM weryfikacja** (`10_data_guard_broker.md`):
   W bloku ⚡ dodany SQL check `SELECT affirm FROM v$archive_dest WHERE dest_id=2;` — broker ustawia AFFIRM automatycznie dla SYNC, ale warto to zweryfikować przed włączeniem FSFO.

3. **Broker config file SINGLE per database** (`10_data_guard_broker.md`):
   W opisie skryptu `configure_broker.sh` dodane wyjaśnienie że `dg_broker_config_file1/2` to **jeden plik per database** (nie per instance na RAC) — na RAC zapisujemy na `+DATA` (shared), na SI na filesystem.

4. **Threshold vs LagLimit semantyka** (`11_fsfo_observer.md`):
   W bloku ⚡ pełne wyjaśnienie różnicy:
   - Threshold = czekanie na heartbeat przed failover
   - LagLimit = max. apply lag tolerowany przed failover
   Plus rekomendacja że oba 30s to baseline dla SYNC; dla ASYNC LagLimit powinien być 300s+.

5. **root.sh sekwencyjnie na obu RAC nodach** (`06_grid_infrastructure_install.md`):
   W bloku ⚡ **jasne ostrzeżenie**: najpierw **pełen `root.sh` na prim01**, dopiero potem na prim02. Można przez `ssh -t root@prim02 '...'` (z TTY), ale **nie równolegle** — CRS na prim01 musi być aktywny zanim prim02 dołączy do klastra.

---

### FIX-014 — kickstart: `--nodefroute` na interfejsie NAT blokuje internet

**Problem:** W kickstartach (wszystkich 5) ustawiłem wcześniej `--nodefroute` na interfejsie NAT (enp0s10 dla prim/infra, enp0s8 dla stby/client). To powodowało że VM po instalacji **nie miała default route do internetu** — `dnf` próbuje sięgnąć `yum.oracle.com`, DNS rozwiązuje (fallback 8.8.8.8), ale pakiet IP nie dociera.

**Objaw na infra01 przy pierwszym `dnf install bind`:**
```
Curl error (6): Couldn't resolve host name for https://yum.oracle.com/...
Could not resolve host: yum.oracle.com
```
Mimo że `/etc/resolv.conf` miał `8.8.8.8` — bo zapytanie DNS wychodzi przez jakiś interfejs, a bez default route Linux nie wie którym.

**Przyczyna:** `--nodefroute` uniemożliwia instalację default route przez DHCP NAT. Host-only (enp0s3) też nie miał gateway (zrobione celowo bo 192.168.56.1 to Windows, nie router). Efekt: brak default route = brak internetu.

**Poprawka:** Wszystkie 5 kickstartów `kickstart/ks-*.cfg`
- Usunięte `--nodefroute` z dyrektywy `network` dla interfejsu NAT
- Dodany komentarz wyjaśniający dlaczego NAT musi instalować default route
- Host-only (enp0s3), priv (enp0s8) i storage (enp0s9) pozostają bez `--gateway` — te sieci są link-local (direct connected), nie potrzebują routera

**Fix na uruchomionej VM** (dla tych które już zainstalowały):
```bash
# 1. Zidentyfikuj subnet NAT i gateway:
ip -4 addr show enp0s10                # lub enp0s8 dla stby/client
# Zapisz subnet, np. 10.0.5.0/24 -> gateway = 10.0.5.2
# (VirtualBox NAT nadaje per-VM subnet 10.0.X.0/24; gateway zawsze na .2)

# 2. Dodaj default route przez prawdziwy gateway:
sudo ip route add default via 10.0.X.2 dev enp0s10   # podstaw X (np. 5)

# 3. Trwale przez NetworkManager (nazwa connection to "System enp0sNN"):
sudo nmcli connection modify "System enp0s10" ipv4.never-default no
sudo nmcli connection modify "System enp0s10" ipv4.ignore-auto-routes no
sudo nmcli connection down "System enp0s10" && sudo nmcli connection up "System enp0s10"
```

---

### FIX-015 — VirtualBox NAT subnet może być inny niż domyślny `10.0.2.0/24`

**Problem:** Dokumentacja i komentarze w kickstartach zakładały że VirtualBox NAT daje `10.0.2.0/24` z gateway `10.0.2.2`. W praktyce VirtualBox przydziela **per-VM** subnet `10.0.X.0/24` gdzie `X` może być inne (u testera: `10.0.5.0/24` → gateway `10.0.5.2`). Przyczyna: konfiguracja VBox na hoście (stara konfiguracja, `--natnet` ustawiony wcześniej, albo VBox w nowszej wersji).

**Objaw:** `sudo ip route add default via 10.0.2.2 dev enp0s10` → `Error: Nexthop has invalid gateway` (bo 10.0.2.2 nie jest na żadnym przyłączonym subnecie VM).

**Regula:** Gateway VirtualBox NAT = **`.2` lokalnego subnetu VM**. Sprawdzenie: `ip -4 addr show enp0s10` → weź pierwsze 3 oktety IP + `.2`.

**Poprawka:**
- `03_os_install_ol810.md` — sekcja 3.1 "Dlaczego inst.ip..." przerobiona na ogólną `10.0.X.2` z tipem jak sprawdzić subnet
- `kickstart/ks-infra01.cfg` — komentarz o NAT gateway zaktualizowany na ogólny `10.0.X.2`
- FIX-014 (poprzedni wpis) zaktualizowany: komendy fix używają placeholdera `10.0.X.2` z instrukcją jak znaleźć X

---

### FIX-016a — `ks-infra01.cfg` i `setup_dns_infra01.sh` nie rozwiązywały własnego problemu DNS

**Problem:** Kickstart infra01 ustawił `--nameserver=127.0.0.1,8.8.8.8` dla host-only, ale po aktywacji NAT DHCP nadpisał resolv.conf adresem LAN routera (192.168.1.1) na PIERWSZE miejsce. Skrypt `setup_dns_infra01.sh` testował przez `dig @192.168.56.10` (bezpośrednio do bind9), więc nie wykrywał że systemowy resolver zachowuje się inaczej. Objaw: `nslookup scan-prim.lab.local` bez `@` → `NXDOMAIN`, mimo że bind9 działa.

**Poprawka:**
- `scripts/setup_dns_infra01.sh` — dodane na końcu: `nmcli ignore-auto-dns yes` dla NAT + `dns=127.0.0.1` dla host-only + restart połączeń. Plus weryfikacja przez systemowy `nslookup` (nie tylko `dig @...`).
- `kickstart/ks-infra01.cfg` — analogiczny fragment w `%post` (dla nowych instalacji).

---

### FIX-016 — DHCP NAT nadpisuje DNS adresem LAN routera zamiast infra01

**Problem:** Po naprawie default route (FIX-014/FIX-015) DHCP NAT propagował upstream DNS z LAN routera użytkownika (np. `192.168.1.1` — Orange Światłowód) do `/etc/resolv.conf` na **pierwsze miejsce**, **nadpisując** statyczny `192.168.56.10` z kickstarta. Efekt: `nslookup scan-prim.lab.local` → `NXDOMAIN` (bo router LAN nie zna strefy `lab.local`).

Na `infra01` to nie bolało — bo kickstart miał `--nameserver=127.0.0.1,8.8.8.8` i `127.0.0.1` (lokalny bind9) było pierwsze. Ale na `prim01`/`prim02`/`stby01`/`client01` statyczny `192.168.56.10` został zepchnięty za `192.168.1.1`.

**Przyczyna:** NetworkManager domyślnie akceptuje DNS z DHCP (`ipv4.ignore-auto-dns=no`). Gdy DHCP NAT aktywował się z default route, jego DNS "wygrał" kolejność.

**Poprawka:**

1. **Kickstarty** (`ks-prim01.cfg`, `ks-prim02.cfg`, `ks-stby01.cfg`, `ks-client01.cfg`) — dodano w `%post` sekwencję `nmcli`:
   ```
   nmcli connection modify "System <NAT_IFACE>" ipv4.ignore-auto-dns yes
   nmcli connection modify "System enp0s3" ipv4.dns "192.168.56.10"
   nmcli connection modify "System enp0s3" ipv4.dns-search "lab.local"
   nmcli connection modify "System enp0s3" ipv4.ignore-auto-dns yes
   ```
   Interfejs NAT: `enp0s10` dla prim01/prim02, `enp0s8` dla stby01/client01.
   (`ks-infra01.cfg` ma inne DNS — `127.0.0.1,8.8.8.8` — i nie wymaga zmiany, bo 127.0.0.1 jest pierwszy.)

2. **`scripts/setup_chrony.sh --role=client`** — auto-fix DNS dodany przed preflight. Skrypt sam wymusza prawidłowy DNS zanim spróbuje połączyć się z `infra01.lab.local` przez chrony. Wykrywa aktywny interfejs NAT (enp0s10 lub enp0s8) i modyfikuje tylko ten, który istnieje.

**Fix na uruchomionej VM** (dla już zainstalowanych prim01/prim02/stby01/client01 — przed uruchomieniem `setup_chrony.sh --role=client`):
```bash
# prim01/prim02 (NAT = enp0s10):
nmcli connection modify "System enp0s10" ipv4.ignore-auto-dns yes
nmcli connection modify "System enp0s3" ipv4.dns "192.168.56.10"
nmcli connection modify "System enp0s3" ipv4.dns-search "lab.local"
nmcli connection modify "System enp0s3" ipv4.ignore-auto-dns yes
nmcli connection down "System enp0s10" && nmcli connection up "System enp0s10"
nmcli connection down "System enp0s3"  && nmcli connection up "System enp0s3"

# stby01/client01 (NAT = enp0s8): podstaw enp0s8 zamiast enp0s10
```

Weryfikacja: `cat /etc/resolv.conf` → musi pokazać `nameserver 192.168.56.10` jako jedyny (lub pierwszy).

---

### FIX-017 — OL8 ma pakiet `targetcli`, nie `targetcli-fb`

**Problem:** Skrypt `setup_iscsi_target_infra01.sh` oraz dokumentacja używały nazwy `targetcli-fb` (Fedora-style). Na Oracle Linux 8 pakiet nazywa się po prostu `targetcli`.

**Objaw:** `dnf install -y targetcli-fb` → `No match for argument: targetcli-fb`

**Poprawka:**
- `scripts/setup_iscsi_target_infra01.sh` linia 57 — `targetcli-fb target-restore` → `targetcli`
- `05_shared_storage_iscsi.md` linie 84, 469, 472 — to samo
- `00_architecture.md` linia 44 — lista zainstalowanych pakietów

**Bonus:** dodany diagram topologii w `05_shared_storage_iscsi.md` sekcja 0 (ASCII: infra01 → LIO → 5 LUN → iSCSI 3260 → prim01/prim02 → `/dev/oracleasm/...`) — z wyjaśnieniem shared storage i alternatywy produkcyjnej.

---

### FIX-018 — udev rules dla iSCSI LIO: `ID_SERIAL` nie zawiera nazwy backstore

**Problem:** Skrypt `setup_iscsi_initiator_prim.sh` używał reguł udev z pattern `ENV{ID_SERIAL}=="*ocr1*"` zakładając że LIO generuje `ID_SERIAL` zawierający nazwę backstore (`lun_ocr1`). **Fałszywe założenie** — LIO generuje losowe 32-znakowe hex-y (np. `360014057d91cd990bb3472f8b6d6acbd`). Reguły nie pasowały → brak symlinków `/dev/oracleasm/OCR1/...`.

**Objaw na prim01:**
```
/dev/sdb LUN=0 serial=360014057d91cd990bb3472f8b6d6acbd
# udev rule: ENV{ID_SERIAL}=="*ocr1*"   ← NIE MATCHUJE
# Wynik: /dev/oracleasm/OCR1 nie istnieje
```

**Rozwiązanie:** Mapowanie po **SCSI LUN#** zamiast po pattern na nazwie. Target LIO na infra01 ma stałe przypisanie:
- LUN 0 → lun_ocr1
- LUN 1 → lun_ocr2
- LUN 2 → lun_ocr3
- LUN 3 → lun_data1
- LUN 4 → lun_reco1

Skrypt czyta `/sys/block/sdX/device/scsi_device/` → wyciąga LUN# → generuje udev rule z konkretnym `ID_SERIAL` (odczytanym przez `/usr/lib/udev/scsi_id`).

**Poprawka:** `scripts/setup_iscsi_initiator_prim.sh` — sekcja 9 (tworzenie udev rules) przepisana z patternów nazwy na dynamiczne mapowanie LUN# → ID_SERIAL → symlink. Wygenerowany plik `/etc/udev/rules.d/99-oracleasm.rules` ma teraz konkretne stringi ID_SERIAL, nie `*ocr1*`.

**Konsekwencja dla user'a:** `ID_SERIAL` każdego LUN-u jest **identyczny z prim01 i prim02** (bo to ten sam fizyczny LUN w iSCSI). Można wygenerować rules raz na prim01 i `scp` na prim02 — albo uruchomić skrypt po obu stronach (oba dadzą ten sam plik).

---

### FIX-019 — Shared folder `OracleBinaries` nie był auto-tworzony/auto-montowany

**Problem:** Stary `vbox_create_vms.ps1` miał warunek `if (Test-Path "D:\OracleBinaries")` — jeśli katalog nie istniał na hoście w momencie tworzenia VM, shared folder w ogóle nie był dodawany. Dodatkowo kickstarty nie miały wpisu fstab dla tego share'a (tylko dla `_RMAN_BCK_from_Linux_`). Efekt: `/media/sf_OracleBinaries/` i `/mnt/oracle_binaries` nie istniały — nie było gdzie wgrać binarek Oracle.

**Poprawka:**

1. `scripts/vbox_create_vms.ps1` — shared folder OracleBinaries jest **zawsze** dodawany:
   - Jeśli `D:\OracleBinaries` nie istnieje → tworzy go (pusty)
   - Dodaje przez `VBoxManage sharedfolder add --automount`
   - Dodatkowo `_RMAN_BCK_from_Linux_` (jeśli istnieje)

2. Kickstarty `ks-*.cfg` (wszystkie 5) — w `%post` dodany wpis fstab:
   ```
   OracleBinaries  /mnt/oracle_binaries  vboxsf  rw,uid=<UID>,gid=<GID>,dmode=775,fmode=664,nofail  0  0
   ```
   Owner:
   - prim01/prim02/stby01/infra01 → `oracle:oinstall` (54322:54321)
   - client01 → `kris:kris` (1000:1000)

**Fix dla już uruchomionych VM (user musi wykonać ręcznie):**
```powershell
# Windows PowerShell (shutdown + add shared folder + start)
New-Item -ItemType Directory -Path "D:\OracleBinaries" -Force
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
foreach ($vm in "prim01","prim02","stby01","infra01","client01") {
    & $VBox controlvm $vm acpipowerbutton
    # Poczekaj na shutdown
    & $VBox sharedfolder add $vm --name "OracleBinaries" --hostpath "D:\OracleBinaries" --automount
    & $VBox startvm $vm --type headless
}
```

Na każdej VM (po restarcie, jako root):
```bash
mkdir -p /mnt/oracle_binaries
echo "OracleBinaries  /mnt/oracle_binaries  vboxsf  rw,uid=54322,gid=54321,dmode=775,fmode=664,nofail  0  0" >> /etc/fstab
mount /mnt/oracle_binaries
```

---

### FIX-020 — `prepare_host.sh` nie ustawiał limits dla usera `grid` → cluvfy FAILED

**Problem:** `oracle-database-preinstall-23ai` RPM ustawia `/etc/security/limits.d/oracle-database-preinstall-23ai.conf` **tylko dla usera `oracle`**. User `grid` (Role Separation dla Grid Infrastructure) nie ma żadnych limits — `ulimit -s` pokazuje OS default 8192 (wymagane 10240), `ulimit -Hl` = 64K (wymagane 128 MB).

**Objaw:** `runcluvfy.sh stage -pre crsinst` zwraca:
- `PRVG-0449 : Proper soft limit for maximum stack size was not found [Expected >= "10240" ; Found = "8192"]`
- `PRVE-0059 : no default entry or entry specific to user "grid" was found in the configuration file "/etc/security/limits.conf" when checking the maximum locked memory "HARD" limit`

**Poprawka:** `scripts/prepare_host.sh` — w sekcji "Preinstall RPM (dla rac/si)" dodany blok tworzący `/etc/security/limits.d/99-grid-oracle.conf` z limitami dla `grid` (nofile, nproc, stack, memlock) oraz uzupełnieniem stack/memlock dla `oracle`.

Dokument `04_os_preparation.md` sekcja 3 MIAŁ ten fragment w instrukcjach ręcznych, ale blok ⚡ AUTOMATYCZNA nie zaznaczał wyraźnie że to ręczny krok — dodane w FIX-012, teraz prepare_host.sh to robi automatycznie.

**Fix dla już uruchomionych VM (prim01, prim02):**
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
# Po tym WYLOGUJ sie i zaloguj ponownie, potem:
su - grid -c "ulimit -s"  # 10240
```

---

### FIX-021 — `runcluvfy.sh` widzi interfejs NAT jako cluster network (fałszywy FAILED)

**Problem:** Wszystkie VM w VirtualBox NAT mają **ten sam IP DHCP** (np. `10.0.5.15`) — bo NAT jest per-VM izolowany. Cluvfy nie wie o tym, testuje TCP connectivity między `10.0.5.15 → 10.0.5.15` (self-loopback) i uznaje za FAILED. Do tego IPv6 link-local między VM też nie routuje się w NAT.

**Objaw:**
```
PRVG-1172 : The IP address "10.0.5.15" is on multiple interfaces "enp0s10" on nodes "prim01,prim02"
PRVG-11067 : TCP connectivity from node "prim02": "10.0.5.15" to node "prim01": "10.0.5.15" failed
```

**Poprawka:** użyj parametru `-networks` w `runcluvfy.sh` żeby jawnie wskazać które interfejsy są public/cluster_interconnect, a enp0s10 (NAT) pomiń.

**UWAGA — składnia `-networks` w cluvfy 26ai:**
- Separator między interfejsami: **`/`** (slash), NIE `,` (comma)
- Typy: **małe litery** (`public`, `cluster_interconnect`, `asm`)
- Subnet bez maski (`192.168.56.0`, NIE `192.168.56.0/24`)

Pierwsza próba ze składnią z comma+UPPERCASE zwróciła `PRVG-11089 : Could not find a valid network entry`:
```bash
# ŹLE (to nie działa):
-networks enp0s3:192.168.56.0:PUBLIC,enp0s8:192.168.100.0:cluster_interconnect
```

Poprawna składnia:
```bash
# OK:
./runcluvfy.sh stage -pre crsinst -n prim01,prim02 \
    -networks "enp0s3:192.168.56.0:public/enp0s8:192.168.100.0:cluster_interconnect" \
    -verbose
```

**Aktualizacja `06_grid_infrastructure_install.md`** sekcja 4 — używa prawidłowej składni.

---

### FIX-022 — Physical Memory warning 8GB (kosmetyczny w lab)

**Problem:** cluvfy wymaga 8 GB physical memory, prim01/prim02 dostały 8 GB RAM, ale Linux reportuje ~7.8 GB po odjęciu kernel/firmware. Cluvfy zaznacza jako FAILED.

**Poprawka:** **ignorować** — podczas `gridSetup.sh -silent` użyć flagi `-ignorePrereq` lub wskazać w response file `oracle.install.option=... ignoreSysPrereqs=true`. Alternatywnie dostawić RAM do 9 GB w VirtualBox.

---

## 2026-04-25

### FIX-023 — `grid.rsp`: nieprawidłowy parametr `oracle.install.crs.config.gimrSA` (schema 19c vs 26ai)

**Problem:** Response file dla 23.26.1 zawierał parametr `oracle.install.crs.config.gimrSA=false` z linii pisanej dla 19c. W Oracle 26ai schema response file (`rspfmt_crsinstall_response_schema_v23.0.0`) ten parametr nie istnieje — GIMR/MGMTDB został w 26ai usunięty.

**Objaw:**
```
[FATAL] [INS-10105] The given response file /home/grid/grid.rsp is not valid.
   CAUSE: Syntactically incorrect response file.
   SUMMARY:
       - cvc-complex-type.2.4.a: Invalid content was found starting with element
         'oracle.install.crs.config.gimrSA'. One of '{ ... configureBackupDG,
         oracle.install.asm.configureGIMRDataDG, ...}' is expected.
```

**Poprawka:** `response_files/grid.rsp` (linia 122-124)
```diff
- # GIMR (Grid Infrastructure Management Repository) - wylaczamy dla oszczednosci
- oracle.install.crs.config.gimrSA=false
+ # GIMR Data DG (osobny disk group dla MGMTDB) - w 26ai nie uzywamy, MGMTDB usuniety w 26ai
+ # UWAGA: w 26ai parametr nazywa sie 'configureGIMRDataDG' (a nie 'gimrSA' jak w 19c)
+ oracle.install.asm.configureGIMRDataDG=false
```

**Fix dla uruchomionych VM (na prim01 jako grid):**
```bash
sed -i 's|^oracle.install.crs.config.gimrSA=false|oracle.install.asm.configureGIMRDataDG=false|' /home/grid/grid.rsp
grep -E "configureGIMRDataDG|gimrSA" /home/grid/grid.rsp
```

**Uwaga na przyszłość:** Walidator `gridSetup.sh -silent` zatrzymuje się na **pierwszym** błędzie XML schema. Jeśli pojawią się kolejne komunikaty o innych parametrach 19c → patrz FIX-024 (kompletne przepisanie response file).

---

### FIX-024 — `grid.rsp`: kompletne przepisanie z 19c-style na 26ai short names (schema 23.0.0)

**Problem:** Po naprawie `gimrSA` (FIX-023) walidator wyrzucał kolejne `[FATAL] [INS-10105]` na każdym parametrze "deprecated" form (`oracle.install.option`, `oracle.install.crs.config.ClusterConfiguration`, `oracle.install.crs.config.gpnp.scanName`, ...). Schema response file 23.0.0 (`/oracle/install/rspfmt_crsinstall_response_schema_v23.0.0`) wymaga **NEW short names** zgodnie z template'em `/u01/app/23.26/grid/install/response/gridsetup.rsp` z instalatora 26ai (komentarze `Deprecated:` w template'cie listują stare nazwy).

**Objawy (kolejne fatale):**
```
[FATAL] [INS-10105] Invalid content was found starting with element
'oracle.install.crs.config.ClusterConfiguration'. One of '{installOption,
oracle.install.crs.config.clusterUsage, clusterUsage, ...}' is expected.
```

**Mapping stary→nowy (kluczowe parametry):**

| Stara nazwa (deprecated) | Nowa nazwa (26ai) | Uwagi |
|--------------------------|-------------------|-------|
| `oracle.install.option=CRS_CONFIG` | `installOption=CRS_CONFIG` | |
| `oracle.install.crs.config.ClusterConfiguration=STANDALONE` | **USUNIĘTE** + `clusterUsage=RAC` | DSC/Domain Services usunięte w 23ai/26ai |
| `oracle.install.crs.config.gpnp.configureGNS` | `configureGNS` | |
| `oracle.install.crs.config.autoConfigureClusterNodeVIP` | `configureDHCPAssignedVIPs` | |
| `oracle.install.crs.config.clusterName` | `clusterName` | |
| `oracle.install.crs.config.gpnp.scanName/scanPort` | `scanName / scanPort` | |
| `oracle.install.crs.config.clusterNodes=prim01:prim01-vip:HUB,...` | `clusterNodes=prim01:prim01-vip,prim02:prim02-vip` | **BEZ `:HUB`** — HUB/LEAF zniesione w 23ai |
| `oracle.install.crs.config.networkInterfaceList` | `networkInterfaceList` | |
| `oracle.install.crs.config.storageOption` | `storageOption` | wartość `FLEX_ASM_STORAGE` nadal OK |
| `oracle.install.asm.SYSASMPassword` | `sysasmPassword` | |
| `oracle.install.asm.monitorPassword` | `asmsnmpPassword` | |
| `oracle.install.asm.diskGroup.name` | `diskGroupName` | |
| `oracle.install.asm.diskGroup.redundancy/AUSize/disks` | `redundancy / auSize / diskList` | |
| `oracle.install.asm.diskGroup.diskDiscoveryString` | `diskString` | |
| `oracle.install.asm.gimrDG.AUSize` | **USUNIĘTE** | GIMR/MGMTDB usunięte |
| `oracle.install.asm.OSDBA/OSOPER/OSASM` | `OSDBA / OSOPER / OSASM` | |
| `oracle.install.asm.configureGIMRDataDG=false` | `configureBackupDG=false` | OCR backup DG (osobny od GIMR) |
| `oracle.install.crs.config.useIPMI` | `useIPMI` | |
| `oracle.install.crs.rootconfig.executeRootScript` | `executeRootScript` | |

**Dodane parametry (jawnie):**
- `scanType=LOCAL_SCAN` (mamy DNS na infra01, nie SHARED_SCAN z innego klastra)
- `clusterUsage=RAC` (zamiast deprecated `ClusterConfiguration=STANDALONE`)
- `managementOption=NONE` (brak Cloud Control)
- `configureBackupDG=false` (zamiast `configureGIMRDataDG=false`)
- `enableAutoFixup=false` (cluvfy nie poprawia automatycznie)
- `INVENTORY_LOCATION=/u01/app/oraInventory` (jawnie)

**Poprawka:** `response_files/grid.rsp` (v1.0 → v2.0) + nowy plik `response_files/grid_minimal.rsp` (62 linie, bez komentarzy — gotowy do `cp` na VMkę).

**Fix dla uruchomionych VM (prim01):**
```bash
cp /home/grid/grid.rsp /home/grid/grid.rsp.bak_v1
cp /media/sf_OracleBinaries/grid.rsp /home/grid/grid.rsp
# lub: cp /media/sf_OracleBinaries/grid_minimal.rsp /home/grid/grid.rsp
```

**Walidacja sukcesu (2026-04-25 08:11):**
```
Launching Oracle Grid Infrastructure Setup Wizard...
[WARNING] [INS-40109] The specified Oracle base location is not empty   ← OK
[WARNING] [INS-13013] Target environment does not meet some mandatory   ← OK z -ignorePrereqFailure
INFO: Copying /u01/app/23.26/grid to remote nodes [prim02]              ← faza kopiowania binarek
```

**Lekcja:** Przy migracji response files między major releases Oracle (19c → 26ai) **nie zamieniaj parametrów po jednym** — zatrzymujący się na pierwszym błędzie parser to droga przez mękę. Generuj template z instalatora (`cat $ORACLE_HOME/install/response/gridsetup.rsp`), zmapuj wszystkie wartości, podmień całość.

---

### FIX-025 — `db.rsp`: deprecated 19c-style → 26ai short names + `managementOption=DEFAULT` (nie `NONE`)

**Problem:** Identyczny vector ataku jak FIX-024, tym razem `db.rsp` przy `runInstaller -silent`. Dodatkowo: w **db schema** 23.0.0 (`rspfmt_dbinstall_response_schema_v23.0.0`) wartość `NONE` dla `managementOption` jest niepoprawna — różnica vs grid schema gdzie `NONE` było OK.

**Objaw 1 (deprecated names):** `[FATAL] [INS-10105]` na każdym z parametrów `oracle.install.option`, `oracle.install.db.InstallEdition`, `oracle.install.db.OSDBA_GROUP`, ...

**Objaw 2 (managementOption):**
```
[FATAL] [INS-10105] The given response file /home/oracle/db.rsp is not valid.
   SUMMARY:
       - cvc-enumeration-valid: Value 'NONE' is not facet-valid with respect to
         enumeration '[CLOUD_CONTROL, DEFAULT]'. It must be a value from the enumeration.
       - cvc-type.3.1.3: The value 'NONE' of element 'managementOption' is not valid.
```

**Mapping stary→nowy (`db.rsp` v1 → v2):**

| Stara nazwa (deprecated) | Nowa nazwa (26ai) | Uwagi |
|--------------------------|-------------------|-------|
| `oracle.install.option=INSTALL_DB_SWONLY` | `installOption=INSTALL_DB_SWONLY` | |
| `oracle.install.db.InstallEdition=EE` | `installEdition=EE` | |
| `oracle.install.db.OSDBA_GROUP=dba` | `OSDBA=dba` | |
| `oracle.install.db.OSOPER_GROUP=oper` | `OSOPER=oper` | |
| `oracle.install.db.OSBACKUPDBA_GROUP=backupdba` | `OSBACKUPDBA=backupdba` | |
| `oracle.install.db.OSDGDBA_GROUP=dgdba` | `OSDGDBA=dgdba` | |
| `oracle.install.db.OSKMDBA_GROUP=kmdba` | `OSKMDBA=kmdba` | |
| `oracle.install.db.OSRACDBA_GROUP=racdba` | `OSRACDBA=racdba` | |
| `oracle.install.db.CLUSTER_NODES=prim01,prim02` | `clusterNodes=prim01,prim02` | |
| `oracle.install.db.isRACOneInstall=false` | **USUNIĘTE** | nie ma w schema 23.0.0 |
| `oracle.install.db.config.starterdb.*` | **USUNIĘTE** + nowe `dbType, gdbName, dbSID, ...` | dla SWONLY puste |
| `DECLINE_SECURITY_UPDATES, SECURITY_UPDATES_VIA_MYORACLESUPPORT` | **USUNIĘTE** | nie ma w schema 23.0.0 |
| (brak) | `managementOption=DEFAULT` | **WAŻNE:** `NONE` NIE działa, musi być `DEFAULT` lub `CLOUD_CONTROL` |

**Poprawka:** `response_files/db.rsp` (v1.0 → v2.0) + `response_files/db_minimal.rsp` (40 linii bez komentarzy).

**Fix dla uruchomionych VM:**
```bash
# Wariant A - skopiuj nowy plik
cp /mnt/oracle_binaries/db.rsp /home/oracle/db.rsp
chmod 600 /home/oracle/db.rsp

# Wariant B - hot-fix tylko managementOption (gdy stara wersja juz na VM)
sed -i 's|^managementOption=NONE|managementOption=DEFAULT|' /home/oracle/db.rsp
```

**Lekcja:** Schemy DB i Grid w 23.0.0 są **różne**, mimo wspólnej wersji 23.0.0. Nie zakładaj że valid value w grid schema (np. `managementOption=NONE`) jest valid w db schema. Gdy parser krzyczy `cvc-enumeration-valid`, lista dozwolonych wartości jest w komunikacie `'[VALUE1, VALUE2, ...]'`.

---

### FIX-026 — `db.rsp`: inline komentarze po wartości NIE są wspierane (`OSDBA=dba    # SYSDBA` → FATAL)

**Problem:** W komentowanej wersji `db.rsp` v2.0 (FIX-025) nieświadomie umieszczono **inline komentarze** po wartościach grup OS:
```
OSDBA=dba                # SYSDBA
OSOPER=oper              # SYSOPER
...
```
Parser response file traktuje **całość po `=`** (włącznie z whitespace i `#`) jako wartość parametru — więc `OSDBA=dba                # SYSDBA` znaczy "user oracle musi być w grupie o nazwie `dba                # SYSDBA`", której oczywiście nie ma.

**Objaw:**
```
[FATAL] [INS-35341] The installation user is not a member of the following groups:
[dba                # SYSDBA, backupdba    # SYSBACKUP (RMAN), dgdba            # SYSDG (Data Guard), ...]
```

**Reguła:** Komentarze w response files Oracle muszą być na **osobnych liniach** zaczynając od `#` w kolumnie 1. NIE wolno robić inline `KEY=VALUE # comment`.

**Wyjątek:** `#` w **wartości bez whitespace** (np. `sysasmPassword=Welcome1#ASM`) jest OK — to część stringu, nie komentarz.

**Poprawka:** `response_files/db.rsp` — komentarze przeniesione PRZED definicje grup, sama linia zawiera tylko `KEY=VALUE`.

**Fix dla uruchomionych VM (na prim01 jako oracle):**
```bash
# Wariant A - skopiuj clean db_minimal.rsp ze shared folderu
cp /mnt/oracle_binaries/db_minimal.rsp /home/oracle/db.rsp
chmod 600 /home/oracle/db.rsp

# Wariant B - hot-fix sed (usuwa inline #-komentarze z grup OS)
sed -i -E 's/^(OS[A-Z]*=[a-z]+)[[:space:]]+#.*$/\1/' /home/oracle/db.rsp
grep "^OS" /home/oracle/db.rsp
# Powinno: OSDBA=dba | OSOPER=oper | ... bez nic po wartosci
```

**Uwaga przy pisaniu nowych response files:** parsery Oracle rsp (gridSetup, runInstaller, dbca) **nie trimują whitespace** ani **nie obcinają od `#`**. Cały tail po `=` to wartość. Komentarz tylko jako osobna linia.

---

### FIX-026b — Mass cleanup: `/media/sf_OracleBinaries/` → `/mnt/oracle_binaries/` + nazwy ZIP ze spacją → `_`

**Problem:** Kickstarty mountują shared folder VirtualBox jako `/mnt/oracle_binaries` (z `fmode=664,uid=oracle`), ale **9 plików w projekcie** (MD + skrypty `.sh`) miało zawarte odniesienia do `/media/sf_OracleBinaries/` (domyślny path Guest Additions auto-mount, którego my nie używamy). Dodatkowo nazwa pliku ZIP w eDelivery to `V1054592-...forLinux x86-64.zip` ze **spacją**, ale po pobraniu/skopiowaniu na shared folder została przemianowana z `_` (underscore) — wszystkie wystąpienia w MD + skryptach miały spację, więc komendy `unzip` z dokumentacji NIE działały bez modyfikacji.

**Pliki naprawione (mass replace):**
- MD: `02_virtualbox_setup.md`, `06_grid_infrastructure_install.md`, `07_database_software_install.md`, `11_fsfo_observer.md`, `13_client_ucp_test.md`, `README.md`, `LOG.md`, `PLAN-dzialania.md`
- Skrypty: `scripts/install_db_silent.sh`, `scripts/install_grid_silent.sh`

**Reguła:**
- Shared folder VirtualBox host `D:\OracleBinaries` → mount point w VM: **`/mnt/oracle_binaries`** (zgodnie z fstab w kickstartach)
- Nazwy pliku ZIP: **z `_`** (`forLinux_x86-64.zip`), nie ze spacją

**Lekcja:** zawsze sprawdzaj realny mount point (`mount | grep oracle` lub `/etc/fstab`) i realną nazwę pliku (`ls /mnt/oracle_binaries/`) zanim zaufasz dokumentacji.

---

### FIX-027 — `db_si.rsp`: `OSRACDBA=` (puste) FATAL nawet w Single Instance install + skrypt install_db_silent.sh nieświadomy trybu

**Problem (1/2):** W Oracle 26ai schema `rspfmt_dbinstall_response_schema_v23.0.0` parametr `OSRACDBA` jest **wymagany niezależnie od trybu** (RAC vs SI). Dla Single Instance install na stby01 ustawiliśmy `OSRACDBA=` (puste — funkcjonalnie nieużywane bo nie ma RAC), ale parser walidacyjny nie zaakceptował.

**Objaw:**
```
[FATAL] [INS-35344] The value is not specified for Real Application Cluster
administrative (OSRACDBA) group.
   ACTION: Specify a valid group name for Real Application Cluster
           administrative (OSRACDBA) group.
```

**Poprawka:** `response_files/db_si.rsp` (i `db_si_minimal.rsp`)
```diff
- OSRACDBA=
+ OSRACDBA=dba
```
Wybór `dba`: bezpieczne (grupa istnieje na każdym Oracle host), oracle user nie musi być formalnie członkiem `racdba` na stby01 (nie ma RAC), parser potrzebuje tylko **istniejącej** grupy żeby przejść walidację. Funkcjonalnie nieużywane.

**Fix dla uruchomionych VM (na stby01 jako oracle):**
```bash
sed -i 's|^OSRACDBA=$|OSRACDBA=dba|' /home/oracle/db_si.rsp
grep "^OSRACDBA" /home/oracle/db_si.rsp
```

**Problem (2/2):** Skrypt `install_db_silent.sh` v2.0 zakładał tryb RAC w komunikatach ("kopiowanie na prim02 przez SSH...", "root.sh sekwencyjnie na obu nodach..."). Dla SI install na stby01 te komunikaty były mylące.

**Poprawka:** `scripts/install_db_silent.sh` — dodana detekcja trybu na podstawie `clusterNodes=` w response file:
- `clusterNodes=prim01,prim02` → tryb RAC, ETA 25-40 min, instrukcje root.sh sekwencyjnie
- `clusterNodes=` (puste) → tryb SI, ETA 15-25 min, jeden root.sh lokalnie

**Lekcja:** Schema 23.0.0 wymaga formalnie wszystkich parametrów grup OS, nawet gdy logicznie nieużywane w danym trybie. Jeśli walidator narzeka `INS-35344` na grupę "której nie powinno potrzebować" — wpisz dowolną istniejącą grupę (`dba`/`oinstall`), to nie wpływa funkcjonalnie.

---

## 2026-04-25 (cd.) — DBCA primary

### FIX-028 — `dbca_prim.rsp`: 8 nielegalnych kluczy schema 23.0.0 + brak archivelog conversion

**Problem:** Plik `dbca_prim.rsp` v1.0 zawierał klucze które **nie istnieją** w template `$ORACLE_HOME/assistants/dbca/dbca.rsp` dla 26ai (schema `rspfmt_dbca_response_schema_v23.0.0`). Analogicznie do FIX-024 (grid.rsp) i FIX-025 (db.rsp) — pozostałości z 19c.

**Diff template 26ai vs nasz v1.0 — 8 nielegalnych kluczy:**

| Klucz w v1.0 | Status w schema 23.0.0 | Naprawa w v2.0 |
|---|---|---|
| `createUserTableSpace=true` | ❌ nie istnieje | usunięty |
| `asmSysPassword=Welcome1#ASM` | ❌ template ma `asmsnmpPassword` | `asmsnmpPassword=Welcome1#ASMSNMP` |
| `recoveryAreaSize=15360` | ❌ nie istnieje | przeniesiony do `initParams=...,db_recovery_file_dest_size=15G` |
| `useSameAdminPassword=true` | ❌ nie istnieje | usunięty (sysPassword + systemPassword wystarczają) |
| `memoryMgmtType=AUTO_SGA` | ❌ nie istnieje | usunięty (template ma tylko `totalMemory` + `automaticMemoryManagement`) |
| `enableArchive=true` | ❌ nie istnieje | usunięty → archivelog conversion w `create_primary.sh` post-create |
| `archiveLogMode=true` | ❌ nie istnieje | jw. |
| `archiveLogDest=+RECO` | ❌ nie istnieje | jw. (archivelog idzie do FRA = `+RECO`) |
| `emExpressPort=` | ❌ template ma `emConfiguration` | `emConfiguration=NONE` |

**Brakujące w v1.0 (nowe w 26ai schema 23.0.0), dodane w v2.0:**
- `useLocalUndoForPDBs=true` (zalecane dla CDB w 23ai+)
- `policyManaged=false` (admin-managed RAC)
- `runCVUChecks=FALSE`
- pełny zestaw pustych kluczy z template (DV, OLS, dirService, EM Cloud Control, oracleHomeUserPassword, ...)

**Poprawka 1 — `response_files/dbca_prim.rsp` v2.0:** pełne przepisanie wzorowane na `$ORACLE_HOME/assistants/dbca/dbca.rsp` z 26ai. Zachowane sensowne wartości z v1.0 (gdbName, sid, RAC, ASM disk groups, hasła, characterSet, totalMemory, sampleSchema=false, initParams).

**Poprawka 2 — `scripts/create_primary.sh` v2.0:**
- Pre-flight checks: whoami=oracle, ORACLE_HOME, dbca, RSP exists.
- **Auto-detekcja 8 deprecated kluczy** w response file (analogicznie do `install_db_silent.sh` FIX-027).
- Idempotentnie: `srvctl status database -db PRIM` → skip DBCA jeśli baza już jest.
- **Post-create archivelog conversion** — bo `templateName=General_Purpose.dbc` tworzy bazę w `NOARCHIVELOG`. W RAC sekwencja: `srvctl stop database -db PRIM` → `STARTUP MOUNT` na PRIM1 (samo `cluster_database=true` w 23ai+ pozwala na mount na 1 instancji) → `ALTER DATABASE ARCHIVELOG` → `SHUTDOWN IMMEDIATE` → `srvctl start database -db PRIM`.
- Idempotentne `ALTER DATABASE ADD STANDBY LOGFILE` (`WHENEVER SQLERROR CONTINUE` bo ORA-01515 przy ponownym uruchomieniu).
- Pełen post-create w jednym przebiegu: FORCE_LOGGING (CDB+APPPDB), Flashback, SRL (8 = 4×2 thread), `log_archive_config`, `log_archive_dest_1=USE_DB_RECOVERY_FILE_DEST`, `standby_file_management=AUTO`, `app_user`/`test_log` w APPPDB, `utlrp.sql`, eksport `orapwPRIM` z ASM do `/tmp/pwd/`.

**Objaw oczekiwany dla v1.0 (gdyby uruchomić):**
```
[FATAL] [DBT-XXXXX] Invalid response file parameter: createUserTableSpace
```
lub
```
[FATAL] [DBT-XXXXX] Invalid value for parameter recoveryAreaSize
```

**Fix dla uruchomionych VM:**
```bash
# Na prim01 jako oracle:
cp /tmp/response_files/dbca_prim.rsp /home/oracle/dbca_prim.rsp
chmod 600 /home/oracle/dbca_prim.rsp
bash /tmp/scripts/create_primary.sh
```

**Lekcja:** Dla każdego pliku response w 26ai (`grid.rsp`, `db.rsp`, `db_si.rsp`, **`dbca_prim.rsp`**, w przyszłości `client.rsp`) **najpierw porównać klucze z template instalatora** (`$ORACLE_HOME/.../assistants/.../*.rsp` lub `$ORACLE_HOME/install/response/*.rsp`) zanim się go uruchomi. Schemat 23.0.0 odrzuca każdy nieznany klucz `[FATAL] [DBT-/INS-]`. Dla DBCA szczególnie: `enableArchive` (znane z 19c) **nie istnieje** w schema 23.0.0 — archivelog robi się ręcznie w post-create RAC stop/mount/alter/restart.

---

### FIX-029 — `dbca_prim.rsp`: `db_recovery_file_dest_size=15G` przekracza wolne miejsce na +RECO

**Problem:** Disk group `+RECO` w naszym labie ma 15 GB EXTERN, ale ASM rezerwuje ~140 MB na metadata (header, ACD, COD, freespace). Wolne miejsce dla bazy = 15220 MB. DBCA przy `db_recovery_file_dest_size=15G` (15360 MB) sprawdza `free_mb >= dest_size` i przerywa.

**Objaw:**
```
[FATAL] [DBT-06604] The location specified for 'Fast Recovery Area Location' has insufficient free space.
   CAUSE: Only (15,220MB) free space is available on the location (+RECO/PRIM/).
   ACTION: Choose a 'Fast Recovery Area Location' that has enough space (minimum of (15,360MB)) or free up space on the specified location.
```

**Poprawka:** `response_files/dbca_prim.rsp` — `db_recovery_file_dest_size=15G` → `14G` (14336 MB; rezerwa ~880 MB pod metadata + safety buffer). Dla labu z 15 GB +RECO to wystarczy: archivelogi po SYNC redo transport + flashback logs + 1 RMAN backup set zmieszczą się w 14 GB w ramach jednego cyklu testów FSFO.

**Dla większego labu / produkcji:** zwiększyć disk group +RECO do 25-50 GB w `05_shared_storage_iscsi.md` (dodatkowe LUN) i ustawić `db_recovery_file_dest_size` na 20-40 GB.

**Fix dla uruchomionego runu (na prim01 jako oracle, po DBT-06604):**
```bash
sed -i 's|db_recovery_file_dest_size=15G|db_recovery_file_dest_size=14G|' /home/oracle/dbca_prim.rsp
grep db_recovery_file_dest_size /home/oracle/dbca_prim.rsp
bash /tmp/scripts/create_primary.sh   # restart - DBCA wykryje brak bazy i zacznie od poczatku
```

**Lekcja:** Sprawdzaj **rzeczywiste** `FREE_MB` z `asmcmd lsdg` zanim ustawisz `db_recovery_file_dest_size` — ASM zarezerwuje ~1% lub minimum kilkadziesiąt MB na metadata, więc wartość parametru ma być zawsze < `FREE_MB`, a nie `TOTAL_MB`.

---

### FIX-030 — `dbca_prim.rsp`: `General_Purpose.dbc` → `New_Database.dbt` (ORA-00201 controlfile version mismatch)

**Problem:** Image-based install Oracle Database 26ai 23.26.1 zawiera w `$ORACLE_HOME/assistants/dbca/templates/`:
- `General_Purpose.dbc` (pre-built CDB, używa `Seed_Database.ctl` + `Seed_Database.dfb1..7`)
- `Data_Warehouse.dbc` (pre-built, j.w.)
- `New_Database.dbt` (definition — DBCA wykonuje CREATE DATABASE od zera)

`Seed_Database.ctl` jest w wersji **23.6.0.0.0**, ale biblioteka RDBMS po OPatch RU 23.26.1 raportuje baseline jako **23.4.0.0.0** (`opatch lsinventory`: "Oracle Database 26ai 23.0.0.0.0" + RU 38743669/38743688 z 2026-01-18). Niespójność wersji wewnątrz tego samego image — Oracle prawdopodobnie nie zaktualizował `Seed_Database.ctl` przy budowie image 23.26.1.

**Objaw (DBCA `templateName=General_Purpose.dbc`):**
```
[WARNING] ORA-00201: control file version 23.6.0.0.0 incompatible with ORACLE version 23.4.0.0.0
ORA-00202: control file: '.../tempControl.ctl'

[WARNING] ORA-01507: database not mounted

[FATAL] ORA-01503: CREATE CONTROLFILE failed
ORA-01565: Error identifying file +DATA/PRIM/sysaux01.dbf.
ORA-15001: disk group "DATA" does not exist or is not mounted
```

ORA-15001 to **kaskada** od ORA-00201 — instancja nie zmountowała się więc nie ma połączenia z ASM. Disk group DATA jest mounted w ASM (potwierdzone `asmcmd lsdg`), nie ma problemu z ASM samym.

**Poprawka:** `response_files/dbca_prim.rsp` v2.1 — `templateName=General_Purpose.dbc` → `New_Database.dbt`. Plik `.dbt` (definition) sprawia że DBCA generuje SQL `CREATE DATABASE ...` od zera bez używania `Seed_Database.ctl`. Tworzenie wszystkich datafiles przez `CREATE TABLESPACE` z poziomu instancji w trybie OPEN (nie z pre-built backup files).

**Skutki uboczne:**
- Czas DBCA: ~30-50 min (CREATE od zera) zamiast ~20-40 min (pre-built copy). Dla labu różnica niewielka.
- Większy I/O w trakcie create (ASM zapisuje wszystkie bloki SYSTEM/SYSAUX/UNDO/USERS) — w naszym labie z LIO iSCSI na lokalnym SSD bez problemu.
- Funkcjonalnie wynik identyczny: CDB + PDB APPPDB + standardowe schemy (PDB$SEED, SYS, SYSTEM).

**Cleanup przed retry (ważne):**

```bash
# Jako grid na prim01 (ASM admin)
asmcmd <<'EOF'
ls +DATA/PRIM
rm -rf +DATA/PRIM
ls +RECO/PRIM 2>/dev/null
rm -rf +RECO/PRIM
EOF
```

Po nieudanym DBCA z ORA-00201 zostaje `+DATA/PRIM/PASSWORD/` (plik haseł utworzony wcześnie w flow). Trzeba usunąć — DBCA przy retry nie nadpisuje istniejących plików, fail.

**Fix dla uruchomionych VM:**

```bash
# Krok 1: cleanup ASM (jako grid na prim01)
sudo su - grid -c "asmcmd rm -rf +DATA/PRIM; asmcmd rm -rf +RECO/PRIM 2>/dev/null"

# Krok 2: update response file (jako oracle na prim01)
sed -i 's|^templateName=General_Purpose.dbc|templateName=New_Database.dbt|' /home/oracle/dbca_prim.rsp
grep templateName /home/oracle/dbca_prim.rsp
# powinno: templateName=New_Database.dbt

# Krok 3: retry
bash /tmp/scripts/create_primary.sh
```

**Lekcja:** Image-based install Oracle 23ai/26ai potrafi mieć **niespójne wersje** plików wewnątrz tego samego ZIP-a (RDBMS baseline vs assistants templates). `New_Database.dbt` jest **bezpiecznym domyślnym wyborem** dla labów DBCA — wolniejszy o ~50%, ale omija wszystkie pułapki seed controlfile / pre-built datafile. `General_Purpose.dbc` warto stosować tylko gdy potwierdzono spójność wersji `Seed_Database.ctl` z RDBMS (np. `strings $ORACLE_HOME/assistants/dbca/templates/Seed_Database.ctl | grep -i "version"` przed pierwszym DBCA).

---

### FIX-031 — `oracle` user w 23ai/26ai Flex ASM Direct Storage Access wymaga grupy `asmadmin`

**Problem:** W naszym kickstart-cie i `prepare_host.sh` v1.0 user `oracle` był dodany tylko do `asmdba` + `asmoper` (jak w standardowym 19c bez Flex ASM):

```
oracle: oinstall, dba, oper, backupdba, dgdba, kmdba, racdba, asmdba, asmoper
                                                               ^^^^^^^ ^^^^^^
                                              brak: asmadmin (54327)!
```

W Oracle 23ai/26ai default `cluster_database_mode=flex` + `Flex ASM Direct Storage Access` (`asmcmd showclustermode` → `Flex mode enabled - Direct Storage Access`) klient DB **bezpośrednio I/O na block devices** reprezentujące ASM disks. Standardowe udev rules (z `setup_iscsi_initiator_prim.sh`/`fix_udev_asm_rules.sh`) tworzą:

```
KERNEL=="sd*", ENV{ID_SERIAL}=="...", SYMLINK+="oracleasm/DATA1",
    OWNER="grid", GROUP="asmadmin", MODE="0660"
```

`MODE=0660` = owner+group rw, others nothing. `oracle` nie w `asmadmin` → **Permission denied** na `/dev/oracleasm/DATA1` → DBCA CREATE DATABASE rzuca ORA-15001.

**Objaw (DBCA `templateName=New_Database.dbt`):**
```
[FATAL] ORA-01501: CREATE DATABASE failed
ORA-00200: control file could not be created
ORA-00202: control file: '+DATA'
ORA-17502: (4)Failed to create file +DATA
ORA-15001: disk group "DATA" does not exist or is not mounted
ORA-59069: Oracle ASM file operation failed.
```

Z perspektywy ASM (`asmcmd lsdg` jako `grid`) disk groups są MOUNTED. Z perspektywy `oracle` user, próba `dd if=/dev/oracleasm/DATA1 of=/dev/null` → `Permission denied` — bezpośrednie potwierdzenie root cause.

**Diagnostyka (zapisana do skryptu sanity check):**
```bash
# Jako grid:
ls -la /dev/oracleasm/                          # symlinks owned by root
cat /etc/udev/rules.d/99*.rules | grep -E "GROUP|MODE"   # GROUP="asmadmin" MODE="0660"
groups oracle                                   # czy zawiera 'asmadmin'?
# Jako oracle:
dd if=/dev/oracleasm/DATA1 of=/dev/null bs=4096 count=1   # OK lub Permission denied
```

**Poprawka:**

1. **`scripts/prepare_host.sh` v1.1** — `usermod -a -G asmadmin,asmdba,asmoper oracle` (dodane `asmadmin`).

2. **`kickstart/ks-prim01.cfg` + `ks-prim02.cfg`**:
   ```bash
   useradd -u 54322 -g oinstall \
       -G dba,oper,backupdba,dgdba,kmdba,racdba,asmadmin,asmdba,asmoper \
       -m -s /bin/bash -c "Oracle Database" oracle
   ```

3. **`04_os_preparation.md`** — sekcja "Sprawdzenie po kickstart-cie" + sekcja 2.1 (manualna instalacja) — `oracle` musi mieć `asmadmin` jako secondary group.

4. **`stby01` NIE wymaga zmiany** — single instance bez ASM (lokalny XFS dla datafiles).

**Fix dla uruchomionych VM:**

```bash
# Na prim01 i prim02 jako root
sudo usermod -aG asmadmin oracle

# UWAGA: po `usermod -aG asmadmin oracle` RECZNIE na uruchomionym klastrze
# (zamiast przez kickstart przed Grid Install) zaleca sie RESTART CRS na danym
# node. Powod: oraagent.bin/orarootagent.bin czasami trzyma stale state ASM IPC,
# a forked instancja DB moze dostac stale view ASM disk groups (ORA-15001 mimo
# ze 'id oracle' i '/proc/<pid>/status' pokazuja 54327 prawidlowo).
# Empirycznie: restart 'crsctl stop/start crs' na danym node naprawia 'stuck'
# state ASM IPC po groups change w oracle. Bezpieczna procedura, nie zaszkodzi.

# Restart CRS na nodzie gdzie zmieniłeś groups (najlepiej oba):
sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
sleep 10
sudo /u01/app/23.26/grid/bin/crsctl start crs
# Czekaj ~3-5 min na pełne podniesienie

# Weryfikacja że oraagent ma asmadmin (54327) w groupset:
cat /proc/$(pgrep -f oraagent.bin | head -1)/status | grep ^Groups:

# Re-login oracle (groups loaded przy login)
exit  # z aktualnej sesji oracle
sudo su - oracle
groups | grep asmadmin   # weryfikacja

# Test direct access do block device
dd if=/dev/oracleasm/DATA1 of=/dev/null bs=4096 count=1
# powinno: "1+0 records in/out"

# Cleanup pozostałości po nieudanym DBCA (jako grid)
sudo su - grid -c 'asmcmd rm -rf +DATA/PRIM 2>/dev/null'

# Retry DBCA (jako oracle)
bash /tmp/scripts/create_primary.sh
```

**Lekcja:** Konwencja Oracle Role Separation z 19c (`oracle` w `asmdba`+`asmoper`, `asmadmin` tylko dla `grid`) **zmieniła się** w 23ai/26ai z Flex ASM Direct Storage Access. Dla **klienta DB w trybie Direct Storage Access** `asmadmin` (lub minimum udev `MODE=0664`) jest wymagane. Alternatywa: zmienić ASM cluster mode na **ASM Proxy** (klient łączy się z ASM przez sieć przez ASMNET listener) zamiast Direct Storage Access — ale wymaga osobnego setup-u i jest wolniejsze. Dla labu prościej dodać `oracle` do `asmadmin`.

---

### FIX-032 — `iscsi.service` race condition z siecią przy boot → CRS nie wstaje po (auto-)reboot

**Problem:** Jednostka systemd `iscsi.service` (która loguje się do iSCSI target przy boot) startuje **przed** pełną inicjalizacją sieci 192.168.200.0/24. Przy szybkim boot (lub po kernel panic auto-reboot) interfejs `enp0s9` (storage network) jeszcze nie ma IP/route gdy `iscsiadm -m node --loginall=automatic` próbuje się połączyć z `192.168.200.10:3260`.

```
14:24:23 systemd: Starting Login and scanning of iSCSI devices...
14:24:23 iscsid: cannot make connection to 192.168.200.10:3260 (-1,101)   ← errno 101 = Network unreachable
14:27:26 iscsid: Giving up after 120 seconds                              ← timeout, sieć storage nie gotowa
14:27:26 systemd: iscsi.service exited (code=8)                            ← FAIL, brak retry
```

Skutek: `/dev/oracleasm/OCR{1,2,3}`, `DATA1`, `RECO1` nie istnieją po boot. CSSD nie może czytać voting disks z `+OCR` → CRS hangs na `RESOURCE_START[ora.cssd 1 1]`. Klaster jako całość żyje (drugi node ma sesje), ale prim01 jest "out".

**Kontekst — co wywołało reboot:** podczas DBCA na 26ai (`New_Database.dbt`, ~50% progress, etap Oracle Text + OLAP) intensywne synchroniczne I/O do ASM przez VirtualBox iSCSI spowodowało gigantyczne **time drift** (`Time drifted forward by 7823240 µs` = 7.8 sek w jednym tiku, `hrtimer: interrupt took 643132 ns`). Linux kernel watchdog uznał system za zawieszony i wywołał panic + auto-reboot. Po reboot iSCSI nie zalogowało → CRS się nie podniósł → DBCA nie ma jak kontynuować.

**Diagnostyka:**
```bash
systemctl status iscsi iscsid
iscsiadm -m session              # "No active sessions" = potwierdza
ls -la /dev/oracleasm/           # puste (poza .., .)
journalctl -u iscsi.service --no-pager
```

**Hot-fix dla bieżącego stanu (po crash + reboot):**
```bash
# Jako root
ping -c 2 192.168.200.10                                 # sprawdz ze sieć storage UP
iscsiadm -m discovery -t st -p 192.168.200.10
iscsiadm -m node --loginall=automatic
sleep 5
iscsiadm -m session                                       # powinno pokazac sesje
ls -la /dev/oracleasm/                                    # OCR1..3, DATA1, RECO1

# CRS sam sie podnosi po ~30-60s (CSSD widzi voting disks)
sleep 60
sudo su - grid -c '. ~/.bash_profile; crsctl check cluster -all'

# Jesli CRS dalej stoi - force restart stack
sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
sleep 10
sudo /u01/app/23.26/grid/bin/crsctl start crs
```

**Trwała poprawka:** `scripts/setup_iscsi_initiator_prim.sh` v1.1 — tworzy systemd override `/etc/systemd/system/iscsi.service.d/00-wait-network.conf`:

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

Skutki:
- `After=network-online.target` — iscsi.service nie startuje dopóki NetworkManager nie zgłosi "online" (wszystkie interfejsy z IP).
- `Restart=on-failure` + `RestartSec=15` — jeśli pierwszy login fail (np. target jeszcze startuje na infra01), retry co 15s, do 10× w 5 min.

Plus: `systemctl enable NetworkManager-wait-online` zapewnia że `network-online.target` faktycznie zostanie osiągnięty (na OL 8.10 ta jednostka jest disabled domyślnie).

**Dla uruchomionych VM (prim01, prim02) — apply override bez ponownego uruchamiania całego skryptu:**
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

**Dodatkowo — FIX-033 (sysctl tolerance) zalecany razem:** żeby kolejny VirtualBox time drift nie wywołał panic + reboot:
```bash
sudo tee /etc/sysctl.d/99-vm-tolerance.conf > /dev/null <<'EOF'
kernel.softlockup_panic = 0
kernel.hung_task_panic = 0
kernel.unknown_nmi_panic = 0
kernel.watchdog_thresh = 30
EOF
sudo sysctl --system
```

**Lekcja:** Domyślny `iscsi.service` w OL 8.x to **fire-and-forget oneshot** — jeden Try, brak retry, brak waitu na sieć. Dla iSCSI-on-internal-VirtualBox-network to za mało. Każdy lab z iSCSI ASM **musi** mieć override z `After=network-online.target` + `Restart=on-failure`, inaczej każdy reboot to ruletka czy CRS się podniesie.

---

### FIX-033 — VirtualBox VM kernel panic z time drift podczas DBCA → auto-reboot

**Problem:** Podczas DBCA `New_Database.dbt` (Oracle Text + OLAP, ~50% progress) intensywne synchroniczne I/O do ASM przez VirtualBox iSCSI spowodowało gigantyczne time drift w guest OS. Linux kernel (5.15) ma watchdog który po `softlockup_thresh` (default 20s) bez postępu CPU panic'uje. Time drift > 5s w jednym tiku = false positive softlockup.

**Objaw w alert log primary instance + dmesg:**
```
Time drifted forward by (7823240) micro seconds at 24660716215 whereas allowed drift is 1000000
hrtimer: interrupt took 643132 ns
[potem brak dalszych wpisow]
[VM auto-reboot]
```

`last reboot` pokazuje świeży boot. Crash wywołał kaskadę: VM reboot → iSCSI fail (FIX-032) → CRS down → DBCA padło bezpowrotnie (orphan `ora.prim.db` w CRS).

**Poprawka:** `/etc/sysctl.d/99-vm-tolerance.conf` — wyłączamy panic na softlockup (VM kernel ma być **TOLERANT** dla time skew, nie agresywnie reset):

```
kernel.softlockup_panic = 0       # default: 0 — explicit dla pewnosci
kernel.hung_task_panic = 0        # default: 0 — j.w.
kernel.unknown_nmi_panic = 0      # default: 0 — j.w.
kernel.watchdog_thresh = 30       # default: 10 — wydluzamy z 10 do 30 sek
```

`watchdog_thresh=30` daje 30 sekund tolerancji zanim kernel uznaje CPU za "stuck". Dla VirtualBox VM gdzie host okazjonalnie zamraża guest na 5-10s przy intensywnym I/O, to wystarczy by przeżyć.

**Dla uruchomionych VM (prim01 + prim02):**
```bash
sudo tee /etc/sysctl.d/99-vm-tolerance.conf > /dev/null <<'EOF'
kernel.softlockup_panic = 0
kernel.hung_task_panic = 0
kernel.unknown_nmi_panic = 0
kernel.watchdog_thresh = 30
EOF
sudo sysctl --system
```

**Dodatkowo do rozważenia (NIE konieczne, tylko opcjonalna optymalizacja):**

1. **Paravirt clock w VirtualBox** (z hosta gdy VM stop):
   ```powershell
   & $VBox modifyvm prim01 --paravirtprovider kvm
   & $VBox modifyvm prim02 --paravirtprovider kvm
   ```
   `kvm` (lub `hyperv` na Windows host) daje guest OS bezpośredni dostęp do TSC hosta — drastycznie redukuje time drift.

2. **Tickless kernel + chrony aggressive sync** (na guest):
   ```bash
   sudo grubby --update-kernel=ALL --args="nohz=off"   # opcjonalne
   # W /etc/chrony.conf: makestep 1.0 -1   # zawsze step zamiast slew
   sudo systemctl restart chronyd
   ```

**Kontekst dlaczego nie zadziałało wcześniej (mimo wczesnego setup chrony):** chrony robi *slew* (powolne korygowanie częstotliwości zegara) zamiast *step* (skokowe ustawienie). Przy time drift 7s w jednym tiku slew nie nadąża — kernel watchdog reaguje szybciej niż chrony.

**Lekcja:** VM Linux z domyślnymi sysctl jest **panic-happy** dla intensywnych I/O scenariuszy (DBCA, RMAN backup, RDBMS startup). Dla labów na VirtualBox/VMware z nominalnym CPU ale intensywnym storage, bezpieczniej ustawić `softlockup_panic=0` + `watchdog_thresh=30` zaraz po instalacji OS — to nie obniża niezawodności, tylko daje kernelowi więcej cierpliwości.

**Plus:** zaktualizowany `scripts/create_primary.sh` v2.1:
- Idempotency check: sprawdza `srvctl status database -db PRIM | grep "is running"` (nie tylko czy resource zarejestrowany), żeby orphan OFFLINE z poprzedniego crashu **nie** był traktowany jako "baza już istnieje"
- Auto-recovery: jeśli wykryje orphan PRIM (registered ale OFFLINE), próbuje `srvctl remove database -db PRIM -force -noprompt` zanim zacznie pełen DBCA
- Lepsze parsowanie output `sqlplus log_mode` (bez `tr -d ' \n'` które zlepiało ORA-01034 w jeden ciąg) — używa `grep -oE 'ARCHIVELOG|NOARCHIVELOG'` z explicit error gdy instancja down

---

### FIX-035 — `create_primary.sh`: utlrp.sql Error 45 / asmcmd hang post-create

**Problem 1 — utlrp.sql exit code mimo sukcesu:**

Po `sqlplus / as sysdba @?/rdbms/admin/utlrp.sql` skrypt utlrp **kończy się pomyślnie** (`UTLRP_END timestamp = ...`, `OBJECTS WITH ERRORS = 0`), ale potem na końcu sqlplus drukuje:
```
Error 45 initializing SQL*Plus
Internal error
```
i zwraca **non-zero exit code**. `set -e` w skrypcie wrapper zabija dalszy flow przed eksportem pwfile. Skutek: skrypt umiera na `[hh:mm:ss] Recompile invalid objects (utlrp.sql)...` jako ostatniej linii w `/tmp/dbca3.out`, mimo że utlrp leci OK.

Przyczyna `Error 45` niejasna — prawdopodobnie sqlplus 23ai post-utlrp drop'uje TEMPORARY function (część cleanup utlrp) i zwraca err code przy zamknięciu sesji.

**Problem 2 — `asmcmd pwcopy` hang z DB home:**

`asmcmd` jako user `oracle` ze zmiennymi `ORACLE_HOME=$DB_HOME` + `ORACLE_SID=PRIM1` potrafi **wisić bez timeout** przy `pwcopy` (lub innych operacjach wymagających connect do ASM instance). Prawidłowy sposób: jako user `grid` z `ORACLE_HOME=$GRID_HOME` + `ORACLE_SID=+ASM1` — wtedy asmcmd direct-connect do lokalnej instancji ASM.

**Objaw:** skrypt wisiał na linii `asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f` przez >5 min bez wyjścia.

**Poprawka `scripts/create_primary.sh` v2.2:**

```bash
# 1. utlrp z '|| true' + walidacja przez log file
sqlplus / as sysdba @?/rdbms/admin/utlrp.sql > /tmp/utlrp_prim.log 2>&1 || true
ERRORS_FOUND=$(grep -A1 "^OBJECTS WITH ERRORS" /tmp/utlrp_prim.log | tail -1 | tr -d ' ')
if [[ -n "$ERRORS_FOUND" && "$ERRORS_FOUND" != "0" ]]; then
    warn "utlrp wykryl $ERRORS_FOUND invalid objects"
fi

# 2. asmcmd przez sudo grid (z fallback timeout 30s na asmcmd jako oracle)
if sudo -n -u grid bash -c '. ~/.bash_profile && asmcmd pwcopy '"$PWFILE"' /tmp/pwd/orapwPRIM -f' 2>/dev/null; then
    sudo chown oracle:oinstall /tmp/pwd/orapwPRIM
    log "Password file skopiowany przez grid"
else
    timeout 30 asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f || \
        warn "Recznie: sudo su - grid -c 'asmcmd pwcopy $PWFILE /tmp/pwd/orapwPRIM -f'"
fi
```

**Hot-fix dla bieżącej sytuacji** (utlrp DONE, ale skrypt umarł z Error 45):

```bash
# 1. Zabij ewentualnie ostały nohup proces
ps -ef | grep create_primary | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null

# 2. Eksport pwfile recznie jako grid
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

**Lekcja:**
- **Ucz `set -e`-friendly tolerance** dla narzędzi które mają znane false-positive errors (sqlplus exit 45, jakieś known buggy scenarios).
- **`asmcmd` zawsze przez grid user** — to jego "natywne" home. Wywołanie z DB home działa **czasem** ale wisi w nieprzewidywalnych momentach.
- **Każdy `asmcmd` w skryptach long-running otaczaj `timeout` lub run jako grid** — eliminuje całą klasę intermittent hangs.

**Dodatek 2026-04-26 — `asmcmd pwcopy` flagi w 23ai:**

W 19c `asmcmd pwcopy` akceptował `--force`, w 23ai akceptuje **tylko `-f`** (skrócona forma). Próba użycia `--force` zwraca:
```
ASMCMD-9412: Invalid option: force
usage: pwcopy [ --dbuniquename <string> | --asm ][-f][--local]
        <source_path> <destination_path>
```

Zaktualizowano w 5 plikach (12 wystąpień): `08_database_create_primary.md`, `09_standby_duplicate.md`, `FIXES_LOG.md`, `SESSION_STATE.md`, `scripts/create_primary.sh`. Wszędzie `--force` → `-f`.

---

## 2026-04-26

### FIX-036 — Storage tuning zaaplikowane domyślnie w pipeline'ie instalacji

**Kontekst:** Po sesji 25.04 zidentyfikowano 5 optymalizacji storage które dają **5–10× speedup** dla random write (DBCA, RMAN, archivelog) i które są **bezpieczne dla labu**. Wcześniej istniały tylko jako post-install runtime tune w `scripts/alt/tune_storage_runtime.sh` — wymagały świadomego wywołania po instalacji. Teraz są wbudowane w skrypty install-time.

**Optymalizacje (5 sztuk):**

| # | Optymalizacja | Bezpieczne? | Gdzie zaaplikowane |
|---|---------------|-------------|---------------------|
| 1 | VBox `--hostiocache on` na SATA infra01 | Tylko dla infra01 (NIE prim/stby/client) | `vbox_create_vms.ps1` + `vbox_create_vms_block.ps1` |
| 2 | XFS opts: `noatime,nodiratime,largeio,inode64,logbufs=8,logbsize=256k` | Pure win | `setup_iscsi_target_infra01.sh` (fstab) |
| 3 | LIO `emulate_write_cache=1` na DATA/RECO LUN-ach (NIE OCR!) | Lab OK; OCR sync dla CSSD voting | `setup_iscsi_target_infra01.sh` + `setup_iscsi_target_block.sh` |
| 4 | iSCSI initiator: `replacement_timeout=15`, `noop_out_*=5/10`, `queue_depth=64` | Pure win | `setup_iscsi_initiator_prim.sh` (iscsid.conf) |
| 5 | `mq-deadline` scheduler na `/dev/sdb` + udev rule | Pure win na concurrent writers | `setup_iscsi_target_infra01.sh` + `setup_iscsi_target_block.sh` |

**Krytyczne zasady które muszą być utrzymane:**
- **`hostiocache=on` TYLKO na infra01.** Na prim01/02/stby01 = corruption datafiles przy crash hosta. Skrypty mają jawne `--hostiocache off` dla pozostałych VM.
- **OCR LUN-y bez `emulate_write_cache`.** Voting disks wymagają sync semantics dla CSSD.
- **iscsid.conf modyfikowany PRZED `iscsiadm --discovery`** — discovery zapisuje per-node config z aktualnego defaultu. Modyfikacja po `--discovery` wymaga `iscsiadm -m node --op update` (skomplikowane).

**Zmiany w plikach:**

```
scripts/vbox_create_vms.ps1 v1.1:
  - infra01 RAM 4096 → 8192 MB (page cache LIO)
  - prim01/02 RAM 8192 → 9216 MB (cluvfy strict ≥8 GB physical)
  - infra01 SATA controller: --hostiocache on
  - pozostale VM: --hostiocache off (jawnie)

scripts/alt/vbox_create_vms_block.ps1 v1.1:
  - prim01/02 RAM 8192 → 9216 MB
  - infra01 SATA controller: --hostiocache on (block backstore tez korzysta z page cache hosta)

scripts/setup_iscsi_target_infra01.sh v1.1:
  - fstab opts: defaults,noatime → defaults,noatime,nodiratime,largeio,inode64,logbufs=8,logbsize=256k
  - mq-deadline na /dev/sdb (sysfs + udev rule)
  - LIO emulate_write_cache=1 na lun_data1+lun_reco1 (NIE OCR)
  - LIO emulate_fua_write=1 (FUA respektowane → SYNC commits nadal sync)

scripts/alt/setup_iscsi_target_block.sh v1.1:
  - LIO emulate_write_cache=1 na lun_data1+lun_reco1 (block backstore tez wspiera)
  - mq-deadline na /dev/sdb (sysfs + udev rule)

scripts/setup_iscsi_initiator_prim.sh v1.2:
  - iscsid.conf tuning PRZED login: replacement_timeout=15, noop_out_interval=5,
    noop_out_timeout=10, queue_depth=64
```

**Spodziewany skutek dla użytkownika rebuilduującego lab od zera:**

| Operacja | Przed (default fileio) | Po FIX-036 (default fileio + tune) | Po wariant 17 |
|----------|------------------------|------------------------------------|---------------|
| DBCA `New_Database.dbt` | 50–90 min | **20–40 min** | 30–50 min |
| RMAN duplicate (4 GB DB) | 15–25 min | **5–12 min** | 8–15 min |
| Random write IOPS | 5–8k | **15–25k** | 20–35k |
| CRS recovery po iSCSI fail | 120 s (default replacement_timeout) | **15 s** | 15 s |

**Risk profile:**
- W przypadku **BSOD/power loss hosta** Windows: utrata writes z page cache → corruption `/var/storage/*.img` → re-create LUN-ów + RMAN restore (~30 min). **Akceptowalne w labie.**
- Dla PROD: **NIE WŁĄCZAĆ** `hostiocache=on`, **NIE WŁĄCZAĆ** `emulate_write_cache` na DATA. Prawdziwy SAN/NetApp ma battery-backed cache — to inna klasa rozwiązań.

**Lekcja:**
- **Lekcje runtime tuning powinny migrować do install-time** gdy są bezpieczne w danym kontekście. Zostawanie ich tylko jako "advanced post-tune" oznacza że 90% userów ich nie odpali.
- **Jawnie podpisuj `hostiocache=off` dla VM-ów z datafiles bazy.** Polegając tylko na default ryzykujesz że ktoś późniejszy zmodyfikuje skrypt i włączy globalnie.
- **OCR ZAWSZE sync.** Cluster voting disks **muszą** mieć consistent state przy crash — to sercem klastra (split-brain prevention).

---

### FIX-037 — HugePages 2MB w pipeline default (dla obu wariantów)

**Kontekst:** W wariancie B (`prepare_host_block.sh`) HugePages 768×2MB były od początku, w wariancie A nie było ich w ogóle. To powodowało że SGA (~1.5 GB) była rozproszona na ~392k stron 4K → częste TLB miss, ~10–15% straty wydajności bazy. Optymalizacja jest **bezpieczna i skuteczna w obu wariantach** — nie zależy od storage backend.

**Decyzja:** Migrowanie HugePages config z wrappera `prepare_host_block.sh` do głównego `prepare_host.sh` jako default dla `--role=rac` i `--role=si`. Wrapper zostaje jako thin shim dla kompatybilności (nowe instalacje go nie potrzebują).

**Poprawka `scripts/prepare_host.sh` v1.3 (sekcja 7c):**

```bash
if [[ "$ROLE" == "rac" || "$ROLE" == "si" ]]; then
    HUGEPAGES_NUM="${HUGEPAGES_NUM:-768}"  # 768 * 2 MB = 1536 MB pokryje SGA_TARGET
    cat > /etc/sysctl.d/99-hugepages.conf <<EOF
vm.nr_hugepages = $HUGEPAGES_NUM
EOF
    # memlock unlimited dla oracle + grid (potrzebne by procesy mogly pinnowac HugePages)
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

**Override dla większych baz:** `HUGEPAGES_NUM=1024 sudo bash prepare_host.sh --role=rac` (= 2 GB SGA), `HUGEPAGES_NUM=2048` (= 4 GB).

**Zysk:**
- ~10–15% generic speedup całej bazy (mniej TLB miss → mniej cycles na każdą operację)
- SGA pinned w pamięci (memlock unlimited) — nie podlega swappingowi nawet pod presją RAM
- Brak fragmentacji 392k stron 4K → 768 stron 2MB

**Wymagany restart bazy** po pierwszym uruchomieniu `prepare_host.sh`, żeby SGA przyalokowała się z hugepages. W pipeline'ie instalacji to nie problem (DBCA tworzy bazę po prepare_host.sh — od razu z hugepages).

**Live application 2026-04-26:** zaaplikowane na działający lab przed Krok F (09 RMAN duplicate). Restart `srvctl stop/start database -db PRIM` wziął SGA na hugepages.

**Weryfikacja:**
```bash
# /proc/meminfo - HugePages_Free ~0 znaczy że SGA wzięła hugepages
grep -i huge /proc/meminfo
# HugePages_Total:    768
# HugePages_Free:       0    ← SGA wzięła
# Hugepagesize:       2048 kB

# Oracle - parametr use_large_pages (default 23ai = TRUE = best-effort)
SHOW PARAMETER use_large_pages   # TRUE (recommended) / ONLY (hard fail) / FALSE
```

**Lekcja:**
- **Optymalizacja niezależna od storage backend = jeden punkt prawdy.** `prepare_host_block.sh` rozdzielał coś co dotyczy obu wariantów — błąd projektowy. Po refaktorze wrapper jest legacy, można go zostawić, ale nowe instalacje używają tylko `prepare_host.sh`.
- **`use_large_pages=TRUE` (default 23ai)** = best-effort fallback. Nie używaj `ONLY` w labie — przy chwilowym braku hugepages baza nie wstanie.
- **memlock unlimited krytyczne** — bez tego procesy oracle nie mogą pinnowac HugePages, alokacja fail-uje, baza pada na 4K.

---

### FIX-038 — `duplicate_standby.sh` audyt pre-09 (8 poprawek)

**Kontekst:** Po Krok C (health check primary) audyt skryptu `duplicate_standby.sh` v1.0 ujawnił 8 issues — 3 critical (skrypt **nie ruszy**), 4 important (ryzyka i wolne wykonanie), 1 nice-to-have. Plus user ma Active Data Guard license (issue ADG #3 z planu odpada).

**Issue #1 (CRITICAL) — Brak generowania tnsnames.ora na stby01.**
Linie skryptu używają `sqlplus sys/...@PRIM` i `CONNECT TARGET ...@PRIM` / `CONNECT AUXILIARY ...@STBY`. Bez aliasów w `$TNS_ADMIN/tnsnames.ora` oba connect fail-ują z `ORA-12154`. Skrypt nie generował tnsnames jako wewnętrzny step — zakładał zewnętrzny prerequisite.

**Issue #2 (CRITICAL) — Brak generowania listener.ora SID_LIST static dla STBY.**
RMAN AUXILIARY connect do `STBY` w stanie nomount wymaga statycznej rejestracji w listenerze (instancja w nomount nie zarejestruje się dynamic — PMON robi to dopiero po MOUNT). Bez `SID_LIST_LISTENER` z entry `STBY` → `ORA-12514 listener does not currently know of service requested`.

**Issue #3 (CRITICAL) — Brak `lsnrctl start` przed RMAN.**
Nawet z poprawnym listener.ora, listener musi być UP przed sekcją RMAN duplicate.

**Issue #4 (IMPORTANT) — `SHUTDOWN ABORT` bez `WHENEVER SQLERROR CONTINUE`.**
Pierwsza sekcja `STARTUP NOMOUNT` zaczyna się od `SHUTDOWN ABORT` (idempotency). Jeśli instancja STBY **nigdy nie startowała**, `SHUTDOWN ABORT` zwraca ORA-01034. Z `set -euo pipefail` może zabić skrypt na pierwszym uruchomieniu (czyste środowisko).

**Issue #5 (IMPORTANT) — Brak sanity check primary.**
Skrypt nie weryfikuje że primary jest gotowy. Jeśli `FORCE_LOGGING != YES`, `< 8 SRL`, `log_archive_config nie zawiera STBY` → duplicate się uda, ale apply nie zadziała / będzie data divergence. Bezpieczniej: SQL `@PRIM` na początku, abort z czytelnym komunikatem.

**Issue #6 (IMPORTANT) — RMAN bez channels parallelism.**
Single channel duplicate ~10-15 min dla 5 GB lab DB. Z 4 target + 4 auxiliary channels: ~3-5 min. Składnia 23.26.1: `RUN { ALLOCATE CHANNEL c1..c4 + ALLOCATE AUXILIARY CHANNEL aux1..aux4; DUPLICATE ...; }`.

**Issue #7 (NICE-TO-HAVE) — `sga_target=2048M` w initSTBY.ora vs primary 1.5 GB.**
Primary ma `sga_target=1536M` (Maximum SGA Size 1533 MB potwierdzone przez `v$sgainfo`). STBY z 2048M = 2 GB **nie zmieści się w HugePages 768×2MB = 1.5 GB** — Oracle fallback do 4K, no benefit z FIX-037. Plus inconsistency po switchover. Zsynchronizowane do `sga_target=1536M`.

**Issue #8 (NICE-TO-HAVE) — `log_archive_dest_2=''` (pusty string w RMAN SET).**
W 23.26.1 niektóre wersje composer rejestrują pusty string jako error parsowania. Bezpieczniej ustawić od razu na `'SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILE,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM'` — gotowe pod switchover, nie wymaga update w doc 10.

**Poprawka `scripts/duplicate_standby.sh` v2.0:**

Pełen rewrite z 9 sekcjami numerowanymi:
- Sekcja 0: Sanity check primary (Issue #5) — 9 sprawdzeń przez `ssh oracle@prim01 sqlplus`, abort z `die` jeśli FAIL
- Sekcja 1: Katalogi /u01/app/oracle/admin/STBY/adump, /u02/oradata/STBY, /u03/fra/STBY + /etc/oratab
- Sekcja 2: initSTBY.ora z `sga_target=1536M` (Issue #7)
- Sekcja 3: tnsnames.ora generation (Issue #1) — PRIM (scan-prim:1521), STBY (lokalnie), PRIM_DGMGRL/STBY_DGMGRL (UR=A)
- Sekcja 4: listener.ora SID_LIST static + `lsnrctl start` (Issue #2 + #3)
- Sekcja 5: scp pwfile z prim01:/tmp/pwd/orapwPRIM
- Sekcja 6: STARTUP NOMOUNT z `WHENEVER SQLERROR CONTINUE` przed `SHUTDOWN ABORT` (Issue #4) + sleep 10s na PMON listener registration
- Sekcja 7: Test connection sys@PRIM
- Sekcja 8: RMAN DUPLICATE z `RUN { ALLOCATE CHANNEL c1..c4 + aux1..aux4 ... }` (Issue #6) + `log_archive_dest_2=` od razu poprawnie (Issue #8)
- Sekcja 9: Post-duplicate `OPEN READ ONLY` + `RECOVER MANAGED STANDBY USING CURRENT LOGFILE` (Active Data Guard real-time apply — user has ADG license)

**Co zachowane bez zmian (sprawdzone OK):**
- `compatible=23.0.0` — pasuje do baseline 23.26.1
- `cluster_database=FALSE` — OK (stby01 to SI)
- `NOFILENAMECHECK` — OK (mamy `db_file_name_convert`)
- `dg_broker_start=FALSE` — OK (włączymy w doc 10)
- `OPEN READ ONLY` — OK (user ma ADG license)

**Spodziewany czas duplicate:** ~3-5 min dla 5 GB DB (z 4+4 channels) zamiast ~10-15 min (single channel). W połączeniu z FIX-036 (TCP buffer tuning byłby następnym krokiem) i FIX-037 (HugePages) — pełen pipeline 09 = ~5-8 min.

**Lekcja:**
- **Audyt skryptów ZAWSZE przed greenfield run.** Skrypty z dokumentacji 19c→23ai mogą mieć ukryte zewnętrzne prerequisites (jak tnsnames/listener) które autor zakładał ale nie zaprogramował.
- **`set -euo pipefail` + idempotency** wymagają jawnego `WHENEVER SQLERROR CONTINUE` w sqlplus heredoc.
- **RMAN parallelism w labie warto** — 4+4 channels nie obciąża nawet małego sprzętu (single VM read+write), zysk czasu ~3x.
- **Sanity check primary BEFORE long-running operation** — 30s SQL eliminuje 15 min wykonania duplicate który zrobiłby się błędnie.

---

### FIX-039 — `sudo` w nohup-owanym skrypcie zatrzymuje proces (SIGTTOU)

**Problem:** Pierwsze odpalenie `duplicate_standby.sh v2.0` przez `nohup ... &` zatrzymało się **natychmiast** w sekcji 1 z komunikatem:

```
We trust you have received the usual lecture from the local System
Administrator. It usually boils down to these three things:
    #1) Respect the privacy of others.
    #2) Think before you type.
    #3) With great power comes great responsibility.

[1]+  Stopped                 nohup bash /tmp/scripts/duplicate_standby.sh > /tmp/dup.out 2>&1
```

**Przyczyna:** Sekcja 1 robiła `echo "STBY:..." | sudo tee -a /etc/oratab`. Pierwsze wywołanie `sudo` na sesji pokazuje "lecture" + prompt na hasło. `nohup` przekierowuje stdin do `/dev/null`, więc sudo **nie ma skąd przeczytać hasła** → próbuje czytać z controlling terminal → bash kontroluje terminal a nohup'owy proces dostaje SIGTTOU (try-to-read-from-tty in background) → status `Stopped`.

**Generalna lekcja:** Skrypty oracle (uruchamiane jako oracle user, nie root) **nigdy nie powinny używać `sudo` w runtime**. Wszystkie modyfikacje plików systemowych (`/etc/oratab`, `/etc/hosts`, `/etc/sysctl.d/...`) muszą być zrobione **proaktywnie przy install time** przez `prepare_host.sh` (jako root) lub ręcznie przez admina.

**Poprawka 1 — `scripts/duplicate_standby.sh` v2.1 (sekcja 1):**

```bash
# Stara wersja (PROBLEM):
if ! grep -q "^STBY:" /etc/oratab 2>/dev/null; then
    echo "STBY:$ORACLE_HOME:N" | sudo tee -a /etc/oratab >/dev/null || \
        warn "Nie udalo sie dopisac do /etc/oratab (kontynuuje)"
fi

# Nowa wersja (FIX-039) - tylko sprawdza, nie modyfikuje:
if ! grep -q "^STBY:" /etc/oratab 2>/dev/null; then
    warn "Brak entry 'STBY:...' w /etc/oratab. Skrypt kontynuuje, ale 'oraenv' nie znajdzie STBY."
    warn "Recznie dodaj jako root: echo 'STBY:$ORACLE_HOME:N' >> /etc/oratab"
fi
```

**Poprawka 2 — `scripts/prepare_host.sh` v1.4 (nowa sekcja 7d):**

Proaktywne dodanie entry do `/etc/oratab` w `prepare_host.sh` (uruchamiany jako root przy OS prep, **nie wymaga sudo**):

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

**Hot-fix dla bieżącej sytuacji (sesja 26.04):**

```bash
# Na stby01 jako root (1 raz)
echo "STBY:/u01/app/oracle/product/23.26/dbhome_1:N" >> /etc/oratab
```

Po tym `duplicate_standby.sh` v2.1 + nohup już nie zawiśnie w sekcji 1.

**Poprawka 3 — `09_standby_duplicate.md`:**
- Dodany wzorzec `nohup bash ... > /tmp/dup.out 2>&1 &` jako recommended (zamiast plain bash)
- Wyjaśnienie dlaczego nohup jest krytyczne (5 min skrypt + ryzyko SSH disconnect)
- Wymóg pre-existing `/etc/oratab` entry STBY w sekcji "Wymagania (zewnętrzne)"

**Lekcja (uniwersalna):**
- **`sudo` + `nohup` (lub jakikolwiek background) = zawsze problem** — sudo wymaga tty dla password prompt; background procesy nie mają tty. Solution: NOPASSWD w sudoers (komplikuje setup) **albo lepsza opcja** — przenieś logikę wymagającą root do skryptu uruchamianego jako root przy install (np. `prepare_host.sh`).
- **Skrypty oracle user-space mają być pure `oracle`-context.** Każde `sudo` w skrypcie który ma być uruchomiony przez oracle = code smell. Refactor do prepare_host.sh.
- **Dla nohup ZAWSZE testuj na `< /dev/null`** — jeśli proces gdzieś próbuje czytać z stdin (sudo password, prompty interaktywne), wisi.

---

### FIX-040 — `service_names` w 23ai DBCA `New_Database.dbt` ma `.db_domain` suffix

**Problem:** `duplicate_standby.sh v2.1` w sekcji 7 (test connection sys@PRIM) padał:

```
ORA-12514: Cannot connect to database. Service PRIM is not registered with the
listener at host 192.168.56.32 port 1521.
```

Mimo że:
- `remote_listener=scan-prim.lab.local:1521` ✅
- SCAN listener up i ONLINE (3 listenery na 2 nodach via `srvctl status scan_listener`) ✅
- PMON-y zarejestrowały się ✅
- `tnsping scan-prim.lab.local:1521` → OK ✅

**Diagnoza:**

```sql
SQL> SHOW PARAMETER service_names
NAME             VALUE
---------------- ------------------------
service_names    PRIM.lab.local        ← Z DOMENĄ!
```

```bash
$ lsnrctl status LISTENER_SCAN3 | grep Service
Service "PRIM.lab.local" has 2 instance(s).        ← TYLKO Z DOMENĄ!
Service "PRIMXDB.lab.local" has 2 instance(s).
# NIE MA "PRIM" jako bare name
```

W tnsnames.ora skryptu było:
```
PRIM = (... (SERVICE_NAME = PRIM) ...)        ← BŁĄD, brak .lab.local
```

**Przyczyna:** Oracle 23ai DBCA z templatem `New_Database.dbt` (FIX-030) **automatycznie appenduje `db_domain` do `service_names`**. W 19c i wcześniejszych 23ai patch sets bywało inaczej (często `db_domain=''` było default, więc service_names bez suffixu). W 23.26.1 ze stycznia 2026 — **db_domain ='lab.local' jest dodawane automatycznie** podczas DBCA jeśli `oracleHomeName` lub network config sugeruje domain (lab.local jest w `db.lab.local` zone na infra01 bind9).

**Poprawka `scripts/duplicate_standby.sh` v2.2:**

1. **`tnsnames.ora`** — `SERVICE_NAME=PRIM` → `SERVICE_NAME=PRIM.lab.local`. Analogicznie dla STBY: `SERVICE_NAME=STBY.lab.local` (post-duplicate STBY też będzie miał suffix bo dodajemy `db_domain=lab.local` do initSTBY.ora — patrz pkt 2).

2. **`initSTBY.ora`** — dodanie `db_domain=lab.local` (consistency z primary). Dodatkowo usunięte deprecated `audit_file_dest`, `audit_trail` (w 23ai legacy audit jest deprecated, Unified Audit jest default-on; warningi ORA-32006 z poprzedniego runu).

3. **`listener.ora` SID_LIST_LISTENER** — dodany 3-ci `SID_DESC` z `GLOBAL_DBNAME=STBY.lab.local` (matche dynamic registration po starcie bazy z db_domain). Pierwszy `SID_DESC` z `GLOBAL_DBNAME=STBY` zachowany (RMAN AUXILIARY connect używa alias `STBY` z tnsnames, który pre-duplicate jest jeszcze bez domeny — instancja STBY w nomount NIE ma db_domain ustawionego dopiero po RMAN sets SPFILE).

4. **DGMGRL services** (`PRIM_DGMGRL`, `STBY_DGMGRL`) **ZACHOWANE bez domeny** — to świadoma decyzja: statyczna rejestracja w `SID_LIST_LISTENER` używa `GLOBAL_DBNAME` parameter wprost, nie respektuje `db_domain`. DG broker w doc 10 będzie się łączył przez te aliasy.

**Hot-fix dla bieżącej sesji 26.04 (przed re-run skryptu):**

```bash
# Na stby01 jako oracle - cleanup nomount instance
sqlplus / as sysdba <<<"SHUTDOWN ABORT;"
ps -ef | grep ora_pmon_STBY | grep -v grep    # powinno: nic

# Skopiuj v2.2 z hosta
scp <repo>/VMs/scripts/duplicate_standby.sh oracle@stby01:/tmp/scripts/duplicate_standby.sh

# Odpal ponownie
nohup bash /tmp/scripts/duplicate_standby.sh > /tmp/dup.out 2>&1 &
tail -f /tmp/dup.out
```

**Lekcja (uniwersalna dla 23ai/26ai):**
- **Nie zakładaj że `service_names = db_unique_name`** — sprawdź **SHOW PARAMETER service_names** zamiast polegać na konwencji.
- **DBCA `New_Database.dbt` w 23.26.1 (styczeń 2026) appenduje db_domain** do service_names automatycznie. Sprawdź `db_domain` po DBCA — jeśli jest ustawiony, każdy service_name ma suffix.
- **`tnsping` mówi tylko o listenerze** (TCP connect + adapter resolve), NIE o tym czy konkretny service jest zarejestrowany. Do testowania konkretnego service: `lsnrctl status SCAN_LISTENER` lub `sqlplus user/pass@PRIM` (i zobacz ORA-error).
- **Dla DG broker static services BEZ domeny** — `_DGMGRL` services tradycyjnie nie mają `.db_domain` suffixu (legacy convention, broker tak je tworzy).

---

### FIX-041 — RMAN DUPLICATE w 26ai: `cluster_database_instances` niewspierane w SET clause

**Problem:** `duplicate_standby.sh v2.2` wszedł do RMAN sekcji 8, alokował 4+4 channels, ale natychmiast po `Starting Duplicate Db at 2026-04-26 16:35:18` padł:

```
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-03002: failure of Duplicate Db command at 04/26/2026 16:35:19
RMAN-05501: aborting duplication of target database
RMAN-06581: option cluster_database_instances not supported
```

Wszystkie channels released, RMAN session dropped.

**Diagnoza:** W 26ai (potwierdzone na 23.26.1 styczeń 2026) RMAN `DUPLICATE TARGET DATABASE FOR STANDBY ... SPFILE SET ...` clause **nie wspiera** parametru `cluster_database_instances`. Lista wspieranych SET parameters została zmieniona w 23ai/26ai (precise diff vs 19c niedostępny w MOS, ale empirycznie potwierdzone — `cluster_database_instances` removed from supported list).

W 19c i wcześniejszych 23ai patches `SET cluster_database_instances='1'` w RMAN duplicate **działało** dla SI standby (zmienia z RAC primary 2-instance na SI 1-instance). W 26ai trzeba **post-duplicate ALTER SYSTEM** + bounce.

**Poprawka `scripts/duplicate_standby.sh` v2.3:**

1. **Sekcja 8 (RMAN DUPLICATE)** — usunięte **2 SET parametry**:
   ```diff
   -    SET cluster_database_instances='1'    # RMAN-06581 niewspierane w 26ai
   -    SET audit_file_dest='/u01/app/oracle/admin/STBY/adump'  # deprecated w 26ai
   ```
   Zostawione: `cluster_database='FALSE'` (działa w SET clause).

2. **Sekcja 8b NOWA — post-duplicate ALTER SYSTEM SCOPE=SPFILE:**
   ```sql
   ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
   ALTER SYSTEM SET audit_file_dest='/u01/app/oracle/admin/STBY/adump' SCOPE=SPFILE;
   ```

3. **Sekcja 9 — refaktor: bounce + open RO + MRP:**
   ```diff
   -ALTER DATABASE OPEN READ ONLY;        # baza w MOUNTED po duplicate, można wprost
   +SHUTDOWN IMMEDIATE;                    # bounce zeby SPFILE params sie zaaplikowaly
   +STARTUP MOUNT;
   +ALTER DATABASE OPEN READ ONLY;
    ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
   ```
   Bounce wymagany żeby `cluster_database=FALSE` i `cluster_database_instances=1` realnie zaczęły obowiązywać (bez bounce baza dalej widzi `cluster_database=TRUE` z initSPFILE z RMAN duplicate).

**Hot-fix dla bieżącej sesji 26.04 (po RMAN-06581):**

```bash
# 1. STBY zostało w nomount po failed duplicate - shutdown
sqlplus / as sysdba <<<"SHUTDOWN ABORT;"

# 2. Skopiuj v2.3
scp <repo>/VMs/scripts/duplicate_standby.sh oracle@stby01:/tmp/scripts/

# 3. Re-run
nohup bash /tmp/scripts/duplicate_standby.sh > /tmp/dup.out 2>&1 &
```

**Lekcja:**
- **W 26ai RMAN DUPLICATE SET clause to ograniczona lista parametrów** vs 19c. Generalna reguła: w SET clause tylko parametry **kluczowe dla budowania bazy klona** (db_unique_name, file_name_convert, controlfiles, log_archive_*, fal_*). Wszystko po stronie cluster, audit, monitoring → post-duplicate ALTER SYSTEM SCOPE=SPFILE + bounce.
- **Test reguły:** jeśli parameter nie jest wymagany żeby DUPLICATE w ogóle ruszył (czyli wpływa na RECOVERY, db identity, lub destination paths), prawdopodobnie nie jest w whitelist SET. Cluster params, audit dest, monitoring dest → ZAWSZE post-duplicate.
- **Bounce po post-duplicate ALTER SYSTEM SCOPE=SPFILE** jest często konieczny — RMAN tworzy SPFILE z target+SET, ale runtime SGA z duplicate ma stare wartości (z target). Tylko bounce reload-uje SPFILE.

---

### FIX-042 — RAC primary → SI standby cleanup (instance_number, remote_listener, NIE thread)

**Kontekst:** Po FIX-041 (usunięcie `cluster_database_instances` z RMAN SET clause) drugi Claude zasugerował dodatkowe parametry. Krytyczna analiza pokazała 4 elementy:

| Sugestia | Werdykt | Dlaczego |
|----------|---------|----------|
| `SET cluster_database_instances='1'` | ❌ NIE | RMAN-06581 — to dokładnie to co rzuciło błąd (FIX-041); nie wspierane w 26ai SET clause |
| `SET thread='1'` | ❌ NIE | **Niebezpieczne dla SI standby z RAC primary.** SI standby aplikuje redo z OBU threads (thread 1 z PRIM1, thread 2 z PRIM2). `thread=1` zablokowałby apply thread 2 → data divergence. Parametr ma sens tylko dla SI primary → SI standby. |
| `SET instance_number='1'` | ✅ TAK | SPFILE z RMAN duplicate dziedziczy `instance_number` z target instance (1 lub 2 — zależy od którego node-a duplicate target się łączy). Wymuszenie =1 jest dobrą praktyką dla SI. **ALE** post-duplicate (nie w RMAN SET — bezpieczniej). |
| `UNSET remote_listener` w SPFILE | ✅ TAK | Primary ma `remote_listener='scan-prim.lab.local:1521'` (RAC dla SCAN registration). SI standby nie ma SCAN → bez sensu na stby01. **ALE** post-duplicate `RESET remote_listener` (czystsze niż UNSET w SET clause). |

**Empiryczna weryfikacja "thread=1 byłoby błędem":**

```sql
SELECT thread#, COUNT(*) FROM v$standby_log GROUP BY thread#;
-- thread 1: 4 SRL
-- thread 2: 4 SRL
-- TOTAL: 8 SRL = 4 per thread x 2 threads (RAC primary)
```

Standby ma 8 SRL (FIX-038 #5 sanity check) bo musi mieć osobne SRL dla każdego thread'a primary. Standby z `thread=1` apply tylko thread 1 redo, thread 2 redo zostawałoby w SRL bez aplikacji → MRP gap → data loss przy switchover.

**Reguła ogólna:** Dla **Physical Standby SI z RAC primary** thread parameter **MUSI pozostać UNSET** (default oznacza "wszystkie threads"). Tylko gdy primary też SI (1-thread), można explicite `thread=1` dla pełnej zgodności.

**Poprawka `scripts/duplicate_standby.sh` v2.4 (sekcja 8b):**

```sql
-- v2.3 (po FIX-041)
ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
ALTER SYSTEM SET audit_file_dest='/u01/app/oracle/admin/STBY/adump' SCOPE=SPFILE;

-- v2.4 (FIX-042) - dodane:
ALTER SYSTEM SET instance_number=1 SCOPE=SPFILE;       -- SI ma instance 1
ALTER SYSTEM RESET remote_listener SCOPE=SPFILE;        -- SI nie używa SCAN
-- UWAGA: NIE ustawiamy thread=1 (data divergence risk)
```

Bounce w sekcji 9 (już z FIX-041) zaaplikuje wszystko.

**Lekcja (uniwersalna):**
- **Verify każdą sugestię z innego źródła krytycznie** — nawet "Claude" może mieć 19c knowledge dla 26ai problemu. Empirycznie: `SHOW PARAMETER thread`, `v$standby_log GROUP BY thread#`, `lsnrctl status SCAN | grep Service`.
- **RAC primary → SI standby asymmetria:** parametry RAC (cluster_database, cluster_database_instances, instance_number) ZAWSZE zmieniaj na SI side; ale parametry redo flow (thread, log_file_name_convert) zostawiaj w SI default żeby nie ograniczyć MRP do jednego thread'a.
- **Post-duplicate ALTER SYSTEM SCOPE=SPFILE** to czystszy mechanizm niż RMAN SET clause — wspiera **wszystkie** parametry, nie tylko whitelist RMAN.

---

### FIX-043 — Active Duplicate w 26ai: primary node potrzebuje aliasu auxiliary w SWOIM tnsnames.ora

**Problem:** `duplicate_standby.sh v2.4` przeszedł przez sekcje 0-7, ruszył RMAN sekcji 8, alokował 8 channels (4+4), zaczął `Starting Duplicate Db at 2026-04-26 16:46:55`, ale natychmiast po pierwszej komendzie Memory Script padł:

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

**Diagnoza:** Klucz: error referencuje **prim01/prim02 ścieżkę** (`PRIM2_ora_65686.trc` w server diagnostic trace). Nie błąd na stby01. Co znaczy że **target instance (PRIM2 z RAC primary)** próbuje połączyć się do **auxiliary STBY** używając SWOJEGO tnsnames.ora — ale `STBY` aliasu tam nie ma.

**Active Database Duplicate w 26ai workflow:**
1. RMAN client (uruchomiony na stby01) łączy się do TARGET (PRIM przez SCAN) i AUXILIARY (STBY local)
2. RMAN target side (PRIM2 instance — wybrany przez SCAN load balancing) **otwiera direct connection do auxiliary** żeby streamować datafiles bezpośrednio
3. PRIM2 patrzy w `$ORACLE_HOME/network/admin/tnsnames.ora` na nodzie prim02 → szuka aliasu `STBY`
4. **Brak aliasu** → ORA-12154 → RMAN-03009 backup fail

W 19c i wcześniejszych 23ai Active Duplicate sometimes działał inaczej (RMAN client mediating całość). W 26ai/23.26.1 architektura aktywnego duplicate **wymaga**, by primary nodes mieli alias do auxiliary, bo robią own connection.

**Why nasz `duplicate_standby.sh` nie zadziałał:**
- Skrypt v2.0–v2.4 generował tnsnames.ora **tylko na stby01** (sekcja 3)
- prim01/prim02 nie miały aliasu STBY → ORA-12154 przy active duplicate

**Poprawka `scripts/duplicate_standby.sh` v2.5 — sekcja 3b NOWA:**

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

Dodatkowo dodany `tnsping STBY` z prim01 jako pre-RMAN sanity check.

**SERVICE_NAME=STBY (BEZ .lab.local):**
- Statyczna rejestracja w `SID_LIST_LISTENER` (sekcja 4) ma `GLOBAL_DBNAME=STBY` jako pierwszy SID_DESC
- W nomount mode `db_domain` nie jest jeszcze zaaplikowany (pfile→ pamięć, ale dynamic registration nieaktywna)
- Po duplicate (gdy `db_domain=lab.local` z initSTBY.ora obowiązuje) dynamic registration doda `STBY.lab.local`, ale w trakcie duplicate aktywny jest tylko static SID_LIST

**`(UR=A)` — Use Restricted = Allow:**
- Wymaga akceptacji connect do bazy w `RESTRICTED SESSION` mode (auxiliary w nomount często ma)
- Bez tego ORA-12526 "TNS:listener: all appropriate instances are in restricted mode"

**Wymóg SSH equivalency:**
Sekcja 3b wymaga ssh oracle@stby01 → oracle@prim01 i prim02 (bez hasła). FIX-038 (sekcja 5) już wymagała oracle@stby01 → oracle@prim01 dla scp pwfile. Sekcja 3b dodatkowo wymaga prim02 (analogicznie). User musi setup-ować SSH key dla obu primary nodes.

**Lekcja (uniwersalna dla Active Duplicate):**
- **Active Duplicate ≠ czysto klient-server** — primary nodes (target) robią own outbound connections do auxiliary. Wymagają lokalnego TNS resolution dla auxiliary.
- **Jeśli primary jest RAC, deploy alias na każdy node** — RMAN nie wie z którego node-a target będzie streamować (load balancing przez SCAN).
- **Test pre-RMAN: `tnsping <auxiliary>` z każdego primary node-a.** Jeśli timeout/no resolve → fix tnsnames PRZED ruszeniem duplicate.
- **W 19c era ten problem był rzadszy** — RMAN client często był na primary + szybsza forma duplicate (image copy). W 26ai service-based active duplicate z service-based restore wymaga peer-to-peer connection.

---

### FIX-044 — RMAN duplicate ASM→XFS: `db_create_file_dest` musi być w SET (nie tylko `db_file_name_convert`)

**Problem:** `duplicate_standby.sh v2.5/v2.6` w sekcji 8 RMAN duplicate. RMAN `restore clone from service 'PRIM' spfile` przeszedł, RMAN aux instance restartowała się ze sklonowanym SPFILE, alokowała 4+4 channels, **rozpoczęła restore datafiles**:

```
channel aux1: starting datafile restore from service ...
channel aux4: restoring datafile 00004 to +DATA      ← TARGET WCIĄŻ +DATA!
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

**Diagnoza:** stby01 (SI z lokalnym XFS, **bez ASM**) próbuje stworzyć datafile w ścieżce `+DATA` — ASM disk group z primary. Mimo że RMAN SET zawiera `db_file_name_convert='+DATA/PRIM','/u02/oradata/STBY'` w SPFILE.

**Why convert nie wystarczył:** `db_file_name_convert` mapuje **istniejące nazwy plików** przy restore (matching prefix → replace). Ale primary ma **`db_create_file_dest='+DATA'`** w SPFILE (Oracle Managed Files dla ASM). Klon dziedziczy z primary, więc **przy CREATE nowych plików** (controlfile mirror, online redo logs, nawet niektóre datafiles które RMAN tworzy z OMF semantyki) RMAN używa **`db_create_file_dest`** jako destination, ignorując `db_file_name_convert`.

Skutek: RMAN próbuje create datafile w `+DATA` (z `db_create_file_dest` skopiowanym z primary) → ORA-15001 disk group not mounted (na stby01 nie ma ASM).

**Workflow w 26ai active duplicate (kluczowe):**
1. `restore clone from service 'PRIM' spfile` — kopia SPFILE z primary
2. `alter system set db_unique_name='STBY' ...` + inne SET parametry **w nowym SPFILE klona**
3. Bounce auxiliary z nowym SPFILE
4. **`restore datafile`** — i tu RMAN używa **bieżącego SPFILE klona**:
   - `db_create_file_dest` → destination dla CREATE
   - `db_file_name_convert` → mapping istniejących nazw (z target)
   - Jeśli `db_create_file_dest` z primary nie został nadpisany w SET → klon próbuje pisać do `+DATA`

**Poprawka `scripts/duplicate_standby.sh` v2.7:**

W RMAN SET dodane **2 nowe parametry**:
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

Zmiany:
- **`db_create_file_dest='/u02/oradata/STBY'`** — Oracle Managed Files destination (CREATE nowych OMF idzie tutaj zamiast +DATA)
- **`db_create_online_log_dest_1='/u02/oradata/STBY'`** — destination dla online redo logs przy CREATE (primary ma w +DATA)
- **`db_file_name_convert` rozszerzony o parę `'+RECO/PRIM','/u03/fra/STBY'`** — niektóre pliki primary (np. flashback logs, archivelog) mogą być w +RECO, nie +DATA. 4-element list = 2 pary (źródło→cel).
- **`log_file_name_convert` analogicznie** — online redo i SRL.

**Rule of thumb dla RMAN duplicate ASM→XFS:**

| Parameter | Co robi | Wymagane? |
|-----------|---------|-----------|
| `db_file_name_convert` | Mapping nazw przy restore istniejących | ✅ TAK |
| `log_file_name_convert` | Mapping nazw redo/SRL przy restore | ✅ TAK |
| `db_create_file_dest` | Destination dla CREATE (OMF) — nowe datafiles, controlfile mirror | ✅ **TAK (often forgotten)** |
| `db_create_online_log_dest_1` | Destination dla online redo logs przy CREATE | ✅ TAK |
| `db_recovery_file_dest` | Destination FRA (archivelog, flashback) | ✅ TAK |
| `control_files` | Lista controlfile path-ów na klonie | ✅ TAK |

Brak któregokolwiek z `db_create_file_dest` / `db_create_online_log_dest_*` przy duplicate z ASM primary do non-ASM standby = ORA-15001 / ORA-19504.

**Lekcja:**
- **`db_file_name_convert` ≠ catch-all dla ASM→XFS migration.** Convert robi tylko mapping przy restore. CREATE używa `db_create_file_dest` (OMF) — i to musi być nadpisane osobno.
- **Sprawdź WSZYSTKIE `*_dest` parameters primary przed duplicate.** `SHOW PARAMETER dest` na primary i każdy ASM-pointing parameter musi mieć override w SET (lub `RESET ... SCOPE=SPFILE` post-duplicate).
- **Reguła: jeśli primary używa OMF z ASM, klon SI musi mieć cały zestaw destination overrides** w RMAN SET clause.

---

### FIX-045 — onlinelog dir + ORL/SRL recreate post-duplicate

**Problem:** RMAN duplicate v2.7 **zakończył się** (`Finished Duplicate Db at 2026-04-26 17:15:57`), datafiles skopiowane na `/u02/oradata/STBY/STBY/datafile/`, ALE w trakcie cleanup phase RMAN zwrócił **12 razy** ORA-00344:

```
Oracle error from auxiliary database: ORA-00344: unable to re-create online log
  '/u02/oradata/STBY/onlinelog/group_1.276.1231537649'
ORA-27040: file create error, unable to create file
Linux-x86_64 Error: 2: No such file or directory

RMAN-05535: warning: All redo log files were not defined properly.
```

12 logów: 4 ORL (groups 1-4) + 8 SRL (groups 11-14, 21-24). Wszystkie z wzorcem `+DATA/PRIM/onlinelog/group_X.YYY.ZZZZ` na primary (ASM-style names) → po convert mają być na `/u02/oradata/STBY/onlinelog/...`.

**Diagnoza:** **Podkatalog `/u02/oradata/STBY/onlinelog/` NIE ISTNIEJE**. Skrypt v2.7 sekcja 1 robił tylko:
```bash
mkdir -p /u01/app/oracle/admin/STBY/adump
mkdir -p /u02/oradata/STBY
mkdir -p /u03/fra/STBY
```

Convert mapuje **prefix** `+DATA/PRIM` → `/u02/oradata/STBY`. Pełna ścieżka primary `+DATA/PRIM/onlinelog/group_X` po convert daje `/u02/oradata/STBY/onlinelog/group_X`. RMAN próbuje create → parent dir nie istnieje → ORA-27040.

**Why RMAN nie auto-tworzy dir:** dla **datafiles** RMAN auto-tworzy podkatalogi przy CREATE OMF (widać po sukcesie `/u02/oradata/STBY/STBY/datafile/o1_mf_*.dbf`). Ale dla **online logs / SRL** OMF mode jest restrictive — tworzy plik tylko jeśli parent dir istnieje. Z `db_file_name_convert` (nie OMF auto-naming dla logs), parent musi być pre-created.

**Skutek:** Standby jest MOUNTED z datafiles, **ALE bez ORL i SRL**. `ALTER DATABASE OPEN READ ONLY` może się otworzyć (datafiles OK), ALE `RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE` → **fail bez SRL** (real-time apply wymaga SRL).

**Plus 2 niekrytyczne errors w sekcji 8b (cleanup):**

```
ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
ERROR at line 1: ORA-02065: illegal option for ALTER SYSTEM
```

**SI standby nie ma parametru `cluster_database_instances`** (tylko RAC). Default implicit = 1. Linia jest zbędna. Tolerowane przez `WHENEVER SQLERROR CONTINUE`, ale czyściej pominąć.

```
ALTER SYSTEM RESET remote_listener SCOPE=SPFILE;
ERROR at line 1: ORA-32010: cannot find entry to delete in SPFILE
```

**RMAN convert wyzerował `remote_listener` w SPFILE klona** (lub primary nie miało w SPFILE explicit value). RESET nie ma czego usunąć. OK, niekrytyczne.

**Poprawka `scripts/duplicate_standby.sh` v2.8:**

1. **Sekcja 1:** dodane `mkdir -p /u02/oradata/STBY/onlinelog`

2. **Sekcja 8b:** usunięte `ALTER SYSTEM SET cluster_database_instances=1` i bezwarunkowy `RESET remote_listener`. Zamiast tego conditional RESET przez PL/SQL block:
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

3. **Sekcja 8c NOWA — recreate ORL i SRL** (po sekcji 8b, przed sekcją 9 bounce+open RO):
   - SHUTDOWN ABORT + STARTUP MOUNT
   - `CLEAR UNARCHIVED LOGFILE GROUP X` + `DROP LOGFILE GROUP X` dla 4 ORL (1,2,3,4) i 8 SRL (11-14, 21-24)
   - `ADD LOGFILE THREAD N GROUP X ('/u02/oradata/STBY/onlinelog/redo0X.log') SIZE 200M REUSE` × 4 ORL
   - `ADD STANDBY LOGFILE THREAD N GROUP X ('...srlXY.log') SIZE 200M REUSE` × 8 SRL

**Hot-fix dla bieżącej sesji 26.04 (po duplicate v2.7 z błędami):**

```bash
# Manual recreate (skrypt v2.8 ma to wbudowane, ale tu już zrobione duplicate)
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

**Lekcja (uniwersalna):**
- **`db_file_name_convert` mapuje prefix, ale parent dir musi istnieć.** Dla datafiles RMAN OMF semantyka tworzy katalogi. Dla online logs/SRL — nie. Pre-create podkatalog `onlinelog/` w skrypcie OS prep.
- **RMAN `Finished Duplicate Db` ≠ sukces.** Sprawdzaj `RMAN-05535: warning: All redo log files were not defined properly.` jako sygnał że logs/SRL nie utworzone — bo bez nich MRP USING CURRENT LOGFILE nie ruszy.
- **SI nie ma `cluster_database_instances` parametru.** Próba ALTER SYSTEM SET na SI = ORA-02065. Default implicit = 1, nie ustawiamy.
- **`ALTER SYSTEM RESET <param>` zwraca ORA-32010 jeśli `<param>` nie ma w SPFILE.** Sprawdzaj `v$spparameter WHERE name=... AND isspecified='TRUE'` przed RESET, lub use PL/SQL block z exception handling.

---

### FIX-046 — Bug logiczny: tnsping STBY w sekcji 3b PRZED listener start (sekcja 4)

**Problem:** `duplicate_standby.sh v2.8` w czystym rebuild padł na końcu sekcji 3b:

```
[17:27:54]   Test tnsping STBY z prim01 (sanity przed RMAN)...
TNS-12541: Cannot connect. No listener at host 192.168.56.13 port 1521.
 TNS-12560: Database communication protocol error.
  TNS-00511: No listener
   Linux Error: 111: Connection refused
[17:27:54] ERROR: tnsping STBY z prim01 FAIL - aliasu nie ma lub stby01 listener niedostepny
```

**Diagnoza:** Bug logiczny w kolejności sekcji v2.6+:
- Sekcja 3: tnsnames.ora local na stby01
- **Sekcja 3b**: deploy STBY alias na prim01/02 + **tnsping STBY z prim01** ← TUTAJ
- Sekcja 4: listener.ora + **lsnrctl start** na stby01 ← LISTENER STARTUJE DOPIERO TUTAJ

`tnsping STBY` z prim01 łączy się do `stby01.lab.local:1521`. Listener stby01 jeszcze nie startuje (sekcja 4 po sekcji 3b) → connection refused.

W v2.6 założenie było że alias deploy + tnsping można razem zrobić. Faktycznie alias deploy działa (kopiuje plik, grep verify OK), ale tnsping wymaga **fizycznie nasłuchującego listenera** na drugim końcu — który startuje dopiero w sekcji 4.

**Poprawka `scripts/duplicate_standby.sh` v2.9:**

1. **Sekcja 3b**: usunięty tnsping. Zostaje tylko `deploy_stby_alias prim01/prim02` + grep verify.

2. **Sekcja 4** (po `lsnrctl start`): dodany tnsping STBY z prim01 jako post-listener-start sanity:
   ```bash
   log "  Test tnsping STBY z prim01 (sanity przed RMAN)..."
   TNSPING_OUT=$(ssh oracle@prim01 ". ~/.bash_profile && tnsping STBY 2>&1" || true)
   echo "$TNSPING_OUT" | tail -5
   echo "$TNSPING_OUT" | grep -q "^OK" || \
       die "tnsping STBY z prim01 FAIL po lsnrctl start - sprawdz alias prim01 lub network"
   ```

Uzasadnienie: tnsping testuje 2 rzeczy — (a) tnsnames.ora alias resolve, (b) network to listener. (a) testuje grep w sekcji 3b. (b) wymaga listener up, więc test musi być PO sekcji 4. Rozdzielenie sanity dwóch warstw na dwa miejsca (alias verify, network verify) eliminuje false-fail.

**Lekcja (uniwersalna):**
- **`tnsping` testuje 2 warstwy: TNS resolution + TCP connect.** Jeśli alias jest deployed ale listener nie up → false-fail. Rozdzielaj testy: `grep` na alias plik (TNS resolution OK), `tnsping` po listener startup (TCP+listener OK).
- **Kolejność sekcji w długich skryptach DBA** musi respektować dependencies. Lista dependencies dla każdej sekcji w komentarzu na początku skryptu pomaga znaleźć takie buggy reordering.
- **Jeśli sanity check fail-uje konsekwentnie po reorderingu skryptu** — zerknij czy zależność (np. listener up) była zapewniona w sekcji wcześniejszej.

---

### FIX-047 — Brakujący `/u03/fra/STBY/onlinelog/` + `standby_file_management=AUTO` blokuje DROP LOGFILE

**Problem:** `duplicate_standby.sh v2.9` w sekcji 8c (recreate ORL/SRL) padł 12× na CLEAR + DROP:

```
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 1
ORA-00344: unable to re-create online log '/u03/fra/STBY/onlinelog/group_1.263.1231537653'
ORA-27040: file create error, unable to create file
Linux-x86_64 Error: 2: No such file or directory

ALTER DATABASE DROP LOGFILE GROUP 1
ORA-01275: Operation DROP LOGFILE is not allowed if standby file management is automatic.
```

**Diagnoza:** dwa problemy spotkały się w sekcji 8c:

1. **Brakujący katalog `/u03/fra/STBY/onlinelog/`.** FIX-045 utworzył tylko `/u02/oradata/STBY/onlinelog/`. Convert pair w RMAN SET to `+DATA/PRIM,/u02/oradata/STBY,+RECO/PRIM,/u03/fra/STBY` — RMAN przy CREATE online log dla każdej grupy umieszcza member 1 w `/u02/...` i member 2 w `/u03/fra/STBY/onlinelog/...` (multiplexed). Member 2 nie ma parent dir → ORA-27040.

2. **`standby_file_management=AUTO` blokuje manualny DROP LOGFILE.** RMAN SET ustawił `SET standby_file_management='AUTO'`. Z AUTO Oracle nie pozwala na ręczny DROP LOGFILE (ORA-01275) — wymaga przełączenia na MANUAL na czas operacji.

**Poprawka `scripts/duplicate_standby.sh` v3.0:**

1. **Sekcja 1**: dodane `mkdir -p /u03/fra/STBY/onlinelog`:
   ```bash
   mkdir -p /u02/oradata/STBY/onlinelog        # FIX-045
   mkdir -p /u03/fra/STBY
   mkdir -p /u03/fra/STBY/onlinelog            # FIX-047: convert mapuje +RECO -> /u03/fra
   ```

2. **Sekcja 8c**: dodane `ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH` PRZED CLEAR/DROP, oraz `=AUTO` PO ADD LOGFILE (przywracamy bo AUTO jest wymagane przy apply gdy primary doda nowe datafile):
   ```sql
   ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH;
   ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 1; ... GROUP 4;
   ALTER DATABASE DROP LOGFILE GROUP 1; ... GROUP 4;
   ALTER DATABASE DROP STANDBY LOGFILE GROUP 11; ... GROUP 24;
   -- ADD LOGFILE THREAD 1/2 + ADD STANDBY LOGFILE THREAD 1/2
   ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH;
   ```

**Runbook ręczny (po FIX-047 odpalonym na bazie ktora juz przeszla RMAN duplicate, zeby nie powtarzac 5 min restore):**

```bash
# Na stby01 jako oracle
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

-- Sekcja 9 manualnie: open + start MRP
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;

-- Verify
SELECT name, db_unique_name, database_role, open_mode, protection_mode FROM v$database;
SELECT process, status FROM v$managed_standby WHERE process IN ('MRP0','RFS') ORDER BY process;
SQL
```

**Lekcja (uniwersalna):**
- **`db_file_name_convert` z parą `+RECO/PRIM,/u03/fra/STBY` powoduje że Oracle przy CREATE online log umieszcza multiplexed members w `/u03/fra/STBY/onlinelog/`.** Trzeba przygotować ten katalog razem z `/u02/.../onlinelog/`. RMAN auto-tworzy parent dirs dla datafile podczas restore, ale NIE dla online logs przy CREATE LOGFILE.
- **`standby_file_management=AUTO` w trakcie operacji ręcznych na logfiles → ORA-01275.** Bezpieczny pattern: `MANUAL` przed manipulacjami, `AUTO` po. NIE zostawiać MANUAL — primary może w przyszłości dodać datafile (e.g. ALTER TABLESPACE ... ADD DATAFILE) i z MANUAL na standby Oracle nie utworzy lokalnego datafile → MRP staje.

---

### FIX-048 — ORA-00918 STATUS column ambiguously specified w verify query sekcji 8c

**Problem:** `duplicate_standby.sh v3.0` po pomyślnym recreate ORL+SRL (FIX-045+047) padł na verify query:

```sql
SELECT thread#, group#, type, status FROM v$logfile l, v$log lv
                              *
ERROR at line 1:
ORA-00918: STATUS: column ambiguously specified - appears in V$LOG and V$LOGFILE
```

`WHENEVER SQLERROR EXIT FAILURE` było aktywne → sqlplus exit code 1 → `set -e` w skrypcie zabił go PRZED sekcją 9 (bounce + OPEN RO + start MRP). Stan bazy był OK (recreate skończony, AUTO przywrócone), ale brakowało otwarcia + apply.

**Diagnoza:** kolumna `status` istnieje w **obu** widokach:
- `v$logfile` ma `status` (INVALID/STALE/DELETED/IN USE) — info o pliku
- `v$log` ma `status` (UNUSED/CURRENT/ACTIVE/INACTIVE) — info o grupie

Join `v$logfile l, v$log lv WHERE l.group#=lv.group#` zostawia niejednoznaczność który `status` wybrać.

**Poprawka `scripts/duplicate_standby.sh` v3.1:**

Rozdzielone na 2 query bez join (czystsze niż prefiksy aliasów; ORL i SRL to dwa różne widoki, łatwiej je traktować osobno):

```sql
SELECT thread#, group#, bytes/1024/1024 AS mb, status FROM v$log ORDER BY thread#, group#;
SELECT thread#, group#, bytes/1024/1024 AS mb, status FROM v$standby_log ORDER BY thread#, group#;
SELECT COUNT(*) AS srl_total FROM v$standby_log;
```

**Recovery dla obecnego runa (gdy skrypt już padł na FIX-048):** stan bazy jest OK (MOUNT, ORL/SRL recreated, AUTO przywrócone). Wystarczy ręcznie odpalić sekcję 9:

```sql
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;   -- jeśli MRP biega z poprzedniej próby (ORA-10456)
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
```

**Lekcja (uniwersalna):**
- **Verify queries pod `WHENEVER SQLERROR EXIT FAILURE` muszą być przetestowane.** Bug w SELECT (ORA-00918, ORA-00904, ORA-00942) zabija skrypt — i to po wykonaniu zmian transakcyjnych (recreate w tym wypadku), więc nie ma "rollback do bezpiecznego stanu". Verify lepiej wstawiać po `WHENEVER SQLERROR CONTINUE` (verify to read-only, nie powinno zabijać skryptu).
- **Join na `v$log + v$logfile` przez `group#` zawsze prowokuje ORA-00918 jeśli SELECT zawiera kolumny współdzielące nazwy.** Bezpieczniejsze: 2 osobne query albo prefiksy.
- **`v$log.status` vs `v$logfile.status` to różne enumeracje** — myli się je przy szybkim debugu. `v$log` o grupie (CURRENT/ACTIVE), `v$logfile` o pliku (INVALID/STALE).

---

### FIX-049 — `log_archive_dest_2` na primary nie był automatyzowany przez skrypt → MRP `WAIT_FOR_LOG` w nieskończoność

**Problem:** Po DONE skryptu `duplicate_standby.sh v3.1`, MRP na stby01 stał w stanie:
```
PROCESS   STATUS                  THREAD#  SEQUENCE#
MRP0      WAIT_FOR_LOG                  1         30
```

Brak RFS process, `v$archived_log` puste, `v$dataguard_stats apply lag` puste. Diagnostyka na primary:

```sql
SELECT dest_id, status FROM v$archive_dest_status WHERE dest_id IN (1,2);
   DEST_ID STATUS
         1 VALID
         2 INACTIVE        ← log_archive_dest_2 puste

SHOW PARAMETER log_archive_dest_2
log_archive_dest_2                   string         ← brak wartości
```

Primary nie miał skonfigurowanego transportu → MRP czekał na sequence 30 którą primary nigdy nie wysłał.

**Diagnoza:** Skrypt `duplicate_standby.sh` automatyzował tylko stronę **auxiliary** (STBY): tnsnames, listener.ora, init.ora, RMAN duplicate, ORL/SRL recreate, OPEN+MRP. Strona **primary** (PRIM) musi mieć:
```sql
ALTER SYSTEM SET log_archive_dest_2='SERVICE=STBY ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILE,PRIMARY_ROLE) DB_UNIQUE_NAME=STBY' SCOPE=BOTH SID='*';
ALTER SYSTEM SET log_archive_dest_state_2='ENABLE' SCOPE=BOTH SID='*';
```

Doc 09 sekcja 4.2 to opisywał, ale jako **manual step** PRZED RMAN duplicate. To było źle z dwóch powodów:
1. Easy to skip przy szybkim runie skryptu
2. Wykonanie PRZED RMAN duplicate → STBY listener jeszcze nie startuje → `v$archive_dest_status STATUS=ERROR` (mylący komunikat)

**Poprawka `scripts/duplicate_standby.sh` v3.2:**

Nowa **sekcja 9b** PO start MRP na STBY (sekcja 9), PRZED finalnym DONE log:

```bash
log "Sekcja 9b — Konfiguracja log_archive_dest_2 na primary (FIX-049)..."
ssh -o StrictHostKeyChecking=no oracle@prim01 \
    ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<'EOF'
ALTER SYSTEM SET log_archive_dest_2='SERVICE=STBY ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILE,PRIMARY_ROLE) DB_UNIQUE_NAME=STBY' SCOPE=BOTH SID='*';
ALTER SYSTEM SET log_archive_dest_state_2='ENABLE' SCOPE=BOTH SID='*';
ALTER SYSTEM ARCHIVE LOG CURRENT;
SELECT dest_id, status, error, gap_status FROM v$archive_dest_status WHERE dest_id IN (1,2);
EOF
```

Dlaczego ASYNC NOAFFIRM, nie SYNC AFFIRM? **MaxPerformance baseline** jest standard dla świeżego standby (apply lag tolerable, primary nie blokuje na commit). MaxAvailability (SYNC AFFIRM) włączy się dopiero w doc 10 przez DG broker `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability` — broker sam zmienia parametry. Manualne SYNC AFFIRM przed brokerem → konflikt zarządzania.

**Poprawka `09_standby_duplicate.md` sekcja 4.2:**
- Box `📌 FIX-049`: "Skrypt v3.2+ robi to automatycznie w sekcji 9b. Jeśli ręcznie — wykonaj PO RMAN duplicate + start MRP, nie przed."
- Zmienione SYNC AFFIRM → ASYNC NOAFFIRM (z uzasadnieniem: doc 10 sam przełączy)
- Dodany SID='*' (RAC: rozsyła na obie instancje)

**Wynik na user environment** po ręcznym wykonaniu sekcji 9b:
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

**Lekcja (uniwersalna):**
- **Active duplicate skrypty domyślnie konfigurują tylko aux side.** Łatwo pominąć fakt że primary też wymaga konfiguracji (`log_archive_dest_2`, opcjonalnie `db_file_name_convert` na primary dla switchover-readiness). Skrypt klastrowy musi obsłużyć **obie strony**.
- **Kolejność: STBY OPEN+MRP gotowe → DOPIERO konfiguracja primary log_archive_dest_2.** Jeśli odwrotnie (dest_2 ENABLE przed OPEN STBY) → primary ARCH/LGWR nie może się połączyć → STATUS=ERROR, alert.log spamowany ORA-12541. Wygląda jak failure ale to tylko stale kolejność.
- **MaxPerformance (ASYNC NOAFFIRM) baseline, MaxAvailability (SYNC AFFIRM) przez DG broker.** Nie ustawiać SYNC AFFIRM manualnie przed broker enable — broker zarządza tym parametrem i nadpisze, ale w trakcie konfliktu możliwe blokady commit-u.

---

### FIX-050 — `duplicate_standby.sh` v3.3: aliasy `PRIM_ADMIN`/`STBY_ADMIN` + `LISTENER_DGMGRL` 1522

**Problem:** po `duplicate_standby.sh` v3.2 stby01 i prim01/02 nie miały aliasów `PRIM_ADMIN`/`STBY_ADMIN` w tnsnames, ani listener `LISTENER_DGMGRL` na port 1522 — wymagane przez `configure_broker.sh` (doc 10) i `setup_observer_infra01.sh` (doc 11). Skrypt v3.2 nadpisywał listener.ora i tnsnames.ora bez tych elementów (doc 07 sekcja 8 zostawiał je przy świeżej instalacji DB software, ale RMAN flow je tracił).

**Diagnoza po doc 09 17:55:**
- tnsnames stby01: `PRIM`, `STBY`, `PRIM_DGMGRL`, `STBY_DGMGRL` — brak `PRIM_ADMIN`, `STBY_ADMIN`
- tnsnames prim01/02: `STBY`, `STBY_DGMGRL` (z sekcji 3b v3.2) — brak `PRIM_ADMIN`, `STBY_ADMIN`
- listener stby01: tylko `LISTENER` na 1521, brak `LISTENER_DGMGRL` 1522 (doc 07 sekcja 8.1 to miał)
- `configure_broker.sh` v1.0 wywołuje `dgmgrl @PRIM_ADMIN` i `sqlplus @STBY_ADMIN` → TNS-12154 alias not found

**Poprawka `scripts/duplicate_standby.sh` v3.3:**

1. **Sekcja 3** (tnsnames stby01) — dopisane `PRIM_ADMIN` (port 1522, prim01+prim02 ADDRESS_LIST, SERVICE_NAME=PRIM_DGMGRL UR=A) i `STBY_ADMIN` (port 1522, stby01, SERVICE_NAME=STBY_DGMGRL UR=A). Wzorzec z doc 07 sekcja 8.

2. **Sekcja 3b** — `STBY_ALIAS_FRAGMENT` → `DGMGRL_ALIAS_FRAGMENT` (rozszerzony o `PRIM_ADMIN` i `STBY_ADMIN`). Funkcja `deploy_stby_alias` przemianowana na `deploy_dgmgrl_aliases`. Idempotency check teraz na `^STBY_ADMIN[[:space:]]*=` (pełen zestaw zamiast tylko STBY).

3. **Sekcja 4** (listener.ora stby01) — dopisana druga sekcja `LISTENER_DGMGRL` na port 1522 + `SID_LIST_LISTENER_DGMGRL` z GLOBAL_DBNAME=STBY_DGMGRL. Dodano `lsnrctl start LISTENER_DGMGRL` po `lsnrctl start`.

**Firewall:** w lab disabled (decyzja user-a 2026-04-26). Skrypt nie wywołuje `firewall-cmd`. Dla produkcji odkomentuj komentarz w skrypcie (port 1522).

**Runbook PATCH (chodzące środowisko po doc 09):**

```bash
# 1. tnsnames stby01 + prim01/02 (jako oracle, append do $ORACLE_HOME/network/admin/tnsnames.ora)
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
# Analogicznie dla prim01 i prim02 — append do /u01/app/oracle/product/23.26/dbhome_1/network/admin/tnsnames.ora

# 2. listener.ora stby01 + start LISTENER_DGMGRL (jako oracle)
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

# 3. listener.ora prim01/02 (jako grid, Grid Home) — manual w doc 10 sekcja 1.1
```

**Lekcja (uniwersalna):**
- **Skrypty „rebuild from scratch" muszą zostawić środowisko gotowe na NASTĘPNY krok pipeline-u**, nie tylko na ten w którym są opisane. `duplicate_standby.sh` był skrojony pod doc 09 (RMAN duplicate) i zostawiał stan dobry dla doc 09 — ale tracił elementy potrzebne w doc 10 (broker). Dziś końcowy plik listener.ora i tnsnames.ora to 50% scope skryptu — tnsnames i listener config są **shared resources** używane przez wszystkie kolejne dokumenty.
- **`SERVICE_NAME` w SID_LIST_LISTENER nie respektuje db_domain** — używa `GLOBAL_DBNAME` wprost. Dlatego `STBY_DGMGRL` (bez `.lab.local`) jest tu poprawne, w przeciwieństwie do `STBY.lab.local` które wymagało db_domain handling.

---

### FIX-051 — `configure_broker.sh` v2.0: pre-flight + verify SUCCESS + die-on-fail

**Problem:** v1.0 (64 linie) miało lukę bezpieczeństwa:
- Brak pre-flight (tnsping aliasów, listener 1522 status, role check, FORCE_LOGGING)
- `dgmgrl <<EOF ... EOF` bez capture stdout → brak verify "Configuration Status: SUCCESS"
- Brak verify SYNC AFFIRM po `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability`
- Cichy fail przy ORA-12154 (PRIM_ADMIN nie istnieje) — exit 0 + `log "DONE"`

**Poprawka `scripts/configure_broker.sh` v2.0 (przepisanie, ~250 linii):**

1. **Sekcja 0 — pre-flight (HARD die-on-fail):**
   - `whoami=oracle`, `hostname=prim01`
   - `SQL_DIR=${SQL_DIR:-/tmp/sql}` istnieje + `fsfo_check_readiness.sql` w nim
   - `tnsping PRIM_ADMIN` i `STBY_ADMIN` — die z hint do doc 10 sekcja 1.1 (manual deploy listener Grid Home)
   - Wywołanie `<repo>/sql/fsfo_check_readiness.sql` → grep FAIL na krytycznych checks (force_logging, archivelog, flashback, broker)
   - SSH oracle@stby01 sanity: PHYSICAL STANDBY, READ ONLY WITH APPLY

2. **Sekcja 1 — dg_broker_start=TRUE** na PRIM (SID='*', RAC) i STBY (przez `@STBY_ADMIN`). Sleep 15. Verify DMON via `gv$managed_standby` count ≥ 1.

3. **Sekcja 2 — CREATE/ADD/ENABLE z verify**:
   - Idempotentnie: jeśli `SHOW CONFIGURATION` daje SUCCESS, skip CREATE+ADD+ENABLE (verify-only mode).
   - Output do `/tmp/dgmgrl_enable.log`, `grep -q "Configuration Status:.*SUCCESS"` → die jeśli brak.

4. **Sekcja 3 — MaxAvailability + verify SYNC AFFIRM**:
   - `EDIT DATABASE PRIM/STBY SET PROPERTY LogXptMode='SYNC'` + `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability`
   - Output do `/tmp/dgmgrl_maxavail.log`
   - Verify dwustopniowy: dgmgrl SHOW CONFIGURATION zawiera "Protection Mode: MaxAvailability" + "Configuration Status: SUCCESS"
   - Verify SQL: `v$archive_dest dest_id=2 transmit_mode=SYNCHRONOUS, affirm=YES` — die jeśli broker nie zmienił automatycznie

**Lekcja (uniwersalna):**
- **Pre-flight must die-on-fail** — `set -e` w bashu nie wystarczy, bo `dgmgrl` zwraca exit 0 mimo ORA-12154 w stdout. Trzeba capture do logu i grep na expected pattern.
- **Idempotentność broker** — `SHOW CONFIGURATION` przed `CREATE` pozwala re-run skryptu po częściowym fail bez REMOVE CONFIGURATION.
- **DG broker zarządza `log_archive_dest_2` automatycznie po `SET PROTECTION MODE`** — nie ustawiać SYNC AFFIRM ręcznie przed brokerem (FIX-049 ustawia ASYNC NOAFFIRM jako MaxPerformance baseline, broker przełącza na SYNC AFFIRM przy MaxAvailability).

---

### FIX-052 — `deploy_tac_service.sh` v1.1: pre-flight `tac_full_readiness.sql` + de-hardcode + post-flight verify

**Problem:** v1.0 (71 linii):
- Brak pre-flight (PRIM OPEN check, APPPDB registered, TAC readiness)
- Hardcoded `stby01.lab.local:6200` w `srvctl modify ons -remoteservers`
- Brak post-flight verify że TAC parametry faktycznie zostały zapisane

**Poprawka `scripts/deploy_tac_service.sh` v1.1:**

1. **Sekcja 0 pre-flight:**
   - `srvctl status database -db PRIM` → "Instance PRIM1/PRIM2 is running" (die jeśli brak)
   - `lsnrctl services | grep -E "Service \"APPPDB"` (die jeśli PDB niezarejestrowane)
   - `sqlplus @${SQL_DIR}/tac_full_readiness.sql` (12 checks) — heurystyka: ≥8 PASS na go-live, die jeśli krytyczne checks (FORCE_LOGGING, archivelog, EE, broker, TAC service, commit_outcome) FAIL

2. **De-hardcode** STBY_HOST:
   ```bash
   STBY_HOST=$(ssh oracle@stby01 hostname -f 2>/dev/null || echo stby01.lab.local)
   srvctl modify ons -clusterid PRIM -remoteservers "${STBY_HOST}:6200"
   ```

3. **Post-flight verify** (sekcja 3):
   - `srvctl config service -db PRIM -service MYAPP_TAC` → grep `failover_type:.*TRANSACTION` + `commit_outcome:.*true` (case-insensitive). Die jeśli brak.

**Lekcja (uniwersalna):**
- **`srvctl add service` zwraca exit 0 nawet gdy parametr został zignorowany** (np. `-failovertype` w starszej wersji srvctl). Post-flight `srvctl config service` + grep na expected wartości to jedyna pewna walidacja.
- **De-hardcode hostnames** — nawet w lab przyzwyczajenie do `$(ssh node hostname -f)` chroni przed pomyłką gdy hostname się zmieni (rebrand / migracja).

---

### FIX-053 — `setup_observer_infra01.sh` v1.1: die-on-fail + observer name variable + post-flight verify

**Problem:** v1.0 (193 linii):
- `|| log "WARN"` przy dgmgrl commands (FSFO properties, ADD OBSERVER, ENABLE FAST_START FAILOVER) → cichy fail, skrypt zwraca exit 0 nawet gdy FSFO Status=DISABLED
- Hardcoded `obs_ext` w 6 miejscach — utrudnia setup backup observers (`obs_dc`, `obs_dr`) z doc 16 (gdzie wcześniej musiało się ręcznie copy+sed skryptu)
- Brak post-flight verify (FSFO ENABLED, systemctl active)

**Poprawka `scripts/setup_observer_infra01.sh` v1.1:**

1. **Wszystkie `|| log "WARN"` → `|| die`** dla critical commands (FSFO properties, ADD OBSERVER, SET MASTEROBSERVER, ENABLE FAST_START FAILOVER, sqlplus connectivity test).

2. **Pre-flight tnsping** (po wallet setup):
   - `tnsping PRIM_ADMIN` i `STBY_ADMIN` z infra01 — die z hint do doc 10 sekcja 1.1 (listener Grid Home) i `duplicate_standby.sh` v3.3+ (listener stby01 + aliasy).

3. **Observer name variable**:
   ```bash
   OBSERVER_NAME="${OBSERVER_NAME:-obs_ext}"
   ```
   Wszystkie `obs_ext` w ADD OBSERVER, SET MASTEROBSERVER, systemd unit name, log file path, ExecStart/ExecStop → `${OBSERVER_NAME}`. Override-able dla doc 16:
   ```bash
   OBSERVER_NAME=obs_dc sudo bash setup_observer_infra01.sh   # backup observer na infra01 lub innej VM
   ```

4. **Post-flight verify** (sekcja 9):
   - `dgmgrl SHOW FAST_START FAILOVER` zawiera `Status: ENABLED` (regex matchuje też wariant "Fast-Start Failover: ENABLED")
   - `systemctl is-active --quiet dgmgrl-observer-${OBSERVER_NAME}` (boolean check)
   - Die z hint `journalctl -u <unit>` jeśli systemd nie active.

**Lekcja (uniwersalna):**
- **`|| log "WARN"` w skrypcie produkcyjnym to debt** — albo error jest niegroźny i nie powinno być warna, albo jest groźny i należy die. "warn-and-continue" maskuje problemy które ujawnią się w doc 14 testach (np. "FSFO nie failoveruje — ale skrypt mówił DONE!").
- **Variables zamiast hardcode** — nawet jeśli default wystarczy w 99% przypadków, override-able pattern eliminuje cały duplicate-and-modify boilerplate.

---

### FIX-054 — `validate_env.sh` v1.1: SQL_DIR wrapper + `--quick`/`--full`

**Problem:** v1.0 (44 linie) wywoływał nieistniejący `bash/validate_all.sh` z `PROJECT_DIR/bash/`. Martwy link.

**Poprawka `scripts/validate_env.sh` v1.1 (przepisanie ~70 linii):**

- Cienki wrapper na `<repo>/sql/*.sql` z `SQL_DIR=${SQL_DIR:-/tmp/sql}`
- Argument parsing: `--quick` (default) / `--full`, `-t PRIM|STBY` (default PRIM)
- **--quick:** `validate_environment.sql` (12 checks combined FSFO+TAC). Heurystyka exit: count `\bFAIL\b` w output, die jeśli ≥1.
- **--full:** dodatkowo `tac_full_readiness.sql` + `fsfo_monitor.sql` + `fsfo_broker_status.sql` → `${REPORTS_DIR:-/tmp/reports}/<sql>_<target>_<timestamp>.log`.
- Connect: PRIM = `/ as sysdba`, STBY = `sys/Welcome1#SYS@STBY_ADMIN as sysdba`.

**Lekcja:** **martwe linki w MD są kosztem pamięciowym** — operator widzi referencję do skryptu który nie istnieje, traci 10 min sprawdzając. Cleanup w trakcie sync MD-skrypt.

---

### FIX-055 — Rename HH→DC, OE→DR w 4 plikach MD VMs/

**Cel:** zunifikować nazewnictwo ośrodków (Data Center / Disaster Recovery / EXT) z konwencją produkcyjną. Whitelist: `08_database_create_primary.md:210` (`Bez HR/SH/OE/PM` to Sample Schemas Order Entry, nie ośrodek).

**Pliki zmienione:**
- `00_architecture.md` (sekcja 2.1 sites): `Site HH` → `Site DC`, `Site OE` → `Site DR`, `obs_hh` → `obs_dc`, `obs_oe` → `obs_dr`
- `LOG.md`: 3-site MAA topology mentions
- `PLAN-dzialania.md`: 6 wystąpień (VM3 description, mapping tabela, observers row, sample schemas, branching diagram)
- `16_extensions.md`: sekcja A (backup observers) — całość przeszła `obs_hh`/`obs_oe` → `obs_dc`/`obs_dr` w komendach mkdir/wallet/systemd/dgmgrl

**Poza scope (świadomie):** rename w `<repo>/sql/`, `<repo>/docs/`, `<repo>/README.md`. Te pozostają z `HH`/`OE` (lab dokumentuje uproszczenie z produkcji, gdzie nazwy mogą być inne). User: "Tylko VMs/, sql/ traktuj jako <repo> read-only".

**Lekcja:** rename w narrative-heavy MD-ach przez sed-a globalnego niebezpieczne. Whitelist linii (Sample Schema OE) pokazuje że terminy jak HH/OE/DR/DC mają wiele kontekstów. Bezpieczniejsze: targeted Edit z czytelnym kontekstem (przed/po fragment).

---

### FIX-056 — `<repo>/sql/` integracja w skryptach VMs/scripts/ + SQL_DIR convention

**Cel:** wykorzystać 8 dojrzałych SQL-i (`fsfo_check_readiness`, `fsfo_configure_broker`, `tac_full_readiness`, `validate_environment`, `fsfo_monitor`, `fsfo_broker_status`, `tac_replay_monitor`, `tac_configure_service_rac`) jako pre-flight + post-flight engines w bash skryptach. Bez powielania logiki.

**Konwencja:**

- **Skrypty bash (na VM):** `SQL_DIR="${SQL_DIR:-/tmp/sql}"` — default `/tmp/sql`, override-able. Każdy skrypt waliduje `[[ -d $SQL_DIR ]]` i die z hint do doc 04 sekcja 0.
- **Dokumenty MD (na hoście):** `<repo>/sql/` (gdzie `<repo>` = `D:/__AI__/_oracle_/20260423-FSFO-TAC-guide/`).

**Mapowanie:**

| SQL | Używany w | Cel |
|---|---|---|
| `fsfo_check_readiness.sql` | `configure_broker.sh` v2.0 sekcja 0 | Pre-flight broker (6 sekcji) |
| `tac_full_readiness.sql` | `deploy_tac_service.sh` v1.1 sekcja 0 | Pre-flight TAC (12 checks) |
| `validate_environment.sql` | `validate_env.sh --quick` | 12 checks FSFO+TAC combined |
| `fsfo_monitor.sql`, `fsfo_broker_status.sql` | `validate_env.sh --full` | Diagnostyka post-deploy |
| `fsfo_configure_broker.sql`, `tac_configure_service_rac.sql` | (potencjalnie `--dry-run`) | Generatory komend dgmgrl/srvctl |
| `tac_replay_monitor.sql` | (manual w doc 14) | Replay statistics |

**Deployment:** user manual SCP `<repo>/sql/` → `/tmp/sql/` na **prim01** i **infra01** (nowa sekcja 0 w doc 04). Dotychczasowy workflow `<repo>/VMs/scripts/` → `/tmp/scripts/` przez MobaXterm bez zmian — dochodzi 1 katalog.

**Lekcja:** **kod re-use przez wywołanie SQL-i z bash zamiast ich kopiowanie** zachowuje single-source-of-truth. Skrypty SQL w `<repo>/sql/` są dokumentowane, mają DEFINE parametry, działają standalone w sqlplus dla manual debug — bash skrypty wzbogacają je o orkiestrację (SSH, capture+grep, exit codes). Bez duplikacji.

---

### FIX-057 — `sqlplus @plik.sql` wisi gdy plik nie ma `EXIT` na końcu

**Problem:** `configure_broker.sh` v2.0 (FIX-051) zawisł na sekcji 0.3 pre-flight przy wywołaniu `<repo>/sql/fsfo_check_readiness.sql`:

```
[20:43:50]   Wywoluje /tmp/sql/fsfo_check_readiness.sql...
(brak dalszego output-u przez 6+ minut)
```

**Diagnoza** przez drugą sesję sqlplus na primary:

```sql
SELECT sid, status, event, seconds_in_wait FROM v$session
WHERE program LIKE 'sqlplus%' AND username='SYS';

-- Wynik:
-- SID 298 INACTIVE 'SQL*Net message from client' 403 sec
```

`INACTIVE` z `SQL*Net message from client` przez 403s = sqlplus wykonał skrypt SQL i **czeka na kolejne polecenie z klienta**, nie zakończył sesji. Bash wrapper który czytał output (`$(sqlplus ... )`) wisiał na `wait`.

**Przyczyna:** wszystkie skrypty SQL w `<repo>/sql/` (`fsfo_check_readiness.sql`, `tac_full_readiness.sql`, `validate_environment.sql`, `fsfo_monitor.sql`, `fsfo_broker_status.sql`, `tac_replay_monitor.sql`, `fsfo_configure_broker.sql`, `tac_configure_service_rac.sql`) **kończą się na sekwencji `PROMPT`** (bez `EXIT`/`QUIT`/`/`):

```sql
PROMPT  Readiness check zakonczony. Przegladnij wyniki powyzej.
PROMPT  ================================================================================
-- (koniec pliku)
```

To jest świadome — pliki są zaprojektowane do uruchamiania **interaktywnie z sqlplus** (gdzie operator chce zostać w sesji żeby drążyć dalej queries). User potwierdził: `<repo>/sql/` traktujemy jako read-only.

Wywołanie `sqlplus @plik.sql` nigdy nie kończy się — sqlplus po przetworzeniu pliku czeka na input z STDIN (a tu STDIN jest pusty bo wywołane przez `$(...)` z brak heredoc).

**Poprawka — wywołanie przez heredoc z explicit `EXIT`:**

```bash
# Stara wersja (zawisa):
RES=$(sqlplus -s / as sysdba @"$SQL_DIR/fsfo_check_readiness.sql" 2>&1)

# Nowa wersja (działa):
RES=$(sqlplus -s / as sysdba <<SQLEOF 2>&1
@$SQL_DIR/fsfo_check_readiness.sql
EXIT
SQLEOF
)
```

Wzorzec `<<SQLEOF ... SQLEOF` (bez quotes wokół nazwy heredoc — czyli zmienne expand-ują się) pozwala wstrzyknąć `EXIT` po `@plik.sql`. Sqlplus wykonuje plik (ścieżka rozwiązana z `$SQL_DIR`) potem dostaje `EXIT` ze STDIN i kończy.

**Skrypty zaktualizowane:**
- `configure_broker.sh` v2.0 → **v2.1** (sekcja 0.3 fsfo_check_readiness)
- `deploy_tac_service.sh` v1.1 → **v1.2** (sekcja 0 tac_full_readiness)
- `validate_env.sh` v1.1 → **v1.2** (--quick i --full path)

**Lekcja (uniwersalna):**
- **`sqlplus @plik.sql` z bash-a działa tylko jeśli plik kończy się na `EXIT`.** W przeciwnym razie — heredoc z explicit `EXIT`. To samo dotyczy `sqlplus / as sysdba @file` z command line.
- **Sql-plików projektowych (read-only, nie nasze) nie modyfikujemy** żeby dodać `EXIT` — opakowujemy wywołanie w bash wrapperze.
- **Diagnostyka „skrypt zawisł"**: zawsze sprawdź `v$session WHERE program LIKE 'sqlplus%'`. `INACTIVE + SQL*Net message from client = sqlplus idle, czeka na input`. `ACTIVE + jakikolwiek event = legitimne wykonanie query`.

---

### FIX-058 — `configure_broker.sh` pre-flight chicken-and-egg na `dg_broker_start=FALSE`

**Problem:** po FIX-057 (sqlplus heredoc EXIT) `fsfo_check_readiness.sql` wykonał się szybko, output był zdrowy w 95%, ale sekcja 6 summary skryptu zwraca:

```
DG Broker    FAIL    dg_broker_start=FALSE
```

To jest **expected** stan przed enable (skrypt `configure_broker.sh` ma broker DOPIERO włączyć w sekcji 1). Heurystyka v2.1 sekcji 0.3:

```bash
if echo "$READINESS_OUT" | grep -E 'FAIL.*(force_logging|archivelog|flashback|broker)' -i >/dev/null; then
    die "Krytyczne checks FAIL..."
fi
```

→ matchowała `FAIL.*broker` → die **przed** sekcją 1 (gdzie broker jest włączany). Klasyczny chicken-and-egg.

**Poprawka `scripts/configure_broker.sh` v2.2:**

Usunięte `broker` z pattern krytycznych. Pozostaje sensowny zestaw rzeczy które **MUSZĄ** być na miejscu zanim broker w ogóle ma sens:

```bash
if echo "$READINESS_OUT" | grep -E 'FAIL.*(force[_ ]logging|archivelog|flashback|standby[_ ]file[_ ]management)' -i >/dev/null; then
    die "..."
fi
```

`standby_file_management=AUTO` zostaje — bo broker `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability` zakłada że standby auto-tworzy datafiles z primary.

**Lekcja:** **pre-flight nie powinien sprawdzać tego co skrypt sam ma ustawić** — to logiczny błąd zaprojektowania (gate sprawdza efekt swojego działania). Pre-flight = sprawdza **prereq z poprzedniego doc-u** (doc 08 pre-broker), nie własny output.

---

### FIX-059 — Brak SSH equivalency `oracle@prim01` → `oracle@stby01` blokuje `configure_broker.sh` sekcja 0.4

**Problem:** po SCP `configure_broker.sh` v2.2 i uruchomieniu, sekcja 0 pre-flight przeszła ✓ (tnsping, fsfo_check_readiness), ale skrypt **umarł cicho** po:

```
[hh:mm:ss]   ✓ fsfo_check_readiness.sql przeszedl
[hh:mm:ss]   Sanity check STBY (przez ssh oracle@stby01)...
(prompt wraca, brak kolejnych linii)
```

**Diagnoza:**
```bash
su - oracle -c 'ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no oracle@stby01 hostname'
# Permission denied, please try again.
# oracle@stby01: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password).
```

Brak SSH equivalency `oracle@prim01` → `oracle@stby01`. Doc 04 sekcja 6 historycznie pokrywała tylko **prim01 ↔ prim02** (Grid + oracle, dla Grid Infrastructure). FIX-038 #3 dodał `oracle@stby01` → `oracle@prim01` (do duplicate_standby.sh sanity primary + scp pwfile). **Kierunek odwrotny `prim01` → `stby01`** był uważany za zbędny — bo doc 09 i 10 manual nie wymagały (tylko skrypty).

**Sekcja 0.4 `configure_broker.sh` v2.0+ robi:**
```bash
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 oracle@stby01 \
    ". ~/.bash_profile && \$ORACLE_HOME/bin/sqlplus -s / as sysdba" <<EOF
SELECT 'ROLE='||database_role... FROM v\$database;
EOF
```

Bez kluczy SSH ten command zwraca "Permission denied" → grep nie matchuje `ROLE=PHYSICAL STANDBY` → `die "STBY nie w roli..."`. Output `die` wprawdzie idzie do stderr i powinien być widoczny w `tee /tmp/broker_run.log` — ale w niektórych edge case-ach (set -euo pipefail + ssh exit code) skrypt umiera bez czytelnego komunikatu.

**Poprawka `04_os_preparation.md` sekcja 6 (przepisana):**

1. **Tytuł** zmieniony z "prim01 ↔ prim02" na **"pełen mesh dla 3 DB nodes"**.
2. **Tabela 5 zestawów SSH** z explicit "z którego doc-u wymagane" — Grid (zestaw 1+2 prim↔prim), duplicate_standby.sh (zestaw 3 stby→prim), configure_broker.sh / deploy_tac_service.sh (zestaw 4 prim01→stby01), opcjonalny zestaw 5 (prim02→stby01).
3. **Nowa sekcja 6.4** "SSH oracle ↔ stby01 (pełen mesh DB nodes)" — Krok A (stby→prim, FIX-038 #3), Krok B (prim01→stby, FIX-059), Krok C (prim02→stby, opcjonalnie). Każdy z `ssh-copy-id` + test.
4. **Nowa sekcja 6.5** weryfikacja — bash loop testujący wszystkie wymagane kierunki.
5. Dodana wskazówka: gdy operator nie zna hasła `oracle@stby01` → `passwd oracle` jako root, po `ssh-copy-id` można hasło zablokować (`passwd -l oracle`).

**Cross-ref dodany:**
- `09_standby_duplicate.md` Prereq — link do doc 04 sekcja 6.4 Krok A
- `10_data_guard_broker.md` Prereq — link do doc 04 sekcja 6.4 Krok B + nota o FIX-059

**Lekcja (uniwersalna):**
- **SSH equivalency to graph, nie linia.** Zaczynamy od cluster (prim01 ↔ prim02) bo to wymaganie Grid. Każdy nowy skrypt który robi `ssh user@host` dodaje **nowy kierunek** do mesh. Trzeba traktować to jak macierz — każda komórka udokumentowana, każdy kierunek przetestowany.
- **Skrypty NIE mogą automatyzować ssh-copy-id** — wymaga hasła docelowego usera. To jest świadome zabezpieczenie Oracle (security by design). Manual step zawsze, jeden raz.
- **Cichy fail z `set -euo pipefail` + `2>&1 | tee`**: gdy skrypt die-uje wewnątrz `$(ssh ... <<EOF)` heredoc-a, output stderr może nie zawsze trafić do tee. Lepiej dodać `set -x` w sekcjach krytycznych dla debug.

---

### FIX-060 — `configure_broker.sh` v2.2 fałszywy "DMON nie wystartował" (zła view: `v$managed_standby` zamiast `gv$process`)

**Problem:** po FIX-058/059 skrypt v2.2 doszedł do sekcji 1, `ALTER SYSTEM SET dg_broker_start=TRUE` przeszło OK (output pokazuje `dg_broker_start TRUE` na PRIM i STBY), ale po sleep 15s skrypt die:

```
[hh:mm:ss]   ✓ dg_broker_start=TRUE na STBY
[hh:mm:ss]   Sleep 15s — czekam az DMON process wystartuje...
[hh:mm:ss] ERROR: DMON process nie wystartowal na PRIM (count=0)
```

**Diagnoza:** query w v2.2:
```sql
SELECT COUNT(*) FROM gv$managed_standby WHERE process='DMON';
```

`v$managed_standby` (`gv$managed_standby` na RAC) to view z procesami **redo transport / apply** — `MRP0`, `RFS`, `LNS`, `NSS`, `ARCH`, `LGWR`. **DMON tam nie istnieje** — DMON to **background process Data Guard Broker**, listed w `v$process` / `v$bgprocess`.

Po `ALTER SYSTEM SET dg_broker_start=TRUE` Oracle uruchamia DMON automatycznie (jeden per instancja) — można zobaczyć w:
```sql
SELECT inst_id, pname FROM gv$process WHERE pname='DMON';
-- lub
SELECT inst_id, name FROM gv$bgprocess WHERE name='DMON' AND paddr<>'00';
-- lub mniej restrykcyjnie
SELECT inst_id, program FROM gv$process WHERE program LIKE '%(DMON)%';
```

**Poprawka `scripts/configure_broker.sh` v2.3:**

Zamiast jednego query po niewłaściwej view — dwa równoległe sprawdzenia:

```bash
DMON_OUT=$(sqlplus -s / as sysdba <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'DMON_PROC=' || COUNT(*) FROM gv$process WHERE program LIKE '%(DMON%)%' OR pname='DMON';
SELECT 'BROKER_PARAM=' || COUNT(*) FROM gv$parameter WHERE name='dg_broker_start' AND UPPER(value)='TRUE';
EXIT
EOF
)
```

Logika:
- `BROKER_PARAM` = liczba RAC instancji z `dg_broker_start=TRUE` (oczekiwane 2 dla 2-node RAC). To **must-pass**.
- `DMON_PROC` = liczba aktywnych DMON background processes (oczekiwane 2). Jeśli <2 → tylko warn + dodatkowy sleep 10s (nie die). Pierwsze enable broker może wymagać 20-30s zanim DMON się ustabilizuje.

**Lekcja (uniwersalna):**
- **Oracle views podziel na warstwy:** `v$managed_standby` = redo transport/apply. `v$process` = wszystkie procesy DB (server + background). `v$bgprocess` = nazwane background processes (DMON, MMON, SMON, PMON, LGWR…). DMON jest typu BG, nie standby.
- **Verify boolean parameter to safer fallback** niż sprawdzanie procesu — parametr ustawiony deterministycznie po `ALTER SYSTEM`, proces uruchamia się asynchronicznie z lekkim opóźnieniem.

---

### FIX-061 — DGMGRL `ADD DATABASE ... MAINTAINED AS PHYSICAL` syntax error w 23ai/26ai

**Problem:** v2.3 sekcja 2 wykonała:
```
DGMGRL> CREATE CONFIGURATION PRIM_DG AS PRIMARY DATABASE IS PRIM CONNECT IDENTIFIER IS PRIM_ADMIN;
Configuration "prim_dg" created with primary database "prim"

DGMGRL> ADD DATABASE STBY AS CONNECT IDENTIFIER IS STBY_ADMIN MAINTAINED AS PHYSICAL;
                                                              ^
Syntax error before or at "MAINTAINED"

DGMGRL> ENABLE CONFIGURATION;
Enabled.
(ale ENABLE poszedł tylko z PRIM - STBY nigdy nie został dodany)
```

Rezultat: konfiguracja w stanie WARNING:
```
Configuration - prim_dg
  Protection Mode: MaxPerformance
  Members:
  PRIM - Primary database
    Warning: ORA-16532: Oracle Data Guard broker configuration does not exist.
Configuration Status: WARNING
```

**Diagnoza:** `MAINTAINED AS LOGICAL|PHYSICAL` było używane w 19c/12c dla rozróżnienia Logical vs Physical Standby przy ADD DATABASE. W 23ai/26ai składnia zmieniona — `MAINTAINED` clause zostało **usunięte** (Physical to domyślne, dla Logical/Snapshot używa się dedykowanych komend `ADD LOGICAL STANDBY` / `CONVERT DATABASE`). Dokumentacja 23ai DGMGRL Reference podaje:
```
ADD DATABASE database-name [AS CONNECT IDENTIFIER IS connect-identifier]
```
bez `MAINTAINED AS`.

**Poprawka `scripts/configure_broker.sh` v2.4:**

Usunięte `MAINTAINED AS PHYSICAL`:
```sql
-- v2.3 (broken w 26ai):
ADD DATABASE STBY AS CONNECT IDENTIFIER IS STBY_ADMIN MAINTAINED AS PHYSICAL;

-- v2.4 (działa w 26ai):
ADD DATABASE STBY AS CONNECT IDENTIFIER IS STBY_ADMIN;
```

**Cleanup po failed run (manual przed re-run skryptu):**

```sql
-- Na prim01 jako oracle
dgmgrl /
DISABLE CONFIGURATION;
REMOVE CONFIGURATION PRESERVE DESTINATIONS;
EXIT
```

`PRESERVE DESTINATIONS` zachowuje `log_archive_dest_2` na PRIM (FIX-049 set ASYNC NOAFFIRM) — bez tego REMOVE wyczyściłby też log transport.

Po cleanup → SCP `configure_broker.sh` v2.4+ → uruchom ponownie. Sekcja 2 `idempotency check` zobaczy `ORA-16532 configuration does not exist` → ruszy `CREATE/ADD/ENABLE` na czysto.

**Lekcja (uniwersalna):**
- **DGMGRL syntax migration 19c → 23ai/26ai** — Oracle wycofał kilka clause-ów (`MAINTAINED AS`, `INSTANCE` dla static services). Skrypty napisane pod 19c nie odpalą się od razu na 26ai. Zawsze test syntax przy migracji wersji.
- **Częściowy fail w `dgmgrl <<EOF` heredoc-u** jest najgorszą klasą błędu — sub-komendy działają sekwencyjnie, jedna fail-uje, kolejne dalej lecą **z brokem statusu konfiguracji**. dgmgrl exit code w heredoc-u kończy się 0 mimo syntax error → bash wrapper widzi "OK" i die-uje dopiero przy verify SUCCESS. Zostaje konfiguracja w WARNING/ERROR — wymaga manualnego REMOVE.
- **REMOVE CONFIGURATION PRESERVE DESTINATIONS** — bezpieczne dla cleanup, nie traci log_archive_dest_2 na primary (FIX-049 work).

---

### FIX-062 — `ENABLE CONFIGURATION` ORA-16905 wymaga retry (broker synchronizuje members ~30-60s)

**Problem:** v2.4 sekcja 2 wykonała poprawnie:
```
Configuration "prim_dg" created with primary database "prim"
Database "stby" added
Enabled.
```

Ale natychmiastowy `SHOW CONFIGURATION` zwrócił:
```
Configuration - prim_dg
  Members:
  PRIM - Primary database
    Warning: ORA-16905: The member was not enabled.
  stby - Physical standby database
    Warning: ORA-16905: The member was not enabled.
Configuration Status: WARNING
```

Skrypt die-uje "ENABLE CONFIGURATION fail".

**Diagnoza:** ORA-16905 = **temporal stan** propagacji konfiguracji. `ENABLE CONFIGURATION` w dgmgrl zwraca natychmiast po commit do brokera config file (`+DATA/PRIM/dr1PRIM.dat`). Faktyczna aktywacja members (DMON sends config do RFS na każdym node, members ack-ują, broker setuje state na `ENABLED`) trwa **30-60s** w background.

`SHOW CONFIGURATION` w trakcie tego okna pokazuje WARNING z ORA-16905 dla każdego member-a. Po ~30s zmienia się na `Configuration Status: SUCCESS`.

**Poprawka `scripts/configure_broker.sh` v2.5 — retry loop:**

```bash
log "  Czekam az broker synchronizuje members (max 90s)..."
SUCCESS=0
for i in 1 2 3 4 5 6; do
    sleep 15
    STATUS_OUT=$(dgmgrl sys/...@PRIM_ADMIN <<EOF
SHOW CONFIGURATION;
EXIT
EOF
    )
    if echo "$STATUS_OUT" | grep -q "Configuration Status:.*SUCCESS"; then
        log "    ✓ Members enabled po ${i}x15s = $((i*15))s"
        SUCCESS=1
        break
    fi
    log "    Probka $i/6: jeszcze nie SUCCESS (czekam 15s)..."
done
[[ "$SUCCESS" -eq 1 ]] || die "..."
```

Max 90s na osiągnięcie SUCCESS. Typowo broker kończy w 30-45s, więc 1-3 iteracje.

**Lekcja (uniwersalna):**
- **DGMGRL commands typu ENABLE/DISABLE/EDIT są asynchroniczne** — zwracają OK po commit do config file, ale rzeczywista propagacja do members trwa. Verify musi mieć retry z timeout-em.
- **ORA-16905 'member was not enabled'** to nie błąd, tylko stan przejściowy. Nigdy nie traktuj tego jako blokujący w skrypcie.
- **Inne async dgmgrl ops gdzie warto retry:** `EDIT CONFIGURATION SET PROTECTION MODE`, `ENABLE FAST_START FAILOVER`, `SWITCHOVER`. Każda potrzebuje sleep + verify loop.

---

### FIX-063 — `dg_broker_config_file{1,2}` na RAC primary musi być shared (`+DATA`), nie lokalny FS

**Problem:** po FIX-061+062 broker przeszedł CREATE+ADD+ENABLE, ale `Configuration Status: WARNING` utrzymywał się >90s. STATUSREPORT pokazał diagnozę:

```
DGMGRL> SHOW DATABASE prim STATUSREPORT;
       INSTANCE_NAME   SEVERITY   ERROR_TEXT
               PRIM1   (no error)
               PRIM2   ERROR      ORA-16532: Oracle Data Guard broker configuration does not exist.

DGMGRL> SHOW DATABASE stby STATUSREPORT;
       INSTANCE_NAME   SEVERITY   ERROR_TEXT
                STBY   (no error)
```

**Tylko PRIM2** raportował ORA-16532. PRIM1 i STBY były OK. STBY mógł zapisywać/odczytywać własny `dr1STBY.dat` (lokalny FS, SI), STBY widział też zdalny config przez DMON↔DMON. Ale **PRIM2 nie miał dostępu do plików zapisanych przez PRIM1**.

**Diagnoza:** parametry brokera:
```sql
SHOW PARAMETER dg_broker_config_file
-- dg_broker_config_file1   /u01/app/oracle/product/23.26/dbhome_1/dbs/dr1PRIM.dat
-- dg_broker_config_file2   /u01/app/oracle/product/23.26/dbhome_1/dbs/dr2PRIM.dat
```

**To są lokalne ścieżki `$ORACLE_HOME/dbs/`** — **DBCA 26ai zostawia je domyślnie zamiast ustawić `+DATA/<DB_UNIQUE_NAME>/`**. Na **RAC** broker config to **jeden plik per database** (nie per instance) — musi być na shared storage żeby oba RAC nodes go widziały. PRIM1 utworzył plik lokalnie → PRIM2 nie miał dostępu → ORA-16532.

Doc 10 sekcja 2.1 to wspomniała:
> "dg_broker_config_file{1,2} — na RAC +DATA, na SI /u01/app/oracle. UWAGA: broker config file jest SINGLE per database, nie per instance!"

Ale nikt nie wymusił tego ustawienia w skrypcie ani DBCA response file (FIX-028..035 nie obejmowały).

**Poprawka `scripts/configure_broker.sh` v2.6:**

Nowa **sekcja 0.5** (między pre-flight a sekcją 1 enable broker) — auto-detect + auto-fix dla RAC primary:

```bash
DBCFG_OUT=$(sqlplus -s / as sysdba <<EOF
SELECT 'CFG1=' || value FROM v$parameter WHERE name='dg_broker_config_file1';
SELECT 'INSTANCES=' || COUNT(*) FROM gv$instance;
EOF
)
INSTANCES=$(echo "$DBCFG_OUT" | grep -oE 'INSTANCES=[0-9]+' | cut -d= -f2)
CFG1=$(echo "$DBCFG_OUT" | grep -oE 'CFG1=.*' | sed 's/^CFG1=//')

if [[ "$INSTANCES" -gt 1 ]] && [[ ! "$CFG1" =~ ^\+ ]]; then
    # RAC + lokalny FS → fix
    dgmgrl ... 'DISABLE CONFIGURATION; REMOVE CONFIGURATION PRESERVE DESTINATIONS;'
    sqlplus / as sysdba <<EOF
ALTER SYSTEM SET dg_broker_start=FALSE SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file1='+DATA/PRIM/dr1PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file2='+DATA/PRIM/dr2PRIM.dat' SCOPE=BOTH SID='*';
EOF
    # Sekcja 1 dalej zrobi ALTER SYSTEM SET dg_broker_start=TRUE
fi
```

**Manual cleanup + fix dla user-a w stanie WARNING:**

```sql
-- Na prim01 jako oracle
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

-- (na STBY zostawiamy lokalny FS - SI, jedna instance)
```

Po tym CREATE CONFIGURATION ponownie. Teraz oba RAC instances będą miały dostęp do tego samego pliku → enable members przejdzie na SUCCESS.

**Lekcja (uniwersalna):**
- **RAC defaults vs requirements** — Oracle DBCA dla RAC nie zawsze ustawia parametry RAC-specific (np. `dg_broker_config_file*`, `cluster_database_instances` dla SI rebuild post-duplicate). Każdy parametr który ma znaczenie shared/per-instance MUSI być explicit.
- **`SCOPE=BOTH SID='*'` jako standard dla RAC ALTER SYSTEM** — bez `SID='*'` zmiana idzie tylko do bieżącej instancji w SPFILE; z `SID='*'` do wszystkich. Tu krytyczne bo RAC członkowie muszą mieć ten sam parametr.
- **STATUSREPORT to pierwszy debug step dla broker WARNING** — pokazuje per-instance error, nie tylko per-member. Bez tego nie widzielibyśmy że tylko PRIM2 ma problem (PRIM1 i STBY OK).

---

### FIX-064 — `ENABLE CONFIGURATION` retry timeout 90s za krótki dla VirtualBox lab

**Problem:** v2.5/v2.6 retry max 6×15s = 90s — broker w lab VirtualBox potrzebował dłużej. Skrypt die-uł przy "Probka 6/6: jeszcze nie SUCCESS", ale 30-60 sekund później `SHOW CONFIGURATION` pokazał `Configuration Status: SUCCESS`. STATUSREPORT bez błędów.

**Diagnoza:** wewnętrzna pętla brokera (`drcSTBY.log`):

```
2026-04-26T21:35:55  Deleting broker configuration data on this member
2026-04-26T21:35:55  Contents of dr1STBY.dat / dr2STBY.dat has been deleted
2026-04-26T21:35:55  Starting task: ENABLE CONFIGURATION
2026-04-26T21:35:57  Apply Instance for Database stby set to STBY
2026-04-26T21:35:58  Updated broker configuration file (miv=5)
...
~21:39:00 (3 minuty po ENABLE) — Configuration Status: SUCCESS
```

VirtualBox z fileio iSCSI backstore (wariant A) ma wolniejsze IO niż produkcja — broker config-file roundtrip + ack od members trwa 90-150s zamiast Oracle-doc-typowych 30-45s.

**Poprawka `scripts/configure_broker.sh` v2.7:**

```bash
# v2.6 - 90s timeout (za krótki dla lab):
for i in 1 2 3 4 5 6; do sleep 15; ... done

# v2.7 - 180s timeout:
for i in $(seq 1 12); do sleep 15; ... done
```

**Idempotency safety:** v2.7 (jak każda od v2.0) ma w sekcji 2 wykrycie istniejącej SUCCESS i pomija CREATE+ENABLE. Czyli die po pierwszym timeout → re-run skryptu → idempotency widzi `Configuration Status: SUCCESS` → skip CREATE → przechodzi do sekcji 3 (MaxAvailability). Operator może spokojnie ponowić bez czyszczenia konfiguracji.

**Lekcja (uniwersalna):**
- **Lab VirtualBox ≠ produkcja** dla async operacji broker. Timeout-y dobrane pod produkcję są często za krótkie. 2-3× margines dla lab to bezpieczny default.
- **Idempotency = redundancja jako bezpieczeństwo** — gdy timeout zbyt agresywny, ponowne uruchomienie ratuje sytuację bez utraty dotychczasowej pracy.

---

### FIX-065 — Idempotency grep w `configure_broker.sh` nie matchuje multiline output dgmgrl

**Problem:** po DONE w sekcji 2 (Configuration Status: SUCCESS — verify ręczne potwierdziło), re-run skryptu v2.7 trafiał w branch:

```
[hh:mm:ss] WARN: Niejednoznaczny stan brokera. Output:
Configuration - prim_dg
  Protection Mode: MaxPerformance
  Members:
  PRIM - Primary database
    stby - Physical standby database
Fast-Start Failover:  Disabled
Configuration Status:
SUCCESS   (status updated 19 seconds ago)
[hh:mm:ss] ERROR: Sprawdz reczne SHOW CONFIGURATION i ewentualnie REMOVE CONFIGURATION przed retry.
```

**Diagnoza:** dgmgrl 23.26.1 wypisuje `SHOW CONFIGURATION` w formacie multiline:

```
Configuration Status:
SUCCESS   (status updated 19 seconds ago)
```

`Configuration Status:` w jednej linii, `SUCCESS` w **następnej**. Mój grep:

```bash
grep -q "Configuration Status:.*SUCCESS"
```

domyślnie matchuje **w jednej linii** (bez `-z` lub multiline). Dlatego nie znajduje SUCCESS, idzie do `else` branch ("niejednoznaczny stan").

W 19c dgmgrl wypisywał jednolinijkowo: `Configuration Status: SUCCESS (status...)`. **W 23ai/26ai format zmieniony na multiline.**

**Poprawka `scripts/configure_broker.sh` v2.8:**

Spłaszczamy output `tr '\n' ' '` przed grep, plus dodany branch dla WARNING (status przejściowy z dodatkowym retry 30s):

```bash
EXIST_FLAT=$(echo "$EXIST_OUT" | tr '\n' ' ' | tr -s ' ')

if echo "$EXIST_FLAT" | grep -qE "Configuration Status:[[:space:]]*SUCCESS"; then
    log "  Configuration juz istnieje i ma status SUCCESS — skip CREATE/ADD/ENABLE"
elif echo "$EXIST_FLAT" | grep -qE "Configuration Status:[[:space:]]*WARNING"; then
    warn "WARNING — czekam 30s..."
    # ... retry ...
elif echo "$EXIST_FLAT" | grep -qE "ORA-16532|configuration does not exist"; then
    # CREATE
fi
```

Plus naprawiony grep w retry loop (sekcja 2 ENABLE) i w sekcji 3 verify (Protection Mode + Status). Wszystkie 3 grep-y na dgmgrl output używają teraz pattern `tr | tr -s ' ' | grep -qE`.

Sekcja 3 verify dla Status: SUCCESS dostała też **retry loop** (max 90s) — bo po `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability` broker musi propagować zmianę protection mode i SYNC+AFFIRM do members analogicznie jak przy CREATE.

**Lekcja (uniwersalna):**
- **dgmgrl 23ai/26ai output multiline** — `SHOW CONFIGURATION`, `SHOW DATABASE`, `SHOW FAST_START FAILOVER` wypisują "Field:" w jednej linii i wartość w następnej. Wszystkie skrypty bash używające grep na dgmgrl output muszą mieć `tr '\n' ' '` przed grep (lub `grep -z` dla NULL-separated).
- **Idempotency = re-run safety** — dobra idempotency oznacza że "uruchom ponownie" zawsze ratuje sytuację. Tu sekcje 0/0.5/1/2 v2.8 sąidempotentne (no-op gdy stan docelowy osiągnięty), sekcja 3 EDIT też (broker zignoruje nadpisanie tego samego LogXptMode).
- **`tr '\n' ' ' | tr -s ' '`** — pierwszy zamienia newline na space, drugi `tr -s ' '` skleja kolejne spaces w jeden (czystszy output dla regex).

---

## FIX-066 — `v$archive_dest.transmit_mode` w 26ai = `PARALLELSYNC`, nie `SYNCHRONOUS`

**Data:** 2026-04-26 21:46 | **Plik:** `VMs/scripts/configure_broker.sh` v2.8 → **v2.9**

**Symptom:**
```
[21:46:54]   Verify v$archive_dest dest_id=2 transmit_mode=SYNCHRONOUS, affirm=YES...
[21:46:54] ERROR: log_archive_dest_2 NIE jest SYNCHRONOUS po MaxAvailability:
          D2_TRANSMIT=PARALLELSYNC,D2_AFFIRM=YES
```

Skrypt v2.8 die-ował na ostatnim verify mimo że broker poprawnie ustawił **MaxAvailability + Configuration Status: SUCCESS + AFFIRM=YES**. Przebieg był idealny:

```
[21:46:43] Sekcja 2 — CREATE/ADD/ENABLE configuration...
[21:46:43]   Configuration juz istnieje i ma status SUCCESS — skip CREATE/ADD/ENABLE   <-- FIX-065 OK
[21:46:43] Sekcja 3 — Zmiana Protection Mode na MaxAvailability...
DGMGRL> Property "logxptmode" updated for member "prim".
DGMGRL> Property "logxptmode" updated for member "stby".
DGMGRL> Succeeded.
  Protection Mode: MaxAvailability
  Configuration Status: SUCCESS
[21:46:54]     ✓ Status SUCCESS po 1x15s
[21:46:54]   ✓ Protection Mode = MaxAvailability + Status SUCCESS
[21:46:54] ERROR: log_archive_dest_2 NIE jest SYNCHRONOUS: D2_TRANSMIT=PARALLELSYNC   <-- FIX-066
```

**Diagnoza:** w Oracle 23ai/26ai broker dla `LogXptMode=SYNC` ustawia `v$archive_dest.transmit_mode='PARALLELSYNC'` (enhanced multi-stream SYNC mode wprowadzony w 21c+) zamiast klasycznego `SYNCHRONOUS` znanego z 19c.

`PARALLELSYNC` to **prawidłowy** SYNC tryb dla MaxAvailability — Oracle używa wielu strumieni redo równolegle dla lepszej przepustowości, ale gwarancje `AFFIRM` (commit zwrócony dopiero po ack ze standby) są zachowane.

**Poprawka v2.9:**

```bash
# Akceptuj oba: SYNCHRONOUS (19c-style) lub PARALLELSYNC (23ai/26ai-style)
echo "$ARCHDEST_OUT" | grep -qE "D2_TRANSMIT=(SYNCHRONOUS|PARALLELSYNC)" \
    || die "log_archive_dest_2 NIE jest w trybie SYNC po MaxAvailability: $ARCHDEST_OUT"
```

**Oczekiwane po fix:**
```
[..]   ✓ log_archive_dest_2: SYNC + AFFIRM=YES (broker skonfigurowal automatycznie):
       D2_TRANSMIT=PARALLELSYNC,D2_AFFIRM=YES
[..] DONE — DG Broker enabled, Protection Mode = MaxAvailability (SYNC+AFFIRM)
```

**Lekcja:**
- W 23ai/26ai `v$archive_dest.transmit_mode` ma 4 możliwe wartości: `ASYNCHRONOUS`, `SYNCHRONOUS`, `PARALLELSYNC`, `PARALLELSYNC_NOAFFIRM`. **`PARALLELSYNC` jest default** dla LogXptMode=SYNC.
- Verify trybu SYNC w 23ai/26ai: `transmit_mode IN ('SYNCHRONOUS','PARALLELSYNC') AND affirm='YES'`.
- Skrypty diagnostyczne MAA portowane z 19c muszą uwzględniać `PARALLELSYNC` w grep/regex.

---

## FIX-067 — `SHOW FAST_START FAILOVER` multiline grep w 26ai

**Data:** 2026-04-26 22:30 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.1 → **v1.2**

**Symptom:** Skrypt v1.1 sekcja "Enable FSFO + post-flight verify" (linia 208):

```bash
echo "$FSFO_OUT" | grep -qE "(Status|Fast-Start Failover):.*ENABLED" \
    || die "FSFO Status != ENABLED po ENABLE FAST_START FAILOVER."
```

W 23ai/26ai output `SHOW FAST_START FAILOVER` to multiline:
```
Fast-Start Failover:
ENABLED

  Threshold:           30 seconds
  ...
```

`Fast-Start Failover:` w jednej linii, `ENABLED` w **następnej**. Grep w jednej linii nie matchuje → skrypt die-uje mimo że FSFO faktycznie ENABLED. **Identyczny pattern jak FIX-065** w `configure_broker.sh`.

**Poprawka v1.2:**
```bash
FSFO_FLAT=$(echo "$FSFO_OUT" | tr '\n' ' ' | tr -s ' ')
if echo "$FSFO_FLAT" | grep -qE "Fast-Start Failover:[[:space:]]*ENABLED"; then
    log "  ✓ Fast-Start Failover: ENABLED"
fi
```

Wszystkie 2 grep-y na dgmgrl output (sekcja 4.5 pre-flight + sekcja 9 retry verify) używają `tr | tr -s ' ' | grep -qE`.

**Lekcja:** dgmgrl 23ai/26ai output jest multiline dla **wszystkich** `SHOW *` komend (`SHOW CONFIGURATION`, `SHOW DATABASE`, `SHOW FAST_START FAILOVER`, `SHOW PROPERTIES`). Każdy bash grep na dgmgrl output musi mieć `tr '\n' ' '` flatten albo `grep -z` (NULL-separated). Reguła uniwersalna dla wszystkich skryptów wykonujących dgmgrl heredoc.

---

## FIX-068 — Pre-flight broker `Configuration Status: SUCCESS` przed ENABLE FSFO

**Data:** 2026-04-26 22:30 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.1 → **v1.2**

**Problem:** Skrypt v1.1 sprawdzał tylko `tnsping` i `sqlplus connect`, ale **NIE** weryfikował że broker jest w stanie `SUCCESS` przed wywołaniem:
1. `EDIT CONFIGURATION SET PROPERTY FastStartFailoverThreshold=30;` (i 4 kolejne)
2. `ADD OBSERVER ${OBSERVER_NAME} ON ${OBSERVER_HOST};`
3. `ENABLE FAST_START FAILOVER;`

Jeśli broker był w stanie `WARNING` (np. apply lag > 30s, ORA-16532 z RAC config_file, świeży re-build), te EDIT-y zwracały `ORA-16664 unable to receive the result from a member` lub `ORA-16830 primary is not ready for failover` z **niejasnym komunikatem** (skrypt logował `dgmgrl output` bez wskazania że root cause to broker WARNING, nie observer setup).

**Poprawka v1.2 — sekcja 4.5 pre-flight:**

```bash
CFG_OUT=$(... dgmgrl /@PRIM_ADMIN <<DGEOF ... SHOW CONFIGURATION ... DGEOF)
CFG_FLAT=$(echo "$CFG_OUT" | tr '\n' ' ' | tr -s ' ')

if echo "$CFG_FLAT" | grep -qE "Configuration Status:[[:space:]]*SUCCESS"; then
    log "  ✓ Configuration Status: SUCCESS"
elif echo "$CFG_FLAT" | grep -qE "ORA-16532|configuration does not exist"; then
    die "Broker configuration nie istnieje. Najpierw uruchom configure_broker.sh (doc 10)."
elif echo "$CFG_FLAT" | grep -qE "Configuration Status:[[:space:]]*WARNING"; then
    die "Broker WARNING — observer setup wstrzymany. Sprawdz: SHOW CONFIGURATION VERBOSE + SHOW DATABASE * STATUSREPORT."
fi
```

Plus warn-only check `Protection Mode: MaxAvailability` (FSFO można włączyć na MaxPerformance, ale nie ma zero data loss guarantee — lepiej user zdecyduje świadomie).

**Lekcja:** Każdy skrypt wykonujący `EDIT CONFIGURATION` lub `ENABLE *` musi pre-flight `SHOW CONFIGURATION` z multiline-aware grep i 3 branche (SUCCESS / WARNING / does not exist). Inaczej błąd downstream maskuje root cause.

---

## FIX-069 — `ENABLE FAST_START FAILOVER` async w 26ai — retry 180s

**Data:** 2026-04-26 22:30 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.1 → **v1.2**

**Problem:** Analogicznie do `ENABLE CONFIGURATION` (FIX-062 / FIX-064), `ENABLE FAST_START FAILOVER` w 26ai jest **async**. Komenda zwraca `Enabled in Zero Data Loss Mode.` natychmiast po commit do `dr*PRIM.dat`, ale broker propaguje state `ENABLED` do members + observer przez **30-150s** (VBox lab; prod 30-45s).

Skrypt v1.1 robił `ENABLE FSFO` + `SHOW FAST_START FAILOVER` w **jednym dgmgrl heredoc** (linia 201-205) — bez sleep-u i bez retry. Pierwsze `SHOW` zaraz po enable może pokazać `DISABLED` mimo że commit się powiódł.

**Poprawka v1.2 — sekcja 9 retry loop:**

```bash
FSFO_OK=0
for i in $(seq 1 12); do
    sleep 15
    FSFO_OUT=$(... dgmgrl /@PRIM_ADMIN <<DGEOF ... SHOW FAST_START FAILOVER ... DGEOF)
    FSFO_FLAT=$(echo "$FSFO_OUT" | tr '\n' ' ' | tr -s ' ')

    if echo "$FSFO_FLAT" | grep -qE "Fast-Start Failover:[[:space:]]*ENABLED"; then
        log "    ✓ ENABLED po ${i}x15s"
        FSFO_OK=1
        break
    fi
    log "    [${i}/12] FSFO jeszcze nie ENABLED, czekam dalej..."
done
[[ "$FSFO_OK" -eq 1 ]] || die "FSFO != ENABLED po 180s."
```

Plus dodatkowy verify że Observer name w SHOW FAST_START FAILOVER matchuje `${OBSERVER_NAME}` (sanity check — observer rzeczywiście zarejestrował się w brokerze).

**Lekcja:** wszystkie `ENABLE *` komendy w dgmgrl 23ai/26ai są async (broker.config zapis + propagacja do members). Skrypt automatyzujący musi mieć retry loop **180s dla VBox lab / 90s dla prod** + multiline grep. Reguła jak dla `ENABLE CONFIGURATION` — propagacja przez `dr*PRIM.dat` w +DATA wymaga drugiego coordination round po commit.

**Dodatkowe housekeeping w v1.2:**

| # | Co | Detal |
|---|---|---|
| #4 | systemd `START OBSERVER` **bez** `IN BACKGROUND` z `Type=simple` | `IN BACKGROUND` fork-uje observer i exit; systemd uznaje za crash → Restart=on-failure loop. Bez `IN BACKGROUND` dgmgrl trzyma proces aż observer zatrzyma. |
| #5 | Reordering: `ADD OBSERVER` → `systemctl start` → wait 15s → `SET MASTEROBSERVER` → `ENABLE FSFO` | `SET MASTEROBSERVER` w 26ai wymaga running observer (broker robi ping). v1.1 robił `SET MASTEROBSERVER` przed `systemctl start` — silent fail. |
| #6 | mkstore `-createCredential` idempotency | `mkstore -listCredential | grep -c PRIM_ADMIN` przed create. Bez tego re-run umierał z `set -e` bo mkstore zwracał exit 1 na "credential already exists". |
| #7 | Cleanup `/tmp/setup_wallet.$$.sh` przez `trap` | Plik zawiera hasło wallet (`Welcome1#Wallet`). v1.1 zostawiał na disk. v1.2 usuwa nawet przy die. |
| ALLOW_HOST | Override dla `ALLOW_HOST=any OBSERVER_NAME=obs_dc` | Doc 16 backup observers (`obs_dc` na prim01, `obs_dr` na stby01). v1.1 wymagał `hostname == infra01` hardcoded. |

---

## FIX-070 — `DECLINE_SECURITY_UPDATES` w `client.rsp` rzuca INS-10105 w 23ai/26ai

**Data:** 2026-04-26 22:25 | **Plik:** `VMs/response_files/client.rsp` v1.1 → **v1.2**, `VMs/11_fsfo_observer.md` sekcja 1.3

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

**Diagnoza:** Schema `rspfmt_clientinstall_response_schema_v23.0.0` w Oracle Client 23ai/26ai jest **strict** i nie akceptuje legacy keys z 19c. `DECLINE_SECURITY_UPDATES=true` był standardowym kluczem w 19c response files (informował OUI że nie chcemy MOS account dla security alerts) — w 23.0.0 schema został usunięty (configuration MOS przeniesiona na poziom konta).

**Lista allowed keys w 23.0.0 client schema** (z error message):
- `SELECTED_LANGUAGES`
- `ORACLE_HOSTNAME`
- `oracle.install.IsBuiltInAccount`, `OracleHomeUserName`, `OracleHomeUserPassword`
- `oracle.install.client.oramtsPortNumber`
- `oracle.install.client.customComponents`
- `oracle.install.client.schedulerAgentHostName`, `schedulerAgentPortNumber`
- `oracle.install.client.drdaas.*` (DRDA AS settings — DB2 compat)
- `PROXY_HOST`, `PROXY_PORT`, `PROXY_USER`, `PROXY_PWD`, `PROXY_REALM`

Plus base keys które działają (z standard response file format):
- `oracle.install.responseFileVersion`
- `UNIX_GROUP_NAME`, `INVENTORY_LOCATION`, `ORACLE_HOME`, `ORACLE_BASE`
- `oracle.install.client.installType`

**Poprawka v1.2:** usunięcie `DECLINE_SECURITY_UPDATES=true` z `client.rsp`. Po fix:

```
[oracle@infra01 client]$ ./runInstaller -silent -responseFile /tmp/scripts/client.rsp -ignorePrereqFailure
Starting Oracle Universal Installer...
Checking Temp space: OK
Checking swap space: OK
...
Successfully Setup Software.
```

**Powiązane:** FIX-028 (`asmSysPassword` w dbca rsp — usunięty w 23.0.0 schema), FIX-029 (`recoveryAreaSize` — usunięty, replaced przez `db_recovery_file_dest_size` w `initParams`). **Pattern uniwersalny:** wszystkie `*_response_schema_v23.0.0` są strict — odrzucają każdy klucz spoza listy. Migracja z 19c rsp wymaga audytu key-by-key.

**Lekcja operacyjna:** przy każdym INS-10105 zacznij od listy allowed keys w SUMMARY error message — Oracle wypisuje pełen schema content. Match key-by-key i usuwaj wszystkie spoza listy.

---

## FIX-071 — `PWD` w helper script wallet kolidował z bash builtin

**Data:** 2026-04-26 22:37 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.2 → **v1.3**

**Symptom:**
```
[22:37:24] Sekcja 3 — Tworzenie/aktualizacja Oracle Wallet...
Creating new wallet...
Enter password:           ← INTERAKTYWNIE (heredoc nie podal hasla)
Enter password again:
Adding PRIM_ADMIN credential...
Enter wallet password:    ← INTERAKTYWNIE
Adding STBY_ADMIN credential...
Enter wallet password:    ← INTERAKTYWNIE
Auto-login (cwallet.sso) juz istnieje - skip
Wallet configured
[22:37:27] Sekcja 4 — Pre-flight: tnsping PRIM_ADMIN i STBY_ADMIN OK
[22:37:27]   Test connectivity sqlplus /@PRIM_ADMIN...
[22:37:27] ERROR: Test PRIM_ADMIN sqlplus FAIL — sprawdz wallet credentials lub broker readiness.
```

3× `Enter password:` gdy heredoc miał automatycznie podać `Welcome1#Wallet`. Wallet powstał z **wrong password** (lub timeout). `sqlplus /@PRIM_ADMIN` w sekcji 4 nie znalazł credentials.

**Diagnoza:** v1.2 helper script używał:
```bash
PWD='Welcome1#Wallet'    # FIX-071: PWD to bash BUILTIN (current working directory)
SYS='Welcome1#SYS'

mkstore -wrl $WL -create <<EOF
$PWD                     # bash interpoluje builtin /home/oracle, NIE 'Welcome1#Wallet'
$PWD
EOF
```

W heredoc bash interpoluje `$PWD` w **inner shell context**. Przypisanie `PWD='Welcome1#Wallet'` w skrypcie nie nadpisało builtin w heredoc evaluation — bash używał `/home/oracle` (current working dir oracle user-a) jako "hasło". mkstore odrzucał jako too-short i prosił interaktywnie. Po 3 timeoutach wallet powstał z empty/junk password.

`Auto-login (cwallet.sso) juz istnieje - skip` — bo `cwallet.sso` powstał automatycznie z `mkstore -create` w 23ai (auto-SSO domyślnie włączony przy create). Skrypt pominął `mkstore -autoLogin` step.

**Poprawka v1.3:**

```bash
# Rename PWD->WP, SYS->SP, WALLET->WL (bez kolizji z bash builtins PWD/OLDPWD)
WL=$WALLET_DIR
WP='$WALLET_PWD'   # interpolowane w outer = 'Welcome1#Wallet'
SP='$SYS_PWD'      # = 'Welcome1#SYS'

mkstore -wrl $WL -create <<EOF
$WP
$WP
EOF
```

Plus:
- **Outer pre-check** (poza heredoc): jeśli wallet istnieje ale `mkstore -listCredential` z prawidłowym hasłem failuje → wipe (`rm -f $WL/*`) & recreate. Bez tego stale wallet z poprzedniego runa blokuje fix.
- **Final verify**: `mkstore -listCredential | grep -cE "(PRIM|STBY)_ADMIN"` musi zwrócić 2 — inaczej die z dump credentials.
- `mkstore -autoLogin` → `-createSSO` (w 23ai preferred syntax, `-autoLogin` jest alias backward-compat).

**Recovery dla istniejącego wallet z stale password:**
```bash
sudo rm -f /etc/oracle/wallet/observer-ext/*
sudo bash /tmp/scripts/setup_observer_infra01.sh   # v1.3
```

**Lekcja uniwersalna:** w bash NIGDY nie używaj `PWD`, `OLDPWD`, `IFS`, `PATH`, `HOME`, `USER`, `UID`, `EUID`, `RANDOM`, `SECONDS`, `LINENO`, `BASH_*` jako nazw lokalnych zmiennych — wszystkie są built-in. Heredoc + builtin = silent override w nieoczekiwanych miejscach. Reguła: nazwy zmiennych w bash heredoc-helpers powinny być 2-literowe nieoczywiste skróty (WP/SP/WL) — żadnej kolizji.

**Dodatkowo (UX):** mkstore w 23ai/26ai ma `-createSSO`, `-createLSSO`, `-createALO` w pomocy zamiast `-autoLogin` — choć backward-compat dla `-autoLogin` zachowane.

---

## FIX-072 — `SQLNET.AUTHENTICATION_SERVICES = (TCPS, NTS, BEQ)` blokuje wallet auto-login

**Data:** 2026-04-26 22:45 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.3 → **v1.4**, `VMs/11_fsfo_observer.md` sekcja 2.3

**Symptom:** Po FIX-071 (wallet z poprawnymi credentials, `mkstore -listCredential` zwracał `1: PRIM_ADMIN sys, 2: STBY_ADMIN sys` z hasłem `Welcome1#Wallet`) sekcja 4 nadal die-uła:

```
[..]   Test connectivity sqlplus /@PRIM_ADMIN...
[..] ERROR: Test PRIM_ADMIN sqlplus FAIL — sprawdz wallet credentials lub broker readiness.
```

Diagnoza dlaczego wallet OK ale sqlplus fail:

`sqlnet.ora` deployed przez skrypt v1.3 sekcja 2 zawierał:
```
SQLNET.AUTHENTICATION_SERVICES = (TCPS, NTS, BEQ)
```

**Wartości i ich znaczenie:**
- `TCPS` = SSL/TLS authentication (wymaga TLS certificates po obu stronach)
- `NTS` = NT Native Service (Windows-only — Active Directory pass-through)
- `BEQ` = Bequeath protocol (lokalny IPC, NIE sieciowy — tylko `sqlplus / as sysdba` z lokalnego hosta)
- `NONE` = pozwala na **password authentication** (wlacznie z wallet auto-login)

**Wallet auto-login** dla `sqlplus /@PRIM_ADMIN as sysdba`:
1. sqlplus czyta `cwallet.sso` (auto-login) → znajduje credential `PRIM_ADMIN sys/Welcome1#SYS`
2. **Wysyła hasło `Welcome1#SYS` do serwera w standardowy sposób (password auth)**
3. Serwer waliduje przeciwko password file (orapwd)

Z `(TCPS, NTS, BEQ)` w sqlnet.ora — sqlplus mówi "tylko TCPS, NTS lub BEQ allowed" → password auth blokowany → **ORA-01017 invalid username/password** (mimo że wallet ma poprawne hasło).

**Pattern z internetu wprowadza w błąd:** `(TCPS, NTS, BEQ)` to typowa "secure config" w blogach DBA — ale ta konfiguracja **wyłącza password auth całkowicie**. Dla wallet-based observerów / klientów aplikacyjnych zawsze należy mieć:

```
SQLNET.AUTHENTICATION_SERVICES = (NONE)
# albo brak linii (default = wszystkie metody włącznie z password)
```

**Poprawka v1.4:**
```diff
- SQLNET.AUTHENTICATION_SERVICES = (TCPS, NTS, BEQ)
+ SQLNET.AUTHENTICATION_SERVICES = (NONE)
```

Plus: usunięte `>/dev/null` z sqlplus test command, capture do `SQLPLUS_OUT` i echo przy fail. Bez tego die nie pokazywało dokładnego ORA-XXXXX (FIX-071 i FIX-072 były invisible przy pierwszej próbie).

**Recovery dla istniejącej infra01 (po v1.3):**
```bash
# 1. Manual edit sqlnet.ora (sekcja AUTHENTICATION_SERVICES):
sudo sed -i 's/(TCPS, NTS, BEQ)/(NONE)/' /etc/oracle/tns/ext/sqlnet.ora

# 2. Test:
su - oracle -c 'export TNS_ADMIN=/etc/oracle/tns/ext && sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT database_role FROM v\$database;
EXIT
EOF'
# Oczekiwane: PRIMARY (lub PHYSICAL STANDBY dla STBY_ADMIN)

# 3. Albo full re-run v1.4:
sudo bash /tmp/scripts/setup_observer_infra01.sh
```

**Lekcja uniwersalna:**
- `SQLNET.AUTHENTICATION_SERVICES` to często źle zrozumiana dyrektywa. Reguły:
  - **Wallet-based password auth** (typowe dla observerów, JDBC apps, automation) → `(NONE)` lub brak linii
  - **TLS-only deployment** (mTLS z certyfikatami) → `(TCPS)` (i tylko TCPS)
  - **Windows AD integration** → `(NTS)` plus `(NONE)` jako fallback
  - **Lokalny BEQ** (sqlplus / as sysdba na DB host) → `(BEQ, NONE)` — BEQ first, password fallback
- **Default jest najbezpieczniejszy:** brak linii = wszystkie metody przyjmowane → wallet auto-login działa.
- Każdy `INS-*` lub `ORA-01017` z wallet = **najpierw sprawdź sqlnet.ora `SQLNET.AUTHENTICATION_SERVICES`** zanim zaczniesz dłubać w mkstore.

**Powiązane wcześniejsze fixy:**
- FIX-071 (wallet stale password) — myślałem że to jest root cause, ale był to dystraktor
- FIX-053 (pre-flight tnsping) — łapie ORA-12154/12541, ale NIE łapie ORA-01017 (bo tnsping nie loguje się, tylko sprawdza alias resolve)

---

## FIX-073 — Heredoc + `su - oracle -c` double-shell escape gubi `\$`

**Data:** 2026-04-26 22:50 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.4 → **v1.5**, `VMs/11_fsfo_observer.md` sekcja 3.5

**Symptom:** Po FIX-072 (sqlnet.ora `(NONE)`) sekcja 4 sqlplus wallet test zwraca:
```
[..]   Test connectivity sqlplus /@PRIM_ADMIN...
SELECT database_role FROM v
                          *
ERROR at line 1:
ORA-00942: table or view "SYS"."V" does not exist
```

Wallet OK (manual `sqlplus /@PRIM_ADMIN` jako oracle zwraca `PRIMARY`), ale przez skrypt (`su - oracle -c "..."`) heredoc traci escape — SQL trafia jako `SELECT database_role FROM v;` zamiast `... FROM v$database;`.

**Diagnoza:** v1.4 sekcja 4 sqlplus test:
```bash
su - oracle -c "export TNS_ADMIN=$TNS_DIR && $ORACLE_HOME/bin/sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE
SELECT database_role FROM v\$database;
EXIT
EOF"
```

Flow expansion przez **2 poziomy shell**:

1. **Outer bash** (root) widzi `"...v\$database..."` w double quotes:
   - W double quotes, `\$` jest **escape sequence** dla literal `$` (bash man: "The backslash retains its special meaning only when followed by one of the following characters: $, `, \", \\, or <newline>")
   - Po expansion: `"...v$database..."`
   - Argument przekazany do `bash -c`: string zawierający `v$database`

2. **Inner bash** (oracle, z `su - oracle -c "..."`) wykonuje string:
   - Heredoc `<<EOF` (unquoted tag) → bash interpoluje zmienne wewnątrz
   - `$database` → undefined zmienna → empty string
   - SQL po expansion: `SELECT database_role FROM v;`

3. **sqlplus** dostaje `SELECT database_role FROM v;` → ORA-00942.

**Manual test jako oracle (single-shell)** nie ma tego problemu:
```bash
[oracle@infra01 ~]$ sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT database_role FROM v\$database;
EXIT
EOF
# OK: zwraca PRIMARY
```
Tu jest **jeden poziom expansion** — bash widzi `\$database` w heredoc context, escape działa, SQL = `v$database`.

**Poprawka v1.5 — SQL przez tymczasowy plik z quoted heredoc:**

```bash
SQLF=/tmp/test_sqlplus.$$.sql
cat > "$SQLF" <<'SQL_EOF'        # 'SQL_EOF' (quoted) = NIE interpoluje
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
echo "$SQLPLUS_OUT" | grep -qE "PRIMARY" || die "Output nie zawiera PRIMARY"
```

Quoted heredoc `<<'SQL_EOF'` blokuje interpolację — `$database` zapisane do pliku **dosłownie**. sqlplus uruchomiony z `@$SQLF` (skrypt SQL) — bezpieczne dla wszystkich nazw obiektów (`v$session`, `gv$instance`, `dba_dg_broker_config_properties` itd).

**Alternatywa — potrójny escape `\\\$database`** w outer:
```bash
su - oracle -c "...sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT database_role FROM v\\\$database;
EOF"
```
Działa, ale **nieczytelne** (3 escape levels: `\\\$` → outer `\$` → inner literal `$` w heredoc). Plik SQL jest cleaner i mniej podatny na regression przy edycji.

**Lekcja uniwersalna:**
- W bash NIGDY nie inline-uj heredoc z `$variable references` przez `su - user -c "..."` (lub `ssh user@host "..."`, `bash -c "..."`). Każdy poziom shell zjada jeden poziom escape.
- **Reguła praktyczna dla skryptów wrapper:** SQL/PL/SQL z `$` references → tymczasowy plik z quoted heredoc (`<<'EOF'`) → uruchomienie przez `sqlplus @file`.
- Manual run w pojedynczym shellu (jeden user, bez `su -c`) — zwykły `\$` escape działa.
- **Diagnostyka:** ORA-00942 z `*` wskazującym na `v` (zamiast `v$database`) = klasyczny shell escape bug. Sprawdź czy SQL jest wywoływany w double-shell context.

**Powiązane:** FIX-072 (sqlnet.ora AUTHENTICATION_SERVICES) — był prawdziwym root cause sqlplus connect fail. FIX-073 to drugi bug **w tym samym kawałku kodu** (sekcja 4 sqlplus test) — odsłonił się dopiero po naprawieniu FIX-072.

---

## FIX-074 — DGMGRL syntax/flag changes w 23ai/26ai (3 zmiany w jednym pipeline)

**Data:** 2026-04-26 22:55 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.5 → **v1.6**, `VMs/11_fsfo_observer.md` sekcje 6.2/6.3/6.4

**Symptom:** Po FIX-073 (sekcja 4 sqlplus przeszedł, sekcje 5/6 częściowo) sekcja 6 + 7 dały trzy oddzielne błędy:

```
DGMGRL> ADD OBSERVER obs_ext ON infra01.lab.local;
    ^
Syntax error before or at "OBSERVER"
DGMGRL>
Configuration - prim_dg
  Protection Mode: MaxAvailability
  ...
[..]   ✓ FSFO properties + ADD OBSERVER zaaplikowane (re-run safe)   ← fałszywy sukces
[..] Sekcja 7 — Uruchomienie systemd observera...

# journalctl:
Apr 26 22:51:25 dgmgrl[9009]: Unknown option: -logfile
Apr 26 22:51:25 dgmgrl[9009]: Usage: dgmgrl [<options>] [<logon> [<command>]]
Apr 26 22:51:25 dgmgrl[9009]:   <options> ::= -silent | -echo

# ExecStop tries to STOP observer:
Apr 26 22:51:27 dgmgrl[9013]: Error: ORA-16873: The observer with the specified name is not started.
Apr 26 22:51:27 systemd[1]: dgmgrl-observer-obs_ext.service: Succeeded.

[22:51:40] ERROR: systemd dgmgrl-observer-obs_ext nie jest active.
```

**Trzy oddzielne 23ai/26ai breaking changes w jednym pipeline:**

### #1 — `ADD OBSERVER` syntax change

| | 19c | 23ai/26ai |
|---|---|---|
| Składnia | `ADD OBSERVER name ON host_name` | `ADD OBSERVER 'name' ON HOST 'host_name'` |
| Keyword `HOST` | brak | **wymagany** |
| Cudzysłowy | opcjonalne | wymagane przy nazwach |

19c-style w 26ai zwraca: `Syntax error before or at "OBSERVER"` (parser nie rozpoznaje OBSERVER token bo `ADD` w 26ai oczekuje innych następników z keyword HOST).

Reference: `docs.oracle.com/en/database/oracle/oracle-database/23/dgbkr/oracle-data-guard-broker-commands.html`

```
ADD OBSERVER ['observer_name'] ON HOST 'host_name' [TO CONFIGURATION 'configname']
```

### #2 — `dgmgrl -logfile` flag USUNIĘTY

Pomoc dgmgrl w 23ai/26ai pokazuje **tylko 2 flagi**:
```
<options> ::= -silent | -echo
```

`-logfile path` był dostępny w 19c — w 23ai/26ai usunięty. Logging observera idzie wyłącznie przez **`LOGFILE='...'` clause w komendzie `START OBSERVER`** (juz było, ale `-logfile` jako outer dgmgrl flag zabija proces zanim execute `START OBSERVER`).

Skutek z `-logfile` w systemd ExecStart:
1. dgmgrl widzi `-logfile path` → exit z `Unknown option` + usage
2. systemd uznaje za crash startup
3. systemd próbuje cleanup przez ExecStop: `dgmgrl /@PRIM_ADMIN "STOP OBSERVER 'obs_ext'"`
4. ExecStop zwraca ORA-16873 "observer not started" (bo nigdy nie wystartował)
5. systemd: `Succeeded` (z punktu widzenia stop OK), service: inactive (dead)
6. Skrypt: `systemctl is-active --quiet` → 1 → die

### #3 — Cudzysłowy w `SET MASTEROBSERVER` i `STOP OBSERVER`

Spójnie z `ADD OBSERVER 'name'` — wszystkie komendy operujące na observer name powinny używać cudzysłowów:
```
SET MASTEROBSERVER TO 'obs_ext';
STOP OBSERVER 'obs_ext';
```

Bez cudzysłowów w niektórych edge cases (nazwa zaczynająca się od liczby, zawierająca dash) parser może nie zaakceptować. W lab z `obs_ext` może pominąć — ale dla spójności.

**Poprawka v1.6:**

```bash
# Sekcja 5 (systemd unit ExecStart):
# v1.5: dgmgrl -echo -logfile $LOG_DIR/${OBSERVER_NAME}.log /@PRIM_ADMIN "START..."
# v1.6: dgmgrl -echo /@PRIM_ADMIN "START OBSERVER '${OBSERVER_NAME}' FILE='...' LOGFILE='...'"

# Sekcja 6 (ADD OBSERVER):
# v1.5: ADD OBSERVER ${OBSERVER_NAME} ON ${OBSERVER_HOST};
# v1.6: ADD OBSERVER '${OBSERVER_NAME}' ON HOST '${OBSERVER_HOST}';

# Sekcja 8 (SET MASTEROBSERVER):
# v1.5: SET MASTEROBSERVER TO ${OBSERVER_NAME};
# v1.6: SET MASTEROBSERVER TO '${OBSERVER_NAME}';
```

**Plus poprawka w idempotency check (sekcja 6 fałszywy sukces):**

v1.5 idempotency check po dgmgrl heredoc:
```bash
if echo "$DGMGRL_FLAT" | grep -qiE "ORA-(16664|16606|16672)"; then
    die "FSFO properties FAIL ..."
fi
log "  ✓ FSFO properties + ADD OBSERVER zaaplikowane"   ← fałszywy sukces
```

`ADD OBSERVER` syntax error nie zwraca ORA-XXXX (to parser error, nie SQL error). Skrypt nie wykrył failure → continue. **TODO v1.7:** dodać grep na `Syntax error before or at` jako die-pattern.

**Recovery dla obecnego stanu na infra01:**
```bash
# 1. Stop systemd (już inactive, ale wykona daemon-reload na nowy unit)
sudo systemctl stop dgmgrl-observer-obs_ext 2>/dev/null || true
sudo systemctl disable dgmgrl-observer-obs_ext 2>/dev/null || true

# 2. Cleanup observer dat/log z poprzedniego nieudanego runu
sudo rm -f /var/log/oracle/observer/obs_ext.dat /var/log/oracle/observer/obs_ext.log

# 3. SCP v1.6 i re-run
scp <repo>/VMs/scripts/setup_observer_infra01.sh root@infra01:/tmp/scripts/
ssh root@infra01 "bash /tmp/scripts/setup_observer_infra01.sh"
```

**Lekcja uniwersalna:** każda komenda dgmgrl/sqlplus z 19c skryptów wymaga audytu w 23ai/26ai. Pattern dla skryptu wrappera:
1. **Syntax keywords** — w 23ai dodano keywords (HOST, MAINTAINED AS removed) lub usuneto (DECLINE_SECURITY_UPDATES, asmSysPassword)
2. **Flags** — narzędzia mają mniej flag (`dgmgrl -logfile` removed, `dgmgrl -v` removed — używaj `dgmgrl` bez args dla version)
3. **Quoting** — 23ai wymaga cudzysłowów wokół identifier names w wielu miejscach
4. **Multiline output** — `SHOW *` wszystkie multiline (FIX-065/067)
5. **Async behavior** — `ENABLE *` async, retry loops (FIX-062/064/069)

**Skumulowane fixy DGMGRL w obecnej sesji:**
- FIX-061 — `ADD DATABASE` bez `MAINTAINED AS PHYSICAL`
- FIX-065 — multiline grep dla `SHOW CONFIGURATION`
- FIX-067 — multiline grep dla `SHOW FAST_START FAILOVER`
- **FIX-074 — `ADD OBSERVER` z `ON HOST`, `dgmgrl -logfile` removed, cudzysłowy wokół nazw**

---

## FIX-075 — DGMGRL prawdziwa składnia 26ai (uzyskana z `HELP`, FIX-074 zgadnięte źle)

**Data:** 2026-04-26 23:00 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.6 → **v1.7**, `VMs/11_fsfo_observer.md` sekcje 6.2/6.3/6.4

**Symptom:** Po FIX-074 (zgadnięte składnie z 19c→23ai migration patterns) skrypt nadal die-uł:

```
DGMGRL> ADD OBSERVER 'obs_ext' ON HOST 'infra01.lab.local';
    ^
Syntax error before or at "OBSERVER"

# systemd ExecStart:
dgmgrl[9535]: START OBSERVER 'obs_ext' FILE='/var/log/oracle/observer/obs_ext.dat' LOGFILE='/var/log/oracle/observer/obs_ext.log'
                              ^
dgmgrl[9535]: Syntax error before or at "FILE"
```

**Diagnoza empiryczna (przez `dgmgrl HELP`):** zamiast zgadywać składnie z internetu/blogów, sięgnąłem po built-in `HELP` w dgmgrl 26ai:

### `HELP START OBSERVER` (faktyczna składnia 26ai):

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
| FILE clause | `FILE='<file>'` | `FILE IS <file>` (keyword `IS`, nie `=`) |
| LOGFILE clause | `LOGFILE='<file>'` | `LOGFILE IS <file>` |
| observer-name | bez cudzysłowów | bez cudzysłowów (regular identifier) |
| dgmgrl `-logfile` flag | dostępny | usunięty (tylko `-silent`/`-echo`) |

### `HELP ADD OBSERVER` (faktyczna w 26ai):

```
ADD CONFIGURATION [<configuration-name>] CONNECT IDENTIFIER IS <connect-identifier>;
ADD { DATABASE | FAR_SYNC | MEMBER | RECOVERY_APPLIANCE } <db-unique-name> ...;
ADD PLUGGABLE DATABASE <pdb-name> AT <target-db-unique-name> ...;
```

**`ADD OBSERVER` USUNIĘTE.** Tylko `ADD CONFIGURATION/DATABASE/MEMBER/PLUGGABLE DATABASE` zostały. Observer jest dodawany **automatycznie** przy `START OBSERVER` — broker tworzy persistent record po pierwszym successful start.

### `HELP SHOW OBSERVER` (potwierdza brak ADD):

```
SHOW OBSERVER;
SHOW OBSERVERS [FOR <configuration-group-name>];
SHOW OBSERVERCONFIGFILE;
```

`SHOW` ma 3 warianty observerów, ale `ADD OBSERVER` nie ma odpowiednika.

### `SET MASTEROBSERVER` w single-observer 26ai

W 26ai pierwszy uruchomiony observer staje się **automatycznie master**. `SET MASTEROBSERVER TO name` wymagany tylko przy multi-observer quorum (3-of-3 FSFO — doc 16). Single observer = niepotrzebne.

**Poprawka v1.7 (4 zmiany):**

```diff
# Sekcja 5 systemd ExecStart:
- ExecStart=... dgmgrl -echo /@PRIM_ADMIN "START OBSERVER 'obs_ext' FILE='...' LOGFILE='...'"
+ ExecStart=... dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_ext FILE IS '...' LOGFILE IS '...'"

# Sekcja 6 (USUNIĘTE całkowicie):
- ADD OBSERVER 'obs_ext' ON HOST 'infra01.lab.local';

# Sekcja 8 (USUNIĘTE):
- SET MASTEROBSERVER TO 'obs_ext';
  ENABLE FAST_START FAILOVER;

# Sekcja 6 idempotency check (DODANE):
+ if echo "$DGMGRL_FLAT" | grep -qiE "Syntax error before or at"; then
+     die "FSFO properties: dgmgrl SYNTAX ERROR — sprawdz output wyzej."
+ fi
```

**Lekcja uniwersalna:** zamiast zgadywać składnie 23ai/26ai z 19c→23ai migration blogs/internet snippets — **najpierw `dgmgrl HELP <command>`**. dgmgrl ma built-in pomoc dla każdej komendy z dokładną składnią dla swojej wersji. To 60-sekundowa diagnostyka która ratuje przed iteracjami "FIX-074, FIX-074a, FIX-074b...".

**Pattern do zapisu:**
```
dgmgrl /@PRIM_ADMIN
DGMGRL> HELP <command>          # dla pojedynczej komendy
DGMGRL> HELP <verb>             # dla głównego verb (HELP ADD pokazuje wszystkie ADD *)
DGMGRL> HELP                    # pełna lista komend
```

Zapis na przyszłość (uniwersalny dla każdego skryptu wrapper na dgmgrl/sqlplus): **przy każdym pierwszym uruchomieniu w nowej wersji Oracle wykonaj `HELP <key-command>` jako sanity check**.

**Skumulowane fixy DGMGRL syntax dla 26ai (FIX-074 → FIX-075):**
- ❌ `ADD OBSERVER` — usunięty
- ❌ `dgmgrl -logfile` — usunięty (tylko `-silent`/`-echo`)
- ❌ `dgmgrl -v` — usunięty (wersja w banner przy zwykłym uruchomieniu)
- ✅ `START OBSERVER name FILE IS '<f>' LOGFILE IS '<f>'` — z keyword `IS`, bez cudzysłowów wokół name
- ✅ `STOP OBSERVER name` — bez cudzysłowów (jak w `START`)
- ➕ Single observer = auto-master, `SET MASTEROBSERVER` opcjonalne (tylko multi-observer quorum)
- ➕ Wszystkie `SHOW *` multiline output → `tr '\n' ' '` przed grep (FIX-065/067)
- ➕ Wszystkie `ENABLE *` async → retry loop 180s w VBox lab (FIX-062/064/069)

---

## FIX-076 — FSFO Zero Data Loss Mode wymaga Flashback Database na PRIM + STBY

**Data:** 2026-04-26 23:07 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.7 → **v1.8**, `VMs/11_fsfo_observer.md` prereq + sekcja 5 noticebox, `VMs/09_standby_duplicate.md` TODO v3.4

**Symptom:**
```
[23:06:56] Sekcja 8 — ENABLE FAST_START FAILOVER (single observer = auto-master)...
DGMGRL> ENABLE FAST_START FAILOVER;
Warning: ORA-16827: Flashback Database is disabled.

Enabled in Potential Data Loss Mode.   ← NIE Zero Data Loss
```

Skrypt v1.7 sekcja 9 verify znalazł `Fast-Start Failover: ENABLED` (status OK) → DONE. Ale **Mode = Potential Data Loss** zamiast `Zero Data Loss` — bez gwarancji zero data loss przy failover.

**Diagnoza:** `ORA-16827: Flashback Database is disabled` — broker nie znalazł flashback YES na obu stronach. Test:
```sql
-- Na prim01:
SELECT db_unique_name, flashback_on FROM v$database;
-- PRIM, YES   ← OK (włączone w doc 08 / fsfo_check_readiness PASS)

-- Na stby01:
SELECT db_unique_name, flashback_on FROM v$database;
-- STBY, NO    ← problem (NIE włączone post-duplicate)
```

**Root cause:** `duplicate_standby.sh` v3.3 sekcja 9b ustawia `log_archive_dest_2` (FIX-049), ale **NIE** włącza flashback na STBY. Flashback jest per-database setting (nie replikowany przez RMAN duplicate) — musi być włączony osobno na każdej stronie.

`fsfo_check_readiness.sql` sekcja 0 sprawdza tylko **lokalny PRIM** (skrypt działa z prim01) — STBY nie jest w scope.

**Dlaczego flashback wymagany na STBY:**
1. **REINSTATE DATABASE po failover** — broker rewinduje stary primary do SCN przed failover, otwiera jako standby. Bez flashback → musisz re-utworzyć przez RMAN duplicate (długie, doc 09 procedura).
2. **FSFO Zero Data Loss Mode** — broker może gwarantować zero data loss tylko jeśli oba sites mogą się "cofnąć" do consistent state w przypadku split-brain.
3. **Switchback** — po przełączeniu z powrotem na original primary, flashback przyspiesza convergence.

**Poprawka v1.8 (2 sekcje, warn-only):**

```bash
# Sekcja 4.6 (NEW) — pre-flight verify Flashback Database na PRIM + STBY
# Robi sqlplus przez wallet do PRIM_ADMIN i STBY_ADMIN, sprawdza FLASHBACK_ON.
# Warn-only (skrypt kontynuuje z hint do recovery procedury).

# Sekcja 9 (UPDATE) — verify Mode w SHOW FAST_START FAILOVER:
if echo "$FSFO_FLAT" | grep -qE "Mode:[[:space:]]*ZERO DATA LOSS"; then
    log "  ✓ FSFO Mode: ZERO DATA LOSS"
elif echo "$FSFO_FLAT" | grep -qE "Mode:[[:space:]]*POTENTIAL DATA LOSS"; then
    warn "FSFO Mode: POTENTIAL DATA LOSS - flashback database disabled..."
    warn "Recovery: wlacz flashback na obu stronach, potem DISABLE/ENABLE FSFO"
fi
```

**Recovery procedura dla istniejącego deployment:**

1. **Verify obie strony:**
   ```sql
   -- Z infra01 (przez wallet):
   sqlplus /@PRIM_ADMIN as sysdba <<EOF
   SELECT flashback_on FROM v\$database;
   EOF

   sqlplus /@STBY_ADMIN as sysdba <<EOF
   SELECT flashback_on FROM v\$database;
   EOF
   ```

2. **Włącz flashback na STBY (bo PRIM zwykle YES po doc 08):**
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

3. **Re-enable FSFO w Zero Data Loss Mode:**
   ```
   DGMGRL> DISABLE FAST_START FAILOVER;
   DGMGRL> ENABLE FAST_START FAILOVER;
   # Enabled in Zero Data Loss Mode.   ← bez warning ORA-16827

   DGMGRL> SHOW FAST_START FAILOVER;
   # Mode: ZERO DATA LOSS
   ```

**Warunki dla `ALTER DATABASE FLASHBACK ON`:**
- Database w MOUNT mode (NIE OPEN — bounce wymagany na STBY w 19c i 23ai/26ai)
- `db_recovery_file_dest` skonfigurowany (FRA) — w naszym lab `/u03/fra` z FIX-049
- `db_recovery_file_dest_size` >= 14G (default w FIX-049)
- `db_flashback_retention_target` opcjonalne (default 1440 min = 24h)

**TODO v3.4 dla `duplicate_standby.sh`:** dodać sekcję 9c:
```bash
# Po sekcji 9b (log_archive_dest_2 FIX-049):
log "Sekcja 9c — Wlacz Flashback Database na STBY (FIX-076)..."
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

To zautomatyzuje recovery — następny clean rebuild będzie miał Zero Data Loss Mode od pierwszej próby.

**Lekcja uniwersalna:**
- **FSFO != ENABLE OK.** ENABLE FAST_START FAILOVER może wrócić sukces ale w `Potential Data Loss Mode` (warning, nie error). Skrypt verify musi sprawdzać **Mode**, nie tylko Status.
- **Flashback per-database**, NIE replikowany przez RMAN duplicate. Musi być włączony osobno na każdej stronie (PRIM przez DBCA/manual, STBY post-duplicate).
- **`ALTER DATABASE FLASHBACK ON` na STBY wymaga MOUNT** (bounce z OPEN READ ONLY). Plus stop apply → włącz flashback → start apply z USING CURRENT LOGFILE.
- **Pre-flight w skryptach FSFO** musi sprawdzać flashback na **obu** stronach, nie tylko local.

---

## FIX-077 — `Potential Data Loss Mode` w MaxAvailability jest BY DESIGN (nie bug)

**Status:** **RESOLVED empirycznie** (2026-04-26 23:37, ORA-16903).

### TL;DR

W Oracle 23ai/26ai broker FSFO Mode jest **strikly determined** przez Protection Mode:

| Protection Mode | LagLimit allowed | FSFO Mode (SHOW FSFO) |
|---|---|---|
| **MaxProtection** | 0 lub > 0 | **Zero Data Loss Mode** |
| **MaxAvailability** | **MUST be > 0** (broker odrzuca 0 z ORA-16903) | **Potential Data Loss Mode** (always) |
| MaxPerformance | dowolna | Potential Data Loss Mode (always) |

**MaxAvailability + LagLimit=0 = ORA-16903** (broker enforce, nie konfiguracyjny niedopatrzenie).

### Empirical proof

Sesja 23:37 — wszystkie pre-conditions OK:
- LogXptMode=SYNC na PRIM + stby
- protection_mode = MAXIMUM AVAILABILITY
- protection_level = MAXIMUM AVAILABILITY (matchuje, no downgrade)
- transmit_mode = PARALLELSYNC, affirm = YES, status = VALID, error = empty
- Apply Lag 0s, Transport Lag 0s, Database Status SUCCESS na obu
- flashback_on = YES na obu
- LagLimit = 30 (Oracle default)

`SHOW FAST_START FAILOVER` → `Enabled in Potential Data Loss Mode`. Próba zmienić LagLimit:
```
DGMGRL> EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
Error: ORA-16903: change of FastStartFailoverLagLimit property violates configuration protection mode
```

**Wniosek:** broker **enforce** że MaxAvailability MUSI mieć LagLimit > 0. Konsekwencja: w MaxAvailability FSFO Mode jest **zawsze** "Potential Data Loss Mode" w SHOW, niezależnie od SYNC+AFFIRM+Flashback.

### Co "Potential Data Loss Mode" naprawdę oznacza

**`Potential` ≠ rzeczywista utrata danych.** To broker theoretical classification:
- Z SYNC+AFFIRM: primary nie commitje aż standby ack → real-world zero data loss
- Apply lag = 0s stale (real-time apply z SRL) → przy każdej decyzji failover lag=0
- Broker dopuszcza że *w teorii* z LagLimit > 0 mógłby zaakceptować failover z lag > 0 → "potential"
- W lab/produkcji z SYNC stable → "potential" się nigdy nie materializuje

### Hipoteza 1 (moja FIX-077 wstępna) — częściowo OK, częściowo zła

**OK:** LagLimit faktycznie wpływa na FSFO Mode classification.
**Zła:** Założyłem że można "naprawić" przez `LagLimit=0`. Broker enforce reguły protection mode → ORA-16903. Naprawa nie jest możliwa w MaxAvailability.

### Hipoteza 2 (drugi agent — transport ASYNC) — błędna

**Empirycznie obalona:** transport jest PARALLELSYNC + AFFIRM (SYNC), protection_level matchuje protection_mode. Z perspektywy transport wszystko OK. "Potential Data Loss Mode" nie pochodzi z transport mode.

### Decyzja projektowa

Lab MAA Oracle 26ai zostaje przy:
- **Protection Mode: MaxAvailability** (production standard)
- **LagLimit: 30** (Oracle default, mandatory > 0)
- **FSFO Mode: Potential Data Loss Mode** (display) — accepted as correct steady-state

**Alternative dla edukacyjnego "Zero Data Loss Mode" w SHOW:**

Migracja na MaxProtection (caveat: primary shutdown gdy standby unreachable):
```
DGMGRL> EDIT CONFIGURATION SET PROTECTION MODE AS MaxProtection;
DGMGRL> EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
DGMGRL> DISABLE FAST_START FAILOVER;
DGMGRL> ENABLE FAST_START FAILOVER;
# Enabled in Zero Data Loss Mode.
```

W lab nie robimy tego (chcemy production-realistic config). Doc 14 testy switchover/failover działają identycznie w obu trybach.

### Skrypt v1.9 (rollback FIX-077 partial fix, akceptacja steady-state)

```bash
# sekcja 6 dgmgrl heredoc (BEZ zmian względem v1.8):
EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=30;   # mandatory > 0 dla MaxAvail
EDIT DATABASE PRIM SET PROPERTY LogXptMode='SYNC';   # sanity re-set (defensive po flashback recovery)
EDIT DATABASE stby SET PROPERTY LogXptMode='SYNC';
```

**Sekcja 9 verify Mode:** info-only logging (nie warn ani die):
- `Mode: ZERO DATA LOSS` → log "✓ Zero Data Loss Mode"
- `Mode: POTENTIAL DATA LOSS` → log "ℹ EXPECTED for MaxAvailability + LagLimit > 0; realny risk = 0 z SYNC+AFFIRM"

### Lekcje uniwersalne

1. **`Potential Data Loss Mode` ≠ ASYNC transport.** Empirycznie obalona popularna hipoteza (drugi agent). Transport może być SYNC+AFFIRM a Mode wciąż "Potential" — zależy od Protection Mode.
2. **Nie można "fix" Mode w MaxAvailability** przez LagLimit=0 — broker enforce ORA-16903.
3. **MaxProtection** = jedyna ścieżka do "Zero Data Loss Mode" w SHOW — caveat primary shutdown.
4. **W production MAA** Oracle: MaxAvailability + LagLimit > 0 + "Potential Data Loss Mode" jest standard. Realny zero loss z SYNC+AFFIRM.
5. **Diagnostyka FSFO Mode anomaly** — sprawdź protection_mode, LagLimit, broker enforces:
   - MaxAvailability MUST LagLimit > 0 → Mode = Potential (always)
   - MaxProtection MAY LagLimit = 0 → Mode = Zero Data Loss
   - MaxPerformance → Mode = Potential (always)

---

## ~~FIX-077 stara wersja (TBD hipotezy konkurujące) — usunięta~~

Wcześniejszy draft (hipoteza 1 vs hipoteza 2) został zastąpiony powyższym RESOLVED. Empirical proof obalił obie wstępne hipotezy — prawda była trzecia: broker enforce reguły protection mode.

### ~~Hipoteza 1 (moja, prawdopodobnie błędna): LagLimit > 0~~

**Data:** 2026-04-26 23:25 | **Plik:** `VMs/scripts/setup_observer_infra01.sh` v1.8 → **v1.9**, `VMs/11_fsfo_observer.md` sekcja 4 + 5

**Symptom:** Po FIX-076 (flashback YES na PRIM + STBY potwierdzony) DISABLE/ENABLE FSFO **nadal** zwracał `Enabled in Potential Data Loss Mode`. Wszystkie inne pre-conditions OK:
- Protection Mode: MaxAvailability ✓
- LogXptMode: SYNC PRIM + STBY ✓
- v$archive_dest dest_id=2: **PARALLELSYNC + AFFIRM=YES** ✓ (FIX-066)
- Flashback: YES na obu ✓
- StatusReport PRIM + STBY: czysty (brak warningów) ✓
- MRP: APPLYING_LOG, lag = 0s ✓

**Diagnoza myth — "Potential Data Loss = ASYNC transport":**

User postawił hipotezę: "Potential Data Loss Mode oznacza że transport działa w ASYNC/NOAFFIRM zamiast SYNC/AFFIRM. To widać było w skrypcie duplicate — log_archive_dest_2 miał ASYNC NOAFFIRM."

**FALSE.** "FSFO Mode" w `SHOW FAST_START FAILOVER` to **derived attribute** brokera, NIE odzwierciedla bezpośrednio transport mode. To dwie różne warstwy:

| Warstwa | Gdzie | Sprawdza |
|---|---|---|
| Transport mode | `v$archive_dest.transmit_mode` + `affirm` | Jak redo dociera (SYNC/ASYNC) |
| FSFO Mode | `SHOW FAST_START FAILOVER` | Czy broker gwarantuje zero data loss przy failover decyzji |

`duplicate_standby.sh` v3.3 ustawiał **baseline** `log_archive_dest_2='ASYNC NOAFFIRM'`, ale `configure_broker.sh` v2.9 po `EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability` + `EDIT DATABASE * SET PROPERTY LogXptMode='SYNC'` **przepisał** to na `PARALLELSYNC AFFIRM`. Verified w sekcji 3 skryptu i w `v$archive_dest`.

**Prawdziwa przyczyna — `FastStartFailoverLagLimit > 0`:**

Broker definiuje 4 pre-conditions AND dla Zero Data Loss Mode w MaxAvailability:
```
Zero Data Loss Mode =
    Protection Mode in {MaxAvailability, MaxProtection}
    AND LogXptMode = 'SYNC' on all members
    AND Flashback Database = YES on all members
    AND FastStartFailoverLagLimit = 0
```

`LagLimit > 0` mówi brokerowi: "Akceptuję failover gdy apply lag ≤ N sekund". To **z definicji** oznacza że w momencie failover w SRL na PRIM mogą siedzieć zatwierdzone (commited) transactions które jeszcze nie dotarły do STBY (apply lag) → te transactions zginą po failover → **Potential Data Loss Mode**.

`LagLimit = 0` = "zero lag tolerance" → failover tylko gdy `apply lag = 0s` → **Zero Data Loss** zagwarantowane przez SYNC+AFFIRM transport.

**Doku Oracle 23ai:** "In MaxAvailability mode, set `FastStartFailoverLagLimit=0` for zero data loss FSFO. `LagLimit > 0` indicates broker tolerates failover with apply lag — by definition Potential Data Loss."

**Konflikt z `FastStartFailoverThreshold` — NIE myl:**
- **Threshold = 30s** = max czas **BRAKU heartbeat** z primary zanim observer ogłosi failover (network/health timeout)
- **LagLimit = 0** = max **apply lag** dla failover decyzji (data freshness)

Dwa różne metryki. Threshold zostaje 30s niezależnie od Mode.

**Poprawka v1.9:**

```diff
# Sekcja 6 dgmgrl heredoc:
- EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=30;
+ EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
```

**Recovery dla istniejącego deploymentu:**
```
DGMGRL> EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
DGMGRL> DISABLE FAST_START FAILOVER;
DGMGRL> ENABLE FAST_START FAILOVER;
# Enabled in Zero Data Loss Mode.    ← target
```

**Lekcja uniwersalna:** `Potential Data Loss Mode` w SHOW FAST_START FAILOVER **NIE jest synonimem ASYNC transport**. To wynik kombinacji wielu properties. Diagnostyka:
1. Sprawdź `Protection Mode` (MaxAvailability vs MaxPerformance)
2. Sprawdź `LogXptMode` na każdym member (SHOW DATABASE * LogXptMode)
3. Sprawdź `flashback_on` na każdym member
4. Sprawdź `FastStartFailoverLagLimit` (=0 dla Zero Data Loss)
5. Sprawdź StatusReport każdego member (warningi blokujące)

Tylko wszystkie 5 OK → broker derywuje Zero Data Loss Mode.

**Wartości baseline z 19c blogów (LagLimit=30, LagLimit=120) są NIEAKTUALNE** dla Zero Data Loss Mode w 23ai/26ai. Default Oracle dla LagLimit = 30 zostaje, ale **nie matchuje** modern best practice "zero data loss FSFO". Zawsze explicite `LagLimit=0` przy MaxAvailability.

### Hipoteza 2 (drugi agent): LogXptMode/Transport ASYNC

> "Potential Data Loss Mode pochodzi wyłącznie z trybu transportu:
> - ASYNC + NOAFFIRM → Potential Data Loss
> - SYNC + AFFIRM → Zero Data Loss
> Musisz zmienić LogXptMode na obu bazach."

**Argument za:** Oracle docs "Fast-Start Failover Modes":
> Zero Data Loss Mode = MaxProtection lub MaxAvailability + **synchronous redo transport (LogXptMode=SYNC) + AFFIRM**

**Co zostało już zrobione (configure_broker.sh v2.9 sekcja 3):**
- `EDIT DATABASE PRIM SET PROPERTY LogXptMode='SYNC'` ✓
- `EDIT DATABASE stby SET PROPERTY LogXptMode='SYNC'` ✓
- Verify `D2_TRANSMIT=PARALLELSYNC,D2_AFFIRM=YES` ✓ (FIX-066)

**Możliwe że post recovery flashback STBY** (SHUTDOWN → STARTUP MOUNT → ALTER DATABASE FLASHBACK ON → OPEN) broker **downgraded** transport runtime mimo że configured value to SYNC. To zostawia LogXptMode='SYNC' w broker.config, ale `protection_level` w `v$database` może być `RESYNCHRONIZATION` lub innym non-MaxAvailability.

### Plan diagnostyki dla user-a

**Test 1: LogXptMode w broker config (configured intent):**
```
DGMGRL> SHOW DATABASE PRIM LogXptMode;
DGMGRL> SHOW DATABASE stby LogXptMode;
```
Oba muszą być SYNC. Jeśli któryś ASYNC → root cause confirmed (Hipoteza 2).

**Test 2: Protection Level (runtime achieved):**
```sql
SELECT db_unique_name, protection_mode, protection_level FROM v$database;
```
- protection_mode = MAXIMUM AVAILABILITY (configured)
- protection_level = MAXIMUM AVAILABILITY (jeśli OK) lub RESYNCHRONIZATION/MAXIMUM PERFORMANCE (downgraded)

Mismatch = transport runtime nie matchuje config → root cause Hipoteza 2.

**Test 3: v$archive_dest details:**
```sql
SELECT dest_id, transmit_mode, affirm, status, error
FROM v$archive_dest WHERE dest_id=2;
```
- transmit_mode IN (SYNCHRONOUS, PARALLELSYNC) ✓
- affirm = YES ✓
- status = VALID
- error = (empty)

Jeśli status != VALID lub transmit_mode = ASYNCHRONOUS → Hipoteza 2.

**Test 4: SHOW DATABASE pełen status:**
```
DGMGRL> SHOW DATABASE PRIM;
DGMGRL> SHOW DATABASE stby;
```
Sprawdzić:
- Apply Lag = 0 seconds
- Transport Lag = 0 seconds
- Database Status = SUCCESS
- Real Time Query = ON (jeśli ADG)

### Empiryczny fix (do potwierdzenia po testach):

**Scenariusz A — LogXptMode = ASYNC na którymś** (Hipoteza 2 confirmed):
```
DGMGRL> EDIT DATABASE PRIM SET PROPERTY LogXptMode='SYNC';
DGMGRL> EDIT DATABASE stby SET PROPERTY LogXptMode='SYNC';
DGMGRL> DISABLE FAST_START FAILOVER;
DGMGRL> ENABLE FAST_START FAILOVER;
```

**Scenariusz B — LogXptMode = SYNC na obu, ale Mode wciąż Potential Data Loss:**
```
DGMGRL> EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
DGMGRL> DISABLE FAST_START FAILOVER;
DGMGRL> ENABLE FAST_START FAILOVER;
```
Jeśli to pomaga → Hipoteza 1 ma znaczenie.
Jeśli nie pomaga → Hipoteza 2 nadal potencjalnie (downgrade w runtime mimo config SYNC) — wymaga `EDIT DATABASE` re-set.

**Skrypt v1.9 (defensive):**
- LagLimit=30 zostaje (Oracle default; nie zmieniam dopóki LagLimit nie jest udowodniony jako root cause)
- DODANE: `EDIT DATABASE PRIM/stby SET PROPERTY LogXptMode='SYNC'` w sekcji 6 jako sanity re-set (re-wymusza SYNC w broker config po potencjalnym downgrade z flashback recovery)
- Sekcja 9 warn-only verify Mode z hint do testów 1-4

**Lekcja uniwersalna:** przy nieprawidłowym FSFO Mode **NIE zgaduj** od jednego property. Diagnostyka by-the-book:
1. SHOW DATABASE * LogXptMode
2. v$database protection_mode vs protection_level
3. v$archive_dest transmit_mode + affirm + status + error
4. SHOW DATABASE * (Apply Lag + Transport Lag + Status)
5. flashback_on na obu

Tylko all 5 = OK → Zero Data Loss Mode achievable.

---

## 2026-04-27

## FIX-078 — Custom listenery 1522 i STBY DB nie auto-startują po reboot VM (broker `ORA-16664/16631` po cold restart)

**Problem:** Po cold STOP + cold START całego labu (3 listenery + STBY DB shutdown gracefully w sesji #1, potem reboot VMs w sesji #2) broker pokazywał:

```
stby - (*) Physical standby database (disabled)
  ORA-16906: The member was shutdown.
ENABLE DATABASE stby; → ORA-16626: failed to enable specified member
                       ORA-16631: operation requires shutdown of database or instance ""

# Po STARTUP MOUNT na STBY + ENABLE DATABASE stby:
stby - (*) Physical standby database
  Error: ORA-16664: unable to receive the result from a member
Configuration Status: ERROR
```

**Diagnostyka (rzeczywista, krok po kroku):**

```bash
# 3 listenery 1522 — wszystkie DOWN po reboot VM
ssh oracle@stby01 "lsnrctl status LISTENER_DGMGRL"
# TNS-12541: Cannot connect. No listener at host stby01.lab.local port 1522.
ssh grid@prim01 "lsnrctl status LISTENER_PRIM_DGMGRL"
# TNS-12541: Cannot connect. No listener at host prim01.lab.local port 1522.
ssh grid@prim02 "lsnrctl status LISTENER_PRIM_DGMGRL"
# TNS-12541: Cannot connect. No listener at host prim02.lab.local port 1522.

# Verify że to faktycznie static listenery (nie CRS resources):
ssh grid@prim01 "crsctl stat res -t | grep -i dgmgrl"
# (puste - nie ma CRS resource ora.listener_prim_dgmgrl.lsnr)
```

**Root cause (3 oddzielne luki w mechanizmie auto-start):**

1. **`LISTENER_PRIM_DGMGRL` na prim01/02** dodany przez ręczny patch FIX-050 jako *static entry w listener.ora* w Grid Home. Grid CRS auto-startuje **tylko** listenery zarejestrowane jako CRS resources (`ora.LISTENER.lsnr`, `ora.LISTENER_SCAN1.lsnr` itd.). Statyczne wpisy dodane bezpośrednio do `listener.ora` są niezauważone przez Grid przy boot CRS — wymagają ręcznego `lsnrctl start` lub osobnego mechanizmu auto-start.

2. **`LISTENER_DGMGRL` na stby01** dodany przez `duplicate_standby.sh` v3.3 sekcja 4 — DB Home, brak Grid na stby01 (Single Instance), brak systemd unit. Skrypt robi `lsnrctl start` jednorazowo przy duplikacji, ale po reboot VM listener nie wstaje sam.

3. **STBY DB** — Single Instance bez Grid, brak systemd unit, brak `dbstart` w `/etc/oratab` z flagą Y. Po reboot VM baza zostaje DOWN. Broker (jeśli zarządzał member-em przed shutdown) zapamiętuje stan jako `ORA-16906 was shutdown` i przy `ENABLE DATABASE` wymaga że member jest minimum w MOUNT (DMON aktywny) — bez DMON STBY broker DMON na PRIM dostaje `ORA-16664/16631` (pusta nazwa instance = "nie mogę nawiązać kontaktu z target DMON").

**Naprawa — dwupoziomowa:**

**(A) Workaround natychmiastowy** (w `OPERATIONS.md` v1.2 → v1.3, krok 2.5 + krok 3 prefix cold START):

```bash
# Po krok 2 (start prim01/02):
ssh grid@prim01 "lsnrctl start LISTENER_PRIM_DGMGRL"
ssh grid@prim02 "lsnrctl start LISTENER_PRIM_DGMGRL"

# Po startvm stby01 (przed STARTUP DB):
ssh oracle@stby01 "lsnrctl start LISTENER_DGMGRL"
```

**(B) Permanent fix** (2 nowe skrypty w `VMs/scripts/`):

1. **`enable_listener_autostart_prim.sh`** (jednorazowy, jako grid na prim01 + prim02):
   - `srvctl add listener -listener LISTENER_PRIM_DGMGRL -endpoints "TCP:1522" -oraclehome $ORACLE_HOME`
   - `srvctl modify listener -listener LISTENER_PRIM_DGMGRL -autostart always`
   - Static `SID_LIST_LISTENER_PRIM_DGMGRL` w listener.ora zostaje (Grid honoruje SID_LIST static przy starcie)
   - Po deployu listener jest CRS resource (`ora.listener_prim_dgmgrl.lsnr`) z `AUTO_START=ALWAYS` → startuje przy każdym `crsctl start crs`

2. **`enable_autostart_stby.sh`** (jednorazowy, jako root na stby01) — instaluje 2 systemd unity:
   - `oracle-listener-dgmgrl.service` (Type=forking, User=oracle, ExecStart `lsnrctl start LISTENER_DGMGRL`, ExecStop `lsnrctl stop`)
   - `oracle-database-stby.service` (After=oracle-listener-dgmgrl, ExecStart `STARTUP MOUNT;`, ExecStop `RECOVER ... CANCEL; SHUTDOWN IMMEDIATE;`)
   - Oba `systemctl enable` → auto-start przy reboot
   - DB startuje tylko do `MOUNT` (broker przejmie kontrolę przez `ENABLE DATABASE` lub auto-recovery jeśli FSFO ENABLED i member zarejestrowany)

**Dlaczego STBY DB tylko do `MOUNT`, nie `OPEN READ ONLY`?**

Broker Data Guard wymaga managed restart przez DMON dla member-a w stanie `disabled`. Jeśli systemd zrobi pełen `OPEN READ ONLY + RECOVER MANAGED STANDBY USING CURRENT LOGFILE`, baza jest UP ale **bez kontroli brokera** — broker nadal widzi `disabled` flag w metadata. `ENABLE DATABASE stby` wtedy daje `ORA-16631 operation requires shutdown` (broker chce sam wystartować). Z `STARTUP MOUNT`-only DMON jest aktywny, broker dotyka member-a i sam robi OPEN+RECOVER zgodnie z properties.

**Test naprawy:**

```bash
# 1. Deploy obu skryptów (raz)
ssh grid@prim01 "bash /tmp/scripts/enable_listener_autostart_prim.sh"
ssh grid@prim02 "bash /tmp/scripts/enable_listener_autostart_prim.sh"
ssh root@stby01 "bash /tmp/scripts/enable_autostart_stby.sh"

# 2. Verify CRS + systemd
ssh grid@prim01 "crsctl stat res ora.listener_prim_dgmgrl.lsnr -t"
# Oczekiwane: STATE=ONLINE, AUTO_START=always
ssh root@stby01 "systemctl is-enabled oracle-listener-dgmgrl.service oracle-database-stby.service"
# Oczekiwane: enabled / enabled

# 3. Test: cold STOP + cold START całego labu
# Po reboot wszystko wstaje samo:
#   - LISTENER_PRIM_DGMGRL via Grid (CRS)
#   - LISTENER_DGMGRL + STBY MOUNT via systemd
# Broker DMON STBY aktywny, ENABLE FSFO przejmuje member bez ORA-16631/16664
```

**Pliki:** `VMs/scripts/enable_listener_autostart_prim.sh` (NEW), `VMs/scripts/enable_autostart_stby.sh` (NEW), `VMs/OPERATIONS.md` v1.3 (krok 2.5 + krok 3 + sekcja "Permanent fix")

**Impact dla reinstalacji:** docelowo `duplicate_standby.sh` v3.4 powinien wywołać oba skrypty w sekcji końcowej (jako root + grid). Obecnie zostają jako manual deploy step po doc 09.

**Lekcja:** W RAC wszystko co ma startować po reboot **musi** być CRS resource (auto-start) lub systemd unit. Static entries w `listener.ora` są honored przez listener po starcie, ale **same nie startują** — Grid auto-startuje tylko listenery które są CRS resources. Single Instance bez Grid wymaga systemd. **Audit:** każdy port/serwis powołany ręcznie (poza standardowym flow Grid/DBCA) musi być wprost zaopatrzony w mechanizm auto-start — inaczej cold restart go gubi.

---

## FIX-079 — `configure_broker.sh` v2.10 wymusza pre-flight auto-start (DRY enforcement bez cross-user sudo)

**Problem:** Po FIX-078 mamy 2 osobne skrypty (`enable_listener_autostart_prim.sh` jako grid, `enable_autostart_stby.sh` jako root) które MUSZĄ być uruchomione przed `configure_broker.sh`. Ale nic w `configure_broker.sh` v2.9 tego nie egzekwuje — user może zapomnieć i broker zostanie skonfigurowany bez auto-start, gubiąc się przy pierwszym cold restarcie.

**Dlaczego nie zintegrować bezpośrednio?** `configure_broker.sh` uruchamiany jako `oracle`, a `srvctl add listener` wymaga `grid`. Pełna integracja wymagałaby:
- sudoers `oracle ALL=(grid) NOPASSWD:` lub
- SSH equivalency `oracle@prim01 → grid@prim01` (cross-user, niestandardowo)
- Mieszanie lifecycles (auto-start = raz per cluster; broker enable = single-shot)

Wszystkie 3 powyższe to nowe komplikacje większe niż problem.

**Rozwiązanie (kompromis):** `configure_broker.sh` v2.10 sekcja 0.2b dodaje pre-flight check **bez** cross-user sudo:

1. **LISTENER_PRIM_DGMGRL CRS check** — `$GRID_HOME/bin/srvctl config listener -listener LISTENER_PRIM_DGMGRL` (oracle z group `osdba`/`asmdba` ma srvctl read perm w 23ai/26ai). Detect Grid Home przez `awk -F: '/^\+ASM[0-9]*:/{print $2}' /etc/oratab`. **Hard die** jeśli FAIL z hint do uruchomienia `enable_listener_autostart_prim.sh`.

2. **stby01 systemd check** — `ssh -o BatchMode=yes oracle@stby01 "systemctl is-enabled oracle-listener-dgmgrl.service oracle-database-stby.service"` (oracle SSH equivalency istnieje od Grid install; `systemctl is-enabled` to read-only, nie wymaga sudo). **Soft warn** jeśli FAIL z hint do `enable_autostart_stby.sh` — bo tnsping STBY_ADMIN powyżej już zweryfikował **live state** listenera (jest UP teraz, tylko persistence after reboot pod znakiem zapytania).

**Symptom przed FIX-079:** broker enabled + FSFO armed → cold restart → listenery 1522 down → broker `Configuration Status: ERROR (ORA-16664)` → user nie wie dlaczego, kopie 1h.

**Symptom po FIX-079:** broker enable upada od razu z exact komendą do uruchomienia. User czyta die-message, robi 1 SSH, restartuje skrypt. Broker SUCCESS w pełnym armed state, cold restart auto-recovery działa.

**Pliki:** `VMs/scripts/configure_broker.sh` v2.9 → v2.10 (+~30 linii w sekcji 0.2b NEW).

**Lekcja:** Cross-skript dependency bez integracji = pre-flight enforcement w skrypcie *konsumentu*. Lepsze to niż integracja z cross-user sudo lub niż zwykła dokumentacja "pamiętaj uruchomić X przed Y". Podobny wzorzec mamy w `setup_observer_infra01.sh` (sekcja 4 sprawdza Configuration Status SUCCESS przed ENABLE FSFO — FIX-068).

---

## FIX-080 — `deploy_tac_service.sh` v1.3 — A2 patch (6 fixów: production hardening przed doc 12 deploy)

**Problem:** `deploy_tac_service.sh` v1.2 (FIX-052+057) był 90% gotowy ale audit przed deployem (sesja 2026-04-27, Explore agent) wykrył 8 luk. 6 z nich (HIGH+MED) zaadresowane w v1.3 (LOW pominięte: F6 CRLF encoding, F8 doc-script drift osobno załatwione).

**Audit findings (z Explore agent raport):**

| ID | Sev | Problem | Lokalizacja |
|---|---|---|---|
| F1 | HIGH | Brak `-failover_restore LEVEL1` (jest w `bash/tac_deploy.sh` v1.0, ale nie w VMs/scripts/deploy_tac_service.sh) | `deploy_tac_service.sh:106` |
| F3 | HIGH | Brak pre-flight check DG Broker SUCCESS — TAC bez działającego brokera = TAC bez sensu (broker triggeruje failover) | sekcja 0 |
| F2 | MED | Post-flight nie woła `tac_replay_monitor.sql` — blind spot dla replay sanity | sekcja 3 |
| F4 | MED | Idempotency niepełny — service exists → log zamiast warn (drift atrybutów się chowa) | linia 97 |
| F5 | MED | Port 6200 (ONS) prim→stby nie walidowany — FAN events mogą nie dotrzeć | sekcja 0 |
| F7 | MED | ONS daemon na stby01 (Single Instance bez Grid) nie sprawdzany — wymaga manualnego `onsctl start` | sekcja 0 |

**Naprawa (v1.3, +~100 linii):**

1. **F1 — `-failover_restore LEVEL1`** (linia 106 srvctl add service):
   - LEVEL1 = auto-restore session na tym samym instance po jego restartcie. Default Oracle = NONE → klient musi ręcznie reconnectować.
   - Standard TAC od Oracle 19c. Spójność z `bash/tac_deploy.sh` v1.0 i `docs/TAC-GUIDE.md` § 4.2.

2. **F3 — Sekcja 0.5 NEW DG Broker SUCCESS check**:
   - Wallet `/@PRIM_ADMIN` jest TYLKO na infra01 (z `setup_observer_infra01.sh`). Z prim01 brak wallet → `dgmgrl /@PRIM_ADMIN` zwraca błąd auth.
   - Workaround: `ssh -o BatchMode=yes oracle@infra01 "dgmgrl /@PRIM_ADMIN 'SHOW CONFIGURATION'"`. Multiline grep przez `tr '\n' ' '` (FIX-065 wzorzec).
   - **Hard die** jeśli `Configuration Status: WARNING/ERROR`. **Soft warn** jeśli SSH na infra01 nieosiągalny (kontynuacja).

3. **F2 — Sekcja 3b NEW post-flight replay monitor**:
   - Dla freshly-created service oczekiwane `requests_total=0` → ocena IDLE.
   - Po failoverach/replayach powinno być PASS (>=95% success rate).
   - Heurystyka: warn jeśli grep `\bCRIT\b` w output `tac_replay_monitor.sql` sekcja 1.

4. **F4 — `log` → `warn` przy idempotency** (linia 97):
   - Service istnieje → warn z hint do `srvctl remove` jeśli atrybuty driftowały (np. brak `-failover_restore LEVEL1` z v1.2).
   - Bez tego re-run skryptu po upgrade do v1.3 nie naprawi service — DBA musi ręcznie usunąć + re-add.

5. **F5 — `nc -zv -w5 ${STBY_HOST} 6200`** (sekcja 0.7):
   - Port 6200 (ONS) wymagany dla cross-site FAN events do klientów UCP.
   - Soft warn (nie die) — w lab firewall wyłączony, problem to ONS daemon (F7), nie firewall.

6. **F7 — `ssh oracle@stby01 "onsctl ping"`** (sekcja 0.6):
   - Single Instance bez Grid → ONS startuje manualnie. Po reboot stby01 ONS pad.
   - Soft warn z hint `onsctl start`. **TODO v1.2 enable_autostart_stby.sh:** dodać systemd unit `oracle-ons.service` (analogia FIX-078 dla listenera + DB) — wtedy F7 stanie się zbędne.

**Symptom przed FIX-080:** TAC service wdrożony bez `failover_restore` i bez weryfikacji broker/ONS → klient UCP po failoverze pad bez replay (Oracle default failover_restore=NONE), albo replay daje rzadkie błędy bo broker nie odpowiada. DBA debugowanie 1-2h zanim znajdzie root cause.

**Symptom po FIX-080:** skrypt blokuje deploy jeśli broker WARNING/ERROR (F3 hard die), warns dla ONS/port 6200 issues (F5/F7 — user widzi od razu co naprawić). Service wdrożony z LEVEL1 + post-flight sanity przez replay monitor.

**Pliki:**
- `VMs/scripts/deploy_tac_service.sh` v1.2 → v1.3 (+~100 linii, sekcja 0.5/0.6/0.7 + 3b)
- `VMs/12_tac_service.md` — sekcja 1.1 srvctl add z `-failover_restore LEVEL1` (drift fix F8 zaakcentowany)
- `VMs/12_tac_service.md` — pre-req lista rozszerzona (DG Broker SUCCESS, ONS daemon, port 6200 — pkt 2/6/7) + intro noticebox z opisem v1.3 changes

**Lekcja:** Pre-deploy audit subagentem (Explore) z konkretnymi pytaniami ("parameter parity vs alternative scripts", "post-flight coverage", "cross-script deps") wyłapuje luki które patrzenie liniowe na skrypt by przeoczyło. Czas: 5 min audit raport → 30 min patch v1.3. Bez audytu: deploy v1.2 + 1-2h debugowania w trakcie testów doc 14.

---

## FIX-081 — `deploy_tac_service.sh` v1.3 hotfixes (4 issues during first run)

**Problem:** Pierwszy run skryptu v1.3 ujawnił 4 issue ukryte w v1.2 (które stary skrypt też miał, ale bez pre-flight enforcement nie było czuć):

1. **PDB lowercase service registration:** `lsnrctl services` w 23ai/26ai pokazuje service jako `apppdb.lab.local` (lowercase). Skrypt `grep -qE "Service \"$PDB(\.lab\.local)?\""` z `$PDB="APPPDB"` (uppercase) **nie matchuje**. False die "PDB nie zarejestrowane" mimo że `v$pdbs` pokazuje OPEN READ WRITE. Fix: `grep -qiE` (case-insensitive).

2. **`srvctl modify ons -clusterid` PRKO-2002:** flag `-clusterid` została usunięta w 26ai. Single-cluster default — wystarczy `-remoteservers`. Fix: usunięcie flag + soft-fail (||true) bo ONS modify nie jest blocker.

3. **CRS-0245 oracle vs grid:** `srvctl modify ons` modyfikuje CRS resource `ora.ons` zarządzany przez Grid (grid user). Oracle dostaje `CRS-0245: doesn't have enough privilege`. Fix: hint do `ssh grid@prim01 "srvctl modify ons ..."` w warn.

4. **`retention_seconds` ORA-00904 (column nazwa zmieniła w 26ai):** kolumna `retention_seconds` (19c) → `retention_timeout` (23ai/26ai). Plus `commit_outcome_enabled` → `commit_outcome`. Fix: SELECT z poprawnymi nazwami.

5. **CRIT grep false positive:** v1.3 sekcja 3b post-flight szuka `\bCRIT\b` w outpucie `tac_replay_monitor.sql` aby wykryć replay failure. Output ma sekcję 6 "Summary" z legendą `CRIT  = < 80% (non-replayable...)`. Grep matchował legendę zamiast statusu. Fix: ostrzejsza heurystyka — wyciągamy tylko linie wyglądające jak rows wynikowe sekcji 1 (`^[[:space:]]*[0-9]+[[:space:]]+[0-9]+.*\b(IDLE|PASS|WARN|CRIT)\b`).

**Pliki:** `VMs/scripts/deploy_tac_service.sh` (5 inline hotfixes wewnątrz v1.3, header note "FIX-081 hotfix"). `VMs/12_tac_service.md` sekcja 1.3 + 3.1 — kolumny `commit_outcome` + `retention_timeout` zamiast 19c.

**Lekcja:** Migration 19c → 23ai/26ai zmienia kolumny w `dba_services` (`retention_seconds → retention_timeout`, `commit_outcome_enabled → commit_outcome`) oraz srvctl options (`-clusterid` removed). Plus default service registration w 26ai jest **lowercase** (różnica vs 19c uppercase). Każdy skrypt który grep'uje output Oracle musi być case-insensitive lub akceptować oba warianty.

---

## FIX-082 — 26ai SQL variants + ONS configuration na stby01 (cross-site FAN)

**Problem:** Po FIX-081 skrypt deployuje TAC service OK, ale 3 osobne luki blokowały cross-site FAN events i tac readiness check:

### Luka 1: GV$REPLAY_STAT_SUMMARY usunięty w 23ai/26ai

`<repo>/sql/tac_full_readiness.sql` sekcja 11 i `tac_replay_monitor.sql` sekcja 1 używają `GV$REPLAY_STAT_SUMMARY` — widok który **został usunięty** w 23ai/26ai. Po `desc all_views WHERE name LIKE '%REPLAY%'` w 26ai widać tylko per-context views (`GV$REPLAY_CONTEXT`, `GV$REPLAY_CONTEXT_LOB`, `GV$REPLAY_CONTEXT_SEQUENCE`, `GV$REPLAY_CONTEXT_SYSDATE`, `GV$REPLAY_CONTEXT_SYSGUID`, `GV$REPLAY_CONTEXT_SYSTIMESTAMP`). Brak agregowanego summary widoku.

**Naprawa:** stworzono dwa `_26ai` warianty z patch sekcji 11/1 — agregacja per-instance z `GV$REPLAY_CONTEXT`:
- `<repo>/sql/tac_full_readiness_26ai.sql` (kopia + patch sekcja 11)
- `<repo>/sql/tac_replay_monitor_26ai.sql` (kopia + patch sekcja 1)

Status logic w 26ai variant:
- `IDLE` = no replay contexts (fresh service, no traffic)
- `PASS` = wszystkie *_REPLAYED >= *_CAPTURED (100% replay rate)
- `WARN` = jakaś kategoria *_REPLAYED < *_CAPTURED (partial replay)

`deploy_tac_service.sh` v1.3+ ma helper `pick_sql()` który auto-preferuje `_26ai` variant z fallback do oryginału. User wgrywa oba pliki, skrypt sam wybiera.

### Luka 2: `ons.config` na stby01 — custom porty + brak `nodes=` directive

Default `ons.config` post-Oracle 23.26 install (Single Instance bez Grid) ma:
```
usesharedinstall=true
localport=6199    # NIESTANDARDOWY (PRIM RAC używa 6100)
remoteport=6299   # NIESTANDARDOWY (PRIM RAC używa 6200)
                  # BRAK 'nodes=' → ONS bind tylko 127.0.0.1
```

Plus `useocr=off` — to **deprecated key** w 26ai (rzuca `[ERROR:1] [parse] unknown key: useocr`, non-fatal ale brzydkie).

**Naprawa (manual):**
```bash
ssh oracle@stby01 'cat > $ORACLE_HOME/opmn/conf/ons.config <<EOF
usesharedinstall=true
localport=6100
remoteport=6200
nodes=stby01.lab.local:6200,prim01.lab.local:6200,prim02.lab.local:6200
EOF
onsctl stop 2>/dev/null; onsctl start && onsctl ping'
```

Po fix: `ss -ntlp | grep 6200` pokazuje `LISTEN *:6200` (zewnętrzny bind). Cross-site FAN events działają.

### Luka 3: `nc -zv` heurystyka — ncat vs BSD nc + `set -e + pipefail` kill

Skrypt v1.3 używał `grep -qiE "succeeded|open"` na output `nc -zv`. Ale na OL8 nc to **ncat z nmap-package**, output:
- `Connected to stby01.lab.local.` (success — nie zawiera "succeeded" ani "open")
- `Ncat: Connection refused` (fail)

**Naprawa 1:** rozszerzony grep `succeeded|open|connected to` (case-insensitive).
**Naprawa 2:** fallback `bash /dev/tcp/${host}/6200` — zawsze dostępny w bash 4+ (nie wymaga nc/ncat). Bardziej niezawodny check.

Plus odkryto bug **`set -o pipefail`** w sekcji 3b: `SECTION1_STATUS=$(echo $REPLAY_OUT | grep -E '...' | head -5)`. Gdy grep nie matchuje (0 rows), zwraca exit 1, pipefail przejmuje exit do command substitution, set -e ubija skrypt **przed** wypisaniem finalnego DONE. **Naprawa:** dodanie `|| true` na końcu pipe.

### Luka 4: `srvctl modify ons` PRKO-2396 false-warn

Output PRKO-2396 "The list of remote host/port ONS pairs matches the current list" to **idempotency success** (no-op gdy config już zgodny). Skrypt `grep -q "PRKO-\|PRCR-\|CRS-"` traktował go jak fail. **Naprawa:** explicit branch dla PRKO-2396 → log success.

**Pliki:**
- `<repo>/sql/tac_full_readiness_26ai.sql` (NEW, ~590 linii)
- `<repo>/sql/tac_replay_monitor_26ai.sql` (NEW, ~270 linii)
- `VMs/scripts/deploy_tac_service.sh`: `pick_sql()` helper + 4 hotfixes (PRKO-2396 success branch, ncat/dev-tcp fallback, sekcja 0.6 grep "is not running", pipefail `|| true`)
- `VMs/12_tac_service.md`: sekcja 2.1 (grid + bez `-clusterid`), sekcja 2.2 (ons.config bez `useocr`, mesh `nodes=`), sekcja 1.3 (lowercase noticebox), sekcja 6 (`_26ai` variant preferred)
- `VMs/04_os_preparation.md`: SQL_DIR table z `_26ai` wariantami + `pick_sql()` reference

**Lekcja:** Migration 19c → 23ai/26ai usuwa pewne views (`GV$REPLAY_STAT_SUMMARY` → per-context views). Strategia `_26ai` suffix dla SQL plików + `pick_sql()` helper dla skryptów = czyste oddzielenie wersji bez modyfikacji oryginalu (zachowuje 19c/21c compat). Plus `bash /dev/tcp/host/port` to portable replacement dla `nc -zv` (różnice ncat vs BSD nc) — niezawodne na OL8.

---

## FIX-083 — `enable_autostart_stby.sh` v1.2 — `oracle-ons.service` systemd unit (3 unity zamiast 2)

**Problem:** Po FIX-082 ONS na stby01 chodzi (`onsctl start` po patch `ons.config`), ale **`onsctl start` to one-shot** — po każdym reboot stby01 trzeba uruchomić ręcznie. Cross-site FAN events do klientów UCP **nie zadziałają** po cold restart bez manual interwencji. Identyczny pattern auto-start gap jak FIX-078 dla LISTENER_DGMGRL/STBY DB.

**Naprawa:** `enable_autostart_stby.sh` v1.1 → v1.2 — dodanie 3-go systemd unitu:

### Struktura v1.2 (3 unity zamiast 2)

```
oracle-listener-dgmgrl.service (port 1522)
    ↓ After=
oracle-ons.service (port 6100/6200, FAN events)        [NEW v1.2]
    ↓ After=
oracle-database-stby.service (STARTUP MOUNT)
```

Pełen ordering boot: `network → listener → ONS → DB MOUNT`. Listener musi być pierwszy (DGMGRL używa go), ONS przed DB (broker DMON publish FAN events przez ONS), DB ostatni.

### Implementacja

**Sekcja 2b NEW — helper scripts:**
```bash
/usr/local/bin/oracle-ons-start.sh:
    export ORACLE_HOME=...
    $ORACLE_HOME/opmn/bin/onsctl start
/usr/local/bin/oracle-ons-stop.sh:
    $ORACLE_HOME/opmn/bin/onsctl stop
```

**Sekcja 2c NEW — pre-flight `ons.config`:**
- Sprawdza istnienie `$ORACLE_HOME/opmn/conf/ons.config`
- Sprawdza `localport=6100` (default 23.26 ma niestandardowe `6199`)
- Sprawdza `nodes=` directive (bez tego ONS bind tylko localhost)
- Soft warn z hint do doc 12 sekcja 2.2 jeśli config wymaga dostosowania

**Sekcja 3a NEW — `oracle-ons.service` systemd unit:**
```ini
[Unit]
After=oracle-listener-dgmgrl.service network-online.target

[Service]
Type=forking
User=oracle
ExecStart=/usr/local/bin/oracle-ons-start.sh
ExecStop=/usr/local/bin/oracle-ons-stop.sh
ExecReload=$ORACLE_HOME/opmn/bin/onsctl reload    ← reload bez drop FAN events
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Update `oracle-database-stby.service`:** `After=` i `Wants=` rozszerzone o `oracle-ons.service` — DB nie wystartuje aż ONS jest UP.

### Po deployu (test cold restart)

```bash
# Po reboot stby01:
ssh root@stby01 "systemctl status oracle-listener-dgmgrl oracle-ons oracle-database-stby --no-pager"
# Oczekiwane: 3 × active (running) + status: SUCCESS

# Sanity check ONS bind external
ssh root@stby01 "ss -ntlp | grep -E ':6[12]00'"
# Oczekiwane: LISTEN *:6200 (zewnętrzny) + 127.0.0.1:6100 (lokalny)

# Connectivity z prim01
ssh oracle@prim01 "timeout 5 bash -c 'echo > /dev/tcp/stby01.lab.local/6200' && echo OK"
```

**Pliki:**
- `VMs/scripts/enable_autostart_stby.sh` v1.1 → v1.2 (~80 linii dodanych: 2 helper scripts + ons.config pre-flight + ONS unit + dependency w DB unit)
- `VMs/09_standby_duplicate.md` sekcja 9b — wzmianka o 3 unitach (było 2)
- `VMs/12_tac_service.md` sekcja 2.2 — usunięcie TODO + nota o `systemctl reload` dla runtime ons.config changes

**Lekcja:** Każdy daemon/serwis który ma być persistent po reboot musi być pod systemd lub CRS. Po FIX-078 (listenery 1522 + STBY DB) i FIX-083 (ONS) mamy pełen self-healing cold restart na stby01: VM boot → 3 unity startują w correct order → broker przejmuje DB → cross-site FAN do klientów UCP. **TODO doc 16:** rozważyć przeniesienie wszystkich 3 unitów do osobnego role-deploymentu (`prepare_host.sh --role=si-standby` mógłby zainstalować systemd unity od razu).

---

## FIX-084 — `13_client_ucp_test.md` A2 patch (TestHarness.java replay-capable + cross-references)

**Problem:** Audit doc 13 (Explore agent, sesja 2026-04-27) wykrył **CRITICAL bug** w TestHarness.java który blokowałby TAC replay w teście klienta UCP. Plus brakowało cross-reference do server-side prereq (FIX-080/081/082/083) ustawionych w docs 09-12.

**Audit findings:**

| ID | Sev | Problem | Lokalizacja |
|---|---|---|---|
| F1 | **CRITICAL** | `pds.setConnectionFactoryClassName("oracle.jdbc.pool.OracleDataSource")` — standardowy DataSource **NIE wspiera replay**. Po failover klient dostanie ORA-03113 zamiast transparent replay | `13_client_ucp_test.md:182` |
| V_C_O_B | LOW | Brak `setValidateConnectionOnBorrow(true)` — UCP best practice dla TAC (filtruje stale connections post-failover) | sekcja 5 TestHarness |
| F3 | MED | Brak prereq context o `failover_restore=LEVEL1` z doc 12 (FIX-080). Operator nie wie że bez tego replay nie zadziała | sekcja 7 |
| F6 | LOW | Troubleshooting referuje `gv$replay_stat_summary` (usunięty w 26ai, FIX-082) | sekcja 10 |
| F8 (own) | LOW | Brak wzmianki że PDB/service registered **lowercase** w listenerze (FIX-081). Operator szukający "Service \"MYAPP_TAC\"" w `lsnrctl services` może nie znaleźć (lowercase) | sekcja 10 |

**Findings POMINIĘTE (raport agenta był nadgorliwy):**
- F4 (stby02 brakuje w ONS): agent założył "2-node STBY RAC" z `INTEGRATION-GUIDE.md`, ale **nasz lab ma SI stby01 (Single Instance bez Grid)** — 3 nody w ONS mesh (`prim01,prim02,stby01`) są correct.
- F2/F5 (compatibility note 23.x vs 19.x): cosmetic, niski priorytet.
- F7 (`OracleReplayDriverContext`): advanced use case, nie potrzebne dla baseline test.

**Naprawa (5 edytów w doc 13):**

### Edit 1 — sekcja 5 TestHarness.java (F1 CRITICAL):
```java
// PRZED (broken):
pds.setConnectionFactoryClassName("oracle.jdbc.pool.OracleDataSource");

// PO (FIX-084):
pds.setConnectionFactoryClassName("oracle.jdbc.replay.OracleDataSourceImpl");
```
Bez tej zmiany: UCP nie zna LTXID, klient dostaje ORA-03113 po failover, replay nie działa.

### Edit 2 — sekcja 5 (V_C_O_B):
```java
pds.setValidateConnectionOnBorrow(true);   // NEW: UCP filtruje stale connections
```

### Edit 3 — sekcja 5 noticebox o lab topology:
Dodano komentarz że ONS mesh `prim01,prim02,stby01` (3 nody, NIE 4 z stby02) jest correct dla SI standby. Plus reference do `enable_autostart_stby.sh` v1.2 (FIX-083) dla persistence.

### Edit 4 — sekcja 7 noticebox prereq server-side:
4-punktowa checklist do uruchomienia PRZED testem:
1. `srvctl config service` zawiera wszystkie TAC params (TRANSACTION + LEVEL1 + TRUE + DYNAMIC + 86400 + 1800)
2. `oracle-ons.service` active na stby01 (FIX-083 systemd)
3. Cross-site ONS na PRIM (`srvctl config ons` jako grid, FIX-082)
4. Broker SUCCESS + FSFO ENABLED

Bez tego klient dostanie ORA-03113 BEZ replay (cosmetic dla DBA — wskazuje od razu co jest nie tak).

### Edit 5 — sekcja 10 troubleshooting:
- ORA-12514 problem: nota o **lowercase service registration** (FIX-081). `lsnrctl services | grep -i myapp_tac` (case-insensitive).
- Replay nie działa: rozszerzona checklist (server-side: `failover_restore=LEVEL1`, client-side: `OracleDataSourceImpl`, `ValidateConnectionOnBorrow=true`, `FastConnectionFailoverEnabled=true`)
- NEW problem entry: `gv$replay_stat_summary` ORA-00942 → użyj `_26ai` variant z FIX-082

**Pliki:** `VMs/13_client_ucp_test.md` (5 edytów, ~60 linii dodanych).

**Lekcja:** TAC ma **2 oddzielne wymagania** dla replay — server-side (`failover_type=TRANSACTION + commit_outcome=TRUE + failover_restore=LEVEL1`) plus client-side (`OracleDataSourceImpl` factory, NIE `OracleDataSource`). Brak któregokolwiek = replay disabled. Client-side bug jest "cichy" — UCP łączy się OK, transakcje commit OK, dopiero failover ujawnia że factory nie ma replay support. Pre-deploy audit subagentem wyłapał to przed testem (15 min) zamiast 2-3h debugowania w trakcie testów doc 14.

---

## FIX-085 — TNS structure fix (LOAD_BALANCE=ON na top level + 2 ADDRESS_LIST losował grupę) + LISTENER:1521 stby01 manual start

**Problem 1 (TNS):** Pierwsza wersja `tnsnames.ora` w doc 13 miała 2 osobne `ADDRESS_LIST` (każda z jednym ADDRESS — pierwsza `scan-prim`, druga `stby01`) z `LOAD_BALANCE=ON` i `FAILOVER=ON` na top level `DESCRIPTION`. Oracle Net traktuje to jako 2 grupy adresowe i z `LOAD_BALANCE=ON` **losuje którą grupę** wybrać. Klient mógł trafić na `stby01:1521` (drugi grup) mimo że PRIM RAC aktywny — `ORA-12541: No listener` (jeśli LISTENER:1521 stby01 down) lub `ORA-12514` (jeśli up ale brak service).

**Problem 2 (LISTENER stby01):** Po reboot stby01 dziś rano `LISTENER:1521` (DB Home, port 1521) zostaje **DOWN**. `enable_autostart_stby.sh` v1.2 (FIX-083) ma systemd unity tylko dla:
- `oracle-listener-dgmgrl.service` (port 1522)
- `oracle-ons.service` (port 6100/6200)
- `oracle-database-stby.service` (DB MOUNT)

Brak unitu dla `LISTENER:1521`. Po failover MYAPP_TAC service przeniesie się na stby01 → klient potrzebuje listener:1521 UP. Aktualnie wymaga manual `lsnrctl start LISTENER`.

**Naprawa Problem 1:** doc 13 sekcja 4 — single `ADDRESS_LIST` z `LOAD_BALANCE=OFF` + `FAILOVER=ON` (deterministic order: SCAN-PRIM first, stby01 second jako post-failover fallback):
```
(ADDRESS_LIST =
    (LOAD_BALANCE = OFF)
    (FAILOVER = ON)
    (ADDRESS = (HOST = scan-prim.lab.local)(PORT = 1521))
    (ADDRESS = (HOST = stby01.lab.local)(PORT = 1521))
)
```

**Naprawa Problem 2 (DONE w FIX-089 — `enable_autostart_stby.sh` v1.3):** dodano 4-ty systemd unit `oracle-listener-stby.service` dla LISTENER:1521 (DB Home jako oracle, ExecStart `lsnrctl start LISTENER`, ExecStop `lsnrctl stop LISTENER`). Analogicznie do FIX-078/083 wzorzec. Zob. FIX-089 dla pełnego kontekstu.

**Pliki:** `VMs/13_client_ucp_test.md` sekcja 4 (TNS structure fix). Część v1.3 skryptu — zob. FIX-089.

**Lekcja:** `LOAD_BALANCE=ON` na top-level `DESCRIPTION` z multiple `ADDRESS_LIST` losuje **grupy adresowe**. Dla deterministyczego failover (preferuj jedno, fallback na drugie) używaj **single** `ADDRESS_LIST` z `LOAD_BALANCE=OFF` + `FAILOVER=ON` + adresy w preferowanej kolejności.

---

## FIX-086 — `SERVICE_NAME` w TNS musi mieć `db_domain` w 26ai (`.lab.local` suffix)

**Problem:** Po naprawie TNS structure (FIX-085) klient z client01 dalej dostawał `ORA-12514: Service MYAPP_TAC is not registered with the listener at host 192.168.56.13`. Mimo że:
- SCAN VIPs OK (192.168.56.31/32/33:1521 reachable)
- SCAN listenery running (LISTENER_SCAN1/2/3)
- Po `ALTER SYSTEM REGISTER` na PRIM1+PRIM2 service `myapp_tac.lab.local` widoczny w SCAN listenerach
- Inny service `PRIM_APPPDB.lab.local` connect OK (z domeną)

**Root cause:** W Oracle 23ai/26ai DBCA przy `New_Database.dbt` template auto-appenduje `db_domain` do każdego service registered w listenerze. Service `MYAPP_TAC` jest registered jako **`myapp_tac.lab.local`** (lowercase + domain `lab.local`). Klient TNS z `(SERVICE_NAME = MYAPP_TAC)` (bez domeny) nie matchuje:

```bash
# Verify db_domain
sqlplus / as sysdba <<EOF
SHOW PARAMETER db_domain
EOF
# db_domain                  string   lab.local

# Verify service registration w listener
lsnrctl services | grep -i myapp
# Service "myapp_tac.lab.local" has 1 instance(s)
```

**Naprawa:** `SERVICE_NAME = MYAPP_TAC.lab.local` (z domeną) w TNS:
```
(CONNECT_DATA =
    (SERVER = DEDICATED)
    (SERVICE_NAME = MYAPP_TAC.lab.local)   ← FIX-086: musi mieć .lab.local
)
```

**Symptom przed fix:** `ORA-12514: Service MYAPP_TAC is not registered` (klient szuka `MYAPP_TAC` w listener, listener ma `MYAPP_TAC.lab.local`). False negative — service jest aktywny, ale pod inną nazwą.

**Symptom po fix:** klient connect OK przez SCAN do PRIM RAC.

**Powiązanie z FIX-040** (z poprzedniej sesji, `feedback_26ai_db_domain.md`): "26ai DBCA appenduje db_domain - service_names po DBCA New_Database.dbt to 'PRIM.lab.local'; tnsnames.ora MUSI mieć fully qualified SERVICE_NAME". FIX-086 to ten sam pattern dla **custom service** (`MYAPP_TAC` utworzony przez `srvctl add service` w doc 12) — Grid także appenduje `db_domain` do nazwy registered w listenerze.

**Pliki:** `VMs/13_client_ucp_test.md`:
- sekcja 4 (TNS) — `SERVICE_NAME = MYAPP_TAC.lab.local` (zamiast `MYAPP_TAC`)
- sekcja 10 troubleshooting — entry "ORA-12514 Service ... is not registered" z 3 przyczynami: (1) brak `db_domain`, (2) service nie cross-registered do SCAN (wymaga `ALTER SYSTEM REGISTER`), (3) TNS_ADMIN drift

**Lekcja:** W Oracle 23ai/26ai **wszystkie** services są registered w listener z `db_domain` jako suffix. TNS klienta MUSI używać fully qualified service name (`<service>.<db_domain>`). Quick check: `lsnrctl services | grep -i <service>` pokazuje pełną nazwę z domeną — kopiuj 1:1 do TNS. Nie polegaj na uppercase aliasing — Oracle case-insensitive ale name lookup wymaga exact match po normalizacji (case-folded).

---

## FIX-087 — Java 17+ wymaga `--add-opens` dla UCP TAC bytecode proxy generation

**Problem:** Po kompilacji `TestHarness.java` (sekcja 5 doc 13) na client01 z JDK 17, runtime fail przy pierwszym `pds.getConnection()`:

```
Exception in thread "main" java.lang.IllegalStateException: cannot resolve or generate proxy
    at oracle.ucp.proxy.ProxyFactory.prepareProxy(ProxyFactory.java:512)
    at oracle.ucp.jdbc.PoolDataSourceImpl.getConnection(PoolDataSourceImpl.java:2117)
    at TestHarness.main(TestHarness.java:71)
```

**Root cause:** Java 17 wprowadziło **JEP 396 (Strong encapsulation by default)** — refleksyjny dostęp do `java.base` modułów (`java.lang`, `java.util`, `jdk.internal.misc`, `sun.nio.ch`) jest **domyślnie zablokowany**. UCP TAC używa bytecode proxy generation (CGLib-style) który injecuje dynamiczne klasy implementujące `java.sql.Connection` z dodatkowymi metodami dla replay tracking. To wymaga deep reflection do internal classes które Java 17 zamknęło.

W JDK 8/11 było tylko warning (`WARNING: An illegal reflective access operation has occurred`) — w JDK 17+ to **hard error**.

**Naprawa:** uruchamiaj `java` z 4 `--add-opens` flagami:

```bash
java \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/java.util=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
  --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
  -cp '/opt/lab/jars/*:.' TestHarness
```

Każda flaga otwiera konkretny package dla `ALL-UNNAMED` (klas które nie są w module — typowe dla classpath-loaded apps).

**Alternatywne rozwiązania (rejected):**

1. **JDK 11 zamiast JDK 17** — zadziała bez flag, ale Java 11 ma EOL Sep 2026 dla Oracle Premier Support. JDK 17 LTS jest preferred dla nowych deploymentów.

2. **`--enable-native-access=ALL-UNNAMED`** — to tylko dla JEP 442 (Foreign Function), nie pomoże tu.

3. **`-Djdk.module.illegalAccess=permit`** — usunięte w JDK 17 (działało w 9-16).

4. **Module-based deployment** (jpms) — wymagałoby module-info.java + remodelowanie UCP jarów które tego nie wspierają out-of-box.

**Pliki:**
- `VMs/13_client_ucp_test.md` sekcja 6 — kompilacja + uruchamianie z `--add-opens` block + helper script `/opt/lab/run_testharness.sh`
- `VMs/src/TestHarness.java` — header comment z hint o `--add-opens`

**Lekcja:** Klasyczny problem JDK 17 + legacy enterprise libraries (UCP, Hibernate, Spring < 6, EJB containers, etc.). Oracle UCP 23.x officially supports JDK 17 dopiero z dodanymi flagami `--add-opens` (Oracle JDBC docs § "Java 17 Compatibility"). Helper script `/opt/lab/run_testharness.sh` to standardowy pattern produkcyjny — zawijanie 4 linii flag w jeden executable. Alternatywnie do `/etc/profile.d/` można dodać `JAVA_OPTS` z tymi flagami i UCP picks them up automatically.

---

## FIX-088 — UCP `autoCommit=true` default + explicit `commit()` = `ORA-17273`

**Problem:** Po naprawie FIX-087 (`--add-opens`) i `ucp/lib/ucp11.jar` (zamiast sqlcl-stripped variant), UCP TAC connection ustanowione poprawnie ale każdy `conn.commit()` w pętli zwraca:

```
[1] ERROR: ORA-17273: Could not commit with auto-commit enabled.
[2] ERROR: ORA-17273: Could not commit with auto-commit enabled.
...
```

**Root cause:** UCP 23.x **default `autoCommit=true`** (zmiana vs UCP 19.x gdzie default był `false`). Przy auto-commit każdy DML jest auto-committowany przez driver, więc explicit `conn.commit()` nie ma czego commitować — JDBC throws `ORA-17273` jako "you can't manually commit when auto-commit handles it".

**Druga warstwa problemu:** **TAC replay wymaga explicit transaction control**. Auto-commit traktuje każdy statement jako osobną transakcję — TAC wtedy replay-uje pojedyncze INSERT-y, nie cały logical unit. Przy złożonych transakcjach (np. transfer A→B w 2 INSERT-ach) auto-commit replay-uje połówki niezależnie, łamiąc atomicity.

**Naprawa:** Po `pds.getConnection()` dodać `conn.setAutoCommit(false)`:

```java
try (Connection conn = pds.getConnection()) {
    conn.setAutoCommit(false);   // FIX-088: explicit transaction control dla TAC
    // ... INSERTs ...
    conn.commit();                // teraz zadziała
}
```

**Alternatywne rozwiązanie:** ustawić globally na PoolDataSource przez properties (Java 17+):
```java
java.util.Properties props = new java.util.Properties();
props.put("autoCommit", "false");
pds.setConnectionProperties(props);
```

W TestHarness wybrałem **per-connection** (jasne i czytelne), bo to lab demo. Production typically wraps w try-with-resources + connection helper.

**Pliki:**
- `VMs/src/TestHarness.java` — dodano `conn.setAutoCommit(false)` w try block
- `VMs/13_client_ucp_test.md` sekcja 5 — TestHarness inline z setAutoCommit(false) + komentarz FIX-088

**Lekcja:** UCP 19.x → 23.x zmienił default `autoCommit=false` → `autoCommit=true` — undocumented breaking change. Plus TAC replay design assumes explicit transaction control (multi-statement units). Ze auto-commit traktować jako "drugi anti-pattern" obok złej factory class (FIX-084) — oba pułapki "cichego błędu" które wyłapuje dopiero pierwszy run, nie kompilacja. Pre-deploy audit (Explore agent) wyłapał tylko factory; setAutoCommit gotcha wymagał faktycznego runtime testu.

---

## FIX-089 — `enable_autostart_stby.sh` v1.2 → v1.3 — 4-ty systemd unit `oracle-listener-stby.service` (LISTENER:1521)

**Problem:** v1.2 instalowała 3 systemd unity (`oracle-listener-dgmgrl.service` 1522, `oracle-ons.service`, `oracle-database-stby.service`), ale **nie obejmowała `LISTENER:1521`** (default DB listener stby01 z DB Home). Po reboot stby01 listener:1521 zostawał DOWN — wymagał manual `lsnrctl start LISTENER`. To była otwarta TODO z FIX-085.

**Dlaczego krytyczne przed doc 14 scenario 2:** scenario 2 testuje failover STBY → PRIMARY. Po failover service `MYAPP_TAC` registruje się w `LISTENER:1521` na stby01 (db_unique_name=STBY, lokalny default listener). Klient UCP łączący się przez TNS (single ADDRESS_LIST z fallback `stby01.lab.local:1521`) trafia na ten listener. Jeśli leży po reboot — `ORA-12541: No listener at stby01:1521`, TAC replay się NIE wykona, scenario 2 fail.

**Naprawa — `enable_autostart_stby.sh` v1.3:**

1. Nowy unit `/etc/systemd/system/oracle-listener-stby.service`:
   ```
   [Unit]
   Description=Oracle Default Listener stby01 (LISTENER on port 1521 - DB + MYAPP_TAC po failover)
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

2. Ordering rozszerzony:
   - `oracle-ons.service` — `After=oracle-listener-stby.service oracle-listener-dgmgrl.service network-online.target`
   - `oracle-database-stby.service` — `After=oracle-listener-stby.service oracle-listener-dgmgrl.service oracle-ons.service network-online.target`
   - Pełen ordering at boot: `network → listener:1521 + listener:1522 → ONS → DB MOUNT`

3. Sekcja 4 enable: `systemctl enable oracle-listener-stby.service` (przed pozostałymi 3).

4. Sekcja 5 verify: `systemctl is-enabled` na 4 unity.

5. Final summary (krok 1 zmieniony, dodany krok 8):
   - `1. oracle-listener-stby (FIX-085) wystartuje LISTENER (port 1521)`
   - `8. Po failover STBY->PRIMARY: MYAPP_TAC registruje sie w LISTENER:1521 (UP)`

**Pliki:**
- `VMs/scripts/enable_autostart_stby.sh` v1.2 → v1.3 (header + sekcja 1a NEW + ordering w 3a/3b + sekcja 4/5 + final summary)
- `VMs/09_standby_duplicate.md` sekcja 9b — naglowek "FIX-078, FIX-085", "**4 systemd unity**" z bullet pointem `oracle-listener-stby.service` jako pierwszy, verify z 4 unity, helper scripts wildcard `oracle-{stby,ons}-{start,stop}.sh`
- `VMs/11_fsfo_observer.md` sekcja prereq 3 — bullet stby01 z 4 unitami, podkreślona krytyczność dla doc 14 scenario 2
- `VMs/FIXES_LOG.md` — FIX-085 update (TODO oznaczone DONE w FIX-089) + ten entry

**Lekcja:** systemd auto-start dla Single Instance bez Grid wymaga **wszystkich** komponentów w łańcuchu network → listenery → ONS → DB. Pominięcie listenera default port 1521 przy v1.0/v1.1/v1.2 było pochodną tego, że tylko port 1522 był wymagany dla DG broker; ale TAC service na primary używa 1521 — a po failover STBY staje się primary. Wzorzec: **każda port-bound usługa Oracle musi mieć swój systemd unit lub CRS resource** dla auto-start, nawet jeśli "normalnie chodzi sama" (LISTENER się nie zarządza po reboot bez systemd/CRS).

---

## FIX-090 — `validate_env.sh` v1.2 → v1.3 + NEW `fsfo_monitor_26ai.sql` (audit doc 14 vs 26ai)

**Problem:** Doc 14 audit przed scenariuszami testowymi wykrył że `validate_env.sh` v1.2 i `<repo>/sql/fsfo_monitor.sql` rzucą `ORA-00942: table or view does not exist` na 26ai w `--full` mode. Plus doc 14 sekcje miały 19c-isms niekompatybilne z 26ai środowiskiem.

**Trzy źródła błędu:**

1. **`fsfo_monitor.sql:281`** używa `gv$replay_stat_summary` — REMOVED w 23ai/26ai (zastąpione per-context views: `GV$REPLAY_CONTEXT_*`). Brak `_26ai` variantu — analogicznie do `tac_full_readiness.sql` → `tac_full_readiness_26ai.sql` z FIX-082.

2. **`validate_env.sh` v1.2** wywołuje hardcoded nazwy (`tac_full_readiness.sql`, `fsfo_monitor.sql`, `fsfo_broker_status.sql`) bez auto-pick `_26ai` variantów. Nawet gdy `tac_full_readiness_26ai.sql` istnieje, skrypt go ignorował.

3. **Doc 14** nie sychronizowany z 26ai findings z sesji (FIX-072, 077, 082, 084-089) i powoływał się na nieaktualne nazwy kolumn / nieistniejące skrypty.

**Naprawa — 3 pliki:**

### A. NEW `<repo>/sql/fsfo_monitor_26ai.sql` (313 linii)

Kopia 1:1 z `fsfo_monitor.sql` z patched sekcją 7:

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
END AS ocena_tac
FROM agg ORDER BY inst_id;
```

Reszta skryptu (sekcje 1-6) bit-identyczna z `fsfo_monitor.sql`. Wzorzec analogiczny do `tac_full_readiness_26ai.sql:543-572` z FIX-082.

### B. `<repo>/VMs/scripts/validate_env.sh` v1.2 → v1.3

Dodany `pick_sql()` helper (kopia z `deploy_tac_service.sh` v1.3 sekcja 0):

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

Wywołania w skrypcie:
- Quick: `QUICK_SQL=$(pick_sql validate_environment)` — preferuje `_26ai` jeśli kiedyś dodasz
- Full: pętla `for BASE in tac_full_readiness fsfo_monitor fsfo_broker_status` — każdy przez `pick_sql`

Nazwy plików w `/tmp/reports/` używają `$(basename ${SQL_FILE%.sql})` — output to `tac_full_readiness_26ai_PRIM_<ts>.log` (samo-dokumentujące).

### C. `<repo>/VMs/14_test_scenarios.md` — refresh całego dokumentu

| # | Sekcja | Zmiana |
|---|---|---|
| D1 | Wstęp | `validate_env.sh v1.1` → `v1.3`, dodany opis `_26ai` auto-pick |
| D9 | NEW "Pre-flight przed scenariuszami" | 6-punktowa checklista server+client (FIX-080/082/083/085/089), wallet location noticebox (FIX-072), multiline grep gotcha (FIX-067) |
| D5 | Scenario 1 + 2 + 3 | TestHarness → `/opt/lab/run_testharness.sh` (z 4 flagami `--add-opens`, FIX-087) |
| D7 | Scenario 1 + 2 + 4 | sqlplus/dgmgrl wszędzie z `ssh oracle@infra01` prefix (wallet only there, FIX-072) |
| D8 | Scenario 2 | Multiline `tr '\n' ' '` flatten dla grep przez dgmgrl output (FIX-067) |
| - | Scenario 2 | sqlplus heredoc z `EXIT;` (FIX-057), CRS stop jako `root@` zamiast `sudo` |
| D6 | Scenario 3 | `conn.setAutoCommit(false)` w batch loop (FIX-088 — bez tego ORA-17273) |
| - | Scenario 3 | Znalezienie konkretnego server process foreground `(LOCAL=NO)` zamiast `head -3` |
| - | Scenario 4 | Noticebox o Potential Data Loss Mode (FIX-077 — to nie regresja w MaxAvail+LagLimit=30) |
| D2 | Scenario 5 | Expected output: `commit_outcome=TRUE` (26ai) zamiast `commit_outcome_enabled=YES` (19c) |
| D3 | Scenario 5 | Usunięte ścieżki placeholdery `/path/to/project/...` |
| D4 | Scenario 5 | Przepisany — używa `validate_env.sh` v1.3 zamiast bezpośredniego `sqlplus @fsfo_check_readiness.sql` (oraz nieistniejącego `bash/validate_all.sh`) |

**Pliki:**
- NEW `<repo>/sql/fsfo_monitor_26ai.sql` (313 linii, sekcja 7 patched)
- `<repo>/VMs/scripts/validate_env.sh` v1.2 → v1.3 (pick_sql helper, 9 zmienionych linii w body)
- `<repo>/VMs/14_test_scenarios.md` — wstęp + 5 scenariuszy + scenario 5 fully rewritten
- `<repo>/VMs/FIXES_LOG.md` — ten entry

**Lekcja:** **dokument testowy musi być audytowany razem ze skryptami które wywołuje**. Doc 14 dotąd referował do narzędzi (`validate_all.sh`, `commit_outcome_enabled`, `/path/to/project/...`) które nigdy nie istniały lub zostały zmienione w trakcie 7 dokumentów (08-13). Bez audytu doc 14 → operator wykonujący scenariusze dostałby 5+ mylących błędów (ORA-00942, ORA-17273, "no such file", FAIL na PASS expected output) zamiast czystego runu. Wzorzec: **przed każdym kierunkiem (next document) zrób cross-check vs accumulated findings**, nawet jeśli dokument "wygląda gotowo" w repo. Listę findings kompiluje audit, fix to drugi krok.

---

## FIX-091 — `validate_env.sh` v1.3 → v1.4 — `SET SQLBLANKLINES ON` + parse_summary() (pierwszy run output)

**Problem:** Pierwszy run `validate_env.sh` v1.3 na prim01 dał dwa równoległe błędy:

```
[oracle@prim01 ~]$ bash /tmp/scripts/validate_env.sh
[13:31:35] [quick] Wywoluje validate_environment.sql na PRIM...
SP2-0042: unknown command "UNION ALL" - rest of line ignored.   ← x11
ORA-03048: SQL reserved word ')' is not syntactically valid following '...END FROM dual'

Status   Liczba % z 12
WARN          1 8.3%
N/A           3 25.0%
PASS          8 66.7%

[13:31:35] [quick] Wynik: PASS=3, WARN=3, FAIL=1                ← falszywie!
[13:31:35] ERROR: Quick: FAIL znalezione w validate_environment.sql
```

**Diagnoza dwóch równoległych błędów:**

### Błąd 1 — `SP2-0042 + ORA-03048`

`validate_environment.sql:40-200` ma jeden duży `WITH checks AS ( ... ) SELECT ...` z wieloma `UNION ALL` rozdzielonymi pustymi liniami dla czytelności:

```sql
WITH checks AS (
    SELECT 1, 'FSFO', ... FROM dual
    UNION ALL
    SELECT 2, 'FSFO', ... FROM dual

    UNION ALL                            ← pusta linia przed = sqlplus uznaje koniec instrukcji
    SELECT 3, 'TAC', ... FROM dual
    ...
)
SELECT * FROM checks ORDER BY ...;
```

sqlplus default `SET SQLBLANKLINES OFF` — **pusta linia w środku instrukcji SQL kończy ją**. Zatem sqlplus traktuje każdy fragment przed pustą linią jako osobne polecenie. `UNION ALL` na pierwszej linii nowej "instrukcji" → `SP2-0042: unknown command`. Po przelocie wszystkich UNION ALL parser dostaje fragmentaryczny SQL bez zamykającego `)` → `ORA-03048: SQL reserved word ')' is not syntactically valid`.

### Błąd 2 — falszywy `FAIL=1` mimo PASS=8

v1.3 heurystyka:
```bash
PASS_N=$(echo "$QUICK_OUT" | grep -cE '\bPASS\b' || true)
FAIL_N=$(echo "$QUICK_OUT" | grep -cE '\bFAIL\b' || true)
WARN_N=$(echo "$QUICK_OUT" | grep -cE '\bWARN\b' || true)
```

Liczy wystąpienia słów PASS/WARN/FAIL **w całym output** włącznie z legendą:

```
Interpretacja:
- PASS  = srodowisko gotowe do wdrozenia FSFO/TAC
- WARN  = dziala, ale zalecana poprawa przed produkcja
- FAIL  = blokuje wdrozenie, musi byc naprawione   ← grep matchuje 'FAIL' tutaj
- N/A   = nie dotyczy (np. TAC checks na bazie bez services)
```

Każde z 4 słów występuje +/- 3x w output (header tabeli, summary, legenda) → falszywy `FAIL=1`. Plus mimo że summary pokazuje `WARN 1 8.3%`, grep zwraca `WARN=3`.

**Naprawa v1.4:**

### A. `SET SQLBLANKLINES ON` w heredoc

Najmniej inwazyjne: dodać do heredoc PRZED `@<sql_file>`. Pokrywa wszystkie skrypty SQL (validate_environment, tac_full_readiness_26ai, fsfo_monitor_26ai, fsfo_broker_status). Plik `<repo>/sql/` zostają nietknięte.

```bash
QUICK_OUT=$(sqlplus -s "$CONNECT" <<SQLEOF 2>&1
SET SQLBLANKLINES ON
@$QUICK_SQL
EXIT
SQLEOF
)

# Plus w petli --full:
sqlplus -s "$CONNECT" <<SQLEOF > "$OUT_FILE" 2>&1
SET SQLBLANKLINES ON
@$SQL_FILE
EXIT
SQLEOF
```

### B. `parse_summary()` helper zamiast grep -c

```bash
parse_summary() {
    local out="$1"
    local status="$2"
    # Match dokladna linia "STATUS<spaces>N<spaces>X.X%" w summary table
    echo "$out" | awk -v s="$status" '$1==s && $2 ~ /^[0-9]+$/ { print $2; exit }'
}

PASS_N=$(parse_summary "$QUICK_OUT" PASS)
FAIL_N=$(parse_summary "$QUICK_OUT" FAIL)
WARN_N=$(parse_summary "$QUICK_OUT" WARN)
NA_N=$(parse_summary "$QUICK_OUT"  N/A)
PASS_N="${PASS_N:-0}"; FAIL_N="${FAIL_N:-0}"; ...
```

`awk '$1==s && $2 ~ /^[0-9]+$/'` matchuje tylko wiersze które:
1. Zaczynają się dokładnie od status string (PASS/WARN/FAIL/N/A) jako pierwsze pole
2. Mają liczbę jako drugie pole (czyli summary table, nie legenda)

### Smoke test na prim01 po SCP v1.4 (oczekiwany output):

```
[13:35:22] validate_env.sh v1.4 — mode=quick, target=PRIM, SQL_DIR=/tmp/sql
[13:35:22] [quick] Wywoluje validate_environment.sql na PRIM...
================================================================================
   FSFO + TAC Environment Validation (12 checks)
================================================================================
( ... 12 wierszy tabeli ... )

Status   Liczba % z 12
PASS          8 66.7%
WARN          1 8.3%
FAIL          0 0.0%
N/A           3 25.0%

[13:35:22] [quick] Wynik: PASS=8, WARN=1, FAIL=0, N/A=3
[13:35:22] DONE — quick validation OK (8 PASS, 1 WARN, 3 N/A)
```

**Pliki:** `<repo>/VMs/scripts/validate_env.sh` v1.3 → v1.4 (header + parse_summary helper + SQLBLANKLINES ON w 2 heredocach + parse calls + log msg).

**Lekcja:**
1. **`SET SQLBLANKLINES ON` jako default dla wrapperów wywołujących `<repo>/sql/`** — pliki SQL pisane "po ludzku" z pustymi liniami dla czytelności są standardową praktyką, ale sqlplus default OFF łamie je. Rozwiązanie zewnętrzne (heredoc setting) jest bardziej zachowawcze niż edytowanie pliku SQL który może być reused w innych kontekstach (np. odpalany z SQLcl gdzie SQLBLANKLINES może mieć inny default).
2. **Heurystyka exit code w wrapperze CI/CD musi wykluczać legendę i opisy** — używaj awk z dwoma warunkami (`$1==status && $2 ~ /^[0-9]+$/`) zamiast `grep -c`. To samo zalecenie dotyczy wszystkich skryptów które parse'ują output diagnostyczny: `deploy_tac_service.sh`, `setup_observer_infra01.sh`, etc. — TODO przy następnym audicie.

---

## FIX-092 — NEW `validate_environment_26ai.sql` (CDB-aware TAC checks)

**Problem:** Po FIX-091 v1.4 smoke test pokazał że TAC checks (#9-12) zwracają `0 service(s)` mimo że `MYAPP_TAC` istnieje i działa (smoke test doc 13 sekcja 6 PASS — loop PRIM1/PRIM2). Powód: `validate_environment.sql` wszystkie 4 checks używają `dba_services` w CDB$ROOT, a `MYAPP_TAC` jest **PDB-level service** w `APPPDB`.

**W CDB-multitenant `dba_services` widzi tylko CDB-level services** (typowo `PRIM.lab.local`, `PRIM_DGMGRL`). Services w PDB-ach są niewidoczne dla `dba_services` z root scope. To Oracle multitenant feature, nie 26ai-specific bug — ale w 23ai/26ai TAC services są **standardowo PDB-level** (założenie projektowe — PDB izoluje aplikacyjne workloads), więc `dba_services` w CDB$ROOT zawsze pokaże 0 TAC.

**Naprawa: NEW `<repo>/sql/validate_environment_26ai.sql`** (oryginał `validate_environment.sql` zostaje nietknięty per request user-a). Zgodne z wzorcem `_26ai` variants z FIX-082/090.

### Co zmienione w `_26ai` wariancie

1. **TAC checks (#9, 10, 11, 12)** — zamiana `FROM dba_services WHERE failover_type='TRANSACTION'` na `FROM cdb_services WHERE failover_type='TRANSACTION' AND con_id > 1` (PDB-only; con_id=1 to CDB$ROOT, con_id>1 to PDB).

   ```sql
   -- BEFORE (CDB$ROOT-only):
   SELECT COUNT(*) FROM dba_services WHERE failover_type = 'TRANSACTION';

   -- AFTER (PDB-aware):
   SELECT COUNT(*) FROM cdb_services WHERE failover_type = 'TRANSACTION' AND con_id > 1;
   ```

   Plus naglowki checków oznaczone `[PDB]` aby operator widzial scope.

2. **NEW sekcja "TAC services per PDB"** — dodatkowy diagnostic SELECT po głównych 12 checks pokazujący breakdown per container:

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

   Po doc 12 deploy operator widzi w outputcie:
   ```
   PDB                  Service          Failover     Commit  SessionSt  FAN
   APPPDB               MYAPP_TAC        TRANSACTION  TRUE    DYNAMIC    TRUE
   ```

3. **Sekcje 1-8 FSFO** — bit-identyczne z oryginałem (FSFO checks są CDB-level i `v$database`/`v$parameter`/`v$standby_log` dają tę samą wartość niezależnie od container scope).

4. **Summary sekcja** — analogicznie zaktualizowana: 4 checks TAC parsowane z `cdb_services WHERE con_id > 1` zamiast `dba_services`. Plus dodana noticebox: "Zakres TAC checks: cdb_services WHERE con_id > 1 (PDB-level). CDB$ROOT services (con_id=1) ignorowane."

5. **Header skryptu** — autor 2026-04-27, wersja 1.0, opis 2-paragrafowy dlaczego `_26ai` (bazuje na 1:1 oryginale, patched 4 sekcje TAC + dodana sekcja PDB breakdown).

### Auto-pick przez `validate_env.sh` v1.4

Bez zmian w skrypcie — `pick_sql() validate_environment` automatycznie wybiera `_26ai` jeśli istnieje (zgodnie z FIX-090 wzorcem). Output:

```
[HH:MM:SS] [quick] Wywoluje validate_environment_26ai.sql na PRIM...
================================================================================
   FSFO + TAC Environment Validation (12 checks) — 26ai CDB-aware variant
   TAC checks (#9-12) scope: cdb_services WHERE con_id > 1 (PDB-level)
================================================================================
( ... 12 wierszy tabeli — teraz #9-12 widzą TAC services z APPPDB ... )

TAC services per PDB / per container (cdb_services WHERE con_id > 1)
  PDB                  Service          Failover     Commit  SessionSt  FAN
  APPPDB               MYAPP_TAC        TRANSACTION  TRUE    DYNAMIC    TRUE
```

**Pliki:**
- NEW `<repo>/sql/validate_environment_26ai.sql` (~340 linii — kopia oryginału + 4 sekcje TAC patched + sekcja PDB breakdown + summary patched)
- `<repo>/VMs/scripts/validate_env.sh` — bez zmian, `pick_sql()` z FIX-090 obsługuje to automatycznie
- `<repo>/VMs/FIXES_LOG.md` — ten entry

**Re-deploy:** SCP `<repo>/sql/validate_environment_26ai.sql` → `oracle@prim01:/tmp/sql/`, ponowne uruchomienie `validate_env.sh` (preference automatyczna).

**Lekcja:**
1. **CDB-multitenant scope w validation queries** — w 23ai/26ai (i wcześniej w 19c+ multitenant) **żadne narzędzie diagnostyczne nie powinno używać `dba_services` w CDB$ROOT** dla TAC/aplikacyjnych services. Standardowy zakres to `cdb_services WHERE con_id > 1` (PDB-only) lub `cdb_services` (wszystkie containers). To samo dotyczy `dba_users`, `dba_tablespaces`, `dba_data_files` itd. — `cdb_*` views są superset.

2. **`_26ai` warianty stają się normą dla read-only repo SQL** — FIX-082 (`tac_full_readiness_26ai`, `tac_replay_monitor_26ai`), FIX-090 (`fsfo_monitor_26ai`), FIX-092 (`validate_environment_26ai`). Wzorzec: oryginał zostaje, NEW `_26ai` z patch + dwuparagrafowy header "DLACZEGO 26ai variant". `validate_env.sh` v1.3+ ma `pick_sql()` który auto-preferuje. Ten pattern jest teraz domknięty dla wszystkich 4 SQL wykorzystywanych przez `validate_env.sh`.

---

## FIX-093 — `commit_outcome`/`aq_ha_notifications` wartość `YES`/`NO` (nie `TRUE`/`FALSE`) + formatting

**Problem:** Po FIX-092 sekcja per-PDB pokazała `MYAPP_TAC` w `APPPDB` poprawnie, ale check #10 dał **FAIL** mimo że MYAPP_TAC ma `commit_outcome=TRUE` po stronie srvctl. Dodatkowo:
1. `nazwa_check FORMAT A40` był za wąski dla `commit_outcome=YES on TAC service(s) [PDB]` (43 znaki) — wrap w outputie
2. Separatory `PROMPT --------------------------------------------------------------------------------` po sekcji breakdown zostały **sklejone** z następną linią `PROMPT TAC services per PDB...` — output wyglądał jak `------- PROMPT TAC services...`

**Diagnoza FAIL #10:**

W output `cdb_services` per-PDB widać:
```
PDB         Service     Failover     Commit  SessionSt  FAN
APPPDB      MYAPP_TAC   TRANSACTION  YES     DYNAMIC    YES
```

Wartość `commit_outcome` to **`YES`**, nie `TRUE`. Validation SQL używał `commit_outcome='TRUE'` → 0 trafień → `FAIL`. To samo `aq_ha_notifications='YES'` (nie `'TRUE'`).

**Gotcha 26ai (i wcześniej 19c+ multitenant):**
- `srvctl config service -db PRIM -service MYAPP_TAC` pokazuje `Commit Outcome: TRUE` (boolean prezentacja w narzędziu CRS)
- `cdb_services.commit_outcome` jest VARCHAR2 z wartościami **`YES`/`NO`**

To samo `aq_ha_notifications`: srvctl pokazuje `AQ HA notifications: TRUE`, dictionary view zwraca `YES`. Tylko `failover_type` (`TRANSACTION`/`SELECT`/`NONE`) i `session_state_consistency` (`STATIC`/`DYNAMIC`) używają explicit string values w obu prezentacjach.

To było istniejące w oryginalnym `validate_environment.sql` od FIX-082 (i wcześniej w v1.0 od 2026-04-23) — bug pre-existing który **nie był widoczny** dopóki nie naprawiliśmy CDB scope w FIX-092 (z `dba_services` w CDB$ROOT zawsze 0 trafień → check skakał na N/A nie FAIL).

**Naprawa — 4 zmiany w `validate_environment_26ai.sql`:**

1. **`commit_outcome='TRUE'` → `commit_outcome='YES'`** (4 wystąpienia: check #10 dwa razy + summary #10 dwa razy)
2. **`aq_ha_notifications='TRUE'` → `aq_ha_notifications='YES'`** (4 wystąpienia: check #11 dwa razy + summary #11 dwa razy)
3. **`COLUMN nazwa_check FORMAT A40` → `A50`** — żeby `commit_outcome=YES on TAC service(s) [PDB]` (43 znaki) i pozostałe nazwy z `[PDB]` suffix mieściły się bez wrap
4. **Separatory PROMPT `---...---` → `===...===`** — `--` na początku argumentu PROMPT z `SET SQLBLANKLINES ON` aktywne (FIX-091) sqlplus traktuje jako "SQL comment continuation" → następna linia PROMPT staje się literalnym tekstem doklejonym do separatora. `==` nie ma takiej interpretacji.

**Naprawa równolegle w `tac_full_readiness_26ai.sql`** (też używa tych warunków):
- linia 228: `commit_outcome = 'TRUE'` → `'YES'`
- linia 262: `aq_ha_notifications = 'TRUE'` → `'YES'`

Oryginalne `validate_environment.sql` i `tac_full_readiness.sql` **zostają nietknięte** (per request user-a — tylko `_26ai` warianty modyfikujemy). Dla 19c działa `'TRUE'` (?) lub jeśli nie, to inny task.

**Update opisu check #10 w `_26ai` wariancie:**
```sql
'commit_outcome=TRUE on TAC service(s) [PDB]'
-- →
'commit_outcome=YES on TAC service(s) [PDB]'
-- + komentarz w SQL: "Kolumna `commit_outcome` w cdb_services to VARCHAR2 z
-- wartosciami YES/NO. srvctl pokazuje 'Commit Outcome: TRUE' (boolean) ale
-- dictionary view zwraca YES/NO."
```

**Pliki:**
- `<repo>/sql/validate_environment_26ai.sql` — 4 fixy (TRUE→YES x 8 wystąpień + A40→A50 + 2 separatory)
- `<repo>/sql/tac_full_readiness_26ai.sql` — 2 fixy (TRUE→YES w sekcji TAC service properties)
- `<repo>/VMs/FIXES_LOG.md` — ten entry

**Smoke test po SCP (oczekiwany output):**
```
[HH:MM:SS] [quick] Wywoluje validate_environment_26ai.sql na PRIM...
================================================================================
   FSFO + TAC Environment Validation (12 checks) — 26ai CDB-aware variant
================================================================================
( ... 12 wierszy, # 9-12 z [PDB] suffix bez wrap ... )

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
   Podsumowanie / Summary
================================================================================
Status   Liczba % z 12
PASS         12 100.0%

[HH:MM:SS] DONE — quick validation OK (12 PASS, 0 WARN, 0 N/A)
```

**Lekcja:**
1. **`srvctl config` ↔ `dba_services`/`cdb_services` mają różne formaty wartości** dla boolean atrybutów. srvctl używa `TRUE`/`FALSE` (CLI-friendly), słownik widoków używa `YES`/`NO` (legacy z 9i/10g). Zawsze sprawdzać format wartości empirycznie z `SELECT DISTINCT commit_outcome, aq_ha_notifications FROM cdb_services WHERE failover_type='TRANSACTION'` przed pisaniem warunków.
2. **`SET SQLBLANKLINES ON` (z FIX-091) wymaga unikania `--` na początku PROMPT-ów** bo sqlplus może próbować zinterpretować jako comment continuation. Bezpieczne separatory: `===`, `===`, `:::`, `~~~`. Stare `---` separatory działały bez SQLBLANKLINES (separator linii pustych).
3. **Pre-existing bug ujawnił się dopiero po wcześniejszym fixie** — `commit_outcome='TRUE'` był w oryginalnym `validate_environment.sql` od 2026-04-23 ale nie widać było problemu bo `dba_services` w CDB$ROOT zawsze zwracało 0 trafień (FIX-092 fixował tę warstwę). Wzorzec: każdy fix może odsłonić kolejny bug warstwę głębiej. Nie zakładaj że "PASS po fix" = "system poprawny" — zawsze sprawdź wartości przeciw rzeczywistości.

---

## 2026-04-27 (przed scenariuszem 1 doc 14)

## FIX-094 — Open PDB w READ ONLY na STBY (Active Data Guard)

**Problem:** Po doc 09 STBY miał `database_role=PHYSICAL STANDBY`, `open_mode=MOUNTED` (CDB) i wszystkie PDB-y w `MOUNTED` (`SHOW PDBS`: `PDB$SEED MOUNTED`, `APPPDB MOUNTED`). Wykryte podczas pre-flight do scenariusza 1 (planned switchover):

**Objawy:**
1. `bash /tmp/scripts/validate_env.sh -t STBY` — ORA-01219 na każdym query do `cdb_services`:
   ```
   ORA-01219: Database or pluggable database not open. Queries allowed on fixed tables or views only.
   ```
   3 sekcje SQL (głowny check 9-12, breakdown per-PDB, summary z #9-12 union all) — wszystkie crash. Wynik `PASS=0, WARN=0, FAIL=0, N/A=0` (szumi dane).
2. ADG read-only offload nie działa — APPPDB nie da się odpytać read-only ze standby.
3. Sam failover scenariusza 2 zadziała (PDB i tak otworzy się RW po promote), ale w trakcie pracy lab APPPDB w STBY powinno być OPEN RO.

**Root cause:** Doc 09 sekcja 8 (linia 640) i sekcja 6 post-duplicate sqlplus block (linia 495) miały `ALTER DATABASE OPEN READ ONLY` (otwiera CDB) **bez** `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` (otwiera PDB). Skrypt `duplicate_standby.sh` v3.3 sekcja 9 też kończy bez open PDB. W 23ai/26ai PDB nie auto-otwiera się przy CDB OPEN — wymaga jawnego ALTER PLUGGABLE DATABASE.

**Diagnostyka (w trakcie pre-flight scenariusza 1):**
```sql
SQL> SELECT database_role, open_mode FROM v$database;
PHYSICAL STANDBY MOUNTED                ← CDB sam jest MOUNTED, nie OPEN RO

SQL> SHOW PDBS;
2 PDB$SEED  MOUNTED                     ← PDB-y też MOUNTED
3 APPPDB    MOUNTED

SQL> ALTER PLUGGABLE DATABASE APPPDB OPEN READ ONLY;
ORA-01109: database not open            ← bo CDB MOUNTED
```

**Fix runtime (zastosowany w trakcie sesji 2026-04-27 ~15:30):**
```bash
# Krok 1 — broker APPLY-OFF (z infra01 wallet location FIX-072)
ssh oracle@infra01
dgmgrl /@PRIM_ADMIN
EDIT DATABASE STBY SET STATE='APPLY-OFF';
EXIT

# Krok 2 — open CDB+PDB (na stby01)
ssh oracle@stby01
sqlplus / as sysdba
ALTER DATABASE OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
SHOW PDBS;
-- 2 PDB$SEED  READ ONLY  NO
-- 3 APPPDB    READ ONLY  NO
EXIT

# Krok 3 — broker APPLY-ON
ssh oracle@infra01
dgmgrl /@PRIM_ADMIN
EDIT DATABASE STBY SET STATE='APPLY-ON';
EXIT
```

**`SAVE STATE` nie zadziała na STBY:**
```sql
SQL> ALTER PLUGGABLE DATABASE ALL SAVE STATE;
ORA-16000: Attempting to modify database or pluggable database that is open for read-only access.
```
Standby ma read-only dictionary — nie da się zapisać stanu PDB. Persistence po reboot wymaga osobnego mechanizmu (zob. FIX-095 TODO).

**Po fixie:**
```bash
ssh oracle@prim01 "bash /tmp/scripts/validate_env.sh -t STBY"
# [quick] Wynik: PASS=12, WARN=0, FAIL=0, N/A=0
# Plus breakdown: APPPDB / MYAPP_TAC / TRANSACTION / YES / DYNAMIC / YES
```

**Poprawka permanentna:**
1. **`VMs/09_standby_duplicate.md`:**
   - Sekcja 6 post-duplicate sqlplus (linia ~495): po `ALTER DATABASE OPEN READ ONLY` dodane `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY`.
   - Sekcja 8 standby OPEN + start MRP (linia ~640): identyczne dopisanie + `SHOW PDBS` weryfikacja + komentarz o limicie SAVE STATE.
2. **`VMs/scripts/duplicate_standby.sh` v3.3 → v3.4:**
   - Sekcja 9 sqlplus block: po `ALTER DATABASE OPEN READ ONLY` dopisane `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` z komentarzem FIX-094.
   - Header bump v3.4 + opis zmiany.
3. **TODO (FIX-095):** persistence stanu PDB po reboot stby01 — kandydaci:
   - **A)** Trigger `AFTER STARTUP ON DATABASE` w CDB$ROOT (wykonuje `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` przy każdym otwarciu standby, replikuje się przez DG, działa też na primary jako RW open).
   - **B)** Modyfikacja systemd unit `oracle-database-stby.service` (FIX-085 v1.3) — dodać ExecStartPost który wykonuje sqlplus z `STARTUP` (full open zamiast `STARTUP MOUNT`) + `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY`.
   - **C)** Broker property `StandbyPDBState` (jeśli dostępne w 26ai broker — sprawdzić).
   - Rekomendacja: A) najmniej invasive, jedna prawda dla obu sites.

**Lekcja:**
1. **CDB OPEN ≠ PDB OPEN w 23ai/26ai.** `ALTER DATABASE OPEN READ ONLY` otwiera tylko CDB$ROOT — PDB-y zostają w MOUNTED dopóki nie ma `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` lub `SAVE STATE` (na primary). Doc 09 to przeoczył — łatwy do pominięcia bo na primary `STARTUP` w skryptach DBCA auto-otwiera PDB-y, a na standby NIE.
2. **`SAVE STATE` jest nielegalne na standby** — read-only dictionary blokuje wszelkie modyfikacje stanu. Persistence wymaga osobnego mechanizmu (trigger, systemd, broker).
3. **`validate_environment_26ai.sql` powinien być odporny na MOUNTED PDB** — graceful N/A z message "PDB not open, skipped TAC checks" zamiast crash. Kandydat na FIX-095/096 (ale nie blokuje FIX-094).
4. **Pre-flight przed scenariuszami testowymi wykrył ten bug** — bez walidacji STBY (FIX-090..093) ten problem przeszedłby niezauważony aż do failover scenario 4 (apply lag exceeded — wymaga zapytań do APPPDB w stanie installed-but-not-running). Wniosek: pre-flight pełen (zarówno PRIM jak i STBY) jest must-have, nawet jeśli wydaje się że doc 09 "było dobrze" bo MRP applies.

---

## FIX-095 — Service `MYAPP_TAC` nie auto-startuje na non-Grid standby po promote (scenario 1 forward)

**Problem:** Po SWITCHOVER TO STBY broker zakończył sukcesem (`Switchover succeeded, new primary is "stby"`), ale TestHarness na client01 dostał `UCP-29: Failed to get a connection` przez ~60s i nie reconnectował się sam. Diagnoza pokazała że service `MYAPP_TAC` **nie został wystartowany** na nowym primary (stby01):

```sql
SQL> ALTER SESSION SET CONTAINER=APPPDB;
SQL> SELECT con_id, name FROM gv$active_services WHERE name LIKE '%myapp%';
no rows selected   ← service nie chodzi
```

**Root cause:** Service `MYAPP_TAC` utworzony przez `srvctl add service ... -role PRIMARY` w doc 12 jest **CRS-managed na PRIM**. Grid Infrastructure Auto-Start mechanism reaguje na role change i startuje service `-role PRIMARY` na nowym primary side. **Ale stby01 jest SI bez Grid Infrastructure** — brak CRS, brak `srvctl`, brak auto-start mechanism. Po promote do PRIMARY service istnieje w `cdb_services` (replikowany przez DG) ale nikt go nie startuje.

**Symptomy klienta:**
- TestHarness petla [37..97] = `ERROR: UCP-29: Failed to get a connection` (~60s)
- Powód: TNS fallback `prim-scan → stby01:1521` znajduje listener, ale listener nie zna `myapp_tac.lab.local` (service nie wystartował) → ORA-12514 → UCP retry → exhaustion → UCP-29.

**Fix runtime (zastosowany w trakcie sesji 16:11):**
```sql
-- Na stby01 po SWITCHOVER, jako sysdba w CDB$ROOT:
ALTER SESSION SET CONTAINER=APPPDB;     -- ⚠️ MUSI być w PDB context (DBMS_SERVICE jest container-scoped)
EXEC DBMS_SERVICE.START_SERVICE('myapp_tac');   -- ⚠️ LOWERCASE, BEZ db_domain (.lab.local)
-- PL/SQL procedure successfully completed.
```

**Pułapki nazwy:**
- `'MYAPP_TAC'` (uppercase, jak w `cdb_services.network_name`) → ORA-44773 "Cannot perform requested service operation" (wprowadzający w błąd komunikat — NIE chodzi o CRS-managed lock, chodzi o case)
- `'myapp_tac.lab.local'` (z domain) → ORA-44304 "service does not exist"
- `'myapp_tac'` (lowercase, internal name) → SUCCESS

26ai/23ai gotcha: `cdb_services.network_name` przechowuje uppercase, ale `DBMS_SERVICE.START_SERVICE` używa internal lowercase name (jak rejestrowany w listener z db_domain auto-suffix).

**Po fix:** Klient TestHarness zaczął dostawać `[98] OK: STBY SID=397 ...` — connection reuse i replay.

**Drain klienta:** ~60s (linie [37]→[97] w log). Z porządnym auto-start service drain byłby ~5-15s (UCP otrzymuje FAN UP event przez ONS od razu po service start).

**Permanent fix (kandydat — long-term, FIX-097/098):**
1. **Trigger `AFTER STARTUP ON DATABASE` w CDB$ROOT** (replikuje się przez DG do stby01):
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
   ⚠️ Trigger reaguje na STARTUP (cold restart), **NIE na role change**. Dla switchover/failover potrzebny też explicit step.

2. **Doc 14 scenario 1+2 — post-switchover/failover housekeeping:**
   ```bash
   # Conditional — tylko jeśli nowy primary == stby01 (SI bez Grid)
   NEW_PRIMARY=$(ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION'" | tr '\n' ' ' | grep -oP '\w+(?= - Primary database)')
   if [[ "$NEW_PRIMARY" == "stby" ]]; then
       ssh oracle@stby01 "sqlplus -s / as sysdba <<EOF
       ALTER SESSION SET CONTAINER=APPPDB;
       EXEC DBMS_SERVICE.START_SERVICE('myapp_tac');
       EXIT
   EOF"
   fi
   ```

3. **Long-term lepszy fix:** doc 12 powinno tworzyć service przez `DBMS_SERVICE.CREATE_SERVICE` (PDB-level) zamiast `srvctl add service` (CRS-managed) — działa na obu typach baz (RAC + Grid jak i SI bez Grid). Wymaga też ręcznego setup `dba_pdbs.failover_role` zamiast srvctl `-role PRIMARY` flag. To jest większa zmiana — kandydat na osobny task po doc 14.

**Lekcja:**
1. **Mixed RAC+SI MAA wymaga uwagi: services CRS-managed na primary nie auto-przenoszą się na non-Grid standby.** Standardowy guide MAA zakłada że obie strony mają Grid (Symmetric MAA). Asymmetric setup (RAC primary, SI standby) wymaga dodatkowych mechanizmów dla service availability.
2. **`DBMS_SERVICE.START_SERVICE` wymaga PDB context i lowercase nazwy.** Komunikaty błędów wprowadzają w błąd: ORA-44773 sugeruje "use SRVCTL" (myli z CRS-managed), ale rzeczywisty powód to mismatch case lub container.
3. **Pre-flight FIX-090..094 nie wykrył tego.** Walidacja sprawdzała że service jest skonfigurowany w `cdb_services` z poprawnymi atrybutami — ale NIE testowała czy potrafi się wystartować na drugim site. Kandydat na pre-flight enhancement: po switchover sanity-check `gv$active_services` na nowym primary.

---

## FIX-096 — `StaticConnectIdentifier` explicit per-instance po ENABLE CONFIGURATION (broker auto-derive bierze PORT=1521)

**Problem:** Podczas SWITCHOVER TO PRIM (rollback) broker próbował zrestartować STBY instance jako nowy standby, ale dostał:
```
Unable to connect to database using (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))
ORA-12514: Cannot connect to database. Service STBY_DGMGRL.lab.local is not registered with the listener at host 192.168.56.13 port 1521.
```

Connection string ma **PORT=1521**, ale `STBY_DGMGRL.lab.local` jest static SID_DESC w `LISTENER_DGMGRL` na **PORT=1522** (FIX-050).

**Root cause:** Broker dla każdej instancji auto-derive `StaticConnectIdentifier` z parametru `local_listener` SPFILE. Na stby01:
- `local_listener` = `(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))` (default LISTENER)
- `LISTENER_DGMGRL` na 1522 jest osobnym entry w `listener.ora`, niezarejestrowany w `local_listener`
- Broker derive bierze PORT=1521 → źle

**Diagnoza:**
```
DGMGRL> SHOW DATABASE 'stby' StaticConnectIdentifier;
StaticConnectIdentifier = '(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521)) ...'
                                                                              ^^^^^^^^^ ZŁE

DGMGRL> SHOW DATABASE 'PRIM' StaticConnectIdentifier;
ORA-16606: unable to find property "staticconnectidentifier"
```

PRIM nie ma explicit, broker używa default (działa accidentally bo Grid CRS rejestruje `PRIM_DGMGRL` w SCAN+local).

**Fix runtime (zastosowany ~16:25):**
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

**Składnia:**
- **SI standby:** `EDIT DATABASE '<dbname>' SET PROPERTY 'StaticConnectIdentifier'='...'`
- **RAC (per-instance):** `EDIT INSTANCE '<inst>' ON DATABASE '<dbname>' SET PROPERTY 'StaticConnectIdentifier'='...'`
- **Property name** musi być w cudzysłowach (`'StaticConnectIdentifier'`); bez quotes ORA-16606.

**Skutek dla doc 10 / configure_broker.sh v3.0 (kandydat FIX-097):**

`configure_broker.sh` v2.x kończy na `ENABLE CONFIGURATION` + verify `Configuration Status: SUCCESS`. **Brak kroku ustawienia explicit `StaticConnectIdentifier`.** Skutek: konfig pozornie działa (`SHOW CONFIGURATION = SUCCESS`), pierwszy switchover też się udaje (broker używa innych connection paths dla initial role change), ale **drugi switchover** fail-uje przy restart instance. Test SWITCHOVER musi przechodzić w obie strony (forward+rollback) jako sanity check przed go-live.

**Plan FIX-097 (configure_broker.sh v3.0):**

Po sekcji 2 (ENABLE CONFIGURATION) dodać sekcję 2b "Set StaticConnectIdentifier per-instance":
```bash
dgmgrl /@PRIM_ADMIN <<DGEOF
EDIT DATABASE 'stby' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM1' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM1)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM2' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim02.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM2)(SERVER=DEDICATED)))';
EXIT
DGEOF
```

**Lekcja:**
1. **Broker auto-derive nie zna LISTENER_DGMGRL na 1522** — zawsze bierze port z `local_listener` (czyli LISTENER:1521). Jeśli setup ma osobny static listener na nieładowych port, **musi być explicit `StaticConnectIdentifier`**.
2. **Pierwszy switchover sukces ≠ broker config zdrowy.** Trzeba testować obie strony (forward+rollback) zanim się ogłosi go-live. Pierwszy switchover może użyć inkrementalnych ścieżek connection (DGConnectIdentifier vs StaticConnectIdentifier), drugi już potrzebuje pełnego statyk.
3. **`StaticConnectIdentifier` na RAC jest per-instance** — `EDIT DATABASE` rzuca ORA-16582. Musisz `EDIT INSTANCE 'PRIMx' ON DATABASE 'PRIM'`.

---

## Otwarte / do weryfikacji

| # | Co sprawdzić | Kiedy |
|---|-------------|-------|
| 1 | Czy `oracle-database-preinstall-23ai` instaluje się poprawnie w `%post` (wymaga NAT + repo ol8_appstream) | Po pierwszym restarcie VM |
| 2 | Czy nazwy interfejsów (`enp0s3`, `enp0s8`, `enp0s9`, `enp0s10`) są prawidłowe z kartami virtio w VirtualBox | Po zalogowaniu: `ip -br link show` |
| 3 | Czy `compat-openssl11` zostaje doinstalowany jako zależność preinstall RPM | `rpm -q compat-openssl11` po instalacji |
| 4 | Czy `setup_observer_infra01.sh` v1.2 z FIX-067/068/069 + #4-7 przechodzi end-to-end na chodzącym brokerze (post doc 10) | Po SCP v1.2 → infra01 |
| 5 | Czy są jeszcze inne legacy 19c keys w `client.rsp` (PROXY_*, ORACLE_HOSTNAME) których 23.0.0 też nie akceptuje | Sprawdź gdy się pojawią INS-10105 na nowych instalkach |
