> [🇬🇧 English](./FAILOVER-WALKTHROUGH.md) | 🇵🇱 Polski

# 🎬 FAILOVER-WALKTHROUGH.md — Krok po kroku przez sequence diagram

![Oracle 19c](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![RTO](https://img.shields.io/badge/RTO-~45s-blue)
![Audience](https://img.shields.io/badge/audience-DBA%20%7C%20DevOps-green)

> Edukacyjne wyjaśnienie sequence diagramu z [INTEGRATION-GUIDE.md § 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction) — co dokładnie dzieje się podczas automatycznego failoveru FSFO + TAC, aktor po aktorze, sekunda po sekundzie.
>
> Educational walkthrough of the sequence diagram from [INTEGRATION-GUIDE.md § 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction) — what exactly happens during automatic FSFO + TAC failover, actor by actor, second by second.

**Autor / Author:** KCB Kris | **Data / Date:** 2026-04-23 | **Wersja / Version:** 1.0
**Related:** [README.md](../README.md) • [FSFO-GUIDE.md](FSFO-GUIDE.md) • [TAC-GUIDE.md](TAC-GUIDE.md) • [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) • [PLAN.md](PLAN.md) • [DESIGN.md](DESIGN.md)

---

## 📋 Spis treści

1. [Kontekst](#1-kontekst)
2. [6 aktorów na diagramie](#2-6-aktorów-na-diagramie)
3. [Fazy failoveru](#3-fazy-failoveru)
   - [Faza 1: Detekcja awarii (0s → 30s)](#-faza-1-detekcja-awarii-0s--30s)
   - [Faza 2: Przełączenie DB (30s → 35s)](#-faza-2-przełączenie-db-30s--35s)
   - [Faza 3: Powiadomienie aplikacji (35s → 40s)](#-faza-3-powiadomienie-aplikacji-35s--40s)
   - [Faza 4: TAC replay transakcji (40s → 45s)](#-faza-4-tac-replay-transakcji-40s--45s--tu-się-dzieje-magia)
   - [Faza 5: Reinstate w tle](#-faza-5-reinstate-w-tle-później)
4. [Kluczowe mechanizmy w jednym zdaniu](#4-kluczowe-mechanizmy-w-jednym-zdaniu)
5. [Co by się stało bez tego wszystkiego?](#5-co-by-się-stało-bez-tego-wszystkiego)
6. [Wnioski operacyjne](#6-wnioski-operacyjne)
7. [Drugi widok: Timing Breakdown (Gantt)](#7-drugi-widok-timing-breakdown-gantt)
   - [Kluczowa obserwacja — jeden pasek dominuje](#-kluczowa-obserwacja--jeden-pasek-dominuje-całość)
   - [Interpretacja każdego toru](#-interpretacja-każdego-toru)
   - [3 wnioski architektoniczne](#-3-wnioski-architektoniczne)
   - [Porównanie: Sequence vs Gantt](#-porównanie-sequence-diagram-vs-gantt-chart)

---

## 1. Kontekst

Diagram [INTEGRATION-GUIDE.md § 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction) to **sequence diagram** pokazujący **kompletny przebieg automatycznego failoveru** z perspektywy wszystkich komponentów — krok po kroku, z osią czasu od `t=0s` do `t=45s` + reinstate później.

**Cel tego walkthrough:**
- Nauczyć on-call DBA i DevOps co dzieje się "pod maską" w każdej sekundzie failoveru
- Pokazać jak komponenty (FSFO, FAN, TAC, Transaction Guard, UCP) współpracują
- Ustalić oczekiwania: **użytkownik końcowy nie powinien zobaczyć błędu**

**Założenia architektoniczne:**
- 2-node RAC PRIM w ośrodku DC
- 2-node RAC STBY w ośrodku DR
- Master Observer `obs_ext` w ośrodku EXT
- `FastStartFailoverThreshold = 30s`, `FastStartFailoverAutoReinstate = TRUE`
- TAC service `MYAPP_TAC` z `failover_type=TRANSACTION`, `commit_outcome=TRUE`, `session_state_consistency=DYNAMIC`

---

## 2. 6 aktorów na diagramie

Każda pionowa kolumna to jeden aktor systemowy:

| Kolumna | Rola w systemie | Gdzie fizycznie |
|---------|-----------------|-----------------|
| **App (UCP)** | Twoja aplikacja z Universal Connection Pool — to ona ma zobaczyć failover | App server (np. Kubernetes, VM) |
| **ONS (FAN)** | Oracle Notification Service — magistrala eventów DOWN/UP między bazą a klientem | Proces na każdym node RAC (port 6200) |
| **Primary (DC)** | Stary primary w ośrodku DC (ten który pada) | 2-node RAC w DC |
| **Observer Master (EXT)** | Observer na trzecim ośrodku — "sędzia" który decyduje kiedy robić failover | Dedykowany host w EXT (`dgmgrl` + systemd) |
| **DG Broker** | Data Guard Broker — wykonawca decyzji (w praktyce żyje na obu bazach) | Proces w każdym DB instance (PRIM + STBY) |
| **Standby (DR)** | Standby w ośrodku DR (ten który przejmie rolę primary) | 2-node RAC w DR |

---

## 3. Fazy failoveru

### 🔴 Faza 1: Detekcja awarii (0s → 30s)

1. **`t=0s`: Primary crashes** — primary pada (np. awaria sprzętu DC, network outage, rack-level failure)
2. **heartbeat LOST** — Observer przestaje dostawać heartbeat od Primary. **Nie reaguje natychmiast** (krótkotrwały flapping sieci to NIE awaria)
3. **Timer running (threshold=30s)** — Observer odlicza 30 sekund (`FastStartFailoverThreshold`)
4. **`t=30s`: Threshold exceeded** — po 30 s ciągłej ciszy Observer uznaje: "Primary naprawdę padł"

> **Dlaczego 30 s?** To kompromis między false positives (flapping sieci) a RTO. Ustawiane w [DESIGN.md ADR-003](DESIGN.md#adr-003-faststartfailoverthreshold--30s-laglimit--30s). Benchmarki MAA 2024 wykazały że krótsze thresholds (np. 10s) powodują zbyt dużo false-positive failoverów na flappingu sieciowym; dłuższe (60s) dwukrotnie zwiększają RTO.

---

### ⚡ Faza 2: Przełączenie DB (30s → 35s)

5. **Initiate FSFO — FAILOVER TO STBY** — Observer wydaje polecenie Brokerowi (`FAILOVER TO STBY`)
6. **Promote to PRIMARY** — Broker mówi Standby'owi: "Ty teraz jesteś primary"
7. **Role changed** — Standby potwierdza zmianę roli (DG Broker markuje `database_role=PRIMARY` w controlfile STBY)
8. **`t=35s`: STBY is new PRIMARY** — w 5 sekund baza gotowa przyjmować traffic

**Co dzieje się "pod maską":**
- Standby otwiera redo logs do zapisu
- Rola w `V$DATABASE.database_role` zmienia się z `PHYSICAL STANDBY` na `PRIMARY`
- Role-based services z `-role PRIMARY` (MYAPP_TAC) automatycznie startują
- Role-based services z `-role PHYSICAL_STANDBY` (MYAPP_RO) są zatrzymywane

---

### 📡 Faza 3: Powiadomienie aplikacji (35s → 40s)

9. **Publish FAN events (DOWN primary, UP new primary)** — nowy Primary (STBY/DR) publikuje eventy do ONS
10. **FAN DOWN: PRIM** — ONS pushuje do aplikacji: "Stary primary nie żyje"
11. **FAN UP: STBY (new PRIMARY)** — "Jest nowy primary, łącz się tam"
12. **Invalidate old connections** — pętla na App (*samowywołanie*) — UCP wywala wszystkie połączenia do martwej bazy (bez czekania na TCP timeout ~60s!)
13. **Open new connections to new primary (via TNS 2nd ADDRESS_LIST)** — UCP używa drugiego `ADDRESS_LIST` w TNS (DR scan) żeby stworzyć nowe połączenia

**Kluczowa rola cross-site ONS:**
Bez cross-site ONS (DC↔DR, port 6200) UCP **nie dostanie** FAN eventów z nowego primary. Musiałby czekać na TCP timeout (~60s) żeby zauważyć że stary primary nie żyje. To by zwiększyło RTO z ~45s do ~90+s.

**TNS konfiguracja (kluczowa!):**
```
MYAPP_TAC =
  (DESCRIPTION =
    (FAILOVER = ON)
    (ADDRESS_LIST =
      (ADDRESS = (HOST = scan-dc.corp.local)(PORT = 1521))
    )
    (ADDRESS_LIST =
      (ADDRESS = (HOST = scan-dr.corp.local)(PORT = 1521))   ← ta linia ratuje
    )
    (CONNECT_DATA = (SERVICE_NAME = MYAPP_TAC))
  )
```

---

### 🔁 Faza 4: TAC replay transakcji (40s → 45s) — **tu się dzieje magia**

14. **`t=40s`: TAC replay** — aplikacja miała w locie transakcje (np. `UPDATE accounts SET balance=... COMMIT`) — **nie wiadomo czy commit zdążył przejść przed awarią**
15. **Query LTXID outcome (uncommitted txns)** — aplikacja pyta nowego primary: "Czy moja transakcja z LTXID=xyz została zatwierdzona?"
    - **LTXID** = Logical Transaction ID — unikalny ID dla każdej transakcji, zapisany dzięki `commit_outcome=TRUE` na service
    - Zapytanie wysyłane przez `DBMS_APP_CONT.GET_LTXID_OUTCOME(ltxid)`
16. **UNCOMMITTED** — Transaction Guard odpowiada: "Ta transakcja NIE została zatwierdzona, bezpiecznie replay"
    - Jeśli odpowiedź byłaby `COMMITTED`, TAC zwraca aplikacji wynik bez replay (transakcja zdążyła przejść przed awarią)
17. **Replay transactions (UPDATE, INSERT, COMMIT)** — aplikacja automatycznie, **bez żadnego kodu** po stronie developera, odtwarza wszystkie DML od ostatniego `COMMIT`
    - Session state (NLS, PL/SQL package vars, temp tables) jest zachowany dzięki `session_state_consistency=DYNAMIC`
    - Mutable objects (`SYSDATE`, sequences, `SYS_GUID()`) są "zamrożone" — mają te same wartości co przy oryginalnym wykonaniu
18. **Replay OK** — sukces
19. **Response to end-user (no error seen)** — i teraz **kluczowy moment**: użytkownik końcowy dostaje normalną odpowiedź, jakby nic się nie stało

**Dlaczego nie zobaczy błędu?**
- Bez TAC: aplikacja łapie `SQLException` (ORA-03113 lub ORA-25408) → musi ręcznie decydować co robić → zwykle zwraca użytkownikowi "Please try again"
- Z TAC: sterownik JDBC z UCP sam przechwytuje błąd, sprawdza LTXID, odtwarza transakcję — aplikacja dostaje wynik tak jakby nic się nie stało. **Nawet jeśli dzwoni `conn.executeUpdate()` w środku awarii**, metoda zwraca normalnie.

---

### ✅ `t=45s`: Total RTO

Po **45 sekundach** end-user widzi tylko chwilowe spowolnienie (jakby kliknął w aplikację i czekał sekundę dłużej). Brak błędu, brak "proszę spróbuj ponownie", brak utraconej transakcji.

**Breakdown RTO (zgodnie z [INTEGRATION-GUIDE § 2.3](INTEGRATION-GUIDE.md#23-impact-on-rto--rpo)):**

| Metryka | Wartość | Komponent |
|---------|---------|-----------|
| RPO | 0 | SYNC+AFFIRM transport |
| Observer detection | 0-30 s | `FastStartFailoverThreshold=30` |
| FSFO execution | ~5 s | Broker + Standby promotion |
| FAN propagation | < 1 s | ONS push cross-site |
| UCP reaction | < 1 s | Pool invalidation + reconnect |
| TAC replay | 1-5 s | Per-session Transaction Guard |
| **Total RTO** | **~30-45 s** | End-user sees brief pause, no error |

---

### 🔄 Faza 5: Reinstate w tle (później)

Gdy stary primary (DC) wraca online (np. po restarcie host, reparacji sieci):

20. **host back online** — Observer widzi znów heartbeat od starego primary
21. **REINSTATE via Flashback** — Broker używa Flashback Database żeby "cofnąć" stary primary do punktu sprzed failover i zrobić z niego standby
22. **now PHYSICAL_STANDBY** — stary primary jest teraz standby

**Wynik:** Topologia "odwrócona" (DC=standby, DR=primary), ale wszystko działa. Opcjonalnie DBA może zrobić planowany switchover z powrotem do oryginalnej topologii (DC=primary).

**Warunki konieczne dla AutoReinstate:**
- `FastStartFailoverAutoReinstate = TRUE` (ADR-004)
- `Flashback Database ON` na obu bazach
- FRA (Fast Recovery Area) wystarczająco duża (przechowuje flashback logs)

Jeśli którykolwiek z warunków nie jest spełniony, stary primary zostaje w stanie `ORA-16661` (needs reinstate) do momentu ręcznego `REINSTATE DATABASE` przez DBA. Zob. [FSFO-GUIDE § 8.3](FSFO-GUIDE.md#83-reinstate-po-failoverze).

---

## 4. Kluczowe mechanizmy w jednym zdaniu

| Mechanizm | Faza | Rola |
|-----------|------|------|
| **FSFO** (Fast-Start Failover) | 1 + 2 | Observer decyduje i zleca failover, Broker wykonuje — **bez DBA** |
| **FAN/ONS** (Fast Application Notification) | 3 | Pushowe powiadomienia żeby aplikacja nie musiała czekać na TCP timeout |
| **TAC** (Transparent Application Continuity) | 4 | Transakcje w locie są **automatycznie** odtwarzane bez zmian w aplikacji |
| **Transaction Guard** (LTXID + commit_outcome) | 4 | Niezawodny protokół do sprawdzenia czy transakcja przeszła przed awarią |
| **AutoReinstate + Flashback** | 5 | Stary primary "sam się naprawia" bez interwencji DBA |

---

## 5. Co by się stało bez tego wszystkiego?

| Brak | Efekt |
|------|-------|
| **Bez FSFO** | DBA dostaje pager o 3:00 w nocy → ręczny failover → **~15-30 min downtime** |
| **Bez TAC** | Aplikacja widzi `ORA-03113` → użytkownicy widzą błąd → każdy musi manualnie ponowić transakcję (z ryzykiem duplikacji jeśli commit jednak przeszedł) |
| **Bez Observer HA (3 observery)** | Jeśli Observer padnie razem z Primary → nikt nie zdecyduje o failoverze → pełna ręczna interwencja |
| **Bez cross-site ONS** | UCP nie dostaje FAN events → musi czekać na TCP timeout (~60 s) zanim zauważy że stary primary nie żyje → **RTO rośnie do ~90-120s** |
| **Bez `commit_outcome=TRUE`** | TAC replay nie wie czy `COMMIT` przeszedł → ryzyko duplikacji transakcji (np. klient zapłacił dwa razy!) |
| **Bez `session_state_consistency=DYNAMIC`** | Replay traci zmienne PL/SQL, NLS, temp tables → aplikacja dostaje wyniki "z innej sesji" |
| **Bez Flashback ON** | AutoReinstate nie działa → stary primary musi być ręcznie reinstate'owany lub zrebuild'owany (godziny pracy DBA) |

---

## 6. Wnioski operacyjne

Diagram to **ściąga mentalna dla on-call DBA i DevOps** — pokazuje, że każda z 6 kolumn ma **ściśle zdefiniowaną rolę** i dowolna z nich może być mitygowana osobno.

**Dla DBA on-call:**
- Przeczytaj alert log pod kątem którego etapu (1-5) coś poszło nie tak
- Sprawdź w kolejności: Broker (`SHOW CONFIGURATION`) → FSFO (`SHOW FAST_START FAILOVER`) → Observer (`SHOW OBSERVER`) → Lag (`V$DATAGUARD_STATS`) → Replay (`GV$REPLAY_STAT_SUMMARY`)
- Runbook w [INTEGRATION-GUIDE § 6.6](INTEGRATION-GUIDE.md#66-troubleshooting-checklist)

**Dla App teamu:**
- Faza 4 (TAC replay) zależy od **waszego kodu**: brak `ALTER SESSION` / `UTL_HTTP` / DDL w transakcji = replay działa. Jeden wyciek = replay się psuje
- Monitoring przez `tac_replay_monitor.sql` — sekcja 5 skanuje V$SQL pod kątem non-replayable operations

**Dla Security / Network:**
- Cross-site ONS (DC↔DR, port 6200) to **hard requirement** — bez tego RTO podwaja się
- Observer (EXT) musi widzieć oba SCAN (DC + DR) — firewall + DNS

**Dla zespołu zarządzającego SLA:**
- Z tym wszystkim działającym: RTO ≤ 45 s, RPO = 0, aplikacja widzi krótką pauzę zamiast błędu
- Kwartalny drill (test T-3 z [PLAN.md Phase 5](PLAN.md#-phase-5--integration-testing-weeks-10-13)) weryfikuje że nic nie zardzewiało

---

## 7. Drugi widok: Timing Breakdown (Gantt)

Ten sam failover pokazany przez **Gantt chart** z [INTEGRATION-GUIDE.md § 4.2](INTEGRATION-GUIDE.md#42-timing-breakdown-mermaid) — **zupełnie inna perspektywa** niż sequence diagram:
- **Sequence diagram** pokazuje **kto z kim rozmawia** (kolumny = aktorzy)
- **Gantt chart** pokazuje **jak długo trwa każda faza** (paski = czas na osi X)

Oś X = sekundy. Oś Y = 6 torów aktywności (swimlanes). Każdy pasek = aktywność, której **długość jest proporcjonalna do czasu trwania**.

### 🎯 Kluczowa obserwacja — jeden pasek dominuje całość

**"Heartbeat lost (observer waits)" zajmuje 30 sekund — cała szerokość pierwszego rzędu.**
Wszystkie pozostałe 7 aktywności razem to ledwie **~15 sekund**.

To jest **fundamentalna prawda o FSFO**:

> **RTO ~45s = 30s czekania + 15s działania.**
> **66% RTO to *"obserwator celowo nic nie robi"*.**

### 🎯 Interpretacja każdego toru

| Tor (swimlane) | Aktywność | Czas | Dlaczego tyle trwa |
|----------------|-----------|------|---------------------|
| **Detect** | Heartbeat lost (observer waits) | **30 s** | Observer **celowo czeka** 30 s żeby odróżnić awarię od flappingu sieci. To `FastStartFailoverThreshold` ([ADR-003](DESIGN.md#adr-003-faststartfailoverthreshold--30s-laglimit--30s)) |
| **FSFO Execute** | Broker switchover to STBY | 5 s | Broker zmienia rolę STBY → PRIMARY w controlfile + aktualizuje metadata |
| **FSFO Execute** | New primary opens | 2 s | Nowy primary otwiera bazę do zapisu (redo logs, role-based services start) |
| **FAN** | Publish DOWN/UP events | 1 s | Primary pushuje eventy do ONS, ONS propaguje **cross-site** (DC↔DR, port 6200) |
| **UCP** | Invalidate bad connections | 1 s | UCP po otrzymaniu FAN DOWN wywala stare connection objects (bez czekania na TCP timeout) |
| **UCP** | Open new connections | 2 s | TCP handshake do nowego primary przez 2. `ADDRESS_LIST` w TNS |
| **TAC Replay** | Per-session transaction replay | 4 s | Dla każdej sesji: `GET_LTXID_OUTCOME` + replay DML + commit |
| **End** | App responds (user sees short pause) | — | Użytkownik dostaje odpowiedź — **bez błędu** |

### 🎯 3 wnioski architektoniczne

#### Wniosek #1: Gdzie szukać oszczędności w RTO?

Widać **od razu**: jeśli chcesz krótszego RTO, jedyny realny zysk to **zmniejszenie `FastStartFailoverThreshold`**. Pozostałe fazy są już krótkie — optymalizowanie "Publish DOWN/UP events" z 1 s do 0.5 s nie zmieni nic znaczącego.

Ale threshold 30 s ma uzasadnienie (false positives z flappingu sieci). Możesz zejść do **20 s** albo **15 s** przy stabilnej sieci metro-area — i wtedy RTO spada do ~30-35 s. **Schodzenie poniżej 10 s jest ryzykowne** (benchmarks MAA 2024 pokazały dramatyczny wzrost false positives).

**Praktyczna rekomendacja:**
- Fintech / banking retail: zostaw 30 s (stabilność > RTO)
- HFT / real-time trading: rozważ 15 s + agresywny monitoring sieci
- Wewnętrzne systemy: 30-60 s w porządku

#### Wniosek #2: Sekwencja, nie równoległość

Paski **nie nakładają się** — wszystko dzieje się **po kolei**. To ważna obserwacja operacyjna:

- Nie ma sensu "przyspieszać FAN" jeśli Broker jeszcze nie skończył switchover
- Nie ma sensu "preloadować connections w UCP" jeśli FAN jeszcze nie zdecydował gdzie one mają iść
- TAC replay **czeka** aż UCP otworzy nowe połączenia

Każda faza **wymaga** zakończenia poprzedniej. Dlatego **jedno wąskie gardło psuje cały RTO** — np. zablokowany firewall na ONS cross-site (6200) powoduje że FAN events nie docierają → UCP czeka na TCP timeout ~60 s → RTO rośnie do **~90-105 s** zamiast 45 s.

#### Wniosek #3: User Experience

Aplikacja widzi pauzę **od t=0s do t=45s** (~45 sekund). Dla aplikacji interaktywnej (bankowość, e-commerce) to jest **długie** — użytkownik może kliknąć "Refresh" w okolicach 10-15 sekundy.

Co oznacza:
- TAC replay robi, że **nie ma błędu** — ale użytkownik i tak widzi że "coś się dzieje"
- Dla aplikacji batchowych (ETL, overnight jobs) — 45 s **niewidoczne**
- Dla aplikacji async/event-driven (Kafka consumers, microservices z retry) — 45 s **niewidoczne**
- Dla aplikacji interaktywnych warto rozważyć **dodatkowy UX**: spinner "Synchronizujemy dane..." od samej aplikacji (kiedy JDBC zgłasza `in replay` przez `oracle.jdbc.replay.* APIs`), żeby user nie klikał F5 w środku replay

### 🎯 Porównanie: Sequence Diagram vs Gantt Chart

| Aspekt | Sequence Diagram ([§ 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction)) | Gantt Chart ([§ 4.2](INTEGRATION-GUIDE.md#42-timing-breakdown-mermaid)) |
|--------|-----------------------------------------------------------|----------------------|
| **Co pokazuje** | **Kto z kim rozmawia** (kolumny = aktorzy) | **Jak długo trwa każda faza** (paski = czas) |
| **Oś X** | Porządek zdarzeń (od góry do dołu) | Sekundy (skalowane do rzeczywistego czasu) |
| **Skala czasu** | Nierealistyczna — każda strzałka = "jedno zdarzenie" niezależnie od czasu | Realistyczna — 30 s jest 30× szersze niż 1 s |
| **Do kogo** | DBA debugujący *"dlaczego failover się zaciął"* | Architekt/SRE analizujący *"gdzie tracimy czas w RTO"* |
| **Pytanie na które odpowiada** | **Co się stało?** (kolejność, komunikacja) | **Gdzie tracimy czas?** (proporcje, bottleneck) |
| **Kiedy użyć** | Runbook on-call, code review konfiguracji | Sizing SLA, optymalizacja threshold, architecture review |

**Ta sama prawda, dwa światła:**
Oba diagramy pokazują ten sam failover, ale odpowiadają na różne pytania. Sequence = *"jak to działa"*. Gantt = *"ile to zajmuje"*.

---

## 👤 Autor / Author

**KCB Kris** | 2026-04-23 | v1.0

**Related:** [INTEGRATION-GUIDE.md § 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction) + [§ 4.2](INTEGRATION-GUIDE.md#42-timing-breakdown-mermaid) (źródłowe diagramy) • [FSFO-GUIDE.md](FSFO-GUIDE.md) • [TAC-GUIDE.md](TAC-GUIDE.md) • [PLAN.md](PLAN.md) • [DESIGN.md](DESIGN.md) • [checklist.html](../checklist.html)
