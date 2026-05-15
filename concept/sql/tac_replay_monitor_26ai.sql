-- ==============================================================================
-- Tytul:        tac_replay_monitor_26ai.sql
-- Opis:         26ai-specific variant tac_replay_monitor.sql (7 sekcji).
--               Sekcja 1: GV$REPLAY_STAT_SUMMARY usuniety w 23ai/26ai
--               -> agregacja per-instance z GV$REPLAY_CONTEXT (per-context view).
--               Sekcja 7: ACCHK protection coverage (26ai / 19.11+) — mierzy %
--               requestow chronionych przez TAC (DBA_ACCHK_* views).
-- Description [EN]: 26ai-specific variant. Section 1 patched: GV$REPLAY_STAT_SUMMARY
--                   removed in 23ai/26ai -> aggregation from GV$REPLAY_CONTEXT.
--                   Section 7: ACCHK protection coverage (% protected via DBA_ACCHK_*).
--
-- Autor:        KCB Kris
-- Data:         2026-04-27
-- Wersja:       1.1
--
-- Zmiany v1.0 (2026-04-27, FIX-082):
--   - Bazuje na oryginale tac_replay_monitor.sql v1.0.
--   - Sekcja 1: zastapiono SELECT FROM gv$replay_stat_summary agregacja per-inst_id
--     z gv$replay_context. Status logic: IDLE/PASS/WARN.
--
-- Zmiany v1.1 (2026-05-15):
--   - Dodano SEKCJA 7: ACCHK protection coverage.
--   - 7.0: preflight check (czy widoki ACCHK istnieja).
--   - 7.1: overall protection summary (DBA_ACCHK_STATISTICS_SUMMARY).
--   - 7.2: event types breakdown (DBA_ACCHK_EVENTS group by event_type/error_code).
--   - 7.3: top problematic services/modules (DBA_ACCHK_EVENTS).
--   - Wymagana procedura: EXEC dbms_app_cont_admin.acchk_views() (jednorazowo)
--     + EXEC dbms_app_cont_admin.acchk_set(true, <sec>) przed pomiarem.
--   - Patrz docs/TAC-GUIDE.md sekcja 9 (workflow ACCHK + 26ai-only TAC features).
--
-- Wymagania [PL]:    - Oracle 19c+ EE z dzialajacym TAC (sekcje 1-6)
--                    - Sekcja 7: Oracle 19.11+ z utworzonymi widokami ACCHK
--                    - Rola SELECT_CATALOG_ROLE (lub _ACCHK_READ_ dla sekcji 7)
-- Requirements [EN]: - Oracle 19c+ EE with active TAC (sections 1-6)
--                    - Section 7: Oracle 19.11+ with ACCHK views created
--                    - SELECT_CATALOG_ROLE (or _ACCHK_READ_ for section 7)
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -f sql/tac_replay_monitor.sql -o reports/tac_$(date +%Y%m%d_%H%M).txt
-- Usage [EN]:        sqlconn.sh -s PRIM -f sql/tac_replay_monitor.sql -o reports/tac_$(date +%Y%m%d_%H%M).txt
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    TAC Replay Monitor
PROMPT ================================================================================
PROMPT

-- ============================================================================
-- SEKCJA 1: Global replay statistics / Section 1: Global replay stats — 26ai variant
-- ============================================================================
-- W 26ai GV$REPLAY_STAT_SUMMARY zostal usuniety. Zastapiony per-context views.
-- Agregujemy per-instance z GV$REPLAY_CONTEXT po SUM(*_VALUES_CAPTURED/REPLAYED).
-- Status logic (rozni sie od 19c bo brak total/failed counts):
--   IDLE = no active contexts = brak ruchu replay
--   PASS = wszystkie *_REPLAYED >= *_CAPTURED (100% per category)
--   WARN = jakas kategoria *_REPLAYED < *_CAPTURED (partial)
-- (CRIT przeniesione do alert log scan w sekcji 4.)

PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 1 / SECTION 1: Globalne statystyki replay (GV$REPLAY_CONTEXT — 26ai)
PROMPT --------------------------------------------------------------------------------

