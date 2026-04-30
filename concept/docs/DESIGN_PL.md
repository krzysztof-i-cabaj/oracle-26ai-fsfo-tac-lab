> [🇬🇧 English](./DESIGN.md) | 🇵🇱 Polski

# 🎨 DESIGN.md — FSFO + TAC dla Oracle 19c (3-site MAA)

![Oracle](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![Status](https://img.shields.io/badge/Status-accepted-4CAF50)
![ADR count](https://img.shields.io/badge/ADRs-8-4CAF50)

> Specyfikacja projektu — decyzje architektoniczne, konwencje, bezpieczeństwo, testy.
> Project specification — architectural decisions, conventions, security, testing.

---

## 📋 Spis treści / Table of Contents

1. [Kontekst / Context](#1-kontekst--context)
2. [Decyzje architektoniczne (ADR)](#2-decyzje-architektoniczne-adr--architectural-decision-records)
3. [Kompatybilność wersji DB](#3-kompatybilność-wersji-db--db-version-compatibility)
4. [Konwencje nazewnictwa](#4-konwencje-nazewnictwa--naming-conventions)
5. [Bezpieczeństwo](#5-bezpieczeństwo--security)
6. [Strategia testów](#6-strategia-testów--testing-strategy)
7. [Progi alertów](#7-progi-alertów--alert-thresholds)
8. [Graceful degradation](#8-graceful-degradation)
9. [Przyszłe rozszerzenia](#9-przyszłe-rozszerzenia--future-extensions)
10. [Appendix](#10-appendix--appendix)

---

## 1. Kontekst / Context

### 1.1 Cel / Goal

- **PL:** Dostarczyć kompletny, powtarzalny zestaw dokumentów i skryptów do wdrożenia Oracle 19c Fast-Start Failover (FSFO) + Transparent Application Continuity (TAC) w architekturze 3-site (MAA), z Observer HA rozproszonym pomiędzy ośrodki DC, DR i EXT.
- **EN:** Deliver a complete, repeatable set of documents and scripts for deploying Oracle 19c Fast-Start Failover (FSFO) + Transparent Application Continuity (TAC) in a 3-site MAA topology, with Observer HA distributed across DC, DR, and EXT sites.

### 1.2 Problem / Problem

- **PL:** Manualny failover Data Guard + brak replay transakcji = długie przestoje aplikacji (minuty → dziesiątki minut), ręczne odzyskiwanie stanu sesji, ryzyko utraty transakcji w trakcie awarii. Single Observer = single point of failure w łańcuchu decyzyjnym FSFO.
- **EN:** Manual Data Guard failover + no transaction replay = long application downtime (minutes → tens of minutes), manual session-state recovery, transaction-loss risk during failure. A single Observer is a single point of failure in the FSFO decision chain.

### 1.3 Zasady projektowe / Design principles

- **Zero-downtime target:** RTO ≤ 30 s, RPO = 0 (SYNC transport DC↔DR, MaxAvailability)
- **No application changes for TAC:** replay przez UCP + Transaction Guard; aplikacja nie wie o failoverze
- **Observer HA by design:** zawsze 3 observery w 3 ośrodkach (master na EXT, backupy na DC/DR)
- **Dry-run first:** wszystkie skrypty zmieniające stan mają tryb `-d` (dry-run) lub generują `.dgmgrl` do review przez DBA
- **Konsolidacja narzędzi:** wszystkie skrypty bash wołają istniejący `sqlconn.sh` (z `PATH`) — brak duplikacji logiki TNS/auth
- **PL/EN dokumentacja:** każdy dokument, nagłówek skryptu i alias kolumny dwujęzyczne

### 1.4 Bibliografia wewnętrzna / Internal references

| Plik / File | Rola / Role |
|---|---|
| [README.md](../README.md) | Overview, spis plików, quickstart |
| [PLAN.md](PLAN.md) | Plan 6-fazowy, Weeks 1-13+ |
| [FSFO-GUIDE.md](FSFO-GUIDE.md) | Poradnik FSFO (11 sekcji) |
| [TAC-GUIDE.md](TAC-GUIDE.md) | Poradnik TAC (10 sekcji) |
| [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) | FSFO+TAC integration (8 sekcji) |


---

## 2. Decyzje architektoniczne (ADR) / Architectural Decision Records

### Rejestr ADR / ADR Registry

| ID | Tytuł / Title | Status | Data |
|---|---|---|---|
| ADR-001 | Master Observer na EXT (geograficznie separowany) | accepted | 2026-04-23 |
| ADR-002 | Protection Mode = MAX AVAILABILITY (SYNC+AFFIRM) | accepted | 2026-04-23 |
| ADR-003 | FastStartFailoverThreshold = 30s, LagLimit = 30s | accepted | 2026-04-23 |
| ADR-004 | FastStartFailoverAutoReinstate = TRUE | accepted | 2026-04-23 |
| ADR-005 | TAC z failover_type=TRANSACTION i DYNAMIC session state | accepted | 2026-04-23 |
| ADR-006 | systemd units per site (zamiast crontab/skrypt init.d) | accepted | 2026-04-23 |
| ADR-007 | Oracle Wallet per-site dla Observer credentials | accepted | 2026-04-23 |
| ADR-008 | Skrypty bash wołają `sqlconn.sh` z `PATH` (bez ścieżki) | accepted | 2026-04-23 |

---

### ADR-001: Master Observer na EXT (geograficznie separowany)

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
Observer musi być w stanie wiarygodnie rozstrzygać "split brain" między PRIM (DC) a STBY (DR). Umieszczenie go w jednym z tych dwóch ośrodków powoduje, że awaria tego ośrodka zabiera równocześnie bazę i Observera — FSFO nie ma kto podjąć decyzji. Third-site Observer to rekomendacja MAA.

**Decyzja:**
Master Observer (`obs_ext`) działa w ośrodku EXT (dedykowany host, nie ma bazy DG). Observer obs_dc i obs_dr są backupami w DC i DR, gotowe przejąć rolę mastera poprzez FSFO observer HA.

**Konsekwencje:**
- `+` Żadna pojedyncza awaria ośrodka nie blokuje decyzji o failoverze
- `+` Sieciowe partycje DC↔DR nie powodują "brain split" — EXT widzi obie strony
- `-` Wymaga trzeciej lokalizacji i łącz sieciowych do obu ośrodków (latency ≤ 50 ms preferowane)
- `-` Koszt operacyjny: utrzymanie host'a obserwacyjnego + wallet + systemd unit

**Alternatywy odrzucone:**
- Observer tylko w DC (primary) — odpada przy awarii DC (single point of failure w łańcuchu FSFO)
- Observer w DR — odpada przy "DC izolowany, DR działa, ale Observer nie widzi PRIM"
- Zewnętrzny SaaS (Oracle Cloud Observer) — niedopuszczalne dla bank/fintech on-premise scenarios

---

### ADR-002: Protection Mode = MAX AVAILABILITY (SYNC+AFFIRM)

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
FSFO wymaga natychmiastowej wiedzy, że standby otrzymał wszystkie commity przed failoverem — inaczej RPO > 0. MAX PROTECTION byłoby jeszcze bezpieczniejsze, ale zatrzymuje PRIM gdy STBY nie odpowiada — niedopuszczalne dla aplikacji OLTP.

**Decyzja:**
Używamy **MAX AVAILABILITY** z transportem SYNC + AFFIRM, z Standby Redo Logs (SRL) na STBY. `FastStartFailoverLagLimit = 30s` — gdy apply lag przekroczy 30 s, FSFO nie może failover (by nie stracić danych).

**Konsekwencje:**
- `+` RPO = 0 pod normalnym ruchem (SYNC + AFFIRM)
- `+` Przy problemie z STBY, PRIM przechodzi automatycznie do MAX PERFORMANCE (async) i aplikacja działa
- `-` Wymaga niskiego latency sieci DC↔DR (dodatkowy round-trip przy każdym commit) — akceptowalne dla metro-area

**Alternatywy odrzucone:**
- MAX PERFORMANCE (async) — RPO > 0, dane mogą być utracone
- MAX PROTECTION — zatrzymuje produkcję przy awarii STBY; niedopuszczalne dla SLA 24/7

---

### ADR-003: FastStartFailoverThreshold = 30s, LagLimit = 30s

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
Threshold określa jak długo Observer czeka po utracie heartbeat, zanim zainicjuje FSFO. Zbyt krótki = false positives (failover przy flappingach sieci), zbyt długi = dłuższe RTO. LagLimit określa max apply lag, przy którym FSFO jest dopuszczony.

**Decyzja:**
`FastStartFailoverThreshold = 30` (s), `FastStartFailoverLagLimit = 30` (s). Razem z reakcją FAN/UCP daje RTO ~30 s — 45 s end-to-end.

**Konsekwencje:**
- `+` Odporne na krótkotrwałe flappingi (< 30 s)
- `+` Apply lag ≤ 30 s = RPO akceptowalny dla fintech
- `-` RTO ~30 s — niewystarczające dla ultra-low-latency HFT; akceptowalne dla bankowości retail/korporacyjnej

**Alternatywy odrzucone:**
- Threshold = 10 s — zbyt dużo false positives pokazały benchmarki MAA 2024
- Threshold = 60 s — podwaja RTO; nieakceptowalne dla SLA 99.995%

---

### ADR-004: FastStartFailoverAutoReinstate = TRUE

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
Po failoverze "stary primary" musi być przywrócony jako nowy standby. Można robić to ręcznie (DBA `REINSTATE DATABASE`) lub automatycznie.

**Decyzja:**
`AutoReinstate = TRUE`. Gdy stary primary znów jest dostępny, Broker automatycznie robi reinstate (wymaga Flashback Database ON).

**Konsekwencje:**
- `+` Self-healing po transient failures (sieć, reboot)
- `+` Mniejsze obciążenie on-call DBA
- `-` Wymaga `FLASHBACK ON` + odpowiedniej FRA (Fast Recovery Area)
- `-` Może reinstate'ować w nieoczekiwanym momencie — trzeba monitorować alert log

**Alternatywy odrzucone:**
- AutoReinstate = FALSE — każda awaria wymaga ręcznej interwencji DBA; zwiększa MTTR

---

### ADR-005: TAC z failover_type=TRANSACTION i DYNAMIC session state

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
TAC ma trzy ustawienia istotne dla replay: `failover_type`, `session_state_consistency`, `commit_outcome`. Domyślne wartości (`SELECT`, `STATIC`) nie wspierają transaction replay.

**Decyzja:**
```
failover_type             = TRANSACTION
session_state_consistency = DYNAMIC
commit_outcome            = TRUE
retention_timeout         = 86400 (24h)
replay_initiation_timeout = 900
drain_timeout             = 300
```

**Konsekwencje:**
- `+` Pełny replay in-flight transakcji po failoverze
- `+` Zachowanie stanu sesji (NLS, PL/SQL package vars, temp tables)
- `-` Aplikacja musi używać UCP (HikariCP nie wspiera TAC w pełni)
- `-` Retencja outcomes 24h zużywa tabelę `SYS.LTXID_TRANS$` — monitoring rozmiaru

**Alternatywy odrzucone:**
- `failover_type=SELECT` (TAF stary) — brak replay DML
- `session_state_consistency=STATIC` — traci zmienne PL/SQL w replay

---

### ADR-006: systemd units per site (zamiast crontab/init.d)

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
Observer musi być uruchomiony jako long-running background process na każdym z 3 hostów (DC, DR, EXT). Wymagania: automatyczny restart po awarii, zależność od sieci, logging do journald, control przez `systemctl`.

**Decyzja:**
Per-site systemd unit file z `Restart=on-failure`, `After=network-online.target`, user `oracle`, wallet path specyficzny dla site'u. Pliki w katalogu [systemd/](../systemd/), deployment w [FSFO-GUIDE § 6.7](FSFO-GUIDE.md#67-observer-ha---systemd-units).

**Konsekwencje:**
- `+` Standardowy OS tooling (`systemctl status/start/stop/restart`)
- `+` Automatyczny restart po crashu observera
- `+` Integracja z journald (`journalctl -u dgmgrl-observer-ext`)
- `-` Wymaga systemd (nie działa na starych RHEL 6) — wymagane RHEL/OL 7+

**Alternatywy odrzucone:**
- Crontab `@reboot dgmgrl ... &` — brak auto-restart po crashu, brak logowania
- init.d SysV — deprecated w RHEL 7+
- supervisord — dodatkowa zależność

---

### ADR-007: Oracle Wallet per-site dla Observer credentials

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
Observer łączy się do PRIM i STBY jako `sys` (DBA) — hasło nie może być w pliku systemd ani w skrypcie bash. Oracle Wallet + TNS alias to rekomendowana metoda.

**Decyzja:**
Każdy z 3 observerów ma własny Oracle Wallet w `/etc/oracle/wallet/observer-{hh,oe,ext}`, zawierający credentials dla `@PRIM_ADMIN` i `@STBY_ADMIN`. Dostęp: `chmod 600`, owner `oracle:oinstall`. Wallet **nie trafia do repozytorium**.

**Konsekwencje:**
- `+` Zero plaintext paroli
- `+` Rotacja hasła przez `mkstore -modifyCredential`, bez restartu observera
- `+` Kompatybilne z `dgmgrl /@PRIM_ADMIN` (bez hasła w CLI)
- `-` Odrębne wallety na 3 hostach — deployment procedure w [FSFO-GUIDE § 6.8](FSFO-GUIDE.md#68-observer-wallet-per-site)

**Alternatywy odrzucone:**
- Plaintext hasła w systemd unit — narusza globalne zasady bezpieczeństwa (`../CLAUDE.md`)
- Single shared wallet na NFS — single point of failure + kompromituje wszystkie observery naraz
- OS-level keyring — nie integruje się z `dgmgrl`

---

### ADR-008: Skrypty bash wołają `sqlconn.sh` z `PATH` (bez ścieżki)

- **Status:** accepted
- **Data:** 2026-04-23
- **Autor:** KCB Kris

**Kontekst:**
Istnieje już dojrzały `sqlconn.sh` (z [../20260130-sqlconn/](../../20260130-sqlconn/)) obsługujący HA, failover A/B, tech/imienne konta, dry-run, C## fallback. Duplikowanie tej logiki w skryptach FSFO byłoby niezdrową redundancją.

**Decyzja:**
Skrypty [bash/fsfo_setup.sh](../bash/fsfo_setup.sh), [bash/fsfo_monitor.sh](../bash/fsfo_monitor.sh), [bash/tac_deploy.sh](../bash/tac_deploy.sh), [bash/validate_all.sh](../bash/validate_all.sh) wołają `sqlconn.sh` **bezpośrednio** — bez ścieżki (jest w `PATH` na docelowych maszynach). Nie importujemy go `source`, wywołujemy jako subprocess.

**Konsekwencje:**
- `+` Brak duplikacji logiki TNS / auth / HA
- `+` Spójne logowanie (ten sam format logów, ten sam wallet/credential store)
- `+` Aktualizacje `sqlconn.sh` automatycznie propagują się do FSFO toolkit
- `-` Portability: na hoście bez `sqlconn.sh` skrypty nie zadziałają — wymagany pre-req w README i w `usage()`

**Alternatywy odrzucone:**
- Standalone sqlplus w każdym skrypcie — duplikacja, rozjazd konfiguracji
- Dowiązanie symboliczne do `sqlconn.sh` w katalogu projektu — utrudnia aktualizacje
- Skopiowanie `sqlconn.sh` — stary kod utrzymuje się w dwóch miejscach

---

## 3. Kompatybilność wersji DB / DB Version Compatibility

### 3.1 Wspierane wersje / Supported versions

| Wersja / Version | Status | Uwagi / Notes |
|---|---|---|
| Oracle 12c | not supported | FSFO 12c wspierany, ale TAC (19c+) — nie |
| Oracle 19c | **primary target** | FSFO + TAC w pełni funkcjonalne, główny target projektu |
| Oracle 21c | compatible | Działa bez zmian; 21c dodaje tylko drobne tuning knoby |
| Oracle 23ai | compatible with caveats | TAC nadal działa; nowe featury (True Cache) nie używane |
| Oracle 26ai | compatible | On-premise, AI Vector Search nie dotyka FSFO/TAC |

### 3.2 Architektura / Architecture

| Aspekt / Aspect | Wartość / Value |
|---|---|
| CDB / Non-CDB | CDB wymagany dla 19c+ (Non-CDB deprecated) |
| RAC | **wymagane** — PRIM i STBY są 2-node RAC |
| Data Guard | **wymagane** — Physical Standby, DG Broker |
| Multitenant (PDB) | wspierane — TAC per-service per-PDB |
| Exadata | wspierane — optymalizacja redo apply jeszcze szybsza |

### 3.3 Różnice widoków systemowych / System view differences

| Widok / View | 19c | 21c | 23ai | Uwagi |
|---|---|---|---|---|
| `V$DATAGUARD_STATS` | ✓ | ✓ | ✓ | Core do FSFO monitoring |
| `GV$REPLAY_STAT_SUMMARY` | ✓ | ✓ | ✓ | Core do TAC monitoring |
| `DBA_DG_BROKER_CONFIG_PROPERTIES` | ✓ | ✓ | ✓ | Broker props z wersji 19c |
| `DBMS_APP_CONT` | ✓ | ✓ | ✓ | Transaction Guard package |
| `V$FS_FAILOVER_STATS` | ✓ | ✓ | ✓ | FSFO statistics |

### 3.4 Strategia handlowania różnic / Strategy for handling differences

- **Conditional compilation** (`$IF DBMS_DB_VERSION.VERSION >= 19 $THEN`): używane w `validate_environment.sql` dla graceful degradation na 12c (readiness check zwraca FAIL z explicit message)
- **Osobne pliki per wersja:** nie — utrzymujemy jeden zestaw targetujący 19c+
- **Dynamic SQL:** tylko w generatorze dgmgrl (`fsfo_configure_broker.sql`) dla parametryzacji nazw baz

---

## 4. Konwencje nazewnictwa / Naming Conventions

### 4.1 Pliki / Files

| Typ / Type | Konwencja / Convention | Przykład / Example |
|---|---|---|
| SQL readiness | `fsfo_*_readiness.sql` / `validate_*.sql` | `fsfo_check_readiness.sql` |
| SQL status | `fsfo_*_status.sql` / `*_monitor.sql` | `fsfo_broker_status.sql` |
| SQL generator | `fsfo_configure_*.sql` | `fsfo_configure_broker.sql` |
| SQL service | `tac_configure_service_*.sql` | `tac_configure_service_rac.sql` |
| Bash orchestrator | `{feature}_setup.sh` | `fsfo_setup.sh` |
| Bash monitor | `{feature}_monitor.sh` | `fsfo_monitor.sh` |
| Bash multi-DB | `validate_all.sh` | — |
| systemd unit | `dgmgrl-observer-{site}.service` | `dgmgrl-observer-ext.service` |
| Output log | `./logs/fsfo_{YYYYMMDD_HHMMSS}.log` | `./logs/fsfo_20260420_143022.log` |
| Output raport | `./reports/{db}_fsfo_{YYYYMMDD_HHMM}.txt` | `./reports/PRIM_fsfo_20260420_1430.txt` |

### 4.2 Obiekty DB / DB objects

| Obiekt | Konwencja | Przykład |
|---|---|---|
| Bazy DG | 4 znaki, wielkie litery | `PRIM`, `STBY` |
| Observer name | `obs_{site_lower}` | `obs_dc`, `obs_dr`, `obs_ext` |
| TAC service | `{APP}_TAC` (RW), `{APP}_RO` (standby read-only) | `MYAPP_TAC`, `MYAPP_RO` |
| TNS alias primary | `{DB}_ADMIN` (z wallet) | `PRIM_ADMIN` |
| Static listener | `{DB}_DGMGRL` | `PRIM_DGMGRL`, `STBY_DGMGRL` |

### 4.3 Zmienne SQL*Plus / SQL*Plus variables

- Parametryzacja przez `ACCEPT ... PROMPT ... DEFAULT ...` (interaktywnie)
- Lub `DEFINE` na początku skryptu (do wywołań nieinteraktywnych)
- **Nigdy** bash-style `${var}` w `.sql`
- Kolumny w wyniku: aliasy po **polsku** (zgodnie z `../_oracle_/CLAUDE.md`)

### 4.4 Sanityzacja hostów

| Źródło | Reguła | Przykład |
|---|---|---|
| `ora-PRIM-a` | bez zmian — używane w `sqlconn.sh` | — |
| `obs-ext.corp.local` | `.` → `_` w plikach output | `obs-ext_corp_local.log` |

---

## 5. Bezpieczeństwo / Security

### 5.1 Zarządzanie poświadczeniami / Credential management

- **Observer:** Oracle Wallet per-site (ADR-007)
- **Monitoring DBA:** SQLcl JCEKS credential store (zgodnie z konwencją workspace `../_oracle_/CLAUDE.md`)
- **Application TAC user:** Oracle Wallet lub secrets manager (AWS/Azure/HashiCorp)

**Zasady:**
- Poświadczenia **nigdy** nie trafiają do repozytorium (FSFO wallets, JCEKS, `.env` w `.gitignore`)
- Pliki `.db_secrets`, `.env`: `chmod 600`
- `tnsnames.ora` **bez haseł** — hasło wyłącznie w wallet/JCEKS
- Observer łączy się jako `sys` — używać wyłącznie przez wallet z TNS alias `PRIM_ADMIN` / `STBY_ADMIN`

### 5.2 Uprawnienia minimalne / Least privilege

| Rola / Role | Uprawnienia | Użycie |
|---|---|---|
| `ops_monitor` (tech) | SELECT_CATALOG_ROLE | Skrypty read-only (`fsfo_broker_status.sql`, `fsfo_monitor.sql`) |
| `C##dba_kris` (imienny) | SYSDBA | Skrypty zmieniające stan (`fsfo_configure_broker.sql`) |
| `observer` (wallet) | SYSDG | Observer process — najmniejszy przywilej dla FSFO decision-making |
| `appuser_tac` (aplikacja) | CREATE SESSION + app role | Produkcyjny pool UCP |

**SYSDG vs SYSDBA:** Observer powinien używać SYSDG (dedykowana rola dla DG, wprowadzona w 12.2) zamiast SYSDBA — mniejsza powierzchnia ataku.

### 5.3 PDB / CDB safety

- FSFO działa na poziomie CDB (cała baza failover'uje atomowo)
- TAC services konfigurowane per-PDB (role-based: `service -role PRIMARY` + `service -role PHYSICAL_STANDBY`)
- Dla wielo-PDB środowisk — iterować po `DBA_PDBS` przy konfigracji TAC

### 5.4 Licencje / Licensing

**Kluczowe pakiety licencyjne:**
- **Enterprise Edition (EE)** — wymagany (Data Guard, FSFO, TAC wbudowane)
- **Active Data Guard (opcja)** — opcjonalny; wymagany dla read-only standby z real-time apply lub fast incremental backups na standby
- **Diagnostic Pack + Tuning Pack** — dla `V$ACTIVE_SESSION_HISTORY`, AWR, SQL Tuning Advisor (użyte w `fsfo_monitor.sql` sekcja 7)
- **Real Application Clusters (RAC)** — dla 2-node RAC w DC i DR

**Projekt używa:** EE + RAC + Diagnostic Pack + Tuning Pack. ADG **nie wymagane** w core scenariuszu (tylko jeśli chcemy read-only offload na STBY — wtedy ADR-009 do dodania).

### 5.5 Sieć / Network

- **Porty wymagane:** 1521 (SQL*Net), 6200 (ONS cross-site dla FAN), 1522 (DGMGRL static listener)
- **Firewall matrix** w [TAC-GUIDE § 6.4](TAC-GUIDE.md#64-firewall-rules--reguły-firewalla)
- **Cross-site ONS:** PRIM ONS ↔ STBY ONS muszą się widzieć wzajemnie po switchover
- **Observer → PRIM/STBY:** port 1521 (SQL*Net dla dgmgrl heartbeats)

---

## 6. Strategia testów / Testing Strategy

### 6.1 Dry-run pattern

Zgodnie z globalnym `../CLAUDE.md`:

- **SQL (zmiana stanu):** 3-krokowy pattern
  ```
  -- KROK 1 / STEP 1: Podgląd (SELECT — bezpieczny)
  -- KROK 2 / STEP 2: Faktyczna zmiana
  -- KROK 3 / STEP 3: Weryfikacja
  ```
- **Bash:** flaga `-d` (dry-run) tylko drukuje komendy bez wykonania
- **Generator dgmgrl:** `fsfo_configure_broker.sql` emituje plik `.dgmgrl` do review, nie wykonuje go

### 6.2 Smoke test

```bash
# 1. Syntax check bash
for f in bash/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done

# 2. Syntax check SQL (dry parse w sqlcl)
for f in sql/*.sql; do echo "@@$f" | sqlcl -nolog -S | grep -i 'error' && echo "FAIL: $f"; done

# 3. Dry-run orchestrator
bash/fsfo_setup.sh -s PRIM -d

# 4. Monitor alert mode (offline — bez bazy zwraca exit 2)
bash/fsfo_monitor.sh -s PRIM -a
```

### 6.3 Matryca testów / Test matrix

| Scenariusz | 19c | 21c | 23ai | Single | RAC | DG |
|---|---|---|---|---|---|---|
| Smoke test (sql syntax + bash -n) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Readiness check | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Broker configure (dry-run) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Planowany switchover | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Symulowany crash PRIM | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Observer HA failover (master ↓) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| TAC replay test (SHUTDOWN ABORT node 1) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Reinstate (AutoReinstate) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Rolling patch z FSFO aktywnym | ✓ | ✓ | ✓ | — | ✓ | ✓ |

### 6.4 Rollback plan

- **Broker config error:** `REMOVE CONFIGURATION [PRESERVE DESTINATIONS]` — przywraca stan sprzed włączenia brokera; standby zostaje skonfigurowany ręcznie przez DBA
- **FSFO error:** `DISABLE FAST_START FAILOVER` — Observer przestaje decydować; switchover tylko manualny
- **TAC error (service):** `srvctl modify service` z `-failovertype NONE` — wyłącza TAC, aplikacja działa bez replay (ale bez zero-downtime)
- **Observer error:** `systemctl stop dgmgrl-observer-ext` + ręczne `DISABLE FAST_START FAILOVER` jeśli wszystkie 3 observery padły

---

## 7. Progi alertów / Alert Thresholds

### 7.1 Broker status

| Wartość | Pill | Uzasadnienie |
|---|---|---|
| `SUCCESS` | ✅ OK | Broker healthy, wszystkie DB w sync |
| `WARNING` | 🟡 WARN | Apply lag > 0 ale < 30s — monitoring, nie wymagane działanie natychmiast |
| `ORA-16819`, `ORA-16820`, `ORA-16825` | 🔴 CRIT | Błędy konfiguracji; [FSFO-GUIDE § 10](FSFO-GUIDE.md#10-troubleshooting) |

### 7.2 FSFO status

| Wartość | Pill | Uzasadnienie |
|---|---|---|
| `ENABLED` + Observer connected | ✅ OK | FSFO ready; auto-failover aktywny |
| `ENABLED` + Observer disconnected > 60s | 🟡 WARN | Observer HA powinien przejąć; sprawdź alert log |
| `DISABLED` | 🔴 CRIT | Brak auto-failover — tylko manual switchover dostępny |

### 7.3 Apply lag (FastStartFailoverLagLimit = 30s)

| Wartość | Pill | Uzasadnienie |
|---|---|---|
| `lag < 5s` | ✅ OK | Normalne obciążenie |
| `5s ≤ lag < 30s` | 🟡 WARN | Standby behind; monitoring; FSFO nadal dostępny |
| `lag ≥ 30s` | 🔴 CRIT | FSFO **niedostępny** (LagLimit exceeded) — zero-downtime nie zagwarantowane |

### 7.4 TAC replay success rate

| Wartość | Pill | Uzasadnienie |
|---|---|---|
| `success_pct ≥ 95%` | ✅ OK | Healthy — mutable objects i session state poprawnie zarządzane |
| `80% ≤ success_pct < 95%` | 🟡 WARN | Niektóre txns nie replay — sprawdź `GV$REPLAY_STAT_SUMMARY.requests_failed` |
| `success_pct < 80%` | 🔴 CRIT | Application design issue — prawdopodobnie non-replayable operations (DDL, external calls) |

### 7.5 Observer heartbeat

| Wartość | Pill | Uzasadnienie |
|---|---|---|
| `last_ping < 10s` | ✅ OK | Observer alive |
| `10s ≤ last_ping < 60s` | 🟡 WARN | Network latency lub GC pause |
| `last_ping ≥ 60s` | 🔴 CRIT | Observer prawdopodobnie padł; backup powinien przejąć |

---

## 8. Graceful degradation

### 8.1 Macierz dostępności / Availability matrix

| Komponent | Wymagany? | Bez niego |
|---|---|---|
| Enterprise Edition | **TAK** | FSFO/TAC nie dostępne — projekt nie działa |
| RAC | TAK (per założenie) | FSFO działa na Single Instance, ale projekt targetuje RAC 2-node |
| Data Guard + SRL | **TAK** | FSFO nie ma co failoverować |
| DG Broker | **TAK** | Bez brokera tylko ręczny switchover |
| `FLASHBACK ON` | TAK (dla AutoReinstate) | AutoReinstate=FALSE; ręczny reinstate wymagany po każdym failoverze |
| `FORCE_LOGGING` | **TAK** | Standby może rozjechać się z primary |
| Diagnostic Pack | NIE | `fsfo_monitor.sql` sekcja 7 (ASH/AWR) — graceful degradation na V$SESSION |
| Tuning Pack | NIE | Brak rekomendacji SQL; reszta działa |
| Active Data Guard (opcja) | NIE | Read-only standby niedostępny; FSFO nadal działa |
| UCP na kliencie | TAK (dla TAC) | Bez UCP — brak replay; aplikacja widzi ORA-03113 |
| FAN/ONS | TAK (dla TAC) | UCP nie dostaje eventów → brak fast connection failover |

### 8.2 Fallback patterns

**Bez Diagnostic Pack (licencji ASH/AWR):**

```sql
-- Standardowo (wymagane Diagnostic Pack):
SELECT COUNT(*) FROM V$ACTIVE_SESSION_HISTORY
WHERE sample_time > SYSDATE - 5/1440;

-- Fallback (bez licencji):
SELECT COUNT(*) FROM V$SESSION
WHERE status = 'ACTIVE' AND type = 'USER';
```

W `fsfo_monitor.sql` — sekcja 7 wrapped w `$IF` conditional:

```sql
$IF (SELECT value FROM v$option WHERE parameter = 'Diagnostic Pack') = 'TRUE' $THEN
   -- Use ASH
$ELSIF
   -- Use V$SESSION sampling
$END
```

**Bez Observera (awaria wszystkich 3):**
- FSFO pozostaje `ENABLED` ale nie ma kto podjąć decyzji
- Manual failover przez DBA: [INTEGRATION-GUIDE § 6.2](INTEGRATION-GUIDE.md#62-emergency-failover-manual)

**Bez FAN/ONS (cross-site ONS zablokowane przez firewall):**
- UCP nie dostaje eventów DOWN/UP
- Aplikacja widzi ORA-03113; JDBC re-connect po `(FAILOVER=ON)` w TNS
- RTO wydłuża się z ~30s do minuty (TCP timeout)

---

## 9. Przyszłe rozszerzenia / Future Extensions

### 9.1 Zaplanowane / Planned (backlog)

| Feature | Złożoność | Opis |
|---|---|---|
| ADG (Active Data Guard) integration | średnia | Offload read-only do STBY dla raportów/analityki |
| Grafana dashboard | średnia | Wizualizacja `V$DATAGUARD_STATS` + `GV$REPLAY_STAT_SUMMARY` |
| Automated failover drill | wysoka | Kwartalny test failover + raport do audytu |
| Multi-standby (cascade) | wysoka | Dodatkowy standby w trzecim DC dla DR regionalnego |
| Oracle 23ai True Cache integration | wysoka | Read-only cache warstwa z własnym failover'em |

### 9.2 Świadomie pominięte / Deliberately skipped

| Feature | Powód pominięcia |
|---|---|
| MAX PROTECTION mode | Zatrzymuje produkcję gdy STBY nie odpowiada; niedopuszczalne dla SLA 24/7 |
| Async transport (MAX PERFORMANCE) | RPO > 0; nie spełnia wymagań fintech |
| HikariCP zamiast UCP | HikariCP nie wspiera TAC w pełni (brak LTXID outcome query) |
| Oracle Cloud Observer | On-premise only — security compliance |
| Zero-data-loss (ZDLRA) | Osobny projekt, nie scope FSFO+TAC |
| Observer bez systemd (crontab) | Brak auto-restart po crashu; odrzucone w ADR-006 |

---

## 10. Appendix / Appendix

### 10.1 Bibliografia zewnętrzna / External references

- [Oracle Database 19c Data Guard Concepts and Administration](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/) — referencja DG
- [Oracle Database 19c Data Guard Broker](https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/) — referencja Broker + FSFO
- [Oracle MAA Best Practices](https://www.oracle.com/database/technologies/high-availability/maa.html) — architektura referencyjna
- [Transparent Application Continuity Technical Brief](https://www.oracle.com/a/tech/docs/tac-technical-brief.pdf) — TAC whitepaper
- [Oracle Note 2064122.1 (MOS)](https://support.oracle.com) — FSFO Observer troubleshooting
- [UCP Developer's Guide 19c](https://docs.oracle.com/en/database/oracle/oracle-database/19/jjucp/) — pool configuration

### 10.2 Słownik terminów / Glossary

| Termin / Term | Definicja / Definition |
|---|---|
| **FSFO** | Fast-Start Failover — automatyczne przełączanie primary→standby przez Observer |
| **TAC** | Transparent Application Continuity — replay in-flight transakcji w 19c+ (następca AC) |
| **AC** | Application Continuity — starsza wersja replay (12c), wymagała zmian w aplikacji |
| **Observer** | Proces `dgmgrl` monitorujący PRIM/STBY, inicjujący FSFO |
| **Broker** | Data Guard Broker — framework zarządzania DG przez `dgmgrl` / `DBMS_DG` |
| **dgmgrl** | Data Guard Manager CLI — komenda do zarządzania brokerem |
| **MAA** | Maximum Availability Architecture — Oracle reference architecture dla HA |
| **SRL** | Standby Redo Logs — wymagane dla real-time apply i FSFO |
| **FAN** | Fast Application Notification — system eventów publikujących zmiany stanu |
| **ONS** | Oracle Notification Service — transport dla FAN (port 6200) |
| **UCP** | Universal Connection Pool — Oracle Java connection pool wspierający TAC |
| **TG** | Transaction Guard — mechanizm LTXID do bezpiecznego replay |
| **LTXID** | Logical Transaction ID — identyfikator transakcji dla TG |
| **SYSDG** | System privilege dla Data Guard operations (12.2+) |
| **ADG** | Active Data Guard — opcja licencyjna dla read-only standby z real-time apply |
| **RTO** | Recovery Time Objective — max dopuszczalny czas odtworzenia |
| **RPO** | Recovery Point Objective — max dopuszczalna utrata danych |

---

## 👤 Autor / Author

- **KCB Kris** — autor i maintainer projektu
- Data: 2026-04-23
- Wersja: 1.0
