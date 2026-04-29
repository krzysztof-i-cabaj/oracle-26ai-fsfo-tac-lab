-- ==============================================================================
-- Tytul:        fsfo_check_readiness.sql
-- Opis:         Sprawdzenie gotowosci bazy do wdrozenia FSFO (6 sekcji)
-- Description [EN]: Pre-deployment readiness check for FSFO (6 sections)
--
-- Autor:        KCB Kris
-- Data:         2026-04-23
-- Wersja:       1.0
--
-- Wymagania [PL]:    - Oracle 19c+ EE
--                    - Uprawnienia SELECT na V$/DBA_ (rola SELECT_CATALOG_ROLE)
--                    - Uruchomic na PRIM i STBY
-- Requirements [EN]: - Oracle 19c+ EE
--                    - SELECT on V$/DBA_ (SELECT_CATALOG_ROLE)
--                    - Run on both PRIM and STBY
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -f sql/fsfo_check_readiness.sql
-- Usage [EN]:        sqlconn.sh -s PRIM -f sql/fsfo_check_readiness.sql
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    FSFO Readiness Check — Oracle 19c
PROMPT ================================================================================
PROMPT

COLUMN sprawdzenie_pl FORMAT A38 HEADING "Sprawdzenie [PL]"
COLUMN check_en       FORMAT A38 HEADING "Check [EN]"
COLUMN wartosc        FORMAT A22 HEADING "Wartosc / Value"
COLUMN status         FORMAT A8  HEADING "Status"
COLUMN nazwa          FORMAT A30 HEADING "Nazwa / Name"
COLUMN wartosc_long   FORMAT A50 HEADING "Wartosc / Value"

-- ============================================================================
-- SEKCJA 1: Wersja bazy danych / Section 1: Database Version
-- ============================================================================

PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 1 / SECTION 1: Wersja Oracle / Oracle Version
PROMPT --------------------------------------------------------------------------------

SELECT
    'Wersja Oracle / Oracle version'       AS sprawdzenie_pl,
    SUBSTR(banner_full, 1, 22)             AS wartosc,
    CASE
        WHEN banner_full LIKE '%19.%' OR banner_full LIKE '%21.%'
          OR banner_full LIKE '%23.%' OR banner_full LIKE '%26.%'
            THEN 'PASS'
        ELSE 'FAIL'
    END                                    AS status
FROM   v$version
WHERE  banner_full LIKE '%Database%';

SELECT
    'Edycja / Edition'                     AS sprawdzenie_pl,
    (SELECT value FROM v$parameter WHERE name = 'compatible') AS wartosc,
    (SELECT CASE WHEN banner LIKE '%Enterprise%' THEN 'PASS' ELSE 'FAIL' END
     FROM v$version WHERE banner LIKE '%Database%')           AS status
FROM dual;

-- ============================================================================
-- SEKCJA 2: Archivelog, force logging, flashback / Section 2: Basic DG prereqs
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 2 / SECTION 2: Archivelog / Force Logging / Flashback
PROMPT --------------------------------------------------------------------------------

SELECT
    sprawdzenie_pl,
    wartosc,
    status
FROM (
    SELECT
        'ARCHIVELOG mode'                  AS sprawdzenie_pl,
        log_mode                           AS wartosc,
        CASE WHEN log_mode = 'ARCHIVELOG' THEN 'PASS' ELSE 'FAIL' END AS status,
        1 AS ord
    FROM v$database
    UNION ALL
    SELECT
        'FORCE LOGGING',
        force_logging,
        CASE WHEN force_logging = 'YES' THEN 'PASS' ELSE 'FAIL' END,
        2
    FROM v$database
    UNION ALL
    SELECT
        'FLASHBACK ON (dla AutoReinstate)',
        flashback_on,
        CASE WHEN flashback_on = 'YES' THEN 'PASS' ELSE 'FAIL' END,
        3
    FROM v$database
    UNION ALL
    SELECT
        'SUPPLEMENTAL_LOG_DATA_MIN',
        supplemental_log_data_min,
        CASE WHEN supplemental_log_data_min IN ('YES','IMPLICIT') THEN 'PASS' ELSE 'WARN' END,
        4
    FROM v$database
    UNION ALL
    SELECT
        'Database role',
        database_role,
        'INFO',
        5
    FROM v$database
    UNION ALL
    SELECT
        'Protection mode',
        protection_mode,
        'INFO',
        6
    FROM v$database
)
ORDER BY ord;

-- ============================================================================
-- SEKCJA 3: Standby Redo Logs / Section 3: Standby Redo Logs (SRL)
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 3 / SECTION 3: Standby Redo Logs (SRL)
PROMPT --------------------------------------------------------------------------------