COLUMN inst_id              FORMAT 999      HEADING "Inst"
COLUMN active_contexts      FORMAT 99999    HEADING "Active|Ctx"
COLUMN seq_capt             FORMAT 99999999 HEADING "Seq|Capt"
COLUMN seq_repl             FORMAT 99999999 HEADING "Seq|Repl"
COLUMN sd_capt              FORMAT 99999999 HEADING "SysDate|Capt"
COLUMN sd_repl              FORMAT 99999999 HEADING "SysDate|Repl"
COLUMN sg_capt              FORMAT 99999999 HEADING "SysGUID|Capt"
COLUMN sg_repl              FORMAT 99999999 HEADING "SysGUID|Repl"
COLUMN lobs_capt            FORMAT 99999999 HEADING "LOBs|Capt"
COLUMN lobs_repl            FORMAT 99999999 HEADING "LOBs|Repl"
COLUMN ocena_tac            FORMAT A6       HEADING "Ocena"

WITH agg AS (
    SELECT inst_id,
           COUNT(*)                                 AS active_contexts,
           NVL(SUM(sequence_values_captured),0)     AS seq_capt,
           NVL(SUM(sequence_values_replayed),0)     AS seq_repl,
           NVL(SUM(sysdate_values_captured),0)      AS sd_capt,
           NVL(SUM(sysdate_values_replayed),0)      AS sd_repl,
           NVL(SUM(sysguid_values_captured),0)      AS sg_capt,
           NVL(SUM(sysguid_values_replayed),0)      AS sg_repl,
           NVL(SUM(lobs_captured),0)                AS lobs_capt,
           NVL(SUM(lobs_replayed),0)                AS lobs_repl
    FROM   gv$replay_context
    GROUP  BY inst_id
)
SELECT inst_id, active_contexts,
       seq_capt, seq_repl,
       sd_capt,  sd_repl,
       sg_capt,  sg_repl,
       lobs_capt, lobs_repl,
       CASE
         WHEN seq_capt + sd_capt + sg_capt + lobs_capt = 0 THEN 'IDLE'
         WHEN seq_repl >= seq_capt
          AND sd_repl  >= sd_capt
          AND sg_repl  >= sg_capt
          AND lobs_repl >= lobs_capt                       THEN 'PASS'
         ELSE 'WARN'
       END                                                 AS ocena_tac
FROM   agg
ORDER  BY inst_id;

-- W 26ai progi: PASS (wszystkie kategorie 100% replay), WARN (jakas <100%).
-- CRIT (failed replays count) - brak agregowanego widoku w 26ai;
-- patrz sekcja 4 (alert log scan dla REPLAY%FAIL i LTXID).

-- ============================================================================
-- SEKCJA 2: Per-service replay stats / Section 2: Per-service replay stats
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 2 / SECTION 2: Per-service replay statistics
PROMPT --------------------------------------------------------------------------------

COLUMN service_name FORMAT A25 HEADING "Service"
COLUMN metric_name  FORMAT A40 HEADING "Metryka"
COLUMN metric_value FORMAT 99999999 HEADING "Wartosc"

-- GV$SERVICES_STATS moze nie byc dostepny na wszystkich 19c; ponizej
-- agregat z V$SERVICES + GV$SESSION sampling
SELECT
    ds.name                         AS service_name,
    'Aktywnych sesji / Active sessions'       AS metric_name,
    COUNT(gs.sid)                   AS metric_value
FROM   dba_services ds
LEFT   JOIN gv$session gs ON gs.service_name = ds.name AND gs.type = 'USER'
WHERE  ds.name NOT LIKE 'SYS%'
  AND  ds.name NOT LIKE '%XDB%'
  AND  ds.failover_type IN ('TRANSACTION','SELECT')
GROUP  BY ds.name
UNION ALL
SELECT
    ds.name,
    'Sesje failed_over=YES / Replayed sessions',
    COUNT(CASE WHEN gs.failed_over = 'YES' THEN 1 END)
FROM   dba_services ds
LEFT   JOIN gv$session gs ON gs.service_name = ds.name AND gs.type = 'USER'
WHERE  ds.name NOT LIKE 'SYS%'
  AND  ds.name NOT LIKE '%XDB%'
  AND  ds.failover_type IN ('TRANSACTION','SELECT')
GROUP  BY ds.name
ORDER  BY 1, 2;

-- ============================================================================
-- SEKCJA 3: Sesje w trakcie replay lub po replay / Section 3: Sessions in replay
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 3 / SECTION 3: Sesje w trakcie / po replay
PROMPT --------------------------------------------------------------------------------

COLUMN inst_id       FORMAT 999    HEADING "Inst"
COLUMN sid           FORMAT 99999  HEADING "SID"
COLUMN serial#       FORMAT 999999 HEADING "Serial#"
COLUMN username      FORMAT A15    HEADING "User"
COLUMN service_name  FORMAT A20    HEADING "Service"
COLUMN failover_type FORMAT A10    HEADING "FO type"
COLUMN failed_over   FORMAT A5     HEADING "Done?"
COLUMN module        FORMAT A30    HEADING "Module"

