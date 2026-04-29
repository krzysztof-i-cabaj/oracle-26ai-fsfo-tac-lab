-- ==============================================================================
-- Tytul:        fsfo_monitor.sql
-- Opis:         Ciagly monitoring stanu FSFO i TAC (7 sekcji)
-- Description [EN]: Ongoing health monitoring of FSFO and TAC (7 sections)
--
-- Autor:        KCB Kris
-- Data:         2026-04-23
-- Wersja:       1.0
--
-- Wymagania [PL]:    - Oracle 19c+ EE z wlaczonym DG Broker i FSFO
--                    - Rola SELECT_CATALOG_ROLE
--                    - Sekcja 7 wymaga Diagnostic Pack (ASH/AWR)
-- Requirements [EN]: - Oracle 19c+ EE with DG Broker and FSFO enabled
--                    - SELECT_CATALOG_ROLE
--                    - Section 7 requires Diagnostic Pack (ASH/AWR)
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -f sql/fsfo_monitor.sql -o reports/fsfo_$(date +%Y%m%d_%H%M).txt
-- Usage [EN]:        sqlconn.sh -s PRIM -f sql/fsfo_monitor.sql -o reports/fsfo_$(date +%Y%m%d_%H%M).txt
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    FSFO + TAC Health Monitor
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
-- SEKCJA 7: TAC monitoring (GV$REPLAY_STAT_SUMMARY) / Section 7: TAC stats
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 7 / SECTION 7: TAC replay statistics
PROMPT --------------------------------------------------------------------------------

COLUMN inst_id             FORMAT 999 HEADING "Inst"
COLUMN requests_total      FORMAT 99999999 HEADING "Wszystkie"
COLUMN requests_replayed   FORMAT 99999999 HEADING "Replay OK"
COLUMN requests_failed     FORMAT 99999999 HEADING "Replay Fail"
COLUMN pct_sukcesu         FORMAT 999.9 HEADING "Success %"
COLUMN ocena_tac           FORMAT A10 HEADING "Ocena"

SELECT
    inst_id,
    requests_total,
    requests_replayed,
    requests_failed,
    CASE
        WHEN requests_total > 0
        THEN ROUND(requests_replayed * 100 / requests_total, 1)
        ELSE 0
    END AS pct_sukcesu,
    CASE
        WHEN requests_total = 0 THEN 'IDLE'
        WHEN requests_replayed * 100 / requests_total >= 95 THEN 'PASS'
        WHEN requests_replayed * 100 / requests_total >= 80 THEN 'WARN'
        ELSE 'CRIT'
    END AS ocena_tac
FROM   gv$replay_stat_summary
ORDER  BY inst_id;

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

PROMPT
PROMPT ================================================================================
PROMPT  Monitor report complete.
PROMPT
PROMPT  Alerty krytyczne (jesli wystapily):
PROMPT    - Section 2: Observer Present = NO
PROMPT    - Section 4: apply lag >= 30s
PROMPT    - Section 7: Success % < 80%
PROMPT ================================================================================
