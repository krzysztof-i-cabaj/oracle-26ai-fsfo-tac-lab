> [🇬🇧 English](./PLAN.md) | 🇵🇱 Polski

# 📅 PLAN.md — Plan wdrożenia FSFO + TAC Oracle 19c

![Status](https://img.shields.io/badge/Status-ready-4CAF50)
![Duration](https://img.shields.io/badge/Duration-13%2B%20weeks-blue)
![Phases](https://img.shields.io/badge/Phases-6-orange)

> Harmonogram wdrożenia Oracle 19c FSFO + TAC w topologii 3-site (DC/DR/EXT).
> Deployment timeline for Oracle 19c FSFO + TAC in 3-site topology (DC/DR/EXT).

> **💡 Interaktywna wersja:** [checklist.html](../checklist.html) zawiera ten sam harmonogram w formie graficznej (Gantt Timeline, Risk Matrix, klikalne checkboxy z progresem zapisywanym w `localStorage`).

---

## 🎯 Cele projektu / Project goals

| Cel | Metryka sukcesu |
|-----|-----------------|
| RTO ≤ 30 s pod awarią PRIM | End-to-end failover test ≤ 30 s |
| RPO = 0 | SYNC+AFFIRM transport, zero lost txns podczas testu |
| Zero application changes for TAC | Aplikacja kompilowana bez `-D` flag, pool tylko UCP |
| Observer HA bez SPOF | 3 observery (DC/DR/EXT), dowolny 1 może paść bez wpływu |
| Self-healing po transient failure | AutoReinstate=TRUE — stary primary wraca jako standby bez DBA |

---

## 📊 Timeline (Gantt-style)

```
                      Week  1  2  3  4  5  6  7  8  9 10 11 12 13 14+
Phase 0 — Diagnostics  ██
Phase 1 — DG Broker       ██ ██
Phase 2 — FSFO + Observer       ██ ██
Phase 3 — TAC Service                 ██
Phase 4 — UCP + FAN                      ██ ██ ██
Phase 5 — Integration Testing                     ██ ██ ██ ██
Phase 6 — Go-Live + Monitoring                                   ████...
```

---

## 📋 Phase 0 — Diagnostyka (Week 1)

**Cel:** Baseline środowiska, dokumentacja stanu obecnego, identyfikacja luk przed wdrożeniem.

### Zadania / Tasks

| # | Zadanie | Narzędzie | Output |
|---|---------|-----------|--------|
| 0.1 | Audyt wersji Oracle na obu klastrach (DC, DR) | `sqlconn.sh -s PRIM -f sql/fsfo_check_readiness.sql` | `reports/PRIM_readiness.txt` |
| 0.2 | Audyt force_logging, flashback, SRL, broker | Sekcje 1-4 `fsfo_check_readiness.sql` | jw. |
| 0.3 | Weryfikacja licencji (EE, Diagnostic, Tuning) | `SELECT * FROM v$option` | Raport do DESIGN § 5.4 |
| 0.4 | Mapowanie sieci DC↔DR↔EXT (latency, MTU, firewall) | `ping`, `mtr`, `iperf3` | Raport sieciowy |
| 0.5 | Sprawdzenie portów: 1521, 1522 (DGMGRL static), 6200 (ONS) | `netstat -tlnp`, `nmap` | Lista blokad do eskalacji |
| 0.6 | Przygotowanie 3 hostów observer (DC/DR/EXT) — OS, dgmgrl, systemd | Manual | Hosty gotowe |
| 0.7 | Review CLAUDE.md + DESIGN.md z zespołem | Meeting | Sign-off DBA lead |

### Deliverables

- Raport readiness dla PRIM i STBY
- Sign-off DBA + Network + Security teams
- Zaktualizowany DESIGN.md (wypełnione "przyszłe decyzje" na bazie faktów)

### Gate do Phase 1

- [ ] PRIM i STBY: Oracle 19c EE + RAC
- [ ] Force logging ON, Flashback ON na obu
- [ ] SRL skonfigurowane na STBY (N+1 logów, rozmiar = redo primary)
- [ ] Porty otwarte we wszystkich kierunkach (DC↔DR, DC↔EXT, DR↔EXT)
- [ ] 3 observer hosts available (CPU, RAM, dysk, sieć)

---

## 📋 Phase 1 — DG Broker Setup (Weeks 2-3)

**Cel:** Włączyć i skonfigurować Data Guard Broker na PRIM i STBY; zweryfikować manual switchover.

### Zadania / Tasks

| # | Zadanie | Polecenie | Miejsce |
|---|---------|-----------|---------|
| 1.1 | Ustawić `dg_broker_start=TRUE` na obu DB | `ALTER SYSTEM SET dg_broker_start=TRUE SCOPE=BOTH SID='*';` | PRIM + STBY |
| 1.2 | Skonfigurować static listener w `listener.ora` (SID `PRIM_DGMGRL`, `STBY_DGMGRL`) | Edycja `listener.ora` + `lsnrctl reload` | Wszystkie nody RAC |
| 1.3 | Wygenerować skrypt dgmgrl przez generator | `sqlconn.sh -s PRIM -f sql/fsfo_configure_broker.sql -o broker_setup.dgmgrl` | Laptop DBA |
| 1.4 | Review `broker_setup.dgmgrl` przez DBA lead | Manual | — |
| 1.5 | `CREATE CONFIGURATION`, `ADD DATABASE`, `ENABLE CONFIGURATION` | `dgmgrl sys/@PRIM_ADMIN @broker_setup.dgmgrl` | PRIM (primary) |
| 1.6 | Weryfikacja: `SHOW CONFIGURATION` — SUCCESS | dgmgrl | — |
| 1.7 | Test manual switchover PRIM → STBY | `SWITCHOVER TO STBY;` | — |
| 1.8 | Switchback STBY → PRIM | `SWITCHOVER TO PRIM;` | — |
| 1.9 | Monitoring `fsfo_broker_status.sql` | `sqlconn.sh -s PRIM -f sql/fsfo_broker_status.sql` | — |

### Deliverables

- Broker configuration `DG_CONFIG_PRIM_STBY` w stanie SUCCESS
- Udany test manual switchover (round-trip PRIM → STBY → PRIM)
- Log ze switchover'a (apply lag = 0, transport lag = 0 po powrocie)

### Gate do Phase 2

- [ ] `SHOW CONFIGURATION` returns `SUCCESS`
- [ ] `SHOW DATABASE PRIM` / `SHOW DATABASE STBY` — obie `SUCCESS`
- [ ] Manual switchover: wykonany, round-trip ≤ 2 minuty
- [ ] `DBA_DG_BROKER_CONFIG.ACTIVE` = `TRUE` na obu

---

## 📋 Phase 2 — FSFO + Observer (Weeks 4-5)

**Cel:** Włączyć FSFO, wdrożyć 3 Observery (DC/DR/EXT), zweryfikować auto-failover.

### Zadania / Tasks

| # | Zadanie | Polecenie | Miejsce |
|---|---------|-----------|---------|
| 2.1 | Ustawić FSFO properties | dgmgrl `EDIT CONFIGURATION SET PROPERTY ...` | PRIM |
| 2.2 | FastStartFailoverThreshold=30, LagLimit=30, AutoReinstate=TRUE, ObserverOverride=TRUE, ObserverReconnect=10 | patrz [FSFO-GUIDE § 5](FSFO-GUIDE.md#5-fsfo-configuration) | — |
| 2.3 | Utworzyć wallety Observer na 3 hostach (DC/DR/EXT) | `mkstore -wrl /etc/oracle/wallet/observer-{dc,dr,ext} -createCredential ...` | 3 hosty |
| 2.4 | Wdrożyć systemd unit files (z [systemd/](../systemd/)) | `cp systemd/dgmgrl-observer-{dc,dr,ext}.service /etc/systemd/system/; systemctl daemon-reload` | 3 hosty |
| 2.5 | `ADD OBSERVER 'obs_dc' ON 'host-dc'` (itd. dla DR, EXT) | dgmgrl | PRIM |
| 2.6 | `SET MASTEROBSERVER TO obs_ext` | dgmgrl | PRIM |
| 2.7 | `ENABLE FAST_START FAILOVER` | dgmgrl | PRIM |
| 2.8 | `systemctl start dgmgrl-observer-ext` (master), potem backup'y | systemctl | 3 hosty |
| 2.9 | Weryfikacja `SHOW OBSERVER` — wszystkie `YES` connected | dgmgrl | — |
| 2.10 | **Test auto-failover:** `SHUTDOWN ABORT` na PRIM | — | PRIM |
| 2.11 | Oczekiwany: FSFO przełącza do STBY w ~30-45 s | Monitoring `fsfo_monitor.sh -s STBY -a` | — |
| 2.12 | Test reinstate: `startup mount` na starym PRIM | Auto: broker sam zrobi reinstate | — |
| 2.13 | Switchback do pierwotnej roli | `SWITCHOVER TO PRIM;` | — |
| 2.14 | **Test Observer HA:** zabij master (`systemctl stop`) → backup powinien przejąć | — | obs_ext |

### Deliverables

- FSFO `ENABLED` + 3 Observery connected
- Udany test auto-failover (RTO ≤ 45 s)
- Udany test auto-reinstate
- Udany test Observer HA (master failover w ≤ 10 s)

### Gate do Phase 3

- [ ] `SHOW FAST_START FAILOVER` returns `ENABLED` + `Master Observer: obs_ext`
- [ ] Wszystkie 3 observery `YES Connected`
- [ ] Auto-failover test zakończony sukcesem (RTO udokumentowany)
- [ ] Auto-reinstate po failoverze — działa
- [ ] Observer master failover — działa (< 60 s quorum re-establishment)

---

## 📋 Phase 3 — TAC Service Configuration (Week 6)

**Cel:** Skonfigurować TAC-enabled services na PRIM i STBY, zweryfikować service-level attributes.

### Zadania / Tasks

| # | Zadanie | Polecenie | Miejsce |
|---|---------|-----------|---------|
| 3.1 | Review `sql/tac_configure_service_rac.sql` | Manual | — |
| 3.2 | Uruchomienie na PRIM (dry-run) | `sqlconn.sh -s PRIM -i -f sql/tac_configure_service_rac.sql -d` | PRIM |
| 3.3 | Faktyczne wykonanie (`srvctl add service` dla MYAPP_TAC, role=PRIMARY) | `bash/tac_deploy.sh -s PRIM` | PRIM |
| 3.4 | Utworzenie MYAPP_RO (role=PHYSICAL_STANDBY) | jw. | — |
| 3.5 | Weryfikacja atrybutów: `srvctl config service -d PRIM -s MYAPP_TAC` | — | — |
| 3.6 | `failover_type=TRANSACTION`, `commit_outcome=TRUE`, `session_state_consistency=DYNAMIC` — wszystkie potwierdzone | `SELECT * FROM dba_services WHERE name = 'MYAPP_TAC';` | PRIM |
| 3.7 | Start service: `srvctl start service -d PRIM -s MYAPP_TAC` | — | PRIM |
| 3.8 | Potwierdzenie że service jest running na obu instance RAC | `srvctl status service -d PRIM -s MYAPP_TAC` | PRIM |
| 3.9 | Test switchover: service powinien przełączyć się na STBY | `SWITCHOVER TO STBY;` + `srvctl status` | — |
| 3.10 | Switchback | — | — |

### Deliverables

- TAC services MYAPP_TAC i MYAPP_RO uruchomione na obu klastrach
- Role-based service (auto-start na role PRIMARY po switchover)
- Service attributes zgodne z [ADR-005](DESIGN.md#adr-005-tac-z-failover_typetransaction-i-dynamic-session-state)

### Gate do Phase 4

- [ ] `MYAPP_TAC` + `MYAPP_RO` running
- [ ] `failover_type=TRANSACTION` potwierdzone w `dba_services`
- [ ] Service auto-switches role przy switchover
- [ ] `commit_outcome=TRUE`, `drain_timeout=300`

---

## 📋 Phase 4 — UCP + FAN Configuration (Weeks 7-9)

**Cel:** Skonfigurować aplikację (UCP pool), włączyć FAN cross-site, test TAC end-to-end na maszynach deweloperskich.

### Zadania / Tasks

| # | Zadanie | Własność | Tydzień |
|---|---------|----------|---------|
| 4.1 | Upgrade JDBC do 19c+ (`ojdbc11.jar`) w repo aplikacji | App team | W7 |
| 4.2 | Dodanie `oracle-ucp.jar` i `ons.jar` do dependencies | App team | W7 |
| 4.3 | Refactor pool: Hikari/DBCP → UCP | App team | W7-W8 |
| 4.4 | `ConnectionFactoryClassName=oracle.jdbc.replay.OracleDataSourceImpl` | App team | W8 |
| 4.5 | TNS string z dwoma ADDRESS_LIST (DC+DR) i `FAILOVER=ON` | DBA + App team | W8 |
| 4.6 | `srvctl modify ons -remoteservers <STBY_nodes:6200>` na PRIM (i odwrotnie) | DBA | W8 |
| 4.7 | Firewall: ONS 6200 DC↔DR bidirectional | Network | W8 |
| 4.8 | Test FAN events: `srvctl stop service -d PRIM -s MYAPP_TAC -drain_timeout 60` | — | W9 |
| 4.9 | Oczekiwany: UCP drain'uje aplikację, reconnect do drugiego node RAC | App monitoring | W9 |
| 4.10 | Test replay: `ALTER SYSTEM KILL SESSION ...` w środku transakcji | — | W9 |
| 4.11 | Oczekiwany: aplikacja nie widzi błędu; `GV$REPLAY_STAT_SUMMARY` pokazuje `requests_replayed > 0` | `fsfo_monitor.sql` sekcja 7 | W9 |

### Deliverables

- Aplikacja zintegrowana z UCP + TAC
- FAN events działają cross-site (PRIM↔STBY)
- Test replay: instance crash → aplikacja nie widzi błędu

### Gate do Phase 5

- [ ] `GV$REPLAY_STAT_SUMMARY.requests_total > 0` po teście
- [ ] Drain test: 0 application errors podczas `srvctl stop service -drain_timeout`
- [ ] UCP pool metrics: `failover_type=TRANSACTION` widoczne w session_info
- [ ] FAN events visible na kliencie (`oracle.ucp.log=FINE`)

---

## 📋 Phase 5 — Integration Testing (Weeks 10-13)

**Cel:** Testy end-to-end kombinacji FSFO + TAC; walidacja SLA (RTO/RPO); chaos engineering.

### Test cases

| # | Scenariusz | Oczekiwany wynik | SLA |
|---|------------|-------------------|-----|
| T-1 | Planowany switchover z FSFO-aware | Drain→switch→services up na STBY; app bez błędów | 60 s |
| T-2 | `SHUTDOWN ABORT` na primary node 1 (jeszcze node 2 działa) | FAN DOWN; UCP reroute na node 2; brak failover FSFO | ≤ 5 s |
| T-3 | `SHUTDOWN ABORT` obu nodes PRIM (awaria ośrodka DC) | Observer (master na EXT) inicjuje FSFO; failover na STBY (DR); TAC replay | ≤ 45 s |
| T-4 | Network partition DC↔DR (Observer widzi obie) | Observer decyduje na bazie quorum: failover na tę stronę, która ma heartbeat | ≤ 45 s |
| T-5 | Network partition DC↔EXT (Observer master izolowany) | Observer backup (obs_dr) przejmuje rolę mastera; FSFO nadal active | ≤ 60 s |
| T-6 | Observer host down (wszystkie 3) | FSFO pozostaje ENABLED ale nie failover; alert do on-call; manual failover możliwy | alert < 60 s |
| T-7 | Rolling patch Oracle (switchover + patch + switchback) | Zero downtime aplikacji; TAC replay w trakcie każdego switchover | 0 errors |
| T-8 | Kill session in-transaction: `ALTER SYSTEM KILL SESSION 'sid,serial#'` | TAC replay commit'a niezrealizowanego; aplikacja OK | ≤ 2 s |
| T-9 | Full STBY drain (60s) | Aplikacja w pełni drain; connection failover; 0 session termination errors | 60 s |
| T-10 | AutoReinstate po failoverze | Stary primary wraca jako standby bez interwencji; broker SUCCESS | ≤ 5 min |

### Deliverables

- Protokół testów z pomiarami RTO/RPO dla każdego scenariusza
- Identyfikacja i rozwiązanie regresji (jeśli występują)
- Sign-off biznesowy (SLA spełnione)

### Gate do Phase 6 (Go-Live)

- [ ] Wszystkie 10 scenariuszy testowych zakończone sukcesem
- [ ] RTO dla T-3 ≤ 45 s (SLA)
- [ ] RPO = 0 dla wszystkich testów (żadnych utraconych committed txns)
- [ ] Runbook [INTEGRATION-GUIDE § 6](INTEGRATION-GUIDE.md#6-operational-runbook) zweryfikowany w praktyce
- [ ] Zespół on-call przeszkolony (min. 2 osoby)

---

## 📋 Phase 6 — Go-Live + Monitoring (Ongoing)

**Cel:** Produkcja; ciągły monitoring; okresowe drills.

### Zadania stałe / Ongoing tasks

| # | Zadanie | Częstotliwość | Narzędzie |
|---|---------|---------------|-----------|
| 6.1 | Monitor FSFO status | co 5 min (cron) | `bash/fsfo_monitor.sh -s PRIM -a` |
| 6.2 | Monitor TAC replay stats | co 1 h | `sql/fsfo_monitor.sql` sekcja 7 |
| 6.3 | Monitor Observer health na 3 hostach | co 1 min | `systemctl status dgmgrl-observer-{dc,dr,ext}` |
| 6.4 | Apply lag alert | real-time | Grafana + `V$DATAGUARD_STATS` |
| 6.5 | Review alert log PRIM/STBY | daily | DBA on-call |
| 6.6 | Pełna walidacja multi-DB | weekly | `bash/validate_all.sh -l targets.lst` |
| 6.7 | Failover drill (planowany test) | quarterly | [INTEGRATION-GUIDE § 6.1](INTEGRATION-GUIDE.md#61-planned-switchover-fsfo-aware) |
| 6.8 | Review ADRs + DESIGN.md | bi-annually | Zespół DBA + Security |

### Alerty / Alerts

| Alert | Severity | Akcja |
|-------|----------|-------|
| FSFO `DISABLED` | CRITICAL | Paging on-call DBA; sprawdzić `ORA-16820/16825` |
| Apply lag ≥ 30 s (LagLimit) | CRITICAL | FSFO nie zadziała — sprawdzić transport, sieć |
| Observer master down | HIGH | Backup powinien przejąć w ≤ 60 s; verify `SHOW OBSERVER` |
| TAC replay success rate < 80% | MEDIUM | App design issue — review `GV$REPLAY_STAT_SUMMARY.requests_failed` |
| Broker config `WARNING` | MEDIUM | Sprawdzić `DBA_DG_BROKER_CONFIG_PROPERTIES` |

---

## 🚨 Risk Matrix

**Top 8 ryzyk wdrożeniowych** (zgodne z [checklist.html](../checklist.html) Risk Matrix):

| # | Ryzyko / Risk | Severity | Opis | Mitygacja |
|---|---------------|----------|------|-----------|
| **R1** | **Observer SPOF** | 🔴 HIGH | Single observer = single point of failure w łańcuchu decyzyjnym FSFO | Observer HA — 3 observery w DC/DR/EXT (ADR-001); systemd `Restart=on-failure`; `SET MASTEROBSERVER` preemptive |
| **R2** | **Network Partition** | 🔴 HIGH | Split-brain ryzyko gdy observer nie widzi obu site'ów | Master observer na trzecim ośrodku (EXT) — niezależna ścieżka sieciowa; quorum-based election |
| **R3** | **Reinstate Failure** | 🟡 MED | Stary primary nie wraca jako standby gdy Flashback wyłączony | `FLASHBACK ON` na PRIM i STBY; FRA odpowiednio rozmiarowana; `AutoReinstate=TRUE` |
| **R4** | **Lag Limit Exceeded** | 🟡 MED | Apply lag > `LagLimit` blokuje auto-failover | Monitoring ciągły; alert progowy przy 50% (15s); SYNC transport w normalnym obciążeniu |
| **R5** | **Non-replayable Ops** | 🔴 HIGH | `ALTER SESSION`, `UTL_HTTP`, DDL w TX przerywają TAC replay | Code review w Phase 4; `tac_replay_monitor.sql` Sekcja 5 skanuje V$SQL; refactoring kodu aplikacji |
| **R6** | **Old JDBC Drivers** | 🟡 MED | JDBC < 19c nie wspiera TAC replay | Upgrade do `ojdbc11.jar` 19c+; weryfikacja przez `V$SESSION_CONNECT_INFO` + `tac_full_readiness.sql` Sekcja 10 |
| **R7** | **FAN Port Blocked** | 🟡 MED | Firewall blokuje ONS 6200 — brak FAN events do UCP | Firewall matrix w Phase 0; test przed go-live (`telnet scan-dr 6200` z app server); cross-site ONS bidirectional |
| **R8** | **Performance Impact** | 🟢 LOW | Commit outcome tracking dodaje ~3% overhead (LTXID writes) | Benchmark w Phase 5; sizing CPU/IO z zapasem 10%; monitoring `V$SYSTEM_EVENT` dla `commit cleanouts` |

**Dodatkowe ryzyka operacyjne** (poza Top 8):

| # | Ryzyko | Severity | Mitygacja |
|---|--------|----------|-----------|
| R-9 | Broker misconfiguration | 🟡 MED | Generator `fsfo_configure_broker.sql` + DBA review w Phase 1 |
| R-10 | UCP misconfig | 🟡 MED | Code review; test T-8, T-9 w Phase 5 |
| R-11 | Wallet expiry | 🟢 LOW | Rotacja hasła zgodnie z polityką (90 dni); monitoring |
| R-12 | Brak RAC expertise on-call | 🟡 MED | Szkolenie w Phase 5; [INTEGRATION-GUIDE § 6](INTEGRATION-GUIDE.md#6-operational-runbook) |

---

## ✅ Deployment Checklist (finalna przed Go-Live)

### FSFO

- [ ] `SHOW CONFIGURATION` = `SUCCESS`
- [ ] `SHOW FAST_START FAILOVER` = `ENABLED`
- [ ] `FastStartFailoverThreshold` = 30
- [ ] `FastStartFailoverLagLimit` = 30
- [ ] `FastStartFailoverAutoReinstate` = TRUE
- [ ] `ObserverOverride` = TRUE
- [ ] `ObserverReconnect` = 10
- [ ] 3 Observery connected (obs_dc, obs_dr, obs_ext)
- [ ] Master Observer = `obs_ext`
- [ ] systemd units enabled + started na wszystkich 3 hostach
- [ ] Wallets na 3 hostach (`/etc/oracle/wallet/observer-*`)
- [ ] Auto-failover test: PASS (RTO ≤ 45 s)
- [ ] Auto-reinstate test: PASS
- [ ] Observer HA failover test: PASS

### TAC

- [ ] `MYAPP_TAC` uruchomione na PRIM (role=PRIMARY) i auto-switch na STBY przy switchover
- [ ] `MYAPP_RO` uruchomione (role=PHYSICAL_STANDBY)
- [ ] `failover_type=TRANSACTION`
- [ ] `commit_outcome=TRUE`
- [ ] `session_state_consistency=DYNAMIC`
- [ ] `retention_timeout=86400`
- [ ] `drain_timeout=300`
- [ ] `aq_ha_notifications=TRUE`

### UCP / Application

- [ ] `ojdbc11.jar` + `oracle-ucp.jar` + `ons.jar` wersja 19c+
- [ ] `ConnectionFactoryClassName=oracle.jdbc.replay.OracleDataSourceImpl`
- [ ] `FastConnectionFailoverEnabled=true`
- [ ] `ONSConfiguration` pointing do cross-site nodes
- [ ] TNS: dwa ADDRESS_LIST (DC+DR) + `FAILOVER=ON`
- [ ] Brak DDL wewnątrz transakcji
- [ ] Brak zewnętrznych wywołań (REST/JMS) w transakcji
- [ ] `DBMS_APP_CONT.REGISTER_CLIENT` dla niestandardowych mutable objects

### Network

- [ ] Port 1521 otwarte między app servers a SCAN (DC i DR)
- [ ] Port 6200 cross-site DC↔DR (dla ONS/FAN)
- [ ] Port 1522 między observer hosts a SCAN (DC i DR) — dla DGMGRL static listener
- [ ] Latency DC↔DR ≤ 2 ms (metro-area)
- [ ] Latency do EXT ≤ 50 ms

### Monitoring

- [ ] `bash/fsfo_monitor.sh` w crontab co 5 min
- [ ] Grafana dashboard z `V$DATAGUARD_STATS` + `GV$REPLAY_STAT_SUMMARY`
- [ ] Alerty na PagerDuty/OpsGenie dla CRITICAL scenariuszy
- [ ] On-call runbook: [INTEGRATION-GUIDE § 6](INTEGRATION-GUIDE.md#6-operational-runbook)

### Documentation

- [ ] `README.md` aktualny
- [ ] `DESIGN.md` aktualny (ADRs sign-offed)
- [ ] `FSFO-GUIDE.md` review DBA lead
- [ ] `TAC-GUIDE.md` review App team lead
- [ ] `INTEGRATION-GUIDE.md` review Security + Network
- [ ] Runbook drill przeprowadzony min. 2 razy

---

## 👤 Autor / Author

**KCB Kris** | Data: 2026-04-23 | Wersja: 1.0

**Related:** [README.md](../README.md) • [DESIGN.md](DESIGN.md) • [FSFO-GUIDE.md](FSFO-GUIDE.md) • [TAC-GUIDE.md](TAC-GUIDE.md) • [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)