SELECT inst_id,
       sid,
       serial#,
       username,
       service_name,
       failover_type,
       failed_over,
       module
FROM   gv$session
WHERE  (failover_type IS NOT NULL AND failover_type <> 'NONE')
   OR  failed_over = 'YES'
ORDER  BY inst_id, sid;

PROMPT
PROMPT (Jesli 0 rows = brak sesji z TAC context; mozliwe ze nie bylo niedawno failovera)

-- ============================================================================
-- SEKCJA 4: Failed replays - alert log ostatnie 24h
-- Section 4: Failed replays from alert log (last 24h)
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 4 / SECTION 4: Failed replays (alert log ostatnie 24h)
PROMPT --------------------------------------------------------------------------------

COLUMN ts                 FORMAT A20 HEADING "Czas"
COLUMN inst_id            FORMAT 999 HEADING "Inst"
COLUMN component_id       FORMAT A15 HEADING "Component"
COLUMN message_text       FORMAT A120 HEADING "Message"

SELECT inst_id,
       TO_CHAR(originating_timestamp, 'YYYY-MM-DD HH24:MI:SS') AS ts,
       component_id,
       SUBSTR(message_text, 1, 120)                            AS message_text
FROM   gv$diag_alert_ext
WHERE  originating_timestamp > SYSDATE - 1
  AND (UPPER(message_text) LIKE '%REPLAY%FAIL%'
       OR UPPER(message_text) LIKE '%ORA-25408%'
       OR UPPER(message_text) LIKE '%ORA-03113%'
       OR UPPER(message_text) LIKE '%LTXID%'
       OR UPPER(message_text) LIKE '%NON-REPLAYABLE%')
ORDER  BY originating_timestamp DESC
FETCH  FIRST 50 ROWS ONLY;

PROMPT
PROMPT (Jesli 0 rows = brak bledow replay w ostatnich 24h — super!)

-- ============================================================================
-- SEKCJA 5: Non-replayable SQL w trafficu / Section 5: Non-replayable SQL
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 5 / SECTION 5: Potencjalnie nie-replayowalne SQL (ostatnie 7 dni)
PROMPT --------------------------------------------------------------------------------

COLUMN sql_id       FORMAT A15 HEADING "SQL_ID"
COLUMN executions   FORMAT 999999999 HEADING "Execs"
COLUMN sql_tekst    FORMAT A80 HEADING "SQL_TEXT (trimmed)"
COLUMN ryzyko       FORMAT A22 HEADING "Ryzyko"

SELECT sql_id,
       executions,
       SUBSTR(sql_text, 1, 80)             AS sql_tekst,
       CASE
         WHEN UPPER(sql_text) LIKE '%ALTER SESSION%' THEN 'ALTER SESSION w TX'
         WHEN UPPER(sql_text) LIKE '%UTL_HTTP%'      THEN 'UTL_HTTP (external)'
         WHEN UPPER(sql_text) LIKE '%UTL_SMTP%'      THEN 'UTL_SMTP (external)'
         WHEN UPPER(sql_text) LIKE '%UTL_FILE%'      THEN 'UTL_FILE (I/O)'
         WHEN UPPER(sql_text) LIKE '%DBMS_PIPE%'     THEN 'DBMS_PIPE (messaging)'
         WHEN UPPER(sql_text) LIKE '%DBMS_ALERT%'    THEN 'DBMS_ALERT (messaging)'
         ELSE 'OK'
       END                                 AS ryzyko
FROM   v$sql
WHERE  executions > 10
  AND  last_active_time > SYSDATE - 7
  AND (UPPER(sql_text) LIKE '%ALTER SESSION%'
       OR UPPER(sql_text) LIKE '%UTL_HTTP%'
       OR UPPER(sql_text) LIKE '%UTL_SMTP%'
       OR UPPER(sql_text) LIKE '%UTL_FILE%'
       OR UPPER(sql_text) LIKE '%DBMS_PIPE%'
       OR UPPER(sql_text) LIKE '%DBMS_ALERT%')
ORDER  BY executions DESC
FETCH  FIRST 20 ROWS ONLY;

PROMPT
PROMPT (Executions > 10 w ostatnich 7 dniach; przejrzyj kod aplikacji aby przeniesc
PROMPT  zewnetrzne wywolania POZA transakcje.)

