-- ==============================================================================
-- Tytul:        validate_environment_26ai.sql
-- Opis:         Polaczona walidacja FSFO + TAC (12 sprawdzen) — 26ai CDB-aware variant.
--               Patch sekcje TAC (#9, 10, 11, 12): zamiana `dba_services` na
--               `cdb_services` z filtrem `con_id > 1` (PDB-level services).
--               Reszta skryptu (sekcje 1-8 FSFO + summary) bit-identyczna
--               z validate_environment.sql.
-- Description [EN]: 26ai-specific variant. TAC checks (#9-12) patched to use
--               cdb_services WHERE con_id > 1 (PDB-level scope) instead of
--               dba_services (CDB$ROOT-only scope). FSFO checks (#1-8) unchanged.
--
-- Autor:        KCB Kris
-- Data:         2026-04-27
-- Wersja:       1.0
--
-- Zmiany v1.0 (FIX-092):
--   - Bazuje na validate_environment.sql v1.0 (2026-04-23).
--   - DLACZEGO _26ai variant (CDB-aware): w 23ai/26ai TAC services (`MYAPP_TAC`)
--     sa zawsze PDB-level — zaklada sie ze CDB$ROOT nie hostuje TAC bezposrednio,
--     tylko PDB-y (np. `APPPDB`). `dba_services` w CDB$ROOT pokazuje tylko CDB-level
--     services -> 4 TAC checks daja 0 service(s) mimo ze MYAPP_TAC istnieje w PDB.
--   - Naprawa: `cdb_services WHERE con_id > 1` (PDB-only). `cdb_services` widzi
--     services we wszystkich containers; con_id=1 to CDB$ROOT, con_id>1 = PDB.
--   - Plus dodajemy do summary noticebox o ktorej PDB pokazuje TAC services.
--
-- Wymagania [PL]:    - Oracle 23ai/26ai EE w architekturze CDB-multitenant
--                    - Rola SELECT_CATALOG_ROLE (minimum)
--                    - Skrypt uruchamiany z CDB$ROOT (sysdba) — `cdb_services`
--                      wymaga widocznosci wszystkich containerow
-- Requirements [EN]: - Oracle 23ai/26ai EE in CDB-multitenant architecture
--                    - SELECT_CATALOG_ROLE
--                    - Run from CDB$ROOT (sysdba) — cdb_services needs all containers
--
-- Uzycie [PL]:       sqlplus -s / as sysdba @sql/validate_environment_26ai.sql
-- Usage [EN]:        sqlplus -s / as sysdba @sql/validate_environment_26ai.sql
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    FSFO + TAC Environment Validation (12 checks) — 26ai CDB-aware variant
PROMPT    TAC checks (#9-12) scope: cdb_services WHERE con_id > 1 (PDB-level)
PROMPT ================================================================================
PROMPT

COLUMN numer     FORMAT 99    HEADING "#"
COLUMN kategoria FORMAT A10   HEADING "Category"
COLUMN nazwa_check FORMAT A50 HEADING "Check name"
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
    -- CHECK 9: TAC service(s) with failover_type=TRANSACTION (CDB-aware: PDB-level)
    SELECT
        9, 'TAC', 'TAC service (failover_type=TRANSACTION) [PDB]',
        TO_CHAR((SELECT COUNT(*) FROM cdb_services
                WHERE failover_type = 'TRANSACTION' AND con_id > 1)) || ' service(s) in PDBs',
        '>= 1',
        CASE WHEN (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type = 'TRANSACTION' AND con_id > 1) >= 1
             THEN 'PASS' ELSE 'WARN' END
    FROM dual

    UNION ALL
    -- CHECK 10: commit_outcome=YES na TAC service (PDB-level)
    --   UWAGA: kolumna `commit_outcome` w cdb_services to VARCHAR2 z wartosciami
    --   YES/NO (nie TRUE/FALSE). srvctl pokazuje "Commit Outcome: TRUE" (boolean)
    --   ale dictionary view zwraca YES/NO. FIX-093 vs original validate_environment.sql.
    SELECT
        10, 'TAC', 'commit_outcome=YES on TAC service(s) [PDB]',
        TO_CHAR((SELECT COUNT(*) FROM cdb_services
                WHERE failover_type = 'TRANSACTION' AND commit_outcome = 'YES' AND con_id > 1)) || ' of ' ||
        TO_CHAR((SELECT COUNT(*) FROM cdb_services
                WHERE failover_type = 'TRANSACTION' AND con_id > 1)) || ' TAC services',
        'all TAC services',
        CASE
            WHEN (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND con_id > 1) = 0 THEN 'N/A'
            WHEN (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND commit_outcome='YES' AND con_id > 1) =
                 (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND con_id > 1)
                THEN 'PASS'
            ELSE 'FAIL'
        END
    FROM dual

    UNION ALL
    -- CHECK 11: FAN (aq_ha_notifications) enabled (PDB-level)
    SELECT
        11, 'TAC', 'FAN enabled on TAC service(s) [PDB]',
        TO_CHAR((SELECT COUNT(*) FROM cdb_services
                WHERE failover_type='TRANSACTION' AND aq_ha_notifications='YES' AND con_id > 1)) || ' service(s)',
        'all TAC services',
        CASE
            WHEN (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND con_id > 1) = 0 THEN 'N/A'
            WHEN (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND aq_ha_notifications='YES' AND con_id > 1) =
                 (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND con_id > 1)
                THEN 'PASS'
            ELSE 'WARN'
        END
    FROM dual

    UNION ALL
    -- CHECK 12: session_state_consistency=DYNAMIC (PDB-level)
    SELECT
        12, 'TAC', 'session_state_consistency=DYNAMIC [PDB]',
        TO_CHAR((SELECT COUNT(*) FROM cdb_services
                WHERE failover_type='TRANSACTION'
                  AND session_state_consistency='DYNAMIC' AND con_id > 1)) || ' service(s)',
        'all TAC services',
        CASE
            WHEN (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND con_id > 1) = 0 THEN 'N/A'
            WHEN (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND session_state_consistency='DYNAMIC' AND con_id > 1) =
                 (SELECT COUNT(*) FROM cdb_services
                  WHERE failover_type='TRANSACTION' AND con_id > 1)
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
-- TAC services breakdown per PDB / Section: TAC services per container
-- ============================================================================

PROMPT
PROMPT ================================================================================
PROMPT   TAC services per PDB / per container (cdb_services WHERE con_id > 1)
PROMPT ================================================================================

COLUMN pdb_name       FORMAT A20  HEADING "PDB"
COLUMN service_name   FORMAT A30  HEADING "Service"
COLUMN failover_type  FORMAT A12  HEADING "Failover"
COLUMN commit_outcome FORMAT A6   HEADING "Commit"
COLUMN ssc            FORMAT A10  HEADING "SessionSt"
COLUMN fan            FORMAT A4   HEADING "FAN"

SELECT
    (SELECT name FROM v$containers c WHERE c.con_id = s.con_id) AS pdb_name,
    s.name                       AS service_name,
    s.failover_type,
    s.commit_outcome,
    s.session_state_consistency  AS ssc,
    s.aq_ha_notifications        AS fan
FROM   cdb_services s
WHERE  s.failover_type IS NOT NULL
   OR  s.commit_outcome = 'YES'
   OR  s.session_state_consistency IS NOT NULL
ORDER  BY s.con_id, s.name;

PROMPT
PROMPT (Jesli 0 wierszy = brak skonfigurowanych TAC services w zadnym PDB.
PROMPT  Po doc 12 (deploy_tac_service.sh) powinno byc widac MYAPP_TAC w APPPDB
PROMPT  z failover_type=TRANSACTION, commit_outcome=YES, ssc=DYNAMIC, FAN=YES.
PROMPT  UWAGA: srvctl pokazuje 'Commit Outcome: TRUE' ale dictionary view zwraca YES/NO.)

-- ============================================================================
-- Podsumowanie / Summary — zliczanie wszystkich 12 checkow
-- Summary — counting all 12 checks (PASS / WARN / FAIL / N/A)
-- ============================================================================

PROMPT
PROMPT ================================================================================
PROMPT   Podsumowanie / Summary
PROMPT ================================================================================

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
    UNION ALL SELECT CASE WHEN (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type = 'TRANSACTION' AND con_id > 1) >= 1
                          THEN 'PASS' ELSE 'WARN' END FROM dual                                                  -- CHECK 9
    UNION ALL SELECT CASE
                          WHEN (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND con_id > 1) = 0 THEN 'N/A'
                          WHEN (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND commit_outcome='YES' AND con_id > 1) =
                               (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND con_id > 1)
                            THEN 'PASS'
                          ELSE 'FAIL' END FROM dual                                                              -- CHECK 10
    UNION ALL SELECT CASE
                          WHEN (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND con_id > 1) = 0 THEN 'N/A'
                          WHEN (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND aq_ha_notifications='YES' AND con_id > 1) =
                               (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND con_id > 1)
                            THEN 'PASS'
                          ELSE 'WARN' END FROM dual                                                              -- CHECK 11
    UNION ALL SELECT CASE
                          WHEN (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND con_id > 1) = 0 THEN 'N/A'
                          WHEN (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND session_state_consistency='DYNAMIC' AND con_id > 1) =
                               (SELECT COUNT(*) FROM cdb_services
                                WHERE failover_type='TRANSACTION' AND con_id > 1)
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
PROMPT Zakres TAC checks: cdb_services WHERE con_id > 1 (PDB-level). CDB$ROOT services (con_id=1) ignorowane.
PROMPT

PROMPT
PROMPT ================================================================================
PROMPT  Validation complete (26ai CDB-aware variant). Plik raportu: reports/{DB}_validation.txt
PROMPT ================================================================================
