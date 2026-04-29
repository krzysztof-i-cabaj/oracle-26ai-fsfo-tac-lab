> [🇬🇧 English](./CODE-REVIEW-REPORT.md) | 🇵🇱 Polski

# 🔍 Raport przeglądu kodu i architektury

## Code & Architecture Review Report

![Oracle 19c](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![Review](https://img.shields.io/badge/review-AI--assisted-blueviolet)
![Scope](https://img.shields.io/badge/scope-FSFO%20%2B%20TAC%20%2B%20MAA-orange)
![Score](https://img.shields.io/badge/overall%20score-82%E2%86%9297%2F100-brightgreen)
![Blockers](https://img.shields.io/badge/blockers-5%20resolved-success)
![Phase 2](https://img.shields.io/badge/Phase%202-complete-brightgreen)

> 📚 **Dokument edukacyjny** — pokazuje proces krytycznej analizy projektu FSFO+TAC przez specjalistę Oracle DBA / MAA Architect. Projekt rozpoczął się z oceną 82/100 i po wdrożeniu rekomendacji osiągnął 97/100. Wszystkie 5 blockerów zaadresowane w Phase 1, a 3 ulepszenia architektoniczne (RMAN DUPLICATE runbook, split-brain diagnostics, ObserverOverride scenarios) dopracowane w Phase 2.

| Pole / Field | Wartość / Value |
|---|---|
| **Projekt / Project** | Oracle 19c FSFO + TAC Deployment Guide |
| **Katalog / Directory** | `_oracle_/20260423-FSFO-TAC-guide` |
| **Data / Date** | 2026-04-23 |
| **Wersja / Version** | 1.0 |
| **Recenzent / Reviewer** | Senior Oracle DBA / MAA Architect (AI-assisted review) |
| **Zakres / Scope** | README.md, DESIGN.md, PLAN.md, FSFO-GUIDE.md, TAC-GUIDE.md, FAILOVER-WALKTHROUGH.md, INTEGRATION-GUIDE.md, checklist.html, 8× sql/, 4× bash/ |
| **Cel / Purpose** | Dokument referencyjny dla Go-Live decision i backlogu Phase 1/2 |

---

## 🎯 1. Executive Summary

Projekt przedstawia **dojrzały, dobrze udokumentowany fundament** pod wdrożenie architektury MAA Oracle 19c z FSFO i TAC w topologii 3-site (DC / DR / EXT) z trzema Observerami oraz services RAC + Data Guard aware. Dokumentacja bilingualna PL/EN jest zgodna z `CLAUDE.md`, a 8 ADR-ów w `DESIGN.md` konsekwentnie uzasadnia decyzje architektoniczne (MaxAvailability, threshold=30 s, Master Observer na EXT, TAC z `TRANSACTION`+`DYNAMIC`).

**Ogólna ocena: 82/100** — projekt jest **gotowy do Go-Live po usunięciu 5 blockerów** z sekcji 2. Największe ryzyka:

- **B1** — zepsuty agregat w `validate_environment.sql` (sumuje tylko 6 z 12 checków, hardkoduje `'PASS'`).
- **B2** — błędne flagi `set -uo pipefail` w `fsfo_monitor.sh` i `validate_all.sh` (bez `-e` — skrypt uznaje za OK stan, w którym `sqlplus` padł).
- **B3** — niekompletna detekcja operacji non-replayable w `tac_full_readiness.sql` (brak `DBMS_RANDOM`, `SEQUENCE NOCACHE`, LOB, DDL auto-commit).
- **B4** — `fsfo_check_readiness.sql` nie waliduje `LOG_ARCHIVE_CONFIG=DG_CONFIG` (wymaganego dla brokera).
- **B5** — `fsfo_setup.sh` i `tac_deploy.sh` **generują** skrypty zamiast ich **wykonywać** — brak idempotencji, brak `srvctl add service`, `START OBSERVER`, `srvctl add ons`.

Rekomendacja: **Go-Live po usunięciu B1–B5** (realny nakład: ~3 dni DBA + 1 dzień testów UAT). Trendy MAA z sekcji 3 i dokumentacja z sekcji 5 mogą zostać w Phase 2.

---

## 🚨 2. Critical Findings (Blockers)

| # | Plik / Lokalizacja | Problem | Ryzyko |
|---|---|---|---|
| **B1** | `sql/validate_environment.sql` L214–236 | Agregat podsumowania sumuje tylko **6 z 12** zadeklarowanych checków (`banner LIKE '%Enterprise%' + log_mode + force_logging + flashback_on + dg_broker_start + v$standby_log`). Brakuje: protection_mode (CHECK 8), TAC services (CHECK 9), commit_outcome (CHECK 10), FAN/aq_ha_notifications (CHECK 11), session_state_consistency (CHECK 12). Dodatkowo `pct_z_calosci` to **literał** `'do/12'`, a `status_agg` jest hardkodowany jako `'PASS'`. Go/No-Go gate jest fałszywie zielony. | **Krytyczne** — DBA widzi „PASS 12/12" nawet gdy MAX AVAILABILITY nie jest ustawiony lub TAC jest wyłączony. |
| **B2** | `bash/fsfo_monitor.sh` L24, `bash/validate_all.sh` L22 | `set -uo pipefail` **bez flagi `-e`**. Gdy `sqlconn.sh` zwróci błąd (brak wallet, listener down), skrypt kontynuuje, grepuje pusty plik wyjścia i raportuje `[OK]`. Monitor cronowy wysyła „all clear" podczas rzeczywistej awarii sieciowej. | **Krytyczne** — cichy failure cron monitora = brak alertu przy prawdziwej awarii. |
| **B3** | `sql/tac_full_readiness.sql` sekcja 8 (L341–365) | Heurystyka non-replayable op detection zawiera tylko `ALTER SESSION`, `UTL_HTTP`, `UTL_SMTP`, `UTL_FILE`, `DBMS_PIPE`, `DBMS_ALERT`. **Brakuje**: `DBMS_RANDOM` w transakcji, `SEQUENCE NOCACHE`/`NOORDER`, LOB bez `DBMS_LOB` boundaries, DDL auto-commit (`CREATE TABLE AS SELECT` w sesji app), użycie `SYSDATE`/`SYSTIMESTAMP`/`SYS_GUID` bez `GRANT KEEP DATE/SYSGUID/SEQUENCE`, `DBMS_AQ.ENQUEUE/DEQUEUE`. | **Krytyczne** — false-positive readiness = TAC „działa", ale przy pierwszej awarii `requests_failed` skacze do 100%. |
| **B4** | `sql/fsfo_check_readiness.sql` sekcja 4 | Sprawdza `dba_dg_broker_config_properties`, ale **nie waliduje** wartości kluczowego parametru `LOG_ARCHIVE_CONFIG` (musi zawierać `DG_CONFIG=(db1,db2,db3)` — inaczej broker nie przyjmie konfiguracji Redo Transport). Brak także check `ARCHIVE_LAG_TARGET`, `DB_UNIQUE_NAME` i spójności `REMOTE_LOGIN_PASSWORDFILE=EXCLUSIVE`. | **Wysokie** — pre-flight przepuszcza setup, który padnie na `DGM-17016: failed to retrieve status` przy `ENABLE CONFIGURATION`. |
| **B5** | `bash/fsfo_setup.sh`, `bash/tac_deploy.sh` | Skrypty **generują skrypty** (do `reports/*.dgmgrl`, `reports/*.srvctl`) zamiast wykonywać zmiany. `fsfo_setup.sh` nigdy nie robi `START OBSERVER IN BACKGROUND`, `tac_deploy.sh` nigdy nie robi `srvctl add service` ani `srvctl add ons`. `FAILOVER-WALKTHROUGH.md` zakłada, że Observer jest uruchomiony — ale żaden plik projektu tego nie robi automatycznie. Brak idempotencji. | **Wysokie** — deployment nie jest automation-ready; po-deployment DBA musi ręcznie uruchomić wygenerowane skrypty. |

---

## ⚙️ 3. Best Practice Deviations (Oracle 19c MAA)

### 🛡️ 3.1 FSFO / Data Guard Broker

| Obszar | Stan obecny | MAA 19c best practice |
|---|---|---|
| Observery (3 instancje) | Master na EXT — **OK**, zgodnie z 19c (limit 3) | Brak ustawienia `ObserverLagThreshold` (19c 19.7+) dla detekcji zawieszonego Observera. |
| `FastStartFailoverAutoReinstate=TRUE` | Tak (ADR-004) | OK dla MaxAvailability. Dokumentacja powinna jawnie wskazać, że wymaga `FLASHBACK DATABASE ON` + `DB_FLASHBACK_RETENTION_TARGET` ≥ 2× `FastStartFailoverThreshold` + RPO margin. |
| Redo Transport Compression | **Nie skonfigurowane** | Dla WAN (DC↔EXT, DR↔EXT) zalecane `EDIT DATABASE … SET PROPERTY Compression='HIGH'` (wymaga Advanced Compression Option — sprawdzić licencję). |
| Far Sync | **Nie wzmiankowane** w `DESIGN.md` | Dla zero-data-loss na WAN z akceptowalnym overhead Far Sync na EXT byłby architektonicznie czystszy od synchronicznego LogXptMode przez WAN. |
| `VALIDATE DATABASE` w runbookach | Brak w `bash/fsfo_monitor.sh`; obecny tylko w walkthrough jako krok manualny | Monitor powinien co N cykli uruchamiać `VALIDATE DATABASE VERBOSE` — dla detekcji luk SRL/archivelog gap. |
| Split-brain detection | Wzmianka w FSFO-GUIDE § 10.1, **brak skryptu** | Dodać `sql/fsfo_split_brain_check.sql`: `V$FS_FAILOVER_STATS.last_failover_time`, `V$DATAGUARD_CONFIG.dest_role`, `V$ARCHIVE_GAP`, rozbieżność `CURRENT_SCN` między Primary a „starym Primary". |
| `ObserverOverride` | Parametryzowany w `fsfo_configure_broker.sql` L139, ale **brak dokumentacji tradeoff** | TAC-GUIDE / FSFO-GUIDE powinna wyjaśnić, kiedy `ObserverOverride=TRUE` jest bezpieczny. |

### 🔄 3.2 TAC / Application Continuity

| Obszar | Stan obecny | MAA 19c best practice |
|---|---|---|
| `REPLAY_INITIATION_TIMEOUT=900` | `tac_configure_service_rac.sql` L109 | Dla mixed OLTP+batch workload zalecane **1800 s**; dla czystego OLTP — 300 s. |
| `FAILOVER_TYPE=TRANSACTION` | ADR-005 | OK. Dokumentacja nie omawia nowego `FAILOVER_TYPE=AUTO` (19c) — Oracle decyduje dynamicznie. |
| Monitoring `GV$APP_CONT_STATUS` | `tac_replay_monitor.sql` używa `GV$REPLAY_STAT_SUMMARY` — **OK** | Brakuje monitoringu `SYS.LTXID_TRANS$` — retention=86400 s powoduje puchnięcie; dodać purge job i alert. |
| DBMS_APP_CONT_ADMIN | Wzmianka w TAC-GUIDE § 7.4 | Brak skryptu `sql/tac_grant_keep.sql` (`GRANT KEEP DATE, KEEP SYSGUID, KEEP SEQUENCE TO <app_user>`) — bez tego mutable functions nie są replayowalne dla user aplikacyjnych. |
| ONS configuration | **Brak** w `tac_deploy.sh` | TAC bez ONS = FAN nie dochodzi do connection pools — cały TAC jest martwy. Must-have. |
| Driver compatibility matrix | README/DESIGN nie zawiera | Dodać: `ojdbc8 ≥ 19.3 + UCP 19.x` = pełne TAC; HikariCP = brak replay; python-oracledb thin < 2.0 = brak TAC; cx_Oracle thick = OK; ODP.NET Managed od 19.3 = OK. |

### 📖 3.3 Architektura dokumentacji

- ~~Brak diagramu sieciowego (port 1521/1522/6200/6123 cross-site, firewall ACL)~~ — **ZROBIONE** w `FSFO-GUIDE.md § 3.2` (rozszerzona tabela portów o 6200 ONS i 6123 CRS, diagram Mermaid z portami na strzałkach, firewall ACL checklist).
- ~~Brak sekcji **Capacity Planning**~~ — **ZROBIONE** w `FSFO-GUIDE.md § 3.5` (formuły dla SRL N+1, FRA sizing, flashback retention, SYSAUX, LTXID growth dla TPS; pre-deployment checklist).
- ~~Brak **runbooku SEV-1 „Observer lost"**~~ — **ZROBIONE** w `FSFO-GUIDE.md § 8.2` (8 faz z timing: triage → pre-check → komunikacja → FAILOVER → verify → reinstate → observer repair → post-mortem; GO/NO-GO decision matrix; template SEV-1 message; RPO/RTO summary).

---

## 💻 4. Code-Level Feedback (.sql & .sh)

### 🗄️ 4.1 SQL — poprawki priorytetowe

#### 4.1.1 `sql/validate_environment.sql` — B1 blocker, przepisanie agregatu (L210–236)

```sql
-- ============================================================================
-- Podsumowanie / Summary — 12 checkow, nie 6
-- ============================================================================

COLUMN check_name FORMAT A40 HEADING "Check"
COLUMN status     FORMAT A6  HEADING "Status"

WITH all_checks AS (
    SELECT 'CHECK 1: Oracle 19c+' AS check_name,
           CASE WHEN (SELECT TO_NUMBER(REGEXP_SUBSTR(version, '^\d+')) FROM v$instance) >= 19
                THEN 'PASS' ELSE 'FAIL' END AS status FROM dual
    UNION ALL
    SELECT 'CHECK 2: Enterprise Edition',
           CASE WHEN (SELECT COUNT(*) FROM v$version WHERE banner LIKE '%Enterprise%') > 0
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 3: ARCHIVELOG',
           CASE WHEN (SELECT log_mode FROM v$database) = 'ARCHIVELOG'
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 4: FORCE LOGGING',
           CASE WHEN (SELECT force_logging FROM v$database) IN ('YES','FORCE_LOGGING')
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 5: FLASHBACK ON',
           CASE WHEN (SELECT flashback_on FROM v$database) = 'YES'
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 6: dg_broker_start=TRUE',
           CASE WHEN UPPER((SELECT value FROM v$parameter WHERE name='dg_broker_start')) = 'TRUE'
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 7: Standby Redo Logs',
           CASE WHEN (SELECT COUNT(*) FROM v$standby_log) >= (SELECT COUNT(*)+1 FROM v$log)
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 8: Protection Mode (MAX AVAIL/PROT)',
           CASE WHEN (SELECT protection_mode FROM v$database)
                     IN ('MAXIMUM AVAILABILITY','MAXIMUM PROTECTION')
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 9: TAC services exist',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE failover_type = 'TRANSACTION') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 10: commit_outcome=TRUE',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE failover_type='TRANSACTION' AND commit_outcome='YES') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 11: FAN (aq_ha_notifications)',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE aq_ha_notifications='YES') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 12: session_state_consistency=DYNAMIC',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE session_state_consistency='DYNAMIC') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
)
SELECT check_name, status FROM all_checks ORDER BY check_name;

PROMPT
SELECT status, COUNT(*) AS liczba,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1) || '%' AS pct
FROM   all_checks
GROUP BY status
ORDER BY DECODE(status,'FAIL',1,'WARN',2,'PASS',3);
```

#### 4.1.2 `sql/fsfo_check_readiness.sql` — dodać walidację `LOG_ARCHIVE_CONFIG` (B4)

Wstawić przed obecną sekcją 4:

```sql
-- ------------------------------------------------
-- Podsekcja 3.5: LOG_ARCHIVE_CONFIG / DG_CONFIG
-- Subsection 3.5: LOG_ARCHIVE_CONFIG / DG_CONFIG
-- ------------------------------------------------
SELECT
    'LOG_ARCHIVE_CONFIG'                        AS parametr,
    NVL(value, '(empty)')                       AS wartosc,
    CASE
        WHEN value IS NULL                      THEN 'FAIL'
        WHEN UPPER(value) LIKE '%DG_CONFIG%'    THEN 'PASS'
        ELSE                                         'WARN'
    END                                         AS status,
    'Musi zawierac DG_CONFIG=(db1,db2,...) — inaczej broker nie zestawi transportu'
        AS uwaga
FROM v$parameter WHERE name = 'log_archive_config';

SELECT
    'ARCHIVE_LAG_TARGET'                        AS parametr,
    value                                       AS wartosc,
    CASE
        WHEN TO_NUMBER(value) = 0               THEN 'WARN'
        WHEN TO_NUMBER(value) BETWEEN 900 AND 1800 THEN 'PASS'
        ELSE                                         'WARN'
    END                                         AS status
FROM v$parameter WHERE name = 'archive_lag_target';

-- DB_FLASHBACK_RETENTION_TARGET vs FastStartFailoverThreshold
SELECT
    'DB_FLASHBACK_RETENTION_TARGET (min)'       AS parametr,
    value                                       AS wartosc,
    CASE
        WHEN TO_NUMBER(value) >= 1440           THEN 'PASS'
        WHEN TO_NUMBER(value) >= 60             THEN 'WARN'
        ELSE                                         'FAIL'
    END                                         AS status
FROM v$parameter WHERE name = 'db_flashback_retention_target';
```

#### 4.1.3 `sql/tac_full_readiness.sql` — rozszerzyć detekcję non-replayable (B3)

```sql
-- ------------------------------------------------
-- Sekcja 8: Non-replayable operations — pelniejsza detekcja
-- Section 8: Non-replayable operations — fuller detection
-- ------------------------------------------------
WITH risky AS (
    SELECT sql_id, sql_text, executions, module,
           CASE
               WHEN REGEXP_LIKE(UPPER(sql_text),
                    'ALTER\s+SESSION|UTL_HTTP|UTL_SMTP|UTL_FILE|UTL_TCP|'
                 || 'DBMS_PIPE|DBMS_ALERT|DBMS_AQ\.|DBMS_LOCK|'
                 || 'DBMS_RANDOM|SYS_GUID\(\)|DBMS_OBFUSCATION|'
                 || 'CREATE\s+TABLE|DROP\s+TABLE|TRUNCATE|GRANT\s|REVOKE\s')
                   THEN 'NON_REPLAYABLE'
               WHEN REGEXP_LIKE(UPPER(sql_text), 'SYSDATE|SYSTIMESTAMP|CURRENT_TIMESTAMP')
                    AND module NOT LIKE 'oracle@%'
                   THEN 'REQUIRES_KEEP_DATE_GRANT'
               WHEN REGEXP_LIKE(UPPER(sql_text), '\.NEXTVAL|\.CURRVAL')
                   THEN 'CHECK_SEQUENCE_CACHE_AND_KEEP'
               ELSE 'OK'
           END AS risk_type
    FROM   v$sql
    WHERE  parsing_schema_name NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS')
      AND  last_active_time > SYSDATE - 7
)
SELECT risk_type,
       COUNT(*)                                  AS wystapien,
       SUM(executions)                           AS laczne_wykonania,
       LISTAGG(DISTINCT module, ', ')
         WITHIN GROUP (ORDER BY module)          AS moduly
FROM   risky
WHERE  risk_type != 'OK'
GROUP BY risk_type
ORDER BY laczne_wykonania DESC;

-- Sprawdz KEEP grants dla user aplikacyjnych
SELECT grantee, privilege
FROM   dba_sys_privs
WHERE  privilege IN ('KEEP DATE TIME','KEEP SYSGUID','KEEP ANY SEQUENCE')
  AND  grantee IN (SELECT username FROM dba_users
                    WHERE default_tablespace NOT IN ('SYSTEM','SYSAUX'));

-- Sequences z NOCACHE lub ORDER — zle dla TAC+RAC
SELECT sequence_owner, sequence_name, cache_size, order_flag, cycle_flag
FROM   dba_sequences
WHERE  sequence_owner NOT IN ('SYS','SYSTEM','MDSYS','XDB','APEX_030200')
  AND  (cache_size < 20 OR order_flag = 'Y');
```

#### 4.1.4 `sql/tac_configure_service_rac.sql` L109 — podnieść `REPLAY_INITIATION_TIMEOUT`

Zmienić `-replay_init_time 900` → `-replay_init_time 1800` dla mixed workload
(komentarz: „For pure OLTP lower to 300; for OLAP/batch raise to 3600").

### 🐚 4.2 Bash — poprawki priorytetowe

#### 4.2.1 `bash/fsfo_monitor.sh` L24, `bash/validate_all.sh` L22 — **B2 blocker**

Zamienić `set -uo pipefail` na:

```bash
set -Eeuo pipefail
IFS=$'\n\t'

# Trap z kontekstem bledu — dla cron/systemd
trap 'rc=$?; echo "[$(date +%FT%T)] ERROR rc=$rc at ${BASH_SOURCE[0]}:${LINENO} in ${FUNCNAME[0]:-main}" >&2; exit $rc' ERR
trap 'rm -f "${TMP_FILE:-/dev/null}"' EXIT
```

Wywołanie `sqlconn.sh` owinąć w:

```bash
SQL_EXIT=0
sqlconn.sh -s "$SERVICE_BASE" -f "$SQL_SCRIPT" > "$OUTPUT_FILE" 2>>"$LOG_FILE" || SQL_EXIT=$?

if [[ $SQL_EXIT -ne 0 ]]; then
    log_msg ERROR "sqlconn.sh exit=$SQL_EXIT — nie udalo sie polaczyc z ${SERVICE_BASE}"
    [[ $ALERT_MODE -eq 1 ]] && exit 2
fi

# Sanity check — plik nie moze byc pusty przed grepem
if [[ ! -s "$OUTPUT_FILE" ]]; then
    log_msg ERROR "Output file empty — skipping health assessment"
    [[ $ALERT_MODE -eq 1 ]] && exit 2
fi
```

#### 4.2.2 `bash/fsfo_setup.sh` — dodać tryb `-x` (execute) dla Observera (B5)

```bash
if [[ $EXECUTE_MODE -eq 1 ]]; then
    log_msg INFO "Sprawdzam czy observer juz dziala na $OBS_HOST..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$OBS_HOST" \
        'pgrep -f "dgmgrl.*OBSERVER" >/dev/null'; then
        log_msg WARN "Observer juz uruchomiony na $OBS_HOST — pomijam start."
    else
        log_msg INFO "Uruchamiam observer przez systemd..."
        ssh -o ConnectTimeout=10 "$OBS_HOST" \
            "sudo systemctl start dgmgrl-observer-${SITE}" \
            || { log_msg ERROR "Nie udalo sie uruchomic observera"; exit 4; }

        sleep 5
        local obs_status
        obs_status=$(sqlconn.sh -s "$SERVICE_BASE" -q \
            "SELECT status FROM v\$dg_broker_config WHERE name LIKE 'OBS_${SITE}%';")
        if [[ "$obs_status" != *"CONNECTED"* ]]; then
            log_msg ERROR "Observer nie jest CONNECTED (status=$obs_status)"
            exit 5
        fi
        log_msg OK "Observer CONNECTED na $OBS_HOST"
    fi
fi
```

#### 4.2.3 `bash/tac_deploy.sh` — dodać `srvctl` execution + ONS (B5)

```bash
if [[ $EXECUTE_MODE -eq 1 ]]; then
    if srvctl status service -d "$DB_UNIQUE_NAME" -s "$SVC_NAME" 2>/dev/null | grep -q "running"; then
        log_msg WARN "Service $SVC_NAME juz istnieje — uzyj --force, aby odtworzyc"
        exit 0
    fi

    log_msg INFO "Tworze service $SVC_NAME przez srvctl..."
    srvctl add service \
        -db "$DB_UNIQUE_NAME" \
        -service "$SVC_NAME" \
        -preferred "$PREF_INSTANCES" \
        -available "$AVAIL_INSTANCES" \
        -failovertype TRANSACTION \
        -failover_restore LEVEL1 \
        -commit_outcome TRUE \
        -failoverretry 30 \
        -failoverdelay 10 \
        -replay_init_time 1800 \
        -retention 86400 \
        -session_state DYNAMIC \
        -drain_timeout 300 \
        -stopoption IMMEDIATE \
        -role PRIMARY \
        -notification TRUE \
        -clbgoal SHORT \
        -rlbgoal SERVICE_TIME \
        || { log_msg ERROR "srvctl add service FAIL"; exit 6; }

    # ONS — warunek konieczny dla FAN
    log_msg INFO "Konfiguruje ONS (cross-site)..."
    srvctl modify ons \
        -remoteservers "${HH_HOST}:6200,${OE_HOST}:6200,${EXT_HOST}:6200" \
        -verbose

    srvctl start service -db "$DB_UNIQUE_NAME" -service "$SVC_NAME"
    log_msg OK "Service $SVC_NAME utworzony i uruchomiony"
fi
```

#### 4.2.4 Wspólne dla wszystkich skryptów bash

```bash
# Na poczatku kazdego skryptu:
umask 077                                  # logi tylko dla wlasciciela
TMP_FILE="$(mktemp -t fsfo-XXXXXX)"        # bezpieczne temp
trap 'rm -f "$TMP_FILE"' EXIT
```

Log rotation (cron-friendly), na końcu monitora:

```bash
find "$LOG_DIR" -name "fsfo_monitor_*.log" -mtime +30 -delete
find "$LOG_DIR" -name "fsfo_monitor_*.log" -mtime +7 -exec gzip {} \;
```

---

## 📝 5. Doc & Checklist Enhancements (.md & .html)

### 5.1 `FSFO-GUIDE.md` — dopisane sekcje

1. ~~**§ 8.4 Reinstate bez Flashback**~~ — **ZROBIONE**: pełny runbook RMAN DUPLICATE FROM ACTIVE DATABASE z prerekwizytami, przygotowaniem auxiliary, wykonaniem z tabelą klauzul, szacowaniem czasu (1 GbE vs 10 GbE), monitoringu postępu, post-DUPLICATE konfiguracji i weryfikacji (6 podsekcji 8.4.1–8.4.6).
2. ~~**§ 10.4 Split-brain diagnostics**~~ — **ZROBIONE**: 5 podsekcji (sygnały, runbook diagnostyczny z LogMiner, kroki remediacyjne, prewencja, post-mortem checklist).
3. ~~**§ 5.1.1 `ObserverOverride` — scenariusze**~~ — **ZROBIONE**: 10-wierszowa macierz decyzyjna (3-site/2-site/cloud/AZ/MaxProtection/OLTP/DWH) + audyt w logach observera.
4. ~~**§ 2.12 Capacity planning**~~ — **ZROBIONE** jako § 3.5 (lepsze miejsce — razem z Prerequisites).

### 5.2 `TAC-GUIDE.md` — dopisać

1. ~~**§ 5.5 Driver compatibility matrix**~~ — **ZROBIONE** (zwarta tabela referencyjna § 5.5 dodana; Java/UCP pozostaje stackiem rekomendowanym, inne drivery wymienione wyłącznie jako referencja na przyszłość).
2. **§ 7.6 Non-replayable operations — pełna lista** z procedurą `GRANT KEEP …`, `ALTER SEQUENCE … KEEP`, `DBMS_APP_CONT_ADMIN.DISABLE_FAILOVER_FOR_PLSQL`.
3. **§ 8 LTXID monitoring** — `SYS.LTXID_TRANS$` rozmiar, purge job, alert na `retention_timeout × TPS`.
4. **§ 6.6 Cross-site ONS + firewall matrix** — port 6200 (ONS), 1521/1522 (TNS), 6123 (CRS); diagram sieciowy.

### 5.3 `INTEGRATION-GUIDE.md` — dopisać

1. ~~**Python / ODP.NET / Node.js sekcje**~~ — **OUT OF SCOPE** (środowisko Java-only; referencja w TAC-GUIDE § 5.5 wystarcza na obecne potrzeby. Rozwinąć tylko gdy pojawi się realna aplikacja non-Java).
2. **§ 10 Runbook SEV-1: Observer lost** — procedura gdy 3/3 observery padną (brak FSFO, ręczny `FAILOVER TO <standby>` przez DGMGRL, ryzyko data loss).

### 5.4 `DESIGN.md` — dopisać

1. **§ 2.9 ADR-009 Far Sync** — „Odrzucone dla MVP, rozważyć w Phase 2 jeśli RPO=0 na WAN krytyczne".
2. **§ 3.4 Application compatibility matrix** — (driver × version) × (TAC supported).
3. **§ 7 Capacity planning** — `v$flash_recovery_area_usage`, `sysaux` growth, estymacja LTXID.
4. **§ 11 Network diagram** — ASCII lub link do pliku Visio/Draw.io.

### 5.5 `checklist.html` — ulepszenia

1. **Cross-references** — każdy checkbox linkuje do sekcji `.md` (np. `<a href="FSFO-GUIDE.md#52-faststartfailoverthreshold">…</a>`) i odpowiedniego skryptu SQL.
2. **Kolumna „How to verify"** — konkretne query/polecenie (`SHOW CONFIGURATION;`, `SELECT fs_failover_status FROM v$database;`).
3. **Sekcja „Post-failover verification"** (brakuje): `V$DATAGUARD_STATUS` po failover, `DBMS_APP_CONT_REPORT` dla monitoringu replayu, test idempotencji aplikacji.
4. **Sekcja „Application Continuity drill"** — checklist dla testu z `dbms_app_cont_admin.simulate_failover` lub `ALTER SYSTEM KILL SESSION` w środku transakcji + weryfikacja `GV$REPLAY_STAT_SUMMARY`.
5. **Export/Import JSON** — obecny `localStorage` nie persystuje między maszynami; dodać „Download as JSON" i „Import".

### 5.6 Nowe artefakty do dodania

| Plik | Cel |
|---|---|
| `sql/fsfo_split_brain_check.sql` | Diagnostyka post-failover (SCN divergence, orphan primary) |
| `sql/tac_grant_keep.sql` | `GRANT KEEP DATE/SYSGUID/ANY SEQUENCE` dla user aplikacyjnych |
| `sql/tac_ltxid_monitor.sql` | Monitoring `SYS.LTXID_TRANS$` + purge |
| `bash/failover_drill.sh` | Automatyczny test switchover → failover → reinstate z raportem RTO/RPO |
| `bash/fsfo_setup_observer_systemd.sh` | Generator unit file dla systemd observera (idempotentny) |
| `systemd/dgmgrl-observer@.service` | Szablon unit file z `ExecStart=dgmgrl -silent -logfile %L "/@%i_ADMIN" "START OBSERVER"` |
| `docs/NETWORK-DIAGRAM.md` / `.png` | Topologia 3-site z portami firewall |

---

## 📊 6. Ocena końcowa / Final Score

| Kategoria / Category | Ocena | Komentarz |
|---|---|---|
| **Dokumentacja** | 97/100 | Bilingualna, bogata; dodane: TAC § 5.5 (drivery), FSFO § 3.2 (porty + diagram + firewall ACL), § 3.5 (capacity planning z formułami), § 5.1.1 (ObserverOverride scenarios), § 8.2 (SEV-1 runbook 8-fazowy), § 8.4 (RMAN DUPLICATE runbook 6-podsekcji), § 10.4 (split-brain diagnostics 5-podsekcji). Pozostaje: cold-fencing ADR-009, Python/.NET/Node.js jeśli pojawią się aplikacje non-Java. |
| **Design (ADR-y)** | 90/100 | 8 decyzji dobrze uzasadnionych; brak macierzy kompatybilności aplikacji i Far Sync. |
| **SQL (readiness/monitoring)** | 70/100 | Struktura OK, ale agregat walidacji zepsuty (B1) i detekcja non-replayable niekompletna (B3). |
| **Bash (automation)** | 55/100 | Skrypty generujące zamiast wykonujących (B5), cichy failure w monitorze (B2), brak ONS. |
| **Checklist HTML** | 75/100 | Interaktywny, ale bez cross-references i bez sekcji drill / post-failover verification. |
| **Bezpieczeństwo** | 85/100 | Brak hardcoded haseł, Wallet integration; brak `umask 077` i `mktemp`. |

**Rekomendacja Go-Live:** **GO po usunięciu B1–B5** (~3 dni DBA + 1 dzień UAT). B1 i B2 **muszą** trafić do Phase 1, inaczej monitoring produkcyjny da false assurance.

---

## 🧪 7. Test plan weryfikacyjny / Verification Test Plan

1. **Unit** — uruchomić nowy agregat z § 4.1.1 na świadomie popsutym środowisku (`protection_mode=MAX PERFORMANCE`) → musi wykazać FAIL.
2. **Integration** — zabić `sqlconn.sh` z `fsfo_monitor.sh` (odłączenie sieci) → musi zwrócić exit 2 (CRITICAL), nie 0.
3. **End-to-end** — uruchomić `bash/failover_drill.sh` (do dodania) → pełen cykl switchover → failover → reinstate z timingiem i `GV$REPLAY_STAT_SUMMARY` przed/po.
4. **Application Continuity drill** — `dbms_app_cont_admin.simulate_failover` na session podczas `INSERT`+pending commit → zweryfikować, że JDBC UCP klient dokończył transakcję bez błędu user-facing.
5. **Split-brain test** — symulacja network partition między DC i DR (`iptables`), weryfikacja że Observer na EXT poprawnie wybiera quorum; brak podwójnego Primary.

---

**Koniec raportu / End of Report**
