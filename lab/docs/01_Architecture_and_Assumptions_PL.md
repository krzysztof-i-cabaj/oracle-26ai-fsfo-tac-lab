> [🇬🇧 English](./01_Architecture_and_Assumptions.md) | 🇵🇱 Polski

# 01 — Architektura Środowiska i Główne Założenia (VMs2-install)

> **Cel:** Zdefiniowanie nowej struktury maszyn wirtualnych dla Oracle 26ai (23.26.1) uwzględniającej Data Guard (Primary RAC 2-węzłowy -> Standby Single Instance z Oracle Restart), FSFO (3 Observery) i TAC.
> **Uwaga:** To środowisko opiera się na wnioskach z poprzednich instalacji (m.in. alokacja pamięci RAM).

---

## 1. Topologia maszyn wirtualnych (5 VM)

Całe środowisko składa się z 5 maszyn wirtualnych w VirtualBox. 

| VM | Hostname | Rola | vCPU | RAM | Dysk OS | Zasoby dodatkowe |
|----|----------|------|------|-----|---------|-------------------|
| **VM1** | `prim01.lab.local` | RAC node 1 (Primary DC) | 4 | **9 GB** | 60 GB | iSCSI initiator (podłączone LUNy ASM) |
| **VM2** | `prim02.lab.local` | RAC node 2 (Primary DC) | 4 | **9 GB** | 60 GB | iSCSI initiator (podłączone LUNy ASM) |
| **VM3** | `stby01.lab.local` | Single Instance (Standby DR) z **Oracle Restart** | 4 | **8 GB** | 100 GB | XFS dla bazy, Oracle Restart zarządza usługami |
| **VM4** | `infra01.lab.local`| DNS, NTP, iSCSI Target, **Master Observer (EXT)** | 2 | **8 GB** | 140 GB | Pamięć LIO Cache (8GB RAM), LUNy dla prim01/02 |
| **VM5** | `client01.lab.local`| Klient do testowania TAC (Java/UCP) | 2 | 3 GB | 30 GB | Oracle Client 23.26 |

*Rozmiary RAM zostały dostosowane (zwiększone dla prim01/02 do 9GB ze względu na restrykcje `cluvfy` w 26ai, oraz infra01/stby01 dla wydajności page cache i Oracle Restart).*

---

## 2. Globalne parametry laboratorium

Dla uproszczenia zarządzania używamy spójnego nazewnictwa i haseł w całym laboratorium:

*   **Hasło dla wszystkich kont OS (`root`, `oracle`, `grid`) oraz kont Oracle DB (`SYS`, `SYSTEM`):**
    *   `Oracle26ai_LAB!`
*   **Sieć publiczna (vboxnet0):** `192.168.56.0/24`
*   **Sieć prywatna/Interconnect (rac-priv):** `192.168.100.0/24`
*   **Sieć iSCSI/Storage (rac-storage):** `192.168.200.0/24`
*   **CDB / PDB Name:** `PRIM` / `APPPDB`
*   **DB_UNIQUE_NAME (Primary / Standby):** `PRIM` / `STBY`
*   **Service Name dla TAC:** `MYAPP_TAC`

---

## 3. Sieć i Adresacja IP (Szczegóły)

Wszystkie maszyny korzystają ze stałych adresów IP w podsieciach VirtualBox. Na maszynie `infra01` zostanie uruchomiony serwer DNS (`bind9`), który zapewni rozwiązywanie nazw dla wszystkich hostów i adresów SCAN klastra Primary.

### Mapowanie adresów IP:
| Hostname | Public (56.x) | Interconnect (100.x) | Storage (200.x) |
|----------|---------------|----------------------|-----------------|
| `infra01`| .10 | .10 | .10 |
| `prim01` | .11 | .11 | .11 |
| `prim02` | .12 | .12 | .12 |
| `stby01` | .13 | - | - |
| `client01`| .15 | - | - |