-- Wymaganie: SRL = threads × (groups per thread + 1), tego samego rozmiaru co redo
SELECT
    thread#                            AS watek,
    group#                             AS grupa,
    ROUND(bytes/1024/1024, 0)          AS rozmiar_mb,
    status                             AS status_srl
FROM   v$standby_log
ORDER  BY thread#, group#;

SELECT
    'Liczba grup SRL / SRL groups'                AS sprawdzenie_pl,
    TO_CHAR(COUNT(*))                             AS wartosc,
    CASE
        WHEN COUNT(*) = 0 THEN 'FAIL'
        WHEN COUNT(*) < (
            SELECT COUNT(DISTINCT thread#) FROM v$log
        ) * ((SELECT COUNT(*) FROM v$log) /
             NULLIF((SELECT COUNT(DISTINCT thread#) FROM v$log), 0) + 1)
            THEN 'WARN'
        ELSE 'PASS'
    END                                           AS status
FROM v$standby_log;

-- Rozmiar SRL vs rozmiar redo
SELECT
    'Rozmiar redo (online) MB'                    AS sprawdzenie_pl,
    TO_CHAR(MAX(ROUND(bytes/1024/1024, 0)))       AS wartosc,
    'INFO'                                        AS status
FROM v$log
UNION ALL
SELECT
    'Rozmiar SRL MB',
    TO_CHAR(NVL(MAX(ROUND(bytes/1024/1024, 0)), 0)),
    CASE
        WHEN MAX(bytes) IS NULL THEN 'N/A'
        WHEN MAX(bytes) >= (SELECT MAX(bytes) FROM v$log) THEN 'PASS'
        ELSE 'FAIL'
    END
FROM v$standby_log;

-- ============================================================================
-- SEKCJA 3.5: Parametry Data Guard wymagane dla brokera
-- Section 3.5: Data Guard parameters required by broker
-- ============================================================================
-- Bez LOG_ARCHIVE_CONFIG=DG_CONFIG(...) broker nie zestawi transportu
-- (DGM-17016 przy ENABLE CONFIGURATION). Ta sekcja jawnie waliduje.

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 3.5 / SECTION 3.5: Parametry DG (LOG_ARCHIVE_CONFIG, retencja)
PROMPT --------------------------------------------------------------------------------

COLUMN parametr   FORMAT A35 HEADING "Parameter"
COLUMN wartosc    FORMAT A50 HEADING "Current value"
COLUMN status_p   FORMAT A6  HEADING "Status"
COLUMN uwaga      FORMAT A60 HEADING "Uwaga / Note"

SELECT
    'LOG_ARCHIVE_CONFIG'                                       AS parametr,
    NVL(value, '(empty)')                                      AS wartosc,
    CASE
        WHEN value IS NULL                                     THEN 'FAIL'
        WHEN UPPER(value) LIKE '%DG_CONFIG%'                   THEN 'PASS'
        ELSE                                                        'WARN'
    END                                                        AS status_p,
    'Musi zawierac DG_CONFIG=(db1,db2,...) dla brokera'        AS uwaga
FROM v$parameter WHERE name = 'log_archive_config'
UNION ALL
SELECT
    'ARCHIVE_LAG_TARGET (s)',
    value,
    CASE
        WHEN TO_NUMBER(value) = 0                              THEN 'WARN'
        WHEN TO_NUMBER(value) BETWEEN 900 AND 1800             THEN 'PASS'
        ELSE                                                        'WARN'
    END,
    'Zalecane 900-1800s - forced log switch'
FROM v$parameter WHERE name = 'archive_lag_target'
UNION ALL
SELECT
    'DB_FLASHBACK_RETENTION_TARGET (min)',
    value,
    CASE
        WHEN TO_NUMBER(value) >= 1440                          THEN 'PASS'
        WHEN TO_NUMBER(value) >= 60                            THEN 'WARN'
        ELSE                                                        'FAIL'
    END,
    'Min 60 min; zalecane >= 1440 (24h) dla reinstate po failover'
FROM v$parameter WHERE name = 'db_flashback_retention_target'
UNION ALL
SELECT
    'REMOTE_LOGIN_PASSWORDFILE',
    value,
    CASE
        WHEN UPPER(value) IN ('EXCLUSIVE','SHARED')            THEN 'PASS'
        ELSE                                                        'FAIL'
    END,
    'EXCLUSIVE/SHARED wymagane dla SYS z hasla do brokera'
FROM v$parameter WHERE name = 'remote_login_passwordfile'
UNION ALL
SELECT
    'STANDBY_FILE_MANAGEMENT',
    value,
    CASE
        WHEN UPPER(value) = 'AUTO'                             THEN 'PASS'
        ELSE                                                        'FAIL'
    END,
    'AUTO wymagane - inaczej datafiles na standby nie beda tworzone'
FROM v$parameter WHERE name = 'standby_file_management';

-- ============================================================================
-- SEKCJA 4: Broker status / Section 4: Data Guard Broker status
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 4 / SECTION 4: Data Guard Broker
PROMPT --------------------------------------------------------------------------------

SELECT
    name                        AS nazwa,
    value                       AS wartosc_long
FROM   v$parameter
WHERE  name IN (
    'dg_broker_start',
    'dg_broker_config_file1',
    'dg_broker_config_file2',
    'log_archive_config',
    'log_archive_dest_1',
    'log_archive_dest_2',
    'standby_file_management',
    'db_unique_name',
    'db_recovery_file_dest',
    'db_recovery_file_dest_size',
    'remote_listener',
    'local_listener'
)
ORDER  BY name;

-- ============================================================================
-- SEKCJA 5: Broker runtime / Section 5: Broker runtime (if enabled)
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 5 / SECTION 5: Broker runtime (jesli uruchomiony / if enabled)
PROMPT --------------------------------------------------------------------------------

-- V$DATAGUARD_CONFIG - konfiguracja DG
COLUMN db_unique_name FORMAT A20 HEADING "DB Unique Name"
COLUMN parent_dbun    FORMAT A20 HEADING "Parent"
COLUMN dest_role      FORMAT A15 HEADING "Role"
COLUMN connect_ident  FORMAT A30 HEADING "Connect Ident"

SELECT
    db_unique_name,
    parent_dbun,
    dest_role,
    current_scn          AS aktualny_scn
FROM   v$dataguard_config;

-- V$DATAGUARD_STATS - metryki lag
COLUMN name      FORMAT A25 HEADING "Metryka / Metric"
COLUMN value     FORMAT A20 HEADING "Wartosc / Value"
COLUMN unit      FORMAT A15 HEADING "Jednostka / Unit"

PROMPT
PROMPT Data Guard Statistics (lag metrics):
SELECT
    name,
    value,
    unit
FROM   v$dataguard_stats
ORDER  BY name;

-- ============================================================================
-- SEKCJA 6: Ostateczne podsumowanie / Section 6: Overall summary
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 6 / SECTION 6: Podsumowanie / Summary
PROMPT --------------------------------------------------------------------------------

COLUMN grupa_sprawdzen FORMAT A40 HEADING "Grupa sprawdzen / Check group"
COLUMN status_sek      FORMAT A10 HEADING "Status"
COLUMN komentarz       FORMAT A60 HEADING "Komentarz / Note"

WITH readiness AS (
    SELECT
        CASE WHEN log_mode = 'ARCHIVELOG' THEN 1 ELSE 0 END +
        CASE WHEN force_logging = 'YES' THEN 1 ELSE 0 END +
        CASE WHEN flashback_on = 'YES' THEN 1 ELSE 0 END           AS podstawy_ok,
        (SELECT COUNT(*) FROM v$standby_log)                       AS srl_count,
        (SELECT value FROM v$parameter WHERE name = 'dg_broker_start') AS broker_status
    FROM v$database
)
SELECT
    'Podstawy DG (archivelog + force + flashback)' AS grupa_sprawdzen,
    CASE WHEN podstawy_ok = 3 THEN 'PASS'
         WHEN podstawy_ok >= 2 THEN 'WARN'
         ELSE 'FAIL' END                           AS status_sek,
    CASE WHEN podstawy_ok = 3 THEN 'Wszystkie 3 wymagania spelnione'
         ELSE 'Brakuje ' || TO_CHAR(3 - podstawy_ok) || ' z 3 wymagan' END AS komentarz
FROM readiness
UNION ALL
SELECT
    'Standby Redo Logs (SRL)',
    CASE WHEN srl_count > 0 THEN 'PASS' ELSE 'FAIL' END,
    'Liczba grup SRL: ' || TO_CHAR(srl_count) || ' (wymagane dla real-time apply)'
FROM readiness
UNION ALL
SELECT
    'DG Broker',
    CASE WHEN UPPER(broker_status) = 'TRUE' THEN 'PASS' ELSE 'FAIL' END,
    'dg_broker_start=' || broker_status
FROM readiness;

PROMPT
PROMPT ================================================================================
PROMPT  Readiness check zakonczony. Przegladnij wyniki powyzej.
PROMPT  Readiness check complete. Review results above.
PROMPT
PROMPT  Oczekiwane: wszystkie PASS przed przejsciem do Phase 1 (Broker Setup).
PROMPT  Expected:   all PASS before moving to Phase 1 (Broker Setup).
PROMPT ================================================================================
