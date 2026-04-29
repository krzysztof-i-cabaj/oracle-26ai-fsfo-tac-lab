-- ==============================================================================
-- Tytul:        validate_environment.sql
-- Opis:         Polaczona walidacja FSFO + TAC (12 sprawdzen).
--               Kazde sprawdzenie zwraca PASS/WARN/FAIL + uzasadnienie.
-- Description [EN]: Combined FSFO + TAC validation (12 checks).
--                   Each check returns PASS/WARN/FAIL + reason.
--
-- Autor:        KCB Kris
-- Data:         2026-04-23
-- Wersja:       1.0
--
-- Wymagania [PL]:    - Oracle 19c+ EE
--                    - Rola SELECT_CATALOG_ROLE (minimum)
-- Requirements [EN]: - Oracle 19c+ EE
--                    - SELECT_CATALOG_ROLE (minimum)
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -f sql/validate_environment.sql -o reports/PRIM_validation.txt
-- Usage [EN]:        sqlconn.sh -s PRIM -f sql/validate_environment.sql -o reports/PRIM_validation.txt
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    FSFO + TAC Environment Validation (12 checks)
PROMPT ================================================================================
PROMPT

COLUMN numer     FORMAT 99    HEADING "#"
COLUMN kategoria FORMAT A10   HEADING "Category"
COLUMN nazwa_check FORMAT A40 HEADING "Check name"
COLUMN wartosc   FORMAT A30   HEADING "Current value"
COLUMN oczekiwane FORMAT A25  HEADING "Expected"
COLUMN status    FORMAT A8    HEADING "Status"

