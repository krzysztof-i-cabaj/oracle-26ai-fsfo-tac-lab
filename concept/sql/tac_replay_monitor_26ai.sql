-- ==============================================================================
-- Tytul:        tac_replay_monitor_26ai.sql
-- Opis:         26ai-specific variant tac_replay_monitor.sql.
--               Patch sekcja 1: GV$REPLAY_STAT_SUMMARY usuniety w 23ai/26ai
--               -> agregacja per-instance z GV$REPLAY_CONTEXT (per-context view).
--               Sekcje 2-6 identyczne z oryginalem.
-- Description [EN]: 26ai-specific variant. Section 1 patched: GV$REPLAY_STAT_SUMMARY
--                   removed in 23ai/26ai -> aggregation from GV$REPLAY_CONTEXT.
--
-- Autor:        KCB Kris
-- Data:         2026-04-27
-- Wersja:       1.0 (FIX-082, baza: oryginal tac_replay_monitor.sql v1.0)
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
