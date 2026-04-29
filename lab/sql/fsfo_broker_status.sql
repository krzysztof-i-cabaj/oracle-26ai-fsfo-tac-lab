-- ==============================================================================
-- Tytul:        fsfo_broker_status.sql
-- Opis:         Status Brokera i FSFO w runtime (5 sekcji)
-- Description [EN]: Broker & FSFO runtime status (5 sections)
--
-- Autor:        KCB Kris
-- Data:         2026-04-23
-- Wersja:       1.0
--
-- Wymagania [PL]:    - Oracle 19c+ EE z wlaczonym DG Broker
--                    - Uprawnienia SELECT_CATALOG_ROLE
-- Requirements [EN]: - Oracle 19c+ EE with DG Broker enabled
--                    - SELECT_CATALOG_ROLE
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -f sql/fsfo_broker_status.sql
-- Usage [EN]:        sqlconn.sh -s PRIM -f sql/fsfo_broker_status.sql
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    Broker & FSFO Runtime Status
PROMPT ================================================================================
PROMPT

-- ============================================================================
-- SEKCJA 1: Rola i status bazy / Section 1: Database role and status
-- ============================================================================

PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 1 / SECTION 1: Rola i stan bazy / Role and state
PROMPT --------------------------------------------------------------------------------

COLUMN metryka     FORMAT A40 HEADING "Metryka / Metric"
COLUMN wartosc     FORMAT A60 HEADING "Wartosc / Value"

SELECT 'DB Unique Name'               AS metryka, db_unique_name                          AS wartosc FROM v$database
UNION ALL SELECT 'Database role',                 database_role                          FROM v$database
UNION ALL SELECT 'Protection mode',               protection_mode                        FROM v$database
UNION ALL SELECT 'Protection level',              protection_level                       FROM v$database
UNION ALL SELECT 'Open mode',                     open_mode                              FROM v$database
UNION ALL SELECT 'Switchover status',             switchover_status                      FROM v$database
UNION ALL SELECT 'FS Failover Status',            fs_failover_status                     FROM v$database
UNION ALL SELECT 'FS Failover Current Target',    fs_failover_current_target             FROM v$database
UNION ALL SELECT 'FS Failover Threshold (s)',     TO_CHAR(fs_failover_threshold)         FROM v$database
UNION ALL SELECT 'FS Failover Observer Present',  fs_failover_observer_present           FROM v$database
UNION ALL SELECT 'FS Failover Observer Host',     fs_failover_observer_host              FROM v$database;

-- ============================================================================
-- SEKCJA 2: Konfiguracja brokera / Section 2: Broker configuration
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 2 / SECTION 2: Konfiguracja Brokera / Broker configuration
PROMPT --------------------------------------------------------------------------------

COLUMN db_unique_name FORMAT A20 HEADING "DB Unique Name"
COLUMN dest_role      FORMAT A15 HEADING "Role"
COLUMN parent_dbun    FORMAT A20 HEADING "Parent DBUN"

SELECT
    db_unique_name,
    dest_role,
    parent_dbun,
    current_scn                AS aktualny_scn
FROM   v$dataguard_config
ORDER  BY db_unique_name;

-- Broker konfiguracje (wszystkie wlasciwosci) - 19c+
COLUMN property_name  FORMAT A35 HEADING "Property"
COLUMN property_value FORMAT A50 HEADING "Value"
COLUMN condition      FORMAT A15 HEADING "Condition"

PROMPT
PROMPT Konfiguracja brokera (DBA_DG_BROKER_CONFIG_PROPERTIES):
SELECT
    property_name,
    property_value,
    condition
FROM   dba_dg_broker_config_properties
WHERE  property_name IN (
    'ProtectionMode',
    'FastStartFailoverThreshold',
    'FastStartFailoverLagLimit',
    'FastStartFailoverAutoReinstate',
    'ObserverOverride',
    'ObserverReconnect',
    'FastStartFailoverTarget'
)
ORDER  BY property_name;

-- ============================================================================
-- SEKCJA 3: Fast-Start Failover / Section 3: FSFO status
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 3 / SECTION 3: FSFO status
PROMPT --------------------------------------------------------------------------------

-- V$FS_FAILOVER_STATS - statystyki historyczne FSFO
COLUMN last_failover_time FORMAT A25 HEADING "Ostatni failover / Last failover"
COLUMN last_failover_target FORMAT A20 HEADING "Target"
COLUMN last_failover_reason FORMAT A40 HEADING "Reason"
COLUMN last_observer_host FORMAT A25 HEADING "Observer host"

SELECT
    TO_CHAR(last_failover_time, 'YYYY-MM-DD HH24:MI:SS') AS last_failover_time,
    NVL(last_failover_target, '-')                       AS last_failover_target,
    NVL(last_failover_reason, '-')                       AS last_failover_reason,
    NVL(last_observer_host, '-')                         AS last_observer_host
FROM   v$fs_failover_stats;

-- ============================================================================
-- SEKCJA 4: Observer status / Section 4: Observer status
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 4 / SECTION 4: Observer (jesli broker uruchomiony / if broker running)
PROMPT --------------------------------------------------------------------------------

-- V$DATAGUARD_STATUS - ostatnie eventy DG (w tym Observer events)
COLUMN message_timestamp FORMAT A20 HEADING "Czas / Timestamp"
COLUMN severity          FORMAT A10 HEADING "Severity"
COLUMN message_num       FORMAT 99999 HEADING "Msg#"
COLUMN message_text      FORMAT A110 HEADING "Message"

PROMPT
PROMPT Ostatnie 20 eventow DG (v$dataguard_status):
SELECT
    TO_CHAR(timestamp, 'YYYY-MM-DD HH24:MI:SS') AS message_timestamp,
    severity,
    message_num,
    message                                      AS message_text
FROM   v$dataguard_status
ORDER  BY timestamp DESC
FETCH  FIRST 20 ROWS ONLY;

-- ============================================================================
-- SEKCJA 5: Lag metrics / Section 5: Lag metrics (transport + apply)
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 5 / SECTION 5: Lag metrics (kluczowe dla FSFO)
PROMPT --------------------------------------------------------------------------------

COLUMN name FORMAT A30 HEADING "Metryka / Metric"
COLUMN value FORMAT A25 HEADING "Wartosc / Value"
COLUMN unit FORMAT A15 HEADING "Jednostka / Unit"
COLUMN time_computed FORMAT A20 HEADING "Czas pomiaru / Computed"

SELECT
    name,
    value,
    unit,
    TO_CHAR(time_computed, 'YYYY-MM-DD HH24:MI:SS') AS time_computed
FROM   v$dataguard_stats
ORDER  BY name;

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  Interpretacja / Interpretation:
PROMPT  - 'apply lag' powinno byc < 30s (FastStartFailoverLagLimit)
PROMPT  - 'transport lag' powinno byc < 5s
PROMPT  - Wartosci '+' lub 'NULL' oznaczaja brak danych (broker niedostepny)
PROMPT --------------------------------------------------------------------------------

PROMPT
PROMPT ================================================================================
PROMPT  Broker status check zakonczony.
PROMPT ================================================================================
