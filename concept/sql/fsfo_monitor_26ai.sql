-- ==============================================================================
-- Tytul:        fsfo_monitor_26ai.sql
-- Opis:         Ciagly monitoring stanu FSFO i TAC (8 sekcji) — 23ai/26ai variant.
--               Sekcja 7: GV$REPLAY_STAT_SUMMARY usuniety w 23ai/26ai
--               -> agregacja per-instance z GV$REPLAY_CONTEXT (per-context view
--               dla sequences, sysdate, sysguid, lobs values captured/replayed).
--               Sekcja 8: 26ai-only Broker views (V$FAST_START_FAILOVER_CONFIG,
--               V$DG_BROKER_PROPERTY, V$DG_BROKER_ROLE_CHANGE, V$FS_LAG_HISTOGRAM).
-- Description [EN]: 26ai-specific variant. Section 7 patched: GV$REPLAY_STAT_SUMMARY
--               removed in 23ai/26ai -> aggregation from GV$REPLAY_CONTEXT.
--               Section 8: 26ai-only Broker views (config snapshot, properties,
--               role change audit, lag histogram).
--
-- Autor:        KCB Kris
-- Data:         2026-04-27
-- Wersja:       1.1
--
-- Zmiany v1.0 (2026-04-27, FIX-090):
--   - Bazuje na fsfo_monitor.sql v1.0 (2026-04-23).
--   - Sekcja 7: zastapiono SELECT FROM gv$replay_stat_summary agregacja per-inst_id
--     z gv$replay_context. Status logic: IDLE/PASS/WARN.
--   - Reszta skryptu bit-identyczna z fsfo_monitor.sql.
--
-- Zmiany v1.1 (2026-05-15):
--   - Dodano SEKCJA 8: 26ai-specific Broker views.
--   - 8.1: V$FAST_START_FAILOVER_CONFIG — jednowierszowy snapshot konfig+status.
--   - 8.2: V$DG_BROKER_PROPERTY — broker properties z kontekstem MEMBER/SCOPE.
--   - 8.3: V$DG_BROKER_ROLE_CHANGE — audit ostatnich 10 zmian roli (zastepuje
--          parsowanie alert.log dla switchover/failover).
--   - 8.4: V$FS_LAG_HISTOGRAM — rozklad lag failover w czasie (SLA analysis).
--   - Kolumny zweryfikowane wg Oracle Database Reference 23ai (refrn/).
--
-- Wymagania [PL]:    - Oracle 23ai/26ai EE z wlaczonym DG Broker i FSFO
--                    - Rola SELECT_CATALOG_ROLE
--                    - Sekcja 7 wymaga obecnosci replay contexts (po replayach)
-- Requirements [EN]: - Oracle 23ai/26ai EE with DG Broker and FSFO enabled
--                    - SELECT_CATALOG_ROLE
--                    - Section 7 requires replay contexts (after replays)
--
-- Uzycie [PL]:       sqlplus -s / as sysdba @sql/fsfo_monitor_26ai.sql > reports/fsfo_$(date +%Y%m%d_%H%M).log
-- Usage [EN]:        sqlplus -s / as sysdba @sql/fsfo_monitor_26ai.sql > reports/fsfo_$(date +%Y%m%d_%H%M).log
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    FSFO + TAC Health Monitor (26ai variant)
PROMPT    Data/Date: sysdate
PROMPT ================================================================================
PROMPT

-- ============================================================================
-- SEKCJA 1: Broker status / Section 1: Broker status
-- ============================================================================

PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 1 / SECTION 1: Broker status
PROMPT --------------------------------------------------------------------------------

COLUMN metryka FORMAT A38 HEADING "Metryka / Metric"
COLUMN wartosc FORMAT A50 HEADING "Wartosc / Value"
COLUMN ocena   FORMAT A8  HEADING "Ocena"

SELECT * FROM (
    SELECT 1 AS ord, 'DB Unique Name'             AS metryka, db_unique_name     AS wartosc,
           'INFO' AS ocena FROM v$database
    UNION ALL SELECT 2, 'Database role',       database_role,                  'INFO'           FROM v$database
    UNION ALL SELECT 3, 'Protection mode',     protection_mode,                CASE WHEN protection_mode = 'MAXIMUM AVAILABILITY' THEN 'PASS' ELSE 'WARN' END FROM v$database
    UNION ALL SELECT 4, 'Protection level',    protection_level,               'INFO'           FROM v$database
    UNION ALL SELECT 5, 'Open mode',           open_mode,                      'INFO'           FROM v$database
    UNION ALL SELECT 6, 'Switchover status',   switchover_status,              CASE WHEN switchover_status IN ('TO STANDBY','TO PRIMARY','RESOLVABLE GAP','NOT ALLOWED') THEN 'INFO' ELSE 'WARN' END FROM v$database
)
ORDER BY ord;