**Wirtualne adresy IP (Grid Managed):**
*   `prim01-vip`: `192.168.56.21`
*   `prim02-vip`: `192.168.56.22`
*   `scan-prim`: `192.168.56.31`, `192.168.56.32`, `192.168.56.33` (DNS round-robin)

---

## 4. Konfiguracja Observerów (FSFO)

Architektura zakłada 3 Observery, aby zapewnić najwyższą dostępność mechanizmu FSFO:
1.  **Master Observer (`obs_ext`)**: Uruchomiony na maszynie `infra01` (symulacja trzeciego ośrodka - EXT).
2.  **Backup Observer 1 (`obs_dc`)**: Uruchomiony na węźle `prim01` (DC).
3.  **Backup Observer 2 (`obs_dr`)**: Uruchomiony na węźle `stby01` (DR).

---

## 4.1 Wymagania licencyjne Oracle (F-21)

> **Uwaga:** poniższe wymagania dotyczą **realnego wdrożenia produkcyjnego**. LAB na własnym OL 8.10 / VirtualBox jest objęty wyłącznie *Developer License* (dla nauki, testów wewnętrznych, demo techniczne — bez uruchamiania workloadu produkcyjnego).

| Komponent / funkcja | Wymagana licencja Oracle |
|----|----|
| Grid Infrastructure (cluster) | **Database Enterprise Edition** + **RAC option** |
| 2-węzłowy klaster Primary (prim01+prim02) | **Real Application Clusters** (RAC) |
| Data Guard (Physical Standby) | **Database Enterprise Edition** (sam DG bez ADG mieści się w EE) |
| `MYAPP_RO` na stby01 (read-only access do standby) | **Active Data Guard** (opcja dodatkowa) |
| Transparent Application Continuity (TAC) | EE + RAC (TAC bazuje na Application Continuity, dostępne od 12.2 EE) |
| `DBMS_APP_CONT.GET_LTXID_OUTCOME` / Transaction Guard | EE (część bazowa) |
| FSFO + Observer (DG Broker) | EE (Broker w bazie EE) |
| `V$ACTIVE_SESSION_HISTORY`, `DBA_HIST_*` (AWR/ASH w monitorach) | **Diagnostic Pack** (oddzielna licencja) |
| `DBMS_SQLTUNE`, SQL Tuning Advisor | **Tuning Pack** (oddzielna licencja) |
| Oracle Wallet / TDE (jeśli włączone) | **Advanced Security Option** |

**Konsekwencje praktyczne dla VMs2-install:**
- Skrypty diagnostyczne korzystają z `V$ACTIVE_SESSION_HISTORY` (np. `tac_replay_monitor_26ai.sql` sekcja 6) — **wymaga Diagnostic Pack** w produkcji. W LAB-ie funkcjonuje bez ostrzeżeń.
- Serwis read-only (`MYAPP_RO`) na stby01 używa Active Data Guard — w produkcji wyłącznie po zakupie ADG; **jeśli nie masz ADG, usuń `MYAPP_RO` z konfiguracji** lub trzymaj stby01 w trybie MRP-only (Apply Only) bez open read-only.
- TAC + RAC opcja musi być licencjonowana per-rdzeń (Named User Plus lub Processor metric).

---

## 5. Nowe podejście: Oracle Restart dla Standby i DGMGRL DUPLICATE

*   **Oracle Restart na `stby01`**: Zamiast czystej instalacji samej bazy, użyjemy instalacji **Grid Infrastructure for a Standalone Server**. Pozwoli to na tworzenie serwisów CRS zarządzających automatycznym startem bazy `STBY` i dedykowanego listenera DGMGRL po restarcie maszyny.
*   **DGMGRL DUPLICATE**: Proces tworzenia bazy Standby zostanie całkowicie zautomatyzowany z użyciem Data Guard Broker (komenda `CREATE CONFIGURATION` a następnie `DUPLICATE`). Eliminujemy pisanie skryptów RMAN.

---
**Następny krok:** `02_OS_and_Network_Preparation_PL.md`
