> [🇬🇧 English](./README.md) | 🇵🇱 Polski

# 🛡️ VMs2-install — Oracle 26ai MAA Environment

![Oracle 26ai](https://img.shields.io/badge/Oracle-26ai%20(23.26.1)-F80000?logo=oracle&logoColor=white)
![Oracle Linux 8](https://img.shields.io/badge/Oracle%20Linux-8-EF0000?logo=oracle&logoColor=white)
![MAA](https://img.shields.io/badge/MAA-RAC%20%2B%20Data%20Guard-1f6feb)
![FSFO](https://img.shields.io/badge/FSFO-Fast--Start%20Failover-2ea44f)
![TAC](https://img.shields.io/badge/TAC-Transparent%20App%20Continuity-success)
![Status](https://img.shields.io/badge/Status-LAB%20%2F%20POC-yellow)
![Hypervisor](https://img.shields.io/badge/Hypervisor-VirtualBox%207.x-183A61?logo=virtualbox&logoColor=white)

Witaj w zrewidowanej i ustandaryzowanej instrukcji wdrożenia środowiska **Oracle 26ai (23.26.1)** opartej o architekturę Maximum Availability Architecture (MAA).

Głównym celem tego podprojektu było wyciągnięcie wniosków z poprzednich instalacji (w tym licznych poprawek tzw. "FIX-ów" dla 26ai) i stworzenie liniowej, bezbłędnej i zautomatyzowanej ścieżki instalacji od poziomu pustych maszyn wirtualnych aż po testy mechanizmu **Transparent Application Continuity (TAC)** w klastrze uzbrojonym w **Fast-Start Failover (FSFO)**.

---

## 📦 Notacja i transfer plików

Skrypty i pliki konfiguracyjne przechowywane są na hoście Windows w katalogu projektu:
`<REPO>`

**Przed każdym krokiem instalacji** skopiuj potrzebne podkatalogi na docelowy serwer Linux przez MobaXterm (SFTP) lub `scp`:
```
# Kopiowanie przez scp z hosta Windows (Git Bash / PowerShell z OpenSSH):
scp -r scripts/ response_files/ sql/ src/ root@prim01:/tmp/
```
Po skopiowaniu pliki są dostępne pod `/tmp/scripts/`, `/tmp/response_files/` itd.
Wszystkie komendy w `docs/` używają `/tmp/` jako lokalizacji roboczej.

> Komendy PowerShell (np. `vbox_create_vms.ps1`) uruchamiane są bezpośrednio na hoście Windows — nie wymagają kopiowania.

---

## 📁 Struktura Katalogów

Zamiast przeklejać skrypty ręcznie, całe wdrożenie zostało podzielone na tematyczne zasoby:

*   📑 **`docs/`** — Główna dokumentacja krok po kroku (od 01 do 09) plus dokumenty uzupełniające (Performance Tuning, Architecture Diagrams).
*   🚀 **`kickstart/`** — Zoptymalizowane pliki Kickstart dla systemu Oracle Linux 8. Włączają LVM iSCSI Block Backstore dla najwyższej wydajności, wyłączają THP i automatycznie montują katalogi współdzielone (VirtualBox Shared Folders).
*   ⚙️ **`scripts/`** — Gotowe skrypty powłoki `bash` dla środowisk. Konfigurują sieć, targety iSCSI, tworzą siatkę autoryzacyjną SSH, cicho instalują oprogramowanie Grid/DB i powołują bazy Standby przez Brokera.
*   📝 **`response_files/`** — Zestaw plików `.rsp` precyzyjnie przygotowanych pod rygorystyczny schemat narzędzi z Oracle 26ai (usunięto z nich przestarzałe dla 19c wpisy).
*   🔍 **`sql/`** — Narzędzia diagnostyczne wykonujące tzw. *Readiness Checks* dla środowiska (np. sprawdzające gotowość bazy do powiadomień FAN/TAC).
*   ☕ **`src/`** — Kody źródłowe, w tym testowy klient Java UCP `TestHarness.java` używający klasy `oracle.jdbc.replay.OracleDataSourceImpl` do weryfikacji przezroczystego przepinania sesji.

---

## 🗺️ Mapa Drogowa Instalacji

Proces budowy podzielony jest na 8 spójnych kroków plus dodatek ze scenariuszami testowymi. Wykonuj je w poniższej kolejności:

1.  🏗️ **`01_Architecture_and_Assumptions_PL.md`** — Wymagania pamięciowe, porty, nazewnictwo i wstępny rzut na topologię maszyn.
2.  💻 **`02_OS_and_Network_Preparation_PL.md`** — Wdrażanie systemów operacyjnych z gotowych kickstartów, testowanie sieci i budowa Full Mesh SSH.
    - 🧰 **`02b_OS_Preparation_Manual_PL.md`** — Alternatywa dla kickstarta: wszystkie kroki krok po kroku dla każdego hosta z komendami copy/paste (sieć, użytkownicy, katalogi, THP, HugePages, NTP, DNS).
3.  💾 **`03_Storage_iSCSI_PL.md`** — Serce wydajności — tworzenie Targetów iSCSI LVM na serwerze `infra01` i podpinanie ich jako surowe bloki do klastra RAC.
4.  🧱 **`04_Grid_Infrastructure_PL.md`** — Instalacja `Grid Infrastructure` na `prim01/prim02` oraz oprogramowania `Oracle Restart` na węźle `stby01`.
5.  🗄️ **`05_Database_Primary_PL.md`** — Instalacja silnika DB (Software-Only) i powołanie `CDB PRIM` z pliku odpowiedzi DBCA. Konfiguracja ARCHIVELOG i Flashback.
6.  🔁 **`06_Data_Guard_Standby_PL.md`** — Nowoczesne, zautomatyzowane tworzenie bazy rezerwowej przy pomocy wbudowanego polecenia Brokera (`CREATE PHYSICAL STANDBY`).
7.  👁️ **`07_FSFO_Observers_PL.md`** — Instalacja Klienta 26ai, utworzenie bezhasłowego autologowania do Wallet SSO i aktywacja Fast-Start Failover.
8.  🔄 **`08_TAC_and_Tests_PL.md`** — Ostateczny sprawdzian. Konfiguracja serwisu aplikacyjnego, cross-site ONS i uruchomienie symulowanej usterki w Java UCP.
9.  🧪 **`09_Test_Scenarios_PL.md`** — Zestaw scenariuszy demonstrujących niezawodność architektury (Switchover, nieplanowany Failover, długotrwały TAC Replay oraz blokady Apply Lag).

---

## 📚 Dokumentacja uzupełniająca

Oprócz numerowanych kroków instalacji, w katalogu `docs/` znajdują się dwa przekrojowe dokumenty referencyjne:

| Dokument | Plik | Opis |
|---|---|---|
| ⚡ **Performance Tuning** | [10_Performance_Tuning_PL.md](./docs/10_Performance_Tuning_PL.md) | Kompleksowy przewodnik optymalizacji wydajności labu Oracle 26ai HA. Pokrywa cztery warstwy: **VirtualBox** (`paravirtprovider=kvm` zamiast default, NIC `virtio` zamiast `e1000`, `hostiocache=on` na infra01), **OS** (HugePages 2200 stron, THP=never przez systemd, memlock=unlimited, jumbo frames MTU 9000 na storage NIC), **iSCSI/LVM** (block backstore zamiast fileio, scheduler `mq-deadline`, `emulate_write_cache=1` na DATA/RECO bez OCR, `replacement_timeout=15`, `queue_depth=64`) i **DBCA** (`use_large_pages=ONLY` + `lock_sga=TRUE`). Łączny efekt: DBCA z ~50 min → ~25 min, fio random write IOPS ↑ 3–5×, RMAN backup ~5 min zamiast ~12 min. Zawiera procedurę wdrożenia oraz checklisty walidacji. |
| 🗺️ **Architecture Diagrams** | [ARCHITECTURE_DIAGRAMS_PL.md](./docs/ARCHITECTURE_DIAGRAMS_PL.md) | Wizualne uzupełnienie dokumentacji w formie 10 diagramów Mermaid (renderują się natywnie w GitHub, GitLab, VS Code, Obsidian): (1) topologia 5 VM, (2) sieci i adresacja IP `vboxnet`/internal, (3) stack storage iSCSI + LVM + ASM (block backstore), (4) Data Guard + Broker + redo transport, (5) Multi-Observer FSFO (Master + 2 Backup), (6) TAC + klient UCP + FAN events, (7) sekwencja nieplanowanego failovera FSFO, (8) sekwencja planowanego switchovera, (9) bezpieczeństwo walletów i haseł, (10) macierz portów sieciowych / firewall. |

> Wersja angielska tych dokumentów jest dostępna przez przełącznik na górze każdego pliku (`🇬🇧 English | 🇵🇱 Polski`).

---

## ✈️ Przed pierwszym uruchomieniem (PRE-FLIGHT)

> Niezależnie czy idziesz **ścieżką automatyczną** (skrypty), czy **ścieżką manualną** (krok-po-kroku z `docs/`), wykonaj poniższe punkty raz przed startem — **w tej kolejności**.

1. 🔐 **Sekret laboratoryjny** (`/root/.lab_secrets`) — na **każdym hoście**, na którym uruchamiasz skrypty `bash` (ssh_setup.sh, setup_observer.sh, create_standby_broker.sh, setup_cross_site_ons.sh, tune_storage_runtime.sh):
   ```bash
   sudo tee /root/.lab_secrets >/dev/null <<'EOF'
   export LAB_PASS='Oracle26ai_LAB!'
   EOF
   sudo chmod 600 /root/.lab_secrets
   ```
   Skrypty same czytają ten plik (`source /root/.lab_secrets`) — nie trzeba `sudo -E` ani eksportu zmiennej w shellu. To samo hasło używane jest dla wszystkich kont (root/oracle/grid/SYS/SYSTEM/ASM/PDB Admin/wallet) — konwencja LAB-u opisana w `docs/01_Architektura_i_Zalozenia.md` sekcja 2.

2. 🌐 **DNS i NTP** — kickstart infra01 konfiguruje `bind9` (strefa `lab.local`) i `chrony` (serwer NTP) automatycznie po restarcie. Kickstarty pozostałych VM ustawiają chrony jako klient (`192.168.56.10`) i wymuszają DNS resolver na `enp0s3` (zabezpieczenie przed nadpisaniem przez DHCP NAT). **Nic nie trzeba robić ręcznie.** Jeśli po restarcie DNS nie działa — patrz `docs/02` sekcja 4 (fallback).

3. ✅ **Walidacja środowiska** — **po DNS i chrony**, przed `gridSetup.sh`, uruchom na **prim01** (jako oracle lub grid) oraz opcjonalnie na **stby01**:
   ```bash
   # prim01 (jako oracle) — kompleksowy check, w tym SSH equivalency do prim02/stby01:
   bash /tmp/scripts/validate_env.sh --full
   # stby01 (jako oracle) — lokalny check DNS/NTP/HugePages/THP/memlock:
   bash /tmp/scripts/validate_env.sh --full
   ```
   Test pokrywa: DNS, NTP, SSH equivalency, `/u01` mount, dyski ASM, porty Oracle, HugePages, THP, memlock. Wszystkie statusy `PASS` = można jechać dalej. `FAIL` = napraw zanim zaczniesz GI install.

   > **memlock WARN?** Kickstart tworzy `zz-oracle-memlock.conf` (prefix `zz-` > `oracle-database-preinstall-23ai.conf` — zawsze wygrywa). Jeśli instalowałeś ze starszego kickstartu, utwórz ten plik ręcznie — patrz `docs/02` sekcja 4c.

4. ⚡ **Wydajność (opcjonalnie ale zalecane)** — po skonfigurowaniu iSCSI:
   ```bash
   sudo bash /tmp/scripts/tune_storage_runtime.sh --target=infra        # na infra01
   sudo bash /tmp/scripts/tune_storage_runtime.sh --target=initiator    # na prim01 i prim02
   ```
   Szczegóły w [`docs/10_Performance_Tuning_PL.md`](./docs/10_Performance_Tuning_PL.md).

> **Spójność dwóch ścieżek:** ścieżka automatyczna (skrypty) i manualna (komendy z `docs/`) używają **tych samych** plików konfiguracyjnych (`response_files/*.rsp`, `kickstart/*.cfg`) i prowadzą do identycznego stanu końcowego. Możesz przełączać się między nimi pomiędzy krokami (np. wykonać GI auto-skryptem, ale standby tworzyć ręcznie wg `docs/06`).

---

Miłej instalacji! 🚀