-- ============================================================================
-- SEKCJA 2: FSFO status / Section 2: FSFO status
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 2 / SECTION 2: FSFO status
PROMPT --------------------------------------------------------------------------------

SELECT * FROM (
    SELECT 1 AS ord, 'FS Failover Status'           AS metryka, fs_failover_status             AS wartosc,
           CASE WHEN fs_failover_status = 'SYNCHRONIZED' THEN 'PASS'
                WHEN fs_failover_status LIKE '%NOT SYNCHRONIZED%' THEN 'CRIT'
                ELSE 'WARN' END AS ocena FROM v$database
    UNION ALL SELECT 2, 'FS Failover Target',    fs_failover_current_target,         'INFO' FROM v$database
    UNION ALL SELECT 3, 'FSFO Threshold (s)',    TO_CHAR(fs_failover_threshold),     'INFO' FROM v$database
    UNION ALL SELECT 4, 'Observer Present',      fs_failover_observer_present,
           CASE WHEN fs_failover_observer_present = 'YES' THEN 'PASS' ELSE 'CRIT' END FROM v$database
    UNION ALL SELECT 5, 'Observer Host',         fs_failover_observer_host,          'INFO' FROM v$database
)
ORDER BY ord;

-- FSFO historyczne statystyki
COLUMN last_failover_time   FORMAT A20 HEADING "Ostatni failover"
COLUMN last_failover_target FORMAT A15 HEADING "Target"
COLUMN last_observer_host   FORMAT A25 HEADING "Observer host"

PROMPT
PROMPT Ostatni failover (v$fs_failover_stats):
SELECT
    TO_CHAR(last_failover_time, 'YYYY-MM-DD HH24:MI:SS') AS last_failover_time,
    last_failover_target,
    last_observer_host
FROM   v$fs_failover_stats;

-- ============================================================================
-- SEKCJA 3: Gap analysis / Section 3: Archive log gap analysis
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 3 / SECTION 3: Gap analysis
PROMPT --------------------------------------------------------------------------------

COLUMN thread#     FORMAT 9999  HEADING "Watek"
COLUMN low_sequence# FORMAT 9999999 HEADING "Od seq"
COLUMN high_sequence# FORMAT 9999999 HEADING "Do seq"
COLUMN gap_size    FORMAT 999 HEADING "Gap"
COLUMN status      FORMAT A10 HEADING "Status"

