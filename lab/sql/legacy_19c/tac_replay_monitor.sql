-- ==============================================================================
-- Tytul:        tac_replay_monitor.sql
-- Opis:         Monitoring TAC replay: statystyki, sesje w replay, alerty.
--               6 sekcji: global stats, per-service, per-session, failed replays,
--               non-replayable SQL, trend 24h
-- Description [EN]: TAC replay monitoring: statistics, sessions in replay, alerts.
--                   6 sections: global stats, per-service, per-session, failed replays,
--                   non-replayable SQL, 24h trend
--
-- Autor:        KCB Kris
-- Data:         2026-04-23
-- Wersja:       1.0
--
-- Wymagania [PL]:    - Oracle 19c+ EE z dzialajacym TAC
--                    - Rola SELECT_CATALOG_ROLE
-- Requirements [EN]: - Oracle 19c+ EE with active TAC
--                    - SELECT_CATALOG_ROLE
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
-- SEKCJA 1: Global replay statistics / Section 1: Global replay stats
-- ============================================================================

PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 1 / SECTION 1: Globalne statystyki replay (GV$REPLAY_STAT_SUMMARY)
PROMPT --------------------------------------------------------------------------------

COLUMN inst_id             FORMAT 999      HEADING "Inst"
COLUMN requests_total      FORMAT 99999999 HEADING "Wszystkie"
COLUMN requests_replayed   FORMAT 99999999 HEADING "Replay OK"
COLUMN requests_failed     FORMAT 99999999 HEADING "Replay Fail"
COLUMN requests_disabled   FORMAT 99999999 HEADING "Disabled"
COLUMN pct_success         FORMAT 999.9    HEADING "Success %"
COLUMN ocena_tac           FORMAT A10      HEADING "Ocena"

SELECT inst_id,
       requests_total,
       requests_replayed,
       requests_failed,
       requests_disabled,
       CASE WHEN requests_total > 0
            THEN ROUND(requests_replayed * 100 / requests_total, 1)
            ELSE 0 END                                  AS pct_success,
       CASE
           WHEN requests_total = 0 THEN 'IDLE'
           WHEN requests_replayed * 100 / requests_total >= 95 THEN 'PASS'
           WHEN requests_replayed * 100 / requests_total >= 80 THEN 'WARN'
           ELSE 'CRIT'
       END                                              AS ocena_tac
FROM   gv$replay_stat_summary
ORDER  BY inst_id;

-- Progi zgodne z DESIGN.md sek. 7.4:
--   PASS (success >= 95%), WARN (80-95%), CRIT (<80%)

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
PROMPT ================================================================================