WITH checks AS (
    -- CHECK 1: Oracle version >= 19c
    SELECT
        1 AS numer,
        'FSFO'    AS kategoria,
        'Oracle version >= 19c'        AS nazwa_check,
        (SELECT SUBSTR(banner_full, 1, 30) FROM v$version WHERE banner_full LIKE '%Database%') AS wartosc,
        '19c, 21c, 23ai, 26ai'         AS oczekiwane,
        CASE
            WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%19.%' THEN 'PASS'
            WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%21.%' THEN 'PASS'
            WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%23.%' THEN 'PASS'
            WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%26.%' THEN 'PASS'
            ELSE 'FAIL'
        END AS status
    FROM dual

    UNION ALL
    -- CHECK 2: Enterprise Edition
    SELECT
        2, 'FSFO', 'Enterprise Edition',
        (SELECT banner FROM v$version WHERE banner LIKE '%Edition%'),
        'Enterprise Edition',
        CASE
            WHEN (SELECT COUNT(*) FROM v$version WHERE banner LIKE '%Enterprise%') > 0
            THEN 'PASS' ELSE 'FAIL'
        END
    FROM dual

    UNION ALL
    -- CHECK 3: ARCHIVELOG mode
    SELECT
        3, 'FSFO', 'ARCHIVELOG mode',
        (SELECT log_mode FROM v$database),
        'ARCHIVELOG',
        CASE WHEN (SELECT log_mode FROM v$database) = 'ARCHIVELOG' THEN 'PASS' ELSE 'FAIL' END
    FROM dual

    UNION ALL
    -- CHECK 4: FORCE LOGGING
    SELECT
        4, 'FSFO', 'Force logging enabled',
        (SELECT force_logging FROM v$database),
        'YES',
        CASE WHEN (SELECT force_logging FROM v$database) = 'YES' THEN 'PASS' ELSE 'FAIL' END
    FROM dual

    UNION ALL
    -- CHECK 5: FLASHBACK ON (dla AutoReinstate)
    SELECT
        5, 'FSFO', 'Flashback Database enabled',
        (SELECT flashback_on FROM v$database),
        'YES (dla AutoReinstate)',
        CASE WHEN (SELECT flashback_on FROM v$database) = 'YES' THEN 'PASS' ELSE 'FAIL' END
    FROM dual

    UNION ALL
    -- CHECK 6: DG Broker started
    SELECT
        6, 'FSFO', 'DG Broker running',
        (SELECT value FROM v$parameter WHERE name = 'dg_broker_start'),
        'TRUE',
        CASE WHEN UPPER((SELECT value FROM v$parameter WHERE name='dg_broker_start')) = 'TRUE'
             THEN 'PASS' ELSE 'FAIL' END
    FROM dual

    UNION ALL
    -- CHECK 7: Standby Redo Logs present
    SELECT
        7, 'FSFO', 'Standby Redo Logs (SRL) present',
        TO_CHAR((SELECT COUNT(*) FROM v$standby_log)) || ' groups',
        '> 0 (ideally N+1)',
        CASE WHEN (SELECT COUNT(*) FROM v$standby_log) > 0 THEN 'PASS' ELSE 'FAIL' END
    FROM dual

    UNION ALL
    -- CHECK 8: Protection mode
    SELECT
        8, 'FSFO', 'Protection mode = MAXIMUM AVAILABILITY',
        (SELECT protection_mode FROM v$database),
        'MAXIMUM AVAILABILITY',
        CASE WHEN (SELECT protection_mode FROM v$database) = 'MAXIMUM AVAILABILITY' THEN 'PASS'
             WHEN (SELECT protection_mode FROM v$database) = 'MAXIMUM PROTECTION' THEN 'PASS'
             ELSE 'WARN' END
    FROM dual

    UNION ALL
    -- CHECK 9: TAC service(s) with failover_type=TRANSACTION
    SELECT
        9, 'TAC', 'TAC service (failover_type=TRANSACTION)',
        TO_CHAR((SELECT COUNT(*) FROM dba_services WHERE failover_type = 'TRANSACTION')) || ' service(s)',
        '>= 1',
        CASE WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type = 'TRANSACTION') >= 1
             THEN 'PASS' ELSE 'WARN' END
    FROM dual

    UNION ALL
    -- CHECK 10: commit_outcome=TRUE na TAC service
    SELECT
        10, 'TAC', 'commit_outcome=TRUE on TAC service(s)',
        TO_CHAR((SELECT COUNT(*) FROM dba_services
                WHERE failover_type = 'TRANSACTION'
                  AND commit_outcome = 'TRUE')) || ' of ' ||
        TO_CHAR((SELECT COUNT(*) FROM dba_services
                WHERE failover_type = 'TRANSACTION')) || ' TAC services',
        'all TAC services',
        CASE
            WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION') = 0 THEN 'N/A'
            WHEN (SELECT COUNT(*) FROM dba_services
                  WHERE failover_type='TRANSACTION' AND commit_outcome='TRUE') =
                 (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION')
                THEN 'PASS'
            ELSE 'FAIL'
        END
    FROM dual

    UNION ALL
    -- CHECK 11: FAN (aq_ha_notifications) enabled
    SELECT
        11, 'TAC', 'FAN enabled on TAC service(s)',
        TO_CHAR((SELECT COUNT(*) FROM dba_services
                WHERE failover_type='TRANSACTION' AND aq_ha_notifications='TRUE')) || ' service(s)',
        'all TAC services',
        CASE
            WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION') = 0 THEN 'N/A'
            WHEN (SELECT COUNT(*) FROM dba_services
                  WHERE failover_type='TRANSACTION' AND aq_ha_notifications='TRUE') =
                 (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION')
                THEN 'PASS'
            ELSE 'WARN'
        END
    FROM dual

    UNION ALL
    -- CHECK 12: session_state_consistency=DYNAMIC
    SELECT
        12, 'TAC', 'session_state_consistency=DYNAMIC',
        TO_CHAR((SELECT COUNT(*) FROM dba_services
                WHERE failover_type='TRANSACTION'
                  AND session_state_consistency='DYNAMIC')) || ' service(s)',
        'all TAC services',
        CASE
            WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION') = 0 THEN 'N/A'
            WHEN (SELECT COUNT(*) FROM dba_services
                  WHERE failover_type='TRANSACTION' AND session_state_consistency='DYNAMIC') =
                 (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION')
                THEN 'PASS'
            ELSE 'WARN'
        END
    FROM dual
)
SELECT
    numer,
    kategoria,
    nazwa_check,
    wartosc,
    oczekiwane,
    status
FROM   checks
ORDER  BY numer;

-- ============================================================================
-- Podsumowanie / Summary — zliczanie wszystkich 12 checkow
-- Summary — counting all 12 checks (PASS / WARN / FAIL / N/A)
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  Podsumowanie / Summary
PROMPT --------------------------------------------------------------------------------

COLUMN status_agg   FORMAT A8  HEADING "Status"
COLUMN liczba       FORMAT 999 HEADING "Liczba"
COLUMN pct_z_12     FORMAT A10 HEADING "% z 12"

-- Pelen zestaw 12 checkow (to samo co w glownym SELECT wyzej)
-- Zliczamy PASS / WARN / FAIL / N/A, nie hardkodujemy.
WITH all_checks AS (
    SELECT CASE
             WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%19.%' THEN 'PASS'
             WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%21.%' THEN 'PASS'
             WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%23.%' THEN 'PASS'
             WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%') LIKE '%26.%' THEN 'PASS'
             ELSE 'FAIL'
           END AS status FROM dual                                                                              -- CHECK 1
    UNION ALL SELECT CASE WHEN (SELECT COUNT(*) FROM v$version WHERE banner LIKE '%Enterprise%') > 0
                          THEN 'PASS' ELSE 'FAIL' END FROM dual                                                 -- CHECK 2
    UNION ALL SELECT CASE WHEN (SELECT log_mode FROM v$database) = 'ARCHIVELOG' THEN 'PASS' ELSE 'FAIL' END
                     FROM dual                                                                                   -- CHECK 3
    UNION ALL SELECT CASE WHEN (SELECT force_logging FROM v$database) = 'YES' THEN 'PASS' ELSE 'FAIL' END
                     FROM dual                                                                                   -- CHECK 4
    UNION ALL SELECT CASE WHEN (SELECT flashback_on FROM v$database) = 'YES' THEN 'PASS' ELSE 'FAIL' END
                     FROM dual                                                                                   -- CHECK 5
    UNION ALL SELECT CASE WHEN UPPER((SELECT value FROM v$parameter WHERE name='dg_broker_start')) = 'TRUE'
                          THEN 'PASS' ELSE 'FAIL' END FROM dual                                                 -- CHECK 6
    UNION ALL SELECT CASE WHEN (SELECT COUNT(*) FROM v$standby_log) > 0 THEN 'PASS' ELSE 'FAIL' END FROM dual   -- CHECK 7
    UNION ALL SELECT CASE WHEN (SELECT protection_mode FROM v$database) = 'MAXIMUM AVAILABILITY' THEN 'PASS'
                          WHEN (SELECT protection_mode FROM v$database) = 'MAXIMUM PROTECTION'   THEN 'PASS'
                          ELSE 'WARN' END FROM dual                                                              -- CHECK 8
    UNION ALL SELECT CASE WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type = 'TRANSACTION') >= 1
                          THEN 'PASS' ELSE 'WARN' END FROM dual                                                  -- CHECK 9
    UNION ALL SELECT CASE
                          WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION') = 0 THEN 'N/A'
                          WHEN (SELECT COUNT(*) FROM dba_services
                                WHERE failover_type='TRANSACTION' AND commit_outcome='TRUE') =
                               (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION')
                            THEN 'PASS'
                          ELSE 'FAIL' END FROM dual                                                              -- CHECK 10
    UNION ALL SELECT CASE
                          WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION') = 0 THEN 'N/A'
                          WHEN (SELECT COUNT(*) FROM dba_services
                                WHERE failover_type='TRANSACTION' AND aq_ha_notifications='TRUE') =
                               (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION')
                            THEN 'PASS'
                          ELSE 'WARN' END FROM dual                                                              -- CHECK 11
    UNION ALL SELECT CASE
                          WHEN (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION') = 0 THEN 'N/A'
                          WHEN (SELECT COUNT(*) FROM dba_services
                                WHERE failover_type='TRANSACTION' AND session_state_consistency='DYNAMIC') =
                               (SELECT COUNT(*) FROM dba_services WHERE failover_type='TRANSACTION')
                            THEN 'PASS'
                          ELSE 'WARN' END FROM dual                                                              -- CHECK 12
)
SELECT status                                              AS status_agg,
       COUNT(*)                                            AS liczba,
       TO_CHAR(ROUND(COUNT(*) * 100 / 12, 1), 'FM990.0')
         || '%'                                            AS pct_z_12
FROM   all_checks
GROUP  BY status
ORDER  BY DECODE(status, 'FAIL', 1, 'WARN', 2, 'N/A', 3, 'PASS', 4);

PROMPT
PROMPT Interpretacja:
PROMPT   - PASS  = srodowisko gotowe do wdrozenia FSFO/TAC
PROMPT   - WARN  = dziala, ale zalecana poprawa przed produkcja
PROMPT   - FAIL  = blokuje wdrozenie, musi byc naprawione
PROMPT   - N/A   = nie dotyczy (np. TAC checks na bazie bez services)
PROMPT
PROMPT Minimalne wymaganie dla Go-Live: wszystkie FSFO checks PASS, wszystkie TAC checks PASS lub WARN.

PROMPT
PROMPT ================================================================================
PROMPT  Validation complete. Plik raportu: reports/{DB}_validation.txt
PROMPT ================================================================================