-- ============================================================================
-- SEKCJA 6: Trend 24h (ASH) - wymaga Diagnostic Pack
-- Section 6: 24h trend (ASH) - requires Diagnostic Pack
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 6 / SECTION 6: Trend 24h (ASH, wymagany Diagnostic Pack)
PROMPT --------------------------------------------------------------------------------

COLUMN hour_bucket  FORMAT A20 HEADING "Godzina"
COLUMN liczba_sesji FORMAT 99999 HEADING "Sesje aktywne"
COLUMN liczba_replay FORMAT 99999 HEADING "Sesje w replay"

-- Heurystyka: session_type=FOREGROUND, sample_time w ostatnich 24h
-- Bez Diagnostic Pack query zwroci brak dostepu (ORA-942)
SELECT TO_CHAR(TRUNC(sample_time, 'HH'), 'YYYY-MM-DD HH24":00"') AS hour_bucket,
       COUNT(DISTINCT session_id || ',' || session_serial#)       AS liczba_sesji,
       COUNT(DISTINCT CASE WHEN consumer_group_id IS NOT NULL
                           THEN session_id || ',' || session_serial# END) AS liczba_replay
FROM   v$active_session_history
WHERE  sample_time > SYSDATE - 1
  AND  session_type = 'FOREGROUND'
GROUP  BY TRUNC(sample_time, 'HH')
ORDER  BY hour_bucket DESC
FETCH  FIRST 24 ROWS ONLY;

PROMPT
PROMPT (Jesli brak wynikow / ORA-00942 = brak Diagnostic Pack licensing)

-- ============================================================================
-- SEKCJA 7: ACCHK — TAC Protection Coverage (26ai / 19.11+)
-- Section 7: ACCHK — measures % of requests protected by TAC
-- ============================================================================
-- ACCHK (Application Continuity Check) jest narzedziem post-processing ktore
-- mierzy % requestow chronionych przez TAC. Widoki DBA_ACCHK_* nie sa tworzone
-- domyslnie — wymagaja jednorazowego:
--   EXEC dbms_app_cont_admin.acchk_views();           -- tworzy widoki + role
-- A pomiar:
--   EXEC dbms_app_cont_admin.acchk_set(true, 3600);   -- on (timeout 1h)
--   -- ...workload...
--   EXEC dbms_app_cont_admin.acchk_set(false);        -- off
--   EXEC dbms_app_cont_report.acchk_report();         -- raport
-- Sekcja 7 dziala niezaleznie od pomiaru — czyta tylko historyczne dane.
-- Preflight (7.0) wykrywa brak widokow i pokazuje instrukcje.
-- Wartosci EVENT_TYPE: DISABLED, NEVER ENABLED, NOT ENABLING, REPLAY FAILED.

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 7 / SECTION 7: ACCHK protection coverage (26ai / 19.11+)
PROMPT --------------------------------------------------------------------------------

-- 7.0 Preflight: czy widoki ACCHK istnieja
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
    v_exists NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_exists
      FROM all_views
     WHERE view_name = 'DBA_ACCHK_EVENTS';

    IF v_exists = 0 THEN
        DBMS_OUTPUT.PUT_LINE('========================================================================');
        DBMS_OUTPUT.PUT_LINE(' INFO: Widoki ACCHK nie sa utworzone w tej bazie.');
        DBMS_OUTPUT.PUT_LINE(' Aby wlaczyc pomiar protection coverage, uruchom jednorazowo:');
        DBMS_OUTPUT.PUT_LINE('   EXEC dbms_app_cont_admin.acchk_views();');
        DBMS_OUTPUT.PUT_LINE(' A nastepnie kazdy pomiar:');
        DBMS_OUTPUT.PUT_LINE('   EXEC dbms_app_cont_admin.acchk_set(true, 3600);');
        DBMS_OUTPUT.PUT_LINE('   -- wykonaj reprezentatywny workload --');
        DBMS_OUTPUT.PUT_LINE('   EXEC dbms_app_cont_admin.acchk_set(false);');
        DBMS_OUTPUT.PUT_LINE(' Patrz docs/TAC-GUIDE.md (sekcja 9.4) dla pelnego workflow.');
        DBMS_OUTPUT.PUT_LINE(' Skipping sections 7.1-7.3.');
        DBMS_OUTPUT.PUT_LINE('========================================================================');
    ELSE
        DBMS_OUTPUT.PUT_LINE('ACCHK views OK — wynik nizej (jesli puste = brak zebranych danych ACCHK).');
    END IF;
END;
/
SET SERVEROUTPUT OFF

-- 7.1 Overall protection summary (DBA_ACCHK_STATISTICS_SUMMARY)
-- Kolumny widoku zaleza od release update (19.11 wprowadza, kolejne RU dodaja pola).
-- SELECT * daje pelny obraz niezaleznie od wersji.
PROMPT
PROMPT 7.1 Overall protection summary (dba_acchk_statistics_summary):
SELECT * FROM dba_acchk_statistics_summary;

-- 7.2 Event types breakdown
COLUMN event_type    FORMAT A18 HEADING "Event type"
COLUMN error_code    FORMAT 99999 HEADING "ORA"
COLUMN liczba_evt    FORMAT 999999 HEADING "Liczba"
COLUMN ocena_evt     FORMAT A6 HEADING "Ocena"

PROMPT
PROMPT 7.2 Event types breakdown (dba_acchk_events):
SELECT
    event_type,
    error_code,
    COUNT(*) AS liczba_evt,
    CASE
        WHEN event_type = 'REPLAY FAILED'  THEN 'CRIT'
        WHEN event_type = 'NEVER ENABLED'  THEN 'WARN'
        WHEN event_type = 'NOT ENABLING'   THEN 'WARN'
        WHEN event_type = 'DISABLED'       THEN 'INFO'
        ELSE 'INFO'
    END AS ocena_evt
FROM   dba_acchk_events
GROUP  BY event_type, error_code
ORDER  BY liczba_evt DESC
FETCH  FIRST 20 ROWS ONLY;

PROMPT
PROMPT (Brak wierszy = brak zebranych eventow ACCHK. EVENT_TYPE rozszyfrowanie:
PROMPT   DISABLED      = AC swiadomie wylaczone w sesji (nie problem per se)
PROMPT   NEVER ENABLED = sesja nie miala AC od poczatku (sprawdz service config)
PROMPT   NOT ENABLING  = AC nie moglo sie wlaczyc (warunki srodowiskowe)
PROMPT   REPLAY FAILED = byla proba replay ale sie nie udala (krytyczne).)

-- 7.3 Top problematic services/modules
COLUMN service_acchk  FORMAT A22 HEADING "Service"
COLUMN module_acchk   FORMAT A30 HEADING "Modul"
COLUMN event_t_acchk  FORMAT A16 HEADING "Event type"

PROMPT
PROMPT 7.3 Top problematic services/modules (dba_acchk_events, ostatnie 7 dni):
SELECT
    service_name AS service_acchk,
    module       AS module_acchk,
    event_type   AS event_t_acchk,
    COUNT(*)     AS liczba_evt
FROM   dba_acchk_events
WHERE  event_type IN ('DISABLED','NEVER ENABLED','NOT ENABLING','REPLAY FAILED')
  AND  timestamp > SYSTIMESTAMP - INTERVAL '7' DAY
GROUP  BY service_name, module, event_type
ORDER  BY liczba_evt DESC
FETCH  FIRST 15 ROWS ONLY;

PROMPT
PROMPT (Top modules z 'NEVER ENABLED' = obszary aplikacji ktore wcale nie korzystaja
PROMPT  z TAC. Skoreluj z TAC-GUIDE.md sekcja 4 — service configuration check.)

-- ============================================================================
-- Podsumowanie / Summary
-- ============================================================================

PROMPT
PROMPT ================================================================================
PROMPT  TAC Replay Monitor - interpretacja / interpretation:
PROMPT
PROMPT    Section 1 (global stats):
PROMPT      PASS  = success rate >= 95% (zdrowe)
PROMPT      WARN  = 80-95% (app design issue — przejrzyj failed replays)
PROMPT      CRIT  = < 80% (non-replayable ops lub network issues)
PROMPT
PROMPT    Section 4 (alert log):
PROMPT      0 rows = zadnych bledow replay w ostatnich 24h (idealnie)
PROMPT      > 0    = przejrzyj kazdy event + koreluj z Section 5
PROMPT
PROMPT    Section 5 (non-replayable SQL):
PROMPT      0 rows    = app code zgodny z TAC best practices
PROMPT      > 0 rows  = zglos app teamowi refactoring
PROMPT
PROMPT    Section 7 (ACCHK protection coverage, 26ai / 19.11+):
PROMPT      7.1 protected % >= 95 = TAC pokrywa wiekszosc ruchu
PROMPT      7.2 REPLAY FAILED > 0 = krytyczne — przejrzyj error_code
PROMPT      7.3 NEVER ENABLED top = service config nie wlacza TAC dla tych modulow
PROMPT ================================================================================
