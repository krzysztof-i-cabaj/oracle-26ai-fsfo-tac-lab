> 🇬🇧 English | [🇵🇱 Polski](./FAILOVER-WALKTHROUGH_PL.md)

# 🎬 FAILOVER-WALKTHROUGH.md — step-by-step through the sequence diagram

![Oracle 19c](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![RTO](https://img.shields.io/badge/RTO-~45s-blue)
![Audience](https://img.shields.io/badge/audience-DBA%20%7C%20DevOps-green)

> Educational walkthrough of the sequence diagram from [INTEGRATION-GUIDE.md § 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction) — what exactly happens during automatic FSFO + TAC failover, actor by actor, second by second.

**Author:** KCB Kris | **Date:** 2026-04-23 | **Version:** 1.0
**Related:** [README.md](../README.md) • [FSFO-GUIDE.md](FSFO-GUIDE.md) • [TAC-GUIDE.md](TAC-GUIDE.md) • [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) • [PLAN.md](PLAN.md) • [DESIGN.md](DESIGN.md)

---

## 📋 Contents

1. [Context](#1-context)
2. [6 actors on the diagram](#2-6-actors-on-the-diagram)
3. [Failover phases](#3-failover-phases)
   - [Phase 1: Failure detection (0s → 30s)](#-phase-1-failure-detection-0s--30s)
   - [Phase 2: DB switch (30s → 35s)](#-phase-2-db-switch-30s--35s)
   - [Phase 3: Application notification (35s → 40s)](#-phase-3-application-notification-35s--40s)
   - [Phase 4: TAC transaction replay (40s → 45s)](#-phase-4-tac-transaction-replay-40s--45s--this-is-where-the-magic-happens)
   - [Phase 5: Reinstate in the background](#-phase-5-reinstate-in-the-background-later)
4. [Key mechanisms in one sentence each](#4-key-mechanisms-in-one-sentence-each)
5. [What would happen without all this?](#5-what-would-happen-without-all-this)
6. [Operational takeaways](#6-operational-takeaways)
7. [A second view: Timing Breakdown (Gantt)](#7-a-second-view-timing-breakdown-gantt)
   - [Key observation — one bar dominates](#-key-observation--one-bar-dominates-everything)
   - [Interpreting each lane](#-interpreting-each-lane)
   - [3 architectural takeaways](#-3-architectural-takeaways)
   - [Comparison: Sequence vs Gantt](#-comparison-sequence-diagram-vs-gantt-chart)

---

## 1. Context

The diagram in [INTEGRATION-GUIDE.md § 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction) is a **sequence diagram** that shows the **complete trajectory of an automatic failover** from every component's perspective — step by step, with a timeline from `t=0s` to `t=45s` plus the reinstate step later on.

**The goal of this walkthrough:**
- Teach on-call DBAs and DevOps what happens "under the hood" each second of the failover
- Show how the components (FSFO, FAN, TAC, Transaction Guard, UCP) cooperate
- Set expectations: **the end user should see no error**

**Architectural assumptions:**
- 2-node RAC PRIM in the DC site
- 2-node RAC STBY in the DR site
- Master Observer `obs_ext` in the EXT site
- `FastStartFailoverThreshold = 30s`, `FastStartFailoverAutoReinstate = TRUE`
- TAC service `MYAPP_TAC` with `failover_type=TRANSACTION`, `commit_outcome=TRUE`, `session_state_consistency=DYNAMIC`

---

## 2. 6 actors on the diagram

Every vertical column is one system actor:

| Column | System role | Where it physically lives |
|--------|-------------|---------------------------|
| **App (UCP)** | Your application with the Universal Connection Pool — this is who must observe the failover | App server (e.g. Kubernetes, VM) |
| **ONS (FAN)** | Oracle Notification Service — the DOWN/UP event bus between database and client | A process on every RAC node (port 6200) |
| **Primary (DC)** | The old primary in the DC site (the one that fails) | 2-node RAC in DC |
| **Observer Master (EXT)** | Observer in the third site — the "judge" deciding when to fail over | Dedicated host in EXT (`dgmgrl` + systemd) |
| **DG Broker** | Data Guard Broker — executes the decision (in practice it lives on both databases) | A process in every DB instance (PRIM + STBY) |
| **Standby (DR)** | Standby in the DR site (the one that takes the primary role) | 2-node RAC in DR |

---

## 3. Failover phases

### 🔴 Phase 1: Failure detection (0s → 30s)

1. **`t=0s`: Primary crashes** — primary fails (e.g. DC hardware outage, network outage, rack-level failure)
2. **heartbeat LOST** — Observer stops receiving the heartbeat from Primary. **It does not react immediately** (a brief network flap is NOT a failure)
3. **Timer running (threshold=30s)** — Observer counts down 30 seconds (`FastStartFailoverThreshold`)
4. **`t=30s`: Threshold exceeded** — after 30 s of continuous silence the Observer concludes: "Primary is really gone"

> **Why 30 s?** It is a compromise between false positives (network flaps) and RTO. Set in [DESIGN.md ADR-003](DESIGN.md#adr-003-faststartfailoverthreshold--30s-laglimit--30s). MAA 2024 benchmarks showed that shorter thresholds (e.g. 10 s) cause too many false-positive failovers under network flaps; longer ones (60 s) double the RTO.

---

### ⚡ Phase 2: DB switch (30s → 35s)

5. **Initiate FSFO — FAILOVER TO STBY** — Observer commands the Broker (`FAILOVER TO STBY`)
6. **Promote to PRIMARY** — Broker tells the Standby: "You are now the primary"
7. **Role changed** — Standby confirms the role change (DG Broker marks `database_role=PRIMARY` in the STBY controlfile)
8. **`t=35s`: STBY is the new PRIMARY** — in 5 seconds the database is ready to accept traffic

**What happens "under the hood":**
- Standby opens redo logs for write
- The role in `V$DATABASE.database_role` flips from `PHYSICAL STANDBY` to `PRIMARY`
- Role-based services with `-role PRIMARY` (MYAPP_TAC) start automatically
- Role-based services with `-role PHYSICAL_STANDBY` (MYAPP_RO) are stopped

---

### 📡 Phase 3: Application notification (35s → 40s)

9. **Publish FAN events (DOWN primary, UP new primary)** — the new Primary (STBY/DR) publishes events to ONS
10. **FAN DOWN: PRIM** — ONS pushes to the application: "The old primary is dead"
11. **FAN UP: STBY (new PRIMARY)** — "There is a new primary, connect there"
12. **Invalidate old connections** — a self-loop on App — UCP throws away every connection to the dead database (without waiting for the TCP timeout of ~60 s!)
13. **Open new connections to the new primary (via the 2nd ADDRESS_LIST in TNS)** — UCP uses the second `ADDRESS_LIST` in TNS (DR scan) to create new connections

**The crucial role of cross-site ONS:**
Without cross-site ONS (DC↔DR, port 6200) UCP **does not receive** FAN events from the new primary. It would have to wait for the TCP timeout (~60 s) before noticing that the old primary is dead. That would push RTO from ~45 s up to ~90+ s.

**Critical TNS configuration:**
```
MYAPP_TAC =
  (DESCRIPTION =
    (FAILOVER = ON)
    (ADDRESS_LIST =
      (ADDRESS = (HOST = scan-dc.corp.local)(PORT = 1521))
    )
    (ADDRESS_LIST =
      (ADDRESS = (HOST = scan-dr.corp.local)(PORT = 1521))   ← this line is the rescue
    )
    (CONNECT_DATA = (SERVICE_NAME = MYAPP_TAC))
  )
```

---

### 🔁 Phase 4: TAC transaction replay (40s → 45s) — **this is where the magic happens**

14. **`t=40s`: TAC replay** — the application had in-flight transactions (e.g. `UPDATE accounts SET balance=... COMMIT`) — **it is unknown whether the commit made it through before the failure**
15. **Query LTXID outcome (uncommitted txns)** — the application asks the new primary: "Was my transaction with LTXID=xyz committed?"
    - **LTXID** = Logical Transaction ID — a unique ID for every transaction, recorded thanks to `commit_outcome=TRUE` on the service
    - The query is sent via `DBMS_APP_CONT.GET_LTXID_OUTCOME(ltxid)`
16. **UNCOMMITTED** — Transaction Guard answers: "That transaction was NOT committed, replay is safe"
    - If the answer were `COMMITTED`, TAC would return the result to the application without replay (the transaction made it through before the failure)
17. **Replay transactions (UPDATE, INSERT, COMMIT)** — the application, automatically and **with zero developer code**, re-executes every DML since the last `COMMIT`
    - Session state (NLS, PL/SQL package vars, temp tables) is preserved thanks to `session_state_consistency=DYNAMIC`
    - Mutable objects (`SYSDATE`, sequences, `SYS_GUID()`) are "frozen" — they take the same values as during the original execution
18. **Replay OK** — success
19. **Response to the end user (no error seen)** — and now the **key moment**: the end user gets a normal response, as if nothing happened

**Why does the user see no error?**
- Without TAC: the application catches a `SQLException` (ORA-03113 or ORA-25408) → it has to decide manually what to do → it usually returns "Please try again" to the user
- With TAC: the JDBC driver behind UCP catches the error itself, checks LTXID, replays the transaction — the application receives a result as if nothing happened. **Even if `conn.executeUpdate()` is mid-call during the failure**, the method returns normally.

---

### ✅ `t=45s`: Total RTO

After **45 seconds** the end user sees only a brief slowdown (as if they clicked the app and waited a second longer). No error, no "please try again", no lost transaction.

**RTO breakdown (per [INTEGRATION-GUIDE § 2.3](INTEGRATION-GUIDE.md#23-impact-on-rto--rpo)):**

| Metric | Value | Component |
|--------|-------|-----------|
| RPO | 0 | SYNC+AFFIRM transport |
| Observer detection | 0–30 s | `FastStartFailoverThreshold=30` |
| FSFO execution | ~5 s | Broker + Standby promotion |
| FAN propagation | < 1 s | ONS push cross-site |
| UCP reaction | < 1 s | Pool invalidation + reconnect |
| TAC replay | 1–5 s | Per-session Transaction Guard |
| **Total RTO** | **~30–45 s** | End user sees a brief pause, no error |

---

### 🔄 Phase 5: Reinstate in the background (later)

When the old primary (DC) returns online (e.g. after host restart, network repair):

20. **host back online** — Observer sees a heartbeat from the old primary again
21. **REINSTATE via Flashback** — Broker uses Flashback Database to "rewind" the old primary to a point in time before the failover and turn it into a standby
22. **now PHYSICAL_STANDBY** — the old primary is now a standby

**Result:** The topology is "flipped" (DC=standby, DR=primary), but everything works. Optionally a DBA can perform a planned switchover back to the original topology (DC=primary).

**Conditions required for AutoReinstate:**
- `FastStartFailoverAutoReinstate = TRUE` (ADR-004)
- `Flashback Database ON` on both databases
- FRA (Fast Recovery Area) sized big enough (it stores flashback logs)

If any of those conditions is missing, the old primary stays in `ORA-16661` (needs reinstate) until a manual `REINSTATE DATABASE` from the DBA. See [FSFO-GUIDE § 8.3](FSFO-GUIDE.md#83-reinstate-po-failoverze).

---

## 4. Key mechanisms in one sentence each

| Mechanism | Phase | Role |
|-----------|-------|------|
| **FSFO** (Fast-Start Failover) | 1 + 2 | The Observer decides and orders the failover, the Broker executes — **without a DBA** |
| **FAN/ONS** (Fast Application Notification) | 3 | Push notifications so the application does not have to wait for the TCP timeout |
| **TAC** (Transparent Application Continuity) | 4 | In-flight transactions are **automatically** replayed without changes to the application |
| **Transaction Guard** (LTXID + commit_outcome) | 4 | A reliable protocol for checking whether a transaction made it through before the failure |
| **AutoReinstate + Flashback** | 5 | The old primary "fixes itself" without DBA intervention |

---

## 5. What would happen without all this?

| Missing | Effect |
|---------|--------|
| **Without FSFO** | DBA gets a 3 a.m. page → manual failover → **~15–30 min downtime** |
| **Without TAC** | Application sees `ORA-03113` → users see an error → each one has to manually re-run the transaction (with duplication risk if the commit did go through) |
| **Without Observer HA (3 observers)** | If the Observer dies together with the Primary → no one decides on failover → full manual intervention |
| **Without cross-site ONS** | UCP does not get FAN events → has to wait for the TCP timeout (~60 s) before noticing that the old primary is dead → **RTO grows to ~90–120 s** |
| **Without `commit_outcome=TRUE`** | TAC replay does not know whether the `COMMIT` went through → risk of duplicate transactions (e.g. the customer paid twice!) |
| **Without `session_state_consistency=DYNAMIC`** | Replay loses PL/SQL variables, NLS, temp tables → application receives results "from a different session" |
| **Without Flashback ON** | AutoReinstate does not work → the old primary has to be manually reinstated or rebuilt (hours of DBA work) |

---

## 6. Operational takeaways

The diagram is a **mental cheat-sheet for on-call DBA and DevOps** — it shows that each of the 6 columns has a **strictly defined role** and any one of them can be mitigated separately.

**For the on-call DBA:**
- Read the alert log for which stage (1–5) something went wrong
- Check in this order: Broker (`SHOW CONFIGURATION`) → FSFO (`SHOW FAST_START FAILOVER`) → Observer (`SHOW OBSERVER`) → Lag (`V$DATAGUARD_STATS`) → Replay (`GV$REPLAY_STAT_SUMMARY`)
- Runbook in [INTEGRATION-GUIDE § 6.6](INTEGRATION-GUIDE.md#66-troubleshooting-checklist)

**For the App team:**
- Phase 4 (TAC replay) depends on **your code**: no `ALTER SESSION` / `UTL_HTTP` / DDL inside the transaction = replay works. One leak and replay breaks
- Monitoring via `tac_replay_monitor.sql` — section 5 scans V$SQL for non-replayable operations

**For Security / Network:**
- Cross-site ONS (DC↔DR, port 6200) is a **hard requirement** — without it RTO doubles
- The Observer (EXT) must see both SCANs (DC + DR) — firewall + DNS

**For the SLA-managing team:**
- With all of this in place: RTO ≤ 45 s, RPO = 0, the application sees a short pause instead of an error
- A quarterly drill (test T-3 from [PLAN.md Phase 5](PLAN.md#-phase-5--integration-testing-weeks-10-13)) verifies that nothing has rusted

---

## 7. A second view: Timing Breakdown (Gantt)

The same failover seen as a **Gantt chart** in [INTEGRATION-GUIDE.md § 4.2](INTEGRATION-GUIDE.md#42-timing-breakdown-mermaid) — a **completely different perspective** from the sequence diagram:
- A **sequence diagram** shows **who talks to whom** (columns = actors)
- A **Gantt chart** shows **how long each phase takes** (bars = time on the X axis)

X axis = seconds. Y axis = 6 activity tracks (swimlanes). Each bar = an activity whose **length is proportional to its duration**.

### 🎯 Key observation — one bar dominates everything

**"Heartbeat lost (observer waits)" takes 30 seconds — the entire width of the first row.**
All 7 remaining activities together amount to barely **~15 seconds**.

This is a **fundamental truth about FSFO**:

> **RTO ~45 s = 30 s of waiting + 15 s of action.**
> **66% of the RTO is *"the observer deliberately doing nothing"*.**

### 🎯 Interpreting each lane

| Swimlane | Activity | Duration | Why it takes that long |
|----------|----------|----------|------------------------|
| **Detect** | Heartbeat lost (observer waits) | **30 s** | The Observer **deliberately waits** 30 s to distinguish a failure from a network flap. This is `FastStartFailoverThreshold` ([ADR-003](DESIGN.md#adr-003-faststartfailoverthreshold--30s-laglimit--30s)) |
| **FSFO Execute** | Broker switchover to STBY | 5 s | The Broker flips the STBY → PRIMARY role in the controlfile + updates metadata |
| **FSFO Execute** | New primary opens | 2 s | The new primary opens the database for write (redo logs, role-based services start) |
| **FAN** | Publish DOWN/UP events | 1 s | Primary pushes events to ONS, ONS propagates **cross-site** (DC↔DR, port 6200) |
| **UCP** | Invalidate bad connections | 1 s | After receiving FAN DOWN, UCP throws away the old connection objects (without waiting for the TCP timeout) |
| **UCP** | Open new connections | 2 s | TCP handshake to the new primary via the 2nd `ADDRESS_LIST` in TNS |
| **TAC Replay** | Per-session transaction replay | 4 s | For each session: `GET_LTXID_OUTCOME` + replay DML + commit |
| **End** | App responds (user sees a short pause) | — | The user gets a response — **with no error** |

### 🎯 3 architectural takeaways

#### Takeaway #1: Where to look for RTO savings

You can see **at a glance**: if you want a shorter RTO, the only real win is **reducing `FastStartFailoverThreshold`**. The other phases are already short — optimizing "Publish DOWN/UP events" from 1 s to 0.5 s buys you nothing meaningful.

But the 30 s threshold has its rationale (false positives from network flaps). You can drop to **20 s** or **15 s** on a stable metro-area network — and then RTO falls to ~30–35 s. **Going below 10 s is risky** (MAA 2024 benchmarks showed a dramatic increase in false positives).

**Practical recommendation:**
- Fintech / retail banking: keep 30 s (stability > RTO)
- HFT / real-time trading: consider 15 s + aggressive network monitoring
- Internal systems: 30–60 s is fine

#### Takeaway #2: Sequence, not parallelism

The bars **do not overlap** — everything happens **in sequence**. This is an important operational observation:

- It makes no sense to "speed up FAN" if Broker has not finished the switchover yet
- It makes no sense to "preload connections in UCP" if FAN has not decided where they should go
- TAC replay **waits** until UCP opens new connections

Each phase **needs** the previous one to finish. That is why **a single bottleneck wrecks the whole RTO** — e.g. a blocked firewall on cross-site ONS (6200) means FAN events do not arrive → UCP waits for the TCP timeout ~60 s → RTO grows to **~90–105 s** instead of 45 s.

#### Takeaway #3: User experience

The application sees a pause **from t=0s to t=45s** (~45 seconds). For an interactive application (banking, e-commerce) that is **long** — the user may click "Refresh" around the 10–15-second mark.

This means:
- TAC replay ensures **there is no error** — but the user still sees that "something is happening"
- For batch applications (ETL, overnight jobs) — 45 s is **invisible**
- For async/event-driven applications (Kafka consumers, microservices with retry) — 45 s is **invisible**
- For interactive applications, consider **additional UX**: a "Synchronizing data..." spinner from the application itself (when JDBC reports `in replay` via `oracle.jdbc.replay.* APIs`) so the user does not hit F5 mid-replay

### 🎯 Comparison: Sequence Diagram vs Gantt Chart

| Aspect | Sequence Diagram ([§ 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction)) | Gantt Chart ([§ 4.2](INTEGRATION-GUIDE.md#42-timing-breakdown-mermaid)) |
|--------|---------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| **What it shows** | **Who talks to whom** (columns = actors) | **How long each phase takes** (bars = time) |
| **X axis** | The order of events (top to bottom) | Seconds (scaled to real time) |
| **Time scale** | Unrealistic — every arrow = "one event" regardless of duration | Realistic — 30 s is 30× wider than 1 s |
| **For whom** | DBA debugging *"why the failover got stuck"* | Architect/SRE analyzing *"where we lose time in RTO"* |
| **Question it answers** | **What happened?** (order, communication) | **Where do we lose time?** (proportions, bottleneck) |
| **When to use** | On-call runbook, configuration code review | SLA sizing, threshold optimization, architecture review |

**The same truth, two lights:**
Both diagrams show the same failover but answer different questions. Sequence = *"how it works"*. Gantt = *"how long it takes"*.

---

## 👤 Author

**KCB Kris** | 2026-04-23 | v1.0

**Related:** [INTEGRATION-GUIDE.md § 2.2](INTEGRATION-GUIDE.md#22-what-happens-during-failover--component-interaction) + [§ 4.2](INTEGRATION-GUIDE.md#42-timing-breakdown-mermaid) (source diagrams) • [FSFO-GUIDE.md](FSFO-GUIDE.md) • [TAC-GUIDE.md](TAC-GUIDE.md) • [PLAN.md](PLAN.md) • [DESIGN.md](DESIGN.md) • [checklist.html](../checklist.html)