SELECT
    thread#,
    low_sequence#,
    high_sequence#,
    (high_sequence# - low_sequence# + 1) AS gap_size,
    CASE
        WHEN high_sequence# - low_sequence# + 1 = 0 THEN 'NO GAP'
        WHEN high_sequence# - low_sequence# + 1 < 5 THEN 'SMALL'
        ELSE 'LARGE'
    END AS status
FROM   v$archive_gap
ORDER  BY thread#;

-- Jesli brak rekordow = brak gap'u (OK)

-- ============================================================================
-- SEKCJA 4: Apply & transport lag / Section 4: Lag metrics
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 4 / SECTION 4: Apply & Transport lag
PROMPT --------------------------------------------------------------------------------

COLUMN name          FORMAT A30 HEADING "Metryka"
COLUMN value         FORMAT A20 HEADING "Wartosc"
COLUMN unit          FORMAT A20 HEADING "Jednostka"
COLUMN time_computed FORMAT A20 HEADING "Czas pomiaru"

SELECT
    name,
    value,
    unit,
    TO_CHAR(time_computed, 'YYYY-MM-DD HH24:MI:SS') AS time_computed
FROM   v$dataguard_stats
WHERE  name IN ('apply lag', 'transport lag', 'apply finish time', 'estimated startup time')
ORDER  BY name;

-- Parse lag to seconds + alert thresholds
COLUMN typ_lag        FORMAT A20 HEADING "Typ"
COLUMN lag_wartosc    FORMAT A20 HEADING "Wartosc"
COLUMN lag_ocena      FORMAT A10 HEADING "Ocena"
COLUMN uzasadnienie   FORMAT A55 HEADING "Uzasadnienie"

PROMPT
PROMPT Lag interpretation (progi z DESIGN.md sek. 7.3):
WITH lag_parsed AS (
    SELECT name,
           value,
           EXTRACT(DAY FROM TO_DSINTERVAL(value)) * 86400 +
           EXTRACT(HOUR FROM TO_DSINTERVAL(value)) * 3600 +
           EXTRACT(MINUTE FROM TO_DSINTERVAL(value)) * 60 +
           EXTRACT(SECOND FROM TO_DSINTERVAL(value)) AS sekundy
    FROM v$dataguard_stats
    WHERE name IN ('apply lag', 'transport lag')
      AND value IS NOT NULL
)
SELECT
    name AS typ_lag,
    value AS lag_wartosc,
    CASE
        WHEN name = 'apply lag' AND sekundy < 5 THEN 'PASS'
        WHEN name = 'apply lag' AND sekundy < 30 THEN 'WARN'
        WHEN name = 'apply lag' THEN 'CRIT'
        WHEN name = 'transport lag' AND sekundy < 2 THEN 'PASS'
        WHEN name = 'transport lag' AND sekundy < 5 THEN 'WARN'
        WHEN name = 'transport lag' THEN 'CRIT'
        ELSE 'INFO'
    END AS lag_ocena,
    CASE
        WHEN name = 'apply lag' AND sekundy >= 30 THEN 'FSFO NIE zadziala (LagLimit exceeded)'
        WHEN name = 'apply lag' AND sekundy >= 5 THEN 'Normalny ruch, ale monitoring'
        WHEN name = 'transport lag' AND sekundy >= 5 THEN 'Sprawdz siec DC-DR'
        ELSE 'OK'
    END AS uzasadnienie
FROM lag_parsed
ORDER BY name;

-- ============================================================================
-- SEKCJA 5: SRL health / Section 5: Standby Redo Log health
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 5 / SECTION 5: SRL health
PROMPT --------------------------------------------------------------------------------

COLUMN thread#  FORMAT 9999 HEADING "Watek"
COLUMN group#   FORMAT 9999 HEADING "Grupa"
COLUMN sequence# FORMAT 99999999 HEADING "Sekwencja"
COLUMN bytes_mb FORMAT 99999 HEADING "Rozmiar MB"
COLUMN used_mb  FORMAT 99999 HEADING "Uzyte MB"
COLUMN status   FORMAT A15 HEADING "Status"

SELECT
    thread#,
    group#,
    sequence#,
    ROUND(bytes/1024/1024, 0)   AS bytes_mb,
    ROUND(used/1024/1024, 0)    AS used_mb,
    status
FROM   v$standby_log
ORDER  BY thread#, group#;

-- ============================================================================
-- SEKCJA 6: FSFO properties (aktualne) / Section 6: Current FSFO properties
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 6 / SECTION 6: FSFO properties (broker config)
PROMPT --------------------------------------------------------------------------------

COLUMN property_name  FORMAT A35 HEADING "Property"
COLUMN property_value FORMAT A30 HEADING "Value"
COLUMN condition      FORMAT A15 HEADING "Condition"
COLUMN ocena_prop     FORMAT A8  HEADING "Ocena"

SELECT
    property_name,
    property_value,
    condition,
    CASE
        WHEN property_name = 'FastStartFailoverThreshold' AND property_value = '30' THEN 'PASS'
        WHEN property_name = 'FastStartFailoverLagLimit' AND property_value = '30' THEN 'PASS'
        WHEN property_name = 'FastStartFailoverAutoReinstate' AND UPPER(property_value) = 'TRUE' THEN 'PASS'
        WHEN property_name = 'ObserverOverride' AND UPPER(property_value) = 'TRUE' THEN 'PASS'
        WHEN property_name = 'ObserverReconnect' AND property_value = '10' THEN 'PASS'
        ELSE 'WARN'
    END AS ocena_prop
FROM   dba_dg_broker_config_properties
WHERE  property_name IN (
    'FastStartFailoverThreshold',
    'FastStartFailoverLagLimit',
    'FastStartFailoverAutoReinstate',
    'ObserverOverride',
    'ObserverReconnect',
    'FastStartFailoverTarget',
    'ProtectionMode'
)
ORDER  BY property_name;

-- ============================================================================
-- SEKCJA 7: TAC monitoring (GV$REPLAY_CONTEXT) — 26ai variant
-- Section 7: TAC stats from per-context views (replaces removed GV$REPLAY_STAT_SUMMARY)
-- ============================================================================
-- W 26ai GV$REPLAY_STAT_SUMMARY zostal usuniety. Zastapiony per-context views:
--   GV$REPLAY_CONTEXT, GV$REPLAY_CONTEXT_LOB, GV$REPLAY_CONTEXT_SEQUENCE,
--   GV$REPLAY_CONTEXT_SYSDATE, GV$REPLAY_CONTEXT_SYSGUID, GV$REPLAY_CONTEXT_SYSTIMESTAMP
-- Tutaj agregujemy per-instance po SUM(*_VALUES_CAPTURED/REPLAYED) z GV$REPLAY_CONTEXT.
-- Status logic:
--   IDLE = no replay contexts (fresh service, no traffic)
--   PASS = wszystkie *_REPLAYED >= *_CAPTURED (success rate 100% per category)
--   WARN = jakas kategoria ma *_REPLAYED < *_CAPTURED (partial replay)

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 7 / SECTION 7: TAC replay statistics (GV$REPLAY_CONTEXT — 26ai)
PROMPT --------------------------------------------------------------------------------

COLUMN inst_id              FORMAT 999      HEADING "Inst"
COLUMN active_contexts      FORMAT 99999    HEADING "Ctx"
COLUMN seq_capt             FORMAT 99999999 HEADING "Seq capt"
COLUMN seq_repl             FORMAT 99999999 HEADING "Seq repl"
COLUMN sd_capt              FORMAT 99999999 HEADING "SysDate capt"
COLUMN sd_repl              FORMAT 99999999 HEADING "SysDate repl"
COLUMN sg_capt              FORMAT 99999999 HEADING "SysGUID capt"
COLUMN sg_repl              FORMAT 99999999 HEADING "SysGUID repl"
COLUMN lobs_capt            FORMAT 99999999 HEADING "LOBs capt"
COLUMN lobs_repl            FORMAT 99999999 HEADING "LOBs repl"
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
SELECT inst_id,
       active_contexts,
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

PROMPT
PROMPT (Jesli 0 wierszy = brak aktywnych replay contexts. Idealne dla swiezo
PROMPT  utworzonego service - po failoverach/replayach beda widoczne wpisy.)

-- TAC services configuration
COLUMN service_name    FORMAT A25 HEADING "Service"
COLUMN failover_type   FORMAT A15 HEADING "Failover type"
COLUMN commit_outcome  FORMAT A6  HEADING "Commit"
COLUMN session_state_consistency FORMAT A10 HEADING "Session"
COLUMN aq_ha_notifications FORMAT A5 HEADING "FAN"

PROMPT
PROMPT TAC services configuration (dba_services):
SELECT
    name              AS service_name,
    failover_type,
    commit_outcome,
    session_state_consistency,
    aq_ha_notifications
FROM   dba_services
WHERE  name NOT LIKE 'SYS%'
  AND  name NOT LIKE '%XDB%'
ORDER  BY name;

-- ============================================================================
-- SEKCJA 8: 26ai-specific Broker views (FSFO config + history + lag distribution)
-- Section 8: 26ai-only views — single-row FSFO config, broker properties,
--            role change audit, failover lag histogram
-- ============================================================================
-- Te 4 widoki wprowadzono w 23ai/26ai. Uzupelniaja diagnostyke z sekcji 1-7:
--   V$FAST_START_FAILOVER_CONFIG — jednowierszowy snapshot konfig FSFO + status
--   V$DG_BROKER_PROPERTY         — szczegolowe broker properties (per DB + scope)
--   V$DG_BROKER_ROLE_CHANGE      — audit ostatnich 10 zmian roli (zastepuje
--                                  parsowanie alert.log dla switchover/failover)
--   V$FS_LAG_HISTOGRAM           — rozklad lag failover w czasie (SLA analysis)
-- Wymaga Oracle 23ai/26ai (w 19c tych view'ow nie ma). Kolumny zweryfikowane
-- wg Oracle Database Reference 23ai (refrn/V-*.html).

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 8 / SECTION 8: 26ai Broker views (FSFO config + role changes + lag hist)
PROMPT --------------------------------------------------------------------------------

-- 8.1: V$FAST_START_FAILOVER_CONFIG — jednowierszowy konfig+status FSFO (26ai)
COLUMN metryka_fsfo  FORMAT A28 HEADING "Metryka / Metric"
COLUMN wartosc_fsfo  FORMAT A45 HEADING "Wartosc / Value"
COLUMN ocena_fsfo    FORMAT A6  HEADING "Ocena"

PROMPT
PROMPT 8.1 FSFO config snapshot (v$fast_start_failover_config):
SELECT * FROM (
    SELECT 1 AS ord, 'FSFO Mode'             AS metryka_fsfo, fast_start_failover_mode AS wartosc_fsfo,
           CASE WHEN fast_start_failover_mode = 'ZERO DATA LOSS' THEN 'PASS'
                WHEN fast_start_failover_mode = 'DISABLED'       THEN 'CRIT'
                ELSE 'INFO' END AS ocena_fsfo FROM v$fast_start_failover_config
    UNION ALL SELECT 2, 'FSFO Status', status,
           CASE WHEN status = 'SYNCHRONIZED' THEN 'PASS'
                WHEN status IN ('UNSYNCHRONIZED','TARGET OVER LAG LIMIT','STALLED','REINSTATE FAILED') THEN 'CRIT'
                ELSE 'WARN' END FROM v$fast_start_failover_config
    UNION ALL SELECT 3, 'Current Target',     current_target,                       'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 4, 'Protection Mode',    protection_mode,
           CASE WHEN protection_mode = 'MAXAVAILABILITY' THEN 'PASS' ELSE 'WARN' END FROM v$fast_start_failover_config
    UNION ALL SELECT 5, 'Observer Present',   observer_present,
           CASE WHEN observer_present = 'YES' THEN 'PASS' ELSE 'CRIT' END           FROM v$fast_start_failover_config
    UNION ALL SELECT 6, 'Observer Host',      observer_host,                        'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 7, 'Threshold (s)',      TO_CHAR(threshold),                   'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 8, 'Lag Limit (s)',      TO_CHAR(lag_limit),                   'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 9, 'Lag Type',           lag_type,                             'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 10,'Lag Grace Time (s)', TO_CHAR(lag_grace_time),              'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 11,'Auto Reinstate',     auto_reinstate,
           CASE WHEN UPPER(auto_reinstate) = 'TRUE' THEN 'PASS' ELSE 'WARN' END     FROM v$fast_start_failover_config
    UNION ALL SELECT 12,'Observer Override',  observer_override,                    'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 13,'Observer Reconnect (s)', TO_CHAR(observer_reconnect),      'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 14,'Ping Interval (ms)', TO_CHAR(ping_interval),               'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 15,'Ping Retry',         TO_CHAR(ping_retry),                  'INFO' FROM v$fast_start_failover_config
    UNION ALL SELECT 16,'Shutdown Primary',   shutdown_primary,                     'INFO' FROM v$fast_start_failover_config
)
ORDER BY ord;

-- 8.2: V$DG_BROKER_PROPERTY — broker properties z kontekstem MEMBER/SCOPE (26ai)
COLUMN member_dg     FORMAT A18 HEADING "Member"
COLUMN dg_role       FORMAT A15 HEADING "Rola"
COLUMN property_dg   FORMAT A32 HEADING "Property"
COLUMN value_dg      FORMAT A22 HEADING "Value"
COLUMN scope_dg      FORMAT A14 HEADING "Scope"

PROMPT
PROMPT 8.2 Broker properties (v$dg_broker_property) - filter na kluczowe FSFO/lag:
SELECT
    member          AS member_dg,
    dataguard_role  AS dg_role,
    property        AS property_dg,
    value           AS value_dg,
    scope           AS scope_dg
FROM   v$dg_broker_property
WHERE  property IN (
    'FastStartFailoverThreshold',
    'FastStartFailoverLagLimit',
    'FastStartFailoverAutoReinstate',
    'FastStartFailoverTarget',
    'FastStartFailoverPmyShutdown',
    'FastStartFailoverLagType',
    'FastStartFailoverLagGraceTime',
    'ObserverOverride',
    'ObserverReconnect',
    'ObserverPingInterval',
    'ObserverPingRetry',
    'TransportLagThreshold',
    'ApplyLagThreshold'
)
ORDER  BY member, property;

-- 8.3: V$DG_BROKER_ROLE_CHANGE — ostatnie 10 zmian roli (audit, zastepuje alert.log)
COLUMN begin_time_str   FORMAT A20 HEADING "Begin time"
COLUMN end_time_str     FORMAT A20 HEADING "End time"
COLUMN event_typ        FORMAT A20 HEADING "Event"
COLUMN old_primary_db   FORMAT A18 HEADING "Old primary"
COLUMN new_primary_db   FORMAT A18 HEADING "New primary"
COLUMN ocena_change     FORMAT A6  HEADING "Ocena"

PROMPT
PROMPT 8.3 Ostatnie 10 zmian roli (v$dg_broker_role_change):
SELECT * FROM (
    SELECT
        TO_CHAR(begin_time, 'YYYY-MM-DD HH24:MI:SS') AS begin_time_str,
        TO_CHAR(end_time,   'YYYY-MM-DD HH24:MI:SS') AS end_time_str,
        event                                        AS event_typ,
        old_primary                                  AS old_primary_db,
        new_primary                                  AS new_primary_db,
        CASE
            WHEN event = 'Switchover'           THEN 'PASS'
            WHEN event = 'Fast-Start Failover'  THEN 'INFO'
            WHEN event = 'Failover'             THEN 'WARN'
            WHEN event = 'Immediate Failover'   THEN 'WARN'
            ELSE 'INFO'
        END AS ocena_change
    FROM   v$dg_broker_role_change
    ORDER  BY begin_time DESC
)
WHERE ROWNUM <= 10;

PROMPT
PROMPT (Jesli 0 wierszy = baza nigdy nie zmieniala roli przez Brokera.
PROMPT  'Switchover' i 'Fast-Start Failover' = OK; 'Failover'/'Immediate Failover'
PROMPT  wymagaja review w docs/FAILOVER-WALKTHROUGH.md.)

-- 8.4: V$FS_LAG_HISTOGRAM — rozklad lag failover w czasie (SLA analysis, 26ai)
COLUMN thread_no     FORMAT 9999     HEADING "Watek"
COLUMN lag_typ       FORMAT A10      HEADING "Typ lag"
COLUMN lag_bucket    FORMAT 99999    HEADING "Bucket s"
COLUMN lag_cnt       FORMAT 99999999 HEADING "Liczba probek"
COLUMN last_upd      FORMAT A20      HEADING "Ostatni update"

PROMPT
PROMPT 8.4 Failover lag histogram (v$fs_lag_histogram) - tylko aktywne buckety:
SELECT
    thread#          AS thread_no,
    lag_type         AS lag_typ,
    lag_time         AS lag_bucket,
    lag_count        AS lag_cnt,
    last_update_time AS last_upd
FROM   v$fs_lag_histogram
WHERE  lag_count > 0
ORDER  BY thread#, lag_type, lag_time;

PROMPT
PROMPT (Brak wierszy = brak zarejestrowanych lag samples. Bucket LAG_TIME = upper bound
PROMPT  w sekundach; LAG_COUNT = ile razy lag wpadl w ten bucket. Sprawdz docs/FSFO-GUIDE.md
PROMPT  sekcja 9 dla interpretacji SLA.)

PROMPT
PROMPT ================================================================================
PROMPT  Monitor report complete (26ai variant).
PROMPT
PROMPT  Alerty krytyczne (jesli wystapily):
PROMPT    - Section 2: Observer Present = NO
PROMPT    - Section 4: apply lag >= 30s
PROMPT    - Section 7: ocena_tac = WARN (partial replay) lub *_capt > 0 a *_repl = 0
PROMPT    - Section 8.1: FSFO Status = UNSYNCHRONIZED / TARGET OVER LAG LIMIT / STALLED
PROMPT    - Section 8.1: Observer Present = NO (dubluje 2, ale z konfig perspective)
PROMPT    - Section 8.3: ostatni Event = 'Failover'/'Immediate Failover' (review przyczyne)
PROMPT
PROMPT  Pelne zliczenie failed replays w 26ai - przez alert log:
PROMPT    SELECT * FROM gv$diag_alert_ext
PROMPT     WHERE message_text LIKE '%REPLAY%FAIL%' OR message_text LIKE '%LTXID%'
PROMPT     AND originating_timestamp > SYSDATE - 1;
PROMPT ================================================================================
